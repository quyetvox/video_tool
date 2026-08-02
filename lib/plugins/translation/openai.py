import os
import json
import logging
from pathlib import Path
from typing import Any, Dict, List
import requests

from plugins.interfaces import TranslatorBase

logger = logging.getLogger("sub_video")


class Plugin(TranslatorBase):
    def translate_segments(self, segments: List[Dict[str, Any]], target_lang: str) -> List[Dict[str, Any]]:
        if not segments:
            return []

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

            prompt = (
                f"You are a professional video subtitle translator.\n"
                f"Translate the following subtitle text segments into target language: '{target_lang}'.\n"
                f"Return strictly a JSON array of objects with keys 'id' and 'text'.\n"
                f"Input JSON: {json.dumps(payload_input, ensure_ascii=False)}"
            )

            body = {
                "model": model,
                "messages": [
                    {"role": "system", "content": "You are a professional subtitle translator. Output strictly JSON array of {\"id\": int, \"text\": string}."},
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

                trans_map = {
                    item["id"]: item["text"]
                    for item in translated_batch
                    if isinstance(item, dict) and "id" in item
                }

                for idx, seg in enumerate(batch):
                    new_seg = dict(seg)
                    new_seg["text"] = trans_map.get(idx, seg["text"])
                    translated_segments.append(new_seg)

            except Exception as e:
                logger.warning(f"Cloud translation failed for batch {i}: {e}. Keeping original text.")
                for seg in batch:
                    translated_segments.append(dict(seg))

        return translated_segments
