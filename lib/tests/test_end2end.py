import unittest
import subprocess
import tempfile
from pathlib import Path
import json

from core.job_state import JobState
from core.pipeline_runner import PipelineRunner
from main import build_pipeline


class TestEndToEndPipeline(unittest.TestCase):
    def test_full_pipeline_run(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmppath = Path(tmpdir)
            test_video = tmppath / "test_sample.mp4"
            
            # Generate a 3-second synthetic video with audio using ffmpeg
            cmd = [
                "ffmpeg", "-y",
                "-f", "lavfi", "-i", "color=c=blue:s=640x480:d=3",
                "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
                "-c:v", "libx264", "-c:a", "aac",
                str(test_video)
            ]
            subprocess.run(cmd, capture_output=True, check=True)

            workspace = tmppath / "workspace"
            config = {
                "workspace_dir": str(workspace),
                "device": "cpu",
                "asr": "whisper_fallback",
                "translator": "ollama_qwen",
                "tts": "preset_tts",
                "ocr": "paddle_ocr",
                "inpaint": "opencv_inpaint",
                "target_lang": "vi",
                "output_suffix": "_vi"
            }

            job = JobState(workspace=workspace, input_video=str(test_video), config=config)
            runner = build_pipeline()
            success = runner.run(job, config)

            self.assertTrue(success)
            self.assertEqual(job.data["status"], "completed")
            self.assertTrue(job.is_step_done("s01_probe"))
            self.assertTrue(job.is_step_done("s02_demux"))
            self.assertTrue(job.is_step_done("s03_subtitle_detect"))
            self.assertTrue(job.is_step_done("s14_encode"))

            encode_out = job.get_step_output("s14_encode")
            self.assertIsNotNone(encode_out)
            output_file = Path(encode_out["output_file"])
            self.assertTrue(output_file.exists())


if __name__ == "__main__":
    unittest.main()
