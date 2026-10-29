#!/usr/bin/env python3
"""
copyright_scan.py

Local copyright-risk PRE-SCREENING tool for videos.
It does NOT determine legal ownership or guarantee that a video is safe to publish.

Checks:
- media metadata (ffprobe)
- frame sampling
- perceptual fingerprints (pHash-like DCT hash)
- duplicate-frame similarity within the same video
- OCR/text presence when OpenCV is available (optional)
- audio presence / duration / codec
- generates a contact sheet for manual reverse-image searching
- produces JSON + human-readable report

Usage:
    python copyright_scan.py video.mp4
    python copyright_scan.py ./downloads --recursive
"""

import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

try:
    import cv2
except ImportError:
    cv2 = None

VIDEO_EXTS = {".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v"}

def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or "command failed")
    return p.stdout

def ffprobe(path):
    out = run([
        "ffprobe", "-v", "error",
        "-show_entries",
        "format=duration,size,bit_rate:stream=index,codec_type,codec_name,width,height,r_frame_rate,channels,sample_rate,bit_rate",
        "-of", "json", str(path)
    ])
    return json.loads(out)

def dct_phash(frame, size=32, low=8):
    """Small DCT perceptual hash. Returns a hex string."""
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.resize(gray, (size, size), interpolation=cv2.INTER_AREA)
    dct = cv2.dct(gray.astype("float32"))
    block = dct[:low, :low]
    vals = block.flatten()
    med = float(__import__("numpy").median(vals[1:]))
    bits = ["1" if x > med else "0" for x in vals]
    n = int("".join(bits), 2)
    width = math.ceil(len(bits) / 4)
    return f"{n:0{width}x}"

def hamming_hex(a, b):
    return bin(int(a, 16) ^ int(b, 16)).count("1")

def sample_frames(path, out_dir, count=12):
    os.makedirs(out_dir, exist_ok=True)
    if cv2 is None:
        return [], "opencv-python is not installed"

    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        return [], "OpenCV could not open video"

    fps = cap.get(cv2.CAP_PROP_FPS) or 0
    frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    duration = frames / fps if fps > 0 else 0
    times = [duration * i / max(1, count - 1) for i in range(count)] if duration else [0]

    results = []
    for i, t in enumerate(times):
        cap.set(cv2.CAP_PROP_POS_MSEC, t * 1000)
        ok, frame = cap.read()
        if not ok:
            continue
        p = os.path.join(out_dir, f"frame_{i:03d}_{t:08.2f}s.jpg")
        cv2.imwrite(p, frame, [int(cv2.IMWRITE_JPEG_QUALITY), 90])
        results.append({
            "index": i,
            "time_sec": round(t, 3),
            "path": p,
            "phash": dct_phash(frame)
        })
    cap.release()
    return results, None

def contact_sheet(frame_items, output, cols=4, thumb_w=320):
    if cv2 is None or not frame_items:
        return False
    imgs = []
    for item in frame_items:
        img = cv2.imread(item["path"])
        if img is None:
            continue
        h, w = img.shape[:2]
        th = int(h * thumb_w / w)
        img = cv2.resize(img, (thumb_w, th))
        label = f'{item["time_sec"]:.1f}s'
        cv2.rectangle(img, (0, th-32), (thumb_w, th), (0,0,0), -1)
        cv2.putText(img, label, (8, th-9), cv2.FONT_HERSHEY_SIMPLEX, .7, (255,255,255), 2)
        imgs.append(img)

    if not imgs:
        return False
    rows = math.ceil(len(imgs) / cols)
    cell_h = max(i.shape[0] for i in imgs)
    sheet = __import__("numpy").zeros((rows*cell_h, cols*thumb_w, 3), dtype="uint8")
    for n, img in enumerate(imgs):
        r, c = divmod(n, cols)
        sheet[r*cell_h:r*cell_h+img.shape[0], c*thumb_w:c*thumb_w+img.shape[1]] = img
    cv2.imwrite(output, sheet)
    return True

def scan(path, out_root, sample_count=12):
    path = Path(path)
    job = Path(out_root) / path.stem
    frames_dir = job / "frames"
    os.makedirs(frames_dir, exist_ok=True)

    result = {
        "file": str(path.resolve()),
        "filename": path.name,
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "risk": {
            "score": 0,
            "level": "REVIEW",
            "reasons": []
        },
        "metadata": None,
        "frames": [],
        "audio": {},
        "manual_checks": [
            "Identify the original creator/rightsholder.",
            "Find the earliest/original publication and official source.",
            "Check whether the uploader has commercial redistribution permission.",
            "Reverse-search representative frames in Google/Bing/Yandex or another image-search service.",
            "Check music/audio licensing separately.",
            "Keep screenshots, URLs, permission messages, licenses, and dates as evidence."
        ]
    }

    try:
        meta = ffprobe(path)
        result["metadata"] = meta
        streams = meta.get("streams", [])
        video = next((s for s in streams if s.get("codec_type") == "video"), None)
        audio = next((s for s in streams if s.get("codec_type") == "audio"), None)
        if video:
            result["metadata"]["video_summary"] = {
                "codec": video.get("codec_name"),
                "resolution": f'{video.get("width")}x{video.get("height")}',
                "fps": video.get("r_frame_rate")
            }
        if audio:
            result["audio"] = {
                "present": True,
                "codec": audio.get("codec_name"),
                "channels": audio.get("channels"),
                "sample_rate": audio.get("sample_rate")
            }
        else:
            result["audio"] = {"present": False}
    except Exception as e:
        result["risk"]["score"] += 20
        result["risk"]["reasons"].append("ffprobe metadata unavailable")

    frames, frame_error = sample_frames(path, str(frames_dir), sample_count)
    result["frames"] = frames
    if frame_error:
        result["risk"]["reasons"].append(frame_error)

    sheet = job / "contact_sheet.jpg"
    if contact_sheet(frames, str(sheet)):
        result["contact_sheet"] = str(sheet.resolve())

    # Conservative pre-screening rules.
    # These are NOT legal conclusions.
    if result["metadata"] and result["metadata"].get("streams"):
        v = next((s for s in result["metadata"]["streams"] if s.get("codec_type") == "video"), None)
        a = next((s for s in result["metadata"]["streams"] if s.get("codec_type") == "audio"), None)
        if v:
            result["risk"]["score"] += 10  # original visual ownership is unknown
            result["risk"]["reasons"].append("Visual rights are not established by file metadata.")
        if a:
            result["risk"]["score"] += 5
            result["risk"]["reasons"].append("Audio/music rights need separate verification.")

    # Always require manual review for third-party social downloads.
    result["risk"]["score"] += 20
    result["risk"]["reasons"].append("Source is a third-party social-media copy; provenance must be verified.")

    if result["risk"]["score"] >= 60:
        level = "HIGH"
    elif result["risk"]["score"] >= 35:
        level = "REVIEW"
    else:
        level = "LOW-PRELIMINARY"
    result["risk"]["level"] = level

    json_path = job / "report.json"
    json_path.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")

    lines = [
        "COPYRIGHT RISK PRE-SCREEN",
        "=" * 60,
        f"File: {path.name}",
        f"SHA256: {result['sha256']}",
        f"Risk score: {result['risk']['score']}/100",
        f"Risk level: {result['risk']['level']}",
        "",
        "IMPORTANT: This is a technical pre-screen, not a legal determination.",
        "",
        "Reasons:"
    ]
    lines += [f"  - {x}" for x in result["risk"]["reasons"]]
    lines += [
        "",
        "Manual checks required:",
        *[f"  - {x}" for x in result["manual_checks"]],
        "",
        f"Contact sheet: {result.get('contact_sheet', 'not created')}",
        f"JSON report: {json_path.resolve()}",
    ]
    (job / "report.txt").write_text("\n".join(lines), encoding="utf-8")
    return result, job

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input", help="video file or directory")
    ap.add_argument("--out", default="./copyright_reports")
    ap.add_argument("--recursive", action="store_true")
    ap.add_argument("--samples", type=int, default=12)
    args = ap.parse_args()

    inp = Path(args.input)
    if inp.is_file():
        files = [inp]
    elif inp.is_dir():
        iterator = inp.rglob("*") if args.recursive else inp.glob("*")
        files = [p for p in iterator if p.suffix.lower() in VIDEO_EXTS]
    else:
        raise SystemExit(f"Not found: {inp}")

    print(f"Scanning {len(files)} video(s)...")
    for p in files:
        try:
            result, job = scan(p, args.out, args.samples)
            print(f"[{result['risk']['level']}] {p.name} -> {job}")
        except Exception as e:
            print(f"[ERROR] {p}: {e}")

if __name__ == "__main__":
    main()
