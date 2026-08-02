import json
import shutil
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional


class JobState:
    def __init__(self, workspace: Path, job_id: Optional[str] = None, input_video: Optional[str] = None, config: Optional[Dict[str, Any]] = None):
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

    def _load(self) -> Dict[str, Any]:
        with open(self.state_file, "r", encoding="utf-8") as f:
            return json.load(f)

    def _save(self) -> None:
        self.data["updated_at"] = datetime.now().isoformat()
        with open(self.state_file, "w", encoding="utf-8") as f:
            json.dump(self.data, f, ensure_ascii=False, indent=2)

    def set_step_status(self, step_id: str, status: str, output: Optional[Dict[str, Any]] = None, error: Optional[str] = None) -> None:
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
        step_data = self.data["steps"].get(step_id, {})
        return step_data.get("output")

    def is_step_done(self, step_id: str) -> bool:
        return self.data["steps"].get(step_id, {}).get("status") == "done"

    def invalidate_step(self, step_id: str) -> None:
        if step_id in self.data["steps"]:
            self.data["steps"][step_id]["status"] = "pending"
            self._save()
        done_file = self.job_dir / f"{step_id}.done"
        if done_file.exists():
            done_file.unlink(missing_ok=True)

    def mark_completed(self) -> None:
        self.data["status"] = "completed"
        self._save()

    def mark_failed(self, error: str) -> None:
        self.data["status"] = "failed"
        self.data["error"] = error
        self._save()

    def cleanup(self) -> None:
        """Cleanup transient files upon successful completion if required."""
        pass
