import json
import unittest
from unittest.mock import MagicMock, patch
from pathlib import Path

from steps.s10_inpaint import StepInpaint
from core.job_state import JobState


class TestInpaintSpeedAndConfigPreservation(unittest.TestCase):
    def setUp(self):
        self.workspace = Path("/tmp/test_inpaint_workspace")
        self.workspace.mkdir(parents=True, exist_ok=True)
        self.video_stream = self.workspace / "video_stream.mp4"
        self.video_stream.touch()

    def tearDown(self):
        import shutil
        if self.workspace.exists():
            shutil.rmtree(self.workspace, ignore_errors=True)

    @patch("steps.s10_inpaint.PluginLoader.load_plugin")
    @patch("utils.ffmpeg_utils.FFmpegUtils.validate_watermark_config", return_value=None)
    def test_inpaint_preserves_engine_specific_configs(self, mock_wm, mock_load_plugin):
        """Ensure StepInpaint preserves specific configs for apple_vision, ffmpeg_blur, and box_color."""
        mock_plugin = MagicMock()
        mock_load_plugin.return_value = mock_plugin

        job_state = JobState(self.workspace, "test_job", str(self.video_stream))
        job_state.set_step_status("s02_demux", "done", output={"video_stream": str(self.video_stream)})
        job_state.set_step_status("s03_subtitle_detect", "done", output={"mode": "burnin", "burnin_region": [0.85, 0.05, 0.95, 0.95]})

        config = {
            "inpaint": {
                "show_box": True,
                "engine": "apple_vision_inpaint",
                "method": "vertical_gradient",
                "padding_y": 0.015,
                "blur_radius": 20,
                "region": [0.86, 0.05, 0.97, 0.95],
                "box": {
                    "bg_color": "black",
                    "bg_opacity": 0.75,
                    "border_radius": 8
                }
            }
        }

        step = StepInpaint()
        step.run(self.workspace, config, job_state)

        # Verify PluginLoader received merged_config with all specific parameters preserved
        self.assertTrue(mock_load_plugin.called)
        called_args, called_kwargs = mock_load_plugin.call_args
        merged_cfg = called_args[2]

        self.assertEqual(merged_cfg["inpaint_method"], "vertical_gradient")
        self.assertEqual(merged_cfg["blur_radius"], 20)
        self.assertEqual(merged_cfg["blur_box_padding_y"], 0.015)
        self.assertEqual(merged_cfg["inpaint_region"], [0.86, 0.05, 0.97, 0.95])
        self.assertIn("inpaint_box", merged_cfg)
        self.assertEqual(merged_cfg["inpaint_box"]["bg_color"], "black")

    @patch("steps.s10_inpaint.PluginLoader.load_plugin")
    @patch("utils.ffmpeg_utils.FFmpegUtils.validate_watermark_config", return_value=None)
    def test_inpaint_falls_back_to_s03_burnin_region_when_region_not_in_config(self, mock_wm, mock_load_plugin):
        """When region is not in config, StepInpaint must adopt s03_subtitle_detect burnin_region."""
        mock_plugin = MagicMock()
        mock_load_plugin.return_value = mock_plugin

        job_state = JobState(self.workspace, "test_job", str(self.video_stream))
        job_state.set_step_status("s02_demux", "done", output={"video_stream": str(self.video_stream)})
        job_state.set_step_status("s03_subtitle_detect", "done", output={"mode": "burnin", "burnin_region": [0.80, 0.10, 0.92, 0.90]})

        config = {
            "inpaint": {
                "show_box": True,
                "engine": "ffmpeg_blur"
            }
        }

        step = StepInpaint()
        step.run(self.workspace, config, job_state)

        called_args, _ = mock_load_plugin.call_args
        merged_cfg = called_args[2]
        # Inherits s03 burnin_region with padding
        self.assertIsNotNone(merged_cfg["inpaint_region"])
        self.assertAlmostEqual(merged_cfg["inpaint_region"][1], 0.10)
        self.assertAlmostEqual(merged_cfg["inpaint_region"][3], 0.90)

    def test_ollama_json_resilient_to_control_characters(self):
        """Ensure JSON with literal control characters does not fail."""
        bad_json = '{"segments": [{"id": 0, "text": "Dòng 1\nDòng 2\r\nkhông hợp lệ"}]}'
        # With strict=False
        parsed = json.loads(bad_json, strict=False)
        self.assertIn("segments", parsed)
        self.assertEqual(len(parsed["segments"]), 1)
        self.assertIn("Dòng 1", parsed["segments"][0]["text"])


if __name__ == "__main__":
    unittest.main()
