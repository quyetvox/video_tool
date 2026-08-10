#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path
from typing import Tuple, List

# Add lib directory to sys.path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from rich.console import Console
from rich.panel import Panel
from utils.concat_utils import concat_videos, remove_video_ranges
from utils.trimmer_utils import parse_time_str, get_unique_trim_path, format_seconds_to_time
from utils.ffmpeg_utils import FFmpegUtils

console = Console()


def format_size(size_bytes: int) -> str:
    """Format bytes into human readable string."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if abs(size_bytes) < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.2f} TB"


def parse_range_str(r_str: str) -> Tuple[float, float]:
    """Parse range string in formats like '00:02-00:05', '00:02..00:05', '15:30', or '00:02->00:05'."""
    r_str = r_str.strip()
    if "->" in r_str:
        parts = r_str.split("->")
    elif ".." in r_str:
        parts = r_str.split("..")
    elif "-" in r_str and not r_str.startswith("-"):
        parts = r_str.split("-")
    elif r_str.count(":") == 3:
        colons = [pos for pos, char in enumerate(r_str) if char == ":"]
        mid = colons[1]
        parts = [r_str[:mid], r_str[mid+1:]]
    elif ":" in r_str:
        parts = r_str.rsplit(":", 1) if r_str.count(":") == 1 else [r_str[:r_str.rfind(":")], r_str[r_str.rfind(":")+1:]]
    else:
        parts = [r_str]

    if len(parts) != 2:
        raise ValueError(f"Định dạng khoảng rác không hợp lệ: '{r_str}'")

    t_start = parse_time_str(parts[0])
    t_end = parse_time_str(parts[1])

    if t_start is None or t_end is None or t_start >= t_end:
        raise ValueError(f"Khoảng rác không hợp lệ: '{r_str}' (Start={parts[0]}, End={parts[1]})")

    return (t_start, t_end)


def main():
    parser = argparse.ArgumentParser(
        description="🎬 Sub-Video Studio — Ghép nhiều video hoặc Cắt loại bỏ nhiều đoạn rác",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ sử dụng:
  # 1. Ghép 3 video thành 1 file duy nhất:
  .venv/bin/python concat.py assets/foods/src/part1.mp4 assets/foods/src/part2.mp4 assets/foods/src/part3.mp4

  # 2. Cắt loại bỏ 2 đoạn rác (15s-30s và 1m10s-1m20s) trên 1 video:
  .venv/bin/python concat.py assets/foods/src/video_001.mp4 --remove 00:15-00:30 01:10-01:20

  # 3. Ghép video với tên file chỉ định:
  .venv/bin/python concat.py vid1.mp4 vid2.mp4 -o merged_output.mp4
        """
    )
    parser.add_argument("video_paths", type=str, nargs="+", help="Danh sách các file video cần ghép hoặc file video duy nhất cần cắt loại bỏ đoạn rác")
    parser.add_argument("-r", "--remove", type=str, nargs="+", default=None, help="Các khoảng rác cần cắt bỏ dạng 'start-end' (Ví dụ: --remove 00:15-00:30 01:10-01:20)")
    parser.add_argument("-o", "--output", type=str, default=None, help="Đường dẫn file đầu ra (mặc định: tự động sinh tên không trùng)")
    parser.add_argument("-b", "--bitrate", type=str, default="4.0M", help="Bitrate video đầu ra (mặc định: 4.0M sắc nét HD)")

    args = parser.parse_args()

    input_paths = [Path(p).resolve() for p in args.video_paths]
    for p in input_paths:
        if not p.exists():
            console.print(f"[bold red]❌ Lỗi:[/bold red] File video không tồn tại: {p}")
            sys.exit(1)

    # Mode Selection: Multi-Cut Range Removal vs Multi-Video Concatenation
    if args.remove and len(input_paths) == 1:
        # Mode B: Multi-Cut Range Removal on 1 Video
        target_video = input_paths[0]
        remove_ranges = []

        for r_str in args.remove:
            try:
                t_start, t_end = parse_range_str(r_str)
                remove_ranges.append((t_start, t_end))
            except ValueError as ve:
                console.print(f"[bold red]❌ Lỗi:[/bold red] {ve}")
                sys.exit(1)

        if args.output:
            out_path = Path(args.output).resolve()
        else:
            out_path = get_unique_trim_path(target_video, str(target_video.parent / f"{target_video.stem}_cut_clean.mp4"))

        console.print(Panel(
            f"[bold cyan]Input File:[/bold cyan] {target_video.name}\n"
            f"[bold cyan]Output File:[/bold cyan] {out_path.name}\n"
            f"[bold yellow]Số đoạn rác cắt bỏ:[/bold yellow] {len(remove_ranges)} đoạn (" + 
            ", ".join(f"{format_seconds_to_time(s)}➔{format_seconds_to_time(e)}" for s, e in remove_ranges) + ")\n"
            f"[bold green]Chế độ:[/bold green] Multi-Cut Segment Stitching (Re-encode VideoToolbox {args.bitrate})",
            title="✂️ Sub-Video Multi-Cut Range Removal"
        ))

        try:
            res_path = remove_video_ranges(target_video, remove_ranges, out_path, bitrate=args.bitrate)
            in_size = format_size(target_video.stat().st_size)
            out_size = format_size(res_path.stat().st_size)
            console.print(f"\n🎉 [bold green]Cắt bỏ đoạn rác thành công![/bold green]")
            console.print(f"📁 File đầu ra: [cyan]{res_path}[/cyan]")
            console.print(f"📊 Kích thước: {in_size} ➔ {out_size}")
        except Exception as e:
            console.print(f"[bold red]❌ Lỗi khi cắt loại bỏ đoạn rác:[/bold red] {e}")
            sys.exit(1)

    else:
        # Mode A: Multi-Video Concatenation
        if len(input_paths) < 2:
            console.print(f"[bold red]❌ Lỗi:[/bold red] Để ghép video cần chọn ít nhất 2 file video, hoặc truyền cờ `--remove` nếu muốn cắt loại bỏ đoạn rác trên 1 video.")
            sys.exit(1)

        first_input = input_paths[0]
        if args.output:
            out_path = Path(args.output).resolve()
        else:
            out_path = get_unique_trim_path(first_input, str(first_input.parent / f"{first_input.stem}_merged.mp4"))

        console.print(Panel(
            f"[bold cyan]Danh sách video ghép ({len(input_paths)} files):[/bold cyan]\n" +
            "\n".join(f"  {idx+1}. {p.name}" for idx, p in enumerate(input_paths)) + "\n\n"
            f"[bold cyan]Output File:[/bold cyan] {out_path.name}\n"
            f"[bold green]Chế độ:[/bold green] Auto Scale & Letterbox Pad + VideoToolbox {args.bitrate}",
            title="🎬 Sub-Video Video Merger"
        ))

        try:
            res_path = concat_videos(input_paths, out_path, bitrate=args.bitrate)
            out_size = format_size(res_path.stat().st_size)
            console.print(f"\n🎉 [bold green]Ghép các video thành công![/bold green]")
            console.print(f"📁 File đầu ra: [cyan]{res_path}[/cyan]")
            console.print(f"📊 Kích thước: {out_size}")
        except Exception as e:
            console.print(f"[bold red]❌ Lỗi khi ghép video:[/bold red] {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
