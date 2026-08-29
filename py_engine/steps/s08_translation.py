import json
from pathlib import Path
from typing import Any, Dict

from core.plugin_loader import PluginLoader
from core.step_base import StepBase


class StepTranslation(StepBase):
    step_id = "s08_translation"
    depends_on = ["s07_transcript_merge"]
    STEP_CONFIG_KEYS = ["translator", "translator_model", "target_lang", "secondary_lang"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        merge_info = job_state.get_step_output("s07_transcript_merge") or {}
        t_cand = merge_info.get("transcript_file")
        transcript_file = Path(t_cand) if t_cand and Path(t_cand).exists() else (workspace / "s07_transcript.json")

        with open(transcript_file, "r", encoding="utf-8") as f:
            segments = json.load(f)

        target_lang = config.get("target_lang", "vi")
        secondary_lang = config.get("secondary_lang", "")
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
        translated_segments = translator_plugin.translate_segments(segments, target_lang, secondary_lang)
        from utils.repetition_cleaner import RepetitionCleaner
        translated_segments = RepetitionCleaner.clean_segments(translated_segments)

        out_file = workspace / "s08_translation.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(translated_segments, f, ensure_ascii=False, indent=2)

        extracted_meta = getattr(translator_plugin, "last_extracted_meta", {}) or {}

        return {
            "translation_file": str(out_file),
            "target_lang": target_lang,
            "secondary_lang": secondary_lang,
            "segment_count": len(translated_segments),
            "extracted_meta": extracted_meta
        }
