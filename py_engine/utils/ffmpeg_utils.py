import os
import json
import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional


def ensure_system_path():
    """Ensure Homebrew and common binary directories are in PATH."""
    extra_paths = [
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
        os.path.expanduser("~/.local/bin"),
    ]
    current = os.environ.get("PATH", "")
    current_parts = current.split(os.pathsep) if current else []
    for p in extra_paths:
        if os.path.exists(p) and p not in current_parts:
            current = f"{p}{os.pathsep}{current}"
    os.environ["PATH"] = current


ensure_system_path()


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
    def demux(input_file: Path, video_out: Path, audio_out: Path, sub_out: Optional[Path] = None, duration: Optional[float] = None) -> None:
        """Demux input video into video stream and audio stream (and subtitle track if requested)."""
        dur_args = ["-t", f"{float(duration):.2f}"] if (duration and float(duration) > 0) else []

        # Extract Video
        cmd_v = [
            "ffmpeg", "-y", "-i", str(input_file)
        ] + dur_args + [
            "-an", "-sn", "-c:v", "copy", str(video_out)
        ]
        res_v = subprocess.run(cmd_v, capture_output=True)
        if res_v.returncode != 0 or not video_out.exists() or video_out.stat().st_size == 0:
            cmd_v_fallback = [
                "ffmpeg", "-y", "-i", str(input_file)
            ] + dur_args + [
                "-an", "-sn", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "ultrafast", str(video_out)
            ]
            subprocess.run(cmd_v_fallback, capture_output=True, check=True)

        # Extract Audio
        cmd_a = [
            "ffmpeg", "-y", "-i", str(input_file)
        ] + dur_args + [
            "-vn", "-sn", "-c:a", "pcm_s16le", str(audio_out)
        ]
        subprocess.run(cmd_a, capture_output=True, check=True)

        # Extract Subtitles if sub_out specified
        if sub_out:
            cmd_s = [
                "ffmpeg", "-y", "-i", str(input_file)
            ] + dur_args + [
                "-map", "0:s:0", str(sub_out)
            ]
            subprocess.run(cmd_s, capture_output=True, check=False)

    @staticmethod
    def get_hardware_h264_encoder() -> str:
        """Detect best available hardware encoder based on platform."""
        import sys
        if sys.platform == "darwin":
            return "h264_videotoolbox"
        elif sys.platform.startswith("win") or sys.platform.startswith("linux"):
            return "h264_nvenc"
        return "libx264"

    @staticmethod
    def trim_video(
        input_file: Path,
        output_file: Path,
        start_sec: Optional[float] = None,
        end_sec: Optional[float] = None,
        accurate: bool = False
    ) -> None:
        """
        Trim video from start_sec to end_sec.
        - If accurate=False: Tries stream copy first (<0.2s). If stream copy fails or snaps incorrectly due to Keyframe GOP, auto-fallbacks to accurate re-encode.
        - If accurate=True: Frame-accurate re-encode using HW acceleration (VideoToolbox/NVENC) with CPU (libx264 ultrafast) fallback.
        """
        s_val = float(start_sec) if (start_sec is not None and float(start_sec) > 0) else None
        e_val = float(end_sec) if (end_sec is not None and float(end_sec) > 0) else None
        expected_dur = (e_val - s_val) if (s_val is not None and e_val is not None) else None

        if not accurate:
            cmd = ["ffmpeg", "-y"]
            if s_val is not None:
                cmd.extend(["-ss", f"{s_val:.3f}"])
            cmd.extend(["-i", str(input_file)])
            if expected_dur is not None:
                cmd.extend(["-t", f"{expected_dur:.3f}"])
            elif e_val is not None:
                cmd.extend(["-t", f"{e_val:.3f}"])
            cmd.extend(["-c", "copy", "-avoid_negative_ts", "make_zero", str(output_file)])
            res = subprocess.run(cmd, capture_output=True)
            
            # Verify stream copy output quality & duration
            if res.returncode == 0 and output_file.exists() and output_file.stat().st_size > 0:
                if expected_dur is not None:
                    try:
                        probe_out = FFmpegUtils.probe(output_file)
                        out_dur = float(probe_out.get("format", {}).get("duration", 0))
                        # If duration difference is > 0.5s due to Keyframe snapping, stream copy is invalid -> fallback to accurate!
                        if abs(out_dur - expected_dur) > 0.5:
                            accurate = True
                    except Exception:
                        pass
                if not accurate:
                    return

        # Accurate Re-encode (HW Acceleration Tier 1 -> CPU libx264 Tier 2)
        hw_encoder = FFmpegUtils.get_hardware_h264_encoder()
        cmd_hw = ["ffmpeg", "-y"]
        if s_val is not None:
            cmd_hw.extend(["-ss", f"{s_val:.3f}"])
        cmd_hw.extend(["-i", str(input_file)])
        if expected_dur is not None:
            cmd_hw.extend(["-t", f"{expected_dur:.3f}"])
        elif e_val is not None:
            cmd_hw.extend(["-t", f"{e_val:.3f}"])
        cmd_hw.extend([
            "-c:v", hw_encoder, "-b:v", "4M", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k",
            str(output_file)
        ])
        res_hw = subprocess.run(cmd_hw, capture_output=True)
        if res_hw.returncode == 0 and output_file.exists() and output_file.stat().st_size > 0:
            return

        # Tier 2: CPU libx264 ultrafast (Universal fallback for all machines without GPU)
        cmd_sw = ["ffmpeg", "-y"]
        if s_val is not None:
            cmd_sw.extend(["-ss", f"{s_val:.3f}"])
        cmd_sw.extend(["-i", str(input_file)])
        if expected_dur is not None:
            cmd_sw.extend(["-t", f"{expected_dur:.3f}"])
        elif e_val is not None:
            cmd_sw.extend(["-t", f"{e_val:.3f}"])
        cmd_sw.extend([
            "-c:v", "libx264", "-preset", "ultrafast", "-b:v", "4M", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k",
            str(output_file)
        ])
        subprocess.run(cmd_sw, capture_output=True, check=True)


    @staticmethod
    def burn_subtitles(video_in: Path, sub_in: Path, video_out: Path, bitrate: str = "1.5M") -> None:
        """Burn subtitles (SRT/ASS) into video stream using Hardware Acceleration if available."""
        if not sub_in.exists() or sub_in.stat().st_size == 0:
            cmd = ["ffmpeg", "-y", "-i", str(video_in), "-c", "copy", str(video_out)]
            subprocess.run(cmd, capture_output=True, check=True)
            return

        sub_path_str = str(sub_in).replace(":", "\\:").replace("'", "'\\''")
        
        # Check if assets/fonts directory exists
        fonts_dir = Path(__file__).resolve().parent.parent.parent / "assets" / "fonts"
        fonts_param = ""
        if fonts_dir.exists() and any(fonts_dir.glob("*.ttf")):
            fdir_str = str(fonts_dir).replace(":", "\\:").replace("'", "'\\''")
            fonts_param = f":fontsdir='{fdir_str}'"

        sub_filter_hw = f"subtitles=filename='{sub_path_str}'{fonts_param},format=nv12"
        sub_filter_sw = f"subtitles=filename='{sub_path_str}'{fonts_param}"
        
        # Try Apple Silicon VideoToolbox Hardware Encoder first (requires format=nv12 for subtitle filter output)
        cmd_hw = [
            "ffmpeg", "-y", "-i", str(video_in),
            "-vf", sub_filter_hw,
            "-c:v", "h264_videotoolbox", "-b:v", str(bitrate),
            "-c:a", "copy",
            str(video_out)
        ]
        try:
            subprocess.run(cmd_hw, capture_output=True, check=True)
        except Exception:
            # Fallback to libx264 ultrafast preset if hardware encoder fails
            cmd_sw = [
                "ffmpeg", "-y", "-i", str(video_in),
                "-vf", sub_filter_sw,
                "-c:v", "libx264", "-preset", "ultrafast", "-b:v", str(bitrate),
                "-c:a", "copy",
                str(video_out)
            ]
            subprocess.run(cmd_sw, capture_output=True, check=True)

    @staticmethod
    def mix_audio(
        music_path: Path,
        voice_path: Path,
        output_path: Path,
        ambient_path: Optional[Path] = None,
        effect_path: Optional[Path] = None,
        target_duration: Optional[float] = None,
        music_volume: float = 0.5,
        ambient_volume: float = 0.75,
        voice_volume: float = 1.0,
        orig_voice_path: Optional[Path] = None,
        orig_voice_volume: float = 0.0
    ) -> None:
        """Mix background music + ambient + effects + translated voice + optional original voice using ffmpeg amix with volume control."""
        inputs = []
        filter_parts = []
        count = 0

        if voice_path and voice_path.exists() and voice_path.stat().st_size > 0 and voice_volume > 0.0:
            inputs.extend(["-i", str(voice_path)])
            filter_parts.append(f"[{count}:a]volume={voice_volume:.2f}[v{count}]")
            count += 1

        if music_path and music_path.exists() and music_path.stat().st_size > 0 and music_volume > 0.0:
            inputs.extend(["-i", str(music_path)])
            filter_parts.append(f"[{count}:a]volume={music_volume:.2f}[v{count}]")
            count += 1

        if ambient_path and ambient_path.exists() and ambient_path.stat().st_size > 0 and ambient_volume > 0.0:
            inputs.extend(["-i", str(ambient_path)])
            filter_parts.append(f"[{count}:a]volume={ambient_volume:.2f}[v{count}]")
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
        amix_filter = f"{amix_inputs}amix=inputs={count}:duration=longest:dropout_transition=2:normalize=0[aout]"
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
    def encode_final(video_in: Path, audio_in: Path, output_file: Path, bitrate: str = "1.5M") -> None:
        """Combine final video stream and audio stream into MP4 container with H.264 & AAC compatible codecs."""
        probe_info = FFmpegUtils.probe(video_in)
        video_codec = None
        for s in probe_info.get("streams", []):
            if s.get("codec_type") == "video":
                video_codec = s.get("codec_name")
                break

        # If already standard h264, use fast stream copy (completes in ~0.1s)
        if video_codec in ("h264", "avc1"):
            cmd_copy = [
                "ffmpeg", "-y",
                "-i", str(video_in),
                "-i", str(audio_in),
                "-c:v", "copy",
                "-c:a", "aac",
                "-map", "0:v:0",
                "-map", "1:a:0",
                "-shortest",
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
            "-c:v", "h264_videotoolbox", "-b:v", str(bitrate), "-pix_fmt", "yuv420p",
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
                "-c:v", "libx264", "-preset", "fast", "-b:v", str(bitrate), "-pix_fmt", "yuv420p",
                "-c:a", "aac",
                "-map", "0:v:0",
                "-map", "1:a:0",
                str(output_file)
            ]
            subprocess.run(cmd_sw, capture_output=True, check=True)

    @staticmethod
    def fused_render_and_encode(
        clean_video: Path,
        sub_file: Optional[Path],
        audio_file: Optional[Path],
        output_file: Path,
        bitrate: str = "1.5M"
    ) -> None:
        """Single-pass Fused Render: Burns ASS subtitles and muxes audio in 1 HW encode command (~2s)."""
        hw_encoder = FFmpegUtils.get_hardware_h264_encoder()
        cmd = ["ffmpeg", "-y", "-i", str(clean_video)]
        has_audio = bool(audio_file and audio_file.exists() and audio_file.stat().st_size > 0)
        if has_audio:
            cmd.extend(["-i", str(audio_file)])

        if sub_file and sub_file.exists():
            ass_path_escaped = str(sub_file.absolute()).replace("\\", "/").replace(":", "\\:")
            cmd.extend(["-vf", f"ass='{ass_path_escaped}'"])

        cmd.extend([
            "-c:v", hw_encoder, "-b:v", str(bitrate), "-pix_fmt", "yuv420p"
        ])
        if has_audio:
            cmd.extend(["-c:a", "aac", "-b:a", "192k", "-map", "0:v:0", "-map", "1:a:0", "-shortest"])
        else:
            cmd.extend(["-an"])

        cmd.append(str(output_file))
        res = subprocess.run(cmd, capture_output=True)
        if res.returncode == 0 and output_file.exists() and output_file.stat().st_size > 0:
            return

        # CPU Fallback
        cmd_cpu = ["ffmpeg", "-y", "-i", str(clean_video)]
        if has_audio:
            cmd_cpu.extend(["-i", str(audio_file)])
        if sub_file and sub_file.exists():
            ass_path_escaped = str(sub_file.absolute()).replace("\\", "/").replace(":", "\\:")
            cmd_cpu.extend(["-vf", f"ass='{ass_path_escaped}'"])
        cmd_cpu.extend(["-c:v", "libx264", "-preset", "ultrafast", "-b:v", str(bitrate), "-pix_fmt", "yuv420p"])
        if has_audio:
            cmd_cpu.extend(["-c:a", "aac", "-b:a", "192k", "-map", "0:v:0", "-map", "1:a:0", "-shortest"])
        else:
            cmd_cpu.extend(["-an"])
        cmd_cpu.append(str(output_file))
        subprocess.run(cmd_cpu, capture_output=True, check=True)

    @staticmethod
    def extract_frames(
        video_file: Path,
        output_dir: Path,
        duration: float = 5.0,
        start_time: float = 0.0,
        fps: float = 1.0,
        img_format: str = "png"
    ) -> List[Path]:
        """Extract frames from video for a specified time range into output_dir."""
        output_dir.mkdir(parents=True, exist_ok=True)
        stem = video_file.stem
        out_pattern = output_dir / f"{stem}_frame_%03d.{img_format}"

        cmd = [
            "ffmpeg", "-y",
            "-ss", str(start_time),
            "-i", str(video_file),
            "-t", str(duration)
        ]

        if fps > 0:
            cmd.extend(["-vf", f"fps={fps}"])

        cmd.append(str(out_pattern))

        subprocess.run(cmd, capture_output=True, check=True)
        return sorted(list(output_dir.glob(f"{stem}_frame_*.{img_format}")))

    @staticmethod
    def apply_watermark(
        input_video: Path,
        output_video: Path,
        config: Dict[str, Any],
        width: Optional[int] = None,
        height: Optional[int] = None
    ) -> bool:
        """
        Applies watermark (image logo or text branding + optional glassmorphism blur background)
        to input_video and saves to output_video.
        """
        wm_cfg = config.get("watermark") if isinstance(config.get("watermark"), dict) else {}
        wm_enable = bool(
            config.get("watermark_enable") if config.get("watermark_enable") is not None
            else (wm_cfg.get("enabled") if wm_cfg.get("enabled") is not None else False)
        )
        wm_region = config.get("watermark_region") or wm_cfg.get("region")
        wm_image = str(config.get("watermark_image") or wm_cfg.get("image") or "").strip()
        wm_text = str(config.get("watermark_text") or wm_cfg.get("text") or "").strip()
        wm_blur_bg = bool(config.get("watermark_blur_bg") if config.get("watermark_blur_bg") is not None else wm_cfg.get("blur_bg", True))
        wm_opacity = float(config.get("watermark_opacity") or wm_cfg.get("opacity") or 0.8)
        wm_font_color = str(config.get("watermark_font_color") or wm_cfg.get("font_color") or "white").strip()
        wm_font_name = str(config.get("watermark_font_name") or wm_cfg.get("font_name") or "Arial").strip() or "Arial"

        wm_active = bool(wm_enable) and bool(wm_image or wm_text)
        if not wm_active:
            return False

        if not width or not height:
            try:
                probe = FFmpegUtils.probe(input_video)
                for s in probe.get("streams", []):
                    if s.get("codec_type") == "video":
                        width = int(s.get("width") or 1920)
                        height = int(s.get("height") or 1080)
                        break
            except Exception:
                pass

        width = int(width or 1920)
        height = int(height or 1080)

        wm_top, wm_left, wm_bottom, wm_right = wm_region if (wm_region and len(wm_region) == 4) else [0.02, 0.65, 0.08, 0.95]
        wx = int(width * wm_left) & ~1
        wy = int(height * wm_top) & ~1
        ww = int(width * (wm_right - wm_left)) & ~1
        wh = int(height * (wm_bottom - wm_top)) & ~1

        wx = max(0, min(width - 2, wx))
        wy = max(0, min(height - 2, wy))
        ww = max(2, min(width - wx, ww))
        wh = max(2, min(height - wy, wh))

        wm_img_path = None
        if wm_image:
            p = Path(wm_image)
            if p.exists() and p.is_file():
                wm_img_path = p
            else:
                ws_dir_str = str(config.get("workspace_dir", ""))
                if ws_dir_str:
                    proj_dir = Path(ws_dir_str).parent
                    p_alt = proj_dir / wm_image
                    if p_alt.exists() and p_alt.is_file():
                        wm_img_path = p_alt
                if not wm_img_path:
                    p_alt2 = input_video.parent.parent.parent / wm_image
                    if p_alt2.exists() and p_alt2.is_file():
                        wm_img_path = p_alt2

        has_wm_img = wm_img_path is not None and wm_img_path.exists()

        inputs = ["-i", str(input_video)]
        if has_wm_img:
            inputs.extend(["-i", str(wm_img_path)])

        filters = []
        last_stream = "[0:v]"

        if wm_blur_bg:
            wm_blur_filter = (
                f"split[wm_m][wm_tb];"
                f"[wm_tb]crop={ww}:{wh}:{wx}:{wy},scale=iw/4:ih/4,avgblur=3,scale={ww}:{wh}:flags=bilinear[wm_bl];"
                f"[wm_m][wm_bl]overlay={wx}:{wy}"
            )
            filters.append(f"{last_stream}{wm_blur_filter}[v_wm_bg]")
            last_stream = "[v_wm_bg]"

        if has_wm_img:
            if wm_left >= 0.5:
                w_right = int(width * wm_right)
                overlay_x = f"{w_right}-overlay_w"
            else:
                overlay_x = f"{wx}"

            logo_filter = (
                f"[1:v]scale=-2:{wh},format=rgba,"
                f"colorchannelmixer=aa={wm_opacity:.2f}[logo];"
                f"{last_stream}[logo]overlay={overlay_x}:{wy}"
            )
            filters.append(f"{logo_filter}[v_wm_out]")
            last_stream = "[v_wm_out]"
        elif wm_text:
            wm_fontsize = max(12, int(wh * 0.65))
            escaped_text = wm_text.replace(":", "\\:").replace("'", "\\'")
            
            fonts_dir = Path(__file__).resolve().parent.parent.parent / "assets" / "fonts"
            font_param = ""
            if wm_font_name:
                matched_ttf = None
                if fonts_dir.exists():
                    for ttf in fonts_dir.glob("*.ttf"):
                        if wm_font_name.lower().replace(" ", "") in ttf.stem.lower().replace(" ", "").replace("-", ""):
                            matched_ttf = ttf
                            break
                if matched_ttf:
                    fpath_str = str(matched_ttf).replace(":", "\\:").replace("'", "'\\''")
                    font_param = f":fontfile='{fpath_str}'"
                else:
                    font_param = f":font='{wm_font_name}'"

            # Safe center positioning with boundary clamping
            pos_x = f"max(8, min(w-text_w-8, {wx}+({ww}-text_w)/2))"
            pos_y = f"max(8, min(h-text_h-8, {wy}+({wh}-text_h)/2))"
            drawtext_str = f"drawtext=text='{escaped_text}'{font_param}:fontcolor={wm_font_color}@{wm_opacity:.2f}:fontsize={wm_fontsize}:x='{pos_x}':y='{pos_y}'"
            filters.append(f"{last_stream}{drawtext_str}[v_wm_out]")
            last_stream = "[v_wm_out]"

        filters.append(f"{last_stream}format=nv12[v_final_out]")
        last_stream = "[v_final_out]"

        filter_complex = ";".join(filters)
        bitrate = str(config.get("video_bitrate", "4.0M")).strip()

        cmd_hw = [
            "ffmpeg", "-y"
        ] + inputs + [
            "-filter_complex", filter_complex,
            "-map", last_stream,
            "-c:v", "h264_videotoolbox",
            "-b:v", bitrate,
            "-c:a", "copy",
            str(output_video)
        ]

        res = subprocess.run(cmd_hw, capture_output=True, text=True)
        if res.returncode != 0 or not output_video.exists() or output_video.stat().st_size == 0:
            cmd_sw = [
                "ffmpeg", "-y"
            ] + inputs + [
                "-filter_complex", filter_complex,
                "-map", last_stream,
                "-c:v", "libx264", "-preset", "ultrafast", "-b:v", bitrate,
                "-c:a", "copy",
                str(output_video)
            ]
            res2 = subprocess.run(cmd_sw, capture_output=True, text=True)
            if res2.returncode != 0 or not output_video.exists() or output_video.stat().st_size == 0:
                raise RuntimeError(f"FFmpeg watermark application failed: {res2.stderr}")

        return True


