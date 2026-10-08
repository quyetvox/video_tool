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


def split_sentences_natural(text: str) -> List[str]:
    """Tách đoạn văn thành các câu tự nhiên bằng quy tắc dấu câu."""
    # Thay thế các dấu ngắt dòng kép thành dấu ngắt đoạn
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    sentences: List[str] = []

    for para in paragraphs:
        # Gom các dòng đơn lẻ lại thành một đoạn liền mạch
        para_clean = " ".join([line.strip() for line in para.split("\n") if line.strip()])
        # Tách theo các dấu chấm câu: . ! ? hoặc dấu chấm câu tiếng Việt
        raw_splits = re.split(r"(?<=[.!?…])\s+", para_clean)
        for s in raw_splits:
            s_clean = s.strip()
            if not s_clean:
                continue
            # Nếu câu quá dài (> 220 ký tự), ngắt theo dấu phẩy / chấm phẩy
            if len(s_clean) > 220:
                sub_parts = re.split(r"(?<=[,;:])\s+", s_clean)
                cur_chunk = ""
                for part in sub_parts:
                    if len(cur_chunk) + len(part) < 180:
                        cur_chunk = f"{cur_chunk} {part}".strip()
                    else:
                        if cur_chunk:
                            sentences.append(cur_chunk)
                        cur_chunk = part
                if cur_chunk:
                    sentences.append(cur_chunk)
            else:
                sentences.append(s_clean)

    return sentences


def parse_markdown_blocks(content: str) -> List[Dict[str, Any]]:
    """
    Phân tích văn bản Markdown theo cấu trúc khối:
    - # Heading: gợi ý template title_point
    - - List: gợi ý template bullet_list
    - ``` Code: gợi ý template code_block
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
                results.append({
                    "text": f"Đoạn mã {lang or 'chương trình'}: {code_text[:80]}...",
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

        # 3. Khối Bullet list (- hoặc * hoặc 1.)
        bullet_match = re.match(r"^(\*|-|\+|\d+\.)\s+(.*)$", line)
        if bullet_match:
            bullet_text = bullet_match.group(2).strip()
            if bullet_text:
                results.append({
                    "text": bullet_text,
                    "type_hint": "bullet_list",
                })
            i += 1
            continue

        # 4. Khối đoạn văn bình thường (Paragraph)
        para_lines = [line]
        i += 1
        while i < total and lines[i].strip() and not lines[i].strip().startswith(("#", "-", "*", "```")):
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
        })
        fake_t += dur_est + 0.3

    emit_log("info", f"Trích xuất thành công {len(output)} câu bài giảng từ {file_path.name}.")
    return output
