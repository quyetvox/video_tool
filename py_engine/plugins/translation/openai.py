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
                self.config.get("openai_api_key")
                or os.environ.get("OPENAI_API_KEY")
                or os.environ.get("GROQ_API_KEY")
                or os.environ.get("GEMINI_API_KEY")
                or os.environ.get("DEEPSEEK_API_KEY")
            )
            base_url = self.config.get("openai_base_url") or os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")
            model = self.config.get("translator_model", "gpt-4o-mini")
            batch_size = self.config.get("translator_batch_size", 20)

        model, endpoint = _normalize_model_and_endpoint(model, base_url)

        translated_segments = []
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}" if api_key else ""
        }

        for i in range(0, len(segments), batch_size):
            batch = segments[i:i + batch_size]
            payload_input = [{"id": idx, "src": seg["text"]} for idx, seg in enumerate(batch)]

            if is_bilingual:
                prompt = (
                    f"You are a professional video subtitle translator.\n"
                    f"Translate each subtitle text segment from 'src' into TWO target languages:\n"
                    f"1. Primary target language: '{target_lang}' (e.g. Vietnamese) -> assign to key 'text'\n"
                    f"2. Secondary target language: '{secondary_lang}' (e.g. English) -> assign to key 'text_secondary'\n\n"
                    f"CRITICAL RULES:\n"
                    f"- The key 'text' MUST be the translation in '{target_lang}'. DO NOT leave original Chinese in 'text'!\n"
                    f"- Return strictly a JSON array of objects with keys 'id', 'text', and 'text_secondary'.\n"
                    f"- Do not add any additional explanation or markdown blocks.\n\n"
                    f"Input JSON: {json.dumps(payload_input, ensure_ascii=False)}"
                )
                system_msg = f"You are a professional subtitle translator. Output strictly JSON array of {{\"id\": int, \"text\": string, \"text_secondary\": string}}."
            else:
                prompt = (
                    f"You are a professional video subtitle translator.\n"
                    f"Translate each subtitle text segment from 'src' into target language: '{target_lang}'.\n\n"
                    f"CRITICAL RULES:\n"
                    f"- The key 'text' MUST be the translation in '{target_lang}'. DO NOT leave original Chinese in 'text'!\n"
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
