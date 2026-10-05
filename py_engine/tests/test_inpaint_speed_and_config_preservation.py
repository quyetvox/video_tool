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

    @patch("plugins.inpaint.ffmpeg_blur.subprocess.run")
    @patch("plugins.inpaint.ffmpeg_blur.FFmpegUtils.probe")
    def test_ffmpeg_blur_dynamic_temporal_disappearance(self, mock_probe, mock_subp):
        """Ensure ffmpeg_blur generates enable='between(...)' filters to disappear during long speech pauses."""
        from plugins.inpaint.ffmpeg_blur import Plugin as FFmpegBlurPlugin
        mock_probe.return_value = {
            "streams": [{"codec_type": "video", "width": 1920, "height": 1080}]
        }
        mock_subp.return_value = MagicMock(returncode=0)

        plugin = FFmpegBlurPlugin({"inpaint": "ffmpeg_blur", "inpaint_color": "transparent"})
        dummy_in = self.workspace / "in.mp4"
        dummy_in.touch()
        dummy_out = self.workspace / "out.mp4"
        dummy_out.write_bytes(b"video_bytes")

        # Two segments with large pause (>0.8s): 1.0s -> 3.0s, then pause until 5.0s -> 7.0s
        segments = [
            {"start": 1.0, "end": 3.0, "text": "Câu 1"},
            {"start": 5.0, "end": 7.0, "text": "Câu 2"},
        ]

        plugin.remove_subtitles(
            dummy_in,
            [0.8, 0.1, 0.9, 0.9],
            dummy_out,
            segments=segments
        )

        self.assertTrue(mock_subp.called)
        cmd = mock_subp.call_args[0][0]
        fc_idx = cmd.index("-filter_complex")
        filter_complex = cmd[fc_idx + 1]

        # Verify enable between terms exist for both segments with temporal padding
        self.assertIn("overlay=", filter_complex)
        self.assertIn(":enable='between(t,0.920,3.080)+between(t,4.920,7.080)'", filter_complex)

    @patch("plugins.inpaint.ffmpeg_blur.subprocess.run")
    @patch("plugins.inpaint.ffmpeg_blur.FFmpegUtils.probe")
    def test_ffmpeg_blur_merges_close_intervals(self, mock_probe, mock_subp):
        """Ensure ffmpeg_blur merges segments that are close together (<= 0.20s)."""
        from plugins.inpaint.ffmpeg_blur import Plugin as FFmpegBlurPlugin
        mock_probe.return_value = {
            "streams": [{"codec_type": "video", "width": 1920, "height": 1080}]
        }
        mock_subp.return_value = MagicMock(returncode=0)

        plugin = FFmpegBlurPlugin({"inpaint": "ffmpeg_blur", "inpaint_color": "transparent"})
        dummy_in = self.workspace / "in.mp4"
        dummy_in.touch()
        dummy_out = self.workspace / "out.mp4"
        dummy_out.write_bytes(b"video_bytes")

        # Close segments: 1.0s -> 3.0s and 3.1s -> 4.5s
        segments = [
            {"start": 1.0, "end": 3.0, "text": "Câu 1"},
            {"start": 3.1, "end": 4.5, "text": "Câu 2"},
        ]

        plugin.remove_subtitles(
            dummy_in,
            [0.8, 0.1, 0.9, 0.9],
            dummy_out,
            segments=segments
        )

        self.assertTrue(mock_subp.called)
        cmd = mock_subp.call_args[0][0]
        fc_idx = cmd.index("-filter_complex")
        filter_complex = cmd[fc_idx + 1]

        # Merged into single interval
        self.assertIn(":enable='between(t,0.920,4.580)'", filter_complex)

    @patch("plugins.inpaint.ffmpeg_blur.subprocess.run")
    @patch("plugins.inpaint.ffmpeg_blur.FFmpegUtils.probe")
    def test_ffmpeg_blur_fallback_static_when_no_segments(self, mock_probe, mock_subp):
        """Ensure ffmpeg_blur falls back to static overlay when segments is None or empty."""
        from plugins.inpaint.ffmpeg_blur import Plugin as FFmpegBlurPlugin
        mock_probe.return_value = {
            "streams": [{"codec_type": "video", "width": 1920, "height": 1080}]
        }
        mock_subp.return_value = MagicMock(returncode=0)

        plugin = FFmpegBlurPlugin({"inpaint": "ffmpeg_blur", "inpaint_color": "transparent"})
        dummy_in = self.workspace / "in.mp4"
        dummy_in.touch()
        dummy_out = self.workspace / "out.mp4"
        dummy_out.write_bytes(b"video_bytes")

        plugin.remove_subtitles(
            dummy_in,
            [0.8, 0.1, 0.9, 0.9],
            dummy_out,
            segments=None
        )

        self.assertTrue(mock_subp.called)
        cmd = mock_subp.call_args[0][0]
        fc_idx = cmd.index("-filter_complex")
        filter_complex = cmd[fc_idx + 1]

        # No enable attribute
        self.assertIn("overlay=", filter_complex)
        self.assertNotIn(":enable=", filter_complex)


if __name__ == "__main__":
    unittest.main()

