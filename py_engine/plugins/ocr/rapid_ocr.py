import os
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import cv2
import numpy as np

from plugins.interfaces import OCRBase

RAPID_OCR_AVAILABLE = False
try:
    from rapidocr_onnxruntime import RapidOCR
    RAPID_OCR_AVAILABLE = True
except Exception:
    RAPID_OCR_AVAILABLE = False


def _get_rapid_engine(config: Optional[Dict[str, Any]] = None) -> Any:
    """Instantiate RapidOCR with optional offline model path auto-discovery."""
    if not RAPID_OCR_AVAILABLE:
        raise RuntimeError(
            "RapidOCR is not installed. Run: pip install rapidocr-onnxruntime"
        )

    # Candidate directories for custom/offline ONNX models
    candidate_model_dirs = [
        Path("models/rapidocr"),
        Path("models/ocr"),
        Path.home() / ".rapidocr",
        Path.home() / ".cache" / "rapidocr",
    ]

    params: Dict[str, Any] = {}
    for m_dir in candidate_model_dirs:
        if m_dir.exists():
            det_file = m_dir / "ch_PP-OCRv4_det_infer.onnx"
            rec_file = m_dir / "ch_PP-OCRv4_rec_infer.onnx"
            if not det_file.exists():
                det_file = m_dir / "ch_PP-OCRv4_det.onnx"
            if not rec_file.exists():
                rec_file = m_dir / "ch_PP-OCRv4_rec.onnx"

            if det_file.exists():
                params["Det.model_path"] = str(det_file)
            if rec_file.exists():
                params["Rec.model_path"] = str(rec_file)
            if params:
                break

    try:
        if params:
            return RapidOCR(params=params)
        return RapidOCR()
    except Exception as e:
        # Fallback to default zero-param initialization
        return RapidOCR()


def _parse_rapid_result(
    result: Any,
    crop_w: int,
    crop_h: int,
    xmin: float,
    xmax: float,
    ymin: float,
    ymax: float,
) -> Tuple[List[str], List[Tuple[float, float, float, float]]]:
    """
    Parse RapidOCR result into extracted lines and normalized [ymin, xmin, ymax, xmax] boxes.
    RapidOCR returns list of [box, text, confidence], where box is [[x0, y0], [x1, y1], [x2, y2], [x3, y3]].
    """
    extracted_lines = []
    line_boxes = []

    if not result:
        return extracted_lines, line_boxes

    for item in result:
        if not isinstance(item, (list, tuple)) or len(item) < 2:
            continue

        box_pts = item[0]
        t_str = str(item[1]).strip() if item[1] is not None else ""
        if not t_str:
            continue

        confidence = float(item[2]) if len(item) > 2 and item[2] is not None else 1.0
        if confidence < 0.35:
            continue

        if hasattr(box_pts, "tolist"):
            box_pts = box_pts.tolist()

        if isinstance(box_pts, (list, tuple)) and len(box_pts) > 0:
            if isinstance(box_pts[0], (list, tuple)):
                xs = [float(p[0]) for p in box_pts]
                ys = [float(p[1]) for p in box_pts]
            else:
                xs = [float(box_pts[0]), float(box_pts[2])]
                ys = [float(box_pts[1]), float(box_pts[3])]

            bx_min = (min(xs) / crop_w) * (xmax - xmin) + xmin
            bx_max = (max(xs) / crop_w) * (xmax - xmin) + xmin
            by_min = (min(ys) / crop_h) * (ymax - ymin) + ymin
            by_max = (max(ys) / crop_h) * (ymax - ymin) + ymin

            line_boxes.append((by_min, bx_min, by_max, bx_max))
            extracted_lines.append(t_str)

    return extracted_lines, line_boxes


def _run_rapid_chunk_worker(args: Tuple[str, int, int, int, List[float], float]) -> List[Dict[str, Any]]:
    """Worker process running RapidOCR with frame diffing on a video chunk."""
    video_path_str, start_frame, end_frame, step, region, diff_threshold = args
    ymin, xmin, ymax, xmax = region if (region and len(region) == 4) else [0.10, 0.0, 0.95, 1.0]

    try:
        ocr = _get_rapid_engine()

        cap = cv2.VideoCapture(video_path_str)
        if not cap.isOpened():
            return []

        fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
        cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)

        segments = []
        frame_idx = start_frame
        current_text = None
        current_boxes = []
        segment_start_frame = start_frame
        prev_crop_gray = None
        last_chinese_items = []

        while cap.isOpened() and frame_idx < end_frame:
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
                    crop_gray = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
                    if prev_crop_gray is not None:
                        diff = float(np.mean(np.abs(crop_gray.astype(np.float32) - prev_crop_gray.astype(np.float32))))
                    else:
                        diff = 999.0
                    prev_crop_gray = crop_gray

                    if diff < diff_threshold and last_chinese_items:
                        chinese_items = last_chinese_items
                    else:
                        try:
                            res, _ = ocr(crop)
                        except Exception:
                            res = None

                        chinese_items = []
                        if res:
                            extracted_lines, line_boxes = _parse_rapid_result(
                                res, crop_w, crop_h, xmin, xmax, ymin, ymax
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
                                    "start": round(segment_start_frame / fps, 3),
                                    "end": round(frame_idx / fps, 3),
                                    "text": current_text,
                                    "bbox": [round(s_ymin, 3), round(s_xmin, 3), round(s_ymax, 3), round(s_xmax, 3)]
                                })
                            current_text = extracted_text
                            current_boxes = [primary_box]
                            segment_start_frame = frame_idx
                        else:
                            current_boxes.append(primary_box)
                    else:
                        if current_text and len(current_text) > 0:
                            s_ymin = max(0.0, min(b[0] for b in current_boxes)) if current_boxes else ymin
                            s_xmin = max(0.0, min(b[1] for b in current_boxes)) if current_boxes else xmin
                            s_ymax = min(1.0, max(b[2] for b in current_boxes)) if current_boxes else ymax
                            s_xmax = min(1.0, max(b[3] for b in current_boxes)) if current_boxes else xmax
                            segments.append({
                                "start": round(segment_start_frame / fps, 3),
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
                "start": round(segment_start_frame / fps, 3),
                "end": round(frame_idx / fps, 3),
                "text": current_text,
                "bbox": [round(s_ymin, 3), round(s_xmin, 3), round(s_ymax, 3), round(s_xmax, 3)]
            })

        return segments
    except Exception as e:
        print(f"[RapidOCR Worker] Exception on chunk {start_frame}-{end_frame}: {e}")
        return []


class Plugin(OCRBase):
    """
    RapidOCR Plugin using ONNX Runtime for ultra-fast, lightweight CPU text extraction.
    Native support for Windows x64 and cross-platform fallback.
    """

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        if not RAPID_OCR_AVAILABLE:
            print("[RapidOCR] WARNING: rapidocr-onnxruntime is not installed.")
            print("[RapidOCR] Run: pip install rapidocr-onnxruntime")

    def _resolve_num_workers(self) -> int:
        from core.concurrency import ConcurrencyManager
        return ConcurrencyManager.get_num_workers(self.config if hasattr(self, "config") else {})

    def extract_text(self, video_path: Path, region: List[float]) -> List[Dict[str, Any]]:
        """Extract text across the video without frame diff skip."""
        return self.extract_text_with_diff_skip(video_path, region, diff_threshold=999.0)

    def extract_text_with_diff_skip(
        self, video_path: Path, region: List[float], diff_threshold: float = 8.0
    ) -> List[Dict[str, Any]]:
        """
        Extract subtitles with frame differencing. Skips OCR on static subtitle frames to save 75%+ time.
        """
        num_workers = self._resolve_num_workers()

        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            return []

        fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        cap.release()

        step = max(1, int(fps / 2.0))

        if num_workers > 1 and total_frames > step * 10:
            print(f"[RapidOCR Multi-core] Fast OCR with {num_workers} CPU workers (diff_threshold={diff_threshold})...", flush=True)
            chunk_size = total_frames // num_workers
            tasks = []
            for i in range(num_workers):
                s_frame = i * chunk_size
                e_frame = total_frames if i == num_workers - 1 else (i + 1) * chunk_size
                tasks.append((str(video_path), s_frame, e_frame, step, region, diff_threshold))

            all_segments = []
            with ProcessPoolExecutor(max_workers=num_workers) as executor:
                results = list(executor.map(_run_rapid_chunk_worker, tasks))
                for res in results:
                    all_segments.extend(res)

            all_segments.sort(key=lambda s: s.get("start", 0.0))
            print(f"[RapidOCR Multi-core] Fast OCR complete: extracted {len(all_segments)} segments across {num_workers} workers.")
            return all_segments

        return _run_rapid_chunk_worker((str(video_path), 0, total_frames, step, region, diff_threshold))

    def extract_text_for_region_detect(
        self, video_path: Path, region: List[float], max_seconds: float = 10.0, min_hits: int = 5
    ) -> List[Dict[str, Any]]:
        """
        Fast 1fps early-exit scan of the first N seconds to detect subtitle region bounds.
        """
        ymin, xmin, ymax, xmax = region if (region and len(region) == 4) else [0.10, 0.0, 0.95, 1.0]

        try:
            ocr = _get_rapid_engine(self.config if hasattr(self, "config") else None)

            cap = cv2.VideoCapture(str(video_path))
            if not cap.isOpened():
                return []

            fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
            total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
            max_frames = int(max_seconds * fps)
            step = max(1, int(fps))

            print(f"[RapidOCR] Region detect: scanning first {max_seconds:.0f}s ({min(max_frames, total_frames)} frames @ 1fps)...", flush=True)

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
                            res, _ = ocr(crop)
                        except Exception:
                            res = None

                        if res:
                            extracted_lines, line_boxes = _parse_rapid_result(
                                res, crop_w, crop_h, xmin, xmax, ymin, ymax
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
                                print(f"[RapidOCR] Region hit {hits}/{min_hits} @ {t_sec:.1f}s: bbox={[round(b, 3) for b in primary_box]}", flush=True)
                                if hits >= min_hits:
                                    print(f"[RapidOCR] Region detect complete: {hits} hits found, stopping early.", flush=True)
                                    break

                frame_idx += 1

            cap.release()
            print(f"[RapidOCR] Region detect finished: {len(segments)} detections.")
            return segments

        except Exception as e:
            print(f"[RapidOCR] Region detect exception: {e}")
            return []

    def extract_text_keyframes(
        self, video_path: Path, region: List[float], asr_segments: List[Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
        """Extract text at timestamps guided by ASR speech segments."""
        ymin, xmin, ymax, xmax = region if region else [0.8, 0.0, 1.0, 1.0]
        try:
            ocr = _get_rapid_engine(self.config if hasattr(self, "config") else None)

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
                    res, _ = ocr(crop)
                except Exception:
                    res = None

                if res:
                    extracted_lines, line_boxes = _parse_rapid_result(
                        res, crop_w, crop_h, xmin, xmax, ymin, ymax
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
            print(f"[RapidOCR Keyframe] Exception: {e}")
            return []
