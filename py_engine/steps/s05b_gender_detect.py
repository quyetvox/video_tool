import json
from pathlib import Path
from typing import Any, Dict

from core.step_base import StepBase
from utils.gender_detector import GenderDetector


class StepGenderDetect(StepBase):
    step_id = "s05b_gender_detect"
    depends_on = ["s04_audio_separate", "s05_asr"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        out_file = workspace / "s05b_gender.json"

        if config.get("ocr_only", False):
            print("[GenderDetect] ocr_only mode enabled: Bypassing (~0s).")
            with open(out_file, "w", encoding="utf-8") as f:
                json.dump({"speaker_profiles": {}}, f)
            return {
                "skipped": True,
                "gender_file": str(out_file),
                "enabled": False,
                "detected_count": 0
            }

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
            if not voice_path.exists():
                voice_path = workspace / "audio_separated" / "voice.wav"

            gender_map = GenderDetector.classify_segments(voice_path, segments)
        else:
            gender_map = {
                "speaker_profiles": {
                    "SPEAKER_00": {
                        "gender": "unknown",
                        "confidence": 0.5,
                        "f0_median": None,
                        "segment_count": len(segments),
                    }
                }
            }
            for idx, seg in enumerate(segments):
                seg_id = str(seg.get("id", idx))
                gender_map[seg_id] = {
                    "start": float(seg.get("start", 0.0)),
                    "end": float(seg.get("end", 0.0)),
                    "speaker": "SPEAKER_00",
                    "gender": "unknown",
                    "confidence": 0.5,
                    "f0": None
                }

        out_file = workspace / "s05b_gender.json"
        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(gender_map, f, ensure_ascii=False, indent=2)

        return {
            "gender_file": str(out_file),
            "enabled": enable_gender,
            "detected_count": len(gender_map) - (1 if "speaker_profiles" in gender_map else 0),
            "speaker_count": len(gender_map.get("speaker_profiles", {}))
        }
