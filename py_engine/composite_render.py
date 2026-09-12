#!/usr/bin/env python3
"""
🎬 Sub-Video Composite Renderer — Xuất bản phối video đa lớp chuẩn 1:1 với Preview.
Hỗ trợ:
- Lớp phủ hình ảnh / Logo / Watermark (Tọa độ X/Y%, Kích thước W/H%, Độ mờ Opacity%, Thời gian [Start, End])
- Trộn âm thanh đa luồng (Video gốc Mute/Volume, Nhạc nền/SFX từng clip theo mốc Start và Volume riêng)
- Sinh & Ghép phụ đề ASS chuẩn từng pixel (FontFamily, FontSize, FontColor #facc15, OrigColor #ffffff, PosX/PosY %, Box)
- Tăng tốc Encode VideoToolbox H.264 / libx264 + AAC Audio.

100% Zero-External-Dependency (chỉ dùng standard library os, sys, json, subprocess + ffmpeg).
"""

import os
import sys
import json
import shutil
import tempfile
import threading
import subprocess
from pathlib import Path


def resolve_ffmpeg():
    """Tìm binary ffmpeg trên hệ thống."""
    for bin_path in [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg",
        shutil.which("ffmpeg"),
    ]:
        if bin_path and os.path.exists(bin_path):
            return bin_path
    return "ffmpeg"


def resolve_ffprobe(ffmpeg_path):
    """Tìm binary ffprobe tương ứng trên hệ thống (hỗ trợ cả Windows và macOS)."""
    ffprobe_name = "ffprobe.exe" if sys.platform == "win32" else "ffprobe"
    if ffmpeg_path and os.path.isabs(ffmpeg_path):
        probe_dir = os.path.dirname(ffmpeg_path)
        candidate = os.path.join(probe_dir, ffprobe_name)
        if os.path.exists(candidate):
            return candidate
    which_probe = shutil.which("ffprobe")
    return which_probe if which_probe else ("ffprobe.exe" if sys.platform == "win32" else "ffprobe")


def hex_to_ass_color(hex_str, alpha=0.0):
    """
    Chuyển đổi màu HEX (#RRGGBB hoặc #RGB) hoặc RGBA sang định dạng ASS &HAABBGGRR.
    alpha: 0.0 = không trong suốt (00), 1.0 = trong suốt hoàn toàn (FF).
    """
    if not hex_str:
        a_val = int(max(0.0, min(1.0, alpha)) * 255)
        return f"&H{a_val:02X}FFFFFF"

    s = str(hex_str).strip().lower()
    if s.startswith("rgba(") or s.startswith("rgb("):
        try:
            parts = s.split("(", 1)[1].split(")", 1)[0].split(",")
            r_val = int(float(parts[0].strip()))
            g_val = int(float(parts[1].strip()))
            b_val = int(float(parts[2].strip()))
            a_val = int(max(0.0, min(1.0, alpha)) * 255)
            return f"&H{a_val:02X}{b_val:02X}{g_val:02X}{r_val:02X}".upper()
        except Exception:
            pass

    hex_clean = s.lstrip("#").replace("0x", "")
    if len(hex_clean) == 3:
        hex_clean = "".join([c * 2 for c in hex_clean])
    elif len(hex_clean) == 8: # AARRGGBB or RRGGBBAA -> lấy RRGGBB
        hex_clean = hex_clean[2:8] if hex_clean.startswith("ff") else hex_clean[0:6]
    
    if len(hex_clean) != 6:
        hex_clean = "000000" if ("black" in s or "000" in s) else "FFFFFF"
    
    r = hex_clean[0:2].upper()
    g = hex_clean[2:4].upper()
    b = hex_clean[4:6].upper()
    
    a_val = int(max(0.0, min(1.0, alpha)) * 255)
    a_hex = f"{a_val:02X}"
    return f"&H{a_hex}{b}{g}{r}"


def format_ass_time(seconds):
    """Định dạng giây sang timestamp ASS: H:MM:SS.CC"""
    total_cs = int(round(seconds * 100))
    cs = total_cs % 100
    total_s = total_cs // 100
    s = total_s % 60
    total_m = total_s // 60
    m = total_m % 60
    h = total_m // 60
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def resolve_fonts_dir():
    """Tìm thư mục fonts trong resources/fonts để libass nạp trực tiếp không phụ thuộc hệ điều hành."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    candidate1 = os.path.abspath(os.path.join(script_dir, "..", "resources", "fonts"))
    if os.path.exists(candidate1):
        return candidate1
    candidate2 = os.path.abspath(os.path.join(os.getcwd(), "resources", "fonts"))
    if os.path.exists(candidate2):
        return candidate2
    return None


def make_box_path(w: int, h: int, radius: int) -> str:
    """Tạo lệnh vẽ vector ASS cho hình chữ nhật bo góc (SubBox)."""
    r = max(0, min(int(radius), h // 2, w // 2))
    if r <= 0:
        return f"m 0 0 l {w} 0 l {w} {h} l 0 {h}"
    return f"m {r} 0 l {w-r} 0 b {w} 0 {w} 0 {w} {r} l {w} {h-r} b {w} {h} {w} {h} {w-r} {h} l {r} {h} b 0 {h} 0 {h} 0 {h-r} l 0 {r} b 0 0 0 0 {r} 0"


def wrap_text_to_lines(text: str, max_chars: int) -> list:
    """Tự động ngắt dòng thông minh theo số ký tự tối đa của hộp chứa."""
    if not text:
        return []
    raw_lines = text.replace(r"\N", "\n").split("\n")
    out_lines = []
    for raw in raw_lines:
        raw = raw.strip()
        if not raw:
            continue
        if len(raw) <= max_chars:
            out_lines.append(raw)
            continue
        words = raw.split()
        cur = ""
        for w in words:
            if not cur:
                cur = w
            elif len(cur) + 1 + len(w) <= max_chars:
                cur += " " + w
            else:
                out_lines.append(cur)
                cur = w
        if cur:
            out_lines.append(cur)
    return out_lines or [text]


def generate_ass_file(subtitles, sub_style, output_path, video_w=1920, video_h=1080, canvas_w=640.0, canvas_h=360.0):
    """Sinh file phụ đề ASS với SubBox vector, đệm padding và vị trí khớp 100% Canvas Preview."""
    canvas_w = max(100.0, float(canvas_w or 640.0))
    canvas_h = max(100.0, float(canvas_h or 360.0))
    scale_x = video_w / canvas_w
    scale_y = video_h / canvas_h

    font_family = sub_style.get("fontFamily") or sub_style.get("fontName", "Be Vietnam Pro")
    base_font_size = float(sub_style.get("fontSize", 22))
    base_sec_font_size = float(sub_style.get("secondaryFontSize") or max(10.0, base_font_size - 4.0))

    # Scale font size theo tỷ lệ hiển thị Canvas Preview
    main_font_size = max(14, int(round((base_font_size / canvas_h) * video_h)))
    sub_font_size = max(12, int(round((base_sec_font_size / canvas_h) * video_h)))

    main_color_hex = sub_style.get("fontColor") or sub_style.get("primaryColor", "#facc15")
    orig_color_hex = sub_style.get("origColor", "#ffffff")
    ass_main_color = hex_to_ass_color(main_color_hex, alpha=0.0)
    ass_sub_color = hex_to_ass_color(orig_color_hex, alpha=0.0)

    # Box styles & dimensions
    show_box = sub_style.get("showSubBox", True)
    box_split = sub_style.get("boxSplit", False)
    separate_sec_pos = sub_style.get("separateSecPos", False)
    show_main = sub_style.get("showMainSub", True)
    show_sub = sub_style.get("showSubSub", True)
    has_shadow = sub_style.get("hasDropShadow", True)
    is_bold = -1 if sub_style.get("isBold", True) else 0
    is_italic = -1 if sub_style.get("isItalic", False) else 0

    # Padding, Radius, Gap scaled to video resolution
    v_pad_x = max(0, int(round(float(sub_style.get("boxPaddingX", 10.0)) * scale_x)))
    v_pad_y = max(0, int(round(float(sub_style.get("boxPaddingY", 6.0)) * scale_y)))
    v_radius = max(0, int(round(float(sub_style.get("boxBorderRadius", 6.0)) * scale_y)))
    v_gap = max(0, int(round(float(sub_style.get("boxGap", 8.0)) * scale_y)))
    v_border_width = max(0, int(round(float(sub_style.get("boxBorderWidth", 0.0)) * scale_y)))

    # Box colors
    box_opacity = float(sub_style.get("boxOpacity", 0.75))
    box_bg_color_hex = sub_style.get("boxBgColor", "#000000")
    ass_box_bg = hex_to_ass_color(box_bg_color_hex, alpha=1.0 - box_opacity)
    box_border_color_hex = sub_style.get("boxBorderColor", "#40ffffff")
    ass_box_border = hex_to_ass_color(box_border_color_hex, alpha=0.0)

    # Line heights (matching Flutter 1.25x line height)
    line_h_main = int(round(main_font_size * 1.25))
    line_h_sub = int(round(sub_font_size * 1.25))

    # Primary Box Geometry
    pos_x_pct = float(sub_style.get("posX", 50.0))
    pos_y_pct = float(sub_style.get("posY", 85.0))
    box_width_pct = float(sub_style.get("boxWidthPct", 90.0))

    v_box_w = max(40, int(round((box_width_pct / 100.0) * video_w)))
    center_x = int(round((pos_x_pct / 100.0) * video_w))
    top_y = int(round((pos_y_pct / 100.0) * video_h))
    left_x = center_x - (v_box_w // 2)

    inner_w_main = max(20, v_box_w - (2 * v_pad_x))
    max_chars_main = max(8, int(inner_w_main / (main_font_size * 0.52)))
    max_chars_sub = max(8, int(inner_w_main / (sub_font_size * 0.52)))

    # Secondary Box Geometry (if separateSecPos is True)
    sec_pos_x_pct = float(sub_style.get("secPosX", 50.0))
    sec_pos_y_pct = float(sub_style.get("secPosY", 15.0))
    sec_box_width_pct = float(sub_style.get("secBoxWidthPct", 90.0))

    v_sec_box_w = max(40, int(round((sec_box_width_pct / 100.0) * video_w)))
    sec_center_x = int(round((sec_pos_x_pct / 100.0) * video_w))
    sec_top_y = int(round((sec_pos_y_pct / 100.0) * video_h))
    sec_left_x = sec_center_x - (v_sec_box_w // 2)

    sec_inner_w = max(20, v_sec_box_w - (2 * v_pad_x))
    sec_max_chars = max(8, int(sec_inner_w / (sub_font_size * 0.52)))

    # Text drop shadow and outline
    text_outline_val = 1 if (has_shadow or not show_box) else 0
    text_shadow_val = 1 if (has_shadow or not show_box) else 0
    text_outline_color = "&H90000000" if (has_shadow or not show_box) else "&H00000000"
    text_shadow_color = "&H80000000" if (has_shadow or not show_box) else "&H00000000"

    ass_content = f"""[Script Info]
Title: Sub-Video Studio Subtitles
ScriptType: v4.00+
PlayResX: {video_w}
PlayResY: {video_h}
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: SubBox,Arial,20,&H00000000,&H000000FF,&H40FFFFFF,&H00000000,0,0,0,0,100,100,0,0,1,0,0,7,0,0,0,1
Style: SubTextMain,{font_family},{main_font_size},{ass_main_color},&H000000FF,{text_outline_color},{text_shadow_color},{is_bold},{is_italic},0,0,100,100,0,0,1,{text_outline_val},{text_shadow_val},8,0,0,0,1
Style: SubTextSec,{font_family},{sub_font_size},{ass_sub_color},&H000000FF,{text_outline_color},{text_shadow_color},0,0,0,0,100,100,0,0,1,{text_outline_val},{text_shadow_val},8,0,0,0,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

    for sub in subtitles:
        start_t = format_ass_time(sub.get("start", 0.0))
        end_t = format_ass_time(sub.get("end", 0.0))
        text_trans = (sub.get("text_vi") or sub.get("textTrans") or "").strip()
        text_orig = (sub.get("text") or sub.get("textSecondary") or sub.get("textOrig") or "").strip()

        has_p = show_main and bool(text_trans)
        has_s = show_sub and bool(text_orig)

        if not has_p and not has_s:
            continue

        if separate_sec_pos:
            # ── Scenario 1: Separate Secondary Subtitle Position ──
            if has_p:
                lines_p = wrap_text_to_lines(text_trans, max_chars_main)
                h_p = len(lines_p) * line_h_main
                h_box_p = h_p + (2 * v_pad_y)
                if show_box:
                    path_p = make_box_path(v_box_w, h_box_p, v_radius)
                    ass_content += f"Dialogue: 0,{start_t},{end_t},SubBox,,0,0,0,,{{\\an7\\pos({left_x},{top_y})\\p1\\bord{v_border_width}\\3c{ass_box_border}\\1c{ass_box_bg}}}{path_p}{{\\p0}}\n"
                p_body = "\\N".join(lines_p)
                p_text_y = top_y + v_pad_y
                ass_content += f"Dialogue: 1,{start_t},{end_t},SubTextMain,,0,0,0,,{{\\an8\\pos({center_x},{p_text_y})\\c{ass_main_color}\\fs{main_font_size}\\b{is_bold}}}{p_body}\n"

            if has_s:
                lines_s = wrap_text_to_lines(text_orig, sec_max_chars)
                h_s = len(lines_s) * line_h_sub
                h_box_s = h_s + (2 * v_pad_y)
                if show_box:
                    path_s = make_box_path(v_sec_box_w, h_box_s, v_radius)
                    ass_content += f"Dialogue: 0,{start_t},{end_t},SubBox,,0,0,0,,{{\\an7\\pos({sec_left_x},{sec_top_y})\\p1\\bord{v_border_width}\\3c{ass_box_border}\\1c{ass_box_bg}}}{path_s}{{\\p0}}\n"
                s_body = "\\N".join(lines_s)
                s_text_y = sec_top_y + v_pad_y
                ass_content += f"Dialogue: 1,{start_t},{end_t},SubTextSec,,0,0,0,,{{\\an8\\pos({sec_center_x},{s_text_y})\\c{ass_sub_color}\\fs{sub_font_size}\\b0}}{s_body}\n"

        elif box_split and has_p and has_s:
            # ── Scenario 2: Split Boxes (2 separate stacked boxes with v_gap) ──
            lines_p = wrap_text_to_lines(text_trans, max_chars_main)
            lines_s = wrap_text_to_lines(text_orig, max_chars_sub)

            h_p = len(lines_p) * line_h_main
            h_box_p = h_p + (2 * v_pad_y)

            h_s = len(lines_s) * line_h_sub
            h_box_s = h_s + (2 * v_pad_y)

            top_box_s = top_y + h_box_p + v_gap

            if show_box:
                path_p = make_box_path(v_box_w, h_box_p, v_radius)
                path_s = make_box_path(v_box_w, h_box_s, v_radius)
                ass_content += f"Dialogue: 0,{start_t},{end_t},SubBox,,0,0,0,,{{\\an7\\pos({left_x},{top_y})\\p1\\bord{v_border_width}\\3c{ass_box_border}\\1c{ass_box_bg}}}{path_p}{{\\p0}}\n"
                ass_content += f"Dialogue: 0,{start_t},{end_t},SubBox,,0,0,0,,{{\\an7\\pos({left_x},{top_box_s})\\p1\\bord{v_border_width}\\3c{ass_box_border}\\1c{ass_box_bg}}}{path_s}{{\\p0}}\n"

            p_body = "\\N".join(lines_p)
            p_text_y = top_y + v_pad_y
            ass_content += f"Dialogue: 1,{start_t},{end_t},SubTextMain,,0,0,0,,{{\\an8\\pos({center_x},{p_text_y})\\c{ass_main_color}\\fs{main_font_size}\\b{is_bold}}}{p_body}\n"

            s_body = "\\N".join(lines_s)
            s_text_y = top_box_s + v_pad_y
            ass_content += f"Dialogue: 1,{start_t},{end_t},SubTextSec,,0,0,0,,{{\\an8\\pos({center_x},{s_text_y})\\c{ass_sub_color}\\fs{sub_font_size}\\b0}}{s_body}\n"

        else:
            # ── Scenario 3: Single combined box (or single active subtitle) ──
            lines_p = wrap_text_to_lines(text_trans, max_chars_main) if has_p else []
            lines_s = wrap_text_to_lines(text_orig, max_chars_sub) if has_s else []

            h_p = len(lines_p) * line_h_main if has_p else 0
            h_s = len(lines_s) * line_h_sub if has_s else 0

            gap_val = v_gap if (has_p and has_s) else 0
            h_box = h_p + gap_val + h_s + (2 * v_pad_y)

            if show_box:
                path = make_box_path(v_box_w, h_box, v_radius)
                ass_content += f"Dialogue: 0,{start_t},{end_t},SubBox,,0,0,0,,{{\\an7\\pos({left_x},{top_y})\\p1\\bord{v_border_width}\\3c{ass_box_border}\\1c{ass_box_bg}}}{path}{{\\p0}}\n"

            if has_p:
                p_body = "\\N".join(lines_p)
                p_text_y = top_y + v_pad_y
                ass_content += f"Dialogue: 1,{start_t},{end_t},SubTextMain,,0,0,0,,{{\\an8\\pos({center_x},{p_text_y})\\c{ass_main_color}\\fs{main_font_size}\\b{is_bold}}}{p_body}\n"

            if has_s:
                s_body = "\\N".join(lines_s)
                s_text_y = (top_y + v_pad_y + h_p + gap_val) if has_p else (top_y + v_pad_y)
                ass_content += f"Dialogue: 1,{start_t},{end_t},SubTextSec,,0,0,0,,{{\\an8\\pos({center_x},{s_text_y})\\c{ass_sub_color}\\fs{sub_font_size}\\b0}}{s_body}\n"

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(ass_content)


def render_composite(config_json_path):
    """Thực thi render bản phối đa lớp từ file JSON cấu hình."""
    with open(config_json_path, "r", encoding="utf-8") as f:
        config = json.load(f)

    video_path = config.get("videoPath")
    output_path = config.get("outputPath")
    if not video_path or not os.path.exists(video_path):
        print(f"❌ Error: Video nguồn không tồn tại: {video_path}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    ffmpeg_bin = resolve_ffmpeg()
    ffprobe_bin = resolve_ffprobe(ffmpeg_bin)

    # 1. Lấy thông tin video nguồn qua ffprobe
    probe_cmd = [
        ffprobe_bin,
        "-v", "error",
        "-show_entries", "stream=width,height,r_frame_rate,duration,codec_type,codec_name:format=duration",
        "-of", "json",
        video_path,
    ]
    video_w, video_h = 1920, 1080
    video_duration_sec = 0.0
    has_audio = False
    try:
        probe_res = subprocess.run(probe_cmd, capture_output=True, text=True, check=True)
        probe_data = json.loads(probe_res.stdout)
        streams = probe_data.get("streams", [])
        video_stream = next((s for s in streams if s.get("codec_type") == "video"), {})
        video_w = int(video_stream.get("width", 1920))
        video_h = int(video_stream.get("height", 1080))
        has_audio = any(s.get("codec_type") == "audio" for s in streams)
        
        # Lấy thời lượng chuẩn từ video stream hoặc format
        stream_dur = float(video_stream.get("duration", "0") or "0")
        fmt_dur = float(probe_data.get("format", {}).get("duration", "0") or "0")
        video_duration_sec = stream_dur if stream_dur > 0 else fmt_dur
    except Exception as e:
        print(f"⚠️ Warning probe: {e}", file=sys.stderr)

    if video_duration_sec <= 0:
        video_duration_sec = 1.0
    total_duration_us = max(1, int(video_duration_sec * 1_000_000))

    temp_dir = tempfile.mkdtemp(prefix="subvideo_composite_")
    try:
        input_args = ["-i", video_path]
        filter_complex_parts = []
        current_v_stream = "0:v"
        input_idx = 1

        # 1.5. Xử lý Tốc độ Video gốc (Speed Scaling)
        video_speed = float(config.get("videoSpeed", 1.0) or 1.0)
        video_speed = max(0.25, min(4.0, video_speed))
        if abs(video_speed - 1.0) > 0.01:
            video_duration_sec = video_duration_sec / video_speed
            next_v_stream = "v_speed"
            filter_complex_parts.append(f"[{current_v_stream}]setpts={1.0/video_speed:.4f}*PTS[{next_v_stream}]")
            current_v_stream = next_v_stream
        total_duration_us = max(1, int(video_duration_sec * 1_000_000))

        # 1.8. Xử lý Vùng xóa / che phụ đề cũ (Inpaint Box / Blur)
        inpaint_cfg = config.get("inpaint", {})
        if inpaint_cfg.get("enabled", False):
            region = inpaint_cfg.get("region", [0.82, 0.05, 0.95, 0.95])
            if len(region) == 4:
                ymin, xmin, ymax, xmax = [float(v) for v in region]
                box_x = max(0, int(round(xmin * video_w)))
                box_y = max(0, int(round(ymin * video_h)))
                box_w = max(16, int(round((xmax - xmin) * video_w)))
                box_h = max(16, int(round((ymax - ymin) * video_h)))
                box_w = min(box_w, video_w - box_x)
                box_h = min(box_h, video_h - box_y)

                mode = inpaint_cfg.get("mode", "box_color")
                opacity = float(inpaint_cfg.get("opacity", 0.75))
                opacity = max(0.0, min(1.0, opacity))

                if mode == "blur":
                    next_v_stream = f"v_inp_{input_idx}"
                    filter_complex_parts.append(
                        f"[{current_v_stream}]split[v_inpb_{input_idx}][v_inpc_{input_idx}];"
                        f"[v_inpc_{input_idx}]crop={box_w}:{box_h}:{box_x}:{box_y},boxblur=luma_radius=15:luma_power=3[v_inpr_{input_idx}];"
                        f"[v_inpb_{input_idx}][v_inpr_{input_idx}]overlay={box_x}:{box_y}[{next_v_stream}]"
                    )
                    input_idx += 1
                    current_v_stream = next_v_stream
                else:
                    color_hex = inpaint_cfg.get("color", "#000000").lstrip("#").upper()
                    if len(color_hex) != 6:
                        color_hex = "000000"
                    next_v_stream = f"v_inp_{input_idx}"
                    input_idx += 1
                    filter_complex_parts.append(
                        f"[{current_v_stream}]drawbox=x={box_x}:y={box_y}:w={box_w}:h={box_h}:"
                        f"color=0x{color_hex}@{opacity:.2f}:t=fill[{next_v_stream}]"
                    )
                    current_v_stream = next_v_stream

        # 2. Xử lý Overlay Clips (Logo / Watermark Images)
        overlay_clips = config.get("overlayClips", [])
        for clip in overlay_clips:
            img_path = clip.get("imagePath", "")
            if not img_path or not os.path.exists(img_path):
                print(f"⚠️ Không tìm thấy ảnh overlay: {img_path}", file=sys.stderr)
                continue

            input_args.extend(["-i", img_path])
            img_in = f"{input_idx}:v"
            input_idx += 1

            start_t = float(clip.get("start", 0.0))
            end_t = float(clip.get("end", 9999.0))
            x_pct = float(clip.get("x", 5.0)) / 100.0
            y_pct = float(clip.get("y", 5.0)) / 100.0
            w_pct = float(clip.get("width", 20.0)) / 100.0
            h_pct = float(clip.get("height", 20.0)) / 100.0
            
            # Chuẩn hoá opacity: Hỗ trợ cả 0.0..1.0 và 0..100
            raw_opacity = float(clip.get("opacity", 1.0))
            opacity = raw_opacity / 100.0 if raw_opacity > 1.0 else max(0.0, min(1.0, raw_opacity))

            target_w = max(16, int(video_w * w_pct))
            target_h = max(16, int(video_h * h_pct))
            x_pos = int(video_w * x_pct)
            y_pos = int(video_h * y_pct)

            scaled_img = f"ov_scaled_{input_idx}"
            # Scale ảnh giữ nguyên Aspect Ratio gốc và áp dụng opacity
            filter_complex_parts.append(
                f"[{img_in}]scale={target_w}:{target_h}:force_original_aspect_ratio=decrease,"
                f"format=rgba,colorchannelmixer=aa={opacity:.2f}[{scaled_img}]"
            )

            next_v_stream = f"v_ov_{input_idx}"
            filter_complex_parts.append(
                f"[{current_v_stream}][{scaled_img}]overlay={x_pos}:{y_pos}:"
                f"enable='between(t,{start_t:.3f},{end_t:.3f})'[{next_v_stream}]"
            )
            current_v_stream = next_v_stream

        # 3. Xử lý Subtitles (Burn-in ASS)
        subtitles = config.get("subtitles", [])
        sub_style = config.get("subStyle", {})
        canvas_info = config.get("canvas", {})
        canvas_w = float(canvas_info.get("width", 640.0) or 640.0)
        canvas_h = float(canvas_info.get("height", 360.0) or 360.0)
        if subtitles:
            ass_path = os.path.join(temp_dir, "subtitles.ass")
            generate_ass_file(subtitles, sub_style, ass_path, video_w, video_h, canvas_w=canvas_w, canvas_h=canvas_h)
            next_v_stream = "v_sub"
            escaped_ass = ass_path.replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
            fonts_dir = resolve_fonts_dir()
            fontsdir_clause = ""
            if fonts_dir and os.path.exists(fonts_dir):
                escaped_fontsdir = fonts_dir.replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
                fontsdir_clause = f":fontsdir='{escaped_fontsdir}'"
            filter_complex_parts.append(f"[{current_v_stream}]subtitles='{escaped_ass}'{fontsdir_clause}[{next_v_stream}]")
            current_v_stream = next_v_stream

        # 4. Xử lý Audio Mixing (Gốc + Nhạc nền + SFX)
        mix_state = config.get("mixState", {})
        orig_muted = mix_state.get("origMuted", False)
        orig_vol = 0.0 if orig_muted else (mix_state.get("origVolume", 100) / 100.0)

        music_muted = mix_state.get("musicMuted", False)
        music_master_vol = 0.0 if music_muted else (mix_state.get("musicVolume", 80) / 100.0)

        sfx_muted = mix_state.get("sfxMuted", False)
        sfx_master_vol = 0.0 if sfx_muted else (mix_state.get("sfxVolume", 60) / 100.0)

        audio_tracks = {t.get("id"): t for t in config.get("audioTracks", [])}
        audio_clips = config.get("audioClips", [])
        audio_streams_to_mix = []

        # Audio gốc — chỉ đưa vào mix nếu video có audio stream thực tế và không bị mute / âm lượng > 0
        should_include_orig = has_audio and (not orig_muted) and (orig_vol > 0.0)
        if should_include_orig:
            if abs(video_speed - 1.0) > 0.01:
                tempo = max(0.5, min(2.0, video_speed))
                filter_complex_parts.append(f"[0:a]atempo={tempo:.4f},volume={orig_vol:.2f},atrim=0:{video_duration_sec:.3f}[a_orig]")
            else:
                filter_complex_parts.append(f"[0:a]volume={orig_vol:.2f},atrim=0:{video_duration_sec:.3f}[a_orig]")
            audio_streams_to_mix.append("[a_orig]")

        for clip in audio_clips:
            aud_path = clip.get("fullPath", "")
            if not aud_path or not os.path.exists(aud_path):
                print(f"⚠️ Không tìm thấy file âm thanh: {aud_path}", file=sys.stderr)
                continue

            clip_vol = float(clip.get("volume", 100)) / 100.0
            track_type = str(clip.get("trackId", "track-au-1"))
            track_info = audio_tracks.get(track_type)

            is_clip_muted = clip.get("muted", False)
            if track_info:
                is_track_muted = track_info.get("muted", False) or music_muted
                track_vol = float(track_info.get("volume", 100)) / 100.0
                master_vol = 0.0 if is_track_muted else (track_vol * music_master_vol)
            else:
                # Legacy fallback
                is_sfx_track = track_type.lower() in ["sfx", "voice", "voiceover", "effect"]
                is_track_muted = sfx_muted if is_sfx_track else music_muted
                master_vol = 0.0 if is_track_muted else (sfx_master_vol if is_sfx_track else music_master_vol)

            final_vol = 0.0 if (is_clip_muted or is_track_muted) else (clip_vol * master_vol)

            if final_vol <= 0.0:
                # Bỏ qua clip bị tắt tiếng hoặc âm lượng 0 để không pha tạp stream rỗng vào mix
                continue

            input_args.extend(["-i", aud_path])
            aud_in = f"{input_idx}:a"
            input_idx += 1

            start_sec = max(0.0, float(clip.get("start", 0.0)))
            start_ms = int(start_sec * 1000)
            end_sec = float(clip.get("end", video_duration_sec))
            clip_dur = max(0.05, end_sec - start_sec)

            delayed_aud = f"a_del_{input_idx}"
            filter_complex_parts.append(
                f"[{aud_in}]volume={final_vol:.2f},atrim=0:{clip_dur:.3f},adelay={start_ms}|{start_ms}[{delayed_aud}]"
            )
            audio_streams_to_mix.append(f"[{delayed_aud}]")

        # Trộn tất cả audio streams và đồng bộ chuẩn xác thời lượng video
        final_a_stream = "a_final"
        if len(audio_streams_to_mix) == 0:
            # Fallback nếu không có stream nào hoạt động: sinh kênh im lặng đúng chuẩn thời lượng
            filter_complex_parts.append(f"anullsrc=r=44100:cl=stereo:d={video_duration_sec:.3f}[{final_a_stream}]")
        elif len(audio_streams_to_mix) == 1:
            only_stream = audio_streams_to_mix[0]
            filter_complex_parts.append(f"{only_stream}alimiter=limit=0.98,apad,atrim=0:{video_duration_sec:.3f}[{final_a_stream}]")
        else:
            inputs_str = "".join(audio_streams_to_mix)
            filter_complex_parts.append(
                f"{inputs_str}amix=inputs={len(audio_streams_to_mix)}:duration=longest:dropout_transition=2:normalize=0,"
                f"alimiter=limit=0.98,apad,atrim=0:{video_duration_sec:.3f}[{final_a_stream}]"
            )

        filter_complex_str = ";".join(filter_complex_parts)

        # 5. Lắp ráp lệnh FFmpeg hoàn chỉnh
        # Smart Stream Copy: Nếu chỉ mix audio (không có layer ảnh phủ, không có phụ đề và không đổi tốc độ video)
        # và codec video tương thích MP4 container (h264, hevc, h265, mpeg4), dùng -c:v copy để render siêu tốc (1-2s).
        has_visual_layers = bool(overlay_clips or subtitles or inpaint_cfg.get("enabled", False) or abs(video_speed - 1.0) > 0.01)
        video_codec = video_stream.get("codec_name", "").lower()
        can_stream_copy = not has_visual_layers and (video_codec in ["h264", "hevc", "h265", "mpeg4"])

        video_bitrate = str(config.get("videoBitrate", "4M") or "4M").strip()
        if video_bitrate.replace(".", "").isdigit():
            video_bitrate = f"{video_bitrate}M"

        use_videotoolbox = sys.platform == "darwin"
        if can_stream_copy:
            v_codec_args = ["-c:v", "copy"]
            pix_fmt_args = []
            print(f"⚡ Kích hoạt Smart Stream Copy (-c:v copy, codec={video_codec}) do không có layer hình ảnh và giữ nguyên tốc độ...")
        elif use_videotoolbox:
            v_codec_args = ["-c:v", "h264_videotoolbox", "-b:v", video_bitrate]
            pix_fmt_args = ["-pix_fmt", "yuv420p"]
        else:
            v_codec_args = ["-c:v", "libx264", "-b:v", video_bitrate, "-preset", "fast"]
            pix_fmt_args = ["-pix_fmt", "yuv420p"]

        v_map_arg = f"[{current_v_stream}]" if current_v_stream != "0:v" else "0:v"

        ffmpeg_cmd = [
            ffmpeg_bin,
            "-y",
            *input_args,
            "-filter_complex", filter_complex_str,
            "-map", v_map_arg,
            "-map", f"[{final_a_stream}]",
            *v_codec_args,
            "-c:a", "aac",
            "-b:a", "192k",
            *pix_fmt_args,
            "-movflags", "+faststart",
            "-shortest",
            "-progress", "pipe:1",
            "-nostats",
            output_path,
        ]

        def _run_with_progress(cmd):
            """Chạy FFmpeg, stream PROGRESS:N ra stdout, log FFmpeg ra stderr."""
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
                universal_newlines=True,
            )

            def _relay_stderr():
                for ln in proc.stderr:
                    print(f"[FFmpeg] {ln.strip()}", flush=True)

            t = threading.Thread(target=_relay_stderr, daemon=True)
            t.start()

            last_pct = -1
            for ln in proc.stdout:
                ln = ln.strip()
                if ln.startswith("out_time_ms="):
                    try:
                        out_us = int(ln.split("=", 1)[1])
                        pct = min(99, int(out_us / total_duration_us * 100))
                        if pct != last_pct:
                            print(f"PROGRESS:{pct}", flush=True)
                            last_pct = pct
                    except (ValueError, ZeroDivisionError):
                        pass

            proc.wait()
            t.join(timeout=3)
            try:
                if proc.stdout:
                    proc.stdout.close()
                if proc.stderr:
                    proc.stderr.close()
            except Exception:
                pass
            return proc.returncode

        print(f"🚀 Bắt đầu render bản phối đa lớp: {output_path}")
        returncode = _run_with_progress(ffmpeg_cmd)

        # Nếu encoder chính lỗi (ví dụ videotoolbox), fallback sang libx264
        if returncode != 0:
            print("⚠️ Encoder chính không khả dụng, chuyển sang libx264...", file=sys.stderr)
            fallback_cmd = [
                ffmpeg_bin,
                "-y",
                *input_args,
                "-filter_complex", filter_complex_str,
                "-map", v_map_arg,
                "-map", f"[{final_a_stream}]",
                "-c:v", "libx264",
                "-preset", "fast",
                "-crf", "20",
                "-c:a", "aac",
                "-b:a", "192k",
                "-pix_fmt", "yuv420p",
                "-movflags", "+faststart",
                "-shortest",
                "-progress", "pipe:1",
                "-nostats",
                output_path,
            ]
            returncode = _run_with_progress(fallback_cmd)
            if returncode != 0:
                print(f"❌ Fallback thất bại", file=sys.stderr)
                sys.exit(returncode)

        print("PROGRESS:100", flush=True)
        print(f"✅ Render bản phối thành công: {output_path}")
        return True

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: composite_render.py <config.json>", file=sys.stderr)
        sys.exit(1)

    config_file = sys.argv[1]
    render_composite(config_file)
