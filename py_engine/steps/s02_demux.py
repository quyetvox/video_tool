from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase
from utils.ffmpeg_utils import FFmpegUtils


class StepDemux(StepBase):
    step_id = "s02_demux"
    depends_on = ["s01_probe"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        input_video = Path(job_state.data["input_video"])
        probe_info = job_state.get_step_output("s01_probe") or {}

        demux_dir = workspace / "demux"
        demux_dir.mkdir(parents=True, exist_ok=True)

        video_out = demux_dir / "video_stream.mp4"
        audio_out = demux_dir / "audio_stream.wav"
        sub_out = demux_dir / "embedded_sub.srt" if probe_info.get("has_embedded_subtitles") else None

        duration = config.get("duration")
        if duration is not None:
            duration = float(duration)

        FFmpegUtils.demux(input_video, video_out, audio_out, sub_out if (sub_out and sub_out.exists()) else None, duration=duration)

        output = {
            "video_stream": str(video_out),
            "audio_stream": str(audio_out),
            "embedded_sub": str(sub_out) if (sub_out and sub_out.exists()) else None
        }

        return output
