#!/usr/bin/env python3
"""
Media Link Tool
===============
Universal Video URL Prober & Downloader for Sub-Video.
Supports YouTube, TikTok, Douyin, Facebook, Bilibili, and direct CDN/MP4 URLs.

Usage:
    python media_link_tool.py probe <url>
    python media_link_tool.py download <url> --out-dir <dir> [--filename <custom_name>]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any
import urllib.parse
import urllib.request
import ssl
import shutil

try:
    import yt_dlp
    HAS_YT_DLP = True
except ImportError:
    HAS_YT_DLP = False

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False


def find_ffmpeg() -> str | None:
    """Find ffmpeg binary location across macOS, Windows and portable paths."""
    candidates = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        os.path.expanduser("~/.local/bin/ffmpeg"),
    ]
    # Check project/app bundled bin directory
    tool_file = Path(__file__).resolve()
    engine_dir = tool_file.parent.parent  # py_engine
    project_root = engine_dir.parent
    candidates.extend([
        str(project_root / "bin" / "ffmpeg"),
        str(project_root / "bin" / "ffmpeg.exe"),
        str(engine_dir / "bin" / "ffmpeg"),
        str(engine_dir / "bin" / "ffmpeg.exe"),
    ])
    which_ffmpeg = shutil.which("ffmpeg")
    if which_ffmpeg:
        candidates.append(which_ffmpeg)

    for c in candidates:
        if c and Path(c).is_file() and os.access(c, os.X_OK):
            # Prepend directory to PATH so subprocesses inherit it
            p_dir = str(Path(c).parent)
            current_path = os.environ.get("PATH", "")
            if p_dir not in current_path.split(os.pathsep):
                os.environ["PATH"] = f"{p_dir}{os.pathsep}{current_path}"
            return c
    return None


def sanitize_filename(name: str, max_len: int = 80) -> str:
    """Sanitize title to a safe file name across Windows and macOS."""
    name = name.strip()
    # Remove control characters and illegal filename characters
    name = re.sub(r'[\\/*?:"<>|]', '_', name)
    # Remove newlines / tabs
    name = re.sub(r'[\r\n\t]+', ' ', name).strip()
    if not name:
        name = f"video_{int(time.time())}"
    if len(name) > max_len:
        name = name[:max_len].strip()
    return name


def format_bytes(n: float | int | None) -> str:
    if not n or n <= 0:
        return "0 KB"
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def format_speed(speed: float | None) -> str:
    if not speed or speed <= 0:
        return "-- MB/s"
    return f"{speed / (1024 * 1024):.1f} MB/s"


def format_eta(eta: int | float | None) -> str:
    if eta is None or eta < 0:
        return "--:--"
    m, s = divmod(int(eta), 60)
    h, m = divmod(m, 60)
    if h > 0:
        return f"{h:02d}:{m:02d}:{s:02d}"
    return f"{m:02d}:{s:02d}"


def is_direct_media_url(url: str) -> bool:
    """Check if URL points directly to a video file."""
    clean_url = url.split('?')[0].lower()
    return clean_url.endswith(('.mp4', '.mov', '.mkv', '.webm', '.m4v', '.flv', '.ts'))


def probe_direct_url(url: str) -> dict[str, Any]:
    """Fallback probe for direct media link using HTTP HEAD."""
    try:
        parsed = urllib.parse.urlparse(url)
        path = parsed.path
        filename = Path(path).name if path else f"video_{int(time.time())}.mp4"
        title = Path(filename).stem or "Direct Video"

        duration = 0.0
        content_length = 0

        if HAS_REQUESTS:
            resp = requests.head(url, timeout=10, allow_redirects=True)
            content_length = int(resp.headers.get("content-length", 0))
        else:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=10, context=ctx) as response:
                content_length = int(response.headers.get("content-length", 0))

        return {
            "success": True,
            "title": title,
            "duration": duration,
            "thumbnail": "",
            "stream_url": url,
            "raw_url": url,
            "size_bytes": content_length,
        }
    except Exception as e:
        return {
            "success": False,
            "error": f"Không thể kiểm tra link trực tiếp: {str(e)}",
            "raw_url": url,
        }


def probe_url(url: str) -> dict[str, Any]:
    """Probe video URL metadata and playable CDN stream URL."""
    url = url.strip()
    if not url or not url.startswith("http"):
        return {"success": False, "error": "URL không hợp lệ (phải bắt đầu bằng http:// hoặc https://)"}

    # Fast path for direct video links
    if is_direct_media_url(url):
        res = probe_direct_url(url)
        if res.get("success"):
            return res

    if not HAS_YT_DLP:
        # Fallback to direct probe if yt_dlp is missing
        return probe_direct_url(url)

    ydl_opts = {
        "quiet": True,
        "no_warnings": True,
        "skip_download": True,
        "extract_flat": False,
        "noplaylist": True,
        "nocheckcertificate": True,
        "prefer_insecure": False,
        "socket_timeout": 12,
    }

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=False)
            if not info:
                return {"success": False, "error": "Không thể trích xuất thông tin video từ link này"}

            title = info.get("title") or "Video"
            duration = float(info.get("duration") or 0.0)
            thumbnail = info.get("thumbnail") or ""

            # Resolve direct stream URL and optional audio URL for in-app preview
            stream_url = ""
            audio_url = ""
            formats = info.get("formats", [])

            # 1. Look for progressive MP4 (audio + video together)
            progressive = [
                f for f in formats
                if f.get("ext") == "mp4"
                and f.get("vcodec") != "none"
                and f.get("acodec") != "none"
                and f.get("url")
            ]
            if progressive:
                # Prefer ~720p or highest available resolution
                progressive.sort(key=lambda x: x.get("height") or 0, reverse=True)
                reasonable = [f for f in progressive if (f.get("height") or 0) <= 1080]
                stream_url = (reasonable[0] if reasonable else progressive[0]).get("url", "")

            # 2. Look for HLS / m3u8 if no progressive mp4 found
            if not stream_url:
                hls_formats = [
                    f for f in formats
                    if (f.get("protocol") or "").startswith("m3u8")
                    and f.get("url")
                ]
                if hls_formats:
                    hls_formats.sort(key=lambda x: x.get("height") or 0, reverse=True)
                    stream_url = hls_formats[0].get("url", "")

            # 3. Look for separated DASH video + audio (e.g. Bilibili, YouTube DASH)
            if not stream_url:
                video_only = [
                    f for f in formats
                    if f.get("vcodec") != "none"
                    and f.get("url")
                ]
                audio_only = [
                    f for f in formats
                    if f.get("acodec") != "none"
                    and f.get("url")
                ]
                if video_only:
                    video_only.sort(key=lambda x: x.get("height") or 0, reverse=True)
                    # Filter preferred around <= 1080p for smooth streaming preview
                    reasonable_v = [f for f in video_only if (f.get("height") or 0) <= 1080]
                    stream_url = (reasonable_v[0] if reasonable_v else video_only[0]).get("url", "")

                if audio_only:
                    audio_only.sort(key=lambda x: x.get("tbr") or x.get("abr") or 0, reverse=True)
                    audio_url = audio_only[0].get("url", "")

            # 4. Fallback: check info['url'] only if it's an actual media URL
            if not stream_url:
                cand = info.get("url", "")
                if cand and cand != url and not cand.endswith(('.html', '.htm', '/')):
                    stream_url = cand

            if not stream_url:
                return {"success": False, "error": "Không tìm thấy luồng video trực tiếp để phát", "raw_url": url}

            http_headers = info.get("http_headers", {})
            if "Referer" not in http_headers and "referer" not in http_headers:
                if "bilibili.com" in url:
                    http_headers["Referer"] = "https://www.bilibili.com/"

            return {
                "success": True,
                "title": title,
                "duration": duration,
                "thumbnail": thumbnail,
                "stream_url": stream_url,
                "audio_url": audio_url,
                "http_headers": http_headers,
                "raw_url": url,
            }
    except Exception as e:
        err_msg = str(e)
        if "Private video" in err_msg:
            err_msg = "Video ở chế độ riêng tư, không thể truy cập"
        elif "Video unavailable" in err_msg:
            err_msg = "Video không tồn tại hoặc đã bị gỡ bỏ"
        elif "Sign in" in err_msg:
            err_msg = "Video yêu cầu đăng nhập tài khoản để xem"
        elif "timed out" in err_msg.lower():
            err_msg = "Kết nối quá hạn khi kiểm tra video"
        return {"success": False, "error": err_msg, "raw_url": url}


def download_url(url: str, out_dir: str, custom_filename: str | None = None) -> dict[str, Any]:
    """Download video with realtime progress reporting on stdout."""
    url = url.strip()
    out_path_dir = Path(out_dir)
    out_path_dir.mkdir(parents=True, exist_ok=True)

    # First probe for title & metadata
    probe_info = probe_url(url)
    title = probe_info.get("title") or "video"
    raw_name = custom_filename if custom_filename else title
    safe_name = sanitize_filename(raw_name)

    # Determine unique target filename
    target_file = out_path_dir / f"{safe_name}.mp4"
    if target_file.exists():
        short_hash = f"{int(time.time()) % 10000:04d}"
        target_file = out_path_dir / f"{safe_name}_{short_hash}.mp4"

    if not HAS_YT_DLP and is_direct_media_url(url):
        # Direct download fallback using requests / urllib
        return _download_direct_fallback(url, target_file)

    # Progress hook for yt-dlp
    last_print = 0.0

    def progress_hook(d: dict[str, Any]):
        nonlocal last_print
        status = d.get("status")
        if status == "downloading":
            now = time.time()
            if now - last_print < 0.25:
                return
            last_print = now

            total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
            downloaded = d.get("downloaded_bytes") or 0
            speed = d.get("speed")
            eta = d.get("eta")

            pct = (downloaded / total * 100.0) if total > 0 else 0.0
            speed_str = format_speed(speed)
            eta_str = format_eta(eta)

            print(f"PROGRESS: {pct:.1f}% | SPEED: {speed_str} | ETA: {eta_str}", flush=True)

        elif status == "finished":
            print(f"PROGRESS: 100.0% | Processing...", flush=True)

    ffmpeg_bin = find_ffmpeg()
    has_ffmpeg = bool(ffmpeg_bin)
    format_spec = "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" if has_ffmpeg else "best[ext=mp4]/best"

    ydl_opts = {
        "format": format_spec,
        "outtmpl": str(target_file.with_suffix(".%(ext)s")),
        "merge_output_format": "mp4",
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "nocheckcertificate": True,
        "prefer_insecure": False,
        "progress_hooks": [progress_hook],
        "socket_timeout": 20,
    }
    if ffmpeg_bin:
        ydl_opts["ffmpeg_location"] = ffmpeg_bin

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.download([url])

        # Verify output file
        actual_output = target_file
        if not actual_output.exists():
            # Check if ext differed before merge
            candidates = list(out_path_dir.glob(f"{target_file.stem}.*"))
            if candidates:
                actual_output = candidates[0]

        if actual_output.exists() and actual_output.stat().st_size > 0:
            print(f"COMPLETED: {actual_output.resolve()}", flush=True)
            return {
                "success": True,
                "file_path": str(actual_output.resolve()),
                "filename": actual_output.name,
                "title": title,
                "size_bytes": actual_output.stat().st_size,
            }
        else:
            return {"success": False, "error": "File sau khi tải không tồn tại hoặc có dung lượng 0 bytes"}
    except Exception as e:
        err = str(e)
        print(f"ERROR: {err}", flush=True)
        return {"success": False, "error": f"Lỗi tải video: {err}"}


def _download_direct_fallback(url: str, target_file: Path) -> dict[str, Any]:
    """Download direct file in chunks with stdout PROGRESS reporting."""
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})

        with urllib.request.urlopen(req, timeout=15, context=ctx) as response:
            total_size = int(response.headers.get("content-length", 0))
            downloaded = 0
            chunk_size = 512 * 1024
            last_print = 0.0
            start_time = time.time()

            with open(target_file, "wb") as out_f:
                while True:
                    chunk = response.read(chunk_size)
                    if not chunk:
                        break
                    out_f.write(chunk)
                    downloaded += len(chunk)

                    now = time.time()
                    if now - last_print > 0.25:
                        last_print = now
                        elapsed = now - start_time
                        speed = downloaded / elapsed if elapsed > 0 else 0
                        eta = (total_size - downloaded) / speed if (speed > 0 and total_size > downloaded) else 0
                        pct = (downloaded / total_size * 100.0) if total_size > 0 else 0.0
                        print(f"PROGRESS: {pct:.1f}% | SPEED: {format_speed(speed)} | ETA: {format_eta(eta)}", flush=True)

        print(f"PROGRESS: 100.0% | Done", flush=True)
        print(f"COMPLETED: {target_file.resolve()}", flush=True)
        return {
            "success": True,
            "file_path": str(target_file.resolve()),
            "filename": target_file.name,
            "size_bytes": target_file.stat().st_size,
        }
    except Exception as e:
        return {"success": False, "error": f"Lỗi tải file trực tiếp: {str(e)}"}


def main():
    parser = argparse.ArgumentParser(description="Media Link Tool for Sub-Video")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Probe command
    probe_parser = subparsers.add_parser("probe", help="Probe video URL metadata and CDN stream URL")
    probe_parser.add_argument("url", help="Video URL to probe")
    probe_parser.add_argument("--json", action="store_true", default=True, help="Output single line JSON")

    # Download command
    download_parser = subparsers.add_parser("download", help="Download video URL to directory")
    download_parser.add_argument("url", help="Video URL to download")
    download_parser.add_argument("--out-dir", required=True, help="Destination directory (e.g. resources/<proj>/src/)")
    download_parser.add_argument("--filename", default=None, help="Optional custom base filename")

    args = parser.parse_args()

    if args.command == "probe":
        res = probe_url(args.url)
        print(json.dumps(res, ensure_ascii=False))
        sys.exit(0 if res.get("success") else 1)

    elif args.command == "download":
        res = download_url(args.url, args.out_dir, args.filename)
        if not res.get("success"):
            sys.exit(1)
        sys.exit(0)


if __name__ == "__main__":
    main()
