from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Dict, List, Optional


class StepBase(ABC):
    step_id: str
    depends_on: List[str] = []

    @abstractmethod
    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        """Execute the pipeline step and return step output dictionary."""
        pass

    def can_skip(self, workspace: Path) -> bool:
        """Check if step has already completed and output checkpoint exists."""
        marker = workspace / f"{self.step_id}.done"
        return marker.exists()

    def mark_done(self, workspace: Path) -> None:
        """Mark step as complete by touching marker file."""
        marker = workspace / f"{self.step_id}.done"
        marker.touch(exist_ok=True)
