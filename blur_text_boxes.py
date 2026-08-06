#!/usr/bin/env python3
import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List

import cv2


def apply_box_blur(
    img: Any,
    boxes: List[Dict[str, Any]],
    padding: int = 5,
    blur_kernel_size: int = 35
) -> Any:
    """Áp dụng hiệu ứng Box Blur lên các vùng chứa text trong ảnh."""
    h, w = img.shape[:2]
    img_out = img.copy()

    for item in boxes:
        # Lấy tọa độ top_left [x1, y1] và bottom_right [x2, y2]
        top_left = item.get("top_left")
        bottom_right = item.get("bottom_right")
        box_pixel = item.get("box_pixel")

        if top_left and bottom_right:
            x1, y1 = top_left
            x2, y2 = bottom_right
        elif box_pixel and len(box_pixel) == 4:
            x1, y1, x2, y2 = box_pixel
        else:
            continue

        # Thêm padding để che phủ hoàn toàn rìa chữ
        x1_pad = max(0, int(x1) - padding)
        y1_pad = max(0, int(y1) - padding)
        x2_pad = min(w, int(x2) + padding)
        y2_pad = min(h, int(y2) + padding)

        box_w = x2_pad - x1_pad
        box_h = y2_pad - y1_pad

        if box_w <= 0 or box_h <= 0:
            continue

        # Lấy vùng ROI
        roi = img_out[y1_pad:y2_pad, x1_pad:x2_pad]

        # Tự động tính kernel size làm mờ tỉ lệ thuận với kích thước box
        kw = max(blur_kernel_size, (box_w // 4) | 1)
        kh = max(blur_kernel_size, (box_h // 4) | 1)

        # Đảm bảo kernel size là số lẻ
        if kw % 2 == 0:
            kw += 1
        if kh % 2 == 0:
            kh += 1

        # Áp dụng GaussianBlur mạnh (có thể lặp lại 2-3 lần để đạt hiệu ứng box blur mịn)
        blurred = cv2.GaussianBlur(roi, (kw, kh), 0)
        blurred = cv2.GaussianBlur(blurred, (kw, kh), 0)

        img_out[y1_pad:y2_pad, x1_pad:x2_pad] = blurred

    return img_out


def main():
    parser = argparse.ArgumentParser(
        description="Tool làm mờ (Box Blur) các vùng text dựa trên tọa độ trong file JSON và lưu vào folder src/."
    )
    parser.add_argument(
        "json_path",
        type=str,
        nargs="?",
        default="assets/images/detected_text_boxes.json",
        help="Đường dẫn file .json chứa tọa độ text boxes (Mặc định: assets/images/detected_text_boxes.json)",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        type=str,
        default=None,
        help="Thư mục đầu ra để lưu hình đã làm mờ (Mặc định: folder 'src' trong cùng thư mục với ảnh gốc)",
    )
    parser.add_argument(
        "-p",
        "--padding",
        type=int,
        default=5,
        help="Số pixel mở rộng thêm xung quanh box để che hết rìa chữ (Mặc định: 5px)",
    )
    parser.add_argument(
        "-b",
        "--blur-size",
        type=int,
        default=35,
        help="Độ mạnh làm mờ / Kernel size (Mặc định: 35)",
    )

    args = parser.parse_args()

    json_file = Path(args.json_path).resolve()
    if not json_file.exists():
        print(f"❌ Lỗi: File JSON '{json_file}' không tồn tại.")
        sys.exit(1)

    with open(json_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Đảm bảo data luôn là danh sách
    if isinstance(data, dict):
        items = [data]
    elif isinstance(data, list):
        items = data
    else:
        print("❌ Lỗi: Cấu trúc file JSON không hợp lệ.")
        sys.exit(1)

    base_dir = json_file.parent

    # Xác định thư mục output (Mặc định: base_dir / "src")
    if args.output_dir:
        out_dir = Path(args.output_dir).resolve()
    else:
        out_dir = base_dir / "src"

    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"📄 Đọc file JSON: {json_file.name}")
    print(f"📁 Thư mục lưu ảnh đã làm mờ: {out_dir}")
    print(f"⚙️ Cấu hình: Padding={args.padding}px, Blur strength={args.blur_size}")
    print("-" * 50)

    success_count = 0

    for item in items:
        img_name = item.get("image_name")
        img_path_str = item.get("image_path")
        text_boxes = item.get("text_boxes", [])

        if not img_name:
            continue

        # Tìm đường dẫn file ảnh gốc
        img_path = base_dir / img_name
        if not img_path.exists() and img_path_str:
            img_path = Path(img_path_str)

        if not img_path.exists():
            print(f"⚠️ Thắt thoát file: Không tìm thấy ảnh '{img_name}' tại '{img_path}'")
            continue

        img = cv2.imread(str(img_path))
        if img is None:
            print(f"⚠️ Không thể đọc file ảnh: {img_path}")
            continue

        print(f"🎨 Đang làm mờ text cho: {img_name} ({len(text_boxes)} box)...", end="", flush=True)

        if text_boxes:
            blurred_img = apply_box_blur(
                img,
                text_boxes,
                padding=args.padding,
                blur_kernel_size=args.blur_size
            )
        else:
            blurred_img = img

        save_path = out_dir / img_name
        cv2.imwrite(str(save_path), blurred_img)
        print(f" -> Đã lưu: {save_path.relative_to(base_dir.parent.parent)}")
        success_count += 1

    print("-" * 50)
    print(f"✅ Hoàn thành làm mờ {success_count} ảnh và lưu vào: '{out_dir}'")


if __name__ == "__main__":
    main()
