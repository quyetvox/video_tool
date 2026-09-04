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


def hex_to_ass_color(hex_str, alpha=0.0):
    """
    Chuyển đổi màu HEX (#RRGGBB hoặc #RGB) sang định dạng ASS &HAABBGGRR.
    alpha: 0.0 = không trong suốt (00), 1.0 = trong suốt hoàn toàn (FF).
    """
    hex_clean = hex_str.strip().lstrip("#").replace("0x", "").replace("0X", "")
    if len(hex_clean) == 3:
        hex_clean = "".join([c * 2 for c in hex_clean])
    elif len(hex_clean) == 8: # AARRGGBB or RRGGBBAA -> lấy RRGGBB
        hex_clean = hex_clean[2:8] if hex_clean.startswith("ff") or hex_clean.startswith("FF") else hex_clean[0:6]
    
    if len(hex_clean) != 6:
        hex_clean = "FFFFFF"
    
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


def generate_ass_file(subtitles, sub_style, output_path, video_w=1920, video_h=1080):
    """Sinh file phụ đề ASS với style và vị trí khớp 100% Canvas Preview."""
    font_family = sub_style.get("fontFamily") or sub_style.get("fontName", "Be Vietnam Pro")
    base_font_size = int(sub_style.get("fontSize", 20))
    
    # Scale font size theo chiều cao video (Canvas Preview chuẩn cao ~450px)
    scale_factor = video_h / 450.0
    main_font_size = max(18, int(base_font_size * scale_factor))
    sub_font_size = max(14, int((base_font_size - 4) * scale_factor))
    
    main_color_hex = sub_style.get("fontColor") or sub_style.get("primaryColor", "#facc15")
    orig_color_hex = sub_style.get("origColor", "#ffffff")
    
    ass_main_color = hex_to_ass_color(main_color_hex, alpha=0.0)
    ass_sub_color = hex_to_ass_color(orig_color_hex, alpha=0.0)
    
    is_bold = -1 if sub_style.get("isBold", True) else 0
    is_italic = -1 if sub_style.get("isItalic", False) else 0
    show_box = sub_style.get("showSubBox", True)
    has_shadow = sub_style.get("hasDropShadow", True)
    show_main = sub_style.get("showMainSub", True)
    show_sub = sub_style.get("showSubSub", True)
    
    # Tọa độ % trên Canvas
    pos_x_pct = float(sub_style.get("posX", 50.0))
    pos_y_pct = float(sub_style.get("posY", 85.0))
    
    center_x = int(video_w * (pos_x_pct / 100.0))
    top_y = int(video_h * (pos_y_pct / 100.0))
    
    # Outline & Shadow (scale theo video)
    border_style = 3 if show_box else 1 # 3 = Opaque Box, 1 = Outline+Shadow
    outline_val = max(2.0, 4.0 * (video_h / 1080.0)) if show_box else 2.0
    shadow_val = max(1.0, 2.0 * (video_h / 1080.0)) if has_shadow else 0.0
    back_color = "&H99000000" if show_box else "&H80000000"

    ass_content = f"""[Script Info]
Title: Sub-Video Studio Subtitles
ScriptType: v4.00+
PlayResX: {video_w}
PlayResY: {video_h}
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,{font_family},{main_font_size},{ass_main_color},&H000000FF,&H00000000,{back_color},{is_bold},{is_italic},0,0,100,100,0,0,{border_style},{outline_val},{shadow_val},8,20,20,20,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

    for sub in subtitles:
        start_t = format_ass_time(sub.get("start", 0.0))
        end_t = format_ass_time(sub.get("end", 0.0))
        text_trans = sub.get("textTrans", "").strip()
        text_orig = sub.get("textOrig", "").strip()

        line_parts = []
        if show_main and text_trans:
            # Câu dịch chính: Màu fontColor (ví dụ vàng #facc15)
            line_parts.append(f"{{\\c{ass_main_color}\\b1\\fs{main_font_size}}}{text_trans}")
        if show_sub and text_orig:
            # Câu gốc: Màu origColor (ví dụ trắng #ffffff)
            line_parts.append(f"{{\\c{ass_sub_color}\\b0\\fs{sub_font_size}}}{text_orig}")

        if line_parts:
            # Ghép nhiều dòng có kèm tọa độ căn chỉnh vị trí \an8\pos(x, y)
            text_body = "\\N".join(line_parts)
            dialogue_line = f"{{\\an8\\pos({center_x},{top_y})}}{text_body}"
            ass_content += f"Dialogue: 0,{start_t},{end_t},Default,,0,0,0,,{dialogue_line}\n"

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

    # 1. Lấy thông tin video nguồn qua ffprobe
    probe_cmd = [
        ffmpeg_bin.replace("ffmpeg", "ffprobe"),
        "-v", "error",
        "-select_streams", "v:0",
        "-show_entries", "stream=width,height,r_frame_rate,duration",
        "-of", "json",
        video_path,
    ]
    video_w, video_h = 1920, 1080
    try:
        probe_res = subprocess.run(probe_cmd, capture_output=True, text=True, check=True)
        probe_data = json.loads(probe_res.stdout)
        stream_info = probe_data.get("streams", [{}])[0]
        video_w = int(stream_info.get("width", 1920))
        video_h = int(stream_info.get("height", 1080))
    except Exception as e:
        print(f"⚠️ Warning probe: {e}", file=sys.stderr)

    temp_dir = tempfile.mkdtemp(prefix="subvideo_composite_")
    try:
        input_args = ["-i", video_path]
        filter_complex_parts = []
        current_v_stream = "0:v"
        input_idx = 1

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
        if subtitles:
            ass_path = os.path.join(temp_dir, "subtitles.ass")
            generate_ass_file(subtitles, sub_style, ass_path, video_w, video_h)
            next_v_stream = "v_sub"
            escaped_ass = ass_path.replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
            filter_complex_parts.append(f"[{current_v_stream}]subtitles='{escaped_ass}'[{next_v_stream}]")
            current_v_stream = next_v_stream

        # 4. Xử lý Audio Mixing (Gốc + Nhạc nền + SFX)
        mix_state = config.get("mixState", {})
        orig_muted = mix_state.get("origMuted", False)
        orig_vol = 0.0 if orig_muted else (mix_state.get("origVolume", 100) / 100.0)

        music_muted = mix_state.get("musicMuted", False)
        music_master_vol = 0.0 if music_muted else (mix_state.get("musicVolume", 80) / 100.0)

        sfx_muted = mix_state.get("sfxMuted", False)
        sfx_master_vol = 0.0 if sfx_muted else (mix_state.get("sfxVolume", 60) / 100.0)

        audio_clips = config.get("audioClips", [])
        audio_streams_to_mix = []

        # Audio gốc
        filter_complex_parts.append(f"[0:a]volume={orig_vol:.2f}[a_orig]")
        audio_streams_to_mix.append("[a_orig]")

        for clip in audio_clips:
            aud_path = clip.get("fullPath", "")
            if not aud_path or not os.path.exists(aud_path):
                print(f"⚠️ Không tìm thấy file âm thanh: {aud_path}", file=sys.stderr)
                continue

            input_args.extend(["-i", aud_path])
            aud_in = f"{input_idx}:a"
            input_idx += 1

            start_ms = int(float(clip.get("start", 0.0)) * 1000)
            clip_vol = float(clip.get("volume", 80)) / 100.0
            track_type = clip.get("trackId", "music")
            is_clip_muted = clip.get("muted", False)

            if is_clip_muted:
                final_vol = 0.0
            else:
                master_factor = sfx_master_vol if track_type == "sfx" else music_master_vol
                final_vol = clip_vol * master_factor

            delayed_aud = f"a_del_{input_idx}"
            filter_complex_parts.append(
                f"[{aud_in}]volume={final_vol:.2f},adelay={start_ms}|{start_ms}[{delayed_aud}]"
            )
            audio_streams_to_mix.append(f"[{delayed_aud}]")

        # Trộn tất cả audio streams
        final_a_stream = "a_final"
        if len(audio_streams_to_mix) == 1:
            final_a_stream = "a_orig"
        else:
            inputs_str = "".join(audio_streams_to_mix)
            filter_complex_parts.append(
                f"{inputs_str}amix=inputs={len(audio_streams_to_mix)}:duration=first:dropout_transition=2[{final_a_stream}]"
            )

        filter_complex_str = ";".join(filter_complex_parts)

        # 5. Lắp ráp lệnh FFmpeg hoàn chỉnh
        ffmpeg_cmd = [
            ffmpeg_bin,
            "-y",
            *input_args,
            "-filter_complex", filter_complex_str,
            "-map", f"[{current_v_stream}]",
            "-map", f"[{final_a_stream}]",
            "-c:v", "h264_videotoolbox",
            "-b:v", "4M",
            "-c:a", "aac",
            "-b:a", "192k",
            "-pix_fmt", "yuv420p",
            output_path,
        ]

        print(f"🚀 Bắt đầu render bản phối đa lớp: {output_path}")
        process = subprocess.Popen(
            ffmpeg_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            universal_newlines=True,
        )

        for line in process.stdout:
            print(f"[FFmpeg] {line.strip()}", flush=True)

        process.wait()

        # Nếu videotoolbox lỗi, fallback sang libx264
        if process.returncode != 0:
            print("⚠️ VideoToolbox không khả dụng, chuyển sang libx264...", file=sys.stderr)
            fallback_cmd = [
                ffmpeg_bin,
                "-y",
                *input_args,
                "-filter_complex", filter_complex_str,
                "-map", f"[{current_v_stream}]",
                "-map", f"[{final_a_stream}]",
                "-c:v", "libx264",
                "-preset", "fast",
                "-crf", "20",
                "-c:a", "aac",
                "-b:a", "192k",
                "-pix_fmt", "yuv420p",
                output_path,
            ]
            fallback_res = subprocess.run(fallback_cmd, capture_output=True, text=True)
            if fallback_res.returncode != 0:
                print(f"❌ Fallback thất bại: {fallback_res.stderr}", file=sys.stderr)
                sys.exit(fallback_res.returncode)

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
