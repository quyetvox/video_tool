import os
import subprocess
import tempfile
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List, Optional

import cv2
import numpy as np

from plugins.interfaces import InpaintBase

# Try importing Vision & Cocoa framework for macOS in-memory execution
HAS_APPLE_VISION = False
try:
    import Vision
    from Cocoa import NSData
    HAS_APPLE_VISION = True
except Exception:
    HAS_APPLE_VISION = False


def _detect_text_mask_apple_vision(
    frame: np.ndarray,
    region: List[float]
) -> np.ndarray:
    """
    Uses Apple Vision Framework via PyObjC to detect text bounding boxes inside candidate region
    in-memory (0 disk I/O) and returns a binary mask covering text character bounding boxes.
    """
    height, width = frame.shape[:2]
    mask = np.zeros((height, width), dtype=np.uint8)

    ymin, xmin, ymax, xmax = region
    rymin, rxmin = int(height * ymin), int(width * xmin)
    rymax, rxmax = int(height * ymax), int(width * xmax)

    # Add small boundary margin for cropping
    crop_ymin, crop_ymax = max(0, rymin - 5), min(height, rymax + 5)
    crop_xmin, crop_xmax = max(0, rxmin - 5), min(width, rxmax + 5)

    crop = frame[crop_ymin:crop_ymax, crop_xmin:crop_xmax]
    if crop.size == 0:
        return mask

    crop_h, crop_w = crop.shape[:2]

    try:
        # Encode image crop to memory PNG buffer
        ok, buf = cv2.imencode(".png", crop)
        if not ok:
            return _detect_text_mask_contour(frame, region)

        data_bytes = buf.tobytes()
        nsdata = NSData.dataWithBytes_length_(data_bytes, len(data_bytes))

        request_det = Vision.VNDetectTextRectanglesRequest.alloc().init()
        request_det.setReportCharacterBoxes_(True)

        request_rec = Vision.VNRecognizeTextRequest.alloc().init()
        request_rec.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
        try:
            request_rec.setRecognitionLanguages_(['zh-Hans', 'zh-Hant', 'en-US', 'vi-VT', 'ja-JP', 'ko-KR'])
        except Exception:
            pass

        handler = Vision.VNImageRequestHandler.alloc().initWithData_options_(nsdata, None)
        success, _ = handler.performRequests_error_([request_det, request_rec], None)

        boxes = []
        if request_rec.results():
            for res in request_rec.results():
                boxes.append(res.boundingBox())
        if request_det.results():
            for res in request_det.results():
                boxes.append(res.boundingBox())

        if boxes:
            for bbox in boxes:
                vx, vy = bbox.origin.x, bbox.origin.y
                vw, vh = bbox.size.width, bbox.size.height

                # Apple Vision coords: Y origin 0.0 is at bottom
                x1 = int(vx * crop_w) + crop_xmin
                x2 = int((vx + vw) * crop_w) + crop_xmin
                y1 = int((1.0 - vy - vh) * crop_h) + crop_ymin
                y2 = int((1.0 - vy) * crop_h) + crop_ymin

                # Add 6px padding to cover text stroke outlines and drop shadows
                x1, x2 = max(0, x1 - 6), min(width, x2 + 6)
                y1, y2 = max(0, y1 - 6), min(height, y2 + 6)

                mask[y1:y2, x1:x2] = 255
        else:
            # Fallback if Vision returns no candidate text: use morphological contour threshold
            mask = _detect_text_mask_contour(frame, region)
    except Exception:
        mask = _detect_text_mask_contour(frame, region)

    return mask


def _detect_text_mask_contour(frame: np.ndarray, region: List[float]) -> np.ndarray:
    """
    Fallback text mask detection using adaptive thresholding and morphological operations
    when Apple Vision is not available or detects no text.
    """
    height, width = frame.shape[:2]
    mask = np.zeros((height, width), dtype=np.uint8)

    ymin, xmin, ymax, xmax = region
    rymin, rxmin = int(height * ymin), int(width * xmin)
    rymax, rxmax = int(height * ymax), int(width * xmax)

    rymin, rxmin = max(0, rymin - 3), max(0, rxmin - 3)
    rymax, rxmax = min(height, rymax + 3), min(width, rxmax + 3)

    roi = frame[rymin:rymax, rxmin:rxmax]
    if roi.size == 0:
        return mask

    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    grad = cv2.morphologyEx(gray, cv2.MORPH_GRADIENT, np.ones((3, 3), np.uint8))
    _, thresh = cv2.threshold(grad, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 3))
    dilated = cv2.dilate(thresh, kernel, iterations=2)

    mask[rymin:rymax, rxmin:rxmax] = dilated
    return mask


def _inpaint_chunk_worker_apple_vision(
    video_path: str,
    start_frame: int,
    frame_count: int,
    default_region: List[float],
    segments: Optional[List[Dict[str, Any]]],
    chunk_out_path: str,
    fps: float,
    width: int,
    height: int
) -> str:
    os.environ.pop("MallocStackLogging", None)
    os.environ.pop("MallocScribble", None)

    # Check Vision framework availability inside worker process
    has_vision = False
    try:
        import Vision
        from Cocoa import NSData
        has_vision = True
    except Exception:
        has_vision = False

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video in worker: {video_path}")

    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(chunk_out_path, fourcc, fps, (width, height))

    processed = 0
    frame_idx = start_frame

    # Collect all candidate subtitle search regions
    search_regions = []
    if default_region:
        search_regions.append(default_region)

    if segments:
        for seg in segments:
            bbox = seg.get("bbox")
            if bbox and len(bbox) == 4:
                search_regions.append(bbox)

    # Build continuous enclosing candidate region covering all detected subtitle Y bounds
    if search_regions:
        all_ymin = min(r[0] for r in search_regions)
        all_xmin = min(r[1] for r in search_regions)
        all_ymax = max(r[2] for r in search_regions)
        all_xmax = max(r[3] for r in search_regions)
        # Add small vertical margin to enclosing region
        enclosing_region = [max(0.0, all_ymin - 0.02), max(0.0, all_xmin - 0.02), min(1.0, all_ymax + 0.02), min(1.0, all_xmax + 0.02)]
    else:
        enclosing_region = [0.55, 0.05, 0.95, 0.95]

    # Cache mask for consecutive frames with identical/similar subtitle crop
    last_crop_gray = None
    last_mask = None

    while processed < frame_count and cap.isOpened():
        ret, frame = cap.read()
        if not ret or frame is None:
            break

        # Check crop diff vs previous frame to reuse cached mask
        ymin, xmin, ymax, xmax = enclosing_region
        rymin, rxmin = int(height * ymin), int(width * xmin)
        rymax, rxmax = int(height * ymax), int(width * xmax)
        crop = frame[max(0, rymin - 5):min(height, rymax + 5), max(0, rxmin - 5):min(width, rxmax + 5)]

        use_cache = False
        if crop.size > 0:
            crop_gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
            if last_crop_gray is not None and last_crop_gray.shape == crop_gray.shape and last_mask is not None:
                diff = cv2.absdiff(crop_gray, last_crop_gray)
                if np.mean(diff) < 2.0: # Very small crop change -> reuse mask
                    use_cache = True

        if use_cache and last_mask is not None:
            combined_mask = last_mask
        else:
            if has_vision:
                combined_mask = _detect_text_mask_apple_vision(frame, enclosing_region)
            else:
                combined_mask = _detect_text_mask_contour(frame, enclosing_region)

            if crop.size > 0:
                last_crop_gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
                last_mask = combined_mask

        if np.any(combined_mask > 0):
            # Erase text cleanly using Telea inpainting on detected text mask
            inpainted = cv2.inpaint(frame, combined_mask, inpaintRadius=3, flags=cv2.INPAINT_TELEA)
            out.write(inpainted)
        else:
            out.write(frame)

        processed += 1
        frame_idx += 1

    cap.release()
    out.release()
    return chunk_out_path


class Plugin(InpaintBase):
    def remove_subtitles(
        self,
        video_path: Path,
        region: List[float],
        output_video: Path,
        segments: Optional[List[Dict[str, Any]]] = None
    ) -> Path:
        inpaint_color = str(self.config.get("inpaint_color", "transparent")).strip().lower()
        if inpaint_color not in ["transparent", "", "none"]:
            from plugins.inpaint.ffmpeg_blur import Plugin as FFmpegBlurPlugin
            return FFmpegBlurPlugin(self.config).remove_subtitles(video_path, region, output_video, segments=segments)

        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            raise RuntimeError(f"Cannot open video for inpainting: {video_path}")

        fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        cap.release()

        num_workers = max(1, min(os.cpu_count() or 4, 8))
        chunk_size = max(1, total_frames // num_workers)

        with tempfile.TemporaryDirectory() as temp_dir:
            futures = []
            chunk_files = []

            with ProcessPoolExecutor(max_workers=num_workers) as executor:
                for i in range(num_workers):
                    start_f = i * chunk_size
                    f_count = total_frames - start_f if i == num_workers - 1 else chunk_size
                    if f_count <= 0:
                        continue

                    chunk_out = os.path.join(temp_dir, f"chunk_{i:03d}.mp4")
                    chunk_files.append(chunk_out)

                    futures.append(executor.submit(
                        _inpaint_chunk_worker_apple_vision,
                        str(video_path),
                        start_f,
                        f_count,
                        region,
                        segments,
                        chunk_out,
                        fps,
                        width,
                        height
                    ))

                for future in as_completed(futures):
                    future.result()

            # Concat video chunks into output file
            list_txt_path = os.path.join(temp_dir, "chunks.txt")
            with open(list_txt_path, "w", encoding="utf-8") as f:
                for cf in sorted(chunk_files):
                    f.write(f"file '{cf}'\n")

            cmd = [
                "ffmpeg", "-y",
                "-f", "concat",
                "-safe", "0",
                "-i", list_txt_path,
                "-c", "copy",
                str(output_video)
            ]

            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if res.returncode != 0:
                cmd_reencode = [
                    "ffmpeg", "-y",
                    "-f", "concat",
                    "-safe", "0",
                    "-i", list_txt_path,
                    "-c:v", "libx264",
                    "-pix_fmt", "yuv420p",
                    str(output_video)
                ]
                subprocess.run(cmd_reencode, check=True)

        return output_video
