import unittest
from pathlib import Path
import tempfile
import json
import sys

sys.path.insert(0, str(Path(__file__).parent.parent.resolve()))

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

    def test_inpaint_show_box_toggle(self):
        from steps.s10_inpaint import StepInpaint
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace = Path(tmpdir)
            job = JobState(workspace=workspace, input_video=str(workspace / "fake.mp4"))
            
            # Create a fake input video stream
            demux_dir = workspace / "demux"
            demux_dir.mkdir(parents=True, exist_ok=True)
            fake_video = demux_dir / "video_stream.mp4"
            fake_video.write_bytes(b"dummy_video_bytes")
            job.set_step_status("s02_demux", "done", output={"video_stream": str(fake_video)})
            job.set_step_status("s03_subtitle_detect", "done", output={"mode": "burnin", "burnin_region": [0.8, 0.1, 0.9, 0.9]})

            step = StepInpaint()
            # When show_box is False, inpaint should be skipped
            config_no_box = {"inpaint": {"show_box": False, "engine": "apple_vision_inpaint"}}
            res_disabled = step.run(workspace, config_no_box, job)
            self.assertFalse(res_disabled["inpaint_applied"])
            self.assertTrue(Path(res_disabled["clean_video"]).exists())


if __name__ == "__main__":
    unittest.main()
