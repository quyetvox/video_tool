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


def check_dependencies():
    if shutil.which("ffprobe") is None:
        print("ERROR: ffprobe chưa được cài đặt.")
        print("macOS: brew install ffmpeg")
        sys.exit(1)


def run_ffprobe(path: Path):
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
            result.stderr.strip()
        )

    return json.loads(result.stdout)


def get_stream(info, codec_type):
    for stream in info.get("streams", []):
        if stream.get("codec_type") == codec_type:
            return stream

    return None


def parse_fraction(value):
    if not value or value == "0/0":
        return None

    try:
        numerator, denominator = value.split("/")

        numerator = float(numerator)
        denominator = float(denominator)

        if denominator == 0:
            return None

        return numerator / denominator

    except Exception:
        return None


def get_size(path: Path):
    return path.stat().st_size


def format_size(value):
    units = [
        "B",
        "KB",
        "MB",
        "GB",
        "TB",
    ]

    value = float(value)

    for unit in units:
        if value < 1024:
            return f"{value:.2f} {unit}"

        value /= 1024

    return f"{value:.2f} PB"


def format_bitrate(value):
    if value is None:
        return "unknown"

    value = float(value)

    if value >= 1_000_000:
        return f"{value / 1_000_000:.2f} Mbps"

    return f"{value / 1_000:.0f} kbps"


def format_duration(value):
    if value is None:
        return "unknown"

    value = float(value)

    hours = int(value // 3600)
    minutes = int((value % 3600) // 60)
    seconds = value % 60

    if hours:
        return (
            f"{hours:02d}:"
            f"{minutes:02d}:"
            f"{seconds:05.2f}"
        )

    return (
        f"{minutes:02d}:"
        f"{seconds:05.2f}"
    )


def calculate_resolution(width, height):
    if not width or not height:
        return None

    return {
        "width": width,
        "height": height,
        "pixels": width * height,
    }


def analyze_video(path: Path, info):
    video = get_stream(
        info,
        "video",
    )

    audio = get_stream(
        info,
        "audio",
    )

    format_info = info.get(
        "format",
        {},
    )

    file_size = get_size(path)

    duration = None

    if format_info.get("duration"):
        duration = float(
            format_info["duration"]
        )

    if duration is None and video:
        if video.get("duration"):
            duration = float(
                video["duration"]
            )

    total_bitrate = None

    if format_info.get("bit_rate"):
        total_bitrate = int(
            format_info["bit_rate"]
        )

    result = {
        "file": str(path),
        "size_bytes": file_size,
        "size": format_size(file_size),
        "duration_seconds": duration,
        "duration": format_duration(duration),
        "container": format_info.get(
            "format_name"
        ),
        "video": {},
        "audio": {},
    }

    if video:

        width = video.get("width")
        height = video.get("height")

        fps = parse_fraction(
            video.get("avg_frame_rate")
        )

        if fps is None:
            fps = parse_fraction(
                video.get("r_frame_rate")
            )

        video_bitrate = None

        if video.get("bit_rate"):
            video_bitrate = int(
                video["bit_rate"]
            )

        result["video"] = {
            "codec": video.get(
                "codec_name"
            ),
            "codec_long_name": video.get(
                "codec_long_name"
            ),
            "profile": video.get(
                "profile"
            ),
            "width": width,
            "height": height,
            "resolution": (
                f"{width}x{height}"
                if width and height
                else None
            ),
            "fps": fps,
            "pixel_format": video.get(
                "pix_fmt"
            ),
            "color_space": video.get(
                "color_space"
            ),
            "color_transfer": video.get(
                "color_transfer"
            ),
            "color_primaries": video.get(
                "color_primaries"
            ),
            "color_range": video.get(
                "color_range"
            ),
            "bit_depth": video.get(
                "bits_per_raw_sample"
            ),
            "bitrate": video_bitrate,
            "bitrate_human": format_bitrate(
                video_bitrate
            ),
            "frames": video.get(
                "nb_frames"
            ),
        }

    if audio:

        audio_bitrate = None

        if audio.get("bit_rate"):
            audio_bitrate = int(
                audio["bit_rate"]
            )

        result["audio"] = {
            "codec": audio.get(
                "codec_name"
            ),
            "codec_long_name": audio.get(
                "codec_long_name"
            ),
            "bitrate": audio_bitrate,
            "bitrate_human": format_bitrate(
                audio_bitrate
            ),
            "sample_rate": audio.get(
                "sample_rate"
            ),
            "channels": audio.get(
                "channels"
            ),
            "channel_layout": audio.get(
                "channel_layout"
            ),
        }

    result["total_bitrate"] = total_bitrate
    result["total_bitrate_human"] = (
        format_bitrate(total_bitrate)
    )

    return result


def add_recommendation(
    recommendations,
    level,
    title,
    description,
    estimated_saving=None,
):
    recommendations.append(
        {
            "level": level,
            "title": title,
            "description": description,
            "estimated_saving": estimated_saving,
        }
    )


def analyze_optimization(data):
    recommendations = []

    video = data["video"]
    audio = data["audio"]

    codec = video.get("codec")
    width = video.get("width")
    height = video.get("height")
    fps = video.get("fps")
    pixel_format = video.get(
        "pixel_format"
    )

    video_bitrate = video.get(
        "bitrate"
    )

    audio_bitrate = audio.get(
        "bitrate"
    )

    # ------------------------------------------------
    # Codec
    # ------------------------------------------------

    if codec in {
        "h264",
        "mpeg4",
        "mpeg2video",
    }:

        add_recommendation(
            recommendations,
            "HIGH",
            "Đổi sang H.265/HEVC",
            (
                f"Video hiện đang dùng {codec}. "
                "Có thể encode lại bằng H.265 "
                "để giảm bitrate ở chất lượng "
                "tương đương."
            ),
            "thường có thể giảm đáng kể",
        )

    elif codec == "hevc":

        add_recommendation(
            recommendations,
            "INFO",
            "Video đã dùng H.265/HEVC",
            (
                "Codec hiện tại đã khá hiệu quả. "
                "Tối ưu tiếp nên tập trung vào "
                "CRF/bitrate, resolution, FPS "
                "và audio."
            ),
        )

    elif codec == "av1":

        add_recommendation(
            recommendations,
            "INFO",
            "Video đã dùng AV1",
            (
                "AV1 đã có compression efficiency "
                "rất tốt. Encode lại chưa chắc "
                "giảm được dung lượng."
            ),
        )

    # ------------------------------------------------
    # Resolution
    # ------------------------------------------------

    if width and height:

        pixels = width * height

        if width >= 3840 or height >= 2160:

            add_recommendation(
                recommendations,
                "HIGH",
                "Resolution 4K",
                (
                    "Video đang ở 4K. Nếu mục tiêu "
                    "là social/video AI và không cần "
                    "4K, giảm xuống 1080p có thể "
                    "giảm dung lượng rất mạnh."
                ),
                "rất lớn nếu 4K → 1080p",
            )

        elif width >= 2560 or height >= 1440:

            add_recommendation(
                recommendations,
                "HIGH",
                "Resolution cao",
                (
                    "Video trên 1080p. Có thể cân "
                    "nhắc giảm xuống 1080p nếu "
                    "không cần giữ nguyên resolution."
                ),
                "đáng kể",
            )

        elif width == 1920 and height == 1080:

            add_recommendation(
                recommendations,
                "INFO",
                "Video đang ở 1080p",
                (
                    "Resolution đã phù hợp cho "
                    "phần lớn social media. "
                    "Không nên resize nếu muốn "
                    "giữ chất lượng hình ảnh."
                ),
            )

    # ------------------------------------------------
    # FPS
    # ------------------------------------------------

    if fps:

        if fps > 50:

            add_recommendation(
                recommendations,
                "HIGH",
                "FPS rất cao",
                (
                    f"Video đang ở {fps:.2f} FPS. "
                    "Nếu không cần slow-motion hoặc "
                    "motion đặc biệt, có thể giảm "
                    "xuống 30 FPS."
                ),
                "đáng kể",
            )

        elif fps > 30:

            add_recommendation(
                recommendations,
                "MEDIUM",
                "FPS trên 30",
                (
                    f"Video đang ở {fps:.2f} FPS. "
                    "Có thể cân nhắc 30 FPS nếu "
                    "không cần giữ chuyển động "
                    "mượt như hiện tại."
                ),
                "vừa phải",
            )

        else:

            add_recommendation(
                recommendations,
                "INFO",
                "FPS đã khá thấp",
                (
                    f"Video đang ở {fps:.2f} FPS. "
                    "Không nên giảm FPS thêm nếu "
                    "muốn giữ motion."
                ),
            )

    # ------------------------------------------------
    # Video bitrate
    # ------------------------------------------------

    if video_bitrate:

        if video_bitrate > 10_000_000:

            add_recommendation(
                recommendations,
                "HIGH",
                "Video bitrate rất cao",
                (
                    f"Video bitrate hiện tại "
                    f"{format_bitrate(video_bitrate)}. "
                    "Có khả năng giảm đáng kể "
                    "bằng H.265 CRF."
                ),
                "đáng kể",
            )

        elif video_bitrate > 5_000_000:

            add_recommendation(
                recommendations,
                "MEDIUM",
                "Video bitrate khá cao",
                (
                    f"Video bitrate hiện tại "
                    f"{format_bitrate(video_bitrate)}. "
                    "Có thể thử H.265 CRF 23–29."
                ),
                "vừa phải",
            )

        else:

            add_recommendation(
                recommendations,
                "INFO",
                "Video bitrate không cao",
                (
                    f"Video bitrate chỉ "
                    f"{format_bitrate(video_bitrate)}. "
                    "Không nên kỳ vọng giảm "
                    "dung lượng quá lớn chỉ bằng "
                    "encode lại."
                ),
            )

    # ------------------------------------------------
    # Audio
    # ------------------------------------------------

    if audio_bitrate >= 256_000:

        estimated_saving = format_bitrate(
            audio_bitrate - 128_000
        )

        add_recommendation(
            recommendations,
            "HIGH",
            "Audio bitrate cao",
            (
                f"Audio đang ở "
                f"{format_bitrate(audio_bitrate)}. "
                "Có thể encode AAC 96k–128k."
            ),
            (
                f"có thể giảm khoảng "
                f"{estimated_saving}"
            ),
        )

    elif audio_bitrate >= 160_000:

        add_recommendation(
            recommendations,
            "MEDIUM",
            "Audio bitrate tương đối cao",
            (
                f"Audio đang ở "
                f"{format_bitrate(audio_bitrate)}. "
                "Có thể thử AAC 96k–128k."
            ),
            "nhỏ đến vừa",
        )

    elif audio_bitrate >= 128_000:

        add_recommendation(
            recommendations,
            "LOW",
            "Có thể tối ưu audio",
            (
                f"Audio đang ở "
                f"{format_bitrate(audio_bitrate)}. "
                "Có thể giảm xuống AAC 96k "
                "nếu đây là video social."
            ),
            "nhỏ",
        )

    else:

        add_recommendation(
            recommendations,
            "INFO",
            "Audio đã khá nhỏ",
            (
                f"Audio chỉ "
                f"{format_bitrate(audio_bitrate)}. "
                "Không nên giảm thêm nếu "
                "muốn giữ chất lượng âm thanh."
            ),
        )

    # ------------------------------------------------
    # Pixel format
    # ------------------------------------------------

    if pixel_format:

        if "444" in pixel_format:

            add_recommendation(
                recommendations,
                "MEDIUM",
                "Pixel format 4:4:4",
                (
                    f"Video đang dùng {pixel_format}. "
                    "Nếu video không cần color "
                    "precision cao, 4:2:0 có thể "
                    "giảm dữ liệu đáng kể."
                ),
                "đáng kể",
            )

        elif "422" in pixel_format:

            add_recommendation(
                recommendations,
                "MEDIUM",
                "Pixel format 4:2:2",
                (
                    f"Video đang dùng {pixel_format}. "
                    "Có thể cân nhắc 4:2:0 cho "
                    "video delivery/social."
                ),
                "vừa phải",
            )

        elif pixel_format == "yuv420p":

            add_recommendation(
                recommendations,
                "INFO",
                "Pixel format tối ưu phổ biến",
                (
                    "Video đã dùng YUV 4:2:0, "
                    "phù hợp cho delivery."
                ),
            )

    # ------------------------------------------------
    # Final
    # ------------------------------------------------

    if not recommendations:

        add_recommendation(
            recommendations,
            "INFO",
            "Không phát hiện tối ưu rõ ràng",
            (
                "Video có vẻ đã được encode khá "
                "hiệu quả. Có thể thử benchmark "
                "H.265 CRF 25–29."
            ),
        )

    return recommendations


def print_report(data, recommendations):
    print()
    print("=" * 70)
    print("VIDEO ANALYSIS")
    print("=" * 70)

    print(
        f"File       : "
        f"{data['file']}"
    )

    print(
        f"Size       : "
        f"{data['size']}"
    )

    print(
        f"Duration   : "
        f"{data['duration']}"
    )

    print(
        f"Container  : "
        f"{data['container']}"
    )

    print(
        f"Total rate : "
        f"{data['total_bitrate_human']}"
    )

    print()
    print("VIDEO")
    print("-" * 70)

    video = data["video"]

    fields = [
        ("Codec", video.get("codec")),
        ("Profile", video.get("profile")),
        ("Resolution", video.get("resolution")),
        (
            "FPS",
            (
                f"{video['fps']:.3f}"
                if video.get("fps")
                else "unknown"
            ),
        ),
        (
            "Bitrate",
            video.get(
                "bitrate_human"
            ),
        ),
        (
            "Pixel format",
            video.get(
                "pixel_format"
            ),
        ),
        (
            "Color space",
            video.get(
                "color_space"
            ),
        ),
        (
            "Color transfer",
            video.get(
                "color_transfer"
            ),
        ),
        (
            "Color range",
            video.get(
                "color_range"
            ),
        ),
        (
            "Bit depth",
            video.get(
                "bit_depth"
            ),
        ),
    ]

    for name, value in fields:
        print(
            f"{name:<16}: {value}"
        )

    print()
    print("AUDIO")
    print("-" * 70)

    audio = data["audio"]

    if audio:

        fields = [
            (
                "Codec",
                audio.get("codec"),
            ),
            (
                "Bitrate",
                audio.get(
                    "bitrate_human"
                ),
            ),
            (
                "Sample rate",
                audio.get(
                    "sample_rate"
                ),
            ),
            (
                "Channels",
                audio.get(
                    "channels"
                ),
            ),
            (
                "Layout",
                audio.get(
                    "channel_layout"
                ),
            ),
        ]

        for name, value in fields:
            print(
                f"{name:<16}: {value}"
            )

    else:

        print(
            "Không có audio stream."
        )

    print()
    print("=" * 70)
    print("OPTIMIZATION RECOMMENDATIONS")
    print("=" * 70)

    priority_order = {
        "HIGH": 0,
        "MEDIUM": 1,
        "LOW": 2,
        "INFO": 3,
    }

    recommendations = sorted(
        recommendations,
        key=lambda item: priority_order.get(
            item["level"],
            99,
        ),
    )

    for index, item in enumerate(
        recommendations,
        start=1,
    ):

        print()
        print(
            f"{index}. "
            f"[{item['level']}] "
            f"{item['title']}"
        )

        print(
            f"   {item['description']}"
        )

        if item.get(
            "estimated_saving"
        ):

            print(
                f"   Tiết kiệm: "
                f"{item['estimated_saving']}"
            )

    print()
    print("=" * 70)


def main():

    parser = argparse.ArgumentParser(
        description=(
            "Analyze video parameters and "
            "find possible size optimizations."
        )
    )

    parser.add_argument(
        "input",
        help="Đường dẫn video",
    )

    parser.add_argument(
        "--json",
        action="store_true",
        help=(
            "Output kết quả dạng JSON"
        ),
    )

    args = parser.parse_args()

    check_dependencies()

    path = (
        Path(args.input)
        .expanduser()
        .resolve()
    )

    if not path.exists():

        print(
            f"ERROR: Không tìm thấy file:\n"
            f"{path}"
        )

        sys.exit(1)

    if not path.is_file():

        print(
            "ERROR: Input không phải file."
        )

        sys.exit(1)

    try:

        info = run_ffprobe(path)

        data = analyze_video(
            path,
            info,
        )

        recommendations = (
            analyze_optimization(
                data
            )
        )

        if args.json:

            output = {
                **data,
                "recommendations":
                    recommendations,
            }

            print(
                json.dumps(
                    output,
                    indent=2,
                    ensure_ascii=False,
                )
            )

        else:

            print_report(
                data,
                recommendations,
            )

    except Exception as error:

        print(
            f"ERROR: {error}"
        )

        sys.exit(1)


if __name__ == "__main__":
    main()