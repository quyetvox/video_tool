from pathlib import Path
from typing import Any, Dict, List, Tuple

import cv2

from plugins.interfaces import OCRBase


def _parse_ocr_item(
    item: Any,
    crop_w: int,
    crop_h: int,
    xmin: float,
    xmax: float,
    ymin: float,
    ymax: float
) -> Tuple[List[str], List[Tuple[float, float, float, float]]]:
    extracted_lines = []
    line_boxes = []

    rec_texts = None
    dt_polys = None

    if isinstance(item, dict):
        rec_texts = item.get("rec_texts")
        dt_polys = item.get("dt_polys") or item.get("rec_boxes")
    elif hasattr(item, "get"):
        try:
            rec_texts = item.get("rec_texts")
            dt_polys = item.get("dt_polys") or item.get("rec_boxes")
        except Exception:
            pass
    elif hasattr(item, "rec_texts"):
        rec_texts = getattr(item, "rec_texts", None)
        dt_polys = getattr(item, "dt_polys", None) or getattr(item, "rec_boxes", None)

    if rec_texts is not None and len(rec_texts) > 0:
        for idx, text_val in enumerate(rec_texts):
            t_str = str(text_val).strip() if text_val is not None else ""
            if not t_str:
                continue
            extracted_lines.append(t_str)

            if dt_polys is not None and idx < len(dt_polys):
                poly = dt_polys[idx]
                if hasattr(poly, "tolist"):
                    poly = poly.tolist()
                if isinstance(poly, (list, tuple)) and len(poly) > 0:
                    if isinstance(poly[0], (list, tuple)):
                        xs = [float(p[0]) for p in poly]
                        ys = [float(p[1]) for p in poly]
                    else:
                        xs = [float(poly[0]), float(poly[2])]
                        ys = [float(poly[1]), float(poly[3])]
                    bx_min = (min(xs) / crop_w) * (xmax - xmin) + xmin
                    bx_max = (max(xs) / crop_w) * (xmax - xmin) + xmin
                    by_min = (min(ys) / crop_h) * (ymax - ymin) + ymin
                    by_max = (max(ys) / crop_h) * (ymax - ymin) + ymin
                    line_boxes.append((by_min, bx_min, by_max, bx_max))

    elif isinstance(item, (list, tuple)):
        for line in item:
            if not isinstance(line, (list, tuple)) or len(line) < 2:
                continue
            box_pts = line[0]
            txt_info = line[1]
            t_str = str(txt_info[0]).strip() if isinstance(txt_info, (list, tuple)) else str(txt_info).strip()
            if not t_str:
                continue
            extracted_lines.append(t_str)

            if hasattr(box_pts, "tolist"):
                box_pts = box_pts.tolist()
            if isinstance(box_pts, (list, tuple)) and len(box_pts) > 0:
                xs = [float(p[0]) for p in box_pts]
                ys = [float(p[1]) for p in box_pts]
                bx_min = (min(xs) / crop_w) * (xmax - xmin) + xmin
                bx_max = (max(xs) / crop_w) * (xmax - xmin) + xmin
                by_min = (min(ys) / crop_h) * (ymax - ymin) + ymin
                by_max = (max(ys) / crop_h) * (ymax - ymin) + ymin
                line_boxes.append((by_min, bx_min, by_max, bx_max))

    return extracted_lines, line_boxes


class Plugin(OCRBase):
    def extract_text(self, video_path: Path, region: List[float]) -> List[Dict[str, Any]]:
        # ymin, xmin, ymax, xmax relative (0.0 to 1.0)
        ymin, xmin, ymax, xmax = region if (region and len(region) == 4) else [0.15, 0.0, 0.98, 1.0]

        try:
            from paddleocr import PaddleOCR
            try:
                ocr = PaddleOCR(use_doc_orientation_classify=False, use_doc_unwarping=False, lang='ch')
            except Exception:
                ocr = PaddleOCR(lang='ch')

            cap = cv2.VideoCapture(str(video_path))
            if not cap.isOpened():
                print(f"[PaddleOCR] Cannot open video: {video_path}")
                return []

            fps = cap.get(cv2.CAP_PROP_FPS) or 24.0

            segments = []
            frame_idx = 0
            current_text = None
            # Sample ~2 frames per second for high accuracy and fast processing
            step = max(1, int(fps / 2.0))
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
            print(f"[PaddleOCR] Starting text extraction on video ({total_frames} total frames, ~2fps sampling)...", flush=True)

            while cap.isOpened():
                ret, frame = cap.read()
                if not ret or frame is None:
                    break

                if frame_idx % step == 0:
                    if total_frames > 0:
                        pct = (frame_idx / total_frames) * 100.0
                        sec = frame_idx / fps
                        print(f"[PaddleOCR] Processing video frame {frame_idx}/{total_frames} ({pct:.0f}% | {sec:.1f}s)...", flush=True)
                    else:
                        print(f"[PaddleOCR] Processing frame {frame_idx}...", flush=True)

                    h, w = frame.shape[:2]
                    crop_y1, crop_y2 = int(h * ymin), int(h * ymax)
                    crop_x1, crop_x2 = int(w * xmin), int(w * xmax)
                    crop = frame[crop_y1:crop_y2, crop_x1:crop_x2]

                    crop_h, crop_w = crop.shape[:2]

                    if crop_h > 0 and crop_w > 0:
                        try:
                            res = ocr.ocr(crop)
                        except Exception as err:
                            res = None

                        if res is not None and len(res) > 0 and res[0] is not None:
                            extracted_lines, line_boxes = _parse_ocr_item(
                                res[0], crop_w, crop_h, xmin, xmax, ymin, ymax
                            )
                            
                            # Filter Chinese subtitle lines only (exclude tiny 1-char background noise and side packaging text)
                            chinese_items = []
                            for t_str, b_box in zip(extracted_lines, line_boxes):
                                t_str = t_str.strip()
                                has_chinese = any(0x4e00 <= ord(c) <= 0x9fff for c in t_str)
                                box_w = b_box[3] - b_box[1]
                                char_count = sum(1 for c in t_str if 0x4e00 <= ord(c) <= 0x9fff)

                                # Ignore 1-char tiny noise boxes (width < 3%)
                                if char_count == 1 and box_w < 0.03:
                                    continue
                                # Ignore small side packaging text on far right/left (xmin > 0.70 or xmax < 0.25 with width < 25%)
                                if (b_box[1] > 0.70 or b_box[3] < 0.25) and box_w < 0.25:
                                    continue

                                if has_chinese or len(t_str) >= 4:
                                    chinese_items.append((t_str, b_box))

                            if chinese_items:
                                # Primary subtitle line is the widest line among Chinese items
                                primary_item = max(chinese_items, key=lambda item: item[1][3] - item[1][1])
                                # Use primary subtitle text (or join items centered on main area)
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

            print(f"[PaddleOCR] Extracted {len(segments)} text segments from video.")
            return segments

        except Exception as e:
            print(f"[PaddleOCR] Exception during text extraction: {e}")
            return []

    def extract_text_for_region_detect(self, video_path: Path, region: List[float], max_seconds: float = 10.0, min_hits: int = 5) -> List[Dict[str, Any]]:
        """
        Fast version for s03 region detection only.
        Scans at ~1fps for the first `max_seconds` seconds.
        Early-exits once `min_hits` consistent subtitle detections are found.
        """
        ymin, xmin, ymax, xmax = region if (region and len(region) == 4) else [0.10, 0.0, 0.95, 1.0]

        try:
            from paddleocr import PaddleOCR
            try:
                ocr = PaddleOCR(use_doc_orientation_classify=False, use_doc_unwarping=False, lang='ch')
            except Exception:
                ocr = PaddleOCR(lang='ch')

            cap = cv2.VideoCapture(str(video_path))
            if not cap.isOpened():
                return []

            fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
            max_frames = int(max_seconds * fps)
            # Sample 1 frame per second (fast)
            step = max(1, int(fps))

            print(f"[PaddleOCR] Region detect: scanning first {max_seconds:.0f}s ({min(max_frames, total_frames)} frames @ 1fps)...", flush=True)

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
                    crop_h, crop_w = crop.shape[:2]

                    if crop_h > 0 and crop_w > 0:
                        try:
                            res = ocr.ocr(crop)
                        except Exception:
                            res = None

                        if res is not None and len(res) > 0 and res[0] is not None:
                            extracted_lines, line_boxes = _parse_ocr_item(
                                res[0], crop_w, crop_h, xmin, xmax, ymin, ymax
                            )
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
                                print(f"[PaddleOCR] Region hit {hits}/{min_hits} @ {t_sec:.1f}s: bbox={[round(b,3) for b in primary_box]}", flush=True)
                                if hits >= min_hits:
                                    print(f"[PaddleOCR] Region detect complete: {hits} hits found, stopping early.", flush=True)
                                    break

                frame_idx += 1

            cap.release()
            print(f"[PaddleOCR] Region detect finished: {len(segments)} detections in first {max_seconds:.0f}s.")
            return segments

        except Exception as e:
            print(f"[PaddleOCR] Region detect exception: {e}")
            return []

    def extract_text_with_diff_skip(self, video_path: Path, region: List[float], diff_threshold: float = 8.0) -> List[Dict[str, Any]]:
        """
        Full-video OCR for s06, optimised with two techniques:
        1. Narrow crop: only processes the known burnin_region (smaller image → faster OCR).
        2. Frame-diff skip: skips OCR when the crop hasn't changed vs previous frame
           (subtitles stay static for 2-5 s, so 70-80 % of 2fps samples are identical).
        """
        ymin, xmin, ymax, xmax = region if (region and len(region) == 4) else [0.10, 0.0, 0.95, 1.0]

        try:
            from paddleocr import PaddleOCR
            import numpy as np
            try:
                ocr = PaddleOCR(use_doc_orientation_classify=False, use_doc_unwarping=False, lang='ch')
            except Exception:
                ocr = PaddleOCR(lang='ch')

            cap = cv2.VideoCapture(str(video_path))
            if not cap.isOpened():
                return []

            fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
            # 2fps sampling (same quality as before)
            step = max(1, int(fps / 2.0))

            print(f"[PaddleOCR] Fast OCR: {total_frames} frames @ 2fps sampling + diff-skip (region Y={ymin:.2f}-{ymax:.2f})...", flush=True)

            segments = []
            frame_idx = 0
            current_text = None
            current_boxes = []
            start_frame = 0
            prev_crop_gray = None
            ocr_calls = 0
            skipped_calls = 0
            last_chinese_items = []   # reuse last OCR result when frame is identical

            while cap.isOpened():
                ret, frame = cap.read()
                if not ret or frame is None:
                    break

                if frame_idx % step == 0:
                    if total_frames > 0 and (frame_idx % (step * 5) == 0):
                        pct = (frame_idx / total_frames) * 100.0
                        sec = frame_idx / fps
                        print(f"[PaddleOCR] Fast OCR processing frame {frame_idx}/{total_frames} ({pct:.0f}% | {sec:.1f}s)...", flush=True)

                    h, w = frame.shape[:2]
                    crop_y1, crop_y2 = int(h * ymin), int(h * ymax)
                    crop_x1, crop_x2 = int(w * xmin), int(w * xmax)
                    crop = frame[crop_y1:crop_y2, crop_x1:crop_x2]
                    crop_h, crop_w = crop.shape[:2]

                    if crop_h == 0 or crop_w == 0:
                        frame_idx += 1
                        continue

                    # Frame diff: compare mean absolute difference of grayscale crop
                    crop_gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
                    if prev_crop_gray is not None:
                        diff = float(np.mean(np.abs(crop_gray.astype(np.float32) - prev_crop_gray.astype(np.float32))))
                    else:
                        diff = 999.0  # first frame: always run OCR
                    prev_crop_gray = crop_gray

                    if diff < diff_threshold:
                        # Frame unchanged — reuse last OCR result
                        skipped_calls += 1
                        chinese_items = last_chinese_items
                    else:
                        # Frame changed — run OCR
                        ocr_calls += 1
                        try:
                            res = ocr.ocr(crop)
                        except Exception:
                            res = None

                        chinese_items = []
                        if res is not None and len(res) > 0 and res[0] is not None:
                            extracted_lines, line_boxes = _parse_ocr_item(
                                res[0], crop_w, crop_h, xmin, xmax, ymin, ymax
                            )
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
                        # No subtitle in this frame
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

            print(f"[PaddleOCR] Fast OCR done: {len(segments)} segments | OCR calls: {ocr_calls} (skipped: {skipped_calls} via diff)")
            return segments

        except Exception as e:
            print(f"[PaddleOCR] Fast OCR exception: {e}")
            return []

    def extract_text_keyframes(self, video_path: Path, region: List[float], asr_segments: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        ymin, xmin, ymax, xmax = region if region else [0.8, 0.0, 1.0, 1.0]
        try:
            from paddleocr import PaddleOCR
            try:
                ocr = PaddleOCR(use_doc_orientation_classify=False, use_doc_unwarping=False, lang='ch')
            except Exception:
                ocr = PaddleOCR(lang='ch')

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

                crop_h, crop_w = crop.shape[:2]
                if crop_h == 0 or crop_w == 0:
                    continue

                try:
                    res = ocr.ocr(crop)
                except Exception:
                    res = None

                if res is not None and len(res) > 0 and res[0] is not None:
                    extracted_lines, line_boxes = _parse_ocr_item(
                        res[0], crop_w, crop_h, xmin, xmax, ymin, ymax
                    )
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
        except Exception as e:
            print(f"[PaddleOCR Keyframe] Exception: {e}")
            return []
