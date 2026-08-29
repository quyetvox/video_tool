import shutil
from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase
from utils.ffmpeg_utils import FFmpegUtils


class StepEncode(StepBase):
    step_id = "s14_encode"
    depends_on = ["s11_subtitle_render", "s13_audio_mix"]
    STEP_CONFIG_KEYS = ["output_suffix", "output_dir", "video_bitrate"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        render_info = job_state.get_step_output("s11_subtitle_render") or {}
        mix_info = job_state.get_step_output("s13_audio_mix") or {}
        demux_info = job_state.get_step_output("s02_demux") or {}

        rendered_video = Path(render_info.get("rendered_video") or workspace / "video_with_subtitles.mp4")
        
        # Resolve audio file safely across voice translator and ocr_only subtitle translator modes
        mixed_audio_str = mix_info.get("mixed_audio")
        if mixed_audio_str and Path(mixed_audio_str).exists() and Path(mixed_audio_str).stat().st_size > 0:
            mixed_audio = Path(mixed_audio_str)
        elif demux_info.get("audio_stream") and Path(demux_info["audio_stream"]).exists():
            mixed_audio = Path(demux_info["audio_stream"])
        elif (workspace / "audio_stream.wav").exists():
            mixed_audio = workspace / "audio_stream.wav"
        else:
            mixed_audio = None

        input_video_val = job_state.data.get("input_video")
        if input_video_val:
            input_video = Path(input_video_val)
        else:
            stem_guess = workspace.name.replace("job_", "")
            input_video = Path(workspace.parent.parent / "src" / f"{stem_guess}.mp4")

        duration = config.get("duration")
        dur_tag = f"_{int(duration)}s" if (duration and float(duration) > 0) else ""

        base_suffix = config.get("output_suffix", "_vi")
        if dur_tag and dur_tag not in base_suffix:
            suffix = f"{dur_tag}{base_suffix}"
        else:
            suffix = base_suffix

        output_name = f"{input_video.stem}{suffix}.mp4"
        output_file = workspace / output_name
        bitrate = str(config.get("video_bitrate", "1.5M")).strip()

        print(f"[Encode Final] Finalizing output '{output_name}' with fast hardware muxing...", flush=True)
        FFmpegUtils.encode_final(rendered_video, mixed_audio, output_file, bitrate=bitrate)

        final_output = str(output_file)
        output_dir_str = config.get("output_dir") or str(workspace.parent.parent / "output")
        if output_dir_str:
            output_dir = Path(output_dir_str).resolve()
            output_dir.mkdir(parents=True, exist_ok=True)
            target_file = output_dir / output_name
            shutil.move(str(output_file), str(target_file))
            final_output = str(target_file)

        # Cleanup test_speed files in workspace if any
        for test_file in workspace.glob("test_speed*.mp4"):
            try:
                test_file.unlink()
            except Exception:
                pass

        return {
            "output_file": final_output,
            "filename": output_name,
            "workspace_output_file": final_output
        }
