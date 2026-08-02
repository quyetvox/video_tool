import shutil
from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase
from utils.ffmpeg_utils import FFmpegUtils


class StepEncode(StepBase):
    step_id = "s14_encode"
    depends_on = ["s11_subtitle_render", "s13_audio_mix"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        render_info = job_state.get_step_output("s11_subtitle_render") or {}
        mix_info = job_state.get_step_output("s13_audio_mix") or {}

        rendered_video = Path(render_info["rendered_video"])
        mixed_audio = Path(mix_info["mixed_audio"])

        input_video = Path(job_state.data["input_video"])
        suffix = config.get("output_suffix", "_vi")
        output_name = f"{input_video.stem}{suffix}.mp4"

        output_file = workspace / output_name
        FFmpegUtils.encode_final(rendered_video, mixed_audio, output_file)

        final_output = str(output_file)
        output_dir_str = config.get("output_dir", "output")
        if output_dir_str:
            output_dir = Path(output_dir_str).resolve()
            output_dir.mkdir(parents=True, exist_ok=True)
            target_file = output_dir / output_name
            shutil.copy(str(output_file), str(target_file))
            final_output = str(target_file)

        return {
            "output_file": final_output,
            "filename": output_name,
            "workspace_output_file": str(output_file)
        }

