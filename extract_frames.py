#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

from lib.utils.ffmpeg_utils import FFmpegUtils


def main():
    parser = argparse.ArgumentParser(
        description="Tool cắt frame từ video theo khoảng thời gian chỉ định (Mặc định: 5s đầu tiên)."
    )
    parser.add_argument(
        "video_path",
        type=str,
        help="Đường dẫn đến file video cần cắt frame (ví dụ: assets/cooking/src/video_001.mp4)",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=str,
        default="assets/images",
        help="Thư mục lưu ảnh frame (Mặc định: assets/images)",
    )
    parser.add_argument(
        "-t",
        "--duration",
        type=float,
        default=5.0,
        help="Thời lượng cắt (giây) tính từ thời điểm bắt đầu (Mặc định: 5.0s)",
    )
    parser.add_argument(
        "-s",
        "--start-time",
        type=float,
        default=0.0,
        help="Thời điểm bắt đầu cắt (giây) (Mặc định: 0.0s)",
    )
    parser.add_argument(
        "-f",
        "--fps",
        type=float,
        default=1.0,
        help="Số frame cắt mỗi giây (fps=1: 1 hình/s, fps=0: giữ nguyên fps gốc) (Mặc định: 1.0)",
    )
    parser.add_argument(
        "--format",
        type=str,
        default="png",
        choices=["png", "jpg", "jpeg", "webp"],
        help="Định dạng ảnh xuất ra (png, jpg, webp...) (Mặc định: png)",
    )

    args = parser.parse_args()

    video_file = Path(args.video_path).resolve()
    if not video_file.exists():
        print(f"❌ Lỗi: File video '{video_file}' không tồn tại.")
        sys.exit(1)

    output_dir = Path(args.output).resolve()
    print(f"🎬 Đang cắt frame từ video: {video_file.name}")
    print(f"⏱️ khoảng thời gian: {args.start_time}s -> {args.start_time + args.duration}s (Độ dài: {args.duration}s, FPS: {args.fps})")
    print(f"📁 Thư mục đầu ra: {output_dir}")

    try:
        frames = FFmpegUtils.extract_frames(
            video_file=video_file,
            output_dir=output_dir,
            duration=args.duration,
            start_time=args.start_time,
            fps=args.fps,
            img_format=args.format,
        )
        print(f"✅ Đã cắt thành công {len(frames)} frames vào '{output_dir}':")
        for f in frames:
            print(f"  - {f.name}")
    except Exception as e:
        print(f"❌ Có lỗi xảy ra trong quá trình cắt frame: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
