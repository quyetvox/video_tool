#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

# Add lib directory to sys.path
sys.path.insert(0, str(Path(__file__).parent / "lib"))

from rich.console import Console
from rich.panel import Panel
from utils.ffmpeg_utils import FFmpegUtils

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
  .venv/bin/python trim.py video.mp4 -s 10 -o video_cut.mp4
  .venv/bin/python trim.py video.mp4 -e 30 --accurate --overwrite
        """
    )
    parser.add_argument("video_path", type=str, help="Đường dẫn đến file video cần cắt")
    parser.add_argument("-s", "--start", type=float, default=None, help="Giây bắt đầu cắt (mặc định: 0s, không cắt giây đầu)")
    parser.add_argument("-e", "--end", type=float, default=None, help="Giây kết thúc cắt (mặc định: đến hết video, không cắt giây sau)")
    parser.add_argument("-o", "--output", type=str, default=None, help="Đường dẫn file đầu ra (mặc định: <tên_file>_trimmed.mp4)")
    parser.add_argument("--overwrite", action="store_true", help="Ghi đè file đầu ra nếu đã tồn tại")
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

    # 2. Process start & end seconds
    start_sec = float(args.start) if (args.start is not None and args.start > 0) else None
    end_sec = float(args.end) if (args.end is not None and 0 < args.end < total_duration) else None

    # Validate parameters
    if start_sec is not None and start_sec >= total_duration:
        console.print(f"[bold red]❌ Lỗi:[/bold red] --start ({start_sec}s) lớn hơn hoặc bằng thời lượng video ({total_duration:.2f}s)")
        sys.exit(1)

    if end_sec is not None and start_sec is not None and end_sec <= start_sec:
        console.print(f"[bold red]❌ Lỗi:[/bold red] --end ({end_sec}s) phải lớn hơn --start ({start_sec}s)")
        sys.exit(1)

    # Check if any trimming is actually needed
    if start_sec is None and end_sec is None:
        console.print(Panel(
            f"[yellow]Không có tham số cắt (--start hoặc --end) hợp lệ.[/yellow]\n"
            f"Video gốc được giữ nguyên toàn bộ thời lượng ({total_duration:.2f}s).",
            title="ℹ️ Video Unchanged"
        ))
        sys.exit(0)

    # Determine output path
    if args.output:
        out_path = Path(args.output).resolve()
    else:
        out_path = input_path.parent / f"{input_path.stem}_trimmed{input_path.suffix}"

    if out_path.exists() and not args.overwrite:
        console.print(f"[bold red]❌ Lỗi:[/bold red] File đầu ra đã tồn tại: {out_path}.\nDùng cờ `--overwrite` để ghi đè.")
        sys.exit(1)

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
        FFmpegUtils.trim_video(
            input_file=input_path,
            output_file=out_path,
            start_sec=start_sec,
            end_sec=end_sec,
            accurate=args.accurate
        )

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
