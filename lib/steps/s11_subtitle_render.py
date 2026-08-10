from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase
from utils.ffmpeg_utils import FFmpegUtils


import shutil

class StepSubtitleRender(StepBase):
    step_id = "s11_subtitle_render"
    depends_on = ["s09_subtitle_gen", "s10_inpaint"]
    STEP_CONFIG_KEYS = ["show_subtitle", "video_bitrate"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        inpaint_info = job_state.get_step_output("s10_inpaint") or {}
        sub_info = job_state.get_step_output("s09_subtitle_gen") or {}

        clean_video = Path(inpaint_info["clean_video"])
        show_subtitle = config.get("show_subtitle", True)
        bitrate = str(config.get("video_bitrate", "1.5M")).strip()

        rendered_video = workspace / "video_with_subtitles.mp4"

        if not show_subtitle:
            shutil.copy(str(clean_video), str(rendered_video))
        else:
            sub_file = Path(sub_info.get("ass_file") or sub_info["srt_file"])
            FFmpegUtils.burn_subtitles(clean_video, sub_file, rendered_video, bitrate=bitrate)

        return {
            "rendered_video": str(rendered_video)
        }
