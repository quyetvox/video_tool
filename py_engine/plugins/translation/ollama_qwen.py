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

        # Strategy 1: clients5 dict API (High availability, zero 429 rate limit)
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


class Plugin(TranslatorBase):
    def _extract_fast_context(
        self,
        sample_text: str,
        host: str,
        model: str,
        headers: Dict[str, str],
        api_key: str = "",
        target_lang: str = "vi"
    ) -> Dict[str, Any]:
        """Extracts characters, relationship, and consistent pronoun guidance in 1 lightweight call."""
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
            if api_key or "/v1" in host:
                endpoint = f"{host}/chat/completions" if host.endswith("/v1") else f"{host}/v1/chat/completions"
                resp = requests.post(
                    endpoint,
                    headers=headers,
                    json={"model": model, "messages": [{"role": "user", "content": prompt}], "temperature": 0.2},
                    timeout=20
                )
                resp.raise_for_status()
                res_txt = resp.json()["choices"][0]["message"]["content"].strip()
            else:
                endpoint = f"{host}/api/generate"
                resp = requests.post(
                    endpoint,
                    headers=headers,
                    json={"model": model, "prompt": prompt, "format": "json", "stream": False},
                    timeout=20
                )
                resp.raise_for_status()
                res_txt = resp.json().get("response", "").strip()

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
                extracted = self._extract_fast_context(sample_text, host, model, headers, api_key, target_lang)
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

        # ── Pass 2: Scene-Aware Context-Injected Batch Translation ────────────
        for i in range(0, len(segments), batch_size):
            batch = segments[i:i + batch_size]
            payload_input = []
            for idx, seg in enumerate(batch):
                item = {"id": idx, "text": seg["text"]}
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
                    f"Translate each subtitle text segment into TWO languages:\n"
                    f"1. Primary target language: '{target_lang}'\n"
                    f"2. Secondary target language: '{secondary_lang}'\n"
                    f"Maintain natural spoken dialogue flow, expressive emotional nuance, and concise phrasing.\n"
                    f"Return strictly a JSON array of objects with keys 'id', 'text' (primary in {target_lang}), and 'text_secondary' (secondary in {secondary_lang}).\n"
                    f"Do not add any additional explanation, markdown blocks, or commentary.\n\n"
                    f"Input JSON: {json.dumps(payload_input, ensure_ascii=False)}"
                )
            else:
                prompt = (
                    f"You are a professional video dialogue and subtitle translator.\n"
                    f"{context_instructions}\n"
                    f"{recent_ctx_str}"
                    f"Translate the following subtitle text segments into target language: '{target_lang}'.\n"
                    f"Maintain natural spoken dialogue flow, expressive emotional nuance, and concise phrasing.\n"
                    f"Return strictly a JSON array of objects with keys 'id' and 'text'.\n"
                    f"Do not add any additional explanation, markdown blocks, or commentary.\n\n"
                    f"Input JSON: {json.dumps(payload_input, ensure_ascii=False)}"
                )

            try:
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
                        raw_trans = _translate_fallback_google(raw_trans, target_lang)

                    # ✅ Giữ nguyên text gốc (ASR/OCR), set translated_text + text_vi cho bản dịch chính
                    new_seg["translated_text"] = raw_trans
                    new_seg["text_vi"] = raw_trans

                    if is_bilingual:
                        if not raw_sec or (zh_pattern.search(raw_sec) and secondary_lang != "zh"):
                            raw_sec = _translate_fallback_google(seg["text"], secondary_lang)
                        new_seg["text_secondary"] = raw_sec
                    else:
                        new_seg.pop("text_secondary", None)

                    translated_segments.append(new_seg)
                    spk_tag = f"[{seg.get('speaker')}]: " if seg.get('speaker') else ""
                    recent_context_lines.append(f"{spk_tag}{raw_trans}")

            except Exception as e:
                logger.warning(f"Ollama translation failed for batch {i}: {e}. Falling back to Google Translate.")
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

        # ── Pass 3: Readability & Length Guard (CPS <= 18) ────────────────────
        for seg in translated_segments:
            s_start = float(seg.get("start", 0.0))
            s_end = float(seg.get("end", 0.0))
            dur = max(0.4, s_end - s_start)
            txt = str(seg.get("translated_text") or "").strip()
            cps = len(txt) / dur if dur > 0 else 0
            if dur < 1.5 and len(txt) > 30 and cps > 18:
                # Remove redundant verbal padding
                cleaned = txt.replace("thực sự là ", "").replace("có vẻ như là ", "").replace("chúng ta hãy ", "").replace("thực ra là ", "")
                seg["translated_text"] = cleaned
                seg["text_vi"] = cleaned

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
        host = translator_cfg.get("base_url") or self.config.get("ollama_host") or self.config.get("base_url") or "http://localhost:11434"
        model = translator_cfg.get("model") or self.config.get("translator_model") or self.config.get("model") or "gemma4:31b-cloud"
        api_key = translator_cfg.get("api_key") or self.config.get("api_key", "")

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
