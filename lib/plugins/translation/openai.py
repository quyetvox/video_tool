import os
import json
import logging
from pathlib import Path
from typing import Any, Dict, List
import requests

from plugins.interfaces import TranslatorBase

logger = logging.getLogger("sub_video")


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
            default_base_url = "https://api.groq.com/openai/v1" if p_type == "groq" else "https://api.deepseek.com/v1" if p_type == "deepseek" else "https://api.openai.com/v1"
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

        translated_segments = []
        headers = {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}" if api_key else ""
        }

        for i in range(0, len(segments), batch_size):
            batch = segments[i:i + batch_size]
            payload_input = [{"id": idx, "text": seg["text"]} for idx, seg in enumerate(batch)]

            if is_bilingual:
                prompt = (
                    f"You are a professional video subtitle translator.\n"
                    f"Translate each subtitle text segment into TWO languages:\n"
                    f"1. Primary target language: '{target_lang}'\n"
                    f"2. Secondary target language: '{secondary_lang}'\n"
                    f"Return strictly a JSON array of objects with keys 'id', 'text' (primary translation in {target_lang}), and 'text_secondary' (secondary translation in {secondary_lang}).\n"
                    f"Do not add any additional explanation, markdown blocks, or commentary.\n\n"
                    f"Input JSON: {json.dumps(payload_input, ensure_ascii=False)}"
                )
                system_msg = f"You are a professional subtitle translator. Output strictly JSON array of {{\"id\": int, \"text\": string, \"text_secondary\": string}}."
            else:
                prompt = (
                    f"You are a professional video subtitle translator.\n"
                    f"Translate the following subtitle text segments into target language: '{target_lang}'.\n"
                    f"Return strictly a JSON array of objects with keys 'id' and 'text'.\n"
                    f"Do not add any additional explanation, markdown blocks, or commentary.\n\n"
                    f"Input JSON: {json.dumps(payload_input, ensure_ascii=False)}"
                )
                system_msg = "You are a professional subtitle translator. Output strictly JSON array of {\"id\": int, \"text\": string}."

            body = {
                "model": model,
                "messages": [
                    {"role": "system", "content": system_msg},
                    {"role": "user", "content": prompt}
                ],
                "temperature": 0.3
            }

            try:
                endpoint = f"{base_url.rstrip('/')}/chat/completions"
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
                        from plugins.translation.ollama_qwen import _translate_fallback_google
                        raw_trans = _translate_fallback_google(raw_trans, target_lang)

                    # ✅ Giữ nguyên text gốc (ASR/OCR), set translated_text + text_vi
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
                    # ✅ Giữ nguyên text gốc, set translated_text + text_vi
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
                "hashtags": ["#video", "#viral", "#sub_video"]
            }

        full_text = " ".join([seg.get("text", "") for seg in segments if seg.get("text")])
        if len(full_text) > 3000:
            full_text = full_text[:3000]

        api_key = (
            self.config.get("openai_api_key")
            or os.environ.get("OPENAI_API_KEY")
            or os.environ.get("GROQ_API_KEY")
            or os.environ.get("GEMINI_API_KEY")
            or os.environ.get("DEEPSEEK_API_KEY")
        )
        base_url = self.config.get("openai_base_url") or os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1")
        model = self.config.get("translator_model", "gpt-4o-mini")

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
            endpoint = f"{base_url.rstrip('/')}/chat/completions"
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
                "hashtags": ["#video", "#viral", "#shortvideo"]
            }
