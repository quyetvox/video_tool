import logging
from pathlib import Path
from typing import Any, Dict, List

from plugins.interfaces import ASRBase
from utils.ffmpeg_utils import ensure_system_path

logger = logging.getLogger("sub_video")


class Plugin(ASRBase):
    def transcribe(self, audio_path: Path) -> List[Dict[str, Any]]:
        ensure_system_path()
        try:
            import whisper
            raw_model = self.config.get("asr_model", "base")
            model_name = "base" if raw_model in ("auto", "", None) else raw_model

            logger.info(f"[ASR Fallback] Loading whisper model '{model_name}' (requested: '{raw_model}')...")
            model = whisper.load_model(model_name)

            transcribe_kwargs: Dict[str, Any] = {"verbose": False}
            try:
                import torch
                if not torch.cuda.is_available():
                    transcribe_kwargs["fp16"] = False
            except Exception:
                transcribe_kwargs["fp16"] = False

            result = model.transcribe(str(audio_path), **transcribe_kwargs)
            segments = []
            for seg in result.get("segments", []):
                text = seg.get("text", "").strip()
                if text:
                    segments.append({
                        "start": round(float(seg.get("start", 0)), 3),
                        "end": round(float(seg.get("end", 0)), 3),
                        "text": text
                    })
            return segments
        except Exception as e:
            logger.warning(f"[ASR Fallback] Whisper transcription failed or library unavailable: {e}")
            return []

