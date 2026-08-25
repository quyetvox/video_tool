import json
import shutil
from pathlib import Path
from typing import Any, Dict

from core.plugin_loader import PluginLoader
from core.step_base import StepBase
from utils.ffmpeg_utils import FFmpegUtils


class StepInpaint(StepBase):
    step_id = "s10_inpaint"
    depends_on = ["s02_demux", "s03_subtitle_detect"]
    STEP_CONFIG_KEYS = [
        "show_subtitle", "inpaint", "inpaint_show_box", "inpaint_method", "inpaint_region", "inpaint_color", "blur_radius", 
        "inpaint_box_bg_color", "inpaint_box_bg_opacity", "inpaint_box_border_color", 
        "inpaint_box_border_width", "inpaint_box_border_radius", "subtitle_font_size", 
        "video_bitrate", "blur_box_padding_y", "watermark_enable", "watermark_region", 
        "watermark_image", "watermark_text", "watermark_font_name", "watermark_blur_bg", 
        "watermark_opacity", "watermark_font_color"
    ]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        detect_info = job_state.get_step_output("s03_subtitle_detect") or {}
        demux_info = job_state.get_step_output("s02_demux") or {}
        probe_info = job_state.get_step_output("s01_probe") or {}

        mode = detect_info.get("mode")
        input_video = Path(demux_info["video_stream"])
        clean_video = workspace / "clean_video.mp4"
        temp_inpainted = workspace / "temp_inpainted.mp4"

        ocr_only = config.get("ocr_only", False)
        show_sub = config.get("show_subtitle", True)
        override_region = config.get("inpaint_region")
        need_inpaint = (show_sub or bool(override_region)) and (ocr_only or (mode == "burnin") or bool(override_region))

        if need_inpaint:
            # Calculate inpaint region: manual config > auto-detect burnin > auto-detect from OCR bboxes > default bottom box
            raw_region = config.get("inpaint_region") or detect_info.get("burnin_region")
            padding_y = float(config.get("blur_box_padding_y", 0.02))

            if raw_region and len(raw_region) == 4:
                if not config.get("inpaint_region"):
                    ymin, xmin, ymax, xmax = raw_region
                    padded_ymin = max(0.0, ymin - padding_y)
                    padded_ymax = min(1.0, ymax + padding_y)
                    region = [round(padded_ymin, 3), xmin, round(padded_ymax, 3), xmax]
                else:
                    region = raw_region
            else:
                region = None

            segments = None
            for cand_name in ["s08c_timing.json", "s08_translation.json", "s07_transcript.json"]:
                cand_file = workspace / cand_name
                if cand_file.exists():
                    try:
                        with open(cand_file, "r", encoding="utf-8") as f:
                            segments = json.load(f)
                            if segments:
                                break
                    except Exception:
                        pass

            if not region and segments:
                # Auto-calculate bounding box enclosing all OCR detected subtitle texts with 10% side margins (0.1 -> 0.9)
                bboxes = [s["bbox"] for s in segments if "bbox" in s and isinstance(s["bbox"], list) and len(s["bbox"]) == 4]
                if bboxes:
                    auto_ymin = max(0.0, min(b[0] for b in bboxes) - padding_y)
                    auto_ymax = min(1.0, max(b[2] for b in bboxes) + padding_y)
                    region = [round(auto_ymin, 3), 0.1, round(auto_ymax, 3), 0.9]

            if not region:
                region = [0.75, 0.1, 0.95, 0.9]

            inpaint_engine = str(config.get("inpaint", "ffmpeg_blur")).replace("-", "_").lower()
            inpaint_color = str(config.get("inpaint_color", "transparent")).strip().lower()
            is_solid_box = (inpaint_engine in ["box_color", "box"]) or (inpaint_color not in ["transparent", "", "none"])

            # When a solid colored box is requested (e.g. black, white), ffmpeg_blur's drawbox is optimal (~0.5s)
            if is_solid_box:
                inpaint_plugin_name = "ffmpeg_blur"
            elif inpaint_engine == "opencv":
                inpaint_plugin_name = "opencv_inpaint"
            elif inpaint_engine in ("apple_vision", "apple_vision_inpaint", "applevision"):
                inpaint_plugin_name = "apple_vision_inpaint"
            elif inpaint_engine in ("blur", "ffmpeg_blur", "boxblur"):
                inpaint_plugin_name = "ffmpeg_blur"
            else:
                inpaint_plugin_name = "ffmpeg_blur"

            inpaint_plugin = PluginLoader.load_plugin("inpaint", inpaint_plugin_name, config)
            inpaint_segments = segments
            try:
                inpaint_plugin.remove_subtitles(input_video, region, temp_inpainted, segments=inpaint_segments)
            except TypeError:
                inpaint_plugin.remove_subtitles(input_video, region, temp_inpainted)

            video_for_watermark = temp_inpainted
            inpaint_applied = True
        else:
            video_for_watermark = input_video
            inpaint_applied = False

        # Apply watermark post-inpaint pass (supported across all inpaint engines)
        wm_applied = False
        if config.get("watermark_enable", False):
            video_width = probe_info.get("width")
            video_height = probe_info.get("height")
            config_ctx = config.copy() if hasattr(config, "copy") else dict(config)
            config_ctx["workspace_dir"] = str(workspace)
            wm_applied = FFmpegUtils.apply_watermark(
                video_for_watermark,
                clean_video,
                config_ctx,
                width=video_width,
                height=video_height
            )

        if not wm_applied:
            # If watermark was not applied (disabled/inactive), output video_for_watermark to clean_video
            if video_for_watermark != clean_video:
                shutil.copy(str(video_for_watermark), str(clean_video))

        if temp_inpainted.exists():
            temp_inpainted.unlink(missing_ok=True)

        return {
            "inpaint_applied": inpaint_applied,
            "watermark_applied": wm_applied,
            "clean_video": str(clean_video)
        }
