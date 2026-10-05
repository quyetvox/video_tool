#!/usr/bin/env python3
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch
import sys
import argparse
import tempfile

ENGINE_DIR = Path(__file__).parent.parent.resolve()
sys.path.insert(0, str(ENGINE_DIR))

from vlog_story_orchestrator import VlogStoryOrchestrator, generate_vlog_ass_subtitles


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
    def test_render_final_video_box_color_inpaint(self, mock_exists, mock_probe):
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
                "engine": "box_color",
                "color": "black",
                "opacity": 0.85,
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
            # Kiểm tra inpaint drawbox cho box_color
            self.assertIn("drawbox=", cmd_str)
            self.assertIn("0x000000@0.85", cmd_str)
            # Kiểm tra watermark
            self.assertIn("MyVlogBrand", cmd_str)
            # Kiểm tra subtitles và fontsdir
            self.assertIn("subtitles=", cmd_str)
            self.assertIn("fontsdir=", cmd_str)

    @patch("vlog_story_orchestrator.FFmpegUtils.probe")
    @patch("pathlib.Path.exists")
    def test_render_final_video_blur_inpaint(self, mock_exists, mock_probe):
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
                "engine": "ffmpeg_blur",
                "blur_radius": 18,
                "region": [0.85, 0.10, 0.95, 0.90]
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
            # Kiểm tra inpaint boxblur cho ffmpeg_blur
            self.assertIn("boxblur=", cmd_str)

    def test_generate_vlog_ass_subtitles_config(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            ass_path = Path(tmpdir) / "test_sub.ass"
            dialogues = [
                {"start": 0.0, "end": 2.5, "text": "Chào mừng các bạn đến với vlog hôm nay!"}
            ]
            cfg = {
                "subtitle": {
                    "font_name": "BeVietnamPro-Bold",
                    "font_size": 42,
                    "font_color": "&H0000FFFF",  # Vàng
                    "outline_color": "&H00000000",
                    "outline_width": 4,
                    "region": [0.80, 0.05, 0.92, 0.95]
                }
            }
            out_file = generate_vlog_ass_subtitles(dialogues, ass_path, 1920, 1080, cfg)
            self.assertTrue(out_file.exists())
            content = out_file.read_text(encoding="utf-8")
            self.assertIn("BeVietnamPro-Bold", content)
            self.assertIn("42", content)
            self.assertIn("&H0000FFFF", content)
            self.assertIn("Chào mừng các bạn", content)

    def test_cli_parser_options(self):
        import argparse
        parser = argparse.ArgumentParser()
        parser.add_argument("--config", default="")
        parser.add_argument("--tts-volume", type=float, default=None)
        parser.add_argument("--enable-inpaint", action="store_true", default=False)
        parser.add_argument("--no-inpaint", action="store_true", default=False)

        args = parser.parse_args(["--config", "/tmp/config.yaml", "--tts-volume", "1.25", "--enable-inpaint"])
        self.assertEqual(args.config, "/tmp/config.yaml")
        self.assertEqual(args.tts_volume, 1.25)
        self.assertTrue(args.enable_inpaint)
        self.assertFalse(args.no_inpaint)


if __name__ == "__main__":
    unittest.main()
