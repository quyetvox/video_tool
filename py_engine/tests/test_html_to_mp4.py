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

    def test_piecewise_linear_time_warp_for_unlocked_explicit_script(self):
        """Kiểm tra nội suy Piecewise-Linear Time-Warp (t_audio -> t_html) khi câu TTS dài hơn mốc gốc."""
        from html_to_mp4 import _build_time_warp_knots, _interpolate_html_time

        # Giả lập 2 câu có mốc gốc [0.80 - 7.60] và [10.00 - 16.00] nhưng TTS tiếng Việt đọc dài hơn:
        # Câu 1: [0.80 - 9.80] (9.0s thay vì 6.8s), khoảng nghỉ chuyển cảnh giữ nguyên 2.4s -> Câu 2: [12.20 - 20.20]
        segments = [
            {
                "id": 1,
                "text": "Câu 1 tiếng Việt dài hơn tiếng Anh",
                "start_sec": 0.80,
                "end_sec": 9.80,
                "orig_start_sec": 0.80,
                "orig_end_sec": 7.60,
                "has_explicit_timestamps": True,
            },
            {
                "id": 2,
                "text": "Câu 2 sau khoảng nghỉ chuyển cảnh 2.4s",
                "start_sec": 12.20,
                "end_sec": 20.20,
                "orig_start_sec": 10.00,
                "orig_end_sec": 16.00,
                "has_explicit_timestamps": True,
            },
        ]

        knots = _build_time_warp_knots(segments, html_duration=17.0)
        self.assertTrue(len(knots) >= 5)

        # Tại đầu câu 1 (t_audio = 0.80) -> t_html phải đúng bằng 0.80
        self.assertAlmostEqual(_interpolate_html_time(0.80, knots), 0.80, places=3)
        # Tại giữa câu 1 (t_audio = 5.30, tức 50% của [0.80, 9.80]) -> t_html = 50% của [0.80, 7.60] = 4.20
        self.assertAlmostEqual(_interpolate_html_time(5.30, knots), 4.20, places=3)
        # Tại cuối câu 1 (t_audio = 9.80) -> t_html phải đúng bằng 7.60
        self.assertAlmostEqual(_interpolate_html_time(9.80, knots), 7.60, places=3)
        # Tại đầu câu 2 (t_audio = 12.20) -> t_html phải đúng bằng 10.00 (không bị lệch tích lũy!)
        self.assertAlmostEqual(_interpolate_html_time(12.20, knots), 10.00, places=3)
        # Tại cuối câu 2 (t_audio = 20.20) -> t_html phải đúng bằng 16.00
        self.assertAlmostEqual(_interpolate_html_time(20.20, knots), 16.00, places=3)
        # Đuôi kết thúc HTML (+1.0s)
        self.assertAlmostEqual(_interpolate_html_time(21.20, knots), 17.00, places=3)

    def test_auto_mode_preserves_orig_timestamps_and_scene_gaps(self):
        """Kiểm tra render_narration_audio_track ở chế độ lock_timeline=False vẫn giữ orig_start_sec và khoảng nghỉ chuyển cảnh."""
        import asyncio
        from narration_voice_generator import import_narration_script, render_narration_audio_track

        script_text = (
            "[0:00.80 – 0:07.60] Một đường dẫn tập tin được gửi trong một yêu cầu web thông thường.\n"
            "[0:08.00 – 0:15.20] Câu thứ hai trong cùng cảnh một.\n"
            "[0:17.60 – 0:24.00] Câu đầu tiên của cảnh hai sau khoảng nghỉ 2.4 giây.\n"
        )
        segs = import_narration_script(script_text, speed=1.0)
        self.assertEqual(len(segs), 3)
        self.assertAlmostEqual(segs[0]["orig_start_sec"], 0.80, places=2)
        self.assertAlmostEqual(segs[0]["orig_end_sec"], 7.60, places=2)

        async def _fake_synth(text, voice, speed, pitch, output_path):
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_bytes(b"ID3" + b"\x00" * 600)
            return output_path, 8.50, True

        with patch("narration_voice_generator.synthesize_single_segment_async", side_effect=_fake_synth), \
             patch("narration_voice_generator.generate_silence_audio", return_value=True), \
             patch("narration_voice_generator.probe_audio_duration", return_value=29.1):
            res = asyncio.run(
                render_narration_audio_track(
                    segments=segs,
                    output_dir=self.workspace / "auto_explicit_out",
                    lock_timeline=False,
                )
            )
            out_segs = res["segments"]
            # Câu 1 giữ khoảng lặng mở đầu 0.80s, kéo dài 8.50s -> kết thúc ở 9.30s
            self.assertAlmostEqual(out_segs[0]["start_sec"], 0.80, places=2)
            self.assertAlmostEqual(out_segs[0]["end_sec"], 9.30, places=2)
            self.assertAlmostEqual(out_segs[0]["orig_start_sec"], 0.80, places=2)
            self.assertAlmostEqual(out_segs[0]["orig_end_sec"], 7.60, places=2)
            # Khoảng nghỉ giữa câu 1 và câu 2 gốc là 8.00 - 7.60 = 0.40s -> câu 2 bắt đầu ở 9.70s, kết thúc ở 18.20s
            self.assertAlmostEqual(out_segs[1]["start_sec"], 9.70, places=2)
            self.assertAlmostEqual(out_segs[1]["end_sec"], 18.20, places=2)
            # Khoảng nghỉ chuyển cảnh giữa câu 2 và câu 3 gốc là 17.60 - 15.20 = 2.40s -> câu 3 bắt đầu ở 20.60s
            self.assertAlmostEqual(out_segs[2]["start_sec"], 20.60, places=2)
            self.assertAlmostEqual(out_segs[2]["orig_start_sec"], 17.60, places=2)

    def test_plan_scene_ranges_and_inverse_time_warp(self):
        """Kiểm tra chia scene tự động từ window.VIDEO.scenes, khoảng nghỉ kịch bản và cân bằng tải theo num_workers."""
        from html_to_mp4 import (
            _build_time_warp_knots,
            _interpolate_audio_time,
            _interpolate_html_time,
            _plan_scene_ranges,
        )

        # 1. Kiểm tra ánh xạ ngược _interpolate_audio_time khớp với _interpolate_html_time
        segments = [
            {
                "id": 1,
                "start_sec": 0.80,
                "end_sec": 9.80,
                "orig_start_sec": 0.80,
                "orig_end_sec": 7.60,
                "has_explicit_timestamps": True,
            },
            {
                "id": 2,
                "start_sec": 12.20,
                "end_sec": 20.20,
                "orig_start_sec": 10.00,
                "orig_end_sec": 16.00,
                "has_explicit_timestamps": True,
            },
        ]
        knots = _build_time_warp_knots(segments, html_duration=17.0)
        for sample_audio_t in (0.80, 5.30, 9.80, 12.20, 16.20, 20.20):
            html_t = _interpolate_html_time(sample_audio_t, knots)
            roundtrip_audio_t = _interpolate_audio_time(html_t, knots)
            self.assertAlmostEqual(roundtrip_audio_t, sample_audio_t, places=3)

        # 2. Chia đều theo num_workers khi không có scene metadata (240 frames @ 24fps = 10s, 4 workers)
        ranges_even = _plan_scene_ranges(total_frames=240, fps=24, num_workers=4)
        self.assertGreaterEqual(len(ranges_even), 3)
        self.assertEqual(ranges_even[0][0], 0)
        self.assertEqual(ranges_even[-1][1], 240)
        for idx in range(len(ranges_even) - 1):
            self.assertEqual(ranges_even[idx][1], ranges_even[idx + 1][0])

        # 3. Chia theo ranh giới window.VIDEO.scenes kết hợp time-warp
        ranges_scenes = _plan_scene_ranges(
            total_frames=500,
            fps=24,
            num_workers=2,
            html_scene_starts=[0.0, 10.00],
            segments=segments,
            time_warp_knots=knots,
        )
        self.assertGreaterEqual(len(ranges_scenes), 2)
        boundary_starts = [r[0] for r in ranges_scenes]
        # Mốc html_t = 10.00 ứng với audio_t = 12.20s -> frame round(12.20 * 24) = 293
        self.assertIn(int(round(12.20 * 24)), boundary_starts)

    def test_build_scene_vf_filter_setpts_subtitle_offset(self):
        """Kiểm tra _build_scene_vf_filter chèn đúng setpts=PTS+t_start/TB trước subtitles và setpts=PTS-STARTPTS sau."""
        from html_to_mp4 import _build_scene_vf_filter

        ass_file = self.workspace / "scene_test.ass"
        ass_file.write_text("[Script Info]\nTitle: Test\n", encoding="utf-8")

        vf_scene0 = _build_scene_vf_filter(1920, 1080, 24, start_frame=0, has_burned_ass=True, ass_path=ass_file)
        self.assertNotIn("setpts=PTS+", vf_scene0)
        self.assertIn("subtitles=", vf_scene0)

        vf_scene1 = _build_scene_vf_filter(1920, 1080, 24, start_frame=240, has_burned_ass=True, ass_path=ass_file)
        self.assertIn("setpts=PTS+10.000000/TB", vf_scene1)
        self.assertIn("subtitles=", vf_scene1)
        self.assertTrue(vf_scene1.endswith("setpts=PTS-STARTPTS"))

    def test_multi_worker_scene_split_and_concat_cleanup(self):
        """Kiểm tra convert() với num_workers=2 chia scene, gọi worker, ghép concat -c:v copy và xóa thư mục tạm."""
        converter = HTMLToMP4Converter(fps=10, num_workers=2)
        test_html = self.workspace / "multi.html"
        test_html.write_text("<!DOCTYPE html><html><body>Multi Scene</body></html>", encoding="utf-8")
        out_mp4 = self.workspace / "multi_out.mp4"

        def _fake_worker(task):
            p_scene = Path(task["out_scene_mp4"])
            p_scene.parent.mkdir(parents=True, exist_ok=True)
            p_scene.write_bytes(b"scene_mp4_bytes_" * 100)
            return task["scene_idx"], str(p_scene), (task["end_frame"] - task["start_frame"])

        def _fake_concat(scene_files, out_path, audio_file_path, temp_dir):
            self.assertGreaterEqual(len(scene_files), 2)
            for sf in scene_files:
                self.assertTrue(Path(sf).exists())
            out_path.write_bytes(b"final_concat_mp4_bytes" * 100)

        progress_updates = []
        with patch("html_to_mp4._get_playwright"), \
             patch("html_to_mp4._launch"), \
             patch("html_to_mp4.ProcessPoolExecutor") as mock_pool_cls, \
             patch("html_to_mp4._concat_scene_videos_with_audio", side_effect=_fake_concat) as mock_concat:

            # Giả lập ProcessPoolExecutor chạy _fake_worker
            mock_pool = MagicMock()
            mock_pool_cls.return_value.__enter__.return_value = mock_pool

            def _submit(fn, task):
                fut = MagicMock()
                fut.result.return_value = _fake_worker(task)
                return fut

            mock_pool.submit.side_effect = _submit

            with patch("html_to_mp4.as_completed", side_effect=lambda futs: list(futs.keys())):
                res = converter.convert(
                    html_input=test_html,
                    output_mp4=out_mp4,
                    duration=12.0,
                    num_workers=2,
                    on_progress=lambda pct, curr, tot: progress_updates.append((pct, curr, tot)),
                )

            self.assertEqual(res, out_mp4.resolve())
            self.assertTrue(out_mp4.exists())
            mock_concat.assert_called_once()
            self.assertTrue(any(p[0] == 100.0 for p in progress_updates))
            # Kiểm tra thư mục tạm chứa các scene lẻ đã được dọn dẹp sạch sẽ
            leftover_tmp = list(self.workspace.glob(".*_scenes_tmp_*"))
            self.assertEqual(leftover_tmp, [])

    def test_cli_num_workers_flag(self):
        """Kiểm tra cờ CLI --num-workers truyền đúng vào html_to_mp4."""
        from html_to_mp4 import main

        with patch("sys.argv", ["html_to_mp4.py", "in.html", "-o", "out.mp4", "--num-workers", "4"]), \
             patch("html_to_mp4.html_to_mp4") as mock_convert:
            mock_convert.return_value = Path("out.mp4")
            try:
                main()
            except SystemExit:
                pass
            _, kwargs = mock_convert.call_args
            self.assertEqual(kwargs["num_workers"], "4")


if __name__ == "__main__":
    unittest.main()



