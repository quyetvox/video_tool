import datetime
import json
from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase


class StepSubtitleGen(StepBase):
    step_id = "s09_subtitle_gen"
    depends_on = ["s03_subtitle_detect", "s08_translation"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        trans_info = job_state.get_step_output("s08_translation") or {}
        trans_file = Path(trans_info["translation_file"])

        with open(trans_file, "r", encoding="utf-8") as f:
            segments = json.load(f)

        # Collect valid segments and adjust timestamps to avoid overlapping
        valid_segments = []
        for seg in segments:
            text_val = seg.get("text", "").strip()
            if not text_val or (len(text_val) <= 1 and text_val.isascii()):
                continue
            valid_segments.append(seg)

        adjusted_segments = []
        for i, seg in enumerate(valid_segments):
            text_val = seg.get("text", "").strip()
            s_start = float(seg.get("start", 0.0))
            raw_end = float(seg.get("end", s_start + 1.2))
            if raw_end <= s_start:
                raw_end = s_start + 1.2

            if i + 1 < len(valid_segments):
                next_start = float(valid_segments[i + 1].get("start", raw_end))
                if next_start > s_start:
                    s_end = min(max(raw_end, s_start + 1.0), next_start)
                else:
                    s_end = raw_end
            else:
                s_end = max(raw_end, s_start + 1.0)

            adjusted_segments.append({
                "seg": seg,
                "text": text_val,
                "start": s_start,
                "end": s_end
            })

        srt_blocks = []
        sub_idx = 1
        for item in adjusted_segments:
            s_start = item["start"]
            s_end = item["end"]
            text = item["text"]
            start_srt = self._format_srt_time(s_start)
            end_srt = self._format_srt_time(s_end)
            srt_blocks.append(f"{sub_idx}\n{start_srt} --> {end_srt}\n{text}\n")
            sub_idx += 1

        srt_content = "\n".join(srt_blocks)

        detect_info = job_state.get_step_output("s03_subtitle_detect") or {}
        probe_info = job_state.get_step_output("s01_probe") or {}

        # inpaint_region from config overrides auto-detect
        region = config.get("inpaint_region") or detect_info.get("burnin_region") or [0.75, 0.05, 0.95, 0.95]

        video_height = probe_info.get("height", 1080)
        video_width = probe_info.get("width", 1920)

        # Font size & region auto-fit
        manual_font_size = config.get("subtitle_font_size")
        if manual_font_size:
            font_size = int(manual_font_size)
        else:
            region_h_px = (region[2] - region[0]) * video_height
            font_size = max(14, min(48, int(region_h_px * 0.45)))

        ymin, xmin, ymax, xmax = region

        # Center of blur box in pixels — \an5 places the TEXT CENTER exactly at pos(x,y)
        center_x = int(((xmin + xmax) / 2.0) * video_width)
        center_y = int(((ymin + ymax) / 2.0) * video_height)

        # Horizontal safe margins: keep text inside the blur box with 5% padding
        margin_l = int(xmin * video_width) + int(video_width * 0.03)
        margin_r = int((1.0 - xmax) * video_width) + int(video_width * 0.03)

        out_srt = workspace / "subtitles_vi.srt"
        with open(out_srt, "w", encoding="utf-8") as f:
            f.write(srt_content)

        # Generate ASS format with per-segment dynamic positioning & font sizing
        out_ass = workspace / "subtitles_vi.ass"
        ass_lines = [
            "[Script Info]",
            "ScriptType: v4.00+",
            f"PlayResX: {video_width}",
            f"PlayResY: {video_height}",
            "WrapStyle: 0",
            "",
            "[V4+ Styles]",
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
            f"Style: Default,Arial,{font_size},&H00FFFFFF,&H000000FF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,2,1,5,{margin_l},{margin_r},10,1",
            "",
            "[Events]",
            "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
        ]

        for item in adjusted_segments:
            seg = item["seg"]
            text_str = item["text"].replace("\n", "\\N")
            s_start = item["start"]
            s_end = item["end"]
            
            start_str = self._format_ass_time(s_start)
            end_str = self._format_ass_time(s_end)

            # \an5 = center-center alignment: pos(x,y) places the exact CENTER of the text at (x,y)
            # No offset needed — center_x/center_y are already the geometric center of the blur box
            seg_font = font_size
            pos_tag = f"{{\\an5\\pos({center_x},{center_y})\\fs{seg_font}}}"
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
