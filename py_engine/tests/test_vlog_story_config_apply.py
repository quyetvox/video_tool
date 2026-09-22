#!/usr/bin/env python3
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch
import sys
import argparse

ENGINE_DIR = Path(__file__).parent.parent.resolve()
sys.path.insert(0, str(ENGINE_DIR))

from vlog_story_orchestrator import VlogStoryOrchestrator


class TestVlogStoryConfigApply(unittest.TestCase):
    def setUp(self):
        self.dummy_video = Path("/tmp/dummy_vlog.mp4")

    @patch("vlog_story_orchestrator.FFmpegUtils.probe")
    @patch("pathlib.Path.exists")
    def test_mix_audio_track_tts_volume_filter(self, mock_exists, mock_probe):
        mock_exists.return_value = True
        mock_probe.return_value = {
            "format": {"duration": "60.0"},
            "streams": [
                {"codec_type": "video", "width": 1920, "height": 1080, "r_frame_rate": "30/1"},
                {"codec_type": "audio"}
            ]
        }

        orch = VlogStoryOrchestrator(video_path=self.dummy_video)
        voice_wav = Path("/tmp/test_voice.wav")
        bgm_wav = Path("/tmp/test_bgm.wav")

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            # Test mix with BGM and custom tts_volume = 1.35
            orch.mix_audio_track(voice_wav=voice_wav, bgm_path=bgm_wav, bgm_volume=0.20, tts_volume=1.35)
            self.assertTrue(mock_run.called)
            cmd = mock_run.call_args[0][0]
            cmd_str = " ".join(cmd)
            self.assertIn("[0:a]volume=1.35[v_voice]", cmd_str)
            self.assertIn("volume=0.20", cmd_str)

    @patch("vlog_story_orchestrator.FFmpegUtils.probe")
    @patch("pathlib.Path.exists")
    def test_render_final_video_single_pass_filters(self, mock_exists, mock_probe):
        mock_exists.return_value = True
        mock_probe.return_value = {
            "format": {"duration": "30.0"},
            "streams": [
                {"codec_type": "video", "width": 1920, "height": 1080, "r_frame_rate": "30/1"},
                {"codec_type": "audio"}
            ]
        }

        config = {
            "inpaint": {
                "show_box": True,
                "blur_radius": 18,
                "region": [0.85, 0.10, 0.95, 0.90]
            },
            "watermark": {
                "enabled": True,
                "text": "MyVlogBrand",
                "region": [0.02, 0.70, 0.08, 0.90]
            },
            "subtitle": {
                "fonts_dir": "resources/fonts"
            }
        }

        orch = VlogStoryOrchestrator(video_path=self.dummy_video, config=config)
        mixed_audio = Path("/tmp/mixed.wav")
        ass_sub = Path("/tmp/test.ass")

        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(returncode=0)
            orch.render_final_video(
                mixed_audio=mixed_audio,
                ass_sub=ass_sub,
                burn_subtitles=True,
                enable_inpaint=True
            )
            self.assertTrue(mock_run.called)
            cmd = mock_run.call_args[0][0]
            cmd_str = " ".join(cmd)
            # Kiểm tra single pass filter_complex
            self.assertIn("-filter_complex", cmd)
            # Kiểm tra inpaint
            self.assertIn("boxblur", cmd_str)
            # Kiểm tra watermark
            self.assertIn("MyVlogBrand", cmd_str)
            # Kiểm tra subtitles và fontsdir
            self.assertIn("subtitles=", cmd_str)
            self.assertIn("fontsdir=", cmd_str)

    def test_cli_parser_options(self):
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--tts-volume", type=float, default=None)
        parser.add_argument("--enable-inpaint", action="store_true", default=False)
        parser.add_argument("--no-inpaint", action="store_true", default=False)

        args = parser.parse_args(["--tts-volume", "1.25", "--enable-inpaint"])
        self.assertEqual(args.tts_volume, 1.25)
        self.assertTrue(args.enable_inpaint)
        self.assertFalse(args.no_inpaint)


if __name__ == "__main__":
    unittest.main()
