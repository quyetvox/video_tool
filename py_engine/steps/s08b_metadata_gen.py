import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

from core.plugin_loader import PluginLoader
from core.step_base import StepBase

logger = logging.getLogger("sub_video")


class StepMetadataGen(StepBase):
    step_id = "s08b_metadata_gen"
    depends_on = ["s08_translation"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        enable_gen = config.get("enable_metadata_gen", True)
        out_file = workspace / "s08b_metadata.json"

        if not enable_gen:
            logger.info("[s08b_metadata_gen] Skipped (enable_metadata_gen is False).")
            res = {
                "job_id": job_state.job_id,
                "video_name": getattr(job_state, "video_name", "video.mp4"),
                "status": "disabled",
                "title": "",
                "description": "",
                "hashtags": []
            }
            with open(out_file, "w", encoding="utf-8") as f:
                json.dump(res, f, ensure_ascii=False, indent=2)
            return {"metadata_file": str(out_file), "enabled": False}

        # ── 1. Persistent Cache Check ──────────────────────────────────────────
        if out_file.exists() and out_file.stat().st_size > 50:
            try:
                with open(out_file, "r", encoding="utf-8") as f:
                    cached_meta = json.load(f)
                if cached_meta.get("title") or cached_meta.get("description"):
                    logger.info("[s08b_metadata_gen] Persistent cache found. Reusing metadata without LLM call.")
                    return {
                        "metadata_file": str(out_file),
                        "title": cached_meta.get("title", ""),
                        "hashtags_count": len(cached_meta.get("hashtags", []))
                    }
            except Exception:
                pass

        trans_info = job_state.get_step_output("s08_translation") or {}
        extracted_meta = trans_info.get("extracted_meta") or {}

        # ── 2. Fast reuse from Step 08 Pass 1 ──────────────────────────────────
        if isinstance(extracted_meta, dict) and (extracted_meta.get("title") or extracted_meta.get("description")):
            logger.info("[s08b_metadata_gen] Reusing Pass 1 extracted metadata (0s).")
            meta_res = {
                "title": extracted_meta.get("title", ""),
                "description": extracted_meta.get("description", ""),
                "hashtags": [f"#{t.lstrip('#')}" for t in extracted_meta.get("tags", [])]
            }
        else:
            trans_file = Path(trans_info.get("translation_file", workspace / "s08_translation.json"))
            segments = []
            if trans_file.exists():
                with open(trans_file, "r", encoding="utf-8") as f:
                    segments = json.load(f)

            target_lang = config.get("target_lang", "vi")
            hashtag_count = int(config.get("metadata_hashtags_count", 5))
            translator_cfg = config.get("translator", "ollama")
            if isinstance(translator_cfg, dict):
                provider_type = str(translator_cfg.get("type", "ollama")).lower().replace("-", "_")
            else:
                provider_type = str(translator_cfg).lower().replace("-", "_")

            if provider_type in ["ollama", "ollama_qwen"]:
                translator_plugin_name = "ollama_qwen"
            else:
                translator_plugin_name = "openai"

            translator_plugin = PluginLoader.load_plugin("translation", translator_plugin_name, config)
            meta_res = translator_plugin.generate_metadata(segments, target_lang=target_lang, hashtag_count=hashtag_count)

        video_stem = job_state.job_id.replace("job_", "")
        output_video_name = f"{video_stem}{config.get('output_suffix', '_vi')}.mp4"

        metadata = {
            "job_id": job_state.job_id,
            "video_name": getattr(job_state, "video_name", f"{video_stem}.mp4"),
            "output_video": output_video_name,
            "title": meta_res.get("title", ""),
            "description": meta_res.get("description", ""),
            "hashtags": meta_res.get("hashtags", []),
            "created_at": datetime.now().isoformat()
        }

        # 1. Save single file to job workspace
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(metadata, f, ensure_ascii=False, indent=2)

        # 2. Append / update to aggregated summary file in project output directory
        project_dir = workspace.parent.parent
        output_dir = project_dir / "output"
        output_dir.mkdir(parents=True, exist_ok=True)
        summary_file = output_dir / "metadata_summary.json"

        summary_list = []
        if summary_file.exists():
            try:
                with open(summary_file, "r", encoding="utf-8") as f:
                    summary_list = json.load(f)
                if not isinstance(summary_list, list):
                    summary_list = []
            except Exception:
                summary_list = []

        # Upsert based on output_video
        item_data = {
            "output_video": metadata["output_video"],
            "title": metadata["title"],
            "description": metadata["description"],
            "hashtags": metadata["hashtags"]
        }

        updated = False
        for idx, item in enumerate(summary_list):
            if isinstance(item, dict) and item.get("output_video") == metadata["output_video"]:
                summary_list[idx] = item_data
                updated = True
                break

        if not updated:
            summary_list.append(item_data)

        with open(summary_file, "w", encoding="utf-8") as f:
            json.dump(summary_list, f, ensure_ascii=False, indent=2)

        logger.info(f"[s08b_metadata_gen] Generated metadata: Title='{metadata['title']}' ({len(metadata['hashtags'])} hashtags)")

        return {
            "metadata_file": str(out_file),
            "summary_file": str(summary_file),
            "title": metadata["title"],
            "hashtags_count": len(metadata["hashtags"])
        }
