import datetime
import json
from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase


class StepSubtitleGen(StepBase):
    step_id = "s09_subtitle_gen"
    depends_on = ["s08_translation"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        trans_info = job_state.get_step_output("s08_translation") or {}
        trans_file = Path(trans_info["translation_file"])

        with open(trans_file, "r", encoding="utf-8") as f:
            segments = json.load(f)

        srt_blocks = []
        sub_idx = 1
        for seg in segments:
            text = seg.get("text", "").strip()
            if not text:
                continue
            s_start = float(seg.get("start", 0.0))
            s_end = max(float(seg.get("end", s_start + 0.5)), s_start + 0.3)
            
            start_srt = self._format_srt_time(s_start)
            end_srt = self._format_srt_time(s_end)
            srt_blocks.append(f"{sub_idx}\n{start_srt} --> {end_srt}\n{text}\n")
            sub_idx += 1

        srt_content = "\n".join(srt_blocks)

        detect_info = job_state.get_step_output("s03_subtitle_detect") or {}
        probe_info = job_state.get_step_output("s01_probe") or {}

        # inpaint_region from config overrides auto-detect
        region = config.get("inpaint_region") or detect_info.get("burnin_region") or [0.75, 0.05, 0.95, 0.95]
        ymin, xmin, ymax, xmax = region

        video_height = probe_info.get("height", 1080)
        video_width = probe_info.get("width", 1920)

        # Region dimensions in pixels
        region_h_px = (ymax - ymin) * video_height
        region_w_px = (xmax - xmin) * video_width

        # Font size: auto-fit to ~45% of region height, or use manual override
        manual_font_size = config.get("subtitle_font_size")
        if manual_font_size:
            font_size = int(manual_font_size)
        else:
            font_size = max(14, min(48, int(region_h_px * 0.45)))

        # Subtitle is always centered inside the inpaint_region (alignment=5)
        alignment = 5
        margin_v = 10

        # Center position (pixel coords) for \pos tag
        center_x = int(((xmin + xmax) / 2.0) * video_width)
        center_y = int(((ymin + ymax) / 2.0) * video_height)

        out_srt = workspace / "subtitles_vi.srt"
        with open(out_srt, "w", encoding="utf-8") as f:
            f.write(srt_content)

        # Generate ASS format for exact styling & positioning
        out_ass = workspace / "subtitles_vi.ass"
        ass_lines = [
            "[Script Info]",
            "ScriptType: v4.00+",
            f"PlayResX: {video_width}",
            f"PlayResY: {video_height}",
            "",
            "[V4+ Styles]",
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
            f"Style: Default,Arial,{font_size},&H00FFFFFF,&H000000FF,&H00000000,&H80000000,1,0,0,0,100,100,0,0,1,2,1,{alignment},20,20,{margin_v},1",
            "",
            "[Events]",
            "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"
        ]

        for seg in segments:
            text_val = seg.get("text", "").strip()
            if not text_val:
                continue
            s_start = float(seg.get("start", 0.0))
            s_end = max(float(seg.get("end", s_start + 0.5)), s_start + 0.3)
            
            start_str = self._format_ass_time(s_start)
            end_str = self._format_ass_time(s_end)
            text_str = text_val.replace("\n", "\\N")

            # Always use inpaint_region center (bbox from keyframe OCR as optional override)
            bbox = seg.get("bbox")
            if bbox:
                b_ymin, b_xmin, b_ymax, b_xmax = bbox
                pos_x = int(((b_xmin + b_xmax) / 2.0) * video_width)
                pos_y = int(((b_ymin + b_ymax) / 2.0) * video_height)
            else:
                pos_x = center_x
                pos_y = center_y
            pos_tag = f"{{\\pos({pos_x},{pos_y})}}"
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
