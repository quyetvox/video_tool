import json
from pathlib import Path
from typing import Any, Dict

from core.plugin_loader import PluginLoader
from core.step_base import StepBase


class StepASR(StepBase):
    step_id = "s05_asr"
    depends_on = ["s04_audio_separate"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        out_file = workspace / "s05_asr.json"

        if config.get("ocr_only", False):
            print("[ASR] ocr_only mode enabled: Bypassing Whisper ASR (~0s).")
            with open(out_file, "w", encoding="utf-8") as f:
                json.dump([], f)
            return {
                "skipped": True,
                "transcript_file": str(out_file),
                "segment_count": 0
            }

        audio_info = job_state.get_step_output("s04_audio_separate") or {}
        voice_path = Path(audio_info["voice"])

        asr_val = config.get("asr", "mlx-whisper")
        if isinstance(asr_val, dict) or hasattr(asr_val, "get"):
            asr_plugin_name = asr_val.get("engine", "mlx-whisper")
        else:
            asr_plugin_name = asr_val
        if isinstance(asr_plugin_name, dict) or hasattr(asr_plugin_name, "get"):
            asr_plugin_name = asr_plugin_name.get("engine", "mlx-whisper")
        asr_plugin_name = str(asr_plugin_name)
        # Map hyphens to underscores for python module imports
        asr_plugin_name = asr_plugin_name.replace("-", "_")

        from utils.repetition_cleaner import RepetitionCleaner

        asr_plugin = PluginLoader.load_plugin("asr", asr_plugin_name, config)
        raw_segments = asr_plugin.transcribe(voice_path)
        segments = RepetitionCleaner.clean_segments(raw_segments)

        out_file = workspace / "s05_asr.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(segments, f, ensure_ascii=False, indent=2)

        detected_lang = getattr(asr_plugin, "detected_language", None)
        return {
            "transcript_file": str(out_file),
            "segment_count": len(segments),
            "detected_language": detected_lang
        }

