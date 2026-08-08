from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase
from utils.ffmpeg_utils import FFmpegUtils


class StepAudioMix(StepBase):
    step_id = "s13_audio_mix"
    depends_on = ["s04_audio_separate", "s12_tts"]
    STEP_CONFIG_KEYS = ["music_volume", "ambient_volume", "tts_voice_volume", "original_voice_volume"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        mixed_audio = workspace / "final_mixed_audio.wav"

        if config.get("ocr_only", False):
            print("[AudioMix] ocr_only mode enabled: Preserving 100% original audio stream (~0s).")
            demux_info = job_state.get_step_output("s02_demux") or {}
            audio_stream = Path(demux_info.get("audio_stream", workspace.parent / "demux" / "audio_stream.wav"))
            import shutil
            shutil.copy2(str(audio_stream), str(mixed_audio))
            return {
                "skipped": True,
                "mixed_audio": str(mixed_audio)
            }

        audio_info = job_state.get_step_output("s04_audio_separate") or {}
        tts_info = job_state.get_step_output("s12_tts") or {}

        music_path = Path(audio_info["music"])
        ambient_path = Path(audio_info["ambient"]) if "ambient" in audio_info else None
        effect_path = Path(audio_info["effect"])
        voice_path = Path(tts_info["translated_voice"])
        orig_voice_path = Path(audio_info["orig_voice"]) if "orig_voice" in audio_info else None

        probe_info = job_state.get_step_output("s01_probe") or {}
        duration = probe_info.get("duration")

        # Audio volume controls (0.0 = automatically disabled/muted)
        orig_vol = max(0.0, float(config.get("original_voice_volume", 0.05)))
        music_vol = max(0.0, float(config.get("music_volume", config.get("background_music_volume", 0.5))))
        ambient_vol = max(0.0, float(config.get("ambient_volume", 0.75)))
        tts_vol = max(0.0, float(config.get("tts_voice_volume", 1.0)))

        if tts_vol > 0.0 and tts_vol < max(music_vol, ambient_vol):
            print(f"[AudioMix] ⚠️ Warning: tts_voice_volume ({tts_vol}) is lower than music/ambient volume, TTS voice might be drowned out.")

        mixed_audio = workspace / "final_mixed_audio.wav"
        FFmpegUtils.mix_audio(
            music_path=music_path,
            voice_path=voice_path,
            output_path=mixed_audio,
            ambient_path=ambient_path,
            effect_path=effect_path,
            target_duration=duration,
            music_volume=music_vol,
            ambient_volume=ambient_vol,
            voice_volume=tts_vol,
            orig_voice_path=orig_voice_path,
            orig_voice_volume=orig_vol
        )

        return {
            "mixed_audio": str(mixed_audio)
        }
