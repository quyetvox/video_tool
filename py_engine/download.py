#!/usr/bin/env python3
"""
Douyin / Direct Video Link Batch Downloader
==========================================
Usage:
    python download.py <path_to_links.txt> [options]

Features:
    - Automatically creates a 'downloaded/' directory in the same folder as the input .txt file.
    - Deduplicates links based on content MD5 hash in URL path.
    - Selects max bitrate URL if duplicates exist.
    - Supports batch limit (--limit / -n) and offset (--start / -s) to protect disk space.
    - Skips existing valid MP4 files for fast resume capability.
"""

from __future__ import annotations

import re
import sys
import time
import json
import hashlib
import argparse
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from typing import NamedTuple
import requests

# Request settings
CONNECT_TIMEOUT = 10          # seconds to establish connection
READ_TIMEOUT    = 15          # seconds waiting for data chunks
TIMEOUT         = (CONNECT_TIMEOUT, READ_TIMEOUT)
CHUNK_SIZE      = 512 * 1024  # 512 KB chunks
RETRY           = 2           # attempts per video
RETRY_WAIT      = 2           # seconds between retries

HEADERS = {
    "User-Agent":      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Referer":         "https://www.douyin.com/",
    "Accept":          "*/*",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8,vi;q=0.7",
    "Accept-Encoding": "identity",
    "Connection":      "keep-alive",
    "Range":           "bytes=0-",
}


class VideoLink(NamedTuple):
    raw_url:      str
    content_hash: str   # MD5 segment in URL path → unique video ID
    bitrate:      int   # br= param (kbps) → quality indicator
    post_time:    str   # Formatted timestamp e.g. "20260816_112513"
    unix_ts:      int   # Unix timestamp integer for accurate chronological sorting
    filename:     str   # Computed filename e.g. "20260816_112513_8fa7d616.mp4"


def parse_url(url: str) -> VideoLink | None:
    """Extract content_hash, bitrate, and publishing timestamp from any Douyin/ByteDance URL."""
    url = url.strip()
    if not url or not url.startswith("http"):
        return None
    try:
        parsed = urlparse(url)
        segments = [s for s in parsed.path.split("/") if s]
        qs = parse_qs(parsed.query)
        bitrate = int(qs.get("br", ["0"])[0])

        # 1. Full Hash & Short Hash (32-char hex MD5 from CDN path or MD5 of URL)
        content_hash = segments[0] if segments and len(segments[0]) >= 16 else ""
        if not content_hash:
            content_hash = hashlib.md5(url.encode("utf-8")).hexdigest()
        short_hash = content_hash[:8]

        # 2. Extract Publishing Timestamp
        unix_ts = None
        post_time_str = ""

        # Strategy A: Douyin Web Video ID / modal_id (Snowflake 64-bit ID)
        vid_match = re.search(r'(?:video/|modal_id=|aweme_id=)(\d{18,20})', url)
        if vid_match:
            try:
                vid_int = int(vid_match.group(1))
                ts = vid_int >> 32
                if 1500000000 <= ts <= 2500000000:
                    unix_ts = ts
                    post_time_str = datetime.fromtimestamp(ts).strftime("%Y%m%d_%H%M%S")
            except Exception:
                pass

        # Strategy B: Parameter l=YYYYMMDDHHMMSS... (Log ID timestamp)
        if not unix_ts and "l" in qs:
            log_id = qs["l"][0]
            if len(log_id) >= 14 and log_id[:14].isdigit():
                try:
                    dt = datetime.strptime(log_id[:14], "%Y%m%d%H%M%S")
                    unix_ts = int(dt.timestamp())
                    post_time_str = dt.strftime("%Y%m%d_%H%M%S")
                except Exception:
                    pass

        # Strategy C: Parameter dy_q=... (Unix epoch timestamp)
        if not unix_ts and "dy_q" in qs:
            try:
                ts = int(qs["dy_q"][0])
                if 1500000000 <= ts <= 2500000000:
                    unix_ts = ts
                    post_time_str = datetime.fromtimestamp(ts).strftime("%Y%m%d_%H%M%S")
            except Exception:
                pass

        # Strategy D: Hex timestamp in path segment (e.g. /6a8158b3/)
        if not unix_ts and len(segments) > 1:
            hex_cand = segments[1]
            if len(hex_cand) == 8:
                try:
                    ts = int(hex_cand, 16)
                    if 1500000000 <= ts <= 2500000000:
                        unix_ts = ts
                        post_time_str = datetime.fromtimestamp(ts).strftime("%Y%m%d_%H%M%S")
                except Exception:
                    pass

        # Strategy E: Fallback to current system timestamp if cannot be extracted
        if not unix_ts:
            now = datetime.now()
            unix_ts = int(now.timestamp())
            post_time_str = now.strftime("%Y%m%d_%H%M%S")

        filename = f"{post_time_str}_{short_hash}.mp4"

        return VideoLink(
            raw_url=url,
            content_hash=content_hash,
            bitrate=bitrate,
            post_time=post_time_str,
            unix_ts=unix_ts,
            filename=filename
        )
    except Exception:
        return None


def load_and_deduplicate(links_file: Path) -> tuple[list[VideoLink], dict]:
    """Parse URLs from file, deduplicate by content_hash keeping max bitrate, and sort chronologically."""
    raw_lines = [l.strip() for l in links_file.read_text(encoding="utf-8").splitlines() if l.strip()]
    total_raw = len(raw_lines)

    parsed: list[VideoLink] = []
    skipped_parse = 0
    for line in raw_lines:
        v = parse_url(line)
        if v:
            parsed.append(v)
        else:
            skipped_parse += 1

    best: dict[str, VideoLink] = {}
    duplicates: list[dict] = []

    for v in parsed:
        if v.content_hash not in best:
            best[v.content_hash] = v
        else:
            existing = best[v.content_hash]
            if v.bitrate > existing.bitrate:
                duplicates.append({"kept": v.raw_url[:80], "removed": existing.raw_url[:80],
                                   "reason": f"lower bitrate ({existing.bitrate} < {v.bitrate})"})
                best[v.content_hash] = v
            else:
                duplicates.append({"kept": existing.raw_url[:80], "removed": v.raw_url[:80],
                                   "reason": f"lower bitrate ({v.bitrate} <= {existing.bitrate})"})

    unique = list(best.values())

    # Sort chronologically by unix_ts (Oldest / Earliest post first)
    unique.sort(key=lambda v: (v.unix_ts, v.content_hash))

    report = {
        "total_raw":          total_raw,
        "skipped_parse":      skipped_parse,
        "duplicates_removed": len(duplicates),
        "unique_to_download": len(unique),
        "duplicates":         duplicates,
    }
    return unique, report


def format_bytes(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def download_one(video: VideoLink, out_path: Path, prefix: str = "") -> tuple[bool, str]:
    """Download a single video. Returns (success, message)."""
    for attempt in range(1, RETRY + 1):
        try:
            resp = requests.get(
                video.raw_url,
                headers=HEADERS,
                stream=True,
                timeout=TIMEOUT,
                allow_redirects=True,
            )
            if resp.status_code not in (200, 206):
                msg = f"HTTP {resp.status_code}"
                if attempt < RETRY:
                    time.sleep(RETRY_WAIT)
                    continue
                return False, msg

            content_type = resp.headers.get("Content-Type", "")
            if "text/html" in content_type:
                return False, "Got HTML response — link likely expired"

            total_size = int(resp.headers.get("content-length", 0))
            downloaded = 0
            t_last_print = 0.0

            with open(out_path, "wb") as f:
                for chunk in resp.iter_content(CHUNK_SIZE):
                    if chunk:
                        f.write(chunk)
                        downloaded += len(chunk)
                        now = time.time()
                        if now - t_last_print > 0.3:
                            t_last_print = now
                            if total_size > 0:
                                pct = downloaded / total_size * 100
                                print(f"\r{prefix} ⬇  {out_path.name}  [br={video.bitrate}kbps]  {format_bytes(downloaded)} / {format_bytes(total_size)} ({pct:.0f}%)    ", end="", flush=True)
                            else:
                                print(f"\r{prefix} ⬇  {out_path.name}  [br={video.bitrate}kbps]  {format_bytes(downloaded)}    ", end="", flush=True)

            if downloaded < 10_000:
                out_path.unlink(missing_ok=True)
                return False, f"File too small ({downloaded} bytes) — likely broken"

            return True, format_bytes(downloaded)

        except requests.exceptions.Timeout:
            if attempt < RETRY:
                time.sleep(RETRY_WAIT)
                continue
            return False, f"Timeout after {READ_TIMEOUT}s"
        except Exception as e:
            if attempt < RETRY:
                time.sleep(RETRY_WAIT)
                continue
            return False, str(e)

    return False, "All retries exhausted"


def _bar(done: int, total: int, width: int = 30) -> str:
    filled = int(width * done / total) if total else 0
    return f"[{'█' * filled}{'░' * (width - filled)}]"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Douyin / Video Direct Links Downloader (Auto folder cùng cấp)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Tải tất cả video từ file (tự tạo thư mục downloaded/ cùng cấp với file txt)
  python download.py input/foods/douyin-video-links.txt

  # Chỉ tải 5 video mỗi lần (tránh đầy ổ cứng):
  python download.py input/foods/douyin-video-links.txt --limit 5

  # Bắt đầu từ video thứ 10, tải 5 video:
  python download.py input/foods/douyin-video-links.txt --start 10 --limit 5

  # Chỉ định thư mục lưu tùy chỉnh:
  python download.py input/foods/douyin-video-links.txt -o custom_folder/
"""
    )
    parser.add_argument("links_file", help="Path to text file containing video URLs")
    parser.add_argument("-o", "--output-dir", default=None, help="Custom output directory (default: 'downloaded' folder alongside input .txt)")
    parser.add_argument("-n", "--limit", type=int, default=None, help="Maximum number of videos to download in this run")
    parser.add_argument("-s", "--start", type=int, default=1, help="Start downloading from video index N (1-indexed, default: 1)")
    parser.add_argument("-f", "--force", action="store_true", help="Force download even if destination file already exists")

    args = parser.parse_args()

    links_file = Path(args.links_file).resolve()
    if not links_file.exists():
        print(f"❌ Error: File not found: {links_file}", file=sys.stderr)
        sys.exit(1)

    # Auto-target project src/ folder if not explicitly specified
    if args.output_dir:
        out_dir = Path(args.output_dir).resolve()
    else:
        if links_file.parent.name == "src":
            out_dir = links_file.parent
        else:
            out_dir = links_file.parent / "src"

    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n🔍 Parsing links from: {links_file}")
    unique, report = load_and_deduplicate(links_file)

    print(f"   Total raw links      : {report['total_raw']}")
    print(f"   Skipped (bad parse)  : {report['skipped_parse']}")
    print(f"   Duplicates removed   : {report['duplicates_removed']}")
    print(f"   ✅ Unique videos     : {report['unique_to_download']}")

    if report["duplicates"]:
        print("\n   Duplicate details:")
        for d in report["duplicates"]:
            print(f"     REMOVE  {d['removed']}…")
            print(f"     KEEP    {d['kept']}…  ({d['reason']})")

    report_path = out_dir / "dedup_report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    if not unique:
        print("\n⚠️ No valid links to download. Exiting.")
        return

    # Filter queue by start and limit
    start_idx = max(1, args.start)
    end_idx = len(unique)
    if args.limit is not None and args.limit > 0:
        end_idx = min(len(unique), start_idx + args.limit - 1)

    target_queue = list(enumerate(unique, 1))[start_idx - 1 : end_idx]

    print(f"\n📥 Downloading batch: index {start_idx} → {end_idx} (total {len(target_queue)} videos in queue) → {out_dir}/")
    print(f"   Timeout: ({CONNECT_TIMEOUT}, {READ_TIMEOUT})s | Retry: {RETRY}x | Chunk: {format_bytes(CHUNK_SIZE)}\n")

    ok_count   = 0
    fail_count = 0
    skip_count = 0
    fail_log: list[dict] = []
    t0 = time.time()

    for i, video in target_queue:
        out_path = out_dir / video.filename
        bar = _bar(i - 1, len(unique))
        prefix = f"  {bar} [{i:03d}/{len(unique)}]"

        if not args.force and out_path.exists() and out_path.stat().st_size > 10_000:
            print(f"{prefix} ⏭  {out_path.name}  (skip — already exists, {format_bytes(out_path.stat().st_size)})")
            skip_count += 1
            continue

        print(f"{prefix} ⬇  {out_path.name}  [br={video.bitrate}kbps]  0 KB", end="", flush=True)
        success, msg = download_one(video, out_path, prefix=prefix)

        if success:
            ok_count += 1
            print(f"\r{prefix} ⬇  {out_path.name}  [br={video.bitrate}kbps]  ✅ {msg}                    ")
        else:
            fail_count += 1
            out_path.unlink(missing_ok=True)
            fail_log.append({"index": i, "file": out_path.name, "error": msg, "url": video.raw_url})
            print(f"\r{prefix} ⬇  {out_path.name}  [br={video.bitrate}kbps]  ❌ {msg}                    ")

    elapsed = time.time() - t0
    print(f"\n{'─' * 60}")
    print(f"✅ Downloaded : {ok_count}")
    print(f"⏭  Skipped   : {skip_count}")
    print(f"❌ Failed     : {fail_count}")
    print(f"⏱  Total time : {elapsed:.1f}s")
    print(f"📁 Output dir : {out_dir}")

    if fail_log:
        fail_path = out_dir / "failed_downloads.json"
        fail_path.write_text(json.dumps(fail_log, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"\n⚠️  {fail_count} failed downloads logged → {fail_path}")

    print()


if __name__ == "__main__":
    main()
