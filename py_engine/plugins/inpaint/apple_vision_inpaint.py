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
    in-memory and returns a unified enclosing line-box mask covering the entire subtitle sentence.
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
            all_x1, all_x2, all_y1, all_y2 = [], [], [], []
            for bbox in boxes:
                vx, vy = bbox.origin.x, bbox.origin.y
                vw, vh = bbox.size.width, bbox.size.height

                # Apple Vision coords: Y origin 0.0 is at bottom
                x1 = int(vx * crop_w) + crop_xmin
                x2 = int((vx + vw) * crop_w) + crop_xmin
                y1 = int((1.0 - vy - vh) * crop_h) + crop_ymin
                y2 = int((1.0 - vy) * crop_h) + crop_ymin

                all_x1.append(x1)
                all_x2.append(x2)
                all_y1.append(y1)
                all_y2.append(y2)

            # Unified Enclosing Line-Box: covers entire subtitle strip with safety padding
            line_x1 = max(0, min(all_x1) - 15)
            line_x2 = min(width, max(all_x2) + 15)
            line_y1 = max(0, min(all_y1) - 8)
            line_y2 = min(height, max(all_y2) + 8)

            mask[line_y1:line_y2, line_x1:line_x2] = 255
        else:
            # Fallback if Vision returns no candidate text: use morphological contour threshold
            mask = _detect_text_mask_contour(frame, region)
    except Exception:
        mask = _detect_text_mask_contour(frame, region)

    return mask


def _detect_text_mask_contour(frame: np.ndarray, region: List[float]) -> np.ndarray:
    """
    Fallback text mask detection using adaptive thresholding and morphological line bounding.
    """
    height, width = frame.shape[:2]
    mask = np.zeros((height, width), dtype=np.uint8)

    ymin, xmin, ymax, xmax = region
    rymin, rxmin = int(height * ymin), int(width * xmin)
    rymax, rxmax = int(height * ymax), int(width * xmax)

    rymin, rxmin = max(0, rymin - 5), max(0, rxmin - 5)
    rymax, rxmax = min(height, rymax + 5), min(width, rxmax + 5)

    roi = frame[rymin:rymax, rxmin:rxmax]
    if roi.size == 0:
        return mask

    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    grad = cv2.morphologyEx(gray, cv2.MORPH_GRADIENT, np.ones((3, 3), np.uint8))
    _, thresh = cv2.threshold(grad, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)

    # Find bounding rect of text components
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    valid_boxes = []
    for c in contours:
        x, y, w, h = cv2.boundingRect(c)
        if w > 8 and h > 6:
            valid_boxes.append((x, y, x + w, y + h))

    if valid_boxes:
        bx1 = max(0, min(b[0] for b in valid_boxes) - 15) + rxmin
        bx2 = min(width, max(b[2] for b in valid_boxes) + 15) + rxmin
        by1 = max(0, min(b[1] for b in valid_boxes) - 8) + rymin
        by2 = min(height, max(b[3] for b in valid_boxes) + 8) + rymin
        mask[by1:by2, bx1:bx2] = 255
    else:
        # Fallback to whole region
        mask[rymin:rymax, rxmin:rxmax] = 255

    return mask


def _inpaint_vertical_gradient(
    frame: np.ndarray,
    rymin: int,
    rymax: int,
    rxmin: int,
    rxmax: int
) -> np.ndarray:
    """
    Directional Vertical Cosine Gradient Interpolation with horizontal soft feathering.
    Interpolates smoothly along the vertical axis from clean pixels above ymin to clean pixels below ymax.
    Completely eliminates 45-degree diagonal shock seams, sword-like artifacts, and yellow smears.
    """
    height, width = frame.shape[:2]
    rymin = max(3, min(height - 4, rymin))
    rymax = max(rymin + 1, min(height - 1, rymax))
    rxmin = max(0, min(width - 1, rxmin))
    rxmax = max(rxmin + 1, min(width, rxmax))

    h = rymax - rymin
    w = rxmax - rxmin
    if h <= 0 or w <= 0:
        return frame

    out_frame = frame.copy()

    # 1. Sample clean boundary strip above (3 rows) and below (3 rows)
    top_sample = frame[max(0, rymin - 4):rymin, rxmin:rxmax].astype(np.float32)
    bot_sample = frame[rymax:min(height, rymax + 4), rxmin:rxmax].astype(np.float32)

    top_row = np.median(top_sample, axis=0) if top_sample.shape[0] > 0 else frame[rymin - 1, rxmin:rxmax].astype(np.float32)
    bot_row = np.median(bot_sample, axis=0) if bot_sample.shape[0] > 0 else frame[rymax, rxmin:rxmax].astype(np.float32)

    # 2. Smooth Cosine Vertical Weights [0.0 -> 1.0] across height h
    y_indices = np.arange(h, dtype=np.float32)
    if h > 1:
        wy = (1.0 - np.cos(np.pi * y_indices / (h - 1))) / 2.0
    else:
        wy = np.array([0.5], dtype=np.float32)

    # 3. Construct the interpolated patch: shape (h, w, 3)
    wy_3d = wy[:, np.newaxis, np.newaxis]
    top_row_3d = top_row[np.newaxis, :, :]
    bot_row_3d = bot_row[np.newaxis, :, :]

    interpolated_patch = (top_row_3d * (1.0 - wy_3d) + bot_row_3d * wy_3d)

    # 4. Horizontal Soft Fade on left (fade in) and right (fade out) margins
    fade_len = min(25, w // 4)
    if fade_len > 0:
        orig_crop = frame[rymin:rymax, rxmin:rxmax].astype(np.float32)
        x_fade = np.ones(w, dtype=np.float32)
        x_fade[:fade_len] = (1.0 - np.cos(np.pi * np.arange(fade_len) / fade_len)) / 2.0
        x_fade[-fade_len:] = (1.0 + np.cos(np.pi * np.arange(fade_len) / fade_len)) / 2.0
        fade_2d = x_fade[np.newaxis, :, np.newaxis]
        interpolated_patch = orig_crop * (1.0 - fade_2d) + interpolated_patch * fade_2d

    out_frame[rymin:rymax, rxmin:rxmax] = np.clip(interpolated_patch, 0, 255).astype(np.uint8)
    return out_frame


def _inpaint_chunk_worker_apple_vision(
    video_path: str,
    start_frame: int,
    frame_count: int,
    default_region: List[float],
    segments: Optional[List[Dict[str, Any]]],
    chunk_out_path: str,
    fps: float,
    width: int,
    height: int,
    inpaint_method: str = "vertical_gradient"
) -> str:
    os.environ.pop("MallocStackLogging", None)
    os.environ.pop("MallocScribble", None)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video in worker: {video_path}")

    # 1. Enclosing candidate search region
    enclosing_region = default_region if (default_region and len(default_region) == 4) else [0.70, 0.05, 0.98, 0.95]
    ymin, xmin, ymax, xmax = enclosing_region
    rymin, rxmin = int(height * ymin), int(width * xmin)
    rymax, rxmax = int(height * ymax), int(width * xmax)
    crop_ymin, crop_xmin = max(0, rymin - 5), max(0, rxmin - 5)
    crop_ymax, crop_xmax = min(height, rymax + 5), min(width, rxmax + 5)

    # Full subtitle strip mask covering the exact inpaint_region [ymin:ymax, xmin:xmax]
    full_strip_mask = np.zeros((height, width), dtype=np.uint8)
    full_strip_mask[rymin:rymax, rxmin:rxmax] = 255

    # 2. Build Temporal Timeline of Segments for this chunk with Full Strip Mask & Safety Padding
    chunk_end_frame = start_frame + frame_count
    active_seg_info = []

    if segments:
        for seg in segments:
            s_sec = float(seg.get("start", 0.0))
            e_sec = float(seg.get("end", 0.0))

            # Temporal safety padding ±0.35s to activate inpaint before hardsub appears & end after it disappears
            sf = max(0, int((s_sec - 0.35) * fps))
            ef = int((e_sec + 0.35) * fps)

            # Check overlap with this worker's chunk
            if ef >= start_frame and sf < chunk_end_frame:
                active_seg_info.append({
                    "start_f": sf,
                    "end_f": ef,
                    "mask": full_strip_mask
                })

    # Seek to start_frame for actual chunk sequential decoding
    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(chunk_out_path, fourcc, fps, (width, height))

    processed = 0
    curr_frame_idx = start_frame

    # Fallback dynamic holding if no segments provided
    dynamic_held_mask = None
    dynamic_hold_counter = 0

    # Temporal EMA history for inpainting stabilization
    prev_inpainted_crop = None
    last_active_mask = None

    while processed < frame_count and cap.isOpened():
        ret, frame = cap.read()
        if not ret or frame is None:
            break

        current_mask = None

        if active_seg_info:
            # Find matching segment mask for current frame
            matching_masks = [s["mask"] for s in active_seg_info if s["start_f"] <= curr_frame_idx <= s["end_f"] and np.any(s["mask"] > 0)]
            if matching_masks:
                current_mask = matching_masks[0]
        else:
            # Dynamic scene change locking when segments are absent
            if dynamic_hold_counter > 0 and dynamic_held_mask is not None:
                current_mask = dynamic_held_mask
                dynamic_hold_counter -= 1
            else:
                m = _detect_text_mask_apple_vision(frame, enclosing_region)
                if np.any(m > 0):
                    dynamic_held_mask = full_strip_mask
                    dynamic_hold_counter = int(fps * 1.5)  # Lock mask for 1.5 seconds
                    current_mask = full_strip_mask
                else:
                    dynamic_held_mask = None
                    dynamic_hold_counter = 0

        # Perform Selected Inpainting Algorithm & Feathering
        if current_mask is not None and np.any(current_mask > 0):
            if inpaint_method == "vertical_gradient":
                # Ultra-flat, directional vertical interpolation: zero sword seams, zero yellow smears
                inpainted = _inpaint_vertical_gradient(frame, rymin, rymax, rxmin, rxmax)
            elif inpaint_method in ("navier_stokes", "ns"):
                # Fluid dynamics isophote flow
                inpainted = cv2.inpaint(frame, current_mask, inpaintRadius=5, flags=cv2.INPAINT_NS)
            else:
                # Telea Fast Marching
                inpainted = cv2.inpaint(frame, current_mask, inpaintRadius=5, flags=cv2.INPAINT_TELEA)

            # Temporal EMA Smoothing (blend with previous frame)
            if prev_inpainted_crop is not None and last_active_mask is not None and np.array_equal(current_mask, last_active_mask):
                curr_crop = inpainted[crop_ymin:crop_ymax, crop_xmin:crop_xmax]
                # 80% current frame + 20% previous frame to eliminate high-frequency pixel shimmer
                smoothed_crop = cv2.addWeighted(curr_crop, 0.80, prev_inpainted_crop, 0.20, 0)
                inpainted[crop_ymin:crop_ymax, crop_xmin:crop_xmax] = smoothed_crop
                prev_inpainted_crop = smoothed_crop
            else:
                prev_inpainted_crop = inpainted[crop_ymin:crop_ymax, crop_xmin:crop_xmax].copy()

            last_active_mask = current_mask

            # Soft Alpha Feathering (Gaussian Blur mask for ultra-smooth edge transitions)
            feather_mask = cv2.GaussianBlur(current_mask.astype(np.float32) / 255.0, (11, 11), 0)
            feather_3ch = np.dstack([feather_mask, feather_mask, feather_mask])

            final_frame = (frame.astype(np.float32) * (1.0 - feather_3ch) + inpainted.astype(np.float32) * feather_3ch).astype(np.uint8)
            out.write(final_frame)
        else:
            prev_inpainted_crop = None
            last_active_mask = None
            # Untouched frame for silent intervals: 100% pristine original video quality
            out.write(frame)

        processed += 1
        curr_frame_idx += 1

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

        inpaint_method = str(self.config.get("inpaint_method") or self.config.get("method") or "vertical_gradient").lower()

        # Check if OpenCV can open the video stream directly (HEVC/VP9/AV1 compatibility check)
        cap = cv2.VideoCapture(str(video_path))
        is_valid = cap.isOpened() and int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) > 0
        if is_valid:
            fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            cap.release()
        else:
            if cap.isOpened():
                cap.release()
            # Auto fallback: Transcode to lightweight standard H.264 YUV420p for 100% OpenCV compatibility
            compat_video = output_video.parent / "temp_h264_compat.mp4"
            cmd_compat = [
                "ffmpeg", "-y", "-i", str(video_path),
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "ultrafast",
                "-crf", "18",
                str(compat_video)
            ]
            subprocess.run(cmd_compat, capture_output=True, check=True)
            video_path = compat_video
            cap = cv2.VideoCapture(str(video_path))
            if not cap.isOpened():
                raise RuntimeError(f"Cannot open video for inpainting even after transcode: {video_path}")
            fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
            width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
            height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
            cap.release()

        from core.concurrency import ConcurrencyManager
        num_workers = ConcurrencyManager.get_num_workers(self.config) if hasattr(self, "config") else 4
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
                        height,
                        inpaint_method
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
