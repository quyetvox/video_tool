import json
from pathlib import Path
from typing import Any, Dict

from core.plugin_loader import PluginLoader
from core.step_base import StepBase


class StepTranslation(StepBase):
    step_id = "s08_translation"
    depends_on = ["s07_transcript_merge"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        merge_info = job_state.get_step_output("s07_transcript_merge") or {}
        transcript_file = Path(merge_info["transcript_file"])

        with open(transcript_file, "r", encoding="utf-8") as f:
            segments = json.load(f)

        target_lang = config.get("target_lang", "vi")
        translator_cfg = config.get("translator", "ollama")
        if isinstance(translator_cfg, dict):
            provider_type = str(translator_cfg.get("type", "ollama")).lower().replace("-", "_")
        else:
            provider_type = str(translator_cfg).lower().replace("-", "_")

        # Map translator options to plugin filenames
        if provider_type in ["ollama", "ollama_qwen"]:
            translator_plugin_name = "ollama_qwen"
        else:
            translator_plugin_name = "openai"

        translator_plugin = PluginLoader.load_plugin("translation", translator_plugin_name, config)
        translated_segments = translator_plugin.translate_segments(segments, target_lang)
        from utils.repetition_cleaner import RepetitionCleaner
        translated_segments = RepetitionCleaner.clean_segments(translated_segments)

        out_file = workspace / "s08_translation.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(translated_segments, f, ensure_ascii=False, indent=2)

        return {
            "translation_file": str(out_file),
            "target_lang": target_lang,
            "segment_count": len(translated_segments)
        }
