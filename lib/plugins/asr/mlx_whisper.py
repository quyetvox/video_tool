from pathlib import Path
from typing import Any, Dict, List

from plugins.interfaces import ASRBase


class Plugin(ASRBase):
    def transcribe(self, audio_path: Path) -> List[Dict[str, Any]]:
        model_name = self.config.get("asr_model", "auto")
        
        try:
            import mlx_whisper
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
                    test_res = mlx_whisper.transcribe(
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

            print(f"[ASR] Transcribing audio with model: {selected_model}...")
            repo_name = _get_hf_repo(selected_model)
            result = mlx_whisper.transcribe(str(audio_path), path_or_hf_repo=repo_name)
            segments = []
            for seg in result.get("segments", []):
                segments.append({
                    "start": round(float(seg.get("start", 0)), 3),
                    "end": round(float(seg.get("end", 0)), 3),
                    "text": seg.get("text", "").strip()
                })
            return segments
        except ImportError:
            # Fallback if mlx_whisper not installed
            from plugins.asr.whisper_fallback import Plugin as FallbackPlugin
            return FallbackPlugin(self.config).transcribe(audio_path)
