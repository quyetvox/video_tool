import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

from plugins.interfaces import InpaintBase
from utils.ffmpeg_utils import FFmpegUtils


class Plugin(InpaintBase):
    """
    FFmpeg Box/Avg Blur Inpaint & Watermark Plugin.
    Applies high-speed hardware-accelerated box blur to target subtitle regions,
    and overlays Image / Text Watermarks with optional background blur in a single pass.
    """

    def remove_subtitles(
        self,
        video_path: Path,
        region: List[float],
        output_video: Path,
        segments: Optional[List[Dict[str, Any]]] = None,
        sub_path: Optional[Path] = None
    ) -> Path:
        data = FFmpegUtils.probe(video_path)
        vstream = next((s for s in data.get("streams", []) if s.get("codec_type") == "video"), None)
        if not vstream:
            raise RuntimeError(f"No video stream found in: {video_path}")

        width = int(vstream.get("width", 1920))
        height = int(vstream.get("height", 1080))

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

        blur_radius = int(self.config.get("blur_radius", 15))

        # 2. Watermark Config Settings
        wm_enable = self.config.get("watermark_enable", False)
        wm_region = self.config.get("watermark_region")
        wm_image = str(self.config.get("watermark_image", "")).strip()
        wm_text = str(self.config.get("watermark_text", "")).strip()
        wm_blur_bg = self.config.get("watermark_blur_bg", True)
        wm_opacity = float(self.config.get("watermark_opacity", 0.8))
        wm_font_color = str(self.config.get("watermark_font_color", "white")).strip()

        wm_active = bool(wm_enable) and bool(wm_image or wm_text)
        wm_img_path = None
        if wm_image:
            p = Path(wm_image)
            if p.exists() and p.is_file():
                wm_img_path = p
            else:
                ws_dir_str = str(self.config.get("workspace_dir", ""))
                if ws_dir_str:
                    proj_dir = Path(ws_dir_str).parent
                    p_alt = proj_dir / wm_image
                    if p_alt.exists() and p_alt.is_file():
                        wm_img_path = p_alt
                if not wm_img_path:
                    p_alt2 = video_path.parent.parent.parent / wm_image
                    if p_alt2.exists() and p_alt2.is_file():
                        wm_img_path = p_alt2

        has_wm_img = wm_img_path is not None and wm_img_path.exists()

        inputs = ["-i", str(video_path)]
        if wm_active and has_wm_img:
            inputs.extend(["-i", str(wm_img_path)])

        filters = []
        last_stream = "[0:v]"

        # Always use Filter A (Static Region Blur) on inpaint_region so blur box and subtitles share exact same region
        valid_seg_bboxes = []

        if valid_seg_bboxes:
            # Cluster segments with similar Y coordinates to create tight-fitting blur boxes
            # (tight padding of +-0.008 Y height around original subtitle text)
            clusters = []
            for s_start, s_end, sb in valid_seg_bboxes:
                ymin_p = max(0.0, sb[0] - 0.008)
                ymax_p = min(1.0, sb[2] + 0.008)

                # Try to find an existing cluster with close Y bounds (within 0.03)
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

            effective_blur = max(int(blur_radius), 25)

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
                    f"[to_blur_{c_idx}]crop={s_rw}:{s_rh}:{s_rx}:{s_ry},avgblur={effective_blur}[blurred_{c_idx}];"
                    f"[main_{c_idx}][blurred_{c_idx}]overlay={s_rx}:{s_ry}:enable='{enable_expr}'"
                )
                filters.append(f"{last_stream}{inpaint_str}[v_inp_{c_idx}]")
                last_stream = f"[v_inp_{c_idx}]"
        else:
            # Filter A (Static): Single region blur for whole video
            effective_blur = max(int(blur_radius), 25)
            inpaint_str = f"split[main][to_blur];[to_blur]crop={rw}:{rh}:{rx}:{ry},avgblur={effective_blur}[blurred];[main][blurred]overlay={rx}:{ry}"
            filters.append(f"{last_stream}{inpaint_str}[v_inpainted]")
            last_stream = "[v_inpainted]"

        # Filter B: Watermark processing (Image or Text)
        if wm_active:
            wm_top, wm_left, wm_bottom, wm_right = wm_region if (wm_region and len(wm_region) == 4) else [0.02, 0.65, 0.08, 0.95]
            wx = int(width * wm_left) & ~1
            wy = int(height * wm_top) & ~1
            ww = int(width * (wm_right - wm_left)) & ~1
            wh = int(height * (wm_bottom - wm_top)) & ~1

            wx = max(0, min(width - 2, wx))
            wy = max(0, min(height - 2, wy))
            ww = max(2, min(width - wx, ww))
            wh = max(2, min(height - wy, wh))

            if wm_blur_bg:
                wm_blur_filter = f"split[wm_m][wm_tb];[wm_tb]crop={ww}:{wh}:{wx}:{wy},avgblur={blur_radius}[wm_bl];[wm_m][wm_bl]overlay={wx}:{wy}"
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
                drawtext_str = f"drawtext=text='{escaped_text}':fontcolor={wm_font_color}@{wm_opacity:.2f}:fontsize={wm_fontsize}:x={wx}+({ww}-text_w)/2:y={wy}+({wh}-text_h)/2"
                filters.append(f"{last_stream}{drawtext_str}[v_wm_out]")
                last_stream = "[v_wm_out]"

        # Filter C: Subtitle burning (if sub_path provided)
        if sub_path and sub_path.exists() and sub_path.stat().st_size > 0:
            escaped_sub = str(sub_path).replace(":", "\\:").replace("'", "'\\''")
            filters.append(f"{last_stream}subtitles='{escaped_sub}'[v_sub_out]")
            last_stream = "[v_sub_out]"

        filter_complex = ";".join(filters)

        # Try Hardware Encoder first for speed and optimized ~4M bitrate, fallback to CPU ultrafast
        cmd_hw = [
            "ffmpeg", "-y"
        ] + inputs + [
            "-filter_complex", filter_complex,
            "-map", last_stream,
            "-c:v", "h264_videotoolbox", "-b:v", "4M",
            str(output_video)
        ]

        result = subprocess.run(cmd_hw, capture_output=True, text=True)
        if result.returncode != 0 or not output_video.exists() or output_video.stat().st_size == 0:
            cmd_sw = [
                "ffmpeg", "-y"
            ] + inputs + [
                "-filter_complex", filter_complex,
                "-map", last_stream,
                "-c:v", "libx264", "-preset", "ultrafast", "-b:v", "4M",
                str(output_video)
            ]
            result = subprocess.run(cmd_sw, capture_output=True, text=True)
            if result.returncode != 0 or not output_video.exists() or output_video.stat().st_size == 0:
                raise RuntimeError(f"FFmpeg blur inpaint & watermark failed: {result.stderr}")

        return output_video
