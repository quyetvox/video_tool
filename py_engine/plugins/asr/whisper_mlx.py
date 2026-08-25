from pathlib import Path
from typing import Any, Dict, List

from plugins.interfaces import ASRBase


class Plugin(ASRBase):
    def transcribe(self, audio_path: Path) -> List[Dict[str, Any]]:
        model_name = self.config.get("asr_model", "auto")
        
        try:
            import mlx_whisper as _mlx
            import subprocess

            selected_model = model_name
            def _get_hf_repo(m_name: str) -> str:
                if m_name.startswith("mlx-community/"):
                    return m_name
                if "turbo" in m_name:
                    return "mlx-community/whisper-large-v3-turbo"
                if not m_name.endswith("-mlx"):
                    return f"mlx-community/whisper-{m_name}-mlx"
                return f"mlx-community/whisper-{m_name}"

            if model_name == "auto":
                # Adaptive Model Selection: Sample 20s of audio to test clarity
                sample_wav = audio_path.parent / "sample_test.wav"
                cmd_sample = [
                    "ffmpeg", "-y", "-ss", "5", "-i", str(audio_path),
                    "-t", "20", "-c:a", "pcm_s16le", str(sample_wav)
                ]
                try:
                    subprocess.run(cmd_sample, capture_output=True, check=True)
                    # Quick test with fast turbo model
                    test_res = _mlx.transcribe(
                        str(sample_wav),
                        path_or_hf_repo=_get_hf_repo("large-v3-turbo")
                    )
                    logprobs = [float(s.get("avg_logprob", -1.0)) for s in test_res.get("segments", []) if "avg_logprob" in s]
                    avg_score = sum(logprobs) / len(logprobs) if logprobs else -0.5

                    if avg_score >= -0.6:
                        selected_model = "large-v3-turbo"
                        print(f"[ASR Auto-Detect] Audio quality is clear (score: {avg_score:.2f} >= -0.60). Using FAST model: large-v3-turbo")
                    else:
                        selected_model = "large-v3"
                        print(f"[ASR Auto-Detect] Audio quality is noisy/complex (score: {avg_score:.2f} < -0.60). Using ACCURATE model: large-v3")
                except Exception as eval_err:
                    print(f"[ASR Auto-Detect] Sampling evaluation skipped ({eval_err}). Defaulting to large-v3-turbo")
                    selected_model = "large-v3-turbo"
                finally:
                    if sample_wav.exists():
                        sample_wav.unlink(missing_ok=True)

            print(f"[ASR] Transcribing audio with model: {selected_model} (word_timestamps=True)...")
            repo_name = _get_hf_repo(selected_model)
            result = _mlx.transcribe(
                str(audio_path),
                path_or_hf_repo=repo_name,
                word_timestamps=True,
                condition_on_previous_text=False
            )
            segments = []
            for seg in result.get("segments", []):
                words = seg.get("words", [])
                if words and len(words) > 0:
                    w_start = float(words[0].get("start", seg.get("start", 0.0)))
                    w_end = float(words[-1].get("end", seg.get("end", 0.0)))
                    s_start = min(float(seg.get("start", 0.0)), w_start) if abs(w_start - float(seg.get("start", 0.0))) > 2.0 else w_start
                    s_end = max(float(seg.get("end", 0.0)), w_end)
                else:
                    s_start = float(seg.get("start", 0.0))
                    s_end = float(seg.get("end", 0.0))

                segments.append({
                    "start": round(s_start, 3),
                    "end": round(s_end, 3),
                    "text": seg.get("text", "").strip()
                })

            # Refine timestamps with Audio VAD energy onset snapping
            from utils.audio_vad import AudioVAD
            refined_segments = AudioVAD.refine_timestamps(audio_path, segments)
            return refined_segments
        except ImportError:
            # Fallback if mlx_whisper not installed
            from plugins.asr.whisper_fallback import Plugin as FallbackPlugin
            return FallbackPlugin(self.config).transcribe(audio_path)
