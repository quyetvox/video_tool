import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

from plugins.interfaces import InpaintBase
from utils.ffmpeg_utils import FFmpegUtils


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

        blur_radius = int(self.config.get("blur_radius") or self.config.get("inpaint_blur_radius") or 15)

        inputs = ["-i", str(video_path)]
        filters = []
        last_stream = "[0:v]"

        valid_seg_bboxes = []

        if valid_seg_bboxes:
            clusters = []
            for s_start, s_end, sb in valid_seg_bboxes:
                ymin_p = max(0.0, sb[0] - 0.008)
                ymax_p = min(1.0, sb[2] + 0.008)

                matched = False
                for c in clusters:
                    if abs(c["ymin"] - ymin_p) < 0.03 and abs(c["ymax"] - ymax_p) < 0.03:
                        c["ymin"] = min(c["ymin"], ymin_p)
                        c["ymax"] = max(c["ymax"], ymax_p)
                        c["segs"].append((s_start, s_end))
                        matched = True
                        break
                if not matched:
                    clusters.append({
                        "ymin": ymin_p,
                        "ymax": ymax_p,
                        "segs": [(s_start, s_end)]
                    })

            for c_idx, c in enumerate(clusters):
                dyn_ymin = c["ymin"]
                dyn_ymax = c["ymax"]
                dyn_xmin = 0.05
                dyn_xmax = 0.95

                s_rx = int(width * dyn_xmin) & ~1
                s_ry = int(height * dyn_ymin) & ~1
                s_rw = int(width * (dyn_xmax - dyn_xmin)) & ~1
                s_rh = int(height * (dyn_ymax - dyn_ymin)) & ~1

                s_rx = max(0, min(width - 2, s_rx))
                s_ry = max(0, min(height - 2, s_ry))
                s_rw = max(2, min(width - s_rx, s_rw))
                s_rh = max(2, min(height - s_ry, s_rh))

                enable_terms = [f"between(t,{s_start:.3f},{s_end:.3f})" for s_start, s_end in c["segs"]]
                enable_expr = "+".join(enable_terms)

                inpaint_str = (
                    f"split[main_{c_idx}][to_blur_{c_idx}];"
                    f"[to_blur_{c_idx}]crop={s_rw}:{s_rh}:{s_rx}:{s_ry},scale=iw/4:ih/4,avgblur=4,scale={s_rw}:{s_rh}:flags=bilinear[blurred_{c_idx}];"
                    f"[main_{c_idx}][blurred_{c_idx}]overlay={s_rx}:{s_ry}:enable='{enable_expr}'"
                )
                filters.append(f"{last_stream}{inpaint_str}[v_inp_{c_idx}]")
                last_stream = f"[v_inp_{c_idx}]"
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
            inpaint_str = (
                f"split[main][to_blur];"
                f"[to_blur]crop={rw}:{rh}:{rx}:{ry},scale=iw/4:ih/4,avgblur=4,scale={rw}:{rh}:flags=bilinear[blurred];"
                f"[main][blurred]overlay={rx}:{ry}"
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
