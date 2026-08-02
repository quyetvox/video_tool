import unittest
from pathlib import Path
import tempfile
import json

from core.job_state import JobState
from core.step_base import StepBase


class DummyStep(StepBase):
    step_id = "test_step"
    depends_on = []

    def run(self, workspace: Path, config: dict, job_state: JobState) -> dict:
        return {"status": "ok", "message": "hello world"}


class TestPipelineCore(unittest.TestCase):
    def test_job_state_lifecycle(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace = Path(tmpdir)
            job = JobState(workspace=workspace, input_video="/tmp/fake_video.mp4")

            self.assertEqual(job.data["status"], "pending")
            self.assertFalse(job.is_step_done("test_step"))

            step = DummyStep()
            self.assertFalse(step.can_skip(job.job_dir))

            output = step.run(job.job_dir, {}, job)
            step.mark_done(job.job_dir)
            job.set_step_status(step.step_id, "done", output=output)

            self.assertTrue(step.can_skip(job.job_dir))
            self.assertTrue(job.is_step_done("test_step"))
            self.assertEqual(job.get_step_output("test_step")["message"], "hello world")


if __name__ == "__main__":
    unittest.main()
