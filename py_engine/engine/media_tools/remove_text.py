#!/usr/bin/env python3
"""
remove_text.py

Clean text from a folder of ordered image frames on macOS / Apple Silicon.

Pipeline
--------
Apple Vision
    -> detect text
    -> build text mask
    -> estimate difficulty
    -> EASY: temporal reconstruction + optical flow
    -> fallback: OpenCV inpainting

This version intentionally has NO ProPainter integration.
It is a clean baseline intended to be tested first.

Requirements
------------
macOS
Python 3.10+

Install:
    python -m pip install numpy opencv-python pyobjc-framework-Vision pyobjc-framework-Quartz

Usage:
    python remove_text.py /path/to/frames

Optional:
    python remove_text.py /path/to/frames \
        --output /path/to/output \
        --save-masks

Notes
-----
- Apple Vision is used for text detection.
- The script processes images in filename order.
- Neighboring frames are used to reconstruct text-covered regions.
- If temporal reconstruction cannot provide a valid donor pixel,
  OpenCV Telea inpainting is used.
- No ProPainter, PyTorch, OCR engine or external service is required.
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

import cv2
import numpy as np

try:
    import Vision
    import Quartz
except ImportError:
    Vision = None
    Quartz = None


IMAGE_EXTENSIONS = {
    ".jpg",
    ".jpeg",
    ".png",
    ".webp",
    ".bmp",
    ".tif",
    ".tiff",
}


@dataclass(frozen=True)
class TextBox:
    x1: int
    y1: int
    x2: int
    y2: int
    confidence: float

    @property
    def width(self) -> int:
        return max(0, self.x2 - self.x1)

    @property
    def height(self) -> int:
        return max(0, self.y2 - self.y1)

    @property
    def area(self) -> int:
        return self.width * self.height


def check_dependencies() -> None:
    if sys.platform != "darwin":
        raise RuntimeError(
            "This script requires macOS because it uses Apple Vision."
        )

    if Vision is None or Quartz is None:
        raise RuntimeError(
            "Apple Vision dependencies are missing.\n\n"
            "Install them with:\n"
            "  python -m pip install pyobjc-framework-Vision pyobjc-framework-Quartz"
        )


def list_images(folder: Path) -> List[Path]:
    images = [
        path
        for path in folder.iterdir()
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
    ]

    return sorted(
        images,
        key=lambda path: path.name.lower(),
    )


def read_image(path: Path) -> np.ndarray:
    image = cv2.imread(
        str(path),
        cv2.IMREAD_COLOR,
    )

    if image is None:
        raise RuntimeError(f"Cannot read image: {path}")

    return image


def image_to_cgimage(image: np.ndarray):
    """
    Convert an OpenCV BGR image to CGImage for Apple Vision.

    Uses CGImageSourceCreateWithData to properly decode PNG bytes.
    CGImageCreate expects raw pixel data, not encoded PNG — using it
    directly with imencode output produces a zero-dimensioned image.
    """
    rgb = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2RGB,
    )

    success, encoded = cv2.imencode(
        ".png",
        rgb,
    )

    if not success:
        raise RuntimeError(
            "Failed to encode image for Apple Vision."
        )

    png_bytes = encoded.tobytes()

    # Wrap PNG bytes in a CFData object
    cf_data = Quartz.CFDataCreate(None, png_bytes, len(png_bytes))

    # Use CGImageSource to properly decode the PNG
    source = Quartz.CGImageSourceCreateWithData(cf_data, None)

    if source is None:
        raise RuntimeError(
            "CGImageSourceCreateWithData returned None. "
            "Image data may be corrupt."
        )

    cg_image = Quartz.CGImageSourceCreateImageAtIndex(source, 0, None)

    if cg_image is None:
        raise RuntimeError(
            "CGImageSourceCreateImageAtIndex returned None."
        )

    return cg_image


class AppleVisionTextDetector:
    """
    Native Apple Vision text detector using dual requests:

    1. VNRecognizeTextRequest  — high-quality text recognition bounding boxes
    2. VNDetectTextRectanglesRequest — pure text region detector (no recognition),
       more sensitive to large/stylized overlays like Douyin subtitles and
       comment UI boxes that VNRecognizeText may miss.

    Boxes from both requests are merged (union) to maximize recall.
    """

    def __init__(
        self,
        recognition_level: str = "accurate",
        min_confidence: float = 0.10,
        languages: Optional[List[str]] = None,
    ):
        check_dependencies()

        self.min_confidence = min_confidence

        # --- Request 1: Text recognition (VNRecognizeTextRequest) ---
        self.recognize_request = (
            Vision.VNRecognizeTextRequest
            .alloc()
            .init()
        )

        if recognition_level == "accurate":
            self.recognize_request.setRecognitionLevel_(
                Vision.VNRequestTextRecognitionLevelAccurate
            )
        else:
            self.recognize_request.setRecognitionLevel_(
                Vision.VNRequestTextRecognitionLevelFast
            )

        if languages:
            try:
                self.recognize_request.setRecognitionLanguages_(
                    languages
                )
            except Exception:
                pass

        try:
            self.recognize_request.setUsesLanguageCorrection_(False)
        except Exception:
            pass

        # --- Request 2: Text rectangle detection (VNDetectTextRectanglesRequest) ---
        # Does NOT recognize text content — only finds rectangular text regions.
        # Much more sensitive to large overlays, UI elements, and stylized text.
        try:
            self.rect_request = (
                Vision.VNDetectTextRectanglesRequest
                .alloc()
                .init()
            )
            # Report character-level boxes for finer granularity
            try:
                self.rect_request.setReportCharacterBoxes_(True)
            except Exception:
                pass
        except Exception:
            self.rect_request = None

    def _extract_boxes_from_recognize(
        self,
        observations,
        width: int,
        height: int,
    ) -> List[TextBox]:
        boxes: List[TextBox] = []

        for observation in (observations or []):
            try:
                candidates = observation.topCandidates_(1)

                if not candidates:
                    continue

                candidate = candidates[0]
                confidence = float(candidate.confidence())

                if confidence < self.min_confidence:
                    continue

                bb = observation.boundingBox()
                boxes.append(self._bb_to_textbox(bb, width, height, confidence))

            except Exception:
                continue

        return boxes

    def _extract_boxes_from_rects(
        self,
        observations,
        width: int,
        height: int,
    ) -> List[TextBox]:
        """Extract bounding boxes from VNDetectTextRectanglesRequest results."""
        boxes: List[TextBox] = []

        for observation in (observations or []):
            try:
                bb = observation.boundingBox()
                # TextRectangles has no confidence — treat all as high confidence
                boxes.append(self._bb_to_textbox(bb, width, height, 1.0))
            except Exception:
                continue

        return boxes

    def _bb_to_textbox(
        self,
        bounding_box,
        width: int,
        height: int,
        confidence: float,
    ) -> TextBox:
        """Convert a Vision normalized bounding box (bottom-left origin) to TextBox."""
        x1 = int(bounding_box.origin.x * width)
        y1 = int(
            (1.0 - bounding_box.origin.y - bounding_box.size.height)
            * height
        )
        x2 = int((bounding_box.origin.x + bounding_box.size.width) * width)
        y2 = int((1.0 - bounding_box.origin.y) * height)

        x1 = max(0, min(width - 1, x1))
        y1 = max(0, min(height - 1, y1))
        x2 = max(0, min(width, x2))
        y2 = max(0, min(height, y2))

        return TextBox(x1=x1, y1=y1, x2=x2, y2=y2, confidence=confidence)

    def detect(
        self,
        image: np.ndarray,
    ) -> List[TextBox]:
        height, width = image.shape[:2]

        cg_image = image_to_cgimage(image)

        handler = (
            Vision.VNImageRequestHandler
            .alloc()
            .initWithCGImage_options_(
                cg_image,
                {},
            )
        )

        # Run both requests in a single handler call for efficiency
        requests = [self.recognize_request]
        if self.rect_request is not None:
            requests.append(self.rect_request)

        # IMPORTANT: PyObjC maps performRequests:error: → performRequests_error_
        success, error = handler.performRequests_error_(requests, None)

        if not success:
            raise RuntimeError(
                f"Apple Vision request failed: {error}"
            )

        # Collect boxes from VNRecognizeTextRequest
        recognize_obs = self.recognize_request.results() or []
        boxes = self._extract_boxes_from_recognize(recognize_obs, width, height)

        # Collect boxes from VNDetectTextRectanglesRequest and merge
        if self.rect_request is not None:
            rect_obs = self.rect_request.results() or []
            rect_boxes = self._extract_boxes_from_rects(rect_obs, width, height)
            boxes.extend(rect_boxes)

        return merge_boxes(boxes)


def merge_boxes(
    boxes: List[TextBox],
    padding: int = 8,
    gap: int = 40,
) -> List[TextBox]:
    """
    Merge nearby text observations into unified bounding boxes.

    Vision may return one observation per word/line/character.
    We combine nearby boxes so the reconstruction mask covers the complete
    text region — including surrounding UI card backgrounds (e.g. Douyin
    comment overlays where avatar + username + body text are separated by
    20-40px gaps but belong to the same UI element).

    padding: expand each box by this many pixels before merging.
    gap: two boxes are considered part of the same region if their edges
         are within this many pixels of each other.
    """
    if not boxes:
        return []

    pending = [
        TextBox(
            x1=b.x1 - padding,
            y1=b.y1 - padding,
            x2=b.x2 + padding,
            y2=b.y2 + padding,
            confidence=b.confidence,
        )
        for b in boxes
    ]

    changed = True

    while changed:
        changed = False
        result: List[TextBox] = []
        used = [False] * len(pending)

        for index, current in enumerate(pending):
            if used[index]:
                continue

            used[index] = True

            merged = current

            merge_again = True

            while merge_again:
                merge_again = False

                for other_index, other in enumerate(pending):
                    if used[other_index]:
                        continue

                    if boxes_close(
                        merged,
                        other,
                        gap,
                    ):
                        merged = TextBox(
                            x1=min(
                                merged.x1,
                                other.x1,
                            ),
                            y1=min(
                                merged.y1,
                                other.y1,
                            ),
                            x2=max(
                                merged.x2,
                                other.x2,
                            ),
                            y2=max(
                                merged.y2,
                                other.y2,
                            ),
                            confidence=max(
                                merged.confidence,
                                other.confidence,
                            ),
                        )

                        used[other_index] = True
                        merge_again = True
                        changed = True

            result.append(merged)

        pending = result

    return pending


def boxes_close(
    a: TextBox,
    b: TextBox,
    gap: int,
) -> bool:
    return not (
        a.x2 + gap < b.x1
        or b.x2 + gap < a.x1
        or a.y2 + gap < b.y1
        or b.y2 + gap < a.y1
    )


def boxes_to_mask(
    image_shape: Tuple[int, int],
    boxes: List[TextBox],
    dilation: int,
) -> np.ndarray:
    height, width = image_shape

    mask = np.zeros(
        (height, width),
        dtype=np.uint8,
    )

    for box in boxes:
        x1 = max(
            0,
            box.x1,
        )

        y1 = max(
            0,
            box.y1,
        )

        x2 = min(
            width,
            box.x2,
        )

        y2 = min(
            height,
            box.y2,
        )

        if x2 <= x1 or y2 <= y1:
            continue

        cv2.rectangle(
            mask,
            (x1, y1),
            (x2, y2),
            255,
            -1,
        )

    if dilation > 0 and np.any(mask):
        kernel_size = (
            dilation * 2 + 1
        )

        kernel = cv2.getStructuringElement(
            cv2.MORPH_ELLIPSE,
            (
                kernel_size,
                kernel_size,
            ),
        )

        mask = cv2.dilate(
            mask,
            kernel,
        )

    return mask


def compute_optical_flow(
    source: np.ndarray,
    target: np.ndarray,
) -> np.ndarray:
    """
    Compute source -> target optical flow.

    Farneback is deliberately used for this baseline because it is available
    in standard OpenCV and does not require another ML model.
    """
    source_gray = cv2.cvtColor(
        source,
        cv2.COLOR_BGR2GRAY,
    )

    target_gray = cv2.cvtColor(
        target,
        cv2.COLOR_BGR2GRAY,
    )

    return cv2.calcOpticalFlowFarneback(
        target_gray,
        source_gray,
        None,
        pyr_scale=0.5,
        levels=3,
        winsize=21,
        iterations=3,
        poly_n=5,
        poly_sigma=1.2,
        flags=0,
    )


def warp_with_flow(
    source: np.ndarray,
    target: np.ndarray,
    flow: np.ndarray,
) -> np.ndarray:
    height, width = target.shape[:2]

    grid_x, grid_y = np.meshgrid(
        np.arange(width),
        np.arange(height),
    )

    map_x = (
        grid_x + flow[..., 0]
    ).astype(np.float32)

    map_y = (
        grid_y + flow[..., 1]
    ).astype(np.float32)

    return cv2.remap(
        source,
        map_x,
        map_y,
        interpolation=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_REFLECT,
    )


def warp_mask(
    mask: np.ndarray,
    target_shape: Tuple[int, int],
    flow: np.ndarray,
) -> np.ndarray:
    height, width = target_shape

    grid_x, grid_y = np.meshgrid(
        np.arange(width),
        np.arange(height),
    )

    map_x = (
        grid_x + flow[..., 0]
    ).astype(np.float32)

    map_y = (
        grid_y + flow[..., 1]
    ).astype(np.float32)

    # BUG FIX: borderValue must be 0 (unmasked), NOT 255.
    # Using 255 marks out-of-bounds warped pixels as "masked in donor",
    # which incorrectly discards valid donor pixels at image edges.
    return cv2.remap(
        mask,
        map_x,
        map_y,
        interpolation=cv2.INTER_NEAREST,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=0,
    )


def calculate_difficulty(
    image: np.ndarray,
    mask: np.ndarray,
    flow: Optional[np.ndarray],
) -> float:
    """
    Estimate reconstruction difficulty from 0 to 1.

    Higher means:
      - larger text-covered area
      - more texture under text
      - stronger local motion

    This score is intentionally heuristic. It is used only to decide whether
    temporal reconstruction is likely to be reliable.
    """
    region = mask > 0

    if not np.any(region):
        return 0.0

    height, width = mask.shape

    area_ratio = (
        float(np.count_nonzero(region))
        / float(height * width)
    )

    area_score = min(
        area_ratio / 0.18,
        1.0,
    )

    gray = cv2.cvtColor(
        image,
        cv2.COLOR_BGR2GRAY,
    )

    laplacian = cv2.Laplacian(
        gray,
        cv2.CV_32F,
    )

    texture_value = float(
        np.mean(
            np.abs(laplacian)[region]
        )
    )

    texture_score = min(
        texture_value / 80.0,
        1.0,
    )

    motion_score = 0.0

    if flow is not None:
        magnitude = np.sqrt(
            flow[..., 0] ** 2
            + flow[..., 1] ** 2
        )

        motion_value = float(
            np.mean(
                magnitude[region]
            )
        )

        motion_score = min(
            motion_value / 10.0,
            1.0,
        )

    return (
        0.30 * area_score
        + 0.35 * texture_score
        + 0.35 * motion_score
    )


def opencv_inpaint(
    image: np.ndarray,
    mask: np.ndarray,
    radius: float = 15.0,
) -> np.ndarray:
    """OpenCV Telea inpainting. radius=15 covers typical subtitle text height."""
    return cv2.inpaint(
        image,
        mask,
        radius,
        cv2.INPAINT_TELEA,
    )


def box_blur_inpaint(
    image: np.ndarray,
    mask: np.ndarray,
    blur_strength: int = 6,
) -> np.ndarray:
    """
    Blur-based inpainting: downscale → heavy blur → upscale → composite.

    This is the same strategy as the pipeline's ffmpeg_blur plugin:
    Downscale 4x ➔ blur ➔ bilinear upscale → paste back onto mask region.

    Works significantly better than Telea inpaint for large text overlays
    (subtitles that cover 10–40% of the frame width) because Telea is
    only reliable for thin/small regions (< ~30px radius).
    """
    h, w = image.shape[:2]

    small_w = max(1, w // 4)
    small_h = max(1, h // 4)

    # Downscale → apply strong Gaussian blur → upscale back
    small = cv2.resize(
        image,
        (small_w, small_h),
        interpolation=cv2.INTER_LINEAR,
    )

    ksize = blur_strength * 2 + 1
    blurred_small = cv2.GaussianBlur(
        small,
        (ksize, ksize),
        0,
    )

    blurred = cv2.resize(
        blurred_small,
        (w, h),
        interpolation=cv2.INTER_LINEAR,
    )

    # Additionally apply a direct blur on original for sharper result
    direct_ksize = min(blur_strength * 8 + 1, 121)
    # Ensure odd
    if direct_ksize % 2 == 0:
        direct_ksize += 1
    direct_blurred = cv2.GaussianBlur(
        image,
        (direct_ksize, direct_ksize),
        0,
    )

    # Blend the two blur sources: 50% downscale-blur + 50% direct blur
    combined_blur = cv2.addWeighted(blurred, 0.5, direct_blurred, 0.5, 0)

    # Composite: paste blurred pixels only in mask region
    result = image.copy()
    mask_bool = mask > 0
    result[mask_bool] = combined_blur[mask_bool]

    return result


def temporal_reconstruct(
    current: np.ndarray,
    current_mask: np.ndarray,
    previous: Optional[np.ndarray],
    previous_mask: Optional[np.ndarray],
    next_image: Optional[np.ndarray],
    next_mask: Optional[np.ndarray],
) -> np.ndarray:
    """
    Reconstruct masked pixels using neighboring frames.

    Strategy:
      1. Warp previous/next frames into current frame (optical flow).
      2. Use donor pixels that are NOT masked in their original frame.
      3. If both donors are valid, average them.
      4. Remaining pixels → OpenCV Telea inpainting (good for small gaps).
      5. ALWAYS apply box-blur inpaint as final pass over entire mask region.
         This ensures large subtitle overlays are fully removed even when
         temporal reconstruction or Telea inpaint leave residual text.
    """
    target_mask = current_mask > 0

    if not np.any(target_mask):
        return current.copy()

    donor_images = []

    if previous is not None:
        donor_images.append(
            (
                previous,
                previous_mask,
            )
        )

    if next_image is not None:
        donor_images.append(
            (
                next_image,
                next_mask,
            )
        )

    reconstructed = current.copy()

    # --- Step 1: Temporal reconstruction via optical flow ---
    if donor_images:
        accumulated = np.zeros(
            current.shape,
            dtype=np.float32,
        )

        weights = np.zeros(
            current_mask.shape,
            dtype=np.float32,
        )

        for donor, donor_mask in donor_images:
            try:
                flow = compute_optical_flow(
                    donor,
                    current,
                )

                warped = warp_with_flow(
                    donor,
                    current,
                    flow,
                )

                if donor_mask is None:
                    valid = np.ones(
                        current_mask.shape,
                        dtype=bool,
                    )
                else:
                    warped_donor_mask = warp_mask(
                        donor_mask,
                        current_mask.shape,
                        flow,
                    )

                    valid = (
                        warped_donor_mask < 128
                    )

                valid &= target_mask

                if not np.any(valid):
                    continue

                accumulated[valid] += (
                    warped[valid].astype(
                        np.float32
                    )
                )

                weights[valid] += 1.0

            except Exception:
                continue

        has_temporal = weights > 0

        if np.any(has_temporal):
            # weights shape: (H, W) — need to broadcast over 3 channels
            w = weights[has_temporal]  # shape: (N,)
            reconstructed[has_temporal] = (
                accumulated[has_temporal]  # shape: (N, 3)
                / w[:, None]               # shape: (N, 1) — correct broadcast
            ).astype(np.uint8)

        # --- Step 2: Telea inpaint for pixels not covered by temporal ---
        remaining = target_mask & (~has_temporal)

        if np.any(remaining):
            fallback_mask = np.zeros_like(current_mask)
            fallback_mask[remaining] = 255
            reconstructed = opencv_inpaint(
                reconstructed,
                fallback_mask,
            )

    else:
        # No donor frames available at all — pure inpaint
        reconstructed = opencv_inpaint(current, current_mask)

    # --- Step 3 (CRITICAL): Box-blur pass over ENTIRE mask region ---
    # This is the primary defense against large subtitle text.
    # Even if steps 1-2 partially failed, the blur guarantees the mask
    # region no longer contains recognizable text pixels.
    reconstructed = box_blur_inpaint(
        reconstructed,
        current_mask,
        blur_strength=8,
    )

    # --- Step 4: Feather the mask edge for a smooth transition ---
    alpha = (
        cv2.GaussianBlur(
            current_mask,
            (0, 0),
            2.0,
        ).astype(np.float32)
        / 255.0
    )

    alpha = alpha[..., None]

    output = (
        current.astype(np.float32) * (1.0 - alpha)
        + reconstructed.astype(np.float32) * alpha
    )

    return np.clip(
        output,
        0,
        255,
    ).astype(np.uint8)



def save_image(
    path: Path,
    image: np.ndarray,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    success = cv2.imwrite(
        str(path),
        image,
    )

    if not success:
        raise RuntimeError(
            f"Failed to write image: {path}"
        )


def save_mask(
    path: Path,
    mask: np.ndarray,
) -> None:
    path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    success = cv2.imwrite(
        str(path),
        mask,
    )

    if not success:
        raise RuntimeError(
            f"Failed to write mask: {path}"
        )


def process_folder(
    input_dir: Path,
    output_dir: Path,
    detector: AppleVisionTextDetector,
    dilation: int,
    hard_threshold: float,
    save_masks: bool,
) -> None:
    images = list_images(
        input_dir
    )

    if not images:
        raise RuntimeError(
            f"No supported images found in: {input_dir}"
        )

    output_dir.mkdir(
        parents=True,
        exist_ok=True,
    )

    mask_dir = (
        output_dir / "_masks"
    )

    if save_masks:
        mask_dir.mkdir(
            parents=True,
            exist_ok=True,
        )

    print(
        f"[INFO] Found {len(images)} images"
    )

    print(
        f"[INFO] Output: {output_dir}"
    )

    print(
        "[INFO] Text detector: Apple Vision"
    )

    print(
        "[INFO] Reconstruction: "
        "Temporal + Optical Flow + OpenCV"
    )

    # ---------------------------------------------------------
    # PASS 1
    # Detect text and calculate masks.
    # ---------------------------------------------------------
    masks: List[np.ndarray] = []
    scores: List[float] = []

    previous_image: Optional[
        np.ndarray
    ] = None

    for index, image_path in enumerate(
        images
    ):
        print(
            f"[DETECT {index + 1:04d}/{len(images):04d}] "
            f"{image_path.name}",
            flush=True,
        )

        image = read_image(
            image_path
        )

        boxes = detector.detect(
            image
        )

        mask = boxes_to_mask(
            image.shape[:2],
            boxes,
            dilation,
        )

        flow = None

        if previous_image is not None and boxes:
            try:
                flow = compute_optical_flow(
                    previous_image,
                    image,
                )
            except Exception:
                flow = None

        score = calculate_difficulty(
            image,
            mask,
            flow,
        )

        masks.append(mask)
        scores.append(score)

        if save_masks:
            save_mask(
                mask_dir
                / f"{index:06d}.png",
                mask,
            )

        state = (
            "NONE"
            if not boxes
            else (
                "HARD"
                if score >= hard_threshold
                else "EASY"
            )
        )

        print(
            f"  text_boxes={len(boxes):02d} "
            f"difficulty={score:.3f} "
            f"state={state}",
            flush=True,
        )

        previous_image = image

    # ---------------------------------------------------------
    # PASS 2
    # Reconstruct each frame.
    #
    # IMPORTANT:
    # This baseline does NOT call ProPainter.
    # HARD only changes the log state; OpenCV is still used.
    # ---------------------------------------------------------
    print(
        "\n[INFO] Starting reconstruction...",
        flush=True,
    )

    for index, image_path in enumerate(
        images
    ):
        image = read_image(
            image_path
        )

        mask = masks[index]

        if not np.any(mask):
            output = image

        else:
            previous = None
            previous_mask = None

            next_image = None
            next_mask = None

            if index > 0:
                previous = read_image(
                    images[index - 1]
                )

                previous_mask = masks[
                    index - 1
                ]

            if index + 1 < len(images):
                next_image = read_image(
                    images[index + 1]
                )

                next_mask = masks[
                    index + 1
                ]

            output = temporal_reconstruct(
                current=image,
                current_mask=mask,
                previous=previous,
                previous_mask=previous_mask,
                next_image=next_image,
                next_mask=next_mask,
            )

        save_image(
            output_dir / image_path.name,
            output,
        )

        state = (
            "HARD"
            if scores[index] >= hard_threshold
            else "EASY"
        )

        print(
            f"[WRITE {index + 1:04d}/{len(images):04d}] "
            f"{image_path.name} "
            f"state={state}",
            flush=True,
        )

    print(
        "\n[DONE]",
        flush=True,
    )

    print(
        f"[DONE] Clean images: {output_dir}",
        flush=True,
    )


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Remove detected text from a folder of image frames "
            "using Apple Vision + temporal reconstruction."
        )
    )

    parser.add_argument(
        "input",
        type=Path,
        help="Input folder containing images.",
    )

    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help=(
            "Output folder. "
            "Default: <input>/cleaned"
        ),
    )

    parser.add_argument(
        "--recognition-level",
        choices=[
            "fast",
            "accurate",
        ],
        default="accurate",
        help=(
            "Apple Vision recognition level. "
            "Default: accurate"
        ),
    )

    parser.add_argument(
        "--min-confidence",
        type=float,
        default=0.10,
        help=(
            "Minimum Apple Vision confidence for VNRecognizeTextRequest. "
            "VNDetectTextRectanglesRequest always runs regardless. "
            "Default: 0.10"
        ),
    )

    parser.add_argument(
        "--languages",
        nargs="*",
        default=None,
        help=(
            "Optional Vision languages, e.g. "
            "vi-VN en-US zh-Hans."
        ),
    )

    parser.add_argument(
        "--dilation",
        type=int,
        default=12,
        help=(
            "Expand text mask by this many pixels. "
            "Default: 12 (covers thick subtitle strokes)"
        ),
    )

    parser.add_argument(
        "--hard-threshold",
        type=float,
        default=0.60,
        help=(
            "Difficulty threshold used only for logging. "
            "Default: 0.60"
        ),
    )

    parser.add_argument(
        "--save-masks",
        action="store_true",
        help=(
            "Save detected masks under output/_masks."
        ),
    )

    return parser.parse_args()


def main() -> int:
    args = parse_arguments()

    try:
        check_dependencies()

        input_dir = (
            args.input
            .expanduser()
            .resolve()
        )

        if not input_dir.exists():
            raise RuntimeError(
                f"Input folder does not exist: "
                f"{input_dir}"
            )

        if not input_dir.is_dir():
            raise RuntimeError(
                f"Input path is not a folder: "
                f"{input_dir}"
            )

        if args.output is None:
            output_dir = (
                input_dir / "cleaned"
            )
        else:
            output_dir = (
                args.output
                .expanduser()
                .resolve()
            )

        detector = AppleVisionTextDetector(
            recognition_level=(
                args.recognition_level
            ),
            min_confidence=(
                args.min_confidence
            ),
            languages=args.languages,
        )

        process_folder(
            input_dir=input_dir,
            output_dir=output_dir,
            detector=detector,
            dilation=args.dilation,
            hard_threshold=(
                args.hard_threshold
            ),
            save_masks=args.save_masks,
        )

        return 0

    except KeyboardInterrupt:
        print(
            "\n[STOPPED]"
        )
        return 130

    except Exception as error:
        print(
            f"[ERROR] {error}",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(
        main()
    )
