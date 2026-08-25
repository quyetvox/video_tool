import datetime
import json
from pathlib import Path
from typing import Any, Dict, List

from core.step_base import StepBase


class StepSubtitleGen(StepBase):
    step_id = "s09_subtitle_gen"
    depends_on = ["s03_subtitle_detect", "s08_translation", "s08c_timing"]
    STEP_CONFIG_KEYS = [
        "show_subtitle", "inpaint", "inpaint_region", "inpaint_box_bg_color", 
        "inpaint_box_bg_opacity", "inpaint_box_border_color", "inpaint_box_border_width", 
        "inpaint_box_border_radius", "subtitle_font_size", "subtitle_font_name", 
        "subtitle_font_color", "subtitle_outline_color", "blur_box_padding_y",
        "subtitle_box_lead_in", "subtitle_box_lead_out", "subtitle_max_gap_fill",
        "secondary_lang", "subtitle_order", "subtitle_box_split", "subtitle_box_gap",
        "subtitle_secondary_font_name", "subtitle_secondary_font_size_scale",
        "subtitle_secondary_font_color", "subtitle_secondary_outline_color"
    ]

    @staticmethod
    def _to_ass_color(color_str: str, default: str = "&H00FFFFFF") -> str:
        """Converts common color names or hex strings to ASS &HAABBGGRR format."""
        if not color_str:
            return default
        c = color_str.strip()
        if c.startswith("&H") or c.startswith("&h"):
            return c
        named_colors = {
            "white": "&H00FFFFFF",
            "yellow": "&H0000FFFF",  # ASS is BGR: 00 (alpha) FF (blue) FF (green) 00 (red) -> Yellow is 00FFFF
            "cyan": "&H00FFFF00",
            "red": "&H000000FF",
            "green": "&H0000FF00",
            "black": "&H00000000",
            "gold": "&H0000D7FF",
            "orange": "&H0000A5FF",
            "transparent": "&HFF000000",
            "lightgray": "&H00D0D0D0",
            "gray": "&H00808080",
        }
        if c.lower() in named_colors:
            return named_colors[c.lower()]
        if c.startswith("#") and len(c) == 7:
            r = c[1:3]
            g = c[3:5]
            b = c[5:7]
            return f"&H00{b}{g}{r}".upper()
        return default

    @staticmethod
    def _make_box_path(w: int, h: int, radius: int) -> str:
        """Generates ASS vector drawing commands for a rounded rectangle."""
        r = max(0, min(int(radius), h // 2, w // 2))
        if r <= 0:
            return f"m 0 0 l {w} 0 l {w} {h} l 0 {h}"
        return f"m {r} 0 l {w-r} 0 b {w} 0 {w} 0 {w} {r} l {w} {h-r} b {w} {h} {w} {h} {w-r} {h} l {r} {h} b 0 {h} 0 {h} 0 {h-r} l 0 {r} b 0 0 0 0 {r} 0"

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        out_srt = workspace / "subtitles_vi.srt"
        out_ass = workspace / "subtitles_vi.ass"

        if config.get("show_subtitle", True) is False:
            with open(out_srt, "w", encoding="utf-8") as f:
                f.write("")
            with open(out_ass, "w", encoding="utf-8") as f:
                f.write("")
        # Load optimized timing segments
        timing_info = job_state.get_step_output("s08c_timing") or {}
        timing_file_str = timing_info.get("timing_file", "")
        if timing_file_str and Path(timing_file_str).exists():
            source_file = Path(timing_file_str)
        else:
            trans_info = job_state.get_step_output("s08_translation") or {}
            source_file = Path(trans_info.get("translation_file") or (workspace / "s08_translation.json"))

        with open(source_file, "r", encoding="utf-8") as f:
            segments = json.load(f)

        # ── 1. Subtitle & Layer Toggle Config ──────────────────────────
        sub_cfg = config.get("subtitle") if isinstance(config.get("subtitle"), dict) else {}
        sub_sec_cfg = sub_cfg.get("secondary") if isinstance(sub_cfg.get("secondary"), dict) else {}
        inpaint_cfg = config.get("inpaint") if isinstance(config.get("inpaint"), dict) else {}

        show_master = bool(config.get("show_subtitle") if config.get("show_subtitle") is not None else sub_cfg.get("show", True))
        show_primary = bool(config.get("subtitle_show_primary") if config.get("subtitle_show_primary") is not None else sub_cfg.get("show_primary", True))
        show_secondary = bool(config.get("subtitle_secondary_show") if config.get("subtitle_secondary_show") is not None else sub_sec_cfg.get("show", True))
        show_box = bool(config.get("inpaint_show_box") if config.get("inpaint_show_box") is not None else inpaint_cfg.get("show_box", True))

        order = str(config.get("subtitle_order") or sub_cfg.get("order") or "primary_top").lower()
        box_split = bool(config.get("subtitle_box_split") if config.get("subtitle_box_split") is not None else sub_cfg.get("box_split", True))
        box_gap = int(config.get("subtitle_box_gap") or sub_cfg.get("box_gap") or 8)

        # Parse & adjust segments according to show toggles
        srt_blocks = []
        adjusted_segments = []
        for i, seg in enumerate(segments):
            raw_pri = str(seg.get("translated_text") or seg.get("text_vi") or seg.get("text") or "").strip()
            raw_sec = str(seg.get("text_secondary") or "").strip()

            primary_text = raw_pri if show_primary else ""
            secondary_text = raw_sec if show_secondary else ""

            s_start = float(seg.get("start", 0))
            s_end = float(seg.get("end", 0))
            if s_end <= s_start:
                s_end = s_start + 1.0

            adjusted_segments.append({
                "seg": seg,
                "primary_text": primary_text,
                "secondary_text": secondary_text,
                "text": primary_text or secondary_text,  # For backward-compat
                "start": s_start,
                "end": s_end
            })

            start_str = self._format_srt_time(s_start)
            end_str = self._format_srt_time(s_end)

            if primary_text and secondary_text:
                if order == "secondary_top":
                    combined_srt = f"{secondary_text}\n{primary_text}"
                else:
                    combined_srt = f"{primary_text}\n{secondary_text}"
            elif primary_text:
                combined_srt = primary_text
            elif secondary_text:
                combined_srt = secondary_text
            else:
                combined_srt = ""

            if combined_srt:
                srt_blocks.append(f"{i + 1}\n{start_str} --> {end_str}\n{combined_srt}\n")

        srt_content = "\n".join(srt_blocks)
        with open(out_srt, "w", encoding="utf-8") as f:
            f.write(srt_content)
        with open(workspace / "subtitles.srt", "w", encoding="utf-8") as f:
            f.write(srt_content)

        has_secondary = any(bool(item["secondary_text"]) for item in adjusted_segments) and show_secondary
        has_primary = any(bool(item["primary_text"]) for item in adjusted_segments) and show_primary

        detect_info = job_state.get_step_output("s03_subtitle_detect") or {}
        probe_info = job_state.get_step_output("s01_probe") or {}

        # ── 2. Box / Subtitle Region Resolutions ───────────────────────
        raw_box_region = config.get("inpaint_region") or inpaint_cfg.get("region") or detect_info.get("burnin_region")
        padding_y = float(config.get("blur_box_padding_y") or inpaint_cfg.get("padding_y") or 0.02)

        if raw_box_region and len(raw_box_region) == 4:
            if not config.get("inpaint_region") and not inpaint_cfg.get("region"):
                ry1, rx1, ry2, rx2 = raw_box_region
                box_region = [max(0.0, ry1 - padding_y), rx1, min(1.0, ry2 + padding_y), rx2]
            else:
                box_region = raw_box_region
        else:
            box_region = [0.75, 0.05, 0.95, 0.95]

        # Primary region overrides (fallback to box_region)
        pri_region = config.get("subtitle_primary_region") or config.get("subtitle_region") or sub_cfg.get("region") or box_region

        # Secondary manual region (if explicitly configured)
        sec_manual_region = config.get("subtitle_secondary_region") or sub_sec_cfg.get("region")
        has_independent_sec_region = bool(sec_manual_region and len(sec_manual_region) == 4)

        video_height = probe_info.get("height") or getattr(job_state, "data", {}).get("video_height") or 1080
        video_width = probe_info.get("width") or getattr(job_state, "data", {}).get("video_width") or 1920

        # Primary Font Styling
        manual_font_size = config.get("subtitle_font_size") or sub_cfg.get("font_size")
        if manual_font_size:
            try:
                raw_fs = int(manual_font_size)
                # If video is vertical (1920p height) and font_size was set in standard 1080p units, scale accordingly
                if video_height > 1080 and raw_fs <= 48:
                    font_size = int(raw_fs * (video_height / 1080.0))
                else:
                    font_size = max(18, raw_fs)
            except (ValueError, TypeError):
                region_h_px = (pri_region[2] - pri_region[0]) * video_height
                font_size = max(24, min(64, int(region_h_px * 0.45)))
        else:
            region_h_px = (pri_region[2] - pri_region[0]) * video_height
            font_size = max(24, min(64, int(region_h_px * 0.45)))

        font_name = str(config.get("subtitle_font_name") or sub_cfg.get("font_name") or "Arial").strip() or "Arial"
        primary_color = self._to_ass_color(str(config.get("subtitle_font_color") or sub_cfg.get("font_color") or "&H00FFFFFF"), "&H00FFFFFF")
        outline_color = self._to_ass_color(str(config.get("subtitle_outline_color") or sub_cfg.get("outline_color") or "&H00000000"), "&H00000000")

        # Secondary Font Styling
        sec_font_name = str(config.get("subtitle_secondary_font_name") or sub_sec_cfg.get("font_name") or "").strip() or font_name
        sec_font_scale = float(config.get("subtitle_secondary_font_size_scale") or sub_sec_cfg.get("font_size_scale") or 0.75)
        sec_font_size = max(14, int(font_size * sec_font_scale))
        sec_primary_color = self._to_ass_color(str(config.get("subtitle_secondary_font_color") or sub_sec_cfg.get("font_color") or "&H00D0D0D0"), "&H00D0D0D0")
        sec_outline_color = self._to_ass_color(str(config.get("subtitle_secondary_outline_color") or sub_sec_cfg.get("outline_color") or "&H00000000"), "&H00000000")

        # 📦 Box Styling
        inpaint_engine = str(inpaint_cfg.get("engine") or config.get("inpaint") or "box_color").lower()
        box_cfg = inpaint_cfg.get("box") or config.get("inpaint_box") or config.get("box") or {}
        if not isinstance(box_cfg, dict):
            box_cfg = {}

        # Box mode is active ONLY when engine is box_color AND show_box is True
        is_box_mode = (inpaint_engine in ["box_color", "box"]) and show_box

        border_width = int(config.get("inpaint_box_border_width") or box_cfg.get("border_width") or 2)
        border_radius = int(config.get("inpaint_box_border_radius") or box_cfg.get("border_radius") or 8)
        bg_opacity = float(config.get("inpaint_box_bg_opacity") or box_cfg.get("bg_opacity") or 0.75)

        alpha_val = max(0, min(255, int((1.0 - bg_opacity) * 255)))
        alpha_hex = f"{alpha_val:02X}"

        raw_bg_color = str(config.get("inpaint_box_bg_color") or box_cfg.get("bg_color") or "black").lower()
        if raw_bg_color in ("white", "#ffffff"):
            ass_bg_color = f"&H{alpha_hex}FFFFFF"
        elif raw_bg_color in ("#1e1e1e", "0x1e1e1e"):
            ass_bg_color = f"&H{alpha_hex}1E1E1E"
        elif raw_bg_color in ("#0f172a", "0x0f172a"):
            ass_bg_color = f"&H{alpha_hex}2A170F"
        else:
            ass_bg_color = f"&H{alpha_hex}000000"

        border_color_str = str(config.get("inpaint_box_border_color") or box_cfg.get("border_color") or "&H40FFFFFF")
        ass_border_color = self._to_ass_color(border_color_str, "&H40FFFFFF")

        ymin, xmin, ymax, xmax = pri_region
        center_x = int(((xmin + xmax) / 2.0) * video_width)
        center_y = int(((ymin + ymax) / 2.0) * video_height)

        margin_l = int(xmin * video_width) + int(video_width * 0.03)
        margin_r = int((1.0 - xmax) * video_width) + int(video_width * 0.03)

        box_lead_in = float(config.get("subtitle_box_lead_in", 0.25))
        box_lead_out = float(config.get("subtitle_box_lead_out", 0.15))
        box_merge_gap = float(config.get("subtitle_max_gap_fill", 0.8))

        # ── 3. Build ASS Document ──────────────────────────────────────
        ass_lines = [
            "[Script Info]",
            "ScriptType: v4.00+",
            f"PlayResX: {video_width}",
            f"PlayResY: {video_height}",
            "WrapStyle: 0",
            "",
            "[V4+ Styles]",
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        ]

        if is_box_mode:
            ass_lines.append(f"Style: SubBox,Arial,{font_size},{ass_bg_color},&H000000FF,{ass_border_color},&H00000000,0,0,0,0,100,100,0,0,1,{border_width},0,5,10,10,10,1")
            ass_lines.append(f"Style: SubText,{font_name},{font_size},{primary_color},&H000000FF,{outline_color},&H80000000,1,0,0,0,100,100,0,0,1,1,0,5,{margin_l},{margin_r},10,1")
            ass_lines.append(f"Style: SubTextSecondary,{sec_font_name},{sec_font_size},{sec_primary_color},&H000000FF,{sec_outline_color},&H80000000,1,0,0,0,100,100,0,0,1,1,0,5,{margin_l},{margin_r},10,1")
        else:
            # Clean floating text styles with solid outline & shadow for readability
            ass_lines.append(f"Style: Default,{font_name},{font_size},{primary_color},&H000000FF,{outline_color},&H80000000,1,0,0,0,100,100,0,0,1,2,1,5,{margin_l},{margin_r},10,1")
            ass_lines.append(f"Style: SubTextSecondary,{sec_font_name},{sec_font_size},{sec_primary_color},&H000000FF,{sec_outline_color},&H80000000,1,0,0,0,100,100,0,0,1,2,1,5,{margin_l},{margin_r},10,1")

        ass_lines.extend([
            "",
            "[Events]",
            "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
        ])

        if not show_master or (not has_primary and not has_secondary):
            # Subtitles completely disabled -> output minimal empty events ASS
            with open(out_ass, "w", encoding="utf-8") as f:
                f.write("\n".join(ass_lines))
            return {
                "srt_file": str(out_srt),
                "ass_file": str(out_ass),
                "segment_count": len(segments),
                "is_bilingual": False
            }

        # ── Case A: Independent Secondary Region (Manual Secondary Placement) ───
        if has_independent_sec_region and has_secondary:
            s_ymin, s_xmin, s_ymax, s_xmax = sec_manual_region
            sec_cx = int(((s_xmin + s_xmax) / 2.0) * video_width)
            sec_cy = int(((s_ymin + s_ymax) / 2.0) * video_height)
            sec_bw = max(20, int((s_xmax - s_xmin) * video_width))
            sec_bh = max(10, int((s_ymax - s_ymin) * video_height))

            pri_bw = max(20, int((xmax - xmin) * video_width))
            pri_bh = max(10, int((ymax - ymin) * video_height))

            for item in adjusted_segments:
                p_txt = item["primary_text"].replace("\n", "\\N")
                s_txt = item["secondary_text"].replace("\n", "\\N")
                s_start = item["start"]
                s_end = item["end"]
                start_str = self._format_ass_time(s_start)
                end_str = self._format_ass_time(s_end)
                b_start_str = self._format_ass_time(max(0.0, s_start - box_lead_in))
                b_end_str = self._format_ass_time(s_end + box_lead_out)

                if is_box_mode:
                    if p_txt and has_primary:
                        path_p = self._make_box_path(pri_bw, pri_bh, border_radius)
                        ass_lines.append(f"Dialogue: 0,{b_start_str},{b_end_str},SubBox,,0,0,0,,{{\\an5\\pos({center_x},{center_y})\\p1\\bord{border_width}\\3c{ass_border_color}\\1c{ass_bg_color}}}{path_p}{{\\p0}}")
                    if s_txt and has_secondary:
                        path_s = self._make_box_path(sec_bw, sec_bh, border_radius)
                        ass_lines.append(f"Dialogue: 0,{b_start_str},{b_end_str},SubBox,,0,0,0,,{{\\an5\\pos({sec_cx},{sec_cy})\\p1\\bord{border_width}\\3c{ass_border_color}\\1c{ass_bg_color}}}{path_s}{{\\p0}}")

                style_p = "SubText" if is_box_mode else "Default"
                if p_txt and has_primary:
                    ass_lines.append(f"Dialogue: 1,{start_str},{end_str},{style_p},,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{p_txt}")
                if s_txt and has_secondary:
                    ass_lines.append(f"Dialogue: 1,{start_str},{end_str},SubTextSecondary,,0,0,0,,{{\\an5\\pos({sec_cx},{sec_cy})}}{s_txt}")

        # ── Case B: Standard Flow (Manual Region / Auto Detect with Stacking) ───
        elif is_box_mode:
            is_manual_box = bool(config.get("inpaint_region") or inpaint_cfg.get("region") or config.get("subtitle_primary_region"))

            if is_manual_box:
                box_w = max(20, int((xmax - xmin) * video_width))
                box_h = max(10, int((ymax - ymin) * video_height))

                # Group continuous dialogue blocks
                box_blocks = []
                for item in adjusted_segments:
                    if not item["primary_text"] and not item["secondary_text"]:
                        continue
                    s_start = max(0.0, float(item["start"]) - box_lead_in)
                    s_end = float(item["end"]) + box_lead_out
                    if not box_blocks:
                        box_blocks.append({"start": s_start, "end": s_end})
                    else:
                        prev_block = box_blocks[-1]
                        if s_start - prev_block["end"] <= box_merge_gap:
                            prev_block["end"] = max(prev_block["end"], s_end)
                        else:
                            box_blocks.append({"start": s_start, "end": s_end})

                if has_secondary and has_primary:
                    # Dual Subtitles in Manual Region Mode (Multi-line Dynamic Stacking)
                    for item in adjusted_segments:
                        p_txt = item["primary_text"].replace("\n", "\\N")
                        s_txt = item["secondary_text"].replace("\n", "\\N")
                        if not p_txt and not s_txt: continue
                        
                        pri_lines = p_txt.split(r"\N") if r"\N" in p_txt else [p_txt]
                        sec_lines = s_txt.split(r"\N") if r"\N" in s_txt else [s_txt]
                        avail_w = max(100, int((xmax - xmin) * video_width))
                        max_chars_pri = max(10, int(avail_w / (font_size * 0.58)))
                        max_chars_sec = max(12, int(avail_w / (sec_font_size * 0.58)))
                        num_pri = max(len(pri_lines), max((len(l) + max_chars_pri - 1) // max_chars_pri for l in pri_lines))
                        num_sec = max(len(sec_lines), max((len(l) + max_chars_sec - 1) // max_chars_sec for l in sec_lines))

                        lh_pri = font_size * 1.15
                        lh_sec = sec_font_size * 1.15
                        h_pri = num_pri * lh_pri
                        h_sec = num_sec * lh_sec
                        gap = max(18.0, float(box_gap) * (video_height / 1080.0))
                        total_h = h_pri + h_sec + gap

                        if order == "secondary_top":
                            cy_sec = int(center_y - (total_h / 2.0) + (h_sec / 2.0))
                            cy_pri = int(center_y + (total_h / 2.0) - (h_pri / 2.0))
                            cy_top, cy_bot = cy_sec, cy_pri
                            h_top, h_bot = int(h_sec + 10), int(h_pri + 12)
                        else:
                            cy_pri = int(center_y - (total_h / 2.0) + (h_pri / 2.0))
                            cy_sec = int(center_y + (total_h / 2.0) - (h_sec / 2.0))
                            cy_top, cy_bot = cy_pri, cy_sec
                            h_top, h_bot = int(h_pri + 12), int(h_sec + 10)

                        # Boundary Clamping
                        bottom_edge = cy_bot + (h_bot // 2)
                        if bottom_edge > video_height - 12:
                            shift_up = bottom_edge - (video_height - 12)
                            cy_top -= shift_up; cy_bot -= shift_up; cy_pri -= shift_up; cy_sec -= shift_up
                        top_edge = cy_top - (h_top // 2)
                        if top_edge < 12:
                            shift_down = 12 - top_edge
                            cy_top += shift_down; cy_bot += shift_down; cy_pri += shift_down; cy_sec += shift_down
                        
                        s_start = max(0.0, float(item["start"]) - box_lead_in)
                        s_end = float(item["end"]) + box_lead_out
                        b_start_str = self._format_ass_time(s_start)
                        b_end_str = self._format_ass_time(s_end)
                        start_str = self._format_ass_time(item["start"])
                        end_str = self._format_ass_time(item["end"])

                        path_top = self._make_box_path(box_w, h_top, border_radius)
                        path_bot = self._make_box_path(box_w, h_bot, border_radius)
                        ass_lines.append(f"Dialogue: 0,{b_start_str},{b_end_str},SubBox,,0,0,0,,{{\\an5\\pos({center_x},{cy_top})\\p1\\bord{border_width}\\3c{ass_border_color}\\1c{ass_bg_color}}}{path_top}{{\\p0}}")
                        ass_lines.append(f"Dialogue: 0,{b_start_str},{b_end_str},SubBox,,0,0,0,,{{\\an5\\pos({center_x},{cy_bot})\\p1\\bord{border_width}\\3c{ass_border_color}\\1c{ass_bg_color}}}{path_bot}{{\\p0}}")
                        if p_txt: ass_lines.append(f"Dialogue: 1,{start_str},{end_str},SubText,,0,0,0,,{{\\an5\\pos({center_x},{cy_pri})}}{p_txt}")
                        if s_txt: ass_lines.append(f"Dialogue: 1,{start_str},{end_str},SubTextSecondary,,0,0,0,,{{\\an5\\pos({center_x},{cy_sec})}}{s_txt}")

                else:
                    # Single Active Subtitle (Primary OR Secondary only)
                    active_style = "SubTextSecondary" if (has_secondary and not has_primary) else "SubText"
                    path = self._make_box_path(box_w, box_h, border_radius)
                    for block in box_blocks:
                        b_start_str = self._format_ass_time(block["start"])
                        b_end_str = self._format_ass_time(block["end"])
                        ass_lines.append(f"Dialogue: 0,{b_start_str},{b_end_str},SubBox,,0,0,0,,{{\\an5\\pos({center_x},{center_y})\\p1\\bord{border_width}\\3c{ass_border_color}\\1c{ass_bg_color}}}{path}{{\\p0}}")

                    for item in adjusted_segments:
                        text_str = (item["secondary_text"] if (has_secondary and not has_primary) else item["primary_text"]).replace("\n", "\\N")
                        if not text_str:
                            continue
                        start_str = self._format_ass_time(item["start"])
                        end_str = self._format_ass_time(item["end"])
                        ass_lines.append(f"Dialogue: 1,{start_str},{end_str},{active_style},,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{text_str}")

            else:
                # Auto-Detect Dynamic Per-Dialogue Sizing
                for item in adjusted_segments:
                    p_txt = item["primary_text"].replace("\n", "\\N")
                    s_txt = item["secondary_text"].replace("\n", "\\N")
                    if not p_txt and not s_txt:
                        continue
                    s_start = item["start"]
                    s_end = item["end"]
                    start_str = self._format_ass_time(s_start)
                    end_str = self._format_ass_time(s_end)
                    b_start_str = self._format_ass_time(max(0.0, s_start - box_lead_in))
                    b_end_str = self._format_ass_time(s_end + box_lead_out)

                    if p_txt and s_txt:
                        # Dual Subtitles Auto Mode
                        lines_p = p_txt.split(r"\N") if r"\N" in p_txt else [p_txt]
                        lines_s = s_txt.split(r"\N") if r"\N" in s_txt else [s_txt]

                        pad_x_p = max(20, int(font_size * 0.75))
                        pad_y_p = max(6, int(font_size * 0.25))
                        w_p = max(int(font_size * 3), min(int(video_width * 0.92), int(max(len(l) for l in lines_p) * font_size * 0.58) + pad_x_p * 2))
                        h_p = int(len(lines_p) * font_size * 1.35) + pad_y_p * 2

                        pad_x_s = max(18, int(sec_font_size * 0.75))
                        pad_y_s = max(5, int(sec_font_size * 0.22))
                        w_s = max(int(sec_font_size * 3), min(int(video_width * 0.92), int(max(len(l) for l in lines_s) * sec_font_size * 0.58) + pad_x_s * 2))
                        h_s = int(len(lines_s) * sec_font_size * 1.35) + pad_y_s * 2

                        gap = box_gap if box_split else 4

                        if order == "secondary_top":
                            cy_sec = center_y - (h_s // 2) - (gap // 2)
                            cy_pri = center_y + (h_p // 2) + (gap // 2)
                        else:
                            cy_pri = center_y - (h_p // 2) - (gap // 2)
                            cy_sec = center_y + (h_s // 2) + (gap // 2)

                        path_p = self._make_box_path(w_p, h_p, border_radius)
                        path_s = self._make_box_path(w_s, h_s, border_radius)

                        ass_lines.append(f"Dialogue: 0,{b_start_str},{b_end_str},SubBox,,0,0,0,,{{\\an5\\pos({center_x},{cy_pri})\\p1\\bord{border_width}\\3c{ass_border_color}\\1c{ass_bg_color}}}{path_p}{{\\p0}}")
                        ass_lines.append(f"Dialogue: 0,{b_start_str},{b_end_str},SubBox,,0,0,0,,{{\\an5\\pos({center_x},{cy_sec})\\p1\\bord{border_width}\\3c{ass_border_color}\\1c{ass_bg_color}}}{path_s}{{\\p0}}")

                        ass_lines.append(f"Dialogue: 1,{start_str},{end_str},SubText,,0,0,0,,{{\\an5\\pos({center_x},{cy_pri})}}{p_txt}")
                        ass_lines.append(f"Dialogue: 1,{start_str},{end_str},SubTextSecondary,,0,0,0,,{{\\an5\\pos({center_x},{cy_sec})}}{s_txt}")

                    else:
                        # Single Active Subtitle
                        active_txt = p_txt if p_txt else s_txt
                        active_style = "SubText" if p_txt else "SubTextSecondary"
                        active_fsize = font_size if p_txt else sec_font_size
                        lines = active_txt.split(r"\N") if r"\N" in active_txt else [active_txt]
                        max_line_len = max(len(l) for l in lines) if lines else 1
                        num_lines = len(lines)
                        pad_x = max(20, int(active_fsize * 0.75))
                        pad_y = max(10, int(active_fsize * 0.35))
                        line_h = int(active_fsize * 1.35)
                        box_w = max(int(active_fsize * 3), min(int(video_width * 0.92), int(max_line_len * active_fsize * 0.58) + pad_x * 2))
                        box_h = int(num_lines * line_h) + pad_y * 2
                        path = self._make_box_path(box_w, box_h, border_radius)

                        ass_lines.append(f"Dialogue: 0,{b_start_str},{b_end_str},SubBox,,0,0,0,,{{\\an5\\pos({center_x},{center_y})\\p1\\bord{border_width}\\3c{ass_border_color}\\1c{ass_bg_color}}}{path}{{\\p0}}")
                        ass_lines.append(f"Dialogue: 1,{start_str},{end_str},{active_style},,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{active_txt}")

        else:
            # ── Case C: Non-Box Mode (Direct Outline ASS) ───────────────────
            for item in adjusted_segments:
                p_txt = item["primary_text"].replace("\n", "\\N")
                s_txt = item["secondary_text"].replace("\n", "\\N")
                if not p_txt and not s_txt:
                    continue
                s_start = item["start"]
                s_end = item["end"]
                start_str = self._format_ass_time(s_start)
                end_str = self._format_ass_time(s_end)

                if p_txt and s_txt:
                    # Smart line count & height calculation
                    pri_lines = p_txt.split(r"\N") if r"\N" in p_txt else [p_txt]
                    sec_lines = s_txt.split(r"\N") if r"\N" in s_txt else [s_txt]
                    
                    avail_w = video_width - margin_l - margin_r
                    max_chars_pri = max(10, int(avail_w / (font_size * 0.58)))
                    max_chars_sec = max(12, int(avail_w / (sec_font_size * 0.58)))
                    
                    num_pri = max(len(pri_lines), max((len(l) + max_chars_pri - 1) // max_chars_pri for l in pri_lines))
                    num_sec = max(len(sec_lines), max((len(l) + max_chars_sec - 1) // max_chars_sec for l in sec_lines))

                    lh_pri = font_size * 1.15
                    lh_sec = sec_font_size * 1.15
                    h_pri = num_pri * lh_pri
                    h_sec = num_sec * lh_sec
                    gap = float(box_gap)
                    total_h = h_pri + h_sec + gap

                    if order == "secondary_top":
                        cy_sec = int(center_y - (total_h / 2.0) + (h_sec / 2.0))
                        cy_pri = int(center_y + (total_h / 2.0) - (h_pri / 2.0))
                    else:
                        cy_pri = int(center_y - (total_h / 2.0) + (h_pri / 2.0))
                        cy_sec = int(center_y + (total_h / 2.0) - (h_sec / 2.0))

                    ass_lines.append(f"Dialogue: 0,{start_str},{end_str},Default,,0,0,0,,{{\\an5\\pos({center_x},{cy_pri})}}{p_txt}")
                    ass_lines.append(f"Dialogue: 0,{start_str},{end_str},SubTextSecondary,,0,0,0,,{{\\an5\\pos({center_x},{cy_sec})}}{s_txt}")
                elif p_txt:
                    ass_lines.append(f"Dialogue: 0,{start_str},{end_str},Default,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{p_txt}")
                elif s_txt:
                    ass_lines.append(f"Dialogue: 0,{start_str},{end_str},SubTextSecondary,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{s_txt}")

        with open(out_ass, "w", encoding="utf-8") as f:
            f.write("\n".join(ass_lines))

        return {
            "srt_file": str(out_srt),
            "ass_file": str(out_ass),
            "segment_count": len(segments),
            "is_bilingual": has_secondary
        }

    def _format_srt_time(self, seconds: float) -> str:
        h = int(seconds // 3600)
        m = int((seconds % 3600) // 60)
        s = int(seconds % 60)
        ms = int(round((seconds - int(seconds)) * 1000))
        if ms >= 1000:
            s += 1
            ms -= 1000
        return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

    def _format_ass_time(self, seconds: float) -> str:
        h = int(seconds // 3600)
        m = int((seconds % 3600) // 60)
        s = int(seconds % 60)
        cs = int(round((seconds - int(seconds)) * 100))
        if cs >= 100:
            s += 1
            cs -= 100
        return f"{h}:{m:02d}:{s:02d}.{cs:02d}"

    def _auto_wrap_text(self, text: str, max_chars: int = 28) -> str:
        clean = text.strip()
        if len(clean) <= max_chars or "\n" in clean or "\\N" in clean:
            return clean.replace("\n", "\\N")
        words = clean.split()
        if len(words) <= 3:
            return clean
        lines = []
        cur = ""
        for w in words:
            if not cur:
                cur = w
            elif len(cur) + 1 + len(w) <= max_chars:
                cur += " " + w
            else:
                lines.append(cur)
                cur = w
        if cur:
            lines.append(cur)
        return "\\N".join(lines)
