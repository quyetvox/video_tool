import shutil
from pathlib import Path
from typing import Any, Dict

from core.plugin_loader import PluginLoader
from core.step_base import StepBase


class StepInpaint(StepBase):
    step_id = "s10_inpaint"
    depends_on = ["s02_demux", "s03_subtitle_detect"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        detect_info = job_state.get_step_output("s03_subtitle_detect") or {}
        demux_info = job_state.get_step_output("s02_demux") or {}

        mode = detect_info.get("mode")
        input_video = Path(demux_info["video_stream"])
        clean_video = workspace / "clean_video.mp4"

        if mode != "burnin":
            # Copy input video directly if no burnin sub
            shutil.copy(str(input_video), str(clean_video))
            return {
                "inpaint_applied": False,
                "clean_video": str(clean_video)
            }

        region = config.get("inpaint_region") or detect_info.get("burnin_region") or [0.8, 0.0, 1.0, 1.0]
        
        segments = None
        transcript_file = workspace / "s07_transcript.json"
        if transcript_file.exists():
            import json
            try:
                with open(transcript_file, "r", encoding="utf-8") as f:
                    segments = json.load(f)
            except Exception:
                pass

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
