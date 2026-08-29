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

            if model_name == "auto" and total_duration > 30.0:
                # Adaptive Quality Check on first 20s
                head_wav = audio_path.parent / "sample_head_20s.wav"
                rest_wav = audio_path.parent / "sample_rest.wav"

                cmd_head = [
                    "ffmpeg", "-y", "-ss", "0", "-i", str(audio_path),
                    "-t", "20.0", "-c:a", "pcm_s16le", str(head_wav)
                ]
                subprocess.run(cmd_head, capture_output=True, check=True)

                print("[ASR Auto-Detect] Testing audio clarity on first 20.0s...")
                head_res = _mlx.transcribe(
                    str(head_wav),
                    path_or_hf_repo=_get_hf_repo("large-v3-turbo"),
                    word_timestamps=True,
                    condition_on_previous_text=False
                )

                logprobs = [float(s.get("avg_logprob", -1.0)) for s in head_res.get("segments", []) if "avg_logprob" in s]
                avg_score = sum(logprobs) / len(logprobs) if logprobs else -0.5

                if avg_score >= -0.6:
                    print(f"[ASR Auto-Detect] Audio quality is clear (score: {avg_score:.2f} >= -0.60). Keeping 20s result & continuing with large-v3-turbo...")
                    head_segs = _parse_raw_segments(head_res, time_offset=0.0)

                    # Transcribe rest of audio from 20.0s to end
                    cmd_rest = [
                        "ffmpeg", "-y", "-ss", "20.0", "-i", str(audio_path),
                        "-c:a", "pcm_s16le", str(rest_wav)
                    ]
                    subprocess.run(cmd_rest, capture_output=True, check=True)

                    rest_res = _mlx.transcribe(
                        str(rest_wav),
                        path_or_hf_repo=_get_hf_repo("large-v3-turbo"),
                        word_timestamps=True,
                        condition_on_previous_text=False
                    )
                    rest_segs = _parse_raw_segments(rest_res, time_offset=20.0)
                    segments = head_segs + rest_segs
                else:
                    print(f"[ASR Auto-Detect] Audio quality is noisy/complex (score: {avg_score:.2f} < -0.60). Using full ACCURATE model: large-v3...")
                    full_res = _mlx.transcribe(
                        str(audio_path),
                        path_or_hf_repo=_get_hf_repo("large-v3"),
                        word_timestamps=True,
                        condition_on_previous_text=False
                    )
                    segments = _parse_raw_segments(full_res, time_offset=0.0)

                # Clean up temporary split sample files
                for tmp_f in (head_wav, rest_wav):
                    if tmp_f.exists():
                        tmp_f.unlink(missing_ok=True)
            else:
                # Direct full audio transcription (short video or explicit model chosen)
                selected_model = "large-v3-turbo" if model_name in ("auto", "turbo") else model_name
                print(f"[ASR] Transcribing audio ({total_duration:.1f}s) with model: {selected_model}...")
                repo_name = _get_hf_repo(selected_model)
                result = _mlx.transcribe(
                    str(audio_path),
                    path_or_hf_repo=repo_name,
                    word_timestamps=True,
                    condition_on_previous_text=False
                )
                segments = _parse_raw_segments(result, time_offset=0.0)

            # Refine timestamps with Audio VAD energy onset snapping
            from utils.audio_vad import AudioVAD
            refined_segments = AudioVAD.refine_timestamps(audio_path, segments)
            return refined_segments
        except ImportError:
            from plugins.asr.whisper_fallback import Plugin as FallbackPlugin
            return FallbackPlugin(self.config).transcribe(audio_path)
