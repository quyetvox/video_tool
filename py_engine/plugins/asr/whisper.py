import logging
import os
from pathlib import Path
from typing import Any, Dict, List

from plugins.interfaces import ASRBase
from utils.ffmpeg_utils import ensure_system_path

logger = logging.getLogger("sub_video")


class Plugin(ASRBase):
    """
    Cross-platform OpenAI-Whisper plugin optimized for Windows/Linux (CPU & CUDA).
    Handles automatic model mapping from 'auto', sets appropriate fp16 flags,
    and refines timestamps using vocal energy AudioVAD.
    """

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self.detected_language = None

    def transcribe(self, audio_path: Path) -> List[Dict[str, Any]]:
        ensure_system_path()

        try:
            import torch
            has_cuda = torch.cuda.is_available()
            device = "cuda" if has_cuda else "cpu"
        except ImportError:
            has_cuda = False
            device = "cpu"

        # Model name resolution & fallback mapping
        raw_model_name = self.config.get("asr_model", "auto")
        if isinstance(raw_model_name, str):
            raw_model_name = raw_model_name.strip()
        else:
            raw_model_name = "auto"

        if raw_model_name in ("auto", "", None):
            selected_model = "small"
        elif "turbo" in raw_model_name.lower():
            selected_model = "turbo" if has_cuda else "small"
        else:
            selected_model = raw_model_name

        logger.info(
            f"[ASR Windows] Loading OpenAI-Whisper model '{selected_model}' on device '{device}' (requested: '{raw_model_name}')..."
        )
        print(
            f"[ASR Windows] Loading Whisper model: '{selected_model}' ({device})..."
        )

        try:
            import whisper

            try:
                model = whisper.load_model(selected_model, device=device)
            except Exception as e_load:
                if selected_model != "base":
                    print(f"[ASR Windows] Model '{selected_model}' unavailable ({e_load}). Falling back to 'base'...")
                    model = whisper.load_model("base", device=device)
                else:
                    raise

            enable_word_ts = bool(self.config.get("word_timestamps", False))
            transcribe_kwargs: Dict[str, Any] = {
                "word_timestamps": enable_word_ts,
                "verbose": False,
            }
            if not has_cuda:
                transcribe_kwargs["fp16"] = False

            lang = (
                self.config.get("source_lang") or
                self.config.get("language") or
                self.config.get("asr_language") or
                self.config.get("src_lang")
            )
            if lang and str(lang).lower() not in ("auto", "none"):
                transcribe_kwargs["language"] = str(lang).lower()

            result = model.transcribe(str(audio_path), **transcribe_kwargs)
            self.detected_language = result.get("language", "zh")

            segments: List[Dict[str, Any]] = []
            for seg in result.get("segments", []):
                words = seg.get("words", [])
                if words:
                    w_start = float(words[0].get("start", seg.get("start", 0.0)))
                    w_end = float(words[-1].get("end", seg.get("end", 0.0)))
                    s_start = min(float(seg.get("start", 0.0)), w_start)
                    s_end = max(float(seg.get("end", 0.0)), w_end)
                else:
                    s_start = float(seg.get("start", 0.0))
                    s_end = float(seg.get("end", 0.0))

                text = seg.get("text", "").strip()
                if text:
                    segments.append({
                        "start": round(s_start, 3),
                        "end": round(s_end, 3),
                        "text": text,
                    })

            # Refine timestamps using AudioVAD if vocal audio is available
            try:
                from utils.audio_vad import AudioVAD
                segments = AudioVAD.refine_timestamps(audio_path, segments)
            except Exception as e_vad:
                logger.warning(f"[ASR Windows] AudioVAD timestamp refinement skipped: {e_vad}")

            logger.info(f"[ASR Windows] Transcribed {len(segments)} segments successfully.")
            return segments

        except Exception as e:
            logger.error(f"[ASR Windows] Failed during transcription with model '{selected_model}': {e}", exc_info=True)
            print(f"[ASR Windows ERROR] Transcription failed: {e}")
            raise
