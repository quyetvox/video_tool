"""
Subtitle and inpaint utilities for Movie Review engine:
- Speed-calibrated sentence splitting
- Rhythmic subtitle cue chunking & Orphan Guard
- ASS subtitle generation with \\pos centering
- Safe Chroma Clamping FFmpeg BoxBlur inpaint filter
"""

import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT_DIR = Path(__file__).parent.parent.parent.resolve()


def split_long_segments_by_speed(
    script_items: List[Dict[str, Any]],
    speed_factor: float = 1.45,
    target_shot_sec_range: Tuple[float, float] = (3.5, 7.5)
) -> List[Dict[str, Any]]:
    """
    SOP Tự động phân đoạn kịch bản dựa vào tốc độ đọc TTS (Speed-Calibrated Segmentation).
    Đảm bảo mỗi phân cảnh là một shot ngắn gọn từ 3.5s - 7.5s, tương ứng 10-22 từ (tùy speed).
    """
    if not script_items:
        return []

    speed = max(0.8, min(2.0, speed_factor))
    words_per_sec = (140.0 * speed) / 60.0
    min_words = max(8, int(round(target_shot_sec_range[0] * words_per_sec)))
    max_words = max(16, int(round(target_shot_sec_range[1] * words_per_sec)))

    def split_text_into_chunks(text: str) -> List[str]:
        raw_text = text.strip()
        if not raw_text:
            return []
        words = raw_text.split()
        if len(words) <= max_words:
            return [raw_text]

        # 1. Tách theo dấu kết câu
        sentences = re.split(r"(?<=[.?!])\s+|\n+", raw_text)
        sub_units = []
        for s in sentences:
            s = s.strip()
            if not s:
                continue
            s_words = s.split()
            if len(s_words) <= max_words:
                sub_units.append(s)
            else:
                # Tách theo dấu phẩy, chấm phẩy, gạch nối
                clauses = re.split(r"(?<=[,;—–])\s+", s)
                for c in clauses:
                    c = c.strip()
                    if not c:
                        continue
                    c_words = c.split()
                    if len(c_words) <= max_words:
                        sub_units.append(c)
                    else:
                        # Tách theo liên từ nếu vẫn quá dài
                        sub_clauses = re.split(r"\s+(?:và|nhưng|mà|nên|do đó|vì vậy|tuy nhiên)\s+", c, flags=re.IGNORECASE)
                        if len(sub_clauses) > 1:
                            for sc in sub_clauses:
                                sc = sc.strip()
                                if sc:
                                    sub_units.append(sc)
                        else:
                            # Cắt cứng theo số từ nếu không có dấu câu hay liên từ
                            w_list = c.split()
                            for idx in range(0, len(w_list), max_words):
                                chunk = " ".join(w_list[idx : idx + max_words])
                                if chunk:
                                    sub_units.append(chunk)

        # Gom các sub_units thành các chunks hợp lý (nằm trong [min_words, max_words])
        chunks = []
        current_chunk = []
        current_word_count = 0

        for unit in sub_units:
            u_words = len(unit.split())
            if current_word_count + u_words <= max_words:
                current_chunk.append(unit)
                current_word_count += u_words
            else:
                if current_chunk:
                    chunks.append(" ".join(current_chunk))
                current_chunk = [unit]
                current_word_count = u_words

        if current_chunk:
            # Greedy Merge cho TTS: Nếu chunk cuối quá ngắn (< min_words hoặc <= 6 từ), luôn gộp vào chunk trước
            if chunks and (current_word_count < min_words or current_word_count <= 6):
                chunks[-1] = chunks[-1] + " " + " ".join(current_chunk)
            else:
                chunks.append(" ".join(current_chunk))

        # Kiểm tra lại: Tuyệt đối không để sót chunk nào quá ngắn (<= 5 từ) làm ngắt quãng giọng đọc
        merged_chunks = []
        for ch in chunks:
            ch_words = len(ch.split())
            if ch_words <= 5 and merged_chunks:
                merged_chunks[-1] = merged_chunks[-1] + " " + ch
            else:
                merged_chunks.append(ch)
        chunks = merged_chunks if merged_chunks else chunks

        return chunks if chunks else [raw_text]

    result = []
    for item in script_items:
        raw_text = item.get("voiceover_text", "").strip()
        chunks = split_text_into_chunks(raw_text)
        if len(chunks) <= 1:
            result.append(dict(item))
            continue

        orig_scenes = item.get("scenes_to_use", [])
        num_chunks = len(chunks)

        for c_idx, chunk_text in enumerate(chunks):
            sub_item = dict(item)
            sub_item["voiceover_text"] = chunk_text

            # Phân bổ scenes_to_use cho sub-item
            if orig_scenes:
                if len(orig_scenes) >= num_chunks:
                    s_start = c_idx * len(orig_scenes) // num_chunks
                    s_end = (c_idx + 1) * len(orig_scenes) // num_chunks
                    sub_item["scenes_to_use"] = orig_scenes[s_start:max(s_start + 1, s_end)]
                else:
                    if len(orig_scenes) == 1:
                        sc = orig_scenes[0]
                        sc_start = float(sc.get("start_sec", 0.0))
                        sc_end = float(sc.get("end_sec", sc_start + 5.0))
                        dur = max(4.0, sc_end - sc_start)
                        # Thay vì cắt vụn cảnh thành các mẩu 2s rồi loop,
                        # mỗi chunk nhận 1 phân đoạn liên tiếp riêng biệt từ phim gốc
                        chunk_start = round(sc_start + c_idx * dur, 2)
                        chunk_end = round(chunk_start + dur, 2)
                        sub_item["scenes_to_use"] = [{
                            "scene_id": sc.get("scene_id", 1),
                            "start_sec": chunk_start,
                            "end_sec": chunk_end
                        }]
                    else:
                        sub_item["scenes_to_use"] = [orig_scenes[c_idx % len(orig_scenes)]]
            result.append(sub_item)

    # Đánh lại ID tuần tự 1, 2, 3...
    for i, it in enumerate(result):
        it["id"] = i + 1

    return result


def wrap_subtitle_text(text: str, max_chars: int = 38) -> str:
    """Tự động chia câu dài thành 2 dòng cân đối, tránh tràn viền màn hình."""
    if len(text) <= max_chars or "\\N" in text:
        return text
    words = text.split()
    mid = max(1, len(words) // 2)
    return " ".join(words[:mid]) + "\\N" + " ".join(words[mid:])


def split_subtitle_into_rhythmic_cues(
    text: str,
    audio_duration: float,
    max_words_per_cue: int = 6
) -> List[Tuple[float, float, str]]:
    """
    Chia câu thoại thành các cụm phụ đề ngắn gọn (4-6 từ) theo nhịp đọc.
    Phân bổ thời lượng theo tỷ lệ số từ, đảm bảo chữ nhảy dứt khoát, tròn câu và không tràn viền.
    Triệt tiêu 100% từ mồ côi (Orphan Guard: không bao giờ có cụm 1-2 từ chớp nhoáng).
    Trả về danh sách (start_rel_sec, end_rel_sec, cue_text).
    """
    raw_text = text.strip()
    if not raw_text or audio_duration <= 0:
        return []

    # 1. Tách theo dấu ngắt câu hoặc dấu phẩy
    raw_clauses = re.split(r"(?<=[,;.?!—–\n])\s+", raw_text)
    units = []
    for cl in raw_clauses:
        cl = cl.strip()
        if not cl:
            continue
        words = cl.split()
        if len(words) <= max_words_per_cue:
            units.append(cl)
        else:
            # Equi-balanced Chunking: Chia đều số từ vào các cụm cân đối
            # Ví dụ: 25 từ chia thành 5 cụm x 5 từ thay vì [6, 6, 6, 6, 1]
            num_chunks = max(1, (len(words) + max_words_per_cue - 1) // max_words_per_cue)
            words_per_chunk = len(words) // num_chunks
            remainder = len(words) % num_chunks
            w_idx = 0
            for c_i in range(num_chunks):
                chunk_len = words_per_chunk + (1 if c_i < remainder else 0)
                chunk_str = " ".join(words[w_idx : w_idx + chunk_len])
                w_idx += chunk_len
                if chunk_str:
                    units.append(chunk_str)

    if not units:
        units = [raw_text]

    # 2. Gom các cụm từ thành các cues hợp lý
    cues = []
    current_cue = []
    current_count = 0
    for u in units:
        u_words = len(u.split())
        if current_count + u_words <= max_words_per_cue:
            current_cue.append(u)
            current_count += u_words
        else:
            if current_cue:
                cues.append(" ".join(current_cue))
            current_cue = [u]
            current_count = u_words
    if current_cue:
        cues.append(" ".join(current_cue))

    # 3. Orphan Guard: Gộp các cụm mồ côi (<= 2 từ) vào cụm liền kề
    merged_cues = []
    for c in cues:
        w_list = c.split()
        if len(w_list) <= 2 and merged_cues:
            merged_cues[-1] = merged_cues[-1] + " " + c
        else:
            merged_cues.append(c)
    cues = merged_cues if merged_cues else cues

    # Nếu cụm cuối cùng vẫn <= 2 từ và có cụm trước đó, gộp vào cụm trước
    if len(cues) >= 2 and len(cues[-1].split()) <= 2:
        orphan = cues.pop()
        cues[-1] = cues[-1] + " " + orphan

    if not cues:
        cues = [raw_text]

    total_words = sum(len(c.split()) for c in cues)
    if total_words == 0:
        return [(0.0, audio_duration, raw_text)]

    result = []
    curr_t = 0.0
    for i, c in enumerate(cues):
        w_cnt = len(c.split())
        cue_dur = audio_duration * (w_cnt / total_words)
        start_t = round(curr_t, 2)
        end_t = round(audio_duration if i == len(cues) - 1 else curr_t + cue_dur, 2)
        cue_clean = c.replace("{", "\\{").replace("}", "\\}").replace("\n", "\\N")
        if len(cue_clean) > 30 and "\\N" not in cue_clean:
            cue_clean = wrap_subtitle_text(cue_clean, max_chars=28)
        result.append((start_t, end_t, cue_clean))
        curr_t += cue_dur

    return result


def _color_to_ass(c: str, default: str = "&H00FFFFFF") -> str:
    """Chuyển đổi mã màu hex (#RRGGBB hoặc #AARRGGBB) sang định dạng màu ASS (&HAABBGGRR)."""
    if not c:
        return default
    c = str(c).strip()
    if c.startswith("&H") or c.startswith("&h"):
        return c
    if c.startswith("#"):
        c = c[1:]
    if len(c) == 6:
        r, g, b = c[0:2], c[2:4], c[4:6]
        return f"&H00{b}{g}{r}".upper()
    if len(c) == 8:
        a, r, g, b = c[0:2], c[2:4], c[4:6], c[6:8]
        return f"&H{a}{b}{g}{r}".upper()
    return default


def generate_review_ass_subtitles(
    segments: List[Dict[str, Any]],
    output_ass_path: Path,
    video_width: int = 1920,
    video_height: int = 1080,
    project_config: Optional[Dict[str, Any]] = None
) -> Path:
    """Tạo file phụ đề .ass chuẩn hóa khớp chính xác timing từng phân đoạn voiceover theo nhịp đọc và tọa độ Gizmo."""
    cfg = project_config or {}
    sub_cfg = cfg.get("subtitle", {})

    font_name = sub_cfg.get("font_name") or cfg.get("subtitle_font_name") or "Arial"
    is_vertical = video_height > video_width
    font_size = int(sub_cfg.get("font_size") or cfg.get("subtitle_font_size") or (46 if is_vertical else 34))
    font_color = _color_to_ass(sub_cfg.get("font_color") or cfg.get("subtitle_font_color"), "&H00FFFFFF")
    outline_color = _color_to_ass(sub_cfg.get("outline_color") or cfg.get("subtitle_outline_color"), "&H00000000")
    outline_width = int(sub_cfg.get("outline_width") or cfg.get("subtitle_outline_width") or 3)

    # Tọa độ vùng phụ đề từ Gizmo: [top, left, bottom, right]
    pri_region = sub_cfg.get("region") or cfg.get("subtitle_region") or [0.76, 0.05, 0.86, 0.95]
    if isinstance(pri_region, (list, tuple)) and len(pri_region) == 4:
        top, left, bottom, right = [float(v) for v in pri_region]
    else:
        top, left, bottom, right = 0.76, 0.05, 0.86, 0.95

    center_x = max(10, min(video_width - 10, int(video_width * (left + right) / 2.0)))
    center_y = max(10, min(video_height - 10, int(video_height * (top + bottom) / 2.0)))

    ass_lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        f"PlayResX: {video_width}",
        f"PlayResY: {video_height}",
        "ScaledBorderAndShadow: yes",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        f"Style: ReviewDefault,{font_name},{font_size},{font_color},&H000000FF,{outline_color},&H80000000,-1,0,0,0,100,100,0,0,1,{outline_width},1,5,10,10,10,1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]

    def format_ass_time(sec: float) -> str:
        h = int(sec // 3600)
        m = int((sec % 3600) // 60)
        s = int(sec % 60)
        cs = int(round((sec - int(sec)) * 100))
        if cs >= 100:
            cs = 99
        return f"{h}:{m:02d}:{s:02d}.{cs:02d}"

    current_t = 0.0
    for seg in segments:
        text = seg.get("voiceover_text", "").strip()
        voice_dur = float(seg.get("audio_duration", 5.0))
        seg_dur = float(seg.get("segment_duration", voice_dur))
        if not text:
            current_t += seg_dur
            continue

        cues = split_subtitle_into_rhythmic_cues(text, voice_dur)
        for start_rel, end_rel, cue_text in cues:
            start_str = format_ass_time(current_t + start_rel)
            end_str = format_ass_time(current_t + end_rel)
            ass_lines.append(f"Dialogue: 0,{start_str},{end_str},ReviewDefault,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{cue_text}")

        current_t += seg_dur

    output_ass_path.parent.mkdir(parents=True, exist_ok=True)
    output_ass_path.write_text("\n".join(ass_lines), encoding="utf-8")
    return output_ass_path


def build_inpaint_filter(
    video_width: int,
    video_height: int,
    project_config: Optional[Dict[str, Any]] = None
) -> Optional[str]:
    """Tạo chuỗi filter boxblur làm mờ vùng sub cũ theo inpaint.region trong config.yaml."""
    cfg = project_config or {}
    inp = cfg.get("inpaint", {})
    region = inp.get("region") or cfg.get("inpaint_region")  # [top, left, bottom, right]
    if not region or len(region) < 4:
        return None

    top, left, bottom, right = float(region[0]), float(region[1]), float(region[2]), float(region[3])
    box_w = max(2, int((right - left) * video_width))
    box_h = max(2, int((bottom - top) * video_height))
    box_x = max(0, int(left * video_width))
    box_y = max(0, int(top * video_height))

    # Đảm bảo box_w và box_h chẵn
    box_w = box_w if box_w % 2 == 0 else box_w - 1
    box_h = box_h if box_h % 2 == 0 else box_h - 1

    radius = int(inp.get("blur_radius") or cfg.get("inpaint_blur_radius", 15))
    # Adaptive Safe Radius Clamping:
    # Trong FFmpeg boxblur với chuẩn màu YUV420p (subsample 2x2):
    # - Kênh Luma (Y): bán kính tối đa <= box_dim / 2
    # - Kênh Chroma (U, V): bán kính tối đa <= (box_dim / 2) / 2 = box_dim / 4
    max_luma_r = max(1, min(box_w // 2 - 1, box_h // 2 - 1))
    max_chroma_r = max(1, min(box_w // 4 - 1, box_h // 4 - 1))
    safe_luma_r = max(1, min(radius, max_luma_r))
    safe_chroma_r = max(1, min(radius, max_chroma_r))

    return (
        f"split[v_main][v_crop];"
        f"[v_crop]crop={box_w}:{box_h}:{box_x}:{box_y},"
        f"boxblur={safe_luma_r}:2:{safe_chroma_r}:2[v_blur];"
        f"[v_main][v_blur]overlay={box_x}:{box_y}"
    )
