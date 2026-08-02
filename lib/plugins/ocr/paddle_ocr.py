from pathlib import Path
from typing import Any, Dict, List

import cv2

from plugins.interfaces import OCRBase


class Plugin(OCRBase):
    def extract_text(self, video_path: Path, region: List[float]) -> List[Dict[str, Any]]:
        # ymin, xmin, ymax, xmax relative
        ymin, xmin, ymax, xmax = region if region else [0.8, 0.0, 1.0, 1.0]

        try:
            from paddleocr import PaddleOCR
            try:
                ocr = PaddleOCR(use_textline_orientation=True, lang='ch')
            except Exception:
                try:
                    ocr = PaddleOCR(use_angle_cls=True, lang='ch')
                except Exception:
                    ocr = PaddleOCR(lang='ch')
            
            cap = cv2.VideoCapture(str(video_path))
            fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
            
            segments = []
            frame_idx = 0
            current_text = None
            current_boxes = []
            start_frame = 0
            
            # Step every 5 frames for OCR efficiency
            step = 5
            while cap.isOpened():
                ret, frame = cap.read()
                if not ret:
                    break
                
                if frame_idx % step == 0:
                    h, w = frame.shape[:2]
                    crop = frame[int(h*ymin):int(h*ymax), int(w*xmin):int(w*xmax)]
                    
                    try:
                        result = ocr.ocr(crop, cls=True)
                    except Exception:
                        result = ocr.ocr(crop)
                    extracted_lines = []
                    line_boxes = []
                    h, w = frame.shape[:2]
                    crop_y1, crop_y2 = int(h*ymin), int(h*ymax)
                    crop_x1, crop_x2 = int(w*xmin), int(w*xmax)
                    crop = frame[crop_y1:crop_y2, crop_x1:crop_x2]
                    crop_h, crop_w = crop.shape[:2]

                    if crop_h > 0 and crop_w > 0:
                        try:
                            result = ocr.ocr(crop, cls=True)
                        except Exception:
                            result = ocr.ocr(crop)
                        if result and len(result) > 0 and result[0]:
                            item = result[0]
                            if isinstance(item, dict) or hasattr(item, "get"):
                                rec_texts = item.get("rec_texts") if hasattr(item, "get") else getattr(item, "rec_texts", [])
                                rec_polys = item.get("dt_polys") if hasattr(item, "get") and item.get("dt_polys") is not None else item.get("rec_polys")
                                if rec_polys is None:
                                    rec_polys = getattr(item, "dt_polys", None) or getattr(item, "rec_polys", [])
                                if rec_texts:
                                    for idx, text_val in enumerate(rec_texts):
                                        if not text_val:
                                            continue
                                        extracted_lines.append(str(text_val))
                                        if rec_polys is not None and idx < len(rec_polys):
                                            box_pts = rec_polys[idx]
                                            bx_min = float(min(pt[0] for pt in box_pts)) / crop_w * (xmax - xmin) + xmin
                                            bx_max = float(max(pt[0] for pt in box_pts)) / crop_w * (xmax - xmin) + xmin
                                            by_min = float(min(pt[1] for pt in box_pts)) / crop_h * (ymax - ymin) + ymin
                                            by_max = float(max(pt[1] for pt in box_pts)) / crop_h * (ymax - ymin) + ymin
                                            line_boxes.append((by_min, bx_min, by_max, bx_max))
                            elif isinstance(item, list):
                                for line in item:
                                    if not line or not isinstance(line, (list, tuple)):
                                        continue
                                    box_pts = line[0]
                                    text_val = line[1][0] if len(line) > 1 and isinstance(line[1], (list, tuple)) else ""
                                    if text_val:
                                        extracted_lines.append(str(text_val))
                                        bx_min = float(min(pt[0] for pt in box_pts)) / crop_w * (xmax - xmin) + xmin
                                        bx_max = float(max(pt[0] for pt in box_pts)) / crop_w * (xmax - xmin) + xmin
                                        by_min = float(min(pt[1] for pt in box_pts)) / crop_h * (ymax - ymin) + ymin
                                        by_max = float(max(pt[1] for pt in box_pts)) / crop_h * (ymax - ymin) + ymin
                                        line_boxes.append((by_min, bx_min, by_max, bx_max))

                    extracted = " ".join(extracted_lines).strip()
                    
                    if extracted != current_text:
                        if current_text and len(current_text) > 0:
                            s_ymin = min(b[0] for b in current_boxes) if current_boxes else ymin
                            s_xmin = min(b[1] for b in current_boxes) if current_boxes else xmin
                            s_ymax = max(b[2] for b in current_boxes) if current_boxes else ymax
                            s_xmax = max(b[3] for b in current_boxes) if current_boxes else xmax
                            segments.append({
                                "start": round(start_frame / fps, 3),
                                "end": round(frame_idx / fps, 3),
                                "text": current_text,
                                "bbox": [round(s_ymin, 3), round(s_xmin, 3), round(s_ymax, 3), round(s_xmax, 3)]
                            })
                        current_text = extracted
                        current_boxes = line_boxes
                        start_frame = frame_idx
                        
                frame_idx += 1
            
            cap.release()
            if current_text and len(current_text) > 0:
                s_ymin = min(b[0] for b in current_boxes) if current_boxes else ymin
                s_xmin = min(b[1] for b in current_boxes) if current_boxes else xmin
                s_ymax = max(b[2] for b in current_boxes) if current_boxes else ymax
                s_xmax = max(b[3] for b in current_boxes) if current_boxes else xmax
                segments.append({
                    "start": round(start_frame / fps, 3),
                    "end": round(frame_idx / fps, 3),
                    "text": current_text,
                    "bbox": [round(s_ymin, 3), round(s_xmin, 3), round(s_ymax, 3), round(s_xmax, 3)]
                })
            return segments

        except Exception as e:
            print(f"[PaddleOCR] Exception encountered during text extraction: {e}")
            return []

    def extract_text_keyframes(self, video_path: Path, region: List[float], asr_segments: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        ymin, xmin, ymax, xmax = region if region else [0.8, 0.0, 1.0, 1.0]
        try:
            from paddleocr import PaddleOCR
            try:
                ocr = PaddleOCR(use_textline_orientation=True, lang='ch')
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
                    
                line_boxes = []
                extracted_lines = []
                if res and len(res) > 0 and res[0]:
                    item = res[0]
                    if isinstance(item, dict) or hasattr(item, "get"):
                        rec_texts = item.get("rec_texts") if hasattr(item, "get") else getattr(item, "rec_texts", [])
                        rec_polys = item.get("dt_polys") if hasattr(item, "get") and item.get("dt_polys") is not None else item.get("rec_polys")
                        if rec_polys is None:
                            rec_polys = getattr(item, "dt_polys", None) or getattr(item, "rec_polys", [])
                        if rec_texts:
                            for idx, text_val in enumerate(rec_texts):
                                if not text_val:
                                    continue
                                extracted_lines.append(str(text_val))
                                if rec_polys is not None and idx < len(rec_polys):
                                    box_pts = rec_polys[idx]
                                    bx_min = float(min(pt[0] for pt in box_pts)) / crop_w * (xmax - xmin) + xmin
                                    bx_max = float(max(pt[0] for pt in box_pts)) / crop_w * (xmax - xmin) + xmin
                                    by_min = float(min(pt[1] for pt in box_pts)) / crop_h * (ymax - ymin) + ymin
                                    by_max = float(max(pt[1] for pt in box_pts)) / crop_h * (ymax - ymin) + ymin
                                    line_boxes.append((by_min, bx_min, by_max, bx_max))

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
