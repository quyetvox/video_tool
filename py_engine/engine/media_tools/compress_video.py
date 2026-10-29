#!/usr/bin/env python3

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


VIDEO_EXTENSIONS = {
    ".mp4",
    ".mov",
    ".mkv",
    ".avi",
    ".webm",
    ".m4v",
}

# CRF càng cao -> nén càng mạnh -> file càng nhỏ.
#
# Mặc định bắt đầu từ CRF 29.
# Nếu CRF 29 vẫn tạo file lớn hơn source,
# script sẽ thử chất lượng cao hơn theo thứ tự:
#
# 29 -> 27 -> 25 -> 23
#
DEFAULT_CRF_LEVELS = [29, 27, 25, 23]


def format_size(size_bytes: int) -> str:
    """Convert bytes to human readable size."""

    units = [
        "B",
        "KB",
        "MB",
        "GB",
        "TB",
    ]

    size = float(size_bytes)

    for unit in units:
        if size < 1024:
            return f"{size:.2f} {unit}"

        size /= 1024

    return f"{size:.2f} PB"


def format_duration(seconds):
    """Convert seconds to HH:MM:SS."""

    if seconds is None:
        return "unknown"

    seconds = float(seconds)

    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = seconds % 60

    if hours > 0:
        return (
            f"{hours:02d}:"
            f"{minutes:02d}:"
            f"{secs:05.2f}"
        )

    return (
        f"{minutes:02d}:"
        f"{secs:05.2f}"
    )


def format_bitrate(bitrate):
    """Convert bitrate to readable Mbps."""

    if bitrate is None:
        return "unknown"

    bitrate = float(bitrate)

    if bitrate >= 1_000_000:
        return f"{bitrate / 1_000_000:.2f} Mbps"

    return f"{bitrate / 1_000:.0f} kbps"


def check_dependencies():
    """Check FFmpeg and FFprobe."""

    if shutil.which("ffmpeg") is None:
        print("ERROR: FFmpeg chưa được cài đặt.")
        print()
        print("macOS:")
        print("  brew install ffmpeg")
        sys.exit(1)

    if shutil.which("ffprobe") is None:
        print("ERROR: FFprobe chưa được cài đặt.")
        print()
        print("macOS:")
        print("  brew install ffmpeg")
        sys.exit(1)


def get_media_info(path: Path):
    """Read media metadata using ffprobe."""

    command = [
        "ffprobe",
        "-v",
        "quiet",
        "-print_format",
        "json",
        "-show_format",
        "-show_streams",
        str(path),
    ]

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        raise RuntimeError(
            "ffprobe failed:\n"
            f"{result.stderr}"
        )

    return json.loads(result.stdout)


def get_video_stream(info):
    """Get first video stream."""

    for stream in info.get("streams", []):
        if stream.get("codec_type") == "video":
            return stream

    return None


def get_audio_stream(info):
    """Get first audio stream."""

    for stream in info.get("streams", []):
        if stream.get("codec_type") == "audio":
            return stream

    return None


def get_duration(info):
    """Get media duration."""

    format_info = info.get(
        "format",
        {},
    )

    duration = format_info.get(
        "duration"
    )

    if duration:
        return float(duration)

    video = get_video_stream(info)

    if video:
        duration = video.get("duration")

        if duration:
            return float(duration)

    return None


def get_bitrate(info):
    """Get total media bitrate."""

    format_info = info.get(
        "format",
        {},
    )

    bitrate = format_info.get(
        "bit_rate"
    )

    if bitrate:
        return int(bitrate)

    return None


def get_fps(video_stream):
    """Get average FPS."""

    if not video_stream:
        return None

    fps = video_stream.get(
        "avg_frame_rate"
    )

    if not fps or fps == "0/0":
        fps = video_stream.get(
            "r_frame_rate"
        )

    if not fps or fps == "0/0":
        return None

    try:
        numerator, denominator = fps.split("/")

        numerator = float(numerator)
        denominator = float(denominator)

        if denominator == 0:
            return None

        return numerator / denominator

    except Exception:
        return None


def print_media_info(
    path: Path,
    info,
):
    """Print input video information."""

    video = get_video_stream(info)
    audio = get_audio_stream(info)

    file_size = path.stat().st_size
    duration = get_duration(info)
    bitrate = get_bitrate(info)

    print()
    print("=" * 65)
    print("INPUT VIDEO")
    print("=" * 65)

    print(f"File        : {path}")
    print(
        f"Size        : "
        f"{format_size(file_size)}"
    )
    print(
        f"Duration    : "
        f"{format_duration(duration)}"
    )
    print(
        f"Bitrate     : "
        f"{format_bitrate(bitrate)}"
    )

    if video:
        codec = video.get(
            "codec_name",
            "unknown",
        )

        width = video.get(
            "width",
            "?",
        )

        height = video.get(
            "height",
            "?",
        )

        fps = get_fps(video)

        print(
            f"Video codec : "
            f"{codec}"
        )

        print(
            f"Resolution  : "
            f"{width}x{height}"
        )

        if fps:
            print(
                f"FPS         : "
                f"{fps:.3f}"
            )

        video_bitrate = video.get(
            "bit_rate"
        )

        if video_bitrate:
            print(
                f"Video rate  : "
                f"{format_bitrate(int(video_bitrate))}"
            )

    if audio:
        audio_codec = audio.get(
            "codec_name",
            "unknown",
        )

        audio_bitrate = audio.get(
            "bit_rate"
        )

        print(
            f"Audio codec : "
            f"{audio_codec}"
        )

        if audio_bitrate:
            print(
                f"Audio rate  : "
                f"{format_bitrate(int(audio_bitrate))}"
            )

    print("=" * 65)


def build_output_path(
    input_path: Path,
    output_path: str | None,
    output_dir: str | None,
):
    """Build final output path."""

    if output_path:

        result = (
            Path(output_path)
            .expanduser()
            .resolve()
        )

        result.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        return result

    if output_dir:

        directory = (
            Path(output_dir)
            .expanduser()
            .resolve()
        )

        directory.mkdir(
            parents=True,
            exist_ok=True,
        )

        return directory / (
            f"{input_path.stem}"
            f"_compressed.mp4"
        )

    return input_path.with_name(
        f"{input_path.stem}"
        f"_compressed.mp4"
    )


def build_ffmpeg_command(
    input_path: Path,
    output_path: Path,
    crf: int,
    preset: str,
    audio_bitrate: str,
):
    """
    Build FFmpeg H.265 compression command.

    Video:
        H.265 / HEVC
        CRF based quality
        preset

    Audio:
        AAC
        configurable bitrate

    Metadata:
        copy from source

    Container:
        MP4
        faststart
    """

    return [
        "ffmpeg",

        "-hide_banner",

        "-y",

        # Input
        "-i",
        str(input_path),

        # -----------------------------------------
        # Video stream
        # -----------------------------------------

        "-map",
        "0:v:0",

        "-c:v",
        "libx265",

        "-preset",
        preset,

        "-crf",
        str(crf),

        # H.265 tag for Apple/Safari compatibility
        "-tag:v",
        "hvc1",

        # -----------------------------------------
        # Audio stream
        # -----------------------------------------

        "-map",
        "0:a?",

        "-c:a",
        "aac",

        "-b:a",
        audio_bitrate,

        # -----------------------------------------
        # Metadata
        # -----------------------------------------

        "-map_metadata",
        "0",

        # -----------------------------------------
        # MP4 optimization
        # -----------------------------------------

        "-movflags",
        "+faststart",

        # Output
        str(output_path),
    ]


def encode_video(
    input_path: Path,
    output_path: Path,
    crf: int,
    preset: str,
    audio_bitrate: str,
):
    """Run FFmpeg encode."""

    command = build_ffmpeg_command(
        input_path=input_path,
        output_path=output_path,
        crf=crf,
        preset=preset,
        audio_bitrate=audio_bitrate,
    )

    print()
    print("-" * 65)
    print(
        f"ENCODING"
    )
    print(
        f"CRF          : {crf}"
    )
    print(
        f"Preset       : {preset}"
    )
    print(
        f"Audio bitrate: {audio_bitrate}"
    )
    print("-" * 65)
    print()

    process = subprocess.run(
        command
    )

    if process.returncode != 0:
        raise RuntimeError(
            "FFmpeg encode thất bại."
        )


def calculate_result(
    original_size: int,
    compressed_size: int,
):
    """Calculate compression statistics."""

    saved = (
        original_size
        - compressed_size
    )

    if original_size <= 0:
        return {
            "saved": saved,
            "reduction": 0.0,
            "ratio": 0.0,
        }

    reduction = (
        saved / original_size
    ) * 100

    ratio = (
        compressed_size
        / original_size
    )

    return {
        "saved": saved,
        "reduction": reduction,
        "ratio": ratio,
    }


def print_result(
    input_path: Path,
    output_path: Path,
    original_size: int,
    compressed_size: int,
    crf: int,
    audio_bitrate: str,
):
    """Print final compression result."""

    result = calculate_result(
        original_size,
        compressed_size,
    )

    print()
    print("=" * 65)
    print("COMPRESSION RESULT")
    print("=" * 65)

    print(
        f"Input       : "
        f"{input_path}"
    )

    print(
        f"Output      : "
        f"{output_path}"
    )

    print()

    print(
        f"Dung lượng gốc   : "
        f"{format_size(original_size)}"
    )

    print(
        f"Dung lượng mới    : "
        f"{format_size(compressed_size)}"
    )

    if result["saved"] >= 0:

        print(
            f"Đã giảm          : "
            f"{format_size(result['saved'])}"
        )

    else:

        print(
            f"Tăng thêm        : "
            f"{format_size(abs(result['saved']))}"
        )

    print(
        f"Tỷ lệ giảm       : "
        f"{result['reduction']:.2f}%"
    )

    print(
        f"Compression ratio: "
        f"{result['ratio']:.3f}x"
    )

    print(
        f"Video CRF        : "
        f"{crf}"
    )

    print(
        f"Audio bitrate    : "
        f"{audio_bitrate}"
    )

    print()

    if compressed_size < original_size:

        print(
            "STATUS: SUCCESS"
        )

        print(
            "Output nhỏ hơn file gốc."
        )

    elif compressed_size == original_size:

        print(
            "STATUS: SAME"
        )

        print(
            "Dung lượng không thay đổi."
        )

    else:

        print(
            "STATUS: LARGER"
        )

        print(
            "Output lớn hơn file gốc."
        )

    print("=" * 65)


def main():

    parser = argparse.ArgumentParser(
        description=(
            "Smart H.265 video compressor "
            "with automatic CRF selection."
        )
    )

    # ------------------------------------------------
    # Input
    # ------------------------------------------------

    parser.add_argument(
        "input",
        help=(
            "Đường dẫn video đầu vào"
        ),
    )

    # ------------------------------------------------
    # Output
    # ------------------------------------------------

    parser.add_argument(
        "-o",
        "--output",
        help=(
            "Đường dẫn file output"
        ),
    )

    parser.add_argument(
        "--output-dir",
        help=(
            "Thư mục chứa output"
        ),
    )

    # ------------------------------------------------
    # CRF
    # ------------------------------------------------

    parser.add_argument(
        "--crf",
        type=int,
        default=29,
        help=(
            "CRF bắt đầu. "
            "Mặc định: 29"
        ),
    )

    parser.add_argument(
        "--min-crf",
        type=int,
        default=23,
        help=(
            "CRF thấp nhất khi auto. "
            "Mặc định: 23"
        ),
    )

    # ------------------------------------------------
    # Preset
    # ------------------------------------------------

    parser.add_argument(
        "--preset",
        default="medium",
        choices=[
            "ultrafast",
            "superfast",
            "veryfast",
            "faster",
            "fast",
            "medium",
            "slow",
            "slower",
            "veryslow",
        ],
        help=(
            "H.265 preset. "
            "Mặc định: medium"
        ),
    )

    # ------------------------------------------------
    # Audio
    # ------------------------------------------------

    parser.add_argument(
        "--audio-bitrate",
        default="96k",
        help=(
            "Audio bitrate. "
            "Mặc định: 96k"
        ),
    )

    # ------------------------------------------------
    # Disable auto
    # ------------------------------------------------

    parser.add_argument(
        "--no-auto",
        action="store_true",
        help=(
            "Chỉ encode một lần "
            "với CRF được chỉ định."
        ),
    )

    # ------------------------------------------------
    # Dry run
    # ------------------------------------------------

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help=(
            "Chỉ phân tích video, "
            "không encode."
        ),
    )

    args = parser.parse_args()

    # ------------------------------------------------
    # Dependency
    # ------------------------------------------------

    check_dependencies()

    # ------------------------------------------------
    # Input
    # ------------------------------------------------

    input_path = (
        Path(args.input)
        .expanduser()
        .resolve()
    )

    if not input_path.exists():

        print(
            "ERROR: Không tìm thấy file:"
        )

        print(
            input_path
        )

        sys.exit(1)

    if not input_path.is_file():

        print(
            "ERROR: Input không phải file:"
        )

        print(
            input_path
        )

        sys.exit(1)

    if (
        input_path.suffix.lower()
        not in VIDEO_EXTENSIONS
    ):

        print(
            "WARNING: Extension không nằm "
            "trong danh sách video phổ biến."
        )

    # ------------------------------------------------
    # Metadata
    # ------------------------------------------------

    try:

        info = get_media_info(
            input_path
        )

    except Exception as error:

        print(
            f"ERROR: Không đọc được metadata:\n"
            f"{error}"
        )

        sys.exit(1)

    print_media_info(
        input_path,
        info,
    )

    # ------------------------------------------------
    # Dry run
    # ------------------------------------------------

    if args.dry_run:
        return

    # ------------------------------------------------
    # Output
    # ------------------------------------------------

    output_path = build_output_path(
        input_path=input_path,
        output_path=args.output,
        output_dir=args.output_dir,
    )

    if output_path == input_path:

        print(
            "ERROR: Output không được "
            "trùng input."
        )

        sys.exit(1)

    original_size = (
        input_path.stat().st_size
    )

    # ------------------------------------------------
    # Build CRF levels
    # ------------------------------------------------

    if args.no_auto:

        crf_levels = [
            args.crf
        ]

    else:

        crf_levels = [
            crf
            for crf in range(
                args.crf,
                args.min_crf - 1,
                -2,
            )
        ]

    print()
    print("=" * 65)
    print("COMPRESSION PLAN")
    print("=" * 65)

    print(
        "CRF levels   : "
        + ", ".join(
            str(x)
            for x in crf_levels
        )
    )

    print(
        "Audio bitrate: "
        f"{args.audio_bitrate}"
    )

    print(
        "Preset       : "
        f"{args.preset}"
    )

    print("=" * 65)

    # ------------------------------------------------
    # Encode
    # ------------------------------------------------

    best_output = None
    best_crf = None

    for crf in crf_levels:

        temp_output = (
            output_path.with_name(
                f"."
                f"{output_path.stem}"
                f".crf{crf}"
                f".tmp.mp4"
            )
        )

        # Remove old temp file
        if temp_output.exists():

            temp_output.unlink()

        try:

            encode_video(
                input_path=input_path,
                output_path=temp_output,
                crf=crf,
                preset=args.preset,
                audio_bitrate=args.audio_bitrate,
            )

        except Exception as error:

            if temp_output.exists():
                temp_output.unlink()

            print()
            print(
                f"ERROR với CRF {crf}:"
            )

            print(error)

            continue

        # ------------------------------------------------
        # Check output
        # ------------------------------------------------

        if not temp_output.exists():

            print(
                f"CRF {crf}: "
                "Không tạo được output."
            )

            continue

        compressed_size = (
            temp_output.stat().st_size
        )

        result = calculate_result(
            original_size,
            compressed_size,
        )

        print()
        print(
            "-" * 65
        )

        print(
            f"CRF {crf}"
        )

        print(
            f"Output size : "
            f"{format_size(compressed_size)}"
        )

        print(
            f"Reduction   : "
            f"{result['reduction']:.2f}%"
        )

        # ------------------------------------------------
        # ACCEPT
        # ------------------------------------------------

        if compressed_size < original_size:

            best_output = (
                temp_output
            )

            best_crf = crf

            print()

            print(
                f"ACCEPT CRF {crf}"
            )

            print(
                "Output nhỏ hơn "
                "file gốc."
            )

            break

        # ------------------------------------------------
        # REJECT
        # ------------------------------------------------

        print()

        print(
            f"REJECT CRF {crf}"
        )

        print(
            "Output vẫn lớn hơn "
            "hoặc bằng file gốc."
        )

        temp_output.unlink()

    # ------------------------------------------------
    # No compression found
    # ------------------------------------------------

    if best_output is None:

        print()
        print("=" * 65)
        print("NO COMPRESSION")
        print("=" * 65)

        print(
            "Không tìm được cấu hình "
            "tạo output nhỏ hơn file gốc."
        )

        print()
        print(
            "File gốc được giữ nguyên."
        )

        print("=" * 65)

        sys.exit(2)

    # ------------------------------------------------
    # Replace existing output
    # ------------------------------------------------

    if output_path.exists():

        output_path.unlink()

    best_output.rename(
        output_path
    )

    compressed_size = (
        output_path.stat().st_size
    )

    # ------------------------------------------------
    # Final result
    # ------------------------------------------------

    print_result(
        input_path=input_path,
        output_path=output_path,
        original_size=original_size,
        compressed_size=compressed_size,
        crf=best_crf,
        audio_bitrate=args.audio_bitrate,
    )


if __name__ == "__main__":
    main()