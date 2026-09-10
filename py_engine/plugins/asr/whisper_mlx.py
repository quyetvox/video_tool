import subprocess
from pathlib import Path
from typing import Any, Dict, List

from plugins.interfaces import ASRBase


class Plugin(ASRBase):
    def transcribe(self, audio_path: Path) -> List[Dict[str, Any]]:
        model_name = self.config.get("asr_model", "auto")
        
        try:
            import warnings
            warnings.filterwarnings("ignore", message=".*unauthenticated requests.*")
            import logging
            logging.getLogger("huggingface_hub").setLevel(logging.ERROR)
            try:
                from huggingface_hub.utils import logging as hf_logging
                hf_logging.set_verbosity_error()
                import huggingface_hub.utils._http as _hf_http
                _hf_http._WARNED_TOPICS.add("")
                _hf_http._WARNED_TOPICS.add("unauthenticated")
            except Exception:
                pass

            import mlx_whisper as _mlx
            from utils.ffmpeg_utils import FFmpegUtils

            def _get_hf_repo(m_name: str) -> str:
                if m_name.startswith("mlx-community/"):
                    repo_id = m_name
                elif "turbo" in m_name:
                    repo_id = "mlx-community/whisper-large-v3-turbo"
                elif not m_name.endswith("-mlx"):
                    repo_id = f"mlx-community/whisper-{m_name}-mlx"
                else:
                    repo_id = f"mlx-community/whisper-{m_name}"

                # Local-First Zero-Latency: Return local directory if model snapshot is already cached.
                # Completely bypasses remote HTTP check, eliminates unauthenticated warnings, and has 0ms latency.
                try:
                    from huggingface_hub import snapshot_download
                    local_dir = snapshot_download(repo_id, local_files_only=True)
                    if local_dir and Path(local_dir).exists():
                        return str(local_dir)
                except Exception:
                    pass

                return repo_id

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
                    try:
                        # Use ultra-lightweight tiny model (39MB) for sub-second (~0.3s) language identification
                        sample_res = _mlx.transcribe(
                            str(sample_wav),
                            path_or_hf_repo=_get_hf_repo("tiny"),
                            temperature=0.0
                        )
                        detected_lang = sample_res.get("language", "zh")
                        print(f"[ASR] Auto-detected language from active voice: '{detected_lang}' (via tiny detector)")
                    except Exception as e_tiny:
                        print(f"[ASR] Tiny detector not available offline ({e_tiny}). Falling back to cached 'large-v3-turbo' for language detection...")
                        sample_res = _mlx.transcribe(
                            str(sample_wav),
                            path_or_hf_repo=_get_hf_repo("large-v3-turbo"),
                            temperature=0.0
                        )
                        detected_lang = sample_res.get("language", "zh")
                        print(f"[ASR] Auto-detected language from active voice: '{detected_lang}'")
                finally:
                    if sample_wav.exists():
                        sample_wav.unlink(missing_ok=True)

            self.detected_language = detected_lang
            raw_m = str(model_name).lower().strip()
            if raw_m in ("auto", "small"):
                selected_model = "small"
            elif "turbo" in raw_m or "large" in raw_m:
                selected_model = "large-v3-turbo"
            else:
                selected_model = raw_m

            enable_word_ts = bool(self.config.get("word_timestamps", False))
            print(f"[ASR] Transcribing audio ({total_duration:.1f}s) with model: {selected_model} (language: {detected_lang}, word_timestamps={enable_word_ts})...")
            repo_name = _get_hf_repo(selected_model)
            try:
                result = _mlx.transcribe(
                    str(audio_path),
                    path_or_hf_repo=repo_name,
                    language=detected_lang,
                    word_timestamps=enable_word_ts,
                    condition_on_previous_text=False,
                    temperature=0.0
                )
            except Exception as e_main:
                if selected_model != "large-v3-turbo":
                    print(f"[ASR] Model '{selected_model}' failed or missing offline ({e_main}). Falling back to cached 'large-v3-turbo'...")
                    fallback_repo = _get_hf_repo("large-v3-turbo")
                    result = _mlx.transcribe(
                        str(audio_path),
                        path_or_hf_repo=fallback_repo,
                        language=detected_lang,
                        word_timestamps=enable_word_ts,
                        condition_on_previous_text=False,
                        temperature=0.0
                    )
                else:
                    raise
            segments = _parse_raw_segments(result, time_offset=0.0)

            # Refine timestamps with Audio VAD energy onset snapping
            refined_segments = AudioVAD.refine_timestamps(audio_path, segments)
            return refined_segments
        except ImportError:
            from plugins.asr.whisper_fallback import Plugin as FallbackPlugin
            return FallbackPlugin(self.config).transcribe(audio_path)
