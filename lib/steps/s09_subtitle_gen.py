import datetime
import json
from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase


class StepSubtitleGen(StepBase):
    step_id = "s09_subtitle_gen"
    depends_on = ["s03_subtitle_detect", "s08_translation", "s08c_timing"]
    STEP_CONFIG_KEYS = ["show_subtitle", "inpaint_region", "subtitle_font_size", "subtitle_font_name", "subtitle_font_color", "subtitle_outline_color", "blur_box_padding_y"]

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
            orig_text = seg.get("text_vi", seg.get("translated_text", seg.get("text", "")))
            cleaned_text = orig_text.strip()
            
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

        ymin, xmin, ymax, xmax = region

        # Center of blur box in pixels — \an5 places the TEXT CENTER exactly at pos(x,y)
        center_x = int(((xmin + xmax) / 2.0) * video_width)
        center_y = int(((ymin + ymax) / 2.0) * video_height)

        # Horizontal safe margins: keep text inside the blur box with 5% padding
        margin_l = int(xmin * video_width) + int(video_width * 0.03)
        margin_r = int((1.0 - xmax) * video_width) + int(video_width * 0.03)

        with open(out_srt, "w", encoding="utf-8") as f:
            f.write(srt_content)

        # Generate ASS format with per-segment dynamic positioning & font sizing
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

            # \an5 = center-center alignment: pos(x,y) places the exact CENTER of the text at (x,y)
            # No offset needed — center_x/center_y are already the geometric center of the blur box
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
