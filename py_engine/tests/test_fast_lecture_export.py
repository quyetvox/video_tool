"""
Unit and integration tests for Fast Lecture Export Pipeline.
- Test 1: generate_batch_ass (relative timestamps for per-batch subtitle)
- Test 2: compute_batch_fingerprint with subtitle configurations
- Test 3: render_scene_video parameters (24 FPS, audio_path, ass_path)
- Test 4: Concat demuxer fast export verification
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT_PY_ENGINE = Path(__file__).resolve().parent.parent
if str(ROOT_PY_ENGINE) not in sys.path:
    sys.path.insert(0, str(ROOT_PY_ENGINE))

from lecture_illustrator.models import LectureBatch, LectureProjectConfig
from lecture_illustrator.subtitles import generate_batch_ass
from lecture_illustrator.visual_renderer import compute_batch_fingerprint


class TestFastLectureExport(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_generate_batch_ass_relative_timing(self):
        """Kiểm tra generate_batch_ass sinh mốc thời gian tương đối chuẩn xác từ 0.0s."""
        batch = LectureBatch(
            id="batch_001",
            start_sec=10.0,
            end_sec=22.0,
            transcript_original="Hello world. Welcome to lecture.",
            transcript_translated="Xin chào thế giới. Chào mừng đến bài giảng.",
            scene_duration=12.0,
            step_starts=[0.0, 5.0],
            sentences=[
                {
                    "text": "Xin chào thế giới.",
                    "text_orig": "Hello world.",
                    "start": 10.0,
                    "end": 14.5,
                },
                {
                    "text": "Chào mừng đến bài giảng.",
                    "text_orig": "Welcome to lecture.",
                    "start": 15.0,
                    "end": 21.8,
                },
            ],
        )
        config = LectureProjectConfig(
            font_name="Arial",
            font_size="28",
            subtitle_mode="bilingual",
            secondary_scale=0.75,
            burn_subtitles=True,
        )
        ass_path = self.workspace / "batch_001.ass"
        res = generate_batch_ass(
            batch=batch,
            output_ass_path=ass_path,
            config=config,
            video_width=1920,
            video_height=1080,
        )
        self.assertTrue(ass_path.exists())
        content = ass_path.read_text(encoding="utf-8")
        self.assertIn("[Script Info]", content)
        self.assertIn("[V4+ Styles]", content)
        self.assertIn("Dialogue: 0,0:00:00.00,0:00:05.00", content)
        self.assertIn("Xin chào thế giới.", content)
        self.assertIn("Chào mừng đến bài giảng.", content)

    def test_compute_batch_fingerprint_includes_subtitle_config(self):
        """Kiểm tra compute_batch_fingerprint thay đổi khi cấu hình phụ đề thay đổi."""
        batch = LectureBatch(
            id="batch_001",
            start_sec=0.0,
            end_sec=5.0,
            scene_duration=5.0,
            transcript_original="Nội dung gốc",
            transcript_translated="Nội dung kiểm thử",
            sentences=[{"text": "Nội dung kiểm thử"}],
        )
        cfg_default = LectureProjectConfig(
            font_size="26",
            burn_subtitles=True,
            font_color="white",
        )
        cfg_modified_size = LectureProjectConfig(
            font_size="32",
            burn_subtitles=True,
            font_color="white",
        )
        cfg_no_sub = LectureProjectConfig(
            font_size="26",
            burn_subtitles=False,
            font_color="white",
        )

        h1 = compute_batch_fingerprint(batch, cfg_default)
        h2 = compute_batch_fingerprint(batch, cfg_modified_size)
        h3 = compute_batch_fingerprint(batch, cfg_no_sub)

        # Hash phải khác nhau khi đổi font size hoặc tắt sub
        self.assertNotEqual(h1, h2, "Fingerprint phải thay đổi khi đổi font_size")
        self.assertNotEqual(h1, h3, "Fingerprint phải thay đổi khi đổi burn_subtitles")

    def test_render_scene_video_params(self):
        """Kiểm tra render_scene_video có fps=24 mặc định và hỗ trợ audio_path, ass_path."""
        import inspect
        from lecture_illustrator.scene_renderer import render_scene_video

        sig = inspect.signature(render_scene_video)
        self.assertIn("audio_path", sig.parameters)
        self.assertIn("ass_path", sig.parameters)
        self.assertEqual(sig.parameters["fps"].default, 24)


if __name__ == "__main__":
    unittest.main()

