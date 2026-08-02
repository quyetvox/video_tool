import json
from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase
from utils.gender_detector import GenderDetector


class StepGenderDetect(StepBase):
    step_id = "s05b_gender_detect"
    depends_on = ["s04_audio_separate", "s05_asr"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        asr_info = job_state.get_step_output("s05_asr") or {}
        asr_file = Path(asr_info.get("transcript_file", workspace / "s05_asr.json"))

        segments = []
        if asr_file.exists():
            with open(asr_file, "r", encoding="utf-8") as f:
                segments = json.load(f)

        gender_map = {}
        enable_gender = config.get("enable_gender_tts", False)

        if enable_gender:
            audio_info = job_state.get_step_output("s04_audio_separate") or {}
            voice_path = Path(audio_info.get("voice", workspace / "vocals.wav"))

            for idx, seg in enumerate(segments):
                seg_id = str(seg.get("id", idx))
                start = float(seg.get("start", 0.0))
                end = float(seg.get("end", start + 1.0))

                gender = GenderDetector.estimate_segment_f0(voice_path, start, end)
                gender_map[seg_id] = {
                    "start": start,
                    "end": end,
                    "text": seg.get("text", ""),
                    "gender": gender
                }
        else:
            for idx, seg in enumerate(segments):
                seg_id = str(seg.get("id", idx))
                gender_map[seg_id] = {
                    "start": float(seg.get("start", 0.0)),
                    "end": float(seg.get("end", 0.0)),
                    "gender": "unknown"
                }

        out_file = workspace / "s05b_gender.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(gender_map, f, ensure_ascii=False, indent=2)

        return {
            "gender_file": str(out_file),
            "enabled": enable_gender,
            "detected_count": len(gender_map)
        }
