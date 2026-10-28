"""
Subtitle generation utilities (.ass / .srt) for AI Lecture Illustrator.
- Single and Bilingual subtitle support
- High quality ASS styles matching Sub-Video standards (SubBox, Outline, Alignment)
"""

import platform
from pathlib import Path
from typing import Dict, List, Optional

from .models import LectureBatch, LectureProjectConfig


def has_cjk_characters(text: str) -> bool:
    """Kiểm tra chuỗi có chứa ký tự tiếng Trung, Nhật, Hàn (CJK) hay không."""
    for char in text:
        cp = ord(char)
        if (0x4E00 <= cp <= 0x9FFF) or (0x3400 <= cp <= 0x4DBF) or \
           (0x3040 <= cp <= 0x309F) or (0x30A0 <= cp <= 0x30FF) or \
           (0xAC00 <= cp <= 0xD7AF):
            return True
    return False


def get_default_cjk_font() -> str:
    """Trả về font CJK chuẩn mặc định theo hệ điều hành (macOS vs Windows)."""
    sys_name = platform.system()
    if sys_name == "Darwin":
        return "Arial Unicode MS"
    elif sys_name == "Windows":
        return "Microsoft YaHei"
    return "Arial Unicode MS"


def resolve_secondary_font_name(
    config: LectureProjectConfig,
    batches: List[LectureBatch]
) -> str:
    """
    Xác định font tối ưu cho phụ đề phụ (dòng tiếng gốc):
    - Nếu người dùng chỉ định rõ secondary_font_name -> dùng font đó.
    - Nếu nội dung gốc hoặc source_lang là CJK -> tự động dùng font CJK hệ điều hành để tránh libass loop fallback.
    - Ngược lại dùng font_name chính.
    """
    if getattr(config, "secondary_font_name", None):
        return config.secondary_font_name

    source_lang = (config.source_lang or "").lower()
    is_cjk_lang = source_lang in ("zh", "ja", "ko", "chinese", "japanese", "korean")
    if is_cjk_lang:
        return get_default_cjk_font()

    for b in batches:
        if b.transcript_original and has_cjk_characters(b.transcript_original):
            return get_default_cjk_font()

    return config.font_name or "Arial"


UNICODE_SUBSCRIPT_NORMALIZATION: Dict[str, str] = {
    # Latin subscript letters
    "ₐ": "a", "ₑ": "e", "ₕ": "h", "ᵢ": "i", "ⱼ": "j", "ₖ": "k",
    "ₗ": "l", "ₘ": "m", "ₙ": "n", "ₒ": "o", "ₚ": "p", "ᵣ": "r",
    "ₛ": "s", "ₜ": "t", "ᵤ": "u", "ᵥ": "v", "ₓ": "x",
    # Subscript numbers and symbols
    "₀": "0", "₁": "1", "₂": "2", "₃": "3", "₄": "4",
    "₅": "5", "₆": "6", "₇": "7", "₈": "8", "₉": "9",
    "₊": "+", "₋": "-", "₌": "=", "₍": "(", "₎": ")",
    # Superscript letters and numbers
    "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
    "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
    "⁺": "+", "⁻": "-", "⁼": "=", "⁽": "(", "⁾": ")",
    "ⁿ": "n", "ⁱ": "i",
}


def sanitize_ass_special_chars(text: str) -> str:
    """Chuẩn hóa các ký tự chỉ số dưới/trên Unicode để bảo vệ font ASS, ngăn CoreText macOS fallback về .SF NS."""
    if not text:
        return ""
    for sub_char, norm_char in UNICODE_SUBSCRIPT_NORMALIZATION.items():
        if sub_char in text:
            text = text.replace(sub_char, norm_char)
    return text


def format_ass_time(seconds: float) -> str:
    """Format seconds into ASS timestamp: H:MM:SS.cs"""
    seconds = max(0.0, seconds)
    hrs = int(seconds // 3600)
    mins = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    centis = int(round((seconds - int(seconds)) * 100))
    if centis >= 100:
        secs += 1
        centis -= 100
    return f"{hrs}:{mins:02d}:{secs:02d}.{centis:02d}"


def format_srt_time(seconds: float) -> str:
    """Format seconds into SRT timestamp: HH:MM:SS,mmm"""
    seconds = max(0.0, seconds)
    hrs = int(seconds // 3600)
    mins = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    millis = int(round((seconds - int(seconds)) * 1000))
    if millis >= 1000:
        secs += 1
        millis -= 1000
    return f"{hrs:02d}:{mins:02d}:{secs:02d},{millis:03d}"


def generate_lecture_srt(
    batches: List[LectureBatch],
    output_srt_path: Path,
    config: LectureProjectConfig,
) -> Path:
    """Tạo file phụ đề .srt đơn giản."""
    lines = []
    idx = 1
    show_pri = getattr(config, "subtitle_show_primary", True)
    show_sec = (config.subtitle_mode == "bilingual" or not show_pri) and getattr(config, "subtitle_secondary_show", True)
    for b in batches:
        start_str = format_srt_time(b.start_sec)
        end_str = format_srt_time(b.end_sec)
        
        # Lấy text phụ (ưu tiên text_secondary đã dịch)
        sec_text = ""
        if show_sec:
            if b.sentences and len(b.sentences) > 0:
                sec_text = " ".join(str(s.get("text_secondary") or s.get("text_orig") or "") for s in b.sentences).strip()
            else:
                sec_text = (b.transcript_original or "").strip()

        pri_text = (b.transcript_translated or b.transcript_original).strip() if show_pri else ""

        if pri_text and sec_text and pri_text != sec_text:
            if getattr(config, "subtitle_order", "primary_top") in ("secondary_top", "primary_bottom"):
                sub_text = f"{sec_text}\n{pri_text}"
            else:
                sub_text = f"{pri_text}\n{sec_text}"
        elif pri_text:
            sub_text = pri_text
        elif sec_text:
            sub_text = sec_text
        else:
            continue

        lines.append(f"{idx}\n{start_str} --> {end_str}\n{sub_text}\n")
        idx += 1

    output_srt_path.parent.mkdir(parents=True, exist_ok=True)
    output_srt_path.write_text("\n".join(lines), encoding="utf-8")
    return output_srt_path


def _color_to_ass(color_val: str, default: str = "&H00FFFFFF") -> str:
    if not color_val:
        return default
    val = color_val.strip()
    if val.startswith("&H") or val.startswith("&h"):
        return val.upper()
    if val.startswith("#"):
        hex_str = val[1:]
        if len(hex_str) == 6:
            r, g, b = hex_str[0:2], hex_str[2:4], hex_str[4:6]
            return f"&H00{b}{g}{r}".upper()
        elif len(hex_str) == 8:
            a, r, g, b = hex_str[0:2], hex_str[2:4], hex_str[4:6], hex_str[6:8]
            return f"&H{a}{b}{g}{r}".upper()
    named_colors = {
        "white": "&H00FFFFFF",
        "black": "&H00000000",
        "yellow": "&H0000FFFF",
        "red": "&H000000FF",
        "cyan": "&H00FFFF00",
        "blue": "&H00FF0000",
        "green": "&H00008000",
        "orange": "&H0000A5FF",
        "gray": "&H00808080",
        "grey": "&H00808080",
    }
    return named_colors.get(val.lower(), default)


def resolve_subtitle_placement(
    config: LectureProjectConfig,
    video_width: int = 1920,
    video_height: int = 1080,
) -> tuple[int, int, int, int]:
    """
    Xác định tọa độ tâm (center_x, center_y) và lề (margin_l, margin_r) cho phụ đề
    từ subtitle_region của config. Mặc định đặt tại vùng đáy [0.85, 0.04, 0.92, 0.94].
    """
    sub_reg = getattr(config, "subtitle_region", None)
    if not (isinstance(sub_reg, (list, tuple)) and len(sub_reg) == 4):
        sub_reg = [0.85, 0.04, 0.92, 0.94]
    try:
        top, left, bottom, right = [float(v) for v in sub_reg]
    except (ValueError, TypeError):
        top, left, bottom, right = 0.85, 0.04, 0.92, 0.94

    top = max(0.0, min(1.0, top))
    bottom = max(0.0, min(1.0, bottom))
    left = max(0.0, min(1.0, left))
    right = max(0.0, min(1.0, right))
    if bottom < top:
        top, bottom = bottom, top
    if right < left:
        left, right = right, left

    center_x = max(10, min(video_width - 10, int(round(video_width * (left + right) / 2.0))))
    center_y = max(10, min(video_height - 10, int(round(video_height * (top + bottom) / 2.0))))
    margin_l = max(10, int(round(video_width * left)))
    margin_r = max(10, int(round(video_width * (1.0 - right))))
    return center_x, center_y, margin_l, margin_r


def generate_lecture_ass(
    batches: List[LectureBatch],
    output_ass_path: Path,
    config: LectureProjectConfig,
    video_width: int = 1920,
    video_height: int = 1080,
) -> Path:
    """
    Tạo file phụ đề .ass chuyên nghiệp hỗ trợ font chữ tùy biến,
    viền chữ sắc nét, căn chỉnh tọa độ chính xác theo subtitle_region,
    và hiển thị song ngữ nếu bật.
    """
    font_name = config.font_name or "Arial"
    sec_font_name = resolve_secondary_font_name(config, batches)
    font_size = config.font_size or "26"
    sec_scale = float(getattr(config, "secondary_scale", 0.70) or 0.70)
    sec_font_size = max(12, int(round(float(font_size) * sec_scale)))
    font_color = _color_to_ass(config.font_color, "&H00FFFFFF")
    outline_color = _color_to_ass(config.outline_color, "&H00000000")
    sec_font_color = _color_to_ass(getattr(config, "secondary_font_color", "&H00E7E1DC"), "&H00E7E1DC")

    center_x, center_y, margin_l, margin_r = resolve_subtitle_placement(config, video_width, video_height)

    ass_header = f"""[Script Info]
Title: AI Lecture Illustrator Subtitles
ScriptType: v4.00+
WrapStyle: 0
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709
PlayResX: {video_width}
PlayResY: {video_height}

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Primary,{font_name},{font_size},{font_color},&H000000FF,{outline_color},&H80000000,-1,0,0,0,100,100,0,0,1,2.5,1,5,{margin_l},{margin_r},10,1
Style: Secondary,{sec_font_name},{sec_font_size},{sec_font_color},&H000000FF,{outline_color},&H80000000,0,0,0,0,100,100,0,0,1,2.0,1,5,{margin_l},{margin_r},10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

    dialogue_lines = []
    # Thu thập tất cả các item phụ đề (ưu tiên từng câu con trong batch để khớp giọng TTS)
    sub_items = []
    for b in batches:
        if getattr(b, "sentences", None) and len(b.sentences) > 0:
            for s in b.sentences:
                sub_items.append({
                    "start": float(s.get("start", b.start_sec)),
                    "end": float(s.get("end", b.end_sec)),
                    "pri_text": str(s.get("text", "")).strip(),
                    "sec_text": str(s.get("text_secondary") or s.get("text_orig") or "").strip(),
                })
        else:
            sub_items.append({
                "start": b.start_sec,
                "end": b.end_sec,
                "pri_text": (b.transcript_translated or b.transcript_original).strip(),
                "sec_text": b.transcript_original.strip(),
            })

    show_pri = getattr(config, "subtitle_show_primary", True)
    show_sec = (config.subtitle_mode == "bilingual" or not show_pri) and getattr(config, "subtitle_secondary_show", True)
    order = getattr(config, "subtitle_order", "primary_top")

    for item in sub_items:
        pri_text = sanitize_ass_special_chars(item["pri_text"]).replace("\n", "\\N") if show_pri else ""
        sec_text = sanitize_ass_special_chars(item["sec_text"]).replace("\n", "\\N") if show_sec else ""

        if not pri_text and not sec_text:
            continue
        start_ass = format_ass_time(item["start"])
        end_ass = format_ass_time(item["end"])

        if pri_text and sec_text and pri_text != sec_text:
            if order in ("secondary_top", "primary_bottom"):
                combined = f"{{\\rSecondary}}{sec_text}\\N{{\\rPrimary}}{pri_text}"
            else:
                combined = f"{pri_text}\\N{{\\rSecondary}}{sec_text}"
            dialogue_lines.append(f"Dialogue: 0,{start_ass},{end_ass},Primary,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{combined}")
        elif pri_text:
            dialogue_lines.append(f"Dialogue: 0,{start_ass},{end_ass},Primary,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{pri_text}")
        elif sec_text:
            dialogue_lines.append(f"Dialogue: 0,{start_ass},{end_ass},Secondary,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{sec_text}")

    full_content = ass_header + "\n".join(dialogue_lines) + "\n"
    output_ass_path.parent.mkdir(parents=True, exist_ok=True)
    output_ass_path.write_text(full_content, encoding="utf-8")
    return output_ass_path


def generate_batch_ass(
    batch: LectureBatch,
    output_ass_path: Path,
    config: LectureProjectConfig,
    video_width: int = 1920,
    video_height: int = 1080,
) -> Path:
    """
    Tạo file phụ đề .ass tương đối cho riêng 1 batch (bắt đầu từ 00:00:00.00).
    Đồng bộ mốc thời gian tuyệt đối với step_starts và giọng đọc TTS của batch.
    """
    font_name = config.font_name or "Arial"
    sec_font_name = resolve_secondary_font_name(config, [batch])
    font_size = config.font_size or "26"
    sec_scale = float(getattr(config, "secondary_scale", 0.70) or 0.70)
    sec_font_size = max(12, int(round(float(font_size) * sec_scale)))
    font_color = _color_to_ass(config.font_color, "&H00FFFFFF")
    outline_color = _color_to_ass(config.outline_color, "&H00000000")
    sec_font_color = _color_to_ass(getattr(config, "secondary_font_color", "&H00E7E1DC"), "&H00E7E1DC")

    center_x, center_y, margin_l, margin_r = resolve_subtitle_placement(config, video_width, video_height)

    ass_header = f"""[Script Info]
Title: AI Lecture Illustrator Batch Subtitles
ScriptType: v4.00+
WrapStyle: 0
ScaledBorderAndShadow: yes
YCbCr Matrix: TV.709
PlayResX: {video_width}
PlayResY: {video_height}

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Primary,{font_name},{font_size},{font_color},&H000000FF,{outline_color},&H80000000,-1,0,0,0,100,100,0,0,1,2.5,1,5,{margin_l},{margin_r},10,1
Style: Secondary,{sec_font_name},{sec_font_size},{sec_font_color},&H000000FF,{outline_color},&H80000000,0,0,0,0,100,100,0,0,1,2.0,1,5,{margin_l},{margin_r},10,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""

    dur = max(0.5, float(batch.scene_duration or (batch.end_sec - batch.start_sec) or 3.0))
    sentences = getattr(batch, "sentences", []) or []
    step_starts = getattr(batch, "step_starts", []) or []

    sub_items = []
    if sentences:
        for idx, s in enumerate(sentences):
            st = float(step_starts[idx]) if idx < len(step_starts) else (idx * 2.0)
            if idx + 1 < len(step_starts):
                et = min(dur, float(step_starts[idx + 1]))
            else:
                et = dur
            sub_items.append({
                "start": max(0.0, st),
                "end": max(st + 0.5, et),
                "pri_text": str(s.get("text", "")).strip(),
                "sec_text": str(s.get("text_secondary") or s.get("text_orig") or "").strip(),
            })
    else:
        pri = (batch.transcript_translated or batch.transcript_original or "").strip()
        sec = (batch.transcript_original or "").strip()
        if pri or sec:
            sub_items.append({
                "start": 0.0,
                "end": dur,
                "pri_text": pri,
                "sec_text": sec,
            })

    show_pri = getattr(config, "subtitle_show_primary", True)
    show_sec = (config.subtitle_mode == "bilingual" or not show_pri) and getattr(config, "subtitle_secondary_show", True)
    order = getattr(config, "subtitle_order", "primary_top")

    dialogue_lines = []
    for item in sub_items:
        pri_text = sanitize_ass_special_chars(item["pri_text"]).replace("\n", "\\N") if show_pri else ""
        sec_text = sanitize_ass_special_chars(item["sec_text"]).replace("\n", "\\N") if show_sec else ""

        if not pri_text and not sec_text:
            continue
        start_ass = format_ass_time(item["start"])
        end_ass = format_ass_time(item["end"])

        if pri_text and sec_text and pri_text != sec_text:
            if order in ("secondary_top", "primary_bottom"):
                combined = f"{{\\rSecondary}}{sec_text}\\N{{\\rPrimary}}{pri_text}"
            else:
                combined = f"{pri_text}\\N{{\\rSecondary}}{sec_text}"
            dialogue_lines.append(f"Dialogue: 0,{start_ass},{end_ass},Primary,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{combined}")
        elif pri_text:
            dialogue_lines.append(f"Dialogue: 0,{start_ass},{end_ass},Primary,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{pri_text}")
        elif sec_text:
            dialogue_lines.append(f"Dialogue: 0,{start_ass},{end_ass},Secondary,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{sec_text}")

    full_content = ass_header + "\n".join(dialogue_lines) + "\n"
    output_ass_path.parent.mkdir(parents=True, exist_ok=True)
    output_ass_path.write_text(full_content, encoding="utf-8")
    return output_ass_path

