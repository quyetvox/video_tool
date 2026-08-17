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
        ocr_only = config.get("ocr_only", False)

        if not ocr_only and (mode != "burnin" or ocr_mode == "region"):
            # Skip OCR if mode is not burnin or if ocr_mode is region (fast 0s mode for audio translate)
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
        region = config.get("inpaint_region") or detect_info.get("burnin_region") or [0.10, 0.0, 0.95, 1.0]

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

        # Use fast diff-skip method if available:
        #   - narrow crop to burnin_region (smaller image → faster OCR per frame)
        #   - skips OCR when subtitle pixel content hasn't changed (saves 70-80% OCR calls)
        if hasattr(ocr_plugin, "extract_text_with_diff_skip"):
            segments = ocr_plugin.extract_text_with_diff_skip(video_path, region)
        elif not ocr_only and hasattr(ocr_plugin, "extract_text_keyframes") and asr_segments:
            segments = ocr_plugin.extract_text_keyframes(video_path, region, asr_segments)
        else:
            segments = ocr_plugin.extract_text(video_path, region)

        # Smart filter to remove small noise text (single non-Chinese digits/letters or 1-char noise)
        filtered_segments = []
        for s in segments:
            txt = s.get("text", "").strip()
            if not txt:
                continue
            has_chinese = any(0x4e00 <= ord(c) <= 0x9fff for c in txt)
            char_count = sum(1 for c in txt if 0x4e00 <= ord(c) <= 0x9fff)
            bbox = s.get("bbox") or [0, 0, 0, 0]
            box_w = bbox[3] - bbox[1] if len(bbox) == 4 else 0.0
            dur = float(s.get("end", 0)) - float(s.get("start", 0))

            # Filter out 1-char Chinese noise with small width < 4% or duration < 0.5s
            if char_count == 1 and (box_w < 0.04 or dur < 0.5):
                continue

            if has_chinese or len(txt) >= 3:
                filtered_segments.append(s)
        segments = filtered_segments

        out_file = workspace / "s06_ocr.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(segments, f, ensure_ascii=False, indent=2)

        return {
            "skipped": False,
            "mode": ocr_mode,
            "transcript_file": str(out_file),
            "segment_count": len(segments)
        }
