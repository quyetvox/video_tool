#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

# Add lib directory to sys.path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from rich.console import Console
from rich.panel import Panel
from utils.ffmpeg_utils import FFmpegUtils
from utils.trimmer_utils import parse_time_str, get_unique_trim_path, format_seconds_to_time

console = Console()


def format_size(size_bytes: int) -> str:
    """Format bytes into human readable string."""
    for unit in ['B', 'KB', 'MB', 'GB']:
        if abs(size_bytes) < 1024.0:
            return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.2f} TB"


def main():
    parser = argparse.ArgumentParser(
        description="🎬 Sub-Video Trimmer — Cắt video nhanh bằng FFmpeg stream copy / re-encode",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ sử dụng:
  .venv/bin/python trim.py assets/foods/src/video_001.mp4 --start 5 --end 25
  .venv/bin/python trim.py video.mp4 -s 01:15 -e 02:30
  .venv/bin/python trim.py video.mp4 -s 10 -o video_cut.mp4
  .venv/bin/python trim.py video.mp4 -e 30 --accurate --overwrite
        """
    )
    parser.add_argument("video_path", type=str, help="Đường dẫn đến file video cần cắt")
    parser.add_argument("-s", "--start", type=str, default=None, help="Bắt đầu cắt (giây float hoặc dạng 'mm:ss' / 'hh:mm:ss')")
    parser.add_argument("-e", "--end", type=str, default=None, help="Kết thúc cắt (giây float hoặc dạng 'mm:ss' / 'hh:mm:ss')")
    parser.add_argument("-o", "--output", type=str, default=None, help="Đường dẫn file đầu ra (mặc định: tự động tăng số <tên_file>_cut_1.mp4)")
    parser.add_argument("--overwrite", action="store_true", help="Ghi đè file đầu ra nếu đã chỉ định -o")
    parser.add_argument("--accurate", action="store_true", help="Re-encode chính xác từng frame thay vì Stream Copy")

    args = parser.parse_args()

    input_path = Path(args.video_path).resolve()
    if not input_path.exists():
        console.print(f"[bold red]❌ Lỗi:[/bold red] File video không tồn tại: {input_path}")
        sys.exit(1)

    # 1. Probe input video
    try:
        probe_data = FFmpegUtils.probe(input_path)
        format_info = probe_data.get("format", {})
        total_duration = float(format_info.get("duration", 0))
    except Exception as e:
        console.print(f"[bold red]❌ Lỗi khi ffprobe video:[/bold red] {e}")
        sys.exit(1)

    # 2. Process start & end seconds (supports '01:30' or '90')
    parsed_start = parse_time_str(args.start)
    parsed_end = parse_time_str(args.end)

    start_sec = parsed_start if (parsed_start is not None and parsed_start > 0) else None
    end_sec = parsed_end if (parsed_end is not None and 0 < parsed_end < total_duration) else None

    # Validate parameters
    if start_sec is not None and start_sec >= total_duration:
        console.print(f"[bold red]❌ Lỗi:[/bold red] --start ({args.start} -> {start_sec:.2f}s) lớn hơn hoặc bằng thời lượng video ({total_duration:.2f}s)")
        sys.exit(1)

    if end_sec is not None and start_sec is not None and end_sec <= start_sec:
        console.print(f"[bold red]❌ Lỗi:[/bold red] --end ({args.end} -> {end_sec:.2f}s) phải lớn hơn --start ({args.start} -> {start_sec:.2f}s)")
        sys.exit(1)

    # Check if any trimming is actually needed
    if start_sec is None and end_sec is None:
        console.print(Panel(
            f"[yellow]Không có tham số cắt (--start hoặc --end) hợp lệ.[/yellow]\n"
            f"Video gốc được giữ nguyên toàn bộ thời lượng ({total_duration:.2f}s).",
            title="ℹ️ Video Unchanged"
        ))
        sys.exit(0)

    # 3. Determine auto-increment non-colliding output path
    if args.output and args.overwrite:
        out_path = Path(args.output).resolve()
        is_overwrite_input = (out_path == input_path)
    elif args.overwrite:
        out_path = input_path
        is_overwrite_input = True
    else:
        out_path = get_unique_trim_path(input_path, args.output)
        is_overwrite_input = False

    # Calculate effective trimmed duration
    actual_start = start_sec if start_sec is not None else 0.0
    actual_end = end_sec if end_sec is not None else total_duration
    trimmed_duration = actual_end - actual_start

    # Print action summary
    mode_str = "Frame-Accurate (Re-encode)" if args.accurate else "Stream Copy (Ultra-fast <1s)"
    console.print(Panel(
        f"[bold cyan]Input File:[/bold cyan] {input_path.name}\n"
        f"[bold cyan]Output File:[/bold cyan] {out_path.name}\n"
        f"[bold cyan]Thời lượng gốc:[/bold cyan] {total_duration:.2f}s\n"
        f"[bold green]Thời lượng sau cắt:[/bold green] {trimmed_duration:.2f}s (Cắt từ {actual_start:.2f}s ➔ {actual_end:.2f}s)\n"
        f"[bold green]Chế độ:[/bold green] {mode_str}",
        title="🎬 Sub-Video Trimmer"
    ))

    # Execute trim
    try:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        temp_target = (out_path.parent / f".tmp_trim_{out_path.name}") if is_overwrite_input else out_path
        FFmpegUtils.trim_video(
            input_file=input_path,
            output_file=temp_target,
            start_sec=start_sec,
            end_sec=end_sec,
            accurate=args.accurate
        )
        if is_overwrite_input:
            temp_target.replace(out_path)

        in_size = format_size(input_path.stat().st_size)
        out_size = format_size(out_path.stat().st_size)

        console.print(f"🎉 [bold green]Cắt video thành công![/bold green]")
        console.print(f"📁 [bold]File đầu ra:[/bold] {out_path}")
        console.print(f"📊 [bold]Kích thước:[/bold] {in_size} ➔ {out_size}")

    except Exception as e:
        console.print(f"[bold red]❌ Lỗi khi thực hiện cắt video:[/bold red] {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
