import json
import shutil
import sys
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
        "video_bitrate", "blur_box_padding_y", "watermark_enable", "watermark_region", 
        "watermark_image", "watermark_text", "watermark_font_name", "watermark_blur_bg", 
        "watermark_opacity", "watermark_font_color"
    ]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        detect_info = job_state.get_step_output("s03_subtitle_detect") or {}
        ocr_info = job_state.get_step_output("s06_ocr") or {}
        demux_info = job_state.get_step_output("s02_demux") or {}
        probe_info = job_state.get_step_output("s01_probe") or {}

        mode = detect_info.get("mode")
        v_cand = demux_info.get("video_stream")
        if v_cand and Path(v_cand).exists():
            input_video = Path(v_cand)
        elif (workspace / "demux" / "video_stream.mp4").exists():
            input_video = workspace / "demux" / "video_stream.mp4"
        elif (workspace / "video_stream.mp4").exists():
            input_video = workspace / "video_stream.mp4"
        elif Path(job_state.data.get("input_video", "")).exists():
            input_video = Path(job_state.data["input_video"])
        else:
            input_video = Path(v_cand) if v_cand else (workspace / "demux" / "video_stream.mp4")

        clean_video = workspace / "clean_video.mp4"
        temp_inpainted = workspace / "temp_inpainted.mp4"

        inpaint_cfg = config.get("inpaint") if isinstance(config.get("inpaint"), dict) else {}
        ocr_only = config.get("ocr_only", False)
        show_sub = config.get("show_subtitle", True)
        show_box = bool(config.get("inpaint_show_box") if config.get("inpaint_show_box") is not None else inpaint_cfg.get("show_box", True))
        override_region = config.get("inpaint_region") or inpaint_cfg.get("region")
        need_inpaint = show_box

        if need_inpaint:
            # Calculate inpaint region: manual config region > auto-detect burnin > ocr detected region > fallback
            raw_region = override_region or detect_info.get("burnin_region") or ocr_info.get("detected_sub_region")
            padding_y = float(inpaint_cfg.get("padding_y") or config.get("blur_box_padding_y") or 0.01)

            if raw_region and len(raw_region) == 4:
                if not override_region:
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
                region = [0.80, 0.05, 0.95, 0.95]

            inpaint_engine = str(inpaint_cfg.get("engine") or config.get("inpaint") or "ffmpeg_blur").replace("-", "_").lower()
            inpaint_color = str(inpaint_cfg.get("color") or config.get("inpaint_color") or "transparent").strip().lower()
            is_solid_box = (inpaint_engine in ["box_color", "box"]) or (inpaint_color not in ["transparent", "", "none"])

            # When a solid colored box is requested (e.g. black, white), ffmpeg_blur's drawbox is optimal (~0.5s)
            if is_solid_box:
                inpaint_plugin_name = "ffmpeg_blur"
            elif inpaint_engine == "opencv":
                inpaint_plugin_name = "opencv_inpaint"
            elif inpaint_engine in ("apple_vision", "apple_vision_inpaint", "applevision"):
                inpaint_plugin_name = "ffmpeg_blur" if sys.platform == "win32" else "apple_vision_inpaint"
            elif inpaint_engine in ("blur", "ffmpeg_blur", "boxblur"):
                inpaint_plugin_name = "ffmpeg_blur"
            else:
                inpaint_plugin_name = "ffmpeg_blur"

            # Merge and preserve all engine-specific configurations to prevent miss-config
            merged_config = dict(config)
            merged_config["inpaint_region"] = region
            merged_config["inpaint_method"] = inpaint_cfg.get("method") or config.get("inpaint_method") or "vertical_gradient"
            merged_config["blur_radius"] = inpaint_cfg.get("blur_radius") or config.get("blur_radius") or 15
            merged_config["blur_box_padding_y"] = padding_y
            if "box" in inpaint_cfg and isinstance(inpaint_cfg["box"], dict):
                merged_config["inpaint_box"] = inpaint_cfg["box"]

            inpaint_plugin = PluginLoader.load_plugin("inpaint", inpaint_plugin_name, merged_config)
            inpaint_segments = segments

            # Validate watermark config strictly before processing
            wm_cfg = FFmpegUtils.validate_watermark_config(config, workspace=workspace)

            # 1-Pass Video Filtergraph: ffmpeg_blur merges inpaint boxblur + watermark into single encode
            try:
                inpaint_plugin.remove_subtitles(
                    input_video,
                    region,
                    clean_video,
                    segments=inpaint_segments,
                    watermark_config=wm_cfg
                )
                inpaint_applied = True
                wm_applied = bool(wm_cfg and wm_cfg.get("enabled"))
            except TypeError:
                # Fallback for third-party inpaint plugins without watermark_config support
                try:
                    inpaint_plugin.remove_subtitles(input_video, region, temp_inpainted, segments=inpaint_segments)
                except TypeError:
                    inpaint_plugin.remove_subtitles(input_video, region, temp_inpainted)
                inpaint_applied = True

                if wm_cfg:
                    video_width = int(probe_info.get("width") or 1920)
                    video_height = int(probe_info.get("height") or 1080)
                    config_ctx = config.copy() if hasattr(config, "copy") else dict(config)
                    config_ctx["workspace_dir"] = str(workspace)
                    wm_applied = FFmpegUtils.apply_watermark(
                        temp_inpainted,
                        clean_video,
                        config_ctx,
                        width=video_width,
                        height=video_height
                    )
                else:
                    shutil.copy(str(temp_inpainted), str(clean_video))
                    wm_applied = False
        else:
            inpaint_applied = False
            # Check if watermark is permitted and requested even when inpaint is skipped
            wm_cfg = FFmpegUtils.validate_watermark_config(config, workspace=workspace)
            if wm_cfg:
                video_width = int(probe_info.get("width") or 1920)
                video_height = int(probe_info.get("height") or 1080)
                config_ctx = config.copy() if hasattr(config, "copy") else dict(config)
                config_ctx["workspace_dir"] = str(workspace)
                wm_applied = FFmpegUtils.apply_watermark(
                    input_video,
                    clean_video,
                    config_ctx,
                    width=video_width,
                    height=video_height
                )
            else:
                shutil.copy(str(input_video), str(clean_video))
                wm_applied = False

        if temp_inpainted.exists():
            temp_inpainted.unlink(missing_ok=True)

        return {
            "inpaint_applied": inpaint_applied,
            "watermark_applied": wm_applied,
            "clean_video": str(clean_video)
        }
