import json
from pathlib import Path
from typing import Any, Dict

from core.plugin_loader import PluginLoader
from core.step_base import StepBase


class StepOCR(StepBase):
    step_id = "s06_ocr"
    depends_on = ["s02_demux", "s03_subtitle_detect", "s05_asr"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        detect_info = job_state.get_step_output("s03_subtitle_detect") or {}
        demux_info = job_state.get_step_output("s02_demux") or {}

        mode = detect_info.get("mode")
        ocr_mode = config.get("ocr_mode", "region")

        if mode != "burnin" or ocr_mode == "region":
            # Skip OCR if mode is not burnin or if ocr_mode is region (fast 0s mode)
            out_file = workspace / "s06_ocr.json"
            with open(out_file, "w", encoding="utf-8") as f:
                json.dump([], f)
            return {
                "skipped": True,
                "mode": ocr_mode,
                "segment_count": 0,
                "transcript_file": str(out_file)
            }

        video_path = Path(demux_info["video_stream"])
        region = detect_info.get("burnin_region") or [0.8, 0.0, 1.0, 1.0]

        asr_info = job_state.get_step_output("s05_asr") or {}
        asr_file = Path(asr_info.get("transcript_file", workspace / "s05_asr.json"))
        asr_segments = []
        if asr_file.exists():
            with open(asr_file, "r", encoding="utf-8") as f:
                asr_segments = json.load(f)

        ocr_plugin_name = config.get("ocr", "paddleocr").replace("-", "_")
        if ocr_plugin_name == "paddleocr":
            ocr_plugin_name = "paddle_ocr"

        ocr_plugin = PluginLoader.load_plugin("ocr", ocr_plugin_name, config)
        
        if hasattr(ocr_plugin, "extract_text_keyframes") and asr_segments:
            segments = ocr_plugin.extract_text_keyframes(video_path, region, asr_segments)
        else:
            segments = ocr_plugin.extract_text(video_path, region)

        out_file = workspace / "s06_ocr.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(segments, f, ensure_ascii=False, indent=2)

        return {
            "skipped": False,
            "mode": ocr_mode,
            "transcript_file": str(out_file),
            "segment_count": len(segments)
        }
