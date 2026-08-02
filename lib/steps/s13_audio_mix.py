from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase
from utils.ffmpeg_utils import FFmpegUtils


class StepAudioMix(StepBase):
    step_id = "s13_audio_mix"
    depends_on = ["s04_audio_separate", "s12_tts"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        audio_info = job_state.get_step_output("s04_audio_separate") or {}
        tts_info = job_state.get_step_output("s12_tts") or {}

        music_path = Path(audio_info["music"])
        effect_path = Path(audio_info["effect"])
        voice_path = Path(tts_info["translated_voice"])
        orig_voice_path = Path(audio_info["orig_voice"]) if "orig_voice" in audio_info else None

        probe_info = job_state.get_step_output("s01_probe") or {}
        duration = probe_info.get("duration")

        keep_orig = config.get("keep_original_voice", False)
        orig_vol = float(config.get("original_voice_volume", 0.15)) if keep_orig else 0.0
        music_vol = float(config.get("background_music_volume", 0.8))

        mixed_audio = workspace / "final_mixed_audio.wav"
        FFmpegUtils.mix_audio(
            music_path=music_path,
            voice_path=voice_path,
            output_path=mixed_audio,
            effect_path=effect_path,
            target_duration=duration,
            music_volume=music_vol,
            voice_volume=1.0,
            orig_voice_path=orig_voice_path,
            orig_voice_volume=orig_vol
        )

        return {
            "mixed_audio": str(mixed_audio)
        }
