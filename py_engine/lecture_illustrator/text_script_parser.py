"""
Text Script Parser for AI Lecture Illustrator.
Bộ trích xuất và phân tách nội dung văn bản (Plain Text .txt, Markdown .md) thành các câu bài giảng.
- Đọc an toàn đa nền tảng UTF-8 / UTF-8-SIG / CP1258 / Latin-1.
- Tự động nhận diện cấu trúc Markdown (# Heading, - List, ``` Code) để gán type_hint cho template.
- Tách câu tự nhiên và hỗ trợ LLM tối ưu tài liệu thô thành kịch bản thuyết trình bài giảng.
"""

import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from .common import clean_json_str, emit_log
from .knowledge_extractor import call_llm_api
from .models import LectureProjectConfig


def read_text_file_safe(file_path: Path) -> str:
    """Đọc tệp văn bản an toàn với nhiều bộ mã ký tự trên Windows & macOS."""
    encodings = ["utf-8", "utf-8-sig", "utf-16", "cp1258", "latin-1"]
    raw_bytes = file_path.read_bytes()
    for enc in encodings:
        try:
            text = raw_bytes.decode(enc)
            # Chuẩn hóa ngắt dòng CRLF -> LF
            return text.replace("\r\n", "\n").replace("\r", "\n").strip()
        except UnicodeDecodeError:
            continue
    # Fallback cuối cùng
    return raw_bytes.decode("utf-8", errors="replace").strip()


COMMON_ABBREVIATIONS: List[str] = [
    r"\bv\.v\.",
    r"\be\.g\.",
    r"\bi\.e\.",
    r"\btp\.",
    r"\bts\.",
    r"\bths\.",
    r"\bgs\.",
    r"\bdr\.",
    r"\bmr\.",
    r"\bmrs\.",
    r"\bms\.",
    r"\bvs\.",
    r"\bapprox\.",
]


def shield_text_dots(text: str) -> str:
    """Tạm thời bảo vệ dấu chấm không phải kết thúc câu (số thập phân, đuôi file công nghệ, từ viết tắt)."""
    # 1. Số thập phân: 3.14, 1.0, 99.99
    text = re.sub(r"(\d+)\.(\d+)", r"\1__NUM_DOT__\2", text)
    # 2. Tên file / thư viện công nghệ: node.js, vue.js, app.py
    text = re.sub(r"\b([A-Za-z0-9_-]+)\.(js|ts|py|cpp|html|css|json|md)\b", r"\1__EXT_DOT__\2", text, flags=re.IGNORECASE)
    # 3. Viết tắt thông dụng
    for pattern in COMMON_ABBREVIATIONS:
        def _replace_abbr(m: re.Match) -> str:
            return m.group(0).replace(".", "__ABBR_DOT__")
        text = re.sub(pattern, _replace_abbr, text, flags=re.IGNORECASE)
    return text


def deshield_text_dots(text: str) -> str:
    """Khôi phục lại các dấu chấm đã được bảo vệ về nguyên bản."""
    return text.replace("__NUM_DOT__", ".").replace("__EXT_DOT__", ".").replace("__ABBR_DOT__", ".")


def split_sentences_natural(text: str) -> List[str]:
    """Tách đoạn văn thành các câu tự nhiên bằng quy tắc dấu câu kết thúc (. ! ? …).

    - Tuyệt đối không băm nhỏ câu theo dấu phẩy, chấm phẩy hay hai chấm.
    - Bảo vệ số thập phân, tên thư viện công nghệ và từ viết tắt thông dụng.
    """
    if not text or not text.strip():
        return []

    # Thay thế các dấu ngắt dòng kép thành dấu ngắt đoạn
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    sentences: List[str] = []

    for para in paragraphs:
        # Gom các dòng đơn lẻ lại thành một đoạn liền mạch
        para_clean = " ".join([line.strip() for line in para.split("\n") if line.strip()])
        if not para_clean:
            continue

        shielded = shield_text_dots(para_clean)
        # Tách theo các dấu chấm câu: . ! ? … có thể kèm dấu ngoặc kép / ngoặc đơn đóng
        raw_splits = re.split(r'(?<=[.!?…])\s+|(?<=[.!?…][”"\'\)\]])\s+', shielded)
        for s in raw_splits:
            s_clean = deshield_text_dots(s).strip()
            if s_clean:
                sentences.append(s_clean)

    return sentences


LANG_SPEECH_MAP: Dict[str, str] = {
    "cpp": "C++", "c++": "C++",
    "python": "Python", "py": "Python",
    "javascript": "JavaScript", "js": "JavaScript",
    "typescript": "TypeScript", "ts": "TypeScript",
    "java": "Java",
    "c": "C", "c#": "C Sharp", "csharp": "C Sharp",
    "html": "HTML", "css": "CSS", "sql": "SQL",
    "text": "mã giả", "pseudocode": "mã giả",
}


def parse_markdown_blocks(content: str) -> List[Dict[str, Any]]:
    """
    Phân tích văn bản Markdown theo cấu trúc khối:
    - # Heading: gợi ý template title_point
    - - List: gợi ý template bullet_list (tự động khâu với câu trước nếu câu trước kết thúc bằng dấu hai chấm ':')
    - ``` Code: gợi ý template code_block, sinh câu dẫn dắt tự nhiên thay vì đọc mã nguồn
    - ![alt](url) / URL thuần: gắn cờ skip_tts để không đọc ký tự web thô
    - Khối văn bản thông thường: tách thành các câu tự nhiên.
    """
    lines = content.split("\n")
    results: List[Dict[str, Any]] = []
    i = 0
    total = len(lines)

    while i < total:
        line = lines[i].strip()
        if not line:
            i += 1
            continue

        # 1. Khối Code block (```)
        if line.startswith("```"):
            lang = line.replace("```", "").strip()
            code_lines = []
            i += 1
            while i < total and not lines[i].strip().startswith("```"):
                code_lines.append(lines[i])
                i += 1
            i += 1  # bỏ qua dòng đóng ```
            code_text = "\n".join(code_lines).strip()
            if code_text:
                human_lang = LANG_SPEECH_MAP.get(lang.lower(), "")
                if human_lang:
                    speech_intro = f"Dưới đây là đoạn mã minh họa cài đặt bằng {human_lang}."
                else:
                    speech_intro = "Dưới đây là đoạn mã minh họa cài đặt thuật toán."
                results.append({
                    "text": speech_intro,
                    "code_content": code_text,
                    "type_hint": "code_block",
                    "title_hint": f"Minh Họa Mã Nguồn {lang.upper() if lang else ''}".strip(),
                })
            continue

        # 2. Khối Heading (#)
        heading_match = re.match(r"^(#{1,6})\s+(.*)$", line)
        if heading_match:
            heading_text = heading_match.group(2).strip()
            if heading_text:
                results.append({
                    "text": heading_text,
                    "type_hint": "title_point",
                    "title_hint": heading_text,
                })
            i += 1
            continue

        # 3. Khối hình ảnh Markdown (![alt](url)) hoặc URL thuần
        img_match = re.match(r"^!\[(.*?)\]\((https?://[^\)]+)\)$", line)
        url_match = re.match(r"^https?://\S+$", line)
        if img_match or url_match:
            alt_txt = img_match.group(1).strip() if img_match else ""
            img_url = img_match.group(2).strip() if img_match else line
            results.append({
                "text": alt_txt or "Hình ảnh minh họa",
                "media_url": img_url,
                "type_hint": "visual_media",
                "title_hint": alt_txt or "Hình ảnh minh họa",
                "skip_tts": True,
            })
            i += 1
            continue

        # 4. Khối Bullet list (- hoặc * hoặc + hoặc 1.)
        bullet_match = re.match(r"^(\*|-|\+|\d+\.)\s+(.*)$", line)
        if bullet_match:
            bullet_text = bullet_match.group(2).strip()
            if bullet_text:
                # Nếu câu trước kết thúc bằng dấu hai chấm ':', khâu câu dẫn dắt với bullet đầu tiên
                if results and str(results[-1].get("text", "")).strip().endswith(":"):
                    p_text = str(results[-1]["text"]).strip()
                    results[-1]["text"] = f"{p_text} {bullet_text}".strip()
                else:
                    results.append({
                        "text": bullet_text,
                        "type_hint": "bullet_list",
                    })
            i += 1
            continue

        # 5. Khối đoạn văn bình thường (Paragraph)
        para_lines = [line]
        i += 1
        while i < total and lines[i].strip() and not lines[i].strip().startswith(("#", "-", "*", "+", "```", "![")):
            if re.match(r"^https?://\S+$", lines[i].strip()):
                break
            para_lines.append(lines[i].strip())
            i += 1

        para_full = " ".join(para_lines).strip()
        for sent in split_sentences_natural(para_full):
            if sent:
                results.append({
                    "text": sent,
                    "type_hint": "auto",
                })

    return results


def refine_raw_article_with_llm(
    text: str,
    api_key: str,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
    target_lang: str = "vi",
) -> List[str]:
    """Sử dụng LLM để tóm tắt và biên soạn tài liệu/bài viết thô thành kịch bản bài giảng gồm các câu ngắn."""
    prompt = (
        f"Bạn là chuyên gia sư phạm và biên kịch bài giảng. Dưới đây là nội dung tài liệu/bài viết:\n\n"
        f"--- NỘI DUNG TÀI LIỆU ---\n{text[:6000]}\n--------------------\n\n"
        f"Hãy chuyển thể nội dung trên thành kịch bản thuyết trình bài giảng (bằng tiếng {target_lang}) "
        f"ngắn gọn, trực quan, dễ hiểu. Từng câu như một lời giảng truyền cảm hứng (mỗi câu từ 12-25 từ).\n"
        f"Trả về DUY NHẤT một JSON array chứa danh sách các chuỗi câu theo thứ tự thuyết minh, ví dụ:\n"
        f'["Chào mừng các bạn đến với bài học hôm nay.", "Khái niệm đầu tiên chúng ta cần nắm là kiến trúc hướng sự kiện.", ...]'
    )
    try:
        raw_resp = call_llm_api(prompt, api_key, model or "gemini-2.5-flash", base_url) or ""
        import json
        parsed = json.loads(clean_json_str(raw_resp))
        if isinstance(parsed, list) and len(parsed) >= 2:
            return [str(s).strip() for s in parsed if str(s).strip()]
    except Exception as e:
        emit_log("warn", f"LLM biên soạn kịch bản từ tài liệu thất bại ({e}), dùng bộ tách câu tự nhiên.")
    return split_sentences_natural(text)


def parse_text_file_to_sentences(
    file_path: Path,
    config: LectureProjectConfig,
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
    is_raw_article: bool = False,
) -> List[Dict[str, Any]]:
    """
    Hàm chính: Nạp tệp .txt / .md và xuất ra danh sách câu chuẩn hóa cho timeline Lecture Illustrator.
    Mỗi phần tử có:
    - index: int
    - text_orig: str
    - text: str (ngôn ngữ đích)
    - text_secondary: str (ngôn ngữ phụ)
    - type_hint: str (gợi ý template)
    - start, end: float (mốc giả định, sẽ được cập nhật lại theo thời lượng thật của TTS)
    """
    raw_content = read_text_file_safe(file_path)
    if not raw_content:
        emit_log("error", f"Tệp văn bản rỗng: {file_path.name}")
        return []

    ext = file_path.suffix.lower()
    raw_sentences: List[Dict[str, Any]] = []

    if is_raw_article and (api_key or base_url):
        emit_log("info", f"Kích hoạt AI biên soạn bài giảng từ tài liệu thô: {file_path.name}")
        refined_texts = refine_raw_article_with_llm(
            text=raw_content,
            api_key=api_key,
            model=model,
            base_url=base_url,
            target_lang=config.target_lang or "vi",
        )
        for s in refined_texts:
            raw_sentences.append({"text": s, "type_hint": "auto"})
    elif ext in [".md", ".markdown"]:
        emit_log("info", f"Phân tích cấu trúc Markdown: {file_path.name}")
        raw_sentences = parse_markdown_blocks(raw_content)
    else:
        emit_log("info", f"Phân tách câu kịch bản văn bản: {file_path.name}")
        for s in split_sentences_natural(raw_content):
            raw_sentences.append({"text": s, "type_hint": "auto"})

    # Chuẩn hóa về danh sách câu với cấu trúc tương đương Whisper transcript
    output: List[Dict[str, Any]] = []
    fake_t = 0.0
    for idx, item in enumerate(raw_sentences):
        text_str = str(item.get("text", "")).strip()
        if not text_str:
            continue
        # Ước tính thời lượng sơ bộ 3s/câu trước khi đo bằng TTS
        dur_est = max(1.5, len(text_str.split()) * 0.35)
        output.append({
            "index": idx,
            "start": round(fake_t, 3),
            "end": round(fake_t + dur_est, 3),
            "text_orig": text_str,
            "text": text_str,
            "text_secondary": text_str,
            "type_hint": item.get("type_hint", "auto"),
            "title_hint": item.get("title_hint"),
            "code_content": item.get("code_content"),
            "skip_tts": bool(item.get("skip_tts", False)),
            "media_url": item.get("media_url"),
        })
        fake_t += dur_est + 0.3

    # Tự động khâu nối các câu/mảnh câu bị cắt ngang dở dang (kết thúc bằng dấu phẩy, liên từ hoặc vế sau viết thường)
    try:
        from .scene_planner import stitch_sentence_boundaries
        output = stitch_sentence_boundaries(output)
        for idx, item in enumerate(output):
            item["index"] = idx
    except Exception as e:
        emit_log("warn", f"Lỗi khâu nối câu dở dang: {e}")

    # Tự động dịch ngôn ngữ phụ sang secondary_lang nếu bật chế độ song ngữ
    try:
        from .scene_planner import translate_secondary_subtitles
        output = translate_secondary_subtitles(
            sentences=output,
            config=config,
            api_key=api_key,
            model=model,
            base_url=base_url,
        )
    except Exception as e:
        emit_log("warn", f"Lỗi dịch tự động phụ đề phụ: {e}")

    emit_log("info", f"Trích xuất thành công {len(output)} câu bài giảng từ {file_path.name}.")
    return output

