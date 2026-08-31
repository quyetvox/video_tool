import os
import json
import logging
from pathlib import Path
from typing import Any, Dict, List, Tuple
import requests

from plugins.interfaces import TranslatorBase

logger = logging.getLogger("sub_video")


def _normalize_model_and_endpoint(model: str, base_url: str) -> Tuple[str, str]:
    """Normalize endpoint and auto-upgrade deprecated model names to prevent 404 errors."""
    b = str(base_url).strip().rstrip('/')
    endpoint = b if b.endswith("/chat/completions") else f"{b}/chat/completions"
    m = str(model).strip()

    # Auto-upgrade deprecated Google Gemini models to latest gemini-3.1-flash-lite
    if "generativelanguage.googleapis.com" in b:
        if m in ("gemini-2.0-flash", "gemini-1.5-flash", "gemini-pro", "gemini-1.0-pro", "gpt-4o-mini"):
            m = "gemini-3.1-flash-lite"

    return m, endpoint


class Plugin(TranslatorBase):
    def _extract_fast_context(
        self,
        sample_text: str,
        endpoint: str,
        model: str,
        headers: Dict[str, str],
        target_lang: str = "vi"
    ) -> Dict[str, Any]:
        prompt = (
            f"Analyze this video dialogue transcript sample:\n"
            f"\"\"\"\n{sample_text}\n\"\"\"\n\n"
            f"Extract key context in JSON format with strictly these keys:\n"
            f"- \"genre\": Content genre (e.g. 'phim_ngắn', 'drama', 'hài_hước', 'gia_đình', 'tình_cảm', 'ẩm_thực', 'vlog', 'tài_liệu')\n"
            f"- \"characters\": List of detected characters/roles (e.g. ['Mẹ', 'Con trai', 'Bố', 'Hàng xóm'])\n"
            f"- \"context\": Short 1-sentence background summary in {target_lang} describing the scenario\n"
            f"- \"title\": Engaging video title in {target_lang} (under 60 chars)\n"
            f"- \"description\": 1-2 sentence video description in {target_lang}\n"
            f"- \"tags\": list of 4-6 trending hashtags in {target_lang} (without # symbol)\n"
            f"Return ONLY valid JSON."
        )
        try:
            body = {
                "model": model,
                "messages": [
                    {"role": "system", "content": "You are an expert film context & pronoun analyzer. Output strictly valid JSON."},
                    {"role": "user", "content": prompt}
                ],
                "temperature": 0.2
            }
            resp = requests.post(endpoint, headers=headers, json=body, timeout=20)
            resp.raise_for_status()
            res_txt = resp.json()["choices"][0]["message"]["content"].strip()
            if res_txt.startswith("```"):
                res_txt = res_txt.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
            return json.loads(res_txt)
        except Exception:
            return {}

    def translate_segments(self, segments: List[Dict[str, Any]], target_lang: str, secondary_lang: str = "") -> List[Dict[str, Any]]:
        if not segments:
            return []

        import re
        zh_pattern = re.compile(r'[\u4e00-\u9fff]')
        is_bilingual = bool(secondary_lang and secondary_lang.strip() and secondary_lang.strip().lower() != target_lang.strip().lower())

        t_cfg = self.config.get("translator")
        if isinstance(t_cfg, dict):
            p_type = str(t_cfg.get("type", "openai")).lower()
            default_base_url = "https://api.groq.com/openai/v1" if p_type == "groq" else "https://api.deepseek.com/v1" if p_type == "deepseek" else "https://generativelanguage.googleapis.com/v1beta/openai" if p_type == "gemini" else "https://api.openai.com/v1"
            api_key = (
                t_cfg.get("api_key")
                or self.config.get("openai_api_key")
                or os.environ.get("OPENAI_API_KEY")
                or os.environ.get("GROQ_API_KEY")
                or os.environ.get("GEMINI_API_KEY")
                or os.environ.get("DEEPSEEK_API_KEY")
            )
            base_url = t_cfg.get("base_url") or self.config.get("openai_base_url") or os.environ.get("OPENAI_BASE_URL", default_base_url)
            model = t_cfg.get("model") or self.config.get("translator_model", "gpt-4o-mini")
            batch_size = t_cfg.get("batch_size") or self.config.get("translator_batch_size", 20)
        else:
            api_key = (
                self.config.get("api_key")
                or self.config.get("openai_api_key")
                or os.environ.get("OPENAI_API_KEY")
            )
            base_url = self.config.get("openai_base_url") or os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")
            model = self.config.get("translator_model", "gpt-4o-mini")
            batch_size = self.config.get("translator_batch_size", 20)

        model, endpoint = _normalize_model_and_endpoint(model, base_url)
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}"
        }

        # ── Pass 1: Scenario & Character Extraction ───────────────────────────
        global_context = ""
        self.last_extracted_meta = {}
        if len(segments) > 3:
            sample_lines = []
            for s in segments[:18]:
                txt = s.get("text", "").strip()
                if txt:
                    spk = s.get("speaker")
                    line_repr = f"[{spk}]: {txt}" if spk else txt
                    sample_lines.append(line_repr)
            sample_text = "\n".join(sample_lines)
            if sample_text.strip():
                extracted = self._extract_fast_context(sample_text, endpoint, model, headers, target_lang)
                if isinstance(extracted, dict):
                    global_context = extracted.get("context", "")
                    self.last_extracted_meta = extracted
                    print(f"[s08_translation] Scenario Context: {global_context}", flush=True)

        pronoun_mode = self.config.get("pronoun_mode", "dynamic")
        custom_pronoun = str(self.config.get("custom_pronoun_prompt", "") or "").strip()

        if pronoun_mode == "custom" and custom_pronoun:
            pronoun_rules = f"CUSTOM PRONOUN RULES (Quy tắc người dùng thiết lập):\n{custom_pronoun}"
        elif pronoun_mode == "couple":
            pronoun_rules = "XƯNG HÔ CẶP ĐÔI: Nam xưng anh - gọi em. Nữ xưng em - gọi anh. Không xưng hô kiểu khác."
        elif pronoun_mode == "family_parent_child":
            pronoun_rules = "XƯNG HÔ GIA ĐÌNH: Bố/Mẹ xưng bố/mẹ - gọi con. Con xưng con - gọi bố/mẹ."
        elif pronoun_mode == "friends":
            pronoun_rules = "XƯNG HÔ BẠN BÈ: Xưng mình/tôi - gọi bạn/cậu tự nhiên."
        elif pronoun_mode == "formal":
            pronoun_rules = "XƯNG HÔ TRANG TRỌNG / THUYẾT MINH: Xưng tôi - gọi anh/chị/quý vị."
        else:
            # dynamic (Default for multi-character dramas, films, vlogs)
            pronoun_rules = (
                "DYNAMIC MULTI-CHARACTER PRONOUN RULES (Xưng hô linh hoạt theo phân cảnh đối thoại):\n"
                "- Determine Vietnamese pronouns dynamically based on who is speaking to whom in the current scene:\n"
                "  * Husband & Wife / Couple: anh - em\n"
                "  * Mother & Child: mẹ - con\n"
                "  * Father & Child: bố - con\n"
                "  * Siblings / Older & Younger: anh/chị - em\n"
                "  * Neighbors / Strangers / Officials: tôi - bác / anh / chị / ông / bà\n"
                "  * Friends / Peers: mình - bạn / cậu\n"
                "- DO NOT lock the entire video into a single 2-person relationship.\n"
                "- Maintain dialogue consistency within each scene."
            )

        context_instructions = (
            f"Scenario: {global_context}\n"
            f"{pronoun_rules}\n"
            if global_context or pronoun_rules else ""
        )

        translated_segments = []
        recent_context_lines = []

        for i in range(0, len(segments), batch_size):
            batch = segments[i:i + batch_size]
            payload_input = []
            for idx, seg in enumerate(batch):
                item = {"id": idx, "src": seg["text"]}
                if seg.get("speaker"):
                    item["speaker"] = seg["speaker"]
                payload_input.append(item)

            recent_ctx_str = ""
            if recent_context_lines:
                recent_ctx_str = "Recent translated context for dialogue continuity:\n" + "\n".join(recent_context_lines[-3:]) + "\n\n"

            if is_bilingual:
                prompt = (
                    f"You are a professional video dialogue and subtitle translator.\n"
                    f"{context_instructions}\n"
                    f"{recent_ctx_str}"
                    f"Translate each subtitle text segment from 'src' into TWO target languages:\n"
                    f"1. Primary target language: '{target_lang}' (e.g. Vietnamese) -> assign to key 'text'\n"
                    f"2. Secondary target language: '{secondary_lang}' (e.g. English) -> assign to key 'text_secondary'\n\n"
                    f"CRITICAL RULES:\n"
                    f"- The key 'text' MUST be the translation in '{target_lang}'. DO NOT leave original Chinese in 'text'!\n"
                    f"- Maintain natural spoken dialogue flow, expressive emotional nuance, and concise phrasing.\n"
                    f"- For short or fast-paced dialogue, keep the Vietnamese translation punchy and concise, avoiding redundant verbal fillers so dubbing synchronizes naturally.\n"
                    f"- Return strictly a JSON array of objects with keys 'id', 'text', and 'text_secondary'.\n"
                    f"- Do not add any additional explanation or markdown blocks.\n\n"
                    f"Input JSON: {json.dumps(payload_input, ensure_ascii=False)}"
                )
                system_msg = f"You are a professional subtitle translator. Output strictly JSON array of {{\"id\": int, \"text\": string, \"text_secondary\": string}}."
            else:
                prompt = (
                    f"You are a professional video dialogue and subtitle translator.\n"
                    f"{context_instructions}\n"
                    f"{recent_ctx_str}"
                    f"Translate each subtitle text segment from 'src' into target language: '{target_lang}'.\n\n"
                    f"CRITICAL RULES:\n"
                    f"- The key 'text' MUST be the translation in '{target_lang}'. DO NOT leave original Chinese in 'text'!\n"
                    f"- Maintain natural spoken dialogue flow, expressive emotional nuance, and concise phrasing.\n"
                    f"- For short or fast-paced dialogue, keep the Vietnamese translation punchy and concise, avoiding redundant verbal fillers so dubbing synchronizes naturally.\n"
                    f"- Return strictly a JSON array of objects with keys 'id' and 'text'.\n"
                    f"- Do not add any additional explanation or markdown blocks.\n\n"
                    f"Input JSON: {json.dumps(payload_input, ensure_ascii=False)}"
                )
                system_msg = "You are a professional subtitle translator. Output strictly JSON array of {\"id\": int, \"text\": string}."

            body = {
                "model": model,
                "messages": [
                    {"role": "system", "content": system_msg},
                    {"role": "user", "content": prompt}
                ],
                "temperature": 0.2
            }

            try:
                resp = requests.post(endpoint, headers=headers, json=body, timeout=120)
                resp.raise_for_status()
                response_text = resp.json()["choices"][0]["message"]["content"].strip()

                if response_text.startswith("```"):
                    response_text = response_text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()

                translated_batch = json.loads(response_text)
                if isinstance(translated_batch, dict):
                    translated_batch = (
                        translated_batch.get("segments")
                        or translated_batch.get("items")
                        or list(translated_batch.values())[0]
                    )

                trans_map = {}
                for item in translated_batch:
                    if isinstance(item, dict) and "id" in item:
                        trans_map[item["id"]] = item

                for idx, seg in enumerate(batch):
                    new_seg = dict(seg)
                    item_res = trans_map.get(idx, {})
                    if isinstance(item_res, dict):
                        raw_trans = item_res.get("text", seg["text"])
                        raw_sec = item_res.get("text_secondary", "")
                    else:
                        raw_trans = str(item_res)
                        raw_sec = ""

                    if zh_pattern.search(raw_trans):
                        # Fast LLM single-retry fallback first
                        try:
                            fix_prompt = f"Translate this short subtitle directly to {target_lang}. Output ONLY the translated text: {seg['text']}"
                            fix_resp = requests.post(
                                endpoint,
                                headers=headers,
                                json={"model": model, "messages": [{"role": "user", "content": fix_prompt}], "temperature": 0.2},
                                timeout=15
                            )
                            if fix_resp.status_code == 200:
                                fixed_t = fix_resp.json()["choices"][0]["message"]["content"].strip().strip('"').strip("'")
                                if fixed_t and not zh_pattern.search(fixed_t):
                                    raw_trans = fixed_t
                        except Exception:
                            pass

                        if zh_pattern.search(raw_trans):
                            from plugins.translation.ollama_qwen import _translate_fallback_google
                            raw_trans = _translate_fallback_google(seg["text"], target_lang)

                    # Giữ nguyên text gốc (ASR/OCR), set translated_text + text_vi
                    new_seg["translated_text"] = raw_trans
                    new_seg["text_vi"] = raw_trans

                    if is_bilingual:
                        from plugins.translation.ollama_qwen import _translate_fallback_google
                        if not raw_sec or (zh_pattern.search(raw_sec) and secondary_lang != "zh"):
                            raw_sec = _translate_fallback_google(seg["text"], secondary_lang)
                        new_seg["text_secondary"] = raw_sec
                    else:
                        new_seg.pop("text_secondary", None)

                    translated_segments.append(new_seg)
                    spk_tag = f"[{seg.get('speaker')}]: " if seg.get('speaker') else ""
                    recent_context_lines.append(f"{spk_tag}{raw_trans}")

            except Exception as e:
                logger.warning(f"Cloud translation failed for batch {i}: {e}. Falling back to Google Translate.")
                from plugins.translation.ollama_qwen import _translate_fallback_google
                for seg in batch:
                    new_seg = dict(seg)
                    raw_trans = _translate_fallback_google(seg["text"], target_lang)
                    new_seg["translated_text"] = raw_trans
                    new_seg["text_vi"] = raw_trans
                    if is_bilingual:
                        new_seg["text_secondary"] = _translate_fallback_google(seg["text"], secondary_lang)
                    else:
                        new_seg.pop("text_secondary", None)
                    translated_segments.append(new_seg)

        # ── Pass 3: Readability & Length Guard (CPS <= 18) ────────────────────
        for seg in translated_segments:
            s_start = float(seg.get("start", 0.0))
            s_end = float(seg.get("end", 0.0))
            dur = max(0.4, s_end - s_start)
            txt = str(seg.get("translated_text") or seg.get("text_vi") or "").strip()
            cps = len(txt) / dur if dur > 0 else 0
            if dur < 1.8 and len(txt) > 22 and cps > 15:
                # Remove redundant verbal padding and shorten wordy patterns
                cleaned = (
                    txt.replace("thực sự là ", "")
                    .replace("thực sự ", "")
                    .replace("có vẻ như là ", "hình như ")
                    .replace("chúng ta hãy ", "hãy ")
                    .replace("chúng ta ", "")
                    .replace("thực ra là ", "")
                    .replace("thực ra ", "")
                    .replace("ngay bây giờ", "ngay")
                    .replace("rất là ", "rất ")
                    .replace("của tôi", "")
                    .strip()
                )
                seg["translated_text"] = cleaned
                seg["text_vi"] = cleaned

        return translated_segments

    def generate_metadata(self, segments: List[Dict[str, Any]], target_lang: str = "vi", hashtag_count: int = 5) -> Dict[str, Any]:
        if not segments:
            return {
                "title": "Video Thuyết Minh",
                "description": "Video thuyết minh tự động.",
                "hashtags": ["#video", "#viral"]
            }

        full_text = " ".join([seg.get("translated_text") or seg.get("text_vi") or seg.get("text", "") for seg in segments[:30]])

        t_cfg = self.config.get("translator")
        if isinstance(t_cfg, dict):
            p_type = str(t_cfg.get("type", "openai")).lower()
            default_base_url = "https://api.groq.com/openai/v1" if p_type == "groq" else "https://api.deepseek.com/v1" if p_type == "deepseek" else "https://generativelanguage.googleapis.com/v1beta/openai" if p_type == "gemini" else "https://api.openai.com/v1"
            api_key = (
                t_cfg.get("api_key")
                or self.config.get("openai_api_key")
                or os.environ.get("OPENAI_API_KEY")
                or os.environ.get("GROQ_API_KEY")
                or os.environ.get("GEMINI_API_KEY")
                or os.environ.get("DEEPSEEK_API_KEY")
            )
            base_url = t_cfg.get("base_url") or self.config.get("openai_base_url") or os.environ.get("OPENAI_BASE_URL", default_base_url)
            model = t_cfg.get("model") or self.config.get("translator_model", "gpt-4o-mini")
        else:
            api_key = (
                self.config.get("openai_api_key")
                or os.environ.get("OPENAI_API_KEY")
                or os.environ.get("GROQ_API_KEY")
                or os.environ.get("GEMINI_API_KEY")
                or os.environ.get("DEEPSEEK_API_KEY")
            )
            base_url = self.config.get("openai_base_url") or os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")
            model = self.config.get("translator_model", "gpt-4o-mini")

        model, endpoint = _normalize_model_and_endpoint(model, base_url)

        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}" if api_key else ""
        }

        prompt = (
            f"Dựa trên nội dung bản dịch video sau đây:\n\"{full_text}\"\n\n"
            f"Hãy sáng tạo thông tin đăng bài bằng ngôn ngữ '{target_lang}'.\n"
            f"Yêu cầu:\n"
            f"1. 'title': Tiêu đề ngắn gọn, giật gân, thu hút người xem (dưới 80 ký tự).\n"
            f"2. 'description': Đoạn mô tả ngắn gọn nội dung video (2-3 câu).\n"
            f"3. 'hashtags': Danh sách đúng {hashtag_count} hashtags xu hướng phù hợp (bắt đầu bằng dấu #).\n\n"
            f"Trả về DUY NHẤT một JSON object với 3 key: 'title', 'description', 'hashtags'."
        )

        body = {
            "model": model,
            "messages": [
                {"role": "system", "content": "You are a professional video content creator. Output strictly JSON with keys: title (string), description (string), hashtags (list of strings)."},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.5
        }

        try:
            resp = requests.post(endpoint, headers=headers, json=body, timeout=120)
            resp.raise_for_status()
            response_text = resp.json()["choices"][0]["message"]["content"].strip()

            if response_text.startswith("```"):
                response_text = response_text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()

            res = json.loads(response_text)
            title = str(res.get("title", "")).strip()
            desc = str(res.get("description", "")).strip()
            tags = res.get("hashtags", [])
            if isinstance(tags, str):
                tags = [t.strip() for t in tags.split() if t.strip()]
            tags = [t if t.startswith("#") else f"#{t}" for t in tags]

            return {
                "title": title or "Video Thuyết Minh",
                "description": desc or "Video thuyết minh tự động.",
                "hashtags": tags or ["#video", "#viral"]
            }
        except Exception as e:
            logger.warning(f"Cloud metadata generation failed: {e}")
            first_few = " ".join([seg.get("text", "") for seg in segments[:3]])
            return {
                "title": first_few[:60] if first_few else "Video Thuyết Minh",
                "description": first_few[:200] if first_few else "Video thuyết minh tự động.",
                "hashtags": ["#video", "#viral", "#subvideo"]
            }
