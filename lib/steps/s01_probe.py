import json
from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase
from utils.ffmpeg_utils import FFmpegUtils


class StepProbe(StepBase):
    step_id = "s01_probe"
    depends_on = []

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        input_video = Path(job_state.data["input_video"])
        if not input_video.exists():
            raise FileNotFoundError(f"Input video file not found: {input_video}")

        probe_data = FFmpegUtils.probe(input_video)
        
        # Analyze streams
        streams = probe_data.get("streams", [])
        video_stream = next((s for s in streams if s.get("codec_type") == "video"), None)
        audio_streams = [s for s in streams if s.get("codec_type") == "audio"]
        sub_streams = [s for s in streams if s.get("codec_type") == "subtitle"]

        format_data = probe_data.get("format", {})
        
        summary = {
            "duration": float(format_data.get("duration", 0)),
            "size_bytes": int(format_data.get("size", 0)),
            "fps": eval(video_stream.get("r_frame_rate", "24/1")) if video_stream else 24.0,
            "width": int(video_stream.get("width", 0)) if video_stream else 0,
            "height": int(video_stream.get("height", 0)) if video_stream else 0,
            "has_audio": len(audio_streams) > 0,
            "has_embedded_subtitles": len(sub_streams) > 0,
            "subtitle_count": len(sub_streams)
        }

        # Save probe result
        out_file = workspace / "s01_probe.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(summary, f, ensure_ascii=False, indent=2)

        return summary
