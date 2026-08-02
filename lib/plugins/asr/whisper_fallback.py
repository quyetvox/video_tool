from pathlib import Path
from typing import Any, Dict, List

from plugins.interfaces import ASRBase


class Plugin(ASRBase):
    def transcribe(self, audio_path: Path) -> List[Dict[str, Any]]:
        # Dummy / lightweight fallback or openai-whisper
        try:
            import whisper
            model_name = self.config.get("asr_model", "base")
            model = whisper.load_model(model_name)
            result = model.transcribe(str(audio_path))
            segments = []
            for seg in result.get("segments", []):
                segments.append({
                    "start": round(float(seg.get("start", 0)), 3),
                    "end": round(float(seg.get("end", 0)), 3),
                    "text": seg.get("text", "").strip()
                })
            return segments
        except Exception as e:
            # Safe fallback if whisper library is not installed
            return []
