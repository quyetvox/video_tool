#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List

import cv2


def get_ocr_engine():
    """Khởi tạo PaddleOCR engine với cấu hình tối ưu."""
    try:
        from paddleocr import PaddleOCR
        try:
            return PaddleOCR(
                use_doc_orientation_classify=False,
                use_doc_unwarping=False,
                lang="ch"
            )
        except Exception:
            return PaddleOCR(lang="ch")
    except ImportError:
        print("❌ Lỗi: Chưa cài đặt library paddleocr.")
        print("Hãy đảm bảo đã cài đặt paddleocr trong virtualenv.")
        sys.exit(1)


def process_image(ocr, img_path: Path) -> Dict[str, Any]:
    """Detect chữ và tọa độ góc trên-trái, góc dưới-phải cho 1 hình ảnh."""
    img = cv2.imread(str(img_path))
    if img is None:
        print(f"⚠️ Không thể đọc file ảnh: {img_path}")
        return {"image": img_path.name, "image_size": [0, 0], "text_boxes": []}

    h, w = img.shape[:2]
    try:
        res = ocr.ocr(str(img_path))
    except Exception as e:
        print(f"⚠️ Lỗi OCR với ảnh {img_path.name}: {e}")
        return {"image": img_path.name, "image_size": [w, h], "text_boxes": []}

    text_boxes = []

    if res and len(res) > 0:
        # Case 1: PaddleX / PaddleOCR v2.9+ trả về list[dict]
        if isinstance(res[0], dict):
            item = res[0]
            rec_boxes = item.get("rec_boxes", [])
            rec_texts = item.get("rec_texts", [])
            rec_scores = item.get("rec_scores", [])
            dt_polys = item.get("dt_polys", [])

            if len(rec_boxes) > 0:
                for i, box in enumerate(rec_boxes):
                    x1, y1, x2, y2 = [int(v) for v in box]
                    text = str(rec_texts[i]) if i < len(rec_texts) else ""
                    score = float(rec_scores[i]) if i < len(rec_scores) else 0.0

                    top_rel = round(y1 / h, 4)
                    left_rel = round(x1 / w, 4)
                    bottom_rel = round(y2 / h, 4)
                    right_rel = round(x2 / w, 4)

                    text_boxes.append({
                        "text": text,
                        "confidence": round(score, 4),
                        "top_left": [x1, y1],
                        "bottom_right": [x2, y2],
                        "box_pixel": [x1, y1, x2, y2],
                        "region_normalized": [top_rel, left_rel, bottom_rel, right_rel]
                    })
            elif len(dt_polys) > 0:
                for i, poly in enumerate(dt_polys):
                    xs = [int(p[0]) for p in poly]
                    ys = [int(p[1]) for p in poly]
                    x1, y1, x2, y2 = min(xs), min(ys), max(xs), max(ys)
                    text = str(rec_texts[i]) if i < len(rec_texts) else ""
                    score = float(rec_scores[i]) if i < len(rec_scores) else 0.0

                    top_rel = round(y1 / h, 4)
                    left_rel = round(x1 / w, 4)
                    bottom_rel = round(y2 / h, 4)
                    right_rel = round(x2 / w, 4)

                    text_boxes.append({
                        "text": text,
                        "confidence": round(score, 4),
                        "top_left": [x1, y1],
                        "bottom_right": [x2, y2],
                        "box_pixel": [x1, y1, x2, y2],
                        "region_normalized": [top_rel, left_rel, bottom_rel, right_rel]
                    })

        # Case 2: Standard legacy PaddleOCR list format
        elif isinstance(res, list):
            lines = res[0] if isinstance(res[0], list) and len(res[0]) > 0 and isinstance(res[0][0], list) else res
            for line in lines:
                if isinstance(line, list) and len(line) == 2:
                    box_points, (text, score) = line
                    xs = [int(p[0]) for p in box_points]
                    ys = [int(p[1]) for p in box_points]
                    x1, y1, x2, y2 = min(xs), min(ys), max(xs), max(ys)

                    top_rel = round(y1 / h, 4)
                    left_rel = round(x1 / w, 4)
                    bottom_rel = round(y2 / h, 4)
                    right_rel = round(x2 / w, 4)

                    text_boxes.append({
                        "text": str(text),
                        "confidence": round(float(score), 4),
                        "top_left": [x1, y1],
                        "bottom_right": [x2, y2],
                        "box_pixel": [x1, y1, x2, y2],
                        "region_normalized": [top_rel, left_rel, bottom_rel, right_rel]
                    })

    return {
        "image_name": img_path.name,
        "image_path": str(img_path),
        "image_size": {"width": w, "height": h},
        "text_boxes": text_boxes
    }


def main():
    parser = argparse.ArgumentParser(
        description="Tool phát hiện vị trí (bounding boxes) của chữ trong ảnh và lưu vào file .json"
    )
    parser.add_argument(
        "target_path",
        type=str,
        nargs="?",
        default="assets/images",
        help="Đường dẫn tới thư mục chứa ảnh hoặc file ảnh đơn lẻ (Mặc định: assets/images)",
    )
    parser.add_argument(
        "--separate-json",
        action="store_true",
        help="Xuất từng file JSON riêng biệt cho mỗi ảnh (ví dụ: image_001.json)",
    )

    args = parser.parse_args()
    target_path = Path(args.target_path).resolve()

    if not target_path.exists():
        print(f"❌ Lỗi: Đường dẫn '{target_path}' không tồn tại.")
        sys.exit(1)

    if target_path.is_file():
        image_files = [target_path]
        output_dir = target_path.parent
    else:
        output_dir = target_path
        valid_exts = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}
        image_files = sorted([p for p in target_path.iterdir() if p.suffix.lower() in valid_exts])

    if not image_files:
        print(f"⚠️ Không tìm thấy file ảnh nào trong '{target_path}'.")
        sys.exit(0)

    print(f"🔍 Khởi tạo OCR Engine...")
    ocr = get_ocr_engine()

    print(f"📸 Đang xử lý {len(image_files)} ảnh...")
    summary_data = []

    for img_file in image_files:
        print(f"  - Phân tích: {img_file.name}...", end="", flush=True)
        img_result = process_image(ocr, img_file)
        box_count = len(img_result["text_boxes"])
        print(f" -> Tìm thấy {box_count} text box(es).")
        summary_data.append(img_result)

    # Lưu duy nhất 1 file JSON tổng hợp
    if target_path.is_file():
        summary_json_path = output_dir / f"{target_path.stem}_text_boxes.json"
    else:
        summary_json_path = output_dir / "detected_text_boxes.json"

    with open(summary_json_path, "w", encoding="utf-8") as f:
        json.dump(summary_data, f, ensure_ascii=False, indent=2)

    print(f"\n✅ Hoàn thành!")
    print(f"📊 Đã lưu tất cả thông tin vào file JSON duy nhất: {summary_json_path}")


if __name__ == "__main__":
    main()
