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

        host = self.config.get("ollama_host", "http://localhost:11434")
        model = self.config.get("translator_model", "qwen2.5")
        batch_size = self.config.get("translator_batch_size", 20)

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
                resp = requests.post(
                    f"{host}/api/generate",
                    json={"model": model, "prompt": prompt, "format": "json", "stream": False},
                    timeout=180
                )
                resp.raise_for_status()
                response_text = resp.json().get("response", "").strip()

                # Clean markdown blocks if present
                if response_text.startswith("```"):
                    response_text = response_text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()

                translated_batch = json.loads(response_text)
                trans_map = {item["id"]: item["text"] for item in translated_batch}

                for idx, seg in enumerate(batch):
                    new_seg = dict(seg)
                    new_seg["text"] = trans_map.get(idx, seg["text"])
                    translated_segments.append(new_seg)

            except Exception as e:
                logger.warning(f"Ollama translation failed for batch {i}: {e}. Falling back to original text or basic translation.")
                # Fallback: keep original text or basic translation
                for seg in batch:
                    translated_segments.append(dict(seg))

        return translated_segments
