import json
from pathlib import Path
from typing import Any, Dict, List

import srt

from core.step_base import StepBase


class StepTranscriptMerge(StepBase):
    step_id = "s07_transcript_merge"
    depends_on = ["s03_subtitle_detect", "s05_asr", "s06_ocr"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        detect_info = job_state.get_step_output("s03_subtitle_detect") or {}
        mode = detect_info.get("mode")

        ocr_file = workspace / "s06_ocr.json"
        asr_file = workspace / "s05_asr.json"
        
        ocr_segments = []
        asr_segments = []
        
        if ocr_file.exists():
            with open(ocr_file, "r", encoding="utf-8") as f:
                ocr_segments = json.load(f)
        if asr_file.exists():
            with open(asr_file, "r", encoding="utf-8") as f:
                asr_segments = json.load(f)

        # Prioritize OCR segments if present, fallback to embedded sub or ASR
        if len(ocr_segments) > 0:
            merged_segments = ocr_segments
        elif mode == "embedded" and detect_info.get("embedded_sub"):
            sub_file = Path(detect_info["embedded_sub"])
            if sub_file.exists():
                with open(sub_file, "r", encoding="utf-8") as f:
                    sub_data = list(srt.parse(f.read()))
                for s in sub_data:
                    merged_segments.append({
                        "start": round(s.start.total_seconds(), 3),
                        "end": round(s.end.total_seconds(), 3),
                        "text": s.content.strip()
                    })
        else:
            merged_segments = asr_segments

        from utils.repetition_cleaner import RepetitionCleaner
        merged_segments = RepetitionCleaner.clean_segments(merged_segments)

        # Anti-Collision Clamping to prevent subtitle overlap on frame transitions
        merged_segments = StepTranscriptMerge.sanitize_and_clamp_segments(merged_segments)

        # Save final transcript
        out_file = workspace / "s07_transcript.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(merged_segments, f, ensure_ascii=False, indent=2)

        return {
            "transcript_file": str(out_file),
            "segment_count": len(merged_segments)
        }

    @staticmethod
    def sanitize_and_clamp_segments(segments: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if not segments:
            return []

        # Sort chronologically by start time
        sorted_segs = sorted(segments, key=lambda s: float(s.get("start", 0.0)))
        cleaned = []

        for i, seg in enumerate(sorted_segs):
            s_time = float(seg.get("start", 0.0))
            e_time = float(seg.get("end", s_time + 1.0))

            # Clamp end time if it overlaps with the next segment's start time
            if i + 1 < len(sorted_segs):
                next_start = float(sorted_segs[i + 1].get("start", 0.0))
                if e_time >= next_start:
                    e_time = round(max(s_time + 0.1, next_start - 0.03), 3)

            dur = e_time - s_time
            # Discard micro flicker segments (< 0.25s)
            if dur < 0.25:
                continue

            seg["start"] = round(s_time, 3)
            seg["end"] = round(e_time, 3)
            cleaned.append(seg)

        return cleaned
