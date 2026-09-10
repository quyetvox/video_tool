import unittest
import time
from pathlib import Path
import tempfile
from typing import Dict, Any, List

from core.job_state import JobState
from core.step_base import StepBase
from core.pipeline_runner import PipelineRunner


class MockStep(StepBase):
    def __init__(self, step_id: str, depends_on: List[str], delay_sec: float = 0.05):
        self.step_id = step_id
        self.depends_on = depends_on
        self.delay_sec = delay_sec
        self.execution_order = []

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        if self.delay_sec > 0:
            time.sleep(self.delay_sec)
        return {"step": self.step_id, "timestamp": time.time()}


class TestPipelineConcurrency(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name)
        self.state_file = self.workspace / "job_state.json"
        self.job_state = JobState(self.state_file, job_id="test_concurrency_job")

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_dual_track_inpaint_parallel_execution(self):
        # Steps setup simulating pipeline: s02_demux -> s03_subtitle_detect -> s04_audio -> s10_inpaint -> s11_render
        s02 = MockStep("s02_demux", [], delay_sec=0.02)
        s03 = MockStep("s03_subtitle_detect", ["s02_demux"], delay_sec=0.02)
        s04 = MockStep("s04_audio_separate", ["s02_demux"], delay_sec=0.1)
        s10 = MockStep("s10_inpaint", ["s02_demux", "s03_subtitle_detect"], delay_sec=0.05)
        s11 = MockStep("s11_subtitle_render", ["s10_inpaint"], delay_sec=0.02)

        steps = [s02, s03, s04, s10, s11]
        runner = PipelineRunner(steps, emit_json=True)

        config = {"enable_dual_track": True}
        start_time = time.time()
        success = runner.run(self.job_state, config)
        total_time = time.time() - start_time

        self.assertTrue(success, "Pipeline execution should succeed")
        self.assertTrue(self.job_state.is_step_done("s10_inpaint"))
        self.assertTrue(self.job_state.is_step_done("s11_subtitle_render"))

        # Sequential would take ~0.02 + 0.02 + 0.1 + 0.05 + 0.02 = ~0.21s
        # Dual-track overlaps s10 (0.05s) with s04 (0.1s), total ~0.16s
        self.assertLess(total_time, 0.20, f"Dual-track should overlap s10 and s04: took {total_time:.3f}s")

    def test_dual_track_disabled_runs_sequentially(self):
        s02 = MockStep("s02_demux", [], delay_sec=0.01)
        s03 = MockStep("s03_subtitle_detect", ["s02_demux"], delay_sec=0.01)
        s10 = MockStep("s10_inpaint", ["s02_demux", "s03_subtitle_detect"], delay_sec=0.01)

        steps = [s02, s03, s10]
        runner = PipelineRunner(steps, emit_json=True)

        config = {"enable_dual_track": False}
        success = runner.run(self.job_state, config)
        self.assertTrue(success)
        self.assertTrue(self.job_state.is_step_done("s10_inpaint"))

    def test_job_state_thread_safety(self):
        # Stress test JobState concurrent reads & writes
        import threading
        errors = []

        def worker_writer(idx):
            try:
                for i in range(20):
                    self.job_state.set_step_status(f"step_{idx}", "running")
                    self.job_state.set_step_status(f"step_{idx}", "done", output={"count": i})
                    _ = self.job_state.get_step_output(f"step_{idx}")
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=worker_writer, args=(i,)) for i in range(5)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        self.assertEqual(len(errors), 0, f"Thread safety errors occurred: {errors}")
        self.assertTrue(self.job_state.is_step_done("step_0"))
        self.assertTrue(self.job_state.is_step_done("step_4"))


if __name__ == "__main__":
    unittest.main()
