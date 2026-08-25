import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple
import cv2
import numpy as np

from plugins.interfaces import OCRBase

# Check availability of macOS Apple Vision framework
APPLE_VISION_AVAILABLE = False
try:
    if sys.platform == "darwin":
        import Quartz
        import Vision
        APPLE_VISION_AVAILABLE = True
except Exception:
    APPLE_VISION_AVAILABLE = False


def _parse_vision_results(
    results: Any,
    crop_w: int,
    crop_h: int,
    xmin: float,
    xmax: float,
    ymin: float,
    ymax: float
) -> Tuple[List[str], List[Tuple[float, float, float, float]]]:
    """
    Parses VNRecognizedTextObservation list into extracted lines and normalized bounding boxes [ymin, xmin, ymax, xmax].
    Apple Vision uses bottom-left normalized origin for bounding boxes.
    """
    extracted_lines = []
    line_boxes = []

    if not results:
        return extracted_lines, line_boxes

    for obs in results:
        try:
            candidates = obs.topCandidates_(1)
            if not candidates or len(candidates) == 0:
                continue
            text = str(candidates[0].string()).strip()
            if not text:
                continue
            extracted_lines.append(text)

            # Convert Vision normalized bounding box (bottom-left origin) to top-left origin
            v_box = obs.boundingBox()
            vx, vy, vw, vh = v_box.origin.x, v_box.origin.y, v_box.size.width, v_box.size.height

            # Map crop-relative coordinates to full image relative coordinates
            by_min_crop = 1.0 - (vy + vh)
            by_max_crop = 1.0 - vy
            bx_min_crop = vx
            bx_max_crop = vx + vw

            by_min = by_min_crop * (ymax - ymin) + ymin
            by_max = by_max_crop * (ymax - ymin) + ymin
            bx_min = bx_min_crop * (xmax - xmin) + xmin
            bx_max = bx_max_crop * (xmax - xmin) + xmin

            line_boxes.append((by_min, bx_min, by_max, bx_max))
        except Exception:
            continue

    return extracted_lines, line_boxes


def _create_cg_image_from_crop(crop_bgr: np.ndarray):
    """Converts OpenCV BGR crop array to macOS CGImage for Vision framework processing."""
    import Quartz

    crop_rgb = cv2.cvtColor(crop_bgr, cv2.COLOR_BGR2RGB)
    h, w, c = crop_rgb.shape
    bytes_per_row = c * w
    color_space = Quartz.CGColorSpaceCreateDeviceRGB()
    data = crop_rgb.tobytes()
    provider = Quartz.CGDataProviderCreateWithData(None, data, len(data), None)
    cg_image = Quartz.CGImageCreate(
        w, h, 8, 24, bytes_per_row, color_space,
        Quartz.kCGImageAlphaNone, provider, None, False,
        Quartz.kCGRenderingIntentDefault
    )
    return cg_image, w, h


class Plugin(OCRBase):
    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        if not APPLE_VISION_AVAILABLE:
            print("[AppleVision] WARNING: Apple Vision API is only available on macOS with pyobjc-framework-Vision installed.")
            print("[AppleVision] Run: pip install pyobjc-framework-Vision pyobjc-framework-Quartz")

    def _ocr_crop(self, crop: np.ndarray, xmin: float, xmax: float, ymin: float, ymax: float):
        """Performs fast Apple Vision OCR on a cropped OpenCV BGR frame."""
        import Vision

        crop_h, crop_w = crop.shape[:2]
        if crop_h == 0 or crop_w == 0:
            return [], []

        try:
            cg_image, w, h = _create_cg_image_from_crop(crop)
            handler = Vision.VNImageRequestHandler.alloc().initWithCGImage_options_(cg_image, None)

            req = Vision.VNRecognizeTextRequest.alloc().init()
            req.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
            req.setUsesLanguageCorrection_(True)
            try:
                req.setRecognitionLanguages_(["zh-Hans", "zh-Hant", "en-US", "vi-VN"])
            except Exception:
                pass

            success, err = handler.performRequests_error_([req], None)
            if not success or err is not None:
                return [], []

            results = req.results()
            return _parse_vision_results(results, crop_w, crop_h, xmin, xmax, ymin, ymax)
        except Exception as e:
            return [], []

    def extract_text(self, video_path: Path, region: List[float]) -> List[Dict[str, Any]]:
        if not APPLE_VISION_AVAILABLE:
            raise RuntimeError("Apple Vision framework is not available on this platform.")

        ymin, xmin, ymax, xmax = region if (region and len(region) == 4) else [0.15, 0.0, 0.98, 1.0]

        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            print(f"[AppleVision] Cannot open video: {video_path}")
            return []

        fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        step = max(1, int(fps / 2.0))  # 2fps sampling

        print(f"[AppleVision] GPU/ANE Text Extraction: {total_frames} frames @ 2fps...", flush=True)

        segments = []
        frame_idx = 0
        current_text = None
        current_boxes = []
        start_frame = 0

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret or frame is None:
                break

            if frame_idx % step == 0:
                h, w = frame.shape[:2]
                crop_y1, crop_y2 = int(h * ymin), int(h * ymax)
                crop_x1, crop_x2 = int(w * xmin), int(w * xmax)
                crop = frame[crop_y1:crop_y2, crop_x1:crop_x2]

                extracted_lines, line_boxes = self._ocr_crop(crop, xmin, xmax, ymin, ymax)

                chinese_items = []
                for t_str, b_box in zip(extracted_lines, line_boxes):
                    t_str = t_str.strip()
                    has_chinese = any(0x4e00 <= ord(c) <= 0x9fff for c in t_str)
                    box_w = b_box[3] - b_box[1]
                    char_count = sum(1 for c in t_str if 0x4e00 <= ord(c) <= 0x9fff)
                    if char_count == 1 and box_w < 0.03:
                        continue
                    if (b_box[1] > 0.70 or b_box[3] < 0.25) and box_w < 0.25:
                        continue
                    if has_chinese or len(t_str) >= 4:
                        chinese_items.append((t_str, b_box))

                if chinese_items:
                    primary_item = max(chinese_items, key=lambda item: item[1][3] - item[1][1])
                    main_items = [item for item in chinese_items if abs(item[1][0] - primary_item[1][0]) < 0.05]
                    extracted_text = " ".join(item[0] for item in main_items)
                    primary_box = primary_item[1]

                    if extracted_text != current_text:
                        if current_text and len(current_text) > 0:
                            s_ymin = max(0.0, min(b[0] for b in current_boxes)) if current_boxes else ymin
                            s_xmin = max(0.0, min(b[1] for b in current_boxes)) if current_boxes else xmin
                            s_ymax = min(1.0, max(b[2] for b in current_boxes)) if current_boxes else ymax
                            s_xmax = min(1.0, max(b[3] for b in current_boxes)) if current_boxes else xmax
                            segments.append({
                                "start": round(start_frame / fps, 3),
                                "end": round(frame_idx / fps, 3),
                                "text": current_text,
                                "bbox": [round(s_ymin, 3), round(s_xmin, 3), round(s_ymax, 3), round(s_xmax, 3)]
                            })
                        current_text = extracted_text
                        current_boxes = [primary_box]
                        start_frame = frame_idx
                    else:
                        current_boxes.append(primary_box)

            frame_idx += 1

        cap.release()

        if current_text and len(current_text) > 0:
            s_ymin = max(0.0, min(b[0] for b in current_boxes)) if current_boxes else ymin
            s_xmin = max(0.0, min(b[1] for b in current_boxes)) if current_boxes else xmin
            s_ymax = min(1.0, max(b[2] for b in current_boxes)) if current_boxes else ymax
            s_xmax = min(1.0, max(b[3] for b in current_boxes)) if current_boxes else xmax
            segments.append({
                "start": round(start_frame / fps, 3),
                "end": round(frame_idx / fps, 3),
                "text": current_text,
                "bbox": [round(s_ymin, 3), round(s_xmin, 3), round(s_ymax, 3), round(s_xmax, 3)]
            })

        print(f"[AppleVision] Extracted {len(segments)} text segments via macOS Neural Engine.")
        return segments

    def extract_text_for_region_detect(self, video_path: Path, region: List[float], max_seconds: float = 10.0, min_hits: int = 5) -> List[Dict[str, Any]]:
        """Fast region detection for s03 using Apple Vision OCR."""
        if not APPLE_VISION_AVAILABLE:
            return []

        ymin, xmin, ymax, xmax = region if (region and len(region) == 4) else [0.10, 0.0, 0.95, 1.0]

        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            return []

        fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        max_frames = int(max_seconds * fps)
        step = max(1, int(fps))  # 1fps sampling

        print(f"[AppleVision] Region detect: scanning first {max_seconds:.0f}s via Apple Neural Engine...", flush=True)

        segments = []
        frame_idx = 0
        hits = 0

        while cap.isOpened() and frame_idx <= max_frames:
            ret, frame = cap.read()
            if not ret or frame is None:
                break

            if frame_idx % step == 0:
                h, w = frame.shape[:2]
                crop_y1, crop_y2 = int(h * ymin), int(h * ymax)
                crop_x1, crop_x2 = int(w * xmin), int(w * xmax)
                crop = frame[crop_y1:crop_y2, crop_x1:crop_x2]

                extracted_lines, line_boxes = self._ocr_crop(crop, xmin, xmax, ymin, ymax)

                chinese_items = []
                for t_str, b_box in zip(extracted_lines, line_boxes):
                    t_str = t_str.strip()
                    has_chinese = any(0x4e00 <= ord(c) <= 0x9fff for c in t_str)
                    box_w = b_box[3] - b_box[1]
                    char_count = sum(1 for c in t_str if 0x4e00 <= ord(c) <= 0x9fff)
                    if char_count == 1 and box_w < 0.03:
                        continue
                    if has_chinese or len(t_str) >= 4:
                        chinese_items.append((t_str, b_box))

                if chinese_items:
                    primary_item = max(chinese_items, key=lambda item: item[1][3] - item[1][1])
                    primary_box = primary_item[1]
                    t_sec = frame_idx / fps
                    segments.append({
                        "start": round(t_sec, 3),
                        "end": round(t_sec + 1.0, 3),
                        "text": primary_item[0],
                        "bbox": [round(b, 3) for b in primary_box]
                    })
                    hits += 1
                    print(f"[AppleVision] Region hit {hits}/{min_hits} @ {t_sec:.1f}s: bbox={[round(b,3) for b in primary_box]}", flush=True)
                    if hits >= min_hits:
                        print(f"[AppleVision] Region detect complete: {hits} hits found, stopping early.", flush=True)
                        break

            frame_idx += 1

        cap.release()
        print(f"[AppleVision] Region detect finished: {len(segments)} detections.")
        return segments

    def extract_text_with_diff_skip(self, video_path: Path, region: List[float], diff_threshold: float = 8.0) -> List[Dict[str, Any]]:
        """Full-video OCR for s06 using Apple Vision OCR with diff-skip."""
        if not APPLE_VISION_AVAILABLE:
            return []

        ymin, xmin, ymax, xmax = region if (region and len(region) == 4) else [0.10, 0.0, 0.95, 1.0]

        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            return []

        fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        step = max(1, int(fps / 2.0))

        print(f"[AppleVision] Fast OCR (Apple GPU/ANE): {total_frames} frames @ 2fps + diff-skip...", flush=True)

        segments = []
        frame_idx = 0
        current_text = None
        current_boxes = []
        start_frame = 0
        prev_crop_gray = None
        ocr_calls = 0
        skipped_calls = 0
        last_chinese_items = []

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret or frame is None:
                break

            if frame_idx % step == 0:
                h, w = frame.shape[:2]
                crop_y1, crop_y2 = int(h * ymin), int(h * ymax)
                crop_x1, crop_x2 = int(w * xmin), int(w * xmax)
                crop = frame[crop_y1:crop_y2, crop_x1:crop_x2]
                crop_h, crop_w = crop.shape[:2]

                if crop_h == 0 or crop_w == 0:
                    frame_idx += 1
                    continue

                crop_gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
                if prev_crop_gray is not None:
                    diff = float(np.mean(np.abs(crop_gray.astype(np.float32) - prev_crop_gray.astype(np.float32))))
                else:
                    diff = 999.0
                prev_crop_gray = crop_gray

                if diff < diff_threshold:
                    skipped_calls += 1
                    chinese_items = last_chinese_items
                else:
                    ocr_calls += 1
                    extracted_lines, line_boxes = self._ocr_crop(crop, xmin, xmax, ymin, ymax)
                    chinese_items = []
                    for t_str, b_box in zip(extracted_lines, line_boxes):
                        t_str = t_str.strip()
                        has_chinese = any(0x4e00 <= ord(c) <= 0x9fff for c in t_str)
                        box_w = b_box[3] - b_box[1]
                        char_count = sum(1 for c in t_str if 0x4e00 <= ord(c) <= 0x9fff)
                        if char_count == 1 and box_w < 0.03:
                            continue
                        if (b_box[1] > 0.70 or b_box[3] < 0.25) and box_w < 0.25:
                            continue
                        if has_chinese or len(t_str) >= 4:
                            chinese_items.append((t_str, b_box))
                    last_chinese_items = chinese_items

                if chinese_items:
                    primary_item = max(chinese_items, key=lambda item: item[1][3] - item[1][1])
                    main_items = [item for item in chinese_items if abs(item[1][0] - primary_item[1][0]) < 0.05]
                    extracted_text = " ".join(item[0] for item in main_items)
                    primary_box = primary_item[1]

                    if extracted_text != current_text:
                        if current_text and len(current_text) > 0:
                            s_ymin = max(0.0, min(b[0] for b in current_boxes)) if current_boxes else ymin
                            s_xmin = max(0.0, min(b[1] for b in current_boxes)) if current_boxes else xmin
                            s_ymax = min(1.0, max(b[2] for b in current_boxes)) if current_boxes else ymax
                            s_xmax = min(1.0, max(b[3] for b in current_boxes)) if current_boxes else xmax
                            segments.append({
                                "start": round(start_frame / fps, 3),
                                "end": round(frame_idx / fps, 3),
                                "text": current_text,
                                "bbox": [round(s_ymin, 3), round(s_xmin, 3), round(s_ymax, 3), round(s_xmax, 3)]
                            })
                        current_text = extracted_text
                        current_boxes = [primary_box]
                        start_frame = frame_idx
                    else:
                        current_boxes.append(primary_box)
                else:
                    if current_text and len(current_text) > 0:
                        s_ymin = max(0.0, min(b[0] for b in current_boxes)) if current_boxes else ymin
                        s_xmin = max(0.0, min(b[1] for b in current_boxes)) if current_boxes else xmin
                        s_ymax = min(1.0, max(b[2] for b in current_boxes)) if current_boxes else ymax
                        s_xmax = min(1.0, max(b[3] for b in current_boxes)) if current_boxes else xmax
                        segments.append({
                            "start": round(start_frame / fps, 3),
                            "end": round(frame_idx / fps, 3),
                            "text": current_text,
                            "bbox": [round(s_ymin, 3), round(s_xmin, 3), round(s_ymax, 3), round(s_xmax, 3)]
                        })
                        current_text = None
                        current_boxes = []
                        last_chinese_items = []

            frame_idx += 1

        cap.release()

        if current_text and len(current_text) > 0:
            s_ymin = max(0.0, min(b[0] for b in current_boxes)) if current_boxes else ymin
            s_xmin = max(0.0, min(b[1] for b in current_boxes)) if current_boxes else xmin
            s_ymax = min(1.0, max(b[2] for b in current_boxes)) if current_boxes else ymax
            s_xmax = min(1.0, max(b[3] for b in current_boxes)) if current_boxes else xmax
            segments.append({
                "start": round(start_frame / fps, 3),
                "end": round(frame_idx / fps, 3),
                "text": current_text,
                "bbox": [round(s_ymin, 3), round(s_xmin, 3), round(s_ymax, 3), round(s_xmax, 3)]
            })

        print(f"[AppleVision] GPU/ANE OCR complete: {len(segments)} segments | Vision calls: {ocr_calls} (skipped: {skipped_calls})")
        return segments

    def extract_text_keyframes(self, video_path: Path, region: List[float], asr_segments: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Keyframe guided OCR using Apple Vision API."""
        if not APPLE_VISION_AVAILABLE:
            return []

        ymin, xmin, ymax, xmax = region if region else [0.8, 0.0, 1.0, 1.0]
        cap = cv2.VideoCapture(str(video_path))
        fps = cap.get(cv2.CAP_PROP_FPS) or 24.0

        results = []
        for seg in asr_segments:
            s_start = float(seg.get("start", 0.0))
            target_sec = s_start + 0.3
            target_frame = int(target_sec * fps)

            cap.set(cv2.CAP_PROP_POS_FRAMES, target_frame)
            ret, frame = cap.read()
            if not ret or frame is None:
                continue

            h, w = frame.shape[:2]
            crop_y1, crop_y2 = int(h * ymin), int(h * ymax)
            crop_x1, crop_x2 = int(w * xmin), int(w * xmax)
            crop = frame[crop_y1:crop_y2, crop_x1:crop_x2]

            extracted_lines, line_boxes = self._ocr_crop(crop, xmin, xmax, ymin, ymax)
            if line_boxes:
                s_ymin = max(0.0, min(b[0] for b in line_boxes))
                s_xmin = max(0.0, min(b[1] for b in line_boxes))
                s_ymax = min(1.0, max(b[2] for b in line_boxes))
                s_xmax = min(1.0, max(b[3] for b in line_boxes))
                bbox = [round(s_ymin, 3), round(s_xmin, 3), round(s_ymax, 3), round(s_xmax, 3)]
            else:
                bbox = [round(ymin, 3), round(xmin, 3), round(ymax, 3), round(xmax, 3)]

            res_seg = dict(seg)
            res_seg["bbox"] = bbox
            if extracted_lines:
                res_seg["ocr_text"] = " ".join(extracted_lines)
            results.append(res_seg)

        cap.release()
        return results
