import datetime
import json
from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase


class StepSubtitleGen(StepBase):
    step_id = "s09_subtitle_gen"
    depends_on = ["s03_subtitle_detect", "s08_translation", "s08c_timing"]
    STEP_CONFIG_KEYS = [
        "show_subtitle", "inpaint", "inpaint_region", "inpaint_box_bg_color", 
        "inpaint_box_bg_opacity", "inpaint_box_border_color", "inpaint_box_border_width", 
        "inpaint_box_border_radius", "subtitle_font_size", "subtitle_font_name", 
        "subtitle_font_color", "subtitle_outline_color", "blur_box_padding_y",
        "subtitle_box_lead_in", "subtitle_box_lead_out", "subtitle_max_gap_fill"
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
        }
        if c.lower() in named_colors:
            return named_colors[c.lower()]
        if c.startswith("#") and len(c) == 7:
            r = c[1:3]
            g = c[3:5]
            b = c[5:7]
            return f"&H00{b}{g}{r}".upper()
        return default

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        out_srt = workspace / "subtitles_vi.srt"
        out_ass = workspace / "subtitles_vi.ass"

        if config.get("show_subtitle", True) is False:
            # Write empty files and skip
            with open(out_srt, "w", encoding="utf-8") as f:
                f.write("")
            with open(out_ass, "w", encoding="utf-8") as f:
                f.write("")
            return {
                "srt_file": str(out_srt),
                "ass_file": str(out_ass),
                "skipped": True
            }

        # Prefer s08c_timing.json (optimized timing) — fallback to s08_translation.json
        timing_info = job_state.get_step_output("s08c_timing") or {}
        timing_file_str = timing_info.get("timing_file", "")
        if timing_file_str and Path(timing_file_str).exists():
            source_file = Path(timing_file_str)
        else:
            trans_info = job_state.get_step_output("s08_translation") or {}
            source_file = Path(trans_info["translation_file"])

        with open(source_file, "r", encoding="utf-8") as f:
            segments = json.load(f)

        # Generate standard SRT
        srt_blocks = []
        adjusted_segments = []
        for i, seg in enumerate(segments):
            orig_text = seg.get("translated_text") or seg.get("text_vi") or seg.get("text") or ""
            cleaned_text = str(orig_text).strip()
            
            s_start = float(seg.get("start", 0))
            s_end = float(seg.get("end", 0))

            if s_end <= s_start:
                s_end = s_start + 1.0

            adjusted_segments.append({
                "seg": seg,
                "text": cleaned_text,
                "start": s_start,
                "end": s_end
            })

            start_str = self._format_srt_time(s_start)
            end_str = self._format_srt_time(s_end)

            srt_blocks.append(f"{i + 1}\n{start_str} --> {end_str}\n{cleaned_text}\n")

        srt_content = "\n".join(srt_blocks)

        detect_info = job_state.get_step_output("s03_subtitle_detect") or {}
        probe_info = job_state.get_step_output("s01_probe") or {}

        # inpaint_region from config overrides auto-detect
        raw_region = config.get("inpaint_region") or detect_info.get("burnin_region")
        padding_y = float(config.get("blur_box_padding_y", 0.02))

        if raw_region and len(raw_region) == 4:
            if not config.get("inpaint_region"):
                ry1, rx1, ry2, rx2 = raw_region
                region = [max(0.0, ry1 - padding_y), rx1, min(1.0, ry2 + padding_y), rx2]
            else:
                region = raw_region
        else:
            region = [0.75, 0.05, 0.95, 0.95]

        video_height = probe_info.get("height", 1080)
        video_width = probe_info.get("width", 1920)

        # Font size & region auto-fit
        manual_font_size = config.get("subtitle_font_size")
        if manual_font_size:
            font_size = int(manual_font_size)
        else:
            region_h_px = (region[2] - region[0]) * video_height
            font_size = max(14, min(48, int(region_h_px * 0.45)))

        # Subtitle font styling & colors
        font_name = str(config.get("subtitle_font_name", "Arial")).strip() or "Arial"
        primary_color = self._to_ass_color(str(config.get("subtitle_font_color", "&H00FFFFFF")), "&H00FFFFFF")
        outline_color = self._to_ass_color(str(config.get("subtitle_outline_color", "&H00000000")), "&H00000000")

        # 📦 Box Styling
        inpaint_engine = str(config.get("inpaint", "box_color")).lower()
        box_cfg = config.get("inpaint_box") or config.get("box") or {}
        if not isinstance(box_cfg, dict):
            box_cfg = {}

        is_box_mode = inpaint_engine in ["box_color", "box"]

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

        ymin, xmin, ymax, xmax = region

        # Center of blur box in pixels — \an5 places the TEXT CENTER exactly at pos(x,y)
        center_x = int(((xmin + xmax) / 2.0) * video_width)
        center_y = int(((ymin + ymax) / 2.0) * video_height)

        # Horizontal safe margins
        margin_l = int(xmin * video_width) + int(video_width * 0.03)
        margin_r = int((1.0 - xmax) * video_width) + int(video_width * 0.03)

        with open(out_srt, "w", encoding="utf-8") as f:
            f.write(srt_content)

        # Generate ASS format with per-segment dynamic positioning & vector rounded box
        if is_box_mode:
            ass_lines = [
                "[Script Info]",
                "ScriptType: v4.00+",
                f"PlayResX: {video_width}",
                f"PlayResY: {video_height}",
                "WrapStyle: 0",
                "",
                "[V4+ Styles]",
                "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
                f"Style: SubBox,Arial,{font_size},{ass_bg_color},&H000000FF,{ass_border_color},&H00000000,0,0,0,0,100,100,0,0,1,{border_width},0,5,10,10,10,1",
                f"Style: SubText,{font_name},{font_size},{primary_color},&H000000FF,{outline_color},&H80000000,1,0,0,0,100,100,0,0,1,1,0,5,{margin_l},{margin_r},10,1",
                "",
                "[Events]",
                "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
            ]

            is_manual_region = bool(config.get("inpaint_region"))

            box_lead_in = float(config.get("subtitle_box_lead_in", 0.25))
            box_lead_out = float(config.get("subtitle_box_lead_out", 0.15))

            if is_manual_region:
                # 1. In manual inpaint_region mode, fix the box width & height strictly to the specified region
                box_w = max(20, int((xmax - xmin) * video_width))
                box_h = max(10, int((ymax - ymin) * video_height))
                r = min(int(border_radius), box_h // 2, box_w // 2)
                w = box_w
                h = box_h
                path = f"m {r} 0 l {w-r} 0 b {w} 0 {w} 0 {w} {r} l {w} {h-r} b {w} {h} {w} {h} {w-r} {h} l {r} {h} b 0 {h} 0 {h} 0 {h-r} l 0 {r} b 0 0 0 0 {r} 0"

                # Group dialogue segments into Continuous Dialogue Blocks with lead_in & lead_out padding
                box_merge_gap = float(config.get("subtitle_max_gap_fill", 0.8))
                box_blocks = []
                for item in adjusted_segments:
                    s_start = max(0.0, float(item["start"]) - box_lead_in)
                    s_end = float(item["end"]) + box_lead_out
                    if not box_blocks:
                        box_blocks.append({"start": s_start, "end": s_end})
                    else:
                        prev_block = box_blocks[-1]
                        if s_start - prev_block["end"] <= box_merge_gap:
                            # Merge into continuous block
                            prev_block["end"] = max(prev_block["end"], s_end)
                        else:
                            # Gap > box_merge_gap -> Start new box block
                            box_blocks.append({"start": s_start, "end": s_end})

                # Render Layer 0: Continuous SubBox blocks (zero flicker, opens early to cover old sub)
                for block in box_blocks:
                    b_start_str = self._format_ass_time(block["start"])
                    b_end_str = self._format_ass_time(block["end"])
                    ass_lines.append(f"Dialogue: 0,{b_start_str},{b_end_str},SubBox,,0,0,0,,{{\\an5\\pos({center_x},{center_y})\\p1\\bord{border_width}\\3c{ass_border_color}\\1c{ass_bg_color}}}{path}{{\\p0}}")

                # Render Layer 1: Subtitle Text events (appear and switch cleanly on top of the continuous box)
                for item in adjusted_segments:
                    text_str = item["text"].replace("\n", "\\N")
                    s_start = item["start"]
                    s_end = item["end"]
                    start_str = self._format_ass_time(s_start)
                    end_str = self._format_ass_time(s_end)
                    ass_lines.append(f"Dialogue: 1,{start_str},{end_str},SubText,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{text_str}")

            else:
                # In auto-detect mode, dynamically size the box per dialogue with lead_in & lead_out
                for item in adjusted_segments:
                    text_str = item["text"].replace("\n", "\\N")
                    s_start = item["start"]
                    s_end = item["end"]
                    start_str = self._format_ass_time(s_start)
                    end_str = self._format_ass_time(s_end)
                    b_start_str = self._format_ass_time(max(0.0, s_start - box_lead_in))
                    b_end_str = self._format_ass_time(s_end + box_lead_out)

                    lines = text_str.split(r"\N") if r"\N" in text_str else [text_str]
                    max_line_len = max(len(l) for l in lines) if lines else 1
                    num_lines = len(lines)
                    pad_x = max(20, int(font_size * 0.75))
                    pad_y = max(10, int(font_size * 0.35))
                    line_h = int(font_size * 1.35)
                    box_w = max(int(font_size * 3), min(int(video_width * 0.92), int(max_line_len * font_size * 0.58) + pad_x * 2))
                    box_h = int(num_lines * line_h) + pad_y * 2
                    r = min(int(border_radius), box_h // 2, box_w // 2)
                    w = box_w
                    h = box_h
                    path = f"m {r} 0 l {w-r} 0 b {w} 0 {w} 0 {w} {r} l {w} {h-r} b {w} {h} {w} {h} {w-r} {h} l {r} {h} b 0 {h} 0 {h} 0 {h-r} l 0 {r} b 0 0 0 0 {r} 0"

                    # Layer 0: Rounded Box Background (opened early by box_lead_in)
                    ass_lines.append(f"Dialogue: 0,{b_start_str},{b_end_str},SubBox,,0,0,0,,{{\\an5\\pos({center_x},{center_y})\\p1\\bord{border_width}\\3c{ass_border_color}\\1c{ass_bg_color}}}{path}{{\\p0}}")
                    # Layer 1: Subtitle Text
                    ass_lines.append(f"Dialogue: 1,{start_str},{end_str},SubText,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{text_str}")
        else:
            ass_lines = [
                "[Script Info]",
                "ScriptType: v4.00+",
                f"PlayResX: {video_width}",
                f"PlayResY: {video_height}",
                "WrapStyle: 0",
                "",
                "[V4+ Styles]",
                "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
                f"Style: Default,{font_name},{font_size},{primary_color},&H000000FF,{outline_color},&H80000000,1,0,0,0,100,100,0,0,1,2,1,5,{margin_l},{margin_r},10,1",
                "",
                "[Events]",
                "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
            ]

            for item in adjusted_segments:
                text_str = item["text"].replace("\n", "\\N")
                s_start = item["start"]
                s_end = item["end"]

                start_str = self._format_ass_time(s_start)
                end_str = self._format_ass_time(s_end)

                pos_tag = f"{{\\an5\\pos({center_x},{center_y})\\fs{font_size}}}"
                ass_lines.append(f"Dialogue: 0,{start_str},{end_str},Default,,0,0,0,,{pos_tag}{text_str}")

        with open(out_ass, "w", encoding="utf-8") as f:
            f.write("\n".join(ass_lines))

        return {
            "srt_file": str(out_srt),
            "ass_file": str(out_ass),
            "segment_count": len(segments)
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
