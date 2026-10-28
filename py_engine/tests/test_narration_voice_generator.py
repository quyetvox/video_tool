#!/usr/bin/env python3
"""
Unit tests for narration voice generator and word-budget audio timing module.
"""

import sys
import unittest
from pathlib import Path

# Add py_engine to sys.path
engine_dir = Path(__file__).parent.parent.resolve()
if str(engine_dir) not in sys.path:
    sys.path.insert(0, str(engine_dir))

from narration_voice_generator import (
    BASE_WPM,
    calculate_word_budget_duration,
    export_subtitles,
    format_seconds_to_srt_time,
    format_seconds_to_vtt_time,
    import_narration_script,
    parse_narration_script_line,
    parse_timestamp_to_seconds,
)
from tts_studio_tool import split_script_into_segments


class TestNarrationVoiceGenerator(unittest.TestCase):
    def setUp(self):
        self.project_root = engine_dir.parent
        self.narration_file = self.project_root / "narration_script.txt"

    def test_parse_timestamp_to_seconds(self):
        self.assertAlmostEqual(parse_timestamp_to_seconds("0:00.80"), 0.80)
        self.assertAlmostEqual(parse_timestamp_to_seconds("0:05.40"), 5.40)
        self.assertAlmostEqual(parse_timestamp_to_seconds("1:02.20"), 62.20)
        self.assertAlmostEqual(parse_timestamp_to_seconds("3:25.20"), 205.20)
        self.assertAlmostEqual(parse_timestamp_to_seconds("01:00:05.50"), 3605.50)
        self.assertAlmostEqual(parse_timestamp_to_seconds("15.25"), 15.25)

    def test_calculate_word_budget_duration(self):
        # 140 WPM at 1.0x -> 140 / 60 = 2.333 words/sec
        # 14 words -> (14 / 140) * 60 = 6.0s
        dur_1_0 = calculate_word_budget_duration(14, speed=1.0, base_wpm=140.0)
        self.assertAlmostEqual(dur_1_0, 6.0, delta=0.01)

        # 14 words at 1.45x (203 wpm) -> (14 / 203) * 60 = 4.138s
        dur_1_45 = calculate_word_budget_duration(14, speed=1.45, base_wpm=140.0)
        self.assertAlmostEqual(dur_1_45, 4.138, delta=0.01)

        # 5 words at 1.15x (161 wpm) -> (5 / 161) * 60 = 1.863s
        dur_1_15 = calculate_word_budget_duration(5, speed=1.15, base_wpm=140.0)
        self.assertAlmostEqual(dur_1_15, 1.863, delta=0.01)

    def test_parse_narration_script_line(self):
        line = "[0:00.80 - 0:05.40] Every company runs on processes."
        start, end, text = parse_narration_script_line(line)
        self.assertAlmostEqual(start, 0.80)
        self.assertAlmostEqual(end, 5.40)
        self.assertEqual(text, "Every company runs on processes.")

        # Test unicode en-dash (–)
        line_endash = "[0:00.80 – 0:07.40] Một mô hình ngôn ngữ tự nó bị cô lập."
        start_ed, end_ed, text_ed = parse_narration_script_line(line_endash)
        self.assertAlmostEqual(start_ed, 0.80)
        self.assertAlmostEqual(end_ed, 7.40)
        self.assertEqual(text_ed, "Một mô hình ngôn ngữ tự nó bị cô lập.")

        # Test unicode em-dash (—) and tilde (~)
        line_emdash = "[1:10.50 — 1:15.20] Em dash sentence"
        s_em, e_em, t_em = parse_narration_script_line(line_emdash)
        self.assertAlmostEqual(s_em, 70.50)
        self.assertAlmostEqual(e_em, 75.20)
        self.assertEqual(t_em, "Em dash sentence")

        # Test parentheses (0:01 - 0:05)
        line_paren = "(0:01.00 – 0:05.00) Parenthesis timestamp"
        s_p, e_p, t_p = parse_narration_script_line(line_paren)
        self.assertAlmostEqual(s_p, 1.00)
        self.assertAlmostEqual(e_p, 5.00)
        self.assertEqual(t_p, "Parenthesis timestamp")

        # Test SRT arrow -->
        line_srt = "00:00:02,500 --> 00:00:06,800 SRT format line"
        s_srt, e_srt, t_srt = parse_narration_script_line(line_srt)
        self.assertAlmostEqual(s_srt, 2.50)
        self.assertAlmostEqual(e_srt, 6.80)
        self.assertEqual(t_srt, "SRT format line")

        plain_line = "Just a regular text sentence without timestamps."
        p_start, p_end, p_text = parse_narration_script_line(plain_line)
        self.assertIsNone(p_start)
        self.assertIsNone(p_end)
        self.assertEqual(p_text, plain_line)

        blank_line = "   \n"
        self.assertIsNone(parse_narration_script_line(blank_line))

    def test_split_script_with_endash_timestamps_user_case(self):
        """Kiểm tra kịch bản có dấu gạch ngang En-dash [0:00.80 – 0:07.40] không bị dính thời gian vào text."""
        raw_script = (
            "[0:00.80 – 0:07.40] Một mô hình ngôn ngữ tự nó bị cô lập. "
            "Nó không thể đọc các file của bạn, truy vấn cơ sở dữ liệu của bạn, hoặc gửi email.\n"
            "[0:07.80 – 0:14.60] Để kết nối nó với những thứ đó, trước đây đồng nghĩa với việc viết code kết nối tùy chỉnh."
        )
        segs = split_script_into_segments(raw_script)
        self.assertEqual(len(segs), 2)
        # Seg 1
        self.assertAlmostEqual(segs[0]["start_sec"], 0.80)
        self.assertAlmostEqual(segs[0]["end_sec"], 7.40)
        self.assertFalse(segs[0]["text"].startswith("["))
        self.assertNotIn("0:00.80", segs[0]["text"])
        self.assertTrue(segs[0]["has_explicit_timestamps"])
        # Seg 2
        self.assertAlmostEqual(segs[1]["start_sec"], 7.80)
        self.assertAlmostEqual(segs[1]["end_sec"], 14.60)
        self.assertFalse(segs[1]["text"].startswith("["))
        self.assertNotIn("0:07.80", segs[1]["text"])
        self.assertTrue(segs[1]["has_explicit_timestamps"])

    def test_import_narration_script_file(self):
        if not self.narration_file.exists():
            self.skipTest(f"{self.narration_file} not found")

        segments = import_narration_script(self.narration_file, speed=1.0)
        self.assertEqual(len(segments), 30)

        # Verify segment 1
        s1 = segments[0]
        self.assertEqual(s1["id"], 1)
        self.assertEqual(s1["text"], "Every company runs on processes.")
        self.assertEqual(s1["word_count"], 5)
        self.assertAlmostEqual(s1["start_sec"], 0.80)
        self.assertAlmostEqual(s1["end_sec"], 5.40)
        self.assertAlmostEqual(s1["duration"], 4.60)
        self.assertTrue(s1["has_explicit_timestamps"])

        # Verify segment 30
        s30 = segments[29]
        self.assertEqual(s30["id"], 30)
        self.assertEqual(s30["text"], "That is a workflow engine. Define once. Run reliably.")
        self.assertEqual(s30["word_count"], 9)
        self.assertAlmostEqual(s30["start_sec"], 205.20)
        self.assertAlmostEqual(s30["end_sec"], 209.60)
        self.assertAlmostEqual(s30["duration"], 4.40)
        self.assertTrue(s30["has_explicit_timestamps"])

    def test_import_narration_script_recalculate_timings(self):
        if not self.narration_file.exists():
            self.skipTest(f"{self.narration_file} not found")

        # Force calculation based on word count & speed 1.15x
        segments = import_narration_script(
            self.narration_file,
            speed=1.15,
            pause_sec=0.35,
            recalculate_timings=True,
        )
        self.assertEqual(len(segments), 30)

        # Segment 1: 5 words at 1.15x -> 1.863s
        s1 = segments[0]
        self.assertAlmostEqual(s1["start_sec"], 0.0)
        self.assertAlmostEqual(s1["duration"], 1.863, delta=0.01)
        self.assertAlmostEqual(s1["end_sec"], 1.863, delta=0.01)

        # Segment 2 starts at 1.863 + 0.35 = 2.213s
        s2 = segments[1]
        self.assertAlmostEqual(s2["start_sec"], 2.213, delta=0.01)

    def test_tts_studio_tool_integration(self):
        sample_text = (
            "[0:00.80 - 0:05.40] Every company runs on processes.\n"
            "[0:05.60 - 0:10.40] Approve an order. Onboard an employee. Process a refund."
        )
        segs = split_script_into_segments(sample_text, speed=1.0)
        self.assertEqual(len(segs), 2)
        self.assertEqual(segs[0]["text"], "Every company runs on processes.")
        self.assertAlmostEqual(segs[0]["start_sec"], 0.8)
        self.assertAlmostEqual(segs[0]["end_sec"], 5.4)

    def test_format_subtitles(self):
        self.assertEqual(format_seconds_to_srt_time(62.20), "00:01:02,200")
        self.assertEqual(format_seconds_to_vtt_time(62.20), "00:01:02.200")

    def test_render_narration_audio_track_explicit_timeline(self):
        """Kiểm tra render_narration_audio_track bảo tồn mốc thời gian explicit và chèn silence gap chính xác."""
        import asyncio, tempfile
        from unittest.mock import patch
        from narration_voice_generator import render_narration_audio_track, generate_silence_audio

        sample_segments = [
            {"id": 1, "text": "First intro.", "start_sec": 1.0, "end_sec": 3.0, "duration": 2.0, "has_explicit_timestamps": True},
            {"id": 2, "text": "Scene two starts.", "start_sec": 10.0, "end_sec": 14.0, "duration": 4.0, "has_explicit_timestamps": True},
        ]

        with tempfile.TemporaryDirectory() as tmp_dir:
            out_dir = Path(tmp_dir)

            async def mock_synth(text, voice, speed, pitch, output_path):
                generate_silence_audio(2.0, output_path)
                return output_path, 2.0, True

            with patch("narration_voice_generator.synthesize_single_segment_async", side_effect=mock_synth):
                res = asyncio.run(render_narration_audio_track(
                    segments=sample_segments,
                    output_dir=out_dir,
                    voice="en-US-JennyNeural",
                    speed=1.0,
                ))

            self.assertTrue(res["success"])
            self.assertEqual(res["total_segments"], 2)
            # Segment 1 starts at 1.0s (after 1.0s silence gap)
            self.assertAlmostEqual(res["segments"][0]["start_sec"], 1.0)
            self.assertAlmostEqual(res["segments"][0]["end_sec"], 3.0)
            # Segment 2 starts at 10.0s (after 7.0s silence gap)
            self.assertAlmostEqual(res["segments"][1]["start_sec"], 10.0)
            self.assertAlmostEqual(res["segments"][1]["end_sec"], 12.0)
            # Verify concat list contains silence gaps
            concat_txt = (out_dir / "concat_list.txt").read_text()
            self.assertIn("silence_gap_", concat_txt)

    def test_render_narration_audio_track_lock_timeline(self):
        """Kiểm tra render_narration_audio_track với lock_timeline=True tự động tính tốc độ và khóa slot."""
        import asyncio, tempfile
        from unittest.mock import patch
        from narration_voice_generator import render_narration_audio_track, generate_silence_audio

        sample_segments = [
            {"id": 1, "text": "Short intro.", "start_sec": 0.0, "end_sec": 3.0, "duration": 3.0, "has_explicit_timestamps": True},
            {"id": 2, "text": "This is a remarkably long sentence with many words that definitely exceeds the normal speech duration for a two second slot.", "start_sec": 5.0, "end_sec": 7.0, "duration": 2.0, "has_explicit_timestamps": True},
        ]

        with tempfile.TemporaryDirectory() as tmp_dir:
            out_dir = Path(tmp_dir)

            captured_speeds = {}
            async def mock_synth(text, voice, speed, pitch, output_path):
                captured_speeds[text] = speed
                # If speed is boosted, audio is shorter
                dur = max(0.5, 4.0 / max(1.0, speed))
                generate_silence_audio(dur, output_path)
                return output_path, dur, True

            with patch("narration_voice_generator.synthesize_single_segment_async", side_effect=mock_synth):
                res = asyncio.run(render_narration_audio_track(
                    segments=sample_segments,
                    output_dir=out_dir,
                    voice="en-US-JennyNeural",
                    speed=1.0,
                    lock_timeline=True,
                ))

            self.assertTrue(res["success"])
            # Sentence 2 must have speed boosted significantly above base speed 1.0
            self.assertGreater(captured_speeds[sample_segments[1]["text"]], 1.2)
            # Segments must be locked to target slots
            self.assertAlmostEqual(res["segments"][0]["start_sec"], 0.0)
            self.assertAlmostEqual(res["segments"][0]["slot_end_sec"], 3.0)
            self.assertAlmostEqual(res["segments"][1]["start_sec"], 5.0)
            self.assertAlmostEqual(res["segments"][1]["slot_end_sec"], 7.0)
            self.assertLessEqual(res["segments"][1]["end_sec"], 7.0)

    def test_render_narration_audio_track_auto_mode(self):
        """Kiểm tra render_narration_audio_track ở chế độ Auto (lock_timeline=False) lấy audio làm Master."""
        import asyncio, tempfile
        from unittest.mock import patch
        from narration_voice_generator import render_narration_audio_track, generate_silence_audio

        sample_segments = [
            {"id": 1, "text": "Scene one narration.", "duration": 2.0, "has_explicit_timestamps": False},
            {"id": 2, "text": "Scene two narration.", "duration": 3.0, "has_explicit_timestamps": False},
        ]

        with tempfile.TemporaryDirectory() as tmp_dir:
            out_dir = Path(tmp_dir)

            async def mock_synth(text, voice, speed, pitch, output_path):
                dur = 1.5 if "one" in text else 2.5
                generate_silence_audio(dur, output_path)
                return output_path, dur, True

            with patch("narration_voice_generator.synthesize_single_segment_async", side_effect=mock_synth):
                res = asyncio.run(render_narration_audio_track(
                    segments=sample_segments,
                    output_dir=out_dir,
                    voice="en-US-JennyNeural",
                    speed=1.0,
                    pause_sec=0.4,
                    lock_timeline=False,
                ))

            self.assertTrue(res["success"])
            segs = res["segments"]
            self.assertAlmostEqual(segs[0]["start_sec"], 0.0)
            self.assertAlmostEqual(segs[0]["end_sec"], 1.5)
            # Scene 2 starts at 1.5 + 0.4 = 1.9s
            self.assertAlmostEqual(segs[1]["start_sec"], 1.9)
            self.assertAlmostEqual(segs[1]["end_sec"], 4.4)


if __name__ == "__main__":
    unittest.main()

