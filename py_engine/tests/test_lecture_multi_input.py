"""
Unit tests for AI Lecture Illustrator Multi-Format Input (Text, Audio, Video).
"""

import tempfile
import unittest
from pathlib import Path
import sys

ENGINE_DIR = Path(__file__).parent.parent.resolve()
if str(ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(ENGINE_DIR))

from lecture_illustrator.models import LectureProjectConfig
from lecture_illustrator.text_script_parser import (
    read_text_file_safe,
    split_sentences_natural,
    parse_markdown_blocks,
    parse_text_file_to_sentences,
)


class TestLectureMultiInput(unittest.TestCase):

    def test_read_text_file_safe_utf8_and_newlines(self):
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".txt") as tf:
            tf.write("Dòng 1: Giới thiệu bài giảng.\r\nDòng 2: Nội dung chi tiết.\n")
            temp_path = Path(tf.name)

        try:
            content = read_text_file_safe(temp_path)
            self.assertIn("Dòng 1: Giới thiệu bài giảng.", content)
            self.assertIn("Dòng 2: Nội dung chi tiết.", content)
            self.assertNotIn("\r", content)
        finally:
            temp_path.unlink(missing_ok=True)

    def test_split_sentences_natural(self):
        text = "Chào mừng các bạn đến với khóa học lập trình. Hôm nay chúng ta sẽ tìm hiểu về Docker! Docker là gì? Hãy cùng khám phá."
        sentences = split_sentences_natural(text)
        self.assertEqual(len(sentences), 4)
        self.assertEqual(sentences[0], "Chào mừng các bạn đến với khóa học lập trình.")
        self.assertEqual(sentences[1], "Hôm nay chúng ta sẽ tìm hiểu về Docker!")
        self.assertEqual(sentences[2], "Docker là gì?")
        self.assertEqual(sentences[3], "Hãy cùng khám phá.")

    def test_parse_markdown_blocks(self):
        md_content = """# Bài 1: Kiến Trúc Hướng Sự Kiện

Kiến trúc hướng sự kiện giúp giảm bớt sự phụ thuộc giữa các dịch vụ.

- Sự kiện được phát đi từ Publisher.
- Broker chuyển tiếp thông điệp.
- Consumer nhận và xử lý sự kiện.

```python
def publish(event):
    print("Sent event:", event)
```
"""
        blocks = parse_markdown_blocks(md_content)
        self.assertTrue(any(b["type_hint"] == "title_point" for b in blocks))
        self.assertTrue(any(b["type_hint"] == "bullet_list" for b in blocks))
        self.assertTrue(any(b["type_hint"] == "code_block" for b in blocks))
        self.assertTrue(any(b["type_hint"] == "auto" for b in blocks))

    def test_parse_text_file_to_sentences(self):
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False, suffix=".md") as tf:
            tf.write("# Lập Trình Bất Đồng Bộ\n\nAsyncio cho phép xử lý I/O non-blocking.\n\n- Tăng thông lượng ứng dụng.\n- Giảm độ trễ.")
            temp_path = Path(tf.name)

        try:
            cfg = LectureProjectConfig(target_lang="vi")
            sentences = parse_text_file_to_sentences(temp_path, cfg)
            self.assertGreaterEqual(len(sentences), 3)
            self.assertEqual(sentences[0]["text"], "Lập Trình Bất Đồng Bộ")
            self.assertEqual(sentences[0]["type_hint"], "title_point")
            self.assertIn("Asyncio cho phép", sentences[1]["text"])
        finally:
            temp_path.unlink(missing_ok=True)


    def test_detect_input_type(self):
        from lecture_illustrator_orchestrator import detect_input_type
        self.assertEqual(detect_input_type(Path("lecture.txt")), "text")
        self.assertEqual(detect_input_type(Path("lesson.md")), "text")
        self.assertEqual(detect_input_type(Path("audio.mp3")), "audio")
        self.assertEqual(detect_input_type(Path("voice.wav")), "audio")
        self.assertEqual(detect_input_type(Path("video.mp4")), "video")
        self.assertEqual(detect_input_type(Path("clip.mov")), "video")

    def test_run_analyze_flow_from_text(self):
        import argparse
        import json
        from lecture_illustrator_orchestrator import run_analyze_flow

        with tempfile.TemporaryDirectory() as td:
            temp_dir = Path(td)
            text_file = temp_dir / "lesson.md"
            text_file.write_text("# Khái Niệm Cơ Bản\n\nĐây là bài học mở đầu.\n\n- Ý số một.\n- Ý số hai.", encoding="utf-8")

            args = argparse.Namespace(
                input=str(text_file),
                video=None,
                workspace=str(temp_dir / ".workspace"),
                project_name="test_text_proj",
                project_file=str(temp_dir / "lecture_project.json"),
                raw_article=False,
                api_key=None,
                base_url=None,
                model="gemini-2.5-flash",
                source_lang="auto",
                target_lang="vi",
                secondary_lang="en",
                pronoun_mode="formal",
                voice_mode="original",
                tts_voice="ban_mai",
                tts_speed=1.15,
                bgm_volume=0.1,
                voice_volume=1.0,
                burn_subtitles="true",
                subtitle_mode="single",
                subtitle_secondary_show="false",
                subtitle_order="primary_top",
                layout_preset="pip",
                watermark_enabled="false",
                watermark_path=None,
                enable_inpaint="false",
                inpaint_engine="ffmpeg_blur",
                inpaint_blur_radius=20,
                box_bg_color="#000000",
                box_opacity=0.85,
                inpaint_method="vertical_gradient",
            )

            # Mock tts synthesis để test chạy nhanh trong 0.1s
            from unittest.mock import patch
            with patch("lecture_illustrator.scene_planner.synthesize_sentences", return_value=[2.0, 2.5, 2.0, 2.0]):
                res = run_analyze_flow(args)
                self.assertEqual(res, 0)

            out_proj = temp_dir / "lecture_project.json"
            self.assertTrue(out_proj.exists())
            data = json.loads(out_proj.read_text(encoding="utf-8"))
            self.assertEqual(data["project_name"], "test_text_proj")
            self.assertGreaterEqual(len(data["batches"]), 1)

    def test_default_voice_mode_is_tts_dub(self):
        cfg = LectureProjectConfig()
        self.assertEqual(cfg.voice_mode, "tts_dub")
        data = cfg.to_dict()
        self.assertEqual(data["voice_mode"], "tts_dub")
        loaded = LectureProjectConfig.from_dict({})
        self.assertEqual(loaded.voice_mode, "tts_dub")

    def test_audio_input_default_flow_calls_tts_synthesize(self):
        import argparse
        import json
        from unittest.mock import patch, MagicMock
        from lecture_illustrator_orchestrator import run_analyze_flow

        with tempfile.TemporaryDirectory() as td:
            temp_dir = Path(td)
            audio_file = temp_dir / "speech.mp3"
            audio_file.write_bytes(b"dummy mp3 data")

            mock_segments = [
                {"start": 0.0, "end": 2.5, "text": "Hello world", "words": []},
                {"start": 2.5, "end": 5.0, "text": "Welcome to lecture", "words": []},
            ]
            mock_sentences = [
                {"start": 0.0, "end": 2.5, "text": "Xin chào thế giới", "text_orig": "Hello world", "type_hint": "auto"},
                {"start": 2.5, "end": 5.0, "text": "Chào mừng đến với bài giảng", "text_orig": "Welcome to lecture", "type_hint": "auto"},
            ]

            args = argparse.Namespace(
                input=str(audio_file),
                video=None,
                workspace=str(temp_dir / ".workspace"),
                project_name="test_audio_proj",
                project_file=str(temp_dir / "lecture_project.json"),
                raw_article=False,
                api_key=None,
                base_url=None,
                model="gemini-2.5-flash",
                source_lang="en",
                target_lang="vi",
                secondary_lang="en",
                pronoun_mode="formal",
                voice_mode=None,  # Để trống -> phải dùng mặc định tts_dub
                tts_voice="ban_mai",
                tts_speed=1.15,
                bgm_volume=0.1,
                voice_volume=1.0,
                burn_subtitles="true",
                subtitle_mode="bilingual",
                subtitle_secondary_show="true",
                subtitle_order="primary_top",
                layout_preset="pip",
                watermark_enabled="false",
                watermark_path=None,
                enable_inpaint="false",
                inpaint_engine="ffmpeg_blur",
                inpaint_blur_radius=20,
                box_bg_color="#000000",
                box_opacity=0.85,
                inpaint_method="vertical_gradient",
            )

            with patch("lecture_illustrator_orchestrator.FFmpegUtils.probe", return_value={"format": {"duration": "10.0"}, "streams": [{"codec_type": "audio"}]}), \
                 patch("lecture_illustrator_orchestrator.transcribe_media_audio", return_value=mock_segments), \
                 patch("lecture_illustrator_orchestrator.translate_sentences", return_value=mock_sentences), \
                 patch("lecture_illustrator_orchestrator.synthesize_sentences", return_value=[2.5, 2.5]) as mock_tts, \
                 patch("lecture_illustrator_orchestrator.extract_original_audio_sentences") as mock_orig:
                res = run_analyze_flow(args)
                self.assertEqual(res, 0)
                # Đảm bảo TTS được gọi để tạo giọng mới, KHÔNG gọi cắt giọng gốc
                mock_tts.assert_called_once()
                mock_orig.assert_not_called()

            # Kiểm tra file project json được lưu có voice_mode: tts_dub
            out_proj = temp_dir / "lecture_project.json"
            self.assertTrue(out_proj.exists())
            proj_data = json.loads(out_proj.read_text(encoding="utf-8"))
            self.assertEqual(proj_data["config"]["voice_mode"], "tts_dub")


if __name__ == "__main__":
    unittest.main()

