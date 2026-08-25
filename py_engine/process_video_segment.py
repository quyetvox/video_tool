#!/usr/bin/env python3
import argparse
import json
import os
import ssl
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import cv2


def translate_text(text: str, target_lang: str = "vi") -> str:
    if not text or not text.strip():
        return text
    text_clean = text.replace("\u63cd\u996d", "n\u1ea5u \u0103n").replace("\u505a\u996d", "n\u1ea5u \u0103n")
    try:
        ssl_ctx = ssl._create_unverified_context()
        url = (
            "https://translate.googleapis.com/translate_a/single?client=gtx&sl=zh-CN&tl="
            + target_lang + "&dt=t&q=" + urllib.parse.quote(text_clean)
        )
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, context=ssl_ctx, timeout=5) as response:
            res = json.loads(response.read().decode())
            translated = "".join([part[0] for part in res[0] if part[0]])
            translated = translated.replace("\u0111\u00e1nh \u0111\u1eadp", "n\u1ea5u \u0103n").replace("\u0111\u00e1nh c\u01a1m", "n\u1ea5u c\u01a1m")
            return translated.strip()
    except Exception as e:
        print(f"Warning: translate failed ({e}), keeping original.")
        return text


def get_ocr_engine():
    try:
        from paddleocr import PaddleOCR
        return PaddleOCR(
            use_doc_orientation_classify=False,
            use_doc_unwarping=False,
            lang="ch"
        )
    except Exception as e:
        print(f"ERROR init PaddleOCR: {e}")
        sys.exit(1)


def detect_subtitles_in_video(video_path: Path, sample_fps: float = 2.0) -> List[Dict[str, Any]]:
    ocr = get_ocr_engine()
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) or 1
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)) or 720
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)) or 1280
    step = max(1, int(fps / sample_fps))
    print(f"Scanning OCR ({total_frames} frames, FPS: {fps:.1f}, Step: {step})...")

    detected_segments: List[Dict[str, Any]] = []
    current_text = None
    segment_start_frame = 0
    last_frame_idx = 0
    current_boxes: List = []
    frame_idx = 0

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break
        if frame_idx % step == 0:
            res = ocr.ocr(frame)
            frame_text_items = []
            if res and len(res) > 0 and isinstance(res[0], dict):
                item = res[0]
                rec_texts = item.get("rec_texts", [])
                rec_boxes = item.get("rec_boxes", [])
                for i, text_val in enumerate(rec_texts):
                    if not text_val:
                        continue
                    if i < len(rec_boxes):
                        box = [int(v) for v in rec_boxes[i]]
                        x1, y1, x2, y2 = box
                        norm_box = [round(y1/height,4), round(x1/width,4), round(y2/height,4), round(x2/width,4)]
                        frame_text_items.append((str(text_val), norm_box))
            frame_text = " ".join([t[0] for t in frame_text_items]).strip()
            if frame_text != current_text:
                if current_text:
                    s = round(segment_start_frame / fps, 2)
                    e = round((frame_idx - 1) / fps, 2)
                    if e > s:
                        detected_segments.append({
                            "start": s, "end": e,
                            "text_zh": current_text,
                            "region": [
                                min(b[0] for b in current_boxes) if current_boxes else 0.3,
                                min(b[1] for b in current_boxes) if current_boxes else 0.1,
                                max(b[2] for b in current_boxes) if current_boxes else 0.4,
                                max(b[3] for b in current_boxes) if current_boxes else 0.9,
                            ]
                        })
                current_text = frame_text
                segment_start_frame = frame_idx
                current_boxes = [t[1] for t in frame_text_items]
            else:
                if frame_text_items:
                    current_boxes.extend([t[1] for t in frame_text_items])
        last_frame_idx = frame_idx
        frame_idx += 1
    cap.release()

    if current_text:
        s = round(segment_start_frame / fps, 2)
        e = round(last_frame_idx / fps, 2)
        if e > s:
            detected_segments.append({
                "start": s, "end": e,
                "text_zh": current_text,
                "region": [
                    min(b[0] for b in current_boxes) if current_boxes else 0.3,
                    min(b[1] for b in current_boxes) if current_boxes else 0.1,
                    max(b[2] for b in current_boxes) if current_boxes else 0.4,
                    max(b[3] for b in current_boxes) if current_boxes else 0.9,
                ]
            })

    for s in detected_segments:
        print(s)
    return detected_segments


def generate_ass_file(
    segments: List[Dict[str, Any]],
    ass_path: Path,
    vid_w: int,
    vid_h: int,
    font_size: int,
    margin_v: int,
) -> None:
    def fmt(sec: float) -> str:
        h = int(sec // 3600)
        m = int((sec % 3600) // 60)
        s = int(sec % 60)
        cs = int(round((sec - int(sec)) * 100))
        return f"{h}:{m:02d}:{s:02d}.{cs:02d}"

    lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        f"PlayResX: {vid_w}",
        f"PlayResY: {vid_h}",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, "
        "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, "
        "Alignment, MarginL, MarginR, MarginV, Encoding",
        f"Style: Default,Arial,{font_size},&H00FFFFFF,&H00000000,&H00000000,&H00000000,"
        f"1,0,0,0,100,100,0,0,1,2,0,8,10,10,{margin_v},1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    for seg in segments:
        text = seg.get("text_vi", seg.get("text_zh", "")).strip()
        if text:
            lines.append(f"Dialogue: 0,{fmt(seg['start'])},{fmt(seg['end'])},Default,,0,0,0,,{text}")
    ass_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def process_video_segment(
    video_path: Path,
    duration: Optional[float] = None,
    start_time: float = 0.0,
    output_path: Optional[Path] = None,
    font_size: int = 20,
) -> None:
    video_path = video_path.resolve()
    if not video_path.exists():
        print(f"ERROR: video not found: {video_path}")
        sys.exit(1)

    cap_info = cv2.VideoCapture(str(video_path))
    vid_fps = cap_info.get(cv2.CAP_PROP_FPS) or 25.0
    total_frames = int(cap_info.get(cv2.CAP_PROP_FRAME_COUNT)) or 1
    total_dur = round(total_frames / vid_fps, 2)
    vid_w = int(cap_info.get(cv2.CAP_PROP_FRAME_WIDTH)) or 720
    vid_h = int(cap_info.get(cv2.CAP_PROP_FRAME_HEIGHT)) or 1280
    cap_info.release()

    if duration is None or duration <= 0:
        duration = total_dur - start_time
        dur_str = f"Full ({duration:.1f}s)"
        dur_tag = ""
    else:
        dur_str = f"{duration:.1f}s"
        dur_tag = f"_{int(duration)}s"

    work_dir = video_path.parent.parent / "workspace" / f"proc_{video_path.stem}{dur_tag}"
    work_dir.mkdir(parents=True, exist_ok=True)

    if output_path is None:
        out_dir = video_path.parent.parent / "output"
        out_dir.mkdir(parents=True, exist_ok=True)
        output_path = out_dir / f"{video_path.stem}{dur_tag}_vi.mp4"
    else:
        output_path = output_path.resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("=== VIDEO TRANSLATION PIPELINE ===")
    print(f"Input : {video_path.name}  ({vid_w}x{vid_h}, {vid_fps:.0f}fps)")
    print(f"Segment: {start_time}s -> {start_time + duration:.1f}s  [{dur_str}]")
    print(f"Output : {output_path}")
    print("=" * 60)

    # Step 1: Cut segment
    trimmed = work_dir / "trimmed.mp4"
    print(f"\n[Step 1/5] Cutting segment ({dur_str})...")
    subprocess.run(
        ["ffmpeg", "-y", "-ss", str(start_time), "-i", str(video_path),
         "-t", str(duration), "-c:v", "libx264", "-preset", "fast", "-c:a", "aac", str(trimmed)],
        capture_output=True, check=True
    )
    print(f"  -> {trimmed.name}")

    # Step 2: OCR
    print("\n[Step 2/5] OCR scanning...")
    segments = detect_subtitles_in_video(trimmed)
    print(f"  -> Found {len(segments)} segments.")

    # Step 3: Translate
    print("\n[Step 3/5] Translating to Vietnamese...")
    for seg in segments:
        seg["text_vi"] = translate_text(seg["text_zh"], target_lang="vi")
        print(f"  [{seg['start']}s -> {seg['end']}s] {seg['text_zh']}  -->  {seg['text_vi']}")

    # Step 4: Per-segment blur — each sub blurred only at its own position & time
    blurred = work_dir / "blurred.mp4"
    print("\n[Step 4/5] Blurring original subtitles (per-segment)...")

    # Only keep real subtitle segments (not UI noise at top of screen)
    valid = [s for s in segments if s["region"][0] >= 0.15 and len(s["text_zh"].strip()) >= 3]
    if not valid:
        valid = [s for s in segments if s["region"][0] >= 0.15]

    if not valid:
        # No valid subs found, just copy trimmed -> blurred
        import shutil
        shutil.copy2(trimmed, blurred)
        print("  -> No subtitle regions detected, skipping blur.")
        # Use dummy box for subtitle placement
        global_cy, global_ch = int(vid_h * 0.30), int(vid_h * 0.06)
        global_cw = vid_w
    else:
        # Build per-segment filter_complex chain with safe label names (no colons)
        filter_parts = []
        prev_label = None  # None = use [0:v] directly as input
        for i, seg in enumerate(valid):
            t = max(0.0, seg["region"][0] - 0.005)
            l = max(0.0, seg["region"][1] - 0.015)
            b = min(1.0, seg["region"][2] + 0.005)
            r = min(1.0, seg["region"][3] + 0.015)

            cw_i = int(vid_w * (r - l)) // 2 * 2
            ch_i = int(vid_h * (b - t)) // 2 * 2
            cx_i = int(vid_w * l) // 2 * 2
            cy_i = int(vid_h * t) // 2 * 2

            seg["_cx"] = cx_i
            seg["_cy"] = cy_i
            seg["_cw"] = cw_i
            seg["_ch"] = ch_i

            # Input to this stage
            # Blur radius capped to ch_i//4 for safety with yuv420p chroma plane
            blur_r = min(8, max(2, ch_i // 4))
            in_ref = f"[{prev_label}]" if prev_label else "[0:v]"
            # Use gte*lte instead of between() to avoid comma-parsing issues in filter_complex
            enable = f"gte(t\\,{seg['start']})*lte(t\\,{seg['end']})"
            filter_parts.append(
                f"{in_ref}split[s{i}a][s{i}b];"
                f"[s{i}a]crop={cw_i}:{ch_i}:{cx_i}:{cy_i},boxblur={blur_r}:2[bl{i}];"
                f"[s{i}b][bl{i}]overlay={cx_i}:{cy_i}:enable='{enable}'[v{i}]"
            )
            prev_label = f"v{i}"
            print(f"  [{seg['start']}s-{seg['end']}s] blur {cw_i}x{ch_i}px at ({cx_i},{cy_i})")

        filter_complex = ";".join(filter_parts)
        last_label = prev_label  # e.g. "v4"
        cmd_blur = [
            "ffmpeg", "-y", "-i", str(trimmed),
            "-filter_complex", filter_complex,
            "-map", f"[{last_label}]", "-map", "0:a",
            "-c:v", "libx264", "-preset", "fast", "-c:a", "copy",
            str(blurred)
        ]
        result = subprocess.run(cmd_blur, capture_output=True)
        if result.returncode != 0:
            print("  -> Warning: per-segment blur failed, falling back to union box blur.")
            print(result.stderr.decode()[-500:])
            # Fallback: union box
            t0 = max(0.0, min(s["region"][0] for s in valid) - 0.005)
            l0 = max(0.0, min(s["region"][1] for s in valid) - 0.015)
            b0 = min(1.0, max(s["region"][2] for s in valid) + 0.005)
            r0 = min(1.0, max(s["region"][3] for s in valid) + 0.015)
            cw0 = int(vid_w * (r0 - l0)) // 2 * 2
            ch0 = int(vid_h * (b0 - t0)) // 2 * 2
            cx0 = int(vid_w * l0) // 2 * 2
            cy0 = int(vid_h * t0) // 2 * 2
            blur_r0 = min(8, max(2, ch0 // 4))
            vf = f"split[a][b];[a]crop={cw0}:{ch0}:{cx0}:{cy0},boxblur={blur_r0}:2[bl];[b][bl]overlay={cx0}:{cy0}"
            subprocess.run(
                ["ffmpeg", "-y", "-i", str(trimmed), "-filter_complex", vf,
                 "-c:v", "libx264", "-preset", "fast", "-c:a", "copy", str(blurred)],
                capture_output=True, check=True
            )
        # Global box for subtitle placement = most-common vertical band
        global_cy = int(min(s["_cy"] for s in valid))
        global_ch = int(max(s["_cy"] + s["_ch"] for s in valid)) - global_cy
        global_cw = int(max(s["_cw"] for s in valid))

    # Step 5: Render Vietnamese subtitles — per-segment ASS MarginV
    print("\n[Step 5/5] Rendering Vietnamese subtitles inside blur box...")
    ass_path = work_dir / "subtitles.ass"

    # Build per-segment entries with correct MarginV per segment position
    def fmt_ass_time(sec: float) -> str:
        h = int(sec // 3600)
        m = int((sec % 3600) // 60)
        s = int(sec % 60)
        cs = int(round((sec - int(sec)) * 100))
        return f"{h}:{m:02d}:{s:02d}.{cs:02d}"

    fit_font_size = font_size
    ass_lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        f"PlayResX: {vid_w}",
        f"PlayResY: {vid_h}",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, "
        "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, "
        "Alignment, MarginL, MarginR, MarginV, Encoding",
        f"Style: Default,Arial,{fit_font_size},&H00FFFFFF,&H00000000,&H00000000,&H00000000,"
        f"1,0,0,0,100,100,0,0,1,2,0,8,10,10,0,1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]

    for seg in segments:
        text = seg.get("text_vi", seg.get("text_zh", "")).strip()
        if not text:
            continue
        # Per-segment MarginV: center text within its own blur box
        if "_cy" in seg and "_ch" in seg:
            seg_ch = seg["_ch"]
            seg_cy = seg["_cy"]
            seg_fit = min(fit_font_size, max(16, seg_ch - 12))
            mv = seg_cy + max(2, (seg_ch - seg_fit) // 2)
        else:
            seg_fit = min(fit_font_size, max(16, global_ch - 12))
            mv = global_cy + max(2, (global_ch - seg_fit) // 2)
        ass_lines.append(
            f"Dialogue: 0,{fmt_ass_time(seg['start'])},{fmt_ass_time(seg['end'])},"
            f"Default,,0,0,{mv},,{text}"
        )
        print(f"  [{seg['start']}s] font={seg_fit}px MarginV={mv}px  -> {text[:40]}")

    ass_path.write_text("\n".join(ass_lines) + "\n", encoding="utf-8")

    ass_esc = str(ass_path).replace(":", "\\:")
    vf_sub = f"subtitles={ass_esc}"
    try:
        subprocess.run(
            ["ffmpeg", "-y", "-i", str(blurred), "-vf", vf_sub,
             "-c:v", "h264_videotoolbox", "-b:v", "4M", "-c:a", "aac", str(output_path)],
            capture_output=True, check=True
        )
    except Exception:
        subprocess.run(
            ["ffmpeg", "-y", "-i", str(blurred), "-vf", vf_sub,
             "-c:v", "libx264", "-preset", "fast", "-c:a", "aac", str(output_path)],
            capture_output=True, check=True
        )

    print("\n" + "=" * 60)
    print("DONE! Output: " + str(output_path))
    print("=" * 60)


def main():
    parser = argparse.ArgumentParser(
        description="Video translator: cut -> OCR -> translate -> blur original subs -> overlay new subs.\n"
                    "If -t is not provided, the ENTIRE video will be processed."
    )
    parser.add_argument("video_path", nargs="?", default="assets/cooking/src/video_001.mp4")
    parser.add_argument("-t", "--duration", type=float, default=None,
                        help="Duration in seconds. Omit to process the full video.")
    parser.add_argument("-s", "--start-time", type=float, default=0.0,
                        help="Start time in seconds. Default: 0.")
    parser.add_argument("-o", "--output", type=str, default=None,
                        help="Output file path.")
    parser.add_argument("--font-size", type=int, default=20,
                        help="Subtitle font size in pixels. Default: 20.")
    args = parser.parse_args()
    process_video_segment(
        video_path=Path(args.video_path),
        duration=args.duration,
        start_time=args.start_time,
        output_path=Path(args.output) if args.output else None,
        font_size=args.font_size,
    )


if __name__ == "__main__":
    main()
