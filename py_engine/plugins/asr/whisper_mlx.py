import subprocess
from pathlib import Path
from typing import Any, Dict, List

from plugins.interfaces import ASRBase


class Plugin(ASRBase):
    def transcribe(self, audio_path: Path) -> List[Dict[str, Any]]:
        model_name = self.config.get("asr_model", "auto")
        
        try:
            import mlx_whisper as _mlx
            from utils.ffmpeg_utils import FFmpegUtils

            def _get_hf_repo(m_name: str) -> str:
                if m_name.startswith("mlx-community/"):
                    return m_name
                if "turbo" in m_name:
                    return "mlx-community/whisper-large-v3-turbo"
                if not m_name.endswith("-mlx"):
                    return f"mlx-community/whisper-{m_name}-mlx"
                return f"mlx-community/whisper-{m_name}"

            def _parse_raw_segments(mlx_result: Dict[str, Any], time_offset: float = 0.0) -> List[Dict[str, Any]]:
                segs = []
                for seg in mlx_result.get("segments", []):
                    words = seg.get("words", [])
                    if words and len(words) > 0:
                        w_start = float(words[0].get("start", seg.get("start", 0.0)))
                        w_end = float(words[-1].get("end", seg.get("end", 0.0)))
                        s_start = min(float(seg.get("start", 0.0)), w_start) if abs(w_start - float(seg.get("start", 0.0))) > 2.0 else w_start
                        s_end = max(float(seg.get("end", 0.0)), w_end)
                    else:
                        s_start = float(seg.get("start", 0.0))
                        s_end = float(seg.get("end", 0.0))

                    text = seg.get("text", "").strip()
                    if text:
                        segs.append({
                            "start": round(s_start + time_offset, 3),
                            "end": round(s_end + time_offset, 3),
                            "text": text
                        })
                return segs

            total_duration = FFmpegUtils.get_audio_duration(audio_path)
            segments = []

            from utils.audio_vad import AudioVAD

            # 1. Determine language: Check explicit config or detected language from parent chunk
            explicit_lang = (
                self.config.get("source_lang") or
                self.config.get("language") or
                self.config.get("asr_language") or
                self.config.get("detected_language")
            )

            detected_lang = None
            if explicit_lang and isinstance(explicit_lang, str) and explicit_lang.strip().lower() not in ("auto", "none"):
                detected_lang = explicit_lang.strip().lower()
                print(f"[ASR] Using configured source language: '{detected_lang}'")
            else:
                # 2. Peak Voice Energy Sampling: Scan audio in RAM to find the loudest 15s voice window
                start_sec, end_sec, peak_rms = AudioVAD.find_peak_voice_window(audio_path, window_sec=15.0)
                print(f"[ASR Peak Scan] Found loudest speech window: {start_sec:.1f}s - {end_sec:.1f}s (RMS: {peak_rms:.1f} dB)")

                if peak_rms < -42.0:
                    # Non-speech audio: entire file is pure silence or quiet instrumental
                    print(f"[ASR] No speech detected across entire audio (Peak RMS {peak_rms:.1f} dB < -42.0 dB). Skipping ASR to prevent hallucinations.")
                    self.detected_language = None
                    return []

                # Extract sample slice in memory / temp file to detect language reliably
                sample_wav = audio_path.parent / "sample_peak_voice.wav"
                cmd_sample = [
                    "ffmpeg", "-y", "-ss", str(start_sec), "-i", str(audio_path),
                    "-t", str(round(end_sec - start_sec, 2)), "-c:a", "pcm_s16le", str(sample_wav)
                ]
                subprocess.run(cmd_sample, capture_output=True, check=True)
                try:
                    sample_res = _mlx.transcribe(
                        str(sample_wav),
                        path_or_hf_repo=_get_hf_repo("large-v3-turbo")
                    )
                    detected_lang = sample_res.get("language", "zh")
                    print(f"[ASR] Auto-detected language from active voice: '{detected_lang}'")
                finally:
                    if sample_wav.exists():
                        sample_wav.unlink(missing_ok=True)

            self.detected_language = detected_lang
            selected_model = "large-v3-turbo" if model_name in ("auto", "turbo") else model_name
            print(f"[ASR] Transcribing audio ({total_duration:.1f}s) with model: {selected_model} (language: {detected_lang})...")
            repo_name = _get_hf_repo(selected_model)
            result = _mlx.transcribe(
                str(audio_path),
                path_or_hf_repo=repo_name,
                language=detected_lang,
                word_timestamps=True,
                condition_on_previous_text=False
            )
            segments = _parse_raw_segments(result, time_offset=0.0)

            # Refine timestamps with Audio VAD energy onset snapping
            refined_segments = AudioVAD.refine_timestamps(audio_path, segments)
            return refined_segments
        except ImportError:
            from plugins.asr.whisper_fallback import Plugin as FallbackPlugin
            return FallbackPlugin(self.config).transcribe(audio_path)
