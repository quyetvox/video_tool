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

        asr_plugin_name = config.get("asr", "mlx-whisper")
        # Map hyphens to underscores for python module imports
        asr_plugin_name = asr_plugin_name.replace("-", "_")

        from utils.repetition_cleaner import RepetitionCleaner

        asr_plugin = PluginLoader.load_plugin("asr", asr_plugin_name, config)
        raw_segments = asr_plugin.transcribe(voice_path)
        segments = RepetitionCleaner.clean_segments(raw_segments)

        out_file = workspace / "s05_asr.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(segments, f, ensure_ascii=False, indent=2)

        return {
            "transcript_file": str(out_file),
            "segment_count": len(segments)
        }
