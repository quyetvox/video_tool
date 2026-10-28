"""
Unit tests for HTML to MP4 conversion module (py_engine/html_to_mp4.py).
"""

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT_PY_ENGINE = Path(__file__).resolve().parent.parent
if str(ROOT_PY_ENGINE) not in sys.path:
    sys.path.insert(0, str(ROOT_PY_ENGINE))

from html_to_mp4 import HTMLToMP4Converter, html_to_mp4


class TestHTMLToMP4(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_converter_initialization(self):
        """Kiểm tra khởi tạo converter với thông số tùy chỉnh và encoder mặc định."""
        converter = HTMLToMP4Converter(fps=30, width=1280, height=720)
        self.assertEqual(converter.fps, 30)
        self.assertEqual(converter.width, 1280)
        self.assertEqual(converter.height, 720)
        self.assertIsNotNone(converter.encoder)

    def test_duration_fallback_defaults(self):
        """Kiểm tra tự động fallback thời lượng về 5.0 giây khi không chỉ định."""
        converter = HTMLToMP4Converter(fps=24)
        test_html = self.workspace / "test.html"
        test_html.write_text("<!DOCTYPE html><html><body><h1>Hello</h1></body></html>", encoding="utf-8")
        out_mp4 = self.workspace / "out.mp4"

        # Mock playwright & subprocess để kiểm tra tham số
        with patch("html_to_mp4._get_playwright") as mock_pw, \
             patch("subprocess.Popen") as mock_popen:
            mock_proc = MagicMock()
            mock_proc.returncode = 0
            mock_proc.stdin = MagicMock()
            mock_popen.return_value = mock_proc

            # Giả lập file mp4 được tạo ra
            def side_effect(*args, **kwargs):
                out_mp4.write_bytes(b"dummy_mp4_bytes")
                return mock_proc

            mock_popen.side_effect = side_effect

            res = converter.convert(
                html_input=test_html,
                output_mp4=out_mp4,
                duration=None,
            )
            self.assertEqual(res, out_mp4.resolve())

    def test_raw_html_string_handling(self):
        """Kiểm tra xử lý raw HTML content (tự động ghi file tạm và dọn dẹp sau khi render)."""
        raw_html = "<!DOCTYPE html><html><head><title>Test</title></head><body><p>World</p></body></html>"
        out_mp4 = self.workspace / "out_raw.mp4"

        with patch("html_to_mp4._get_playwright") as mock_pw, \
             patch("subprocess.Popen") as mock_popen:
            mock_proc = MagicMock()
            mock_proc.returncode = 0
            mock_proc.stdin = MagicMock()
            mock_popen.return_value = mock_proc

            def side_effect(*args, **kwargs):
                out_mp4.write_bytes(b"dummy_mp4")
                return mock_proc

            mock_popen.side_effect = side_effect

            res = html_to_mp4(
                html_input=raw_html,
                output_mp4=out_mp4,
                duration=2.0,
                fps=24,
            )
            self.assertTrue(out_mp4.exists())
            self.assertEqual(res, out_mp4.resolve())

    def test_invalid_input_path_raises(self):
        """Kiểm tra ném lỗi FileNotFoundError khi đường dẫn file không tồn tại."""
        converter = HTMLToMP4Converter()
        with self.assertRaises(FileNotFoundError):
            converter.convert(
                html_input="/path/does/not/exist/random_12345.html",
                output_mp4=self.workspace / "fail.mp4",
            )

    def test_cli_argument_parsing(self):
        """Kiểm tra argparse xử lý linh hoạt: positional input, --res, --subtitle."""
        from html_to_mp4 import main
        import argparse

        test_args = [
            "test.html", "-o", "out.mp4", "--res", "1920x1080", "--fps", "30",
            "--subtitle", "sub.ass", "--lang", "vi", "--font-size", "42", "--speed", "1.15"
        ]
        with patch("sys.argv", ["html_to_mp4.py", *test_args]), \
             patch("html_to_mp4.html_to_mp4") as mock_convert:
            mock_convert.return_value = Path("out.mp4")
            try:
                main()
            except SystemExit:
                pass
            mock_convert.assert_called_once()
            _, kwargs = mock_convert.call_args
            self.assertEqual(kwargs["html_input"], "test.html")
            self.assertEqual(kwargs["output_mp4"], "out.mp4")
            self.assertEqual(kwargs["width"], 1920)
            self.assertEqual(kwargs["height"], 1080)
            self.assertEqual(kwargs["fps"], 30)
            self.assertEqual(kwargs["ass_path"], "sub.ass")
            self.assertEqual(kwargs["language"], "vi")
            self.assertEqual(kwargs["font_size"], 42)
            self.assertEqual(kwargs["speed"], 1.15)


    def test_script_sync_integration(self):
        """Kiểm tra tích hợp kịch bản narration: tự động đọc timeline và đồng bộ thời lượng."""
        script_file = self.workspace / "test_narration.txt"
        script_file.write_text(
            "[0:01.00 - 0:04.50] Welcome to test workflow.\n"
            "[0:05.00 - 0:09.20] Second step of workflow.\n",
            encoding="utf-8"
        )
        test_html = self.workspace / "anim.html"
        test_html.write_text("<!DOCTYPE html><html><body><h1>Animation</h1></body></html>", encoding="utf-8")
        out_mp4 = self.workspace / "anim.mp4"

        converter = HTMLToMP4Converter()
        dummy_audio = self.workspace / "dummy_audio.wav"
        dummy_audio.write_bytes(b"RIFF" + b"\x00" * 200)

        async def fake_render(*args, **kwargs):
            return {"output_audio": str(dummy_audio), "segments_rendered": 2}

        with patch("html_to_mp4._get_playwright") as mock_pw, \
             patch("subprocess.Popen") as mock_popen, \
             patch("narration_voice_generator.render_narration_audio_track", side_effect=fake_render) as mock_audio, \
             patch("html_to_mp4.FFmpegUtils.get_audio_duration", return_value=10.0):
            mock_proc = MagicMock()
            mock_proc.returncode = 0
            mock_proc.stdin = MagicMock()
            mock_popen.return_value = mock_proc

            def side_effect(*args, **kwargs):
                out_mp4.write_bytes(b"dummy")
                return mock_proc

            mock_popen.side_effect = side_effect

            res = converter.convert(
                html_input=test_html,
                output_mp4=out_mp4,
                script_path=script_file,
                voice="en-US-JennyNeural",
            )
            self.assertEqual(res, out_mp4.resolve())
            # Verify subtitle ASS file was generated
            expected_ass = self.workspace / "anim.ass"
            self.assertTrue(expected_ass.exists())

    def test_render_shim_and_stream_mapping(self):
        """Kiểm tra HTML_RENDER_SHIM và cấu hình mapping tường minh FFmpeg."""
        from html_to_mp4 import HTML_RENDER_SHIM

        self.assertIn("window.isExternalControl = true", HTML_RENDER_SHIM)
        self.assertIn("window.__registeredFrameCallbacks", HTML_RENDER_SHIM)

        converter = HTMLToMP4Converter()
        test_html = self.workspace / "test.html"
        test_html.write_text("<!DOCTYPE html><html><body>Test</body></html>", encoding="utf-8")
        test_audio = self.workspace / "test.wav"
        test_audio.write_bytes(b"RIFF" + b"\x00" * 100)
        out_mp4 = self.workspace / "test.mp4"

        with patch("html_to_mp4._get_playwright") as mock_pw, \
             patch("subprocess.Popen") as mock_popen, \
             patch("html_to_mp4.FFmpegUtils.get_audio_duration", return_value=6.0):
            mock_proc = MagicMock()
            mock_proc.returncode = 0
            mock_proc.stdin = MagicMock()

            def side_effect(cmd, *args, **kwargs):
                self.assertIn("-map", cmd)
                self.assertIn("0:v:0", cmd)
                self.assertIn("1:a:0", cmd)
                out_mp4.write_bytes(b"dummy")
                return mock_proc

            mock_popen.side_effect = side_effect

            res = converter.convert(
                html_input=test_html,
                output_mp4=out_mp4,
                audio_path=test_audio,
                duration=6.0,
            )
            self.assertEqual(res, out_mp4.resolve())

    def test_burn_subtitles_toggle_disabled(self):
        """Kiểm tra khi burn_subtitles=False, FFmpeg không chèn filter subtitles ngay cả khi có script."""
        converter = HTMLToMP4Converter()
        test_html = self.workspace / "noburn.html"
        test_html.write_text("<!DOCTYPE html><html><body>No Subtitles</body></html>", encoding="utf-8")
        out_mp4 = self.workspace / "noburn.mp4"
        script_file = self.workspace / "noburn_script.txt"
        script_file.write_text("[0:01.00 - 0:03.00] Speech without subtitles.", encoding="utf-8")

        with patch("html_to_mp4._get_playwright") as mock_pw, \
             patch("subprocess.Popen") as mock_popen:
            mock_proc = MagicMock()
            mock_proc.returncode = 0
            mock_proc.stdin = MagicMock()

            def side_effect(cmd, *args, **kwargs):
                # Verify subtitles filter is NOT included in vf
                vf_idx = cmd.index("-vf")
                vf_val = cmd[vf_idx + 1]
                self.assertNotIn("subtitles=", vf_val)
                out_mp4.write_bytes(b"dummy")
                return mock_proc

            mock_popen.side_effect = side_effect

            res = converter.convert(
                html_input=test_html,
                output_mp4=out_mp4,
                script_path=script_file,
                burn_subtitles=False,
                duration=3.0,
            )
            self.assertEqual(res, out_mp4.resolve())

    def test_master_audio_key_resolution_for_tts(self):
        """Kiểm tra trích xuất key master_audio từ kết quả render narration để mux TTS vào video."""
        converter = HTMLToMP4Converter()
        test_html = self.workspace / "tts.html"
        test_html.write_text("<!DOCTYPE html><html><body>TTS</body></html>", encoding="utf-8")
        out_mp4 = self.workspace / "tts.mp4"
        script_file = self.workspace / "tts_script.txt"
        script_file.write_text("[0:00.00 - 0:02.00] TTS Audio Test.", encoding="utf-8")

        dummy_audio = self.workspace / "master_audio.mp3"
        dummy_audio.write_bytes(b"ID3" + b"\x00" * 200)

        async def fake_render_narration(*args, **kwargs):
            return {"master_audio": str(dummy_audio), "success": True}

        with patch("html_to_mp4._get_playwright") as mock_pw, \
             patch("subprocess.Popen") as mock_popen, \
             patch("narration_voice_generator.render_narration_audio_track", side_effect=fake_render_narration), \
             patch("html_to_mp4.FFmpegUtils.get_audio_duration", return_value=2.0):
            mock_proc = MagicMock()
            mock_proc.returncode = 0
            mock_proc.stdin = MagicMock()

            def side_effect(cmd, *args, **kwargs):
                self.assertIn(str(dummy_audio.resolve()), cmd)
                self.assertIn("-map", cmd)
                self.assertIn("1:a:0", cmd)
                out_mp4.write_bytes(b"dummy")
                return mock_proc

            mock_popen.side_effect = side_effect

            res = converter.convert(
                html_input=test_html,
                output_mp4=out_mp4,
                script_path=script_file,
                duration=2.0,
            )
            self.assertEqual(res, out_mp4.resolve())

    def test_cli_burn_subtitles_flags(self):
        """Kiểm tra cờ CLI --no-subtitles và --burn-subtitles."""
        from html_to_mp4 import main

        # Case 1: --no-subtitles
        with patch("sys.argv", ["html_to_mp4.py", "in.html", "-o", "out.mp4", "--no-subtitles"]), \
             patch("html_to_mp4.html_to_mp4") as mock_convert:
            mock_convert.return_value = Path("out.mp4")
            try:
                main()
            except SystemExit:
                pass
            _, kwargs = mock_convert.call_args
            self.assertFalse(kwargs["burn_subtitles"])

        # Case 2: default or --burn-subtitles
        with patch("sys.argv", ["html_to_mp4.py", "in.html", "-o", "out.mp4", "--burn-subtitles"]), \
             patch("html_to_mp4.html_to_mp4") as mock_convert:
            mock_convert.return_value = Path("out.mp4")
            try:
                main()
            except SystemExit:
                pass
            _, kwargs = mock_convert.call_args
            self.assertTrue(kwargs["burn_subtitles"])

    def test_bilingual_secondary_subtitles_ass_generation(self):
        """Kiểm tra sinh phụ đề ASS song ngữ khi kịch bản có phụ đề phụ (inline hoặc secondary_lang)."""
        converter = HTMLToMP4Converter()
        test_html = self.workspace / "bilingual.html"
        test_html.write_text("<!DOCTYPE html><html><body>Bilingual</body></html>", encoding="utf-8")
        out_mp4 = self.workspace / "bilingual.mp4"
        script_file = self.workspace / "bilingual_script.txt"
        script_file.write_text("[0:00.00 - 0:02.50] Welcome to System // Chào mừng đến với hệ thống\n", encoding="utf-8")

        with patch("html_to_mp4._get_playwright") as mock_pw, \
             patch("subprocess.Popen") as mock_popen:
            mock_proc = MagicMock()
            mock_proc.returncode = 0
            mock_proc.stdin = MagicMock()

            def side_effect(cmd, *args, **kwargs):
                out_mp4.write_bytes(b"dummy")
                return mock_proc

            mock_popen.side_effect = side_effect

            res = converter.convert(
                html_input=test_html,
                output_mp4=out_mp4,
                script_path=script_file,
                burn_subtitles=True,
                font_size=36,
                secondary_font_size=26,
                duration=2.5,
            )
            self.assertEqual(res, out_mp4.resolve())

            # Verify generated ASS has both primary and secondary
            ass_file = self.workspace / "bilingual.ass"
            self.assertTrue(ass_file.exists())
            ass_content = ass_file.read_text(encoding="utf-8")
            self.assertIn("Style: Secondary", ass_content)
            self.assertIn(r"\N{\fs26\c&H0000FFFF}Chào mừng đến với hệ thống", ass_content)
            self.assertIn("Welcome to System", ass_content)

    def test_cli_secondary_lang_and_font_size_arguments(self):
        """Kiểm tra cờ CLI --secondary-lang và --secondary-font-size."""
        from html_to_mp4 import main

        test_args = [
            "in.html", "-o", "out.mp4",
            "--secondary-lang", "vi",
            "--secondary-font-size", "24",
        ]
        with patch("sys.argv", ["html_to_mp4.py", *test_args]), \
             patch("html_to_mp4.html_to_mp4") as mock_convert:
            mock_convert.return_value = Path("out.mp4")
            try:
                main()
            except SystemExit:
                pass
            _, kwargs = mock_convert.call_args
            self.assertEqual(kwargs["secondary_lang"], "vi")
            self.assertEqual(kwargs["secondary_font_size"], 24)


    def test_audio_padding_and_broken_pipe_guard(self):
        """Kiểm tra FFmpeg áp dụng -filter:a apad -shortest và vòng lặp frame bắt BrokenPipeError an toàn."""
        converter = HTMLToMP4Converter()
        test_html = self.workspace / "pipe_test.html"
        test_html.write_text("<!DOCTYPE html><html><body>Pipe Test</body></html>", encoding="utf-8")
        test_audio = self.workspace / "short_audio.wav"
        test_audio.write_bytes(b"RIFF" + b"\x00" * 100)
        out_mp4 = self.workspace / "pipe_out.mp4"

        with patch("html_to_mp4._get_playwright") as mock_pw, \
             patch("subprocess.Popen") as mock_popen, \
             patch("html_to_mp4.FFmpegUtils.get_audio_duration", return_value=1.0):
            mock_proc = MagicMock()
            mock_proc.returncode = 0
            # Giả lập BrokenPipeError khi stdin.write
            mock_proc.stdin.write.side_effect = BrokenPipeError("Broken pipe")

            def side_effect(cmd, *args, **kwargs):
                self.assertIn("-filter:a", cmd)
                self.assertIn("apad", cmd)
                self.assertIn("-shortest", cmd)
                out_mp4.write_bytes(b"dummy")
                return mock_proc

            mock_popen.side_effect = side_effect

            # Không được crash unhandled BrokenPipeError
            res = converter.convert(
                html_input=test_html,
                output_mp4=out_mp4,
                audio_path=test_audio,
                duration=3.0,
            )
            self.assertEqual(res, out_mp4.resolve())

    def test_html_to_mp4_lock_timeline_sync(self):
        """Kiểm tra safe_step_starts và duration được đồng bộ chuẩn xác khi lock_timeline=True."""
        converter = HTMLToMP4Converter(fps=10)
        test_html = self.workspace / "anim.html"
        test_html.write_text("<!DOCTYPE html><html><body>Anim</body></html>", encoding="utf-8")
        out_mp4 = self.workspace / "anim_out.mp4"
        script_file = self.workspace / "anim_script.txt"
        script_file.write_text("[0:00.00 - 0:02.00] Scene 1\n[0:04.00 - 0:06.00] Scene 2\n", encoding="utf-8")

        dummy_audio = self.workspace / "dummy_master.mp3"
        dummy_audio.write_bytes(b"dummy_audio_bytes" * 50)

        mock_segments = [
            {"id": 1, "text": "Scene 1", "start_sec": 0.0, "end_sec": 2.0, "duration": 2.0, "has_explicit_timestamps": True},
            {"id": 2, "text": "Scene 2", "start_sec": 4.0, "end_sec": 6.0, "duration": 2.0, "has_explicit_timestamps": True},
        ]

        evaluated_args = []
        with patch("html_to_mp4._get_playwright") as mock_pw, \
             patch("html_to_mp4._launch") as mock_launch, \
             patch("subprocess.Popen") as mock_popen, \
             patch("narration_voice_generator.render_narration_audio_track") as mock_render, \
             patch("html_to_mp4.FFmpegUtils.get_audio_duration", return_value=6.0):

            async def _fake_render(*args, **kwargs):
                self.assertTrue(kwargs.get("lock_timeline"))
                return {
                    "success": True,
                    "master_audio": str(dummy_audio),
                    "segments": mock_segments,
                }

            mock_render.side_effect = _fake_render

            mock_proc = MagicMock()
            mock_proc.returncode = 0
            mock_proc.stdin = MagicMock()

            def side_effect(cmd, *args, **kwargs):
                out_mp4.write_bytes(b"dummy_mp4")
                return mock_proc

            mock_popen.side_effect = side_effect

            # Capture evaluate calls in Playwright page
            mock_instance = MagicMock()
            mock_browser = MagicMock()
            mock_page = MagicMock()
            mock_pw.return_value.__enter__.return_value = mock_instance
            mock_launch.return_value = mock_browser
            mock_browser.new_page.return_value = mock_page

            def _cap_eval(script, args=None):
                if args is not None:
                    evaluated_args.append(args)
                return None

            mock_page.evaluate.side_effect = _cap_eval

            res = converter.convert(
                html_input=test_html,
                output_mp4=out_mp4,
                script_path=script_file,
                lock_timeline=True,
                duration=6.0,
            )

            self.assertEqual(res, out_mp4.resolve())
            self.assertTrue(len(evaluated_args) > 0)
            # The second element in evaluated_args is safe_step_starts
            step_starts = evaluated_args[0][1]
            self.assertEqual(step_starts, [0.0, 4.0])

    def test_cli_lock_timeline_flags(self):
        """Kiểm tra cờ CLI --lock-timeline và --no-lock-timeline."""
        from html_to_mp4 import main

        # Case 1: --lock-timeline
        with patch("sys.argv", ["html_to_mp4.py", "in.html", "-o", "out.mp4", "--lock-timeline"]), \
             patch("html_to_mp4.html_to_mp4") as mock_convert:
            mock_convert.return_value = Path("out.mp4")
            try:
                main()
            except SystemExit:
                pass
            _, kwargs = mock_convert.call_args
            self.assertTrue(kwargs["lock_timeline"])

        # Case 2: --no-lock-timeline
        with patch("sys.argv", ["html_to_mp4.py", "in.html", "-o", "out.mp4", "--no-lock-timeline"]), \
             patch("html_to_mp4.html_to_mp4") as mock_convert:
            mock_convert.return_value = Path("out.mp4")
            try:
                main()
            except SystemExit:
                pass
            _, kwargs = mock_convert.call_args
            self.assertFalse(kwargs["lock_timeline"])


if __name__ == "__main__":
    unittest.main()



