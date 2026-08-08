import json
import logging
from pathlib import Path
from typing import Any, Dict, List

import requests

from plugins.interfaces import TranslatorBase

logger = logging.getLogger("sub_video")


def _translate_fallback_google(text: str, target_lang: str = "vi") -> str:
    if not text or not text.strip():
        return text
    try:
        import urllib.parse
        import urllib.request
        import ssl
        ctx = ssl._create_unverified_context()
        url = f"https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl={target_lang}&dt=t&q={urllib.parse.quote(text)}"
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return "".join([part[0] for part in data[0] if part[0]])
    except Exception:
        return text


class Plugin(TranslatorBase):
    def translate_segments(self, segments: List[Dict[str, Any]], target_lang: str) -> List[Dict[str, Any]]:
        if not segments:
            return []

        import re
        zh_pattern = re.compile(r'[\u4e00-\u9fff]')

        t_cfg = self.config.get("translator")
        if isinstance(t_cfg, dict):
            host = t_cfg.get("base_url") or t_cfg.get("host") or self.config.get("ollama_host", "http://localhost:11434")
            model = t_cfg.get("model") or self.config.get("translator_model", "qwen2.5")
            batch_size = t_cfg.get("batch_size") or self.config.get("translator_batch_size", 20)
            api_key = t_cfg.get("api_key") or self.config.get("api_key", "")
        else:
            host = self.config.get("ollama_host", "http://localhost:11434")
            model = self.config.get("translator_model", "qwen2.5")
            batch_size = self.config.get("translator_batch_size", 20)
            api_key = self.config.get("api_key", "")

        host = host.rstrip("/")
        headers = {"Content-Type": "application/json"}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"

        translated_segments = []

        for i in range(0, len(segments), batch_size):
            batch = segments[i:i + batch_size]
            payload_input = [{"id": idx, "text": seg["text"]} for idx, seg in enumerate(batch)]

            prompt = (
                f"You are a professional video subtitle translator.\n"
                f"Translate the following subtitle text segments into target language: '{target_lang}'.\n"
                f"Return strictly a JSON array of objects with keys 'id' and 'text'.\n"
                f"Do not add any additional explanation, markdown blocks, or commentary.\n\n"
                f"Input JSON: {json.dumps(payload_input, ensure_ascii=False)}"
            )

            try:
                # Try OpenAI-compatible /v1/chat/completions first (used by Cline/LiteLLM/Ollama Proxy)
                if api_key or "/v1" in host:
                    endpoint = f"{host}/chat/completions" if host.endswith("/v1") else f"{host}/v1/chat/completions"
                    resp = requests.post(
                        endpoint,
                        headers=headers,
                        json={"model": model, "messages": [{"role": "user", "content": prompt}], "temperature": 0.2},
                        timeout=180
                    )
                    resp.raise_for_status()
                    response_text = resp.json()["choices"][0]["message"]["content"].strip()
                else:
                    endpoint = f"{host}/api/generate"
                    resp = requests.post(
                        endpoint,
                        headers=headers,
                        json={"model": model, "prompt": prompt, "format": "json", "stream": False},
                        timeout=180
                    )
                    resp.raise_for_status()
                    response_text = resp.json().get("response", "").strip()

                if response_text.startswith("```"):
                    response_text = response_text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()

                translated_batch = json.loads(response_text)
                trans_map = {item["id"]: item["text"] for item in translated_batch}

                for idx, seg in enumerate(batch):
                    new_seg = dict(seg)
                    raw_trans = trans_map.get(idx, seg["text"])
                    if zh_pattern.search(raw_trans):
                        raw_trans = _translate_fallback_google(raw_trans, target_lang)
                    new_seg["text"] = raw_trans
                    translated_segments.append(new_seg)

            except Exception as e:
                logger.warning(f"Ollama translation failed for batch {i}: {e}. Falling back to Google Translate.")
                for seg in batch:
                    new_seg = dict(seg)
                    new_seg["text"] = _translate_fallback_google(seg["text"], target_lang)
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

        translator_cfg = self.config.get("translator") if isinstance(self.config.get("translator"), dict) else {}
        host = self.config.get("ollama_host") or self.config.get("base_url") or translator_cfg.get("base_url") or "http://localhost:11434"
        model = self.config.get("translator_model") or self.config.get("model") or translator_cfg.get("model") or "qwen3.5:4b"
        api_key = self.config.get("api_key") or translator_cfg.get("api_key", "")

        host = host.rstrip("/")
        headers = {"Content-Type": "application/json"}
        if api_key:
            headers["Authorization"] = f"Bearer {api_key}"

        prompt = (
            f"Dựa trên nội dung bản dịch video sau đây:\n\"{full_text}\"\n\n"
            f"Hãy sáng tạo thông tin đăng bài bằng ngôn ngữ '{target_lang}'.\n"
            f"Yêu cầu:\n"
            f"1. 'title': Tiêu đề ngắn gọn, giật gân, thu hút người xem (dưới 80 ký tự).\n"
            f"2. 'description': Đoạn mô tả ngắn gọn nội dung video (2-3 câu).\n"
            f"3. 'hashtags': Danh sách đúng {hashtag_count} hashtags xu hướng phù hợp (bắt đầu bằng dấu #).\n\n"
            f"Trả về DUY NHẤT một JSON object với 3 key: 'title', 'description', 'hashtags'.\n"
            f"Ví dụ: {{\n"
            f"  \"title\": \"Bí quyết làm món ăn siêu ngon\",\n"
            f"  \"description\": \"Chia sẻ chi tiết các bước chế biến món ăn hấp dẫn ngay tại nhà.\",\n"
            f"  \"hashtags\": [\"#monngon\", \"#nauan\", \"#amthuc\"]\n"
            f"}}"
        )

        try:
            if api_key or "/v1" in host:
                endpoint = f"{host}/chat/completions" if host.endswith("/v1") else f"{host}/v1/chat/completions"
                resp = requests.post(
                    endpoint,
                    headers=headers,
                    json={"model": model, "messages": [{"role": "user", "content": prompt}], "temperature": 0.3},
                    timeout=120
                )
                resp.raise_for_status()
                response_text = resp.json()["choices"][0]["message"]["content"].strip()
            else:
                endpoint = f"{host}/api/generate"
                resp = requests.post(
                    endpoint,
                    headers=headers,
                    json={"model": model, "prompt": prompt, "format": "json", "stream": False},
                    timeout=120
                )
                resp.raise_for_status()
                response_text = resp.json().get("response", "").strip()

            if "<think>" in response_text and "</think>" in response_text:
                response_text = response_text.split("</think>")[-1].strip()

            if "```" in response_text:
                parts = response_text.split("```")
                for part in parts:
                    clean_part = part.replace("json", "").strip()
                    if clean_part.startswith("{") and clean_part.endswith("}"):
                        response_text = clean_part
                        break

            # Find first { and last }
            s_idx = response_text.find("{")
            e_idx = response_text.rfind("}")
            if s_idx != -1 and e_idx != -1 and e_idx > s_idx:
                response_text = response_text[s_idx:e_idx+1]

            import re
            # Clean trailing commas inside JSON
            cleaned_json_str = re.sub(r',\s*([\]}])', r'\1', response_text)

            res = {}
            try:
                res = json.loads(cleaned_json_str, strict=False)
            except Exception:
                # Regex fallback if JSON parsing fails due to unescaped quotes
                t_match = re.search(r'"title"\s*:\s*"(.*?)"', response_text, re.DOTALL)
                d_match = re.search(r'"description"\s*:\s*"(.*?)"', response_text, re.DOTALL)
                tags_match = re.search(r'"hashtags"\s*:\s*\[(.*?)\]', response_text, re.DOTALL)

                if t_match:
                    res["title"] = t_match.group(1).replace('\\"', '"')
                if d_match:
                    res["description"] = d_match.group(1).replace('\\"', '"')
                if tags_match:
                    raw_tags = re.findall(r'"(#?[^"]+)"', tags_match.group(1))
                    res["hashtags"] = raw_tags

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
            logger.warning(f"Ollama metadata generation failed: {e}")
            first_few = " ".join([seg.get("text", "") for seg in segments[:3]])
            return {
                "title": first_few[:60] if first_few else "Video Thuyết Minh",
                "description": first_few[:200] if first_few else "Video thuyết minh tự động.",
                "hashtags": ["#video", "#viral", "#shortvideo"]
            }
