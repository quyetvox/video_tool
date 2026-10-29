"""Dịch → gom nhóm → TTS → scene plan cho Lecture Illustrator (cảnh sinh mới, không dùng hình video gốc)."""
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from .common import clean_json_str, emit_log, emit_progress
from .knowledge_extractor import call_llm_api, translate_text_free
from .models import LectureProjectConfig
from .scene_validator import validate_scene

LEAD_IN = 1.2         # giây đầu mỗi cảnh để tiêu đề được vẽ trước khi câu đầu tiên được đọc
TAIL = 0.6            # giây cuối mỗi cảnh sau câu cuối
SENTENCE_GAP = 0.25   # nghỉ giữa các câu trong cùng nhóm
MAX_SENTENCES = 4     # giới hạn số câu mỗi nhóm (2-4 câu) chống nhồi nhét, đảm bảo đồ họa thoáng đãng
PAUSE_SPLIT = 1.2     # khoảng lặng (giây) trong video gốc coi là ranh giới nhóm


# ── Dịch ─────────────────────────────────────────────────────────────────────

def _chunks(items: list, size: int):
    for i in range(0, len(items), size):
        yield i, items[i:i + size]


import re

def _contains_cjk(text: str) -> bool:
    """Kiểm tra chuỗi có chứa ký tự chữ Hán (CJK) hay không."""
    return bool(re.search(r"[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]", str(text or "")))


def translate_sentences(
    segments: List[Dict[str, Any]],
    config: LectureProjectConfig,
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Dịch từng câu ASR sang ngôn ngữ đích (target_lang) và ngôn ngữ phụ (secondary_lang nếu bật song ngữ)."""
    try:
        from engine.shared.repetition_cleaner import RepetitionCleaner
        segments = RepetitionCleaner.clean_segments(segments)
    except Exception:
        pass

    src = [s for s in segments if str(s.get("text", "")).strip()]
    texts = [str(s["text"]).strip() for s in src]
    out: List[Optional[str]] = [None] * len(texts)
    target_lang = config.target_lang or "vi"

    # 1. Dịch theo lô bằng LLM (nếu có api_key hoặc base_url)
    if api_key or base_url:
        for base, chunk in _chunks(texts, 20):
            prompt = (
                f"Dịch từng câu sau sang ngôn ngữ '{target_lang}' (xưng hô: {config.pronoun_mode}), "
                "giữ nguyên ý, tự nhiên, ngắn gọn như lời giảng. Tuyệt đối không để sót ký tự ngôn ngữ nguồn. "
                f"Trả về DUY NHẤT một JSON array gồm đúng {len(chunk)} chuỗi tiếng {target_lang} theo thứ tự.\n"
                + json.dumps(chunk, ensure_ascii=False)
            )
            try:
                raw_resp = call_llm_api(prompt, api_key, model or "gemini-2.5-flash", base_url) or ""
                parsed = json.loads(clean_json_str(raw_resp))
                if isinstance(parsed, list) and len(parsed) == len(chunk):
                    for j, t in enumerate(parsed):
                        if isinstance(t, str) and t.strip() and not _contains_cjk(t):
                            out[base + j] = t.strip()
            except Exception as e:  # noqa: BLE001
                emit_log("warn", f"Dịch LLM lô {base // 20 + 1} lỗi ({e}), chuyển sang tự phục hồi...")

    # 2. Multi-tier Fallback cho các câu còn thiếu hoặc bị dính CJK
    missing_indices = [i for i, t in enumerate(out) if not t or _contains_cjk(t)]
    if missing_indices:
        emit_log("info", f"Kích hoạt Translation Guard tự phục hồi cho {len(missing_indices)} câu thoại...")

        def _safe_translate_one(idx: int) -> str:
            orig = texts[idx]
            # Thử dịch trực tiếp sang target_lang
            res = translate_text_free(orig, target_lang)
            if res and not _contains_cjk(res) and res.strip() != orig:
                return res.strip()

            # Thử bắc cầu qua tiếng Anh: CJK -> EN -> target_lang
            en_mid = translate_text_free(orig, "en")
            if en_mid and not _contains_cjk(en_mid):
                res2 = translate_text_free(en_mid, target_lang)
                if res2 and not _contains_cjk(res2):
                    return res2.strip()

            # Nếu vẫn còn ký tự CJK, làm sạch triệt để loại bỏ ký tự lạ
            clean = re.sub(r"[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff]+", " ", res or orig)
            clean = re.sub(r"\s+", " ", clean).strip()
            return clean if clean else "Khái niệm và nội dung bài học"

        with ThreadPoolExecutor(max_workers=4) as pool:
            for i, translated in zip(missing_indices, pool.map(_safe_translate_one, missing_indices)):
                out[i] = translated

    # 3. Dịch ngôn ngữ phụ secondary_lang (nếu bật song ngữ và secondary_lang khác target_lang)
    out_sec: List[str] = list(texts)
    sec_lang = (config.secondary_lang or "").strip().lower()
    if sec_lang and sec_lang != "none" and sec_lang != target_lang.lower():
        if sec_lang == (config.source_lang or "").lower():
            out_sec = list(texts)
        else:
            emit_log("info", f"Đang dịch dòng phụ sang ngôn ngữ đã chọn: '{sec_lang}'...")
            with ThreadPoolExecutor(max_workers=4) as pool:
                sec_translated = list(pool.map(lambda t: translate_text_free(t, sec_lang), texts))
                out_sec = [t if t and t.strip() and not _contains_cjk(t) else orig for t, orig in zip(sec_translated, texts)]

    return [
        {
            "start": float(s.get("start", 0.0)),
            "end": float(s.get("end", 0.0)),
            "text_orig": texts[i],
            "text": out[i] or "Nội dung bài học",
            "text_secondary": out_sec[i] if i < len(out_sec) else texts[i],
        }
        for i, s in enumerate(src)
    ]


def translate_secondary_subtitles(
    sentences: List[Dict[str, Any]],
    config: LectureProjectConfig,
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """
    Dịch tự động text_secondary sang config.secondary_lang (mặc định 'en')
    khi config.subtitle_mode == 'bilingual' và secondary_lang khác target_lang.
    Hỗ trợ LLM batch đa luồng kết hợp free translation fallback.
    """
    sec_lang = (getattr(config, "secondary_lang", "en") or "en").strip().lower()
    target_lang = (getattr(config, "target_lang", "vi") or "vi").strip().lower()

    if getattr(config, "subtitle_mode", "bilingual") != "bilingual" or not sec_lang or sec_lang in ("none", target_lang):
        return sentences

    indices_to_translate: List[int] = []
    texts_to_translate: List[str] = []

    for idx, s in enumerate(sentences):
        sec = str(s.get("text_secondary", "")).strip()
        pri = str(s.get("text", "")).strip()
        # Dịch nếu text_secondary rỗng hoặc đang trùng với câu chính
        if pri and (not sec or sec == pri):
            indices_to_translate.append(idx)
            texts_to_translate.append(pri)

    if not indices_to_translate:
        return sentences

    emit_log("info", f"Đang dịch tự động {len(indices_to_translate)} dòng phụ (secondary subtitle) sang '{sec_lang}'...")
    translated_map: Dict[int, str] = {}

    # 1. Thử dịch theo lô bằng LLM nếu có api_key hoặc base_url
    if api_key or base_url:
        for base, chunk in _chunks(texts_to_translate, 20):
            prompt = (
                f"Translate each sentence to '{sec_lang}'. "
                "Keep it natural, concise, and clear for video subtitles. Do not include markdown or extra explanations. "
                f"Return ONLY a JSON array with exactly {len(chunk)} translated strings in the same order.\n"
                + json.dumps(chunk, ensure_ascii=False)
            )
            try:
                raw_resp = call_llm_api(prompt, api_key, model or "gemini-2.5-flash", base_url) or ""
                parsed = json.loads(clean_json_str(raw_resp))
                if isinstance(parsed, list) and len(parsed) == len(chunk):
                    for j, t in enumerate(parsed):
                        if isinstance(t, str) and t.strip() and t.strip() != chunk[j]:
                            translated_map[base + j] = t.strip()
            except Exception as e:
                emit_log("warn", f"LLM dịch dòng phụ lô {base // 20 + 1} lỗi ({e}), chuyển sang fallback...")

    # 2. Multi-threaded Fallback bằng translate_text_free
    missing_locs = [k for k in range(len(texts_to_translate)) if k not in translated_map]
    if missing_locs:
        def _translate_one(k: int):
            t = texts_to_translate[k]
            res = translate_text_free(t, sec_lang)
            return k, res.strip() if res else ""

        with ThreadPoolExecutor(max_workers=6) as pool:
            for k, res in pool.map(_translate_one, missing_locs):
                if res and res != texts_to_translate[k]:
                    translated_map[k] = res

    # 3. Cập nhật vào danh sách câu
    for k, orig_idx in enumerate(indices_to_translate):
        if k in translated_map and translated_map[k]:
            sentences[orig_idx]["text_secondary"] = translated_map[k]

    return sentences


DANGLING_END_PATTERN = re.compile(
    r"([,;:\-—…]\s*$)|(\b(và|hoặc|nhưng|vì|do|khi|nếu|để|rằng|là|thì|mà|của|với|trong|cho|ở|về|and|or|but|because|since|as|with|that|which|who|in|to|for|of|is|are|was|were|the|a|an|then|if|when)\s*$)",
    re.IGNORECASE,
)

LOWERCASE_START_PATTERN = re.compile(
    r"^\s*[a-zàáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]",
)


TERMINAL_PUNCTUATION_PATTERN = re.compile(
    r"[.!?…][”\"\'\)\]]*\s*$"
)


def is_dangling_boundary(s1: Dict[str, Any], s2: Dict[str, Any]) -> bool:
    """Kiểm tra ranh giới giữa 2 câu có bị đứt gãy ngữ pháp (câu trước kết thúc dở dang, câu sau viết thường, hoặc câu sau là mảnh mồ côi)."""
    t1_vi = str(s1.get("text", "")).strip()
    t1_orig = str(s1.get("text_orig", "")).strip()
    t2_vi = str(s2.get("text", "")).strip()
    t2_orig = str(s2.get("text_orig", "")).strip()

    t1 = t1_vi if t1_vi else t1_orig
    t2 = t2_vi if t2_vi else t2_orig

    if not t1 or not t2:
        return False

    if s1.get("type_hint") in ("title_point", "heading") or s2.get("type_hint") in ("title_point", "heading"):
        return False

    w2 = len(t2.split())
    t1_has_terminal = bool(TERMINAL_PUNCTUATION_PATTERN.search(t1))
    t2_starts_lower = bool(LOWERCASE_START_PATTERN.search(t2))
    t1_is_dangling = bool(DANGLING_END_PATTERN.search(t1))

    # 1. Mảnh câu mồ côi (Orphan Fragment Rule): câu kế tiếp chỉ có <= 2 từ (như "xếp.", "Tuy vậy,")
    # hoặc câu sau bắt đầu bằng chữ cái viết thường (như "vào đúng vị trí.") -> Luôn là phần sau của câu trước!
    if w2 <= 2 or t2_starts_lower:
        return True

    # 2. Câu trước chưa kết thúc dấu câu (. ! ? …) hoặc kết thúc bằng dấu phẩy, liên từ nối
    if not t1_has_terminal or t1_is_dangling:
        return True

    return False


def stitch_sentence_boundaries(
    sentences: List[Dict[str, Any]],
    concat_audio_fn: Optional[Any] = None,
) -> List[Dict[str, Any]]:
    """Tự động khâu nối các câu/mảnh câu bị cắt ngang giữa chừng (kết thúc bằng dấu phẩy, liên từ, vế sau viết thường hoặc mảnh mồ côi <= 2 từ)."""
    if not sentences:
        return []

    stitched: List[Dict[str, Any]] = [dict(sentences[0])]
    for s in sentences[1:]:
        prev = stitched[-1]
        p_text = str(prev.get("text", "")).strip()
        s_text = str(s.get("text", "")).strip()
        p_words = len(p_text.split())
        s_words = len(s_text.split())

        # Tuyệt đối không khâu nối tiêu đề / đề mục với câu thân bài bên dưới
        if prev.get("type_hint") in ("title_point", "heading") or s.get("type_hint") in ("title_point", "heading"):
            stitched.append(dict(s))
            continue

        is_dangling = is_dangling_boundary(prev, s)
        is_orphan = (
            s_words <= 2
            or bool(LOWERCASE_START_PATTERN.search(s_text))
            or not bool(TERMINAL_PUNCTUATION_PATTERN.search(p_text))
        )

        # Điều kiện khâu nối:
        # - Nếu là mảnh mồ côi / từ bị xé rách (orphan): cho phép tổng câu lên tới 38 từ để chống dị tật giọng đọc và phụ đề
        # - Nếu là 2 mệnh đề thông thường: giới hạn tổng từ <= 32 và câu trước < 22 để tránh phụ đề phình to
        should_stitch = False
        if is_orphan and (p_words + s_words) <= 38:
            should_stitch = True
        elif is_dangling and (p_words + s_words) <= 32 and p_words < 22:
            should_stitch = True

        if should_stitch:
            joined_text = f"{p_text} {s_text}".strip()

            p_orig = str(prev.get("text_orig", "")).strip()
            s_orig = str(s.get("text_orig", "")).strip()
            joined_orig = f"{p_orig} {s_orig}".strip()

            p_sec = str(prev.get("text_secondary", "")).strip()
            s_sec = str(s.get("text_secondary", "")).strip()
            joined_sec = f"{p_sec} {s_sec}".strip() if (p_sec or s_sec) else joined_orig

            prev["text"] = joined_text
            prev["text_orig"] = joined_orig
            prev["text_secondary"] = joined_sec
            prev["end"] = max(float(prev.get("end", 0.0)), float(s.get("end", 0.0)))
            prev_dur = float(prev.get("duration", 0.0))
            s_dur = float(s.get("duration", 0.0))
            prev["duration"] = round(prev_dur + s_dur, 3)

            if "audio_file" in prev and "audio_file" in s and concat_audio_fn:
                try:
                    concat_audio_fn(prev["audio_file"], s["audio_file"])
                except Exception:
                    pass
        else:
            stitched.append(dict(s))

    return stitched


TOPIC_SHIFT_PATTERN = re.compile(
    r"^\s*(bây giờ|tiếp theo|chúng ta cùng|tóm lại|tổng kết|nhìn xa hơn|thực tế|đây chính là|chuyển sang|nói cách khác|tôi muốn|sau đây)\b",
    re.IGNORECASE,
)
EXAMPLE_INDICATOR_PATTERN = re.compile(
    r"\b(ví dụ|chẳng hạn|giả sử|tình huống|trường hợp|xét ví dụ|lấy ví dụ)\b",
    re.IGNORECASE,
)


def _group_sentences_heuristic(sentences: List[Dict[str, Any]]) -> List[List[Dict[str, Any]]]:
    """Phân nhóm câu dự phòng bằng quy tắc heuristic khoảng lặng và ranh giới ngữ pháp."""
    groups: List[List[Dict[str, Any]]] = []
    cur: List[Dict[str, Any]] = []

    for s in sentences:
        txt = str(s.get("text", "")).strip()
        is_topic_shift = bool(TOPIC_SHIFT_PATTERN.search(txt))
        is_example = bool(EXAMPLE_INDICATOR_PATTERN.search(txt))

        # Kiểm tra khoảng lặng thực tế từ audio gốc
        pause_gap = s["start"] - cur[-1]["end"] if cur else 0.0

        should_split = False
        if cur:
            # Bảo vệ ngữ pháp: Nếu câu trước dở dang hoặc câu sau bắt đầu bằng chữ thường, ưu tiên không ngắt cụm
            can_split_grammatically = not is_dangling_boundary(cur[-1], s)

            # 1. Chạm ngưỡng tối đa MAX_SENTENCES
            if len(cur) >= MAX_SENTENCES:
                should_split = True
            # 2. Mở đầu ví dụ mới độc lập (đã có >= 2 câu lý thuyết trước đó) và ranh giới ngữ pháp cho phép
            elif is_example and len(cur) >= 2 and can_split_grammatically:
                should_split = True
            # 3. Đã đủ nội dung (>= 3 câu) và gặp điểm chuyển chủ đề hoặc khoảng lặng lớn
            elif len(cur) >= 3 and (is_topic_shift or pause_gap >= PAUSE_SPLIT) and can_split_grammatically:
                should_split = True

        if should_split:
            groups.append(cur)
            cur = []

        cur.append(s)

    # Xử lý đoạn dôi dư cuối cùng: hòa nhập nếu chỉ có 1 câu cô độc để tránh cảnh cụt
    if cur:
        cur_has_example = bool(EXAMPLE_INDICATOR_PATTERN.search(str(cur[0].get("text", "")))) if cur else False
        if len(cur) == 1 and not cur_has_example and groups and len(groups[-1]) < MAX_SENTENCES:
            groups[-1].extend(cur)
        else:
            groups.append(cur)

    return groups


def _group_sentences_by_paragraphs(sentences: List[Dict[str, Any]]) -> List[List[Dict[str, Any]]]:
    """Gom nhóm theo ranh giới đoạn văn (\n\n / para_idx) do tác giả đã chủ động phân đoạn."""
    groups_dict: Dict[int, List[Dict[str, Any]]] = {}
    for s in sentences:
        p_idx = s.get("para_idx", 0)
        if p_idx not in groups_dict:
            groups_dict[p_idx] = []
        groups_dict[p_idx].append(s)

    raw_groups = list(groups_dict.values())
    if len(raw_groups) <= 1:
        return _group_sentences_heuristic(sentences)

    # Hòa nhập đoạn đơn câu cực ngắn (< 2 câu) vào đoạn kế tiếp nếu không quá dài
    merged_groups: List[List[Dict[str, Any]]] = []
    for g in raw_groups:
        if merged_groups and len(merged_groups[-1]) == 1 and (len(merged_groups[-1]) + len(g) <= 8):
            merged_groups[-1].extend(g)
        else:
            merged_groups.append(g)

    return merged_groups or [sentences]


def _generate_default_metas_for_groups(groups: List[List[Dict[str, Any]]]) -> List[Dict[str, Any]]:
    """Sinh metadata mặc định cho các nhóm phân cảnh khi chạy fallback không có LLM."""
    metas: List[Dict[str, Any]] = []
    for g in groups:
        first_txt = g[0].get("text", "") if g else "Bài giảng"
        title = extract_concise_title(first_txt)
        metas.append({
            "title": title,
            "visual_concept": f"Mô phỏng nội dung {title}",
            "diagram_type": "process_steps",
        })
    return metas


def plan_semantic_knowledge_units(
    sentences: List[Dict[str, Any]],
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
    llm_caller: Optional[Any] = None,
) -> Tuple[List[List[Dict[str, Any]]], List[Dict[str, Any]]]:
    """
    Sử dụng LLM 1-Pass để chia toàn bộ kịch bản bài giảng thành các Cụm Tri thức Trọn vẹn (Semantic Knowledge Units).
    Mỗi cụm đại diện cho 1 phân cảnh minh họa (Scene) hoàn chỉnh về mặt ngữ nghĩa và khái niệm.

    RÀNG BUỘC CHÍNH:
    - Không gò bó cứng nhắc số câu (mỗi cụm có thể từ 2 câu đến 6-8 câu nếu cùng nằm trong một chu trình/khái niệm).
    - Phủ kín 100% các câu từ index 0 đến len(sentences)-1, không bỏ sót, không trùng lặp.
    - Trả về: (groups, group_metas)
    """
    if not sentences:
        return [], []
    if len(sentences) == 1:
        txt = sentences[0].get("text", "")
        return [sentences], [{
            "title": extract_concise_title(txt),
            "visual_concept": f"Minh họa {extract_concise_title(txt)}",
            "diagram_type": "process_steps",
        }]

    has_paragraphs = len(set(s.get("para_idx", 0) for s in sentences)) > 1

    def _fallback() -> Tuple[List[List[Dict[str, Any]]], List[Dict[str, Any]]]:
        if has_paragraphs:
            fb_groups = _group_sentences_by_paragraphs(sentences)
        else:
            fb_groups = _group_sentences_heuristic(sentences)
        fb_metas = _generate_default_metas_for_groups(fb_groups)
        return fb_groups, fb_metas

    if not (api_key or base_url or llm_caller):
        return _fallback()

    indexed_lines = []
    for i, s in enumerate(sentences):
        txt = str(s.get("text", "")).strip()
        indexed_lines.append(f"[{i}] {txt}")
    content_block = "\n".join(indexed_lines)

    prompt = f"""Bạn là Giám Đốc Nội Dung & Kỹ Sư Đồ Họa Bài Giảng Giáo Dục.
Nhiệm vụ của bạn là phân tích toàn bộ kịch bản bài giảng dưới đây và chia thành các "Cụm Tri thức Trọn vẹn" (Complete Semantic Knowledge Units) để làm các phân cảnh minh họa hoạt ảnh (Visual Scenes).

--- NỘI DUNG TOÀN BỘ BÀI GIẢNG ({len(sentences)} CÂU THOẠI) ---
{content_block}
-----------------------------------------------------------

NGUYÊN TẮC PHÂN CỤM BẮT BUỘC (CRITICAL INVARIANTS):
1. BẢO TOÀN TRỌN VẸN NGỮ CẢNH Ý TƯỞNG: Mỗi cụm phải thể hiện trọn vẹn MỘT khái niệm, một giải thuật, hoặc một chu trình logic hoàn chỉnh (ví dụ: giải thuật Bubble Sort giải thích nguyên lý, các bước so sánh đổi chỗ và độ phức tạp phải nằm chung một cụm; không được cắt đôi giải thuật sang cụm khác).
2. KHÔNG GIỚI HẠN CỨNG SỐ CÂU: Mỗi cụm có thể gồm 2-3 câu ngắn, hoặc 4-8 câu giải thích chi tiết, miễn là chúng cùng diễn giải 1 ý niệm sư phạm thống nhất.
3. PHỦ KÍN TOÀN BỘ 100% CHỈ SỐ: Tuyệt đối không được bỏ sót bất kỳ câu nào từ index 0 đến index {len(sentences) - 1}. Các mảng "sentence_indices" phải liên tục, không ngắt quãng và không trùng lặp.
4. XÁC ĐỊNH THUỘC TÍNH CHO MỖI CỤM:
   - "sentence_indices": Danh sách các số nguyên [start...end] liên tục thuộc về cụm này.
   - "title": Tiêu đề phân cảnh ngắn gọn, chuẩn sư phạm, viết HOA (từ 2 đến 5 từ, ví dụ "TỔNG QUAN BÀI GIẢNG", "GIẢI THUẬT BUBBLE SORT", "KIẾN TRÚC HIGH AVAILABILITY").
   - "visual_concept": 1 câu súc tích mô tả ý niệm trực quan cần vẽ (ví dụ "Mô phỏng dãy số so sánh từng cặp kề nhau và đổi chỗ", "Sơ đồ kiến trúc Load Balancer phát hiện Server lỗi và failover").
   - "diagram_type": Thể loại sơ đồ thích hợp nhất, chọn 1 trong: ["flowchart", "architecture", "comparison", "cycle", "timeline", "process_steps"].

Trả về DUY NHẤT một JSON array các object theo định dạng:
[
  {{
    "sentence_indices": [0, 1, 2],
    "title": "TIÊU ĐỀ KHỐI",
    "visual_concept": "Ý niệm mô phỏng trực quan...",
    "diagram_type": "architecture"
  }}
]"""

    try:
        if llm_caller:
            raw_resp = llm_caller(prompt)
        else:
            raw_resp = call_llm_api(
                prompt=prompt,
                api_key=api_key,
                model_name=model or "gemini-3.8-flash",
                base_url=base_url,
                response_mime_type="application/json",
            ) or ""
        raw_units = json.loads(clean_json_str(raw_resp))
        if not isinstance(raw_units, list) or not raw_units:
            raise ValueError("LLM không trả về mảng JSON hợp lệ")

        n_total = len(sentences)
        parsed_clusters = []
        for u in raw_units:
            if not isinstance(u, dict):
                continue
            idxs = u.get("sentence_indices", [])
            v_idxs = [int(x) for x in idxs if isinstance(x, (int, float)) and 0 <= int(x) < n_total]
            if v_idxs:
                parsed_clusters.append({
                    "indices": sorted(list(set(v_idxs))),
                    "title": str(u.get("title", "")).strip() or "BÀI GIẢNG",
                    "visual_concept": str(u.get("visual_concept", "")).strip(),
                    "diagram_type": str(u.get("diagram_type", "architecture")).strip(),
                })

        if not parsed_clusters:
            raise ValueError("Không có cụm nào chứa chỉ số câu hợp lệ")

        parsed_clusters.sort(key=lambda c: c["indices"][0])

        assigned = {}
        for c_idx, c in enumerate(parsed_clusters):
            for i in c["indices"]:
                if i not in assigned:
                    assigned[i] = c_idx

        curr_cluster = 0
        for i in range(n_total):
            if i in assigned:
                curr_cluster = assigned[i]
            else:
                assigned[i] = curr_cluster
                parsed_clusters[curr_cluster]["indices"].append(i)
                parsed_clusters[curr_cluster]["indices"].sort()

        groups = []
        metas = []
        for idx_c, c in enumerate(parsed_clusters):
            c_idxs = sorted(list(set(i for i in c["indices"] if assigned.get(i) == idx_c)))
            if c_idxs:
                g = [sentences[i] for i in c_idxs]
                groups.append(g)
                first_sent = g[0].get("text", "")
                metas.append({
                    "title": c["title"] if c["title"] and c["title"] != "BÀI GIẢNG" else extract_concise_title(first_sent),
                    "visual_concept": c["visual_concept"],
                    "diagram_type": c["diagram_type"],
                })

        if groups:
            emit_log("info", f"[Semantic Planner] LLM đã phân đoạn kịch bản thành {len(groups)} cụm tri thức trọn vẹn.")
            return groups, metas
    except Exception as e:
        emit_log("warn", f"[Semantic Planner] Phân cụm LLM thất bại ({e}), kích hoạt Fallback...")

    return _fallback()


def group_sentences(
    sentences: List[Dict[str, Any]],
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
    llm_caller: Optional[Any] = None,
) -> List[List[Dict[str, Any]]]:
    """Gom câu thành các Cụm Tri thức (Knowledge Units) theo ranh giới ngữ nghĩa tự nhiên.

    - Giữ nguyên 100% từng câu (tuyệt đối không ghép chuỗi/xóa câu) để bảo toàn đồng bộ âm thanh TTS & phụ đề ASS.
    - Ưu tiên LLM 1-Pass Semantic Chunking để bảo toàn toàn vẹn ngữ cảnh của từng khái niệm/thuật toán.
    - Fallback an toàn sang ranh giới đoạn văn (para_idx) hoặc heuristic khoảng lặng/ngữ pháp.
    """
    groups, metas = plan_semantic_knowledge_units(
        sentences=sentences,
        api_key=api_key,
        model=model,
        base_url=base_url,
        llm_caller=llm_caller,
    )
    for g, meta in zip(groups, metas):
        if g and isinstance(g[0], dict):
            g[0]["_group_meta"] = meta
    return groups


# ── Timeline theo thời lượng TTS ─────────────────────────────────────────────

def build_timeline(groups: List[List[Dict[str, Any]]], durations: List[float]) -> List[Dict[str, Any]]:
    """Gán mốc thời gian mới. `durations` là thời lượng TTS của từng câu, theo thứ tự phẳng.

    Mốc của câu k trong nhóm là nguồn thời gian duy nhất cho animation, giọng và subtitle.
    """
    timeline: List[Dict[str, Any]] = []
    t = 0.0
    n = 0
    for g in groups:
        step_starts: List[float] = []
        local = LEAD_IN
        sents = []
        for s in g:
            d = durations[n]
            audio_file = f"s_{n:04d}.mp3"
            step_starts.append(round(local, 3))
            sents.append({
                "index": n,
                "audio_file": audio_file,
                "text_orig": s["text_orig"],
                "text": s["text"],
                "text_secondary": s.get("text_secondary", s["text_orig"]),
                "duration": round(d, 3),
                "start": round(t + local, 3),
                "end": round(t + local + d, 3),
            })
            n += 1
            local += d + SENTENCE_GAP
        scene_duration = local - SENTENCE_GAP + TAIL
        timeline.append({
            "start": round(t, 3), "end": round(t + scene_duration, 3),
            "scene_duration": round(scene_duration, 3), "step_starts": step_starts, "sentences": sents,
        })
        t += scene_duration
    return timeline


# ── TTS ──────────────────────────────────────────────────────────────────────

def synthesize_sentences(sentences: List[Dict[str, Any]], config: LectureProjectConfig, workspace_dir: Path) -> List[float]:
    """Sinh TTS từng câu, trả thời lượng thật. Lưu file ở workspace/tts/s_XXXX.mp3 và đồng bộ .audio_manifest.json."""
    import threading
    from engine.shared.movie_review_tts import MovieReviewTTS
    from .common import (
        resolve_hardware_config,
        load_audio_manifest,
        save_audio_manifest,
        compute_sentence_audio_fingerprint,
    )

    tts_dir = workspace_dir / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)
    voice = config.tts_voice or "ban_mai"
    if (getattr(config, "target_lang", "vi") or "").lower().startswith("en"):
        if str(voice).lower().startswith("vi-") or str(voice).lower() in ("ban_mai", "hoai_my", "nam_minh", "vi"):
            voice = "en-US-JennyNeural"
    speed = float(config.tts_speed or 1.15)

    manifest = load_audio_manifest(tts_dir)
    manifest_lock = threading.Lock()

    def one(i: int) -> float:
        s = sentences[i]
        out_f = tts_dir / f"s_{i:04d}.mp3"
        audio_name = out_f.name
        text = str(s.get("text", "")).strip()
        sig_hash = compute_sentence_audio_fingerprint(text, voice, speed)

        # Kiểm tra cache hợp lệ theo text + voice + speed
        with manifest_lock:
            cached_entry = manifest.get(audio_name)
            cached_hash = cached_entry.get("hash") if isinstance(cached_entry, dict) else cached_entry
            cached_dur = float(cached_entry.get("duration", 0.0)) if isinstance(cached_entry, dict) else 0.0

        if out_f.exists() and out_f.stat().st_size >= 300 and cached_hash == sig_hash and cached_dur > 0.1:
            return cached_dur

        if s.get("skip_tts"):
            cmd = [
                "ffmpeg", "-y", "-loglevel", "error",
                "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                "-t", "2.0", "-q:a", "9", "-acodec", "libmp3lame", str(out_f)
            ]
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            dur = 2.0
        else:
            dur = MovieReviewTTS.synthesize_single(
                text=text, out_file=out_f,
                voice=voice, speed_factor=speed,
            )

        eff_dur = dur if dur > 0 else 1.5
        with manifest_lock:
            manifest[audio_name] = {
                "hash": sig_hash,
                "voice": voice,
                "speed": speed,
                "duration": round(eff_dur, 3),
            }
        return eff_dur

    workers, _, _ = resolve_hardware_config(config)

    with ThreadPoolExecutor(max_workers=max(2, workers)) as pool:
        durations = []
        for i, d in enumerate(pool.map(one, range(len(sentences)))):
            durations.append(d)
            emit_progress(0.40 + 0.25 * (i + 1) / max(1, len(sentences)), f"Đã tạo giọng đọc {i + 1}/{len(sentences)}...")

    save_audio_manifest(tts_dir, manifest)
    return durations


# ── Cơ chế Đánh Index Phân Loại Template (3-Tier Semantic Router) ──────────

TEMPLATE_KEYWORD_RULES = [
    # 1. Họ AI & Autonomous Agent
    ("agent_workflow", [
        r"\bagent\b", r"\btự trị\b", r"\bworkflow\b", r"\bchu trình\b", r"\bloop\b",
        r"\breasoning\b", r"\bsuy luận\b", r"\bhành động\b", r"\bquan sát\b", r"\btool\b",
        r"\bcông cụ\b", r"\bperception\b", r"\bdecision\b", r"\bmulti-agent\b", r"\bphản hồi\b"
    ]),
    ("rag_pipeline", [
        r"\brag\b", r"\bretrieval\b", r"\bvector\b", r"\bembedding\b", r"\btrích xuất\b",
        r"\btruy vấn\b", r"\bdatabase\b", r"\bkho tri thức\b", r"\bsemantic search\b",
        r"\bngữ nghĩa\b", r"\bchunk\b", r"\bcontext\b", r"\btop-k\b"
    ]),
    ("transformer_attention", [
        r"\btransformer\b", r"\battention\b", r"\btự chú ý\b", r"\bself-attention\b",
        r"\bquery\b", r"\bkey\b", r"\bvalue\b", r"\bqkv\b", r"\bsoftmax\b", r"\btoken\b",
        r"\btrọng số\b", r"\bhead\b", r"\bmulti-head\b"
    ]),
    ("neural_net", [
        r"\bnơ-ron\b", r"\bneuron\b", r"\bneural\b", r"\bhọc sâu\b", r"\bdeep learning\b",
        r"\bforward\b", r"\blan truyền\b", r"\bbackprop\b", r"\blớp ẩn\b", r"\bhidden layer\b",
        r"\btrọng số w\b", r"\bgradient\b"
    ]),

    # 2. Họ Coding & Hệ Thống
    ("algo_array", [
        r"\bmảng\b", r"\barray\b", r"\bcon trỏ\b", r"\bpointer\b", r"\btwo pointer\b",
        r"\bthuật toán\b", r"\bsắp xếp\b", r"\bsort\b", r"\bvòng lặp\b", r"\bduyệt\b",
        r"\bchỉ số\b", r"\bindex\b", r"\bbinary search\b", r"\bphần tử\b"
    ]),
    ("code_block", [
        r"\bcode\b", r"\bmã nguồn\b", r"\bcú pháp\b", r"\bsyntax\b", r"\bhàm\b",
        r"\bfunction\b", r"\blập trình\b", r"\bterminal\b", r"\blệnh\b", r"\bcommand\b",
        r"\bclass\b", r"\bvariable\b", r"\bconsole\b"
    ]),
    ("system_tree", [
        r"\bkiến trúc\b", r"\bhệ thống\b", r"\bcây\b", r"\btree\b", r"\bphân nhánh\b",
        r"\bapi\b", r"\bendpoint\b", r"\brest\b", r"\bmicroservice\b", r"\bmodule\b",
        r"\bphân cấp\b", r"\btradeoff\b"
    ]),
    ("network_route", [
        r"\bmạng\b", r"\bnetwork\b", r"\btín hiệu\b", r"\bđịa lý\b", r"\bkhoảng cách\b",
        r"\broute\b", r"\bđịnh tuyến\b", r"\bip\b", r"\bserver\b", r"\bclient\b",
        r"\bpacket\b", r"\bgói tin\b", r"\bcdn\b", r"\bradar\b"
    ]),
    ("architecture_stack", [
        r"\bngăn xếp\b", r"\btầng\b", r"\blayer\b", r"\bstack\b", r"\bđa tầng\b",
        r"\bosi\b", r"\bhạ tầng\b", r"\bphân tầng\b", r"\bkiến trúc tầng\b"
    ]),
    ("dialogue_flow", [
        r"\bhội thoại\b", r"\btương tác\b", r"\btrao đổi\b", r"\bgiao tiếp\b",
        r"\bhỏi đáp\b", r"\brequest\b", r"\bresponse\b", r"\bphản hồi\b"
    ]),

    # 3. Họ Phân Tích, Hình Thái Đa Năng & Đồ Thị
    ("compare_two", [
        r"\bso sánh\b", r"\bđối chiếu\b", r"\bkhác biệt\b", r"\bưu điểm\b", r"\bnhược điểm\b",
        r"\bvs\b", r"\btrái ngược\b", r"\bhơn kém\b", r"\bmặt khác\b", r"\bhaui lựa chọn\b"
    ]),
    ("process_flow", [
        r"\bquy trình\b", r"\btuần tự\b", r"\bbước 1\b", r"\bbước 2\b", r"\bgiai đoạn\b",
        r"\btrình tự\b", r"\bchuyển giao\b", r"\bflow\b"
    ]),
    ("cycle_loop", [
        r"\bchu trình\b", r"\bvòng lặp\b", r"\bloop\b", r"\bfeedback\b", r"\bpdca\b",
        r"\bvòng đời\b", r"\blặp đi lặp lại\b", r"\btuần hoàn\b", r"\blặp\b"
    ]),
    ("timeline_horizontal", [
        r"\bthời gian\b", r"\btiến trình\b", r"\blịch sử\b", r"\broadmap\b",
        r"\bmốc\b", r"\bnăm \d+\b", r"\btương lai\b", r"\bquá khứ\b", r"\blộ trình\b"
    ]),
    ("quadrant_matrix", [
        r"\bma trận\b", r"\b4 góc\b", r"\b2x2\b", r"\bgóc phần tư\b", r"\bưu tiên\b",
        r"\bkhẩn cấp\b", r"\bquan trọng\b", r"\bphân loại\b"
    ]),
    ("pyramid_hierarchy", [
        r"\bkim tự tháp\b", r"\btháp\b", r"\bpyramid\b", r"\bphân cấp\b", r"\bthứ bậc\b",
        r"\bmaslow\b", r"\btừ đáy lên đỉnh\b", r"\btháp nhu cầu\b"
    ]),
    ("dynamic_diagram", [
        r"\bsơ đồ\b", r"\bđồ thị\b", r"\btopology\b", r"\bquan hệ chéo\b", r"\bmermaid\b"
    ]),
    ("number_stat", [
        r"\bphần trăm\b", r"%", r"\bthống kê\b", r"\btỷ lệ\b", r"\btăng trưởng\b",
        r"\bgấp đôi\b", r"\btriệu\b", r"\btỷ\b", r"\bcon số\b"
    ]),
    ("example_simulation", [
        r"\bví dụ\b", r"\bchẳng hạn\b", r"\bgiả sử\b", r"\btình huống\b",
        r"\btrường hợp\b", r"\bcase study\b", r"\bthực tế như\b", r"\blấy ví dụ\b"
    ]),
    ("definition", [
        r"\bđịnh nghĩa\b", r"\bkhái niệm\b", r"\blà gì\b", r"\bđược hiểu là\b",
        r"\bthuật ngữ\b", r"\bcốt lõi\b"
    ]),
    ("title_point", [
        r"\btóm lại\b", r"\btổng kết\b", r"\blưu ý\b", r"\bquan trọng nhất\b",
        r"\bthông điệp\b", r"\bkết luận\b"
    ]),
]

TEMPLATE_FAMILIES = {
    "ai": ["agent_workflow", "rag_pipeline", "transformer_attention", "neural_net"],
    "code_sys": ["algo_array", "code_block", "system_tree", "network_route", "architecture_stack", "dialogue_flow"],
    "analysis": ["process_flow", "compare_two", "number_stat", "cycle_loop", "timeline_horizontal", "quadrant_matrix", "pyramid_hierarchy", "dynamic_diagram"],
    "narrative": ["bullet_list", "title_point", "definition", "example_simulation"],
}


def is_eligible_template(template_name: str, text: str, scene: Optional[Dict[str, Any]] = None) -> bool:
    """Hard Eligibility Guard: Kiểm tra điều kiện tiên quyết bắt buộc trước khi cho phép gán template."""
    lowered = text.lower()
    sc = scene or {}

    # 1. number_stat: BẮT BUỘC có số liệu thống kê hoặc %
    if template_name == "number_stat":
        stat = str(sc.get("stat") or "").strip()
        if stat and stat != "100%":
            return True
        return bool(re.search(r"(\d+([.,]\d+)?\s*(%|triệu|tỷ|nghìn tỷ|k|USD|\$))", text))

    # 2. compare_two: BẮT BUỘC có dấu hiệu so sánh/đối chiếu rõ rệt giữa 2 thực thể
    if template_name == "compare_two":
        has_comp = bool(re.search(r"\b(so sánh|đối chiếu|vs|khác biệt|truyền thống.*học máy|hai (phương pháp|lựa chọn|mặt|trường phái))\b", lowered))
        return has_comp

    # 3. timeline_horizontal: BẮT BUỘC có dòng thời gian, mốc năm hoặc roadmap
    if template_name == "timeline_horizontal":
        return bool(re.search(r"\b(năm \d{4}|lịch sử|tiến trình|lộ trình|quá khứ.*hiện tại|tương lai|giai đoạn)\b", lowered))

    # 4. code_block: BẮT BUỘC có cú pháp code hoặc terminal
    if template_name == "code_block":
        return bool(re.search(r"\b(def |import |class |console|function|terminal|lệnh|cú pháp|lập trình|viết mã)\b", lowered))

    # 5. process_flow: BẮT BUỘC có chuỗi tuần tự các bước
    if template_name == "process_flow":
        return bool(re.search(r"\b(bước 1|bước 2|quy trình|tuần tự|trình tự|các bước|flow)\b", lowered))

    # 6. example_simulation: Dành cho ví dụ thực tế / giả định có đối tượng tương tác
    if template_name == "example_simulation":
        return bool(re.search(r"\b(ví dụ|chẳng hạn|giả sử|tình huống|trường hợp|thực tế như|lấy ví dụ)\b", lowered))

    # 7. algo_array: BẮT BUỘC về mảng, con trỏ hoặc thuật toán mảng cụ thể (không phải bài giảng chung chung)
    if template_name == "algo_array":
        return bool(re.search(r"\b(mảng|array|con trỏ|pointer|two pointer|sắp xếp|sort|chỉ số|index|binary search)\b", lowered))

    # 8. agent_workflow: BẮT BUỘC về AI Agent tự trị, ReAct loop hoặc công cụ tools
    if template_name == "agent_workflow":
        return bool(re.search(r"\b(agent|tự trị|react loop|gọi tool|công cụ tool|quan sát.*suy luận|hành động.*phản hồi)\b", lowered))

    # Các template cơ bản/thuyết minh (bullet_list, title_point, definition) luôn an toàn
    return True


def extract_concise_title(text: str, default: str = "Bài giảng") -> str:
    """Rút trích tiêu đề ngắn gọn (Punchline Title, tối đa 6-8 từ) cho thẻ tiêu đề sketch."""
    if not text:
        return default
    # Cắt tại dấu phẩy, hai chấm, chấm phẩy hoặc dấu gạch đầu tiên
    clean = re.split(r"[,:;—–\n!?]", str(text))[0].strip()
    words = clean.split()
    if len(words) > 7:
        return " ".join(words[:7])
    return clean if clean else default


def classify_template_by_keywords(text: str) -> Optional[str]:
    """Tier 1: Đánh giá phân loại template dựa trên mật độ từ khóa kỹ thuật có kiểm tra tính hợp lệ."""
    lowered = text.lower()
    # Nếu câu mở đầu bằng dấu hiệu ví dụ/giả sử rõ rệt, ưu tiên tuyệt đối mô phỏng ví dụ
    if re.search(r"^\s*(ví dụ|chẳng hạn|giả sử|tình huống|trường hợp|xét ví dụ|lấy ví dụ)\b", lowered):
        return "example_simulation"

    best_template = None
    max_score = 0
    for template_name, patterns in TEMPLATE_KEYWORD_RULES:
        score = 0
        for pat in patterns:
            if re.search(pat, lowered):
                score += 1
        if score > max_score and is_eligible_template(template_name, text):
            max_score = score
            best_template = template_name
    return best_template if max_score > 0 else None


def apply_semantic_diversity_guard(scenes: List[Dict[str, Any]], groups_text: Optional[List[str]] = None) -> List[Dict[str, Any]]:
    """Tier 3: Giám sát đa dạng hóa bám sát ngữ nghĩa, lọc bỏ template không đủ điều kiện."""
    if groups_text is None:
        groups_text = ["" for _ in scenes]

    # Bước 1: Lọc bỏ các template bị gán nhầm không đủ điều kiện (Hard Eligibility Guard khi có text)
    for i, sc in enumerate(scenes):
        tmpl = sc.get("template", "bullet_list")
        txt = groups_text[i] if i < len(groups_text) else ""
        if txt and not is_eligible_template(tmpl, txt, sc):
            emit_log("info", f"Eligibility Guard: Cảnh {i + 1} gán '{tmpl}' nhưng nội dung không đủ điều kiện. Chuyển về 'bullet_list'.")
            sc["template"] = "bullet_list"

    # Bước 2: Chống lặp liên tiếp thông minh (chống lặp quá 2 batch liên tiếp hoặc lặp các template đơn nhất)
    for i in range(1, len(scenes)):
        t_curr = scenes[i].get("template")
        t_prev = scenes[i - 1].get("template")
        t_prev2 = scenes[i - 2].get("template") if i >= 2 else None
        txt = groups_text[i] if i < len(groups_text) else ""
        lowered = txt.lower()

        # Kích hoạt luân chuyển khi trùng 3 batch liên tiếp hoặc trùng 2 batch với template nặng/đặc biệt
        is_repetitive = False
        if i >= 2 and t_curr and t_curr == t_prev == t_prev2:
            is_repetitive = True
        elif t_curr and t_curr == t_prev and t_curr in ("timeline_horizontal", "pyramid_hierarchy", "quadrant_matrix", "compare_two"):
            is_repetitive = True

        if is_repetitive:
            if t_curr == "bullet_list":
                # Nếu là giải thích khái niệm cốt lõi -> chuyển sang definition
                if re.search(r"\b(định nghĩa|khái niệm|là gì|được hiểu là)\b", lowered):
                    scenes[i]["template"] = "definition"
                # Nếu câu ngắn, mang tính thông điệp/kết luận/chốt -> chuyển sang title_point
                elif len(scenes[i].get("steps", [])) <= 4 or re.search(r"\b(tóm lại|kết luận|thời điểm|lưu ý|quan trọng nhất|thông điệp)\b", lowered):
                    scenes[i]["template"] = "title_point"
                else:
                    scenes[i]["template"] = "title_point"
            elif t_curr == "timeline_horizontal":
                scenes[i]["template"] = "bullet_list"
            elif t_curr in ("title_point", "definition"):
                scenes[i]["template"] = "bullet_list"
            else:
                # Tìm họ gia đình của template hiện tại (ai, code_sys, analysis, narrative)
                target_family = None
                for fam_name, members in TEMPLATE_FAMILIES.items():
                    if t_curr in members:
                        target_family = members
                        break
                if target_family:
                    alternates = [m for m in target_family if m != t_curr]
                    valid_alts = [m for m in alternates if not txt or is_eligible_template(m, txt, scenes[i])]
                    chosen = valid_alts[(i) % len(valid_alts)] if valid_alts else alternates[(i) % len(alternates)]
                    scenes[i]["template"] = chosen
                else:
                    scenes[i]["template"] = "bullet_list"

    # Bước 3: Đảm bảo cảnh kết thúc (lời chào, chuyển video) luôn là title_point trang trọng
    if scenes and len(scenes) > 1:
        last_txt = groups_text[-1].lower() if groups_text else ""
        if any(w in last_txt for w in ("chuyển sang video", "video tiếp theo", "kết thúc", "cảm ơn", "bài tiếp theo")):
            scenes[-1]["template"] = "title_point"

    return scenes


# Alias tương thích ngược cho các unit test và module liên kết
apply_anti_repetition_guard = apply_semantic_diversity_guard


# ── Scene plan ───────────────────────────────────────────────────────────────

def plan_scenes(
    groups: List[List[Dict[str, Any]]],
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Tự động lập kế hoạch phân cảnh chuẩn AI-Native: mỗi cụm tri thức trở thành 1 cảnh authored độc lập."""
    scenes: List[Dict[str, Any]] = []
    for i, g in enumerate(groups):
        sentences = [s["text"] for s in g]
        first_sent = sentences[0] if sentences else "Bài giảng"
        meta = g[0].get("_group_meta", {}) if g and isinstance(g[0], dict) else {}
        title = meta.get("title") or extract_concise_title(first_sent)
        visual_concept = meta.get("visual_concept", "")
        diagram_type = meta.get("diagram_type", "architecture")

        scene_item = {
            "mode": "authored",
            "template": "authored",
            "title": title,
            "visual_concept": visual_concept,
            "diagram_type": diagram_type,
            "steps": [{"label": s.strip(), "icon": "bulb", "role": "VISUAL"} for s in sentences],
        }
        scenes.append(validate_scene(scene_item, sentences))

    return scenes

