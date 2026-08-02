import json
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional


class FFmpegUtils:
    @staticmethod
    def probe(input_file: Path) -> Dict[str, Any]:
        """Run ffprobe on an input video file and return JSON stream metadata."""
        cmd = [
            "ffprobe",
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            str(input_file)
        ]
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    @staticmethod
    def get_audio_duration(audio_file: Path) -> float:
        """Get exact duration in seconds of an audio file using ffprobe."""
        try:
            cmd = [
                "ffprobe", "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                str(audio_file)
            ]
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return float(res.stdout.strip())
        except Exception:
            return 1.0

    @staticmethod
    def demux(input_file: Path, video_out: Path, audio_out: Path, sub_out: Optional[Path] = None) -> None:
        """Demux input video into video stream and audio stream (and subtitle track if requested)."""
        # Extract Video
        cmd_v = [
            "ffmpeg", "-y", "-i", str(input_file),
            "-an", "-vn", "-c:v", "copy", str(video_out)
        ]
        # In ffmpeg, -vn disables video recording. We want video stream only:
        cmd_v = [
            "ffmpeg", "-y", "-i", str(input_file),
            "-an", "-sn", "-c:v", "copy", str(video_out)
        ]
        subprocess.run(cmd_v, capture_output=True, check=True)

        # Extract Audio
        cmd_a = [
            "ffmpeg", "-y", "-i", str(input_file),
            "-vn", "-sn", "-c:a", "pcm_s16le", str(audio_out)
        ]
        subprocess.run(cmd_a, capture_output=True, check=True)

        # Extract Subtitles if sub_out specified
        if sub_out:
            cmd_s = [
                "ffmpeg", "-y", "-i", str(input_file),
                "-map", "0:s:0", str(sub_out)
            ]
            subprocess.run(cmd_s, capture_output=True, check=False)

    @staticmethod
    def burn_subtitles(video_in: Path, sub_in: Path, video_out: Path) -> None:
        """Burn subtitles (SRT/ASS) into video stream using Hardware Acceleration if available."""
        if not sub_in.exists() or sub_in.stat().st_size == 0:
            cmd = ["ffmpeg", "-y", "-i", str(video_in), "-c", "copy", str(video_out)]
            subprocess.run(cmd, capture_output=True, check=True)
            return

        sub_path_str = str(sub_in).replace(":", "\\:").replace("'", "'\\''")
        
        # Try Apple Silicon VideoToolbox Hardware Encoder first
        cmd_hw = [
            "ffmpeg", "-y", "-i", str(video_in),
            "-vf", f"subtitles={sub_path_str}",
            "-c:v", "h264_videotoolbox", "-b:v", "4M",
            "-c:a", "copy",
            str(video_out)
        ]
        try:
            subprocess.run(cmd_hw, capture_output=True, check=True)
        except Exception:
            # Fallback to libx264 ultrafast preset if hardware encoder fails
            cmd_sw = [
                "ffmpeg", "-y", "-i", str(video_in),
                "-vf", f"subtitles={sub_path_str}",
                "-c:v", "libx264", "-preset", "ultrafast",
                "-c:a", "copy",
                str(video_out)
            ]
            subprocess.run(cmd_sw, capture_output=True, check=True)

    @staticmethod
    def mix_audio(
        music_path: Path,
        voice_path: Path,
        output_path: Path,
        effect_path: Optional[Path] = None,
        target_duration: Optional[float] = None,
        music_volume: float = 0.8,
        voice_volume: float = 1.0,
        orig_voice_path: Optional[Path] = None,
        orig_voice_volume: float = 0.0
    ) -> None:
        """Mix background music + effects + translated voice + optional original voice using ffmpeg amix with volume control."""
        inputs = []
        filter_parts = []
        count = 0

        if voice_path.exists() and voice_path.stat().st_size > 0:
            inputs.extend(["-i", str(voice_path)])
            filter_parts.append(f"[{count}:a]volume={voice_volume:.2f}[v{count}]")
            count += 1

        if music_path.exists() and music_path.stat().st_size > 0 and music_volume > 0.0:
            inputs.extend(["-i", str(music_path)])
            filter_parts.append(f"[{count}:a]volume={music_volume:.2f}[v{count}]")
            count += 1

        if orig_voice_path and orig_voice_path.exists() and orig_voice_path.stat().st_size > 0 and orig_voice_volume > 0.0:
            inputs.extend(["-i", str(orig_voice_path)])
            filter_parts.append(f"[{count}:a]volume={orig_voice_volume:.2f}[v{count}]")
            count += 1

        if effect_path and effect_path.exists() and effect_path.stat().st_size > 0:
            inputs.extend(["-i", str(effect_path)])
            filter_parts.append(f"[{count}:a]volume=1.0[v{count}]")
            count += 1

        if count == 0:
            dur = f"{target_duration:.2f}" if target_duration else "1.00"
            cmd = ["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", dur, "-c:a", "pcm_s16le", str(output_path)]
            subprocess.run(cmd, capture_output=True, check=True)
            return

        if count == 1:
            cmd = ["ffmpeg", "-y"] + inputs
            v_filter = f"volume={voice_volume:.2f}"
            if target_duration:
                v_filter += f",apad=whole_dur={target_duration:.2f}"
            cmd.extend(["-af", v_filter])
            if target_duration:
                cmd.extend(["-t", f"{target_duration:.2f}"])
            cmd.extend(["-c:a", "pcm_s16le", str(output_path)])
            subprocess.run(cmd, capture_output=True, check=True)
            return

        # Multi-track mixing with volume filters
        amix_inputs = "".join([f"[v{i}]" for i in range(count)])
        amix_filter = f"{amix_inputs}amix=inputs={count}:duration=longest:dropout_transition=2[aout]"
        if target_duration:
            amix_filter += f";[aout]apad=whole_dur={target_duration:.2f}[afinal]"
            final_map = "[afinal]"
        else:
            final_map = "[aout]"

        filter_complex = ";".join(filter_parts) + ";" + amix_filter

        cmd = ["ffmpeg", "-y"] + inputs + ["-filter_complex", filter_complex, "-map", final_map]
        if target_duration:
            cmd.extend(["-t", f"{target_duration:.2f}"])
        cmd.extend(["-c:a", "pcm_s16le", str(output_path)])
        subprocess.run(cmd, capture_output=True, check=True)

    @staticmethod
    def encode_final(video_in: Path, audio_in: Path, output_file: Path) -> None:
        """Combine final video stream and audio stream into MP4 container with H.264 & AAC compatible codecs."""
        probe_info = FFmpegUtils.probe(video_in)
        video_codec = None
        for s in probe_info.get("streams", []):
            if s.get("codec_type") == "video":
                video_codec = s.get("codec_name")
                break

        # If already standard h264, use fast stream copy
        if video_codec == "h264":
            cmd_copy = [
                "ffmpeg", "-y",
                "-i", str(video_in),
                "-i", str(audio_in),
                "-c:v", "copy",
                "-c:a", "aac",
                "-map", "0:v:0",
                "-map", "1:a:0",
                str(output_file)
            ]
            res = subprocess.run(cmd_copy, capture_output=True, check=False)
            if res.returncode == 0 and output_file.exists() and output_file.stat().st_size > 0:
                return

        # Otherwise re-encode video to H.264 (Apple VideoToolbox HW encoder first, fallback libx264 yuv420p)
        cmd_hw = [
            "ffmpeg", "-y",
            "-i", str(video_in),
            "-i", str(audio_in),
            "-c:v", "h264_videotoolbox", "-b:v", "4M", "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-map", "0:v:0",
            "-map", "1:a:0",
            str(output_file)
        ]
        res_hw = subprocess.run(cmd_hw, capture_output=True, check=False)
        if res_hw.returncode != 0:
            cmd_sw = [
                "ffmpeg", "-y",
                "-i", str(video_in),
                "-i", str(audio_in),
                "-c:v", "libx264", "-preset", "fast", "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-map", "0:v:0",
                "-map", "1:a:0",
                str(output_file)
            ]
            subprocess.run(cmd_sw, capture_output=True, check=True)
