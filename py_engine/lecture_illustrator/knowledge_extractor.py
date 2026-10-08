"""
Knowledge Extractor & Prompt Engine for AI Lecture Illustrator.
- Semantic Batching from Whisper ASR timestamps (10s - 30s)
- Contextual Translation & Pronoun Adaptation (Trang trọng / Sư phạm)
- Educational Intent Classification (PROCESS, DEFINITION, COMPARISON, etc.)
- 3-in-1 Prompt Pack Generation (AI Image No-text, Mermaid.js Code, Motion Concept)
"""

import json
import os
import re
import ssl
import urllib.request
import urllib.error
from typing import Any, Dict, List, Optional, Tuple

from .common import emit_log, emit_progress, clean_json_str
from .models import LectureBatch, BatchPrompts, LectureProjectConfig


EDUCATIONAL_INTENTS = [
    "DEFINITION",
    "CONCEPT",
    "PROCESS",
    "SEQUENCE",
    "COMPARISON",
    "STRUCTURE",
    "MECHANISM",
    "EXAMPLE",
    "FORMULA",
    "SUMMARY",
]


def group_transcript_into_semantic_batches(
    raw_segments: List[Dict[str, Any]],
    min_duration: float = 10.0,
    max_duration: float = 30.0,
) -> List[Dict[str, Any]]:
    """
    Nhóm các đoạn transcript câu ngắn từ Whisper thành các semantic batch (10s – 30s).
    Cắt batch tại điểm kết thúc câu (. ! ? ;).
    """
    if not raw_segments:
        return []

    batches = []
    current_texts = []
    current_start = raw_segments[0].get("start", 0.0)
    current_end = current_start
    batch_idx = 1

    for seg in raw_segments:
        text = str(seg.get("text", "")).strip()
        if not text:
            continue
        seg_start = float(seg.get("start", current_end))
        seg_end = float(seg.get("end", seg_start + 1.0))

        if not current_texts:
            current_start = seg_start

        current_texts.append(text)
        current_end = seg_end
        batch_duration = current_end - current_start

        # Kiểm tra điều kiện ngắt batch
        is_sentence_end = bool(re.search(r"[.!?…;]$", text))
        if (batch_duration >= min_duration and is_sentence_end) or (batch_duration >= max_duration):
            combined_text = " ".join(current_texts).strip()
            batches.append({
                "id": f"batch_{batch_idx:03d}",
                "start_sec": round(current_start, 3),
                "end_sec": round(current_end, 3),
                "transcript_original": combined_text,
            })
            batch_idx += 1
            current_texts = []
            current_start = current_end

    # Đoạn dôi dư cuối cùng nếu còn
    if current_texts:
        combined_text = " ".join(current_texts).strip()
        batches.append({
            "id": f"batch_{batch_idx:03d}",
            "start_sec": round(current_start, 3),
            "end_sec": round(current_end, 3),
            "transcript_original": combined_text,
        })

    return batches


def sanitize_english_prompt(text: str) -> str:
    """Loại bỏ triệt để các ký tự CJK (Trung, Nhật, Hàn) khỏi Prompt tiếng Anh."""
    if not text:
        return ""
    cleaned = re.sub(r'[\u4e00-\u9fff\u3400-\u4dbf\uf900-\ufaff\u3040-\u30ff\uac00-\ud7af]+', ' ', text)
    cleaned = re.sub(r'\s+', ' ', cleaned).strip()
    return cleaned


def translate_text_free(text: str, target_lang: str = "vi") -> str:
    """Dịch nhanh text qua Google Translate không cần API key (tương thích đa hạ tầng)."""
    if not text or not text.strip():
        return text
    try:
        import urllib.parse
        ctx = _get_ssl_context()
        # Strategy 1: clients5 dict API (Zero rate limit)
        try:
            url1 = f"https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl={target_lang}&q={urllib.parse.quote(text)}"
            req1 = urllib.request.Request(url1, headers={"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"})
            with urllib.request.urlopen(req1, context=ctx, timeout=6) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                if isinstance(data, list) and len(data) > 0:
                    if isinstance(data[0], list) and len(data[0]) > 0 and isinstance(data[0][0], str):
                        res = data[0][0].strip()
                        if res:
                            return res
                    elif isinstance(data[0], str) and data[0].strip():
                        return data[0].strip()
        except Exception:
            pass

        # Strategy 2: translate_a single API (GTX client)
        url2 = f"https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl={target_lang}&dt=t&q={urllib.parse.quote(text)}"
        req2 = urllib.request.Request(url2, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req2, context=ctx, timeout=6) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return "".join([part[0] for part in data[0] if part[0]]).strip()
    except Exception:
        return text


def build_educational_analysis_prompt(
    batches: List[Dict[str, Any]],
    target_lang: str = "vi",
    pronoun_mode: str = "formal",
) -> str:
    """Xây dựng prompt phân tích toàn diện cho LLM với ràng buộc ngôn ngữ nghiêm ngặt."""
    batch_json = json.dumps(batches, ensure_ascii=False, indent=2)

    pronoun_instruction = "Trang trọng, chuẩn mực sư phạm (Tôi - Các bạn / Quý vị)"
    if pronoun_mode == "teacher_student":
        pronoun_instruction = "Thân thiện, sư phạm lớp học (Thầy/Cô - Các em)"
    elif pronoun_mode == "casual":
        pronoun_instruction = "Gần gũi, chia sẻ (Mình - Các bạn)"

    prompt = f"""Bạn là Chuyên gia Thiết kế Trực quan Hóa Bài Giảng Giáo Dục (Educational Video Illustration Architect).
Dưới đây là danh sách các phân đoạn bài giảng (Batches) được trích xuất từ video:

{batch_json}

YÊU CẦU XỬ LÝ CHO TỪNG BATCH:
1. `transcript_translated`: Dịch nghĩa học thuật chính xác sang ngôn ngữ đích: '{target_lang}'.
   - Phong cách xưng hô: {pronoun_instruction}.
   - Giữ nguyên các thuật ngữ chuyên ngành chuẩn nếu cần thiết.
2. `educational_intent`: Chọn 1 trong các mục sau:
   [DEFINITION, CONCEPT, PROCESS, SEQUENCE, COMPARISON, STRUCTURE, MECHANISM, EXAMPLE, FORMULA, SUMMARY].
3. `visual_priority`: Đánh giá mức độ cần thiết phải minh họa:
   - "HIGH" (Khái niệm cốt lõi, quy trình, công thức bắt buộc phải có visual).
   - "MEDIUM" (Ý phụ, ví dụ minh họa).
   - "KEEP_ORIGINAL" (Lời chào, chuyển tiếp, giữ nguyên khung hình giảng viên).
4. `prompts` (Gói Prompt Đa Năng 4-trong-1):
   - `image_prompt`: BẮT BUỘC viết bằng TIẾNG ANH (ENGLISH).
     * Diễn đạt khái niệm khoa học bằng tiếng Anh tự nhiên (Midjourney/Flux/Imagen style).
     * TUYỆT ĐỐI KHÔNG chứa bất kỳ từ ngữ, chữ Hán hay ký tự nào của ngôn ngữ gốc.
     * QUY TẮC BẮT BUỘC: Luôn thêm đuôi ", clean educational illustration, scientific diagram, hyper-detailed, no text, no words, no letters, no watermark, 16:9".
   - `diagram_mermaid`: Mã nguồn sơ đồ Mermaid.js hợp lệ.
     * BẮT BUỘC: Toàn bộ nhãn các nút [Node] và liên kết -->|Label| BẮT BUỘC viết bằng ngôn ngữ đích '{target_lang}' (ví dụ: "graph TD; A[Bắt đầu] --> B[Xử lý];" hoặc "sequenceDiagram").
   - `animation_concept`: 1 câu mô tả chuyển động trực quan, BẮT BUỘC viết bằng ngôn ngữ đích '{target_lang}' (ví dụ: "Mô phỏng các phân tử nước di chuyển từ rễ lên thân lá").
   - `code_animation`: NẾU bài giảng chứa nội dung lập trình, thuật toán, cú pháp code (Python, JS, C++, SQL...), hãy sinh:
     * (1) Đoạn mã code/pseudo-code ngắn gọn, chuẩn cú pháp.
     * (2) Kịch bản diễn hoạt từng bước (Motion Cues) bằng ngôn ngữ đích '{target_lang}'.
     * NẾU KHÔNG PHẢI bài giảng lập trình, để trường này là chuỗi rỗng: "".

TRẢ VỀ DUY NHẤT 1 MẢNG JSON HỢP LỆ VỚI CẤU TRÚC SAU (KHÔNG KÈM GIẢI THÍCH):
[
  {{
    "id": "batch_001",
    "transcript_translated": "...",
    "educational_intent": "PROCESS",
    "visual_priority": "HIGH",
    "prompts": {{
      "image_prompt": "...",
      "diagram_mermaid": "graph TD; ...",
      "animation_concept": "...",
      "code_animation": "..."
    }}
  }}
]
"""
    return prompt


def _get_ssl_context() -> ssl.SSLContext:
    """Tạo SSL Context tương thích cao với macOS và môi trường thiếu root certs."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        pass
    try:
        return ssl._create_unverified_context()
    except Exception:
        pass
    return ssl.create_default_context()


def call_llm_api(
    prompt: str,
    api_key: Optional[str] = None,
    model_name: str = "gemini-2.5-flash",
    base_url: Optional[str] = None,
) -> Optional[str]:
    """Gọi LLM API qua REST (Hỗ trợ cả OpenAI-compatible endpoint, Ollama native REST và Google Gemini native REST)."""
    # 0. Làm sạch API key và lọc bỏ SSH key
    clean_key = (api_key or "").strip()
    if clean_key.startswith("ssh-") or "\n" in clean_key:
        emit_log("warn", f"Khóa API cấu hình là SSH key thay vì API token: '{clean_key[:20]}...'. Đã bỏ qua key.")
        clean_key = ""

    if not clean_key and not base_url:
        return None

    ctx = _get_ssl_context()

    # 1. Nếu có base_url (Ollama, OpenAI, Groq, DeepSeek, v.v.)
    if base_url:
        b = str(base_url).strip().rstrip("/")
        if b.endswith("/chat/completions"):
            url = b
        elif b.endswith("/v1"):
            url = f"{b}/chat/completions"
        elif "11434" in b or "ollama" in b or "localhost" in b:
            url = f"{b}/v1/chat/completions"
        else:
            url = f"{b}/chat/completions"

        headers = {"Content-Type": "application/json"}
        if clean_key and " " not in clean_key:
            headers["Authorization"] = f"Bearer {clean_key}"

        payload = {
            "model": model_name or "gemma4:31b-cloud",
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0.2,
        }
        try:
            req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST")
            with urllib.request.urlopen(req, timeout=60, context=ctx) as response:
                res_data = json.loads(response.read().decode("utf-8"))
                choices = res_data.get("choices", [])
                if choices:
                    return choices[0].get("message", {}).get("content", "")
        except Exception as e:
            # Nếu là Ollama endpoint, thử fallback sang Ollama native /api/generate
            if "11434" in b or "ollama" in b or "localhost" in b:
                try:
                    native_url = f"{b}/api/generate"
                    native_payload = {
                        "model": model_name or "gemma4:31b-cloud",
                        "prompt": prompt,
                        "stream": False,
                    }
                    if "json" in prompt.lower():
                        native_payload["format"] = "json"
                    req_nat = urllib.request.Request(
                        native_url,
                        data=json.dumps(native_payload).encode("utf-8"),
                        headers={"Content-Type": "application/json"},
                        method="POST",
                    )
                    with urllib.request.urlopen(req_nat, timeout=60, context=ctx) as response_nat:
                        res_data_nat = json.loads(response_nat.read().decode("utf-8"))
                        if "response" in res_data_nat and res_data_nat["response"]:
                            return res_data_nat["response"]
                except Exception as e_nat:
                    emit_log("warn", f"Gọi Ollama native /api/generate thất bại ({e_nat}).")

            emit_log("warn", f"Gọi endpoint OpenAI/Ollama thất bại ({e}). Thử fallback...")

    # 2. Native Google Gemini REST Endpoint v1beta (Chỉ gọi khi có API key hợp lệ của Google, không chứa khoảng trắng)
    if clean_key and " " not in clean_key and not clean_key.startswith("sk-") and (not base_url or "generativelanguage" in str(base_url) or "gemini" in str(model_name)):
        model = model_name if ("gemini" in str(model_name) and "lite" not in str(model_name)) else "gemini-2.5-flash"
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={clean_key}"
        headers = {"Content-Type": "application/json"}
        payload = {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {
                "temperature": 0.2,
                "responseMimeType": "application/json",
            },
        }

        try:
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode("utf-8"),
                headers=headers,
                method="POST",
            )
            try:
                with urllib.request.urlopen(req, timeout=60, context=ctx) as response:
                    res_data = json.loads(response.read().decode("utf-8"))
            except (ssl.SSLError, urllib.error.URLError) as ssl_err:
                if "CERTIFICATE_VERIFY_FAILED" in str(ssl_err) or isinstance(ssl_err, ssl.SSLError):
                    unverified_ctx = ssl._create_unverified_context()
                    with urllib.request.urlopen(req, timeout=60, context=unverified_ctx) as response:
                        res_data = json.loads(response.read().decode("utf-8"))
                else:
                    raise ssl_err

            candidates = res_data.get("candidates", [])
            if candidates:
                parts = candidates[0].get("content", {}).get("parts", [])
                if parts:
                    return parts[0].get("text", "")
        except Exception as e:
            emit_log("warn", f"Gọi Gemini API thất bại ({e}). Đang kích hoạt chuyển ngữ dự phòng.")
            return None

    return None


def generate_fallback_prompts_for_batch(batch: Dict[str, Any], target_lang: str = "vi") -> Dict[str, Any]:
    """Tạo gói prompt dự phòng song ngữ an toàn: Dịch kịch bản/Mermaid/Motion sang target_lang và Image Prompt sang Tiếng Anh sạch."""
    orig_text = batch.get("transcript_original", "")
    low_text = orig_text.lower()

    # Dịch nghĩa sang ngôn ngữ đích (target_lang)
    translated_text = translate_text_free(orig_text, target_lang)
    if not translated_text or not translated_text.strip():
        translated_text = orig_text

    # Dịch khái niệm sang Tiếng Anh để làm cơ sở cho Image Prompt
    en_concept = translate_text_free(orig_text, "en")
    clean_en_concept = sanitize_english_prompt(en_concept)
    if not clean_en_concept:
        clean_en_concept = "core scientific concept and process"

    # Nhận diện bài giảng lập trình/thuật toán thông minh
    code_keywords = [
        "code", "function", "def ", "class ", "return", "import", "const ", "let ",
        "var ", "loop", "vòng lặp", "thuật toán", "cú pháp", "lập trình", "mảng",
        "array", "string", "int ", "bool", "if ", "else", "lambda", "async", "await",
    ]
    is_coding = any(k in low_text for k in code_keywords)

    code_anim = ""
    if is_coding:
        clean_name = re.sub(r"[^a-zA-Z0-9_]", "", clean_en_concept[:20]).strip() or "processData"
        code_anim = (
            f"// Code minh họa logic bài giảng:\n"
            f"function {clean_name}() {{\n"
            f"    // Khởi tạo và xử lý: {translated_text[:40]}...\n"
            f"    const result = executeStep();\n"
            f"    return result;\n"
            f"}}\n\n"
            f"[Animation Execution Cues]:\n"
            f"- 0.0s - 2.5s: Hiệu ứng gõ phím (typing) khai báo hàm và tham số.\n"
            f"- 2.5s - 5.5s: Highlight dòng executeStep() đồng bộ với lời giảng viên.\n"
            f"- 5.5s - end: Đổi màu dòng return thành màu xanh lá (chỉ thị hoàn tất)."
        )

    # Làm sạch nhãn nút cho sơ đồ Mermaid (bằng ngôn ngữ đích)
    clean_label = re.sub(r'[\[\]\(\)\"\'\{\};]', ' ', translated_text[:35]).strip() or "Nội dung phân đoạn"
    anim_text = f"Thu phóng và làm nổi bật: {translated_text[:60]}" if target_lang == "vi" else f"Zoom in and highlight: {translated_text[:60]}"

    return {
        "transcript_translated": translated_text,
        "educational_intent": "CONCEPT",
        "visual_priority": "HIGH",
        "prompts": {
            "image_prompt": f"Educational scientific illustration explaining {clean_en_concept[:90]}, clean educational illustration, scientific diagram, hyper-detailed, no text, no words, no letters, no watermark, 16:9",
            "diagram_mermaid": f"graph TD;\n  A[Khái niệm chính] --> B[{clean_label}];",
            "animation_concept": anim_text,
            "code_animation": code_anim,
        },
    }


def extract_lecture_knowledge(
    raw_segments: List[Dict[str, Any]],
    config: LectureProjectConfig,
    api_key: Optional[str] = None,
    ai_model: Optional[str] = None,
    base_url: Optional[str] = None,
) -> List[LectureBatch]:
    """
    Thực hiện trọn vẹn quy trình phân tích bài giảng:
    ASR Segments -> Semantic Batches -> LLM Intent & Prompt Pack -> LectureBatch models.
    """
    emit_progress(0.20, "Đang nhóm phân đoạn ngữ nghĩa bài giảng (Semantic Batches)...")
    raw_batches = group_transcript_into_semantic_batches(raw_segments)
    emit_log("info", f"Đã chia bài giảng thành {len(raw_batches)} phân đoạn ngữ nghĩa.")

    if not raw_batches:
        return []

    analyzed_map: Dict[str, Dict[str, Any]] = {}
    effective_key = api_key or os.environ.get("GEMINI_API_KEY", "")
    effective_model = ai_model or os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
    target_lang = config.target_lang or "vi"

    if effective_key or base_url:
        emit_progress(0.40, f"Đang gửi phân đoạn lên AI ({effective_model}) phân tích tri thức & tạo Prompt Pack...")
        prompt = build_educational_analysis_prompt(
            raw_batches,
            target_lang=target_lang,
            pronoun_mode=config.pronoun_mode,
        )
        llm_response = call_llm_api(prompt, effective_key, effective_model, base_url=base_url)
        if llm_response:
            try:
                cleaned = clean_json_str(llm_response)
                parsed = json.loads(cleaned)
                if isinstance(parsed, list):
                    for item in parsed:
                        b_id = item.get("id")
                        if b_id:
                            analyzed_map[b_id] = item
                    emit_log("info", f"AI đã phân tích thành công {len(analyzed_map)} phân đoạn bài giảng.")
            except Exception as e:
                emit_log("warn", f"Lỗi phân giải JSON từ AI ({e}). Áp dụng chuyển ngữ dự phòng chuẩn hóa.")

    # Ghép dữ liệu thành LectureBatch objects
    final_batches: List[LectureBatch] = []
    for rb in raw_batches:
        b_id = rb["id"]
        ai_data = analyzed_map.get(b_id)
        if not ai_data:
            ai_data = generate_fallback_prompts_for_batch(rb, target_lang=target_lang)

        prompts_dict = ai_data.get("prompts") or {}
        raw_img_prompt = prompts_dict.get("image_prompt", "")
        # Lọc sạch triệt để mọi ký tự CJK còn sót trong Prompt tiếng Anh
        clean_img_prompt = sanitize_english_prompt(raw_img_prompt)
        if not clean_img_prompt:
            clean_img_prompt = "Educational scientific illustration, clean educational illustration, scientific diagram, hyper-detailed, no text, no words, no letters, no watermark, 16:9"

        batch_obj = LectureBatch(
            id=b_id,
            start_sec=rb["start_sec"],
            end_sec=rb["end_sec"],
            transcript_original=rb["transcript_original"],
            transcript_translated=ai_data.get("transcript_translated") or rb["transcript_original"],
            educational_intent=ai_data.get("educational_intent", "CONCEPT"),
            visual_priority=ai_data.get("visual_priority", "HIGH"),
            prompts=BatchPrompts(
                image_prompt=clean_img_prompt,
                diagram_mermaid=prompts_dict.get("diagram_mermaid", ""),
                animation_concept=prompts_dict.get("animation_concept", ""),
                code_animation=prompts_dict.get("code_animation", ""),
            ),
        )
        final_batches.append(batch_obj)

    emit_progress(0.60, f"Hoàn tất phân tích {len(final_batches)} thẻ kịch bản bài giảng.")
    return final_batches

