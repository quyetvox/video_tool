import json
import shutil
import threading
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional, List

STEP_ORDER = [
    "s01_probe",
    "s02_demux",
    "s03_subtitle_detect",
    "s04_audio_separate",
    "s05_asr",
    "s05b_gender_detect",
    "s06_ocr",
    "s07_transcript_merge",
    "s08_translation",
    "s08b_metadata_gen",
    "s08c_timing",
    "s09_subtitle_gen",
    "s10_inpaint",
    "s11_subtitle_render",
    "s12_tts",
    "s13_audio_mix",
    "s14_encode"
]

STEP_DEPENDENCIES = {
    "s01_probe": [],
    "s02_demux": ["s01_probe"],
    "s03_subtitle_detect": ["s01_probe", "s02_demux"],
    "s04_audio_separate": ["s02_demux"],
    "s05_asr": ["s04_audio_separate"],
    "s05b_gender_detect": ["s04_audio_separate", "s05_asr"],
    "s06_ocr": ["s01_probe", "s03_subtitle_detect"],
    "s07_transcript_merge": ["s05_asr", "s06_ocr"],
    "s08_translation": ["s07_transcript_merge"],
    "s08b_metadata_gen": ["s08_translation"],
    "s08c_timing": ["s08_translation"],
    "s09_subtitle_gen": ["s08_translation", "s08c_timing", "s03_subtitle_detect"],
    "s10_inpaint": ["s02_demux", "s03_subtitle_detect"],
    "s11_subtitle_render": ["s10_inpaint", "s09_subtitle_gen"],
    "s12_tts": ["s08_translation", "s05b_gender_detect"],
    "s13_audio_mix": ["s04_audio_separate", "s12_tts"],
    "s14_encode": ["s11_subtitle_render", "s13_audio_mix"]
}

STEP_ARTIFACTS = {
    "s01_probe": ["s01_probe.json", "s01_probe.done"],
    "s02_demux": ["demux", "s02_demux.done"],
    "s03_subtitle_detect": ["s03_subtitle_detect.done"],
    "s04_audio_separate": ["audio_separated", "s04_audio_separate.done"],
    "s05_asr": ["s05_asr.json", "s05_asr.done"],
    "s05b_gender_detect": ["s05b_gender.json", "s05b_gender_detect.done"],
    "s06_ocr": ["s06_ocr.json", "s06_ocr.done"],
    "s07_transcript_merge": ["s07_transcript.json", "s07_transcript_merge.done"],
    "s08_translation": ["s08_translation.json", "s08_translation.done"],
    "s08b_metadata_gen": ["s08b_metadata.json", "s08b_metadata_gen.done"],
    "s08c_timing": ["s08c_timing.json", "s08c_timing.done"],
    "s09_subtitle_gen": ["subtitles.srt", "subtitles_vi.srt", "subtitles_vi.ass", "s09_subtitle_gen.done"],
    "s10_inpaint": ["clean_video.mp4", "s10_inpaint.done"],
    "s11_subtitle_render": ["video_with_subtitles.mp4", "s11_subtitle_render.done"],
    "s12_tts": ["tts_segments", "tts_audio.wav", "translated_voice.wav", "s12_tts.done"],
    "s13_audio_mix": ["mixed_audio.wav", "final_mixed_audio.wav", "s13_audio_mix.done"],
    "s14_encode": ["s14_encode.done"]
}


def get_downstream_steps(target_step_id: str) -> list:
    """Finds target_step_id and all transitive downstream steps that depend on it."""
    if target_step_id not in STEP_ORDER:
        return [target_step_id]

    affected = {target_step_id}
    changed = True
    while changed:
        changed = False
        for step_id, deps in STEP_DEPENDENCIES.items():
            if step_id not in affected:
                if any(dep in affected for dep in deps):
                    affected.add(step_id)
                    changed = True

    return [step for step in STEP_ORDER if step in affected]


class JobState:
    def __init__(self, workspace: Path, job_id: Optional[str] = None, input_video: Optional[str] = None, config: Optional[Dict[str, Any]] = None):
        self._lock = threading.RLock()
        self.workspace = workspace
        self.job_id = job_id or f"job_{uuid.uuid4().hex[:8]}"
        self.job_dir = self.workspace / self.job_id
        self.job_dir.mkdir(parents=True, exist_ok=True)
        self.state_file = self.job_dir / "state.json"
        
        if self.state_file.exists():
            self.data = self._load()
        else:
            self.data = {
                "job_id": self.job_id,
                "input_video": input_video or "",
                "created_at": datetime.now().isoformat(),
                "status": "pending",
                "config": config or {},
                "steps": {}
            }
            self._save()

    def _normalize_paths(self, val: Any) -> Any:
        if isinstance(val, str):
            if "/assets/" in val and not Path(val).exists():
                rel_parts = val[val.find("/assets/") + 1:]
                resolved = Path.cwd() / rel_parts
                if resolved.exists():
                    return str(resolved)
            return val
        elif isinstance(val, dict):
            return {k: self._normalize_paths(v) for k, v in val.items()}
        elif isinstance(val, list):
            return [self._normalize_paths(v) for v in val]
        return val

    def _load(self) -> Dict[str, Any]:
        with self._lock:
            with open(self.state_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            return self._normalize_paths(data)

    def _save(self) -> None:
        with self._lock:
            self.data["updated_at"] = datetime.now().isoformat()
            with open(self.state_file, "w", encoding="utf-8") as f:
                json.dump(self.data, f, ensure_ascii=False, indent=2)

    def set_step_status(self, step_id: str, status: str, output: Optional[Dict[str, Any]] = None, error: Optional[str] = None) -> None:
        with self._lock:
            if step_id not in self.data["steps"]:
                self.data["steps"][step_id] = {}
            
            self.data["steps"][step_id]["status"] = status
            self.data["steps"][step_id]["updated_at"] = datetime.now().isoformat()
            if output is not None:
                self.data["steps"][step_id]["output"] = output
            if error is not None:
                self.data["steps"][step_id]["error"] = error
            
            self._save()

    def get_step_output(self, step_id: str) -> Optional[Dict[str, Any]]:
        with self._lock:
            step_data = self.data["steps"].get(step_id, {})
            return step_data.get("output")

    def is_step_done(self, step_id: str) -> bool:
        with self._lock:
            return self.data["steps"].get(step_id, {}).get("status") == "done"

    def invalidate_step(self, step_id: str) -> None:
        with self._lock:
            if step_id in self.data["steps"]:
                self.data["steps"][step_id]["status"] = "pending"
                self._save()
            done_file = self.job_dir / f"{step_id}.done"
            if done_file.exists():
                done_file.unlink(missing_ok=True)

    def clear_step(self, step_id: str, delete_artifacts: bool = True) -> list:
        """Invalidates step_id and all downstream steps, deleting their artifacts."""
        with self._lock:
            affected_steps = get_downstream_steps(step_id)
            for s_id in affected_steps:
                if s_id in self.data["steps"]:
                    self.data["steps"][s_id]["status"] = "pending"
                    self.data["steps"][s_id].pop("error", None)

                done_file = self.job_dir / f"{s_id}.done"
                if done_file.exists():
                    done_file.unlink(missing_ok=True)

                if delete_artifacts:
                    artifacts = STEP_ARTIFACTS.get(s_id, [])
                    for art in artifacts:
                        art_path = self.job_dir / art
                        if art_path.exists():
                            if art_path.is_dir():
                                shutil.rmtree(art_path, ignore_errors=True)
                            else:
                                art_path.unlink(missing_ok=True)

            self.data["status"] = "pending"
            self.data.pop("error", None)
            self._save()
            return affected_steps

    def delete_job(self) -> bool:
        """Deletes the entire job directory."""
        with self._lock:
            if self.job_dir.exists():
                shutil.rmtree(self.job_dir, ignore_errors=True)
                return True
            return False

    def mark_completed(self) -> None:
        with self._lock:
            self.data["status"] = "completed"
            self._save()

    def mark_failed(self, error: str) -> None:
        with self._lock:
            self.data["status"] = "failed"
            self.data["error"] = error
            self._save()

    def cleanup(self) -> None:
        """Cleanup transient files upon successful completion if required."""
        pass

