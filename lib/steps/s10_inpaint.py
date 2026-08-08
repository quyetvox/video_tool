import shutil
from pathlib import Path
from typing import Any, Dict

from core.plugin_loader import PluginLoader
from core.step_base import StepBase


class StepInpaint(StepBase):
    step_id = "s10_inpaint"
    depends_on = ["s02_demux", "s03_subtitle_detect"]
    STEP_CONFIG_KEYS = [
        "inpaint", "inpaint_region", "blur_radius", "subtitle_font_size",
        "watermark_enable", "watermark_region", "watermark_image",
        "watermark_text", "watermark_blur_bg", "watermark_opacity", "watermark_font_color"
    ]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        detect_info = job_state.get_step_output("s03_subtitle_detect") or {}
        demux_info = job_state.get_step_output("s02_demux") or {}

        mode = detect_info.get("mode")
        input_video = Path(demux_info["video_stream"])
        clean_video = workspace / "clean_video.mp4"

        ocr_only = config.get("ocr_only", False)
        if not ocr_only and mode != "burnin":
            # Copy input video directly if no burnin sub and not in ocr_only mode
            shutil.copy(str(input_video), str(clean_video))
            return {
                "inpaint_applied": False,
                "clean_video": str(clean_video)
            }

        # Calculate inpaint region: manual config > auto-detect burnin > auto-detect from OCR bboxes > default bottom box
        region = config.get("inpaint_region") or detect_info.get("burnin_region")
        
        segments = None
        transcript_file = workspace / "s07_transcript.json"
        if transcript_file.exists():
            import json
            try:
                with open(transcript_file, "r", encoding="utf-8") as f:
                    segments = json.load(f)
            except Exception:
                pass

        if not region and segments:
            # Auto-calculate bounding box enclosing all OCR detected subtitle texts with 10% side margins (0.1 -> 0.9)
            bboxes = [s["bbox"] for s in segments if "bbox" in s and isinstance(s["bbox"], list) and len(s["bbox"]) == 4]
            if bboxes:
                auto_ymin = max(0.0, min(b[0] for b in bboxes) - 0.02)
                auto_ymax = min(1.0, max(b[2] for b in bboxes) + 0.02)
                region = [round(auto_ymin, 3), 0.1, round(auto_ymax, 3), 0.9]

        if not region:
            region = [0.75, 0.1, 0.95, 0.9]

        # Use full detected/configured burnin region so box blur completely covers original subtitle
        inpaint_plugin_name = config.get("inpaint", "ffmpeg_blur").replace("-", "_")

        if inpaint_plugin_name == "opencv":
            inpaint_plugin_name = "opencv_inpaint"
        elif inpaint_plugin_name in ("blur", "ffmpeg_blur", "boxblur"):
            inpaint_plugin_name = "ffmpeg_blur"

        inpaint_plugin = PluginLoader.load_plugin("inpaint", inpaint_plugin_name, config)
        try:
            inpaint_plugin.remove_subtitles(input_video, region, clean_video, segments=segments)
        except TypeError:
            inpaint_plugin.remove_subtitles(input_video, region, clean_video)

        return {
            "inpaint_applied": True,
            "clean_video": str(clean_video)
        }
