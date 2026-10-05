import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

from plugins.interfaces import InpaintBase
from utils.ffmpeg_utils import FFmpegUtils
from utils.safe_cast import safe_int


class Plugin(InpaintBase):
    """
    FFmpeg Box/Avg Blur Inpaint Plugin.
    Applies high-speed hardware-accelerated box blur to target subtitle regions.
    """

    def remove_subtitles(
        self,
        video_path: Path,
        region: List[float],
        output_video: Path,
        segments: Optional[List[Dict[str, Any]]] = None,
        sub_path: Optional[Path] = None,
        watermark_config: Optional[Dict[str, Any]] = None
    ) -> Path:
        data = FFmpegUtils.probe(video_path)
        vstream = next((s for s in data.get("streams", []) if s.get("codec_type") == "video"), None)
        if not vstream:
            raise RuntimeError(f"No video stream found in: {video_path}")

        width = int(vstream.get("width") or 1920)
        height = int(vstream.get("height") or 1080)

        # 1. Subtitle Inpaint Region Coordinates
        ymin, xmin, ymax, xmax = region if (region and len(region) == 4) else [0.80, 0.10, 0.92, 0.90]
        rx = int(width * xmin) & ~1
        ry = int(height * ymin) & ~1
        rw = int(width * (xmax - xmin)) & ~1
        rh = int(height * (ymax - ymin)) & ~1

        rx = max(0, min(width - 2, rx))
        ry = max(0, min(height - 2, ry))
        rw = max(2, min(width - rx, rw))
        rh = max(2, min(height - ry, rh))

        blur_radius = safe_int(self.config.get("blur_radius") or self.config.get("inpaint_blur_radius"), 15)

        inputs = ["-i", str(video_path)]
        filters = []
        last_stream = "[0:v]"

        enable_expr = ""
        if segments:
            raw_intervals = []
            for seg in segments:
                try:
                    s_start = float(seg.get("start", 0.0))
                    s_end = float(seg.get("end", 0.0))
                    if s_end > s_start:
                        # Add slight temporal safety padding (±0.08s) to cover hardsub appearance & disappearance
                        s_pad = max(0.0, s_start - 0.08)
                        e_pad = s_end + 0.08
                        raw_intervals.append((s_pad, e_pad))
                except (ValueError, TypeError):
                    continue

            if raw_intervals:
                raw_intervals.sort(key=lambda x: x[0])
                merged = []
                for s, e in raw_intervals:
                    if not merged:
                        merged.append([s, e])
                    else:
                        # Seamlessly merge if intervals overlap or gap is negligible (<= 0.20s)
                        if s <= merged[-1][1] + 0.20:
                            merged[-1][1] = max(merged[-1][1], e)
                        else:
                            merged.append([s, e])

                enable_terms = [f"between(t,{s:.3f},{e:.3f})" for s, e in merged]
                enable_expr = "+".join(enable_terms)

        inpaint_engine = str(self.config.get("inpaint", "box_color")).lower()
        inpaint_color = str(self.config.get("inpaint_color", "transparent")).strip()
        box_cfg = self.config.get("inpaint_box") or self.config.get("box") or {}
        if not isinstance(box_cfg, dict):
            box_cfg = {}

        is_box_color = (inpaint_engine in ["box_color", "box"]) or (inpaint_color.lower() not in ["transparent", "", "none"])

        if is_box_color:
            # In box_color mode, dynamic rounded boxes with borders are rendered per-dialogue in s09/s11 ASS burning.
            # We avoid drawing a static whole-video drawbox so the video remains clean when there is no speech.
            pass
        else:
            # High-speed glassmorphism blur: downscale 4x -> light blur -> bilinear upscale (15-20x speedup)
            enable_attr = f":enable='{enable_expr}'" if enable_expr else ""
            inpaint_str = (
                f"split[main][to_blur];"
                f"[to_blur]crop={rw}:{rh}:{rx}:{ry},scale=iw/4:ih/4,avgblur=4,scale={rw}:{rh}:flags=bilinear[blurred];"
                f"[main][blurred]overlay={rx}:{ry}{enable_attr}"
            )
            filters.append(f"{last_stream}{inpaint_str}[v_inpainted]")
            last_stream = "[v_inpainted]"

        # Subtitle burning (if sub_path provided)
        if sub_path and sub_path.exists() and sub_path.stat().st_size > 0:
            escaped_sub = str(sub_path).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
            filters.append(f"{last_stream}subtitles='{escaped_sub}'[v_sub_out]")
            last_stream = "[v_sub_out]"

        # Watermark integration (Single-Pass optimization)
        if watermark_config and watermark_config.get("enabled"):
            last_stream, wm_filters = FFmpegUtils.build_watermark_filters(
                last_stream=last_stream,
                width=width,
                height=height,
                watermark_config=watermark_config,
                inputs=inputs
            )
            filters.extend(wm_filters)

        if not filters:
            # Direct copy when no visual inpaint filter is needed
            shutil.copy(str(video_path), str(output_video))
            return output_video

        # Format output to NV12 for direct zero-copy Apple Silicon VideoToolbox Hardware Encoder
        filters.append(f"{last_stream}format=nv12[v_final_out]")
        last_stream = "[v_final_out]"

        filter_complex = ";".join(filters)

        bitrate = str(self.config.get("video_bitrate", "4.0M")).strip()

        # Try Hardware Encoder first for speed and configured bitrate, fallback to CPU ultrafast
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

        result = subprocess.run(cmd_hw, capture_output=True, text=True)
        if result.returncode != 0 or not output_video.exists() or output_video.stat().st_size == 0:
            cmd_sw = [
                "ffmpeg", "-y"
            ] + inputs + [
                "-filter_complex", filter_complex,
                "-map", last_stream,
                "-c:v", "libx264", "-preset", "ultrafast", "-b:v", bitrate,
                "-c:a", "copy",
                str(output_video)
            ]
            result = subprocess.run(cmd_sw, capture_output=True, text=True)
            if result.returncode != 0 or not output_video.exists() or output_video.stat().st_size == 0:
                raise RuntimeError(f"FFmpeg blur inpaint failed: {result.stderr}")

        return output_video
