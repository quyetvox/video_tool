#!/usr/bin/env python3
"""
Unit tests for Strict Timeline Alignment & Speed Floor in TTS Studio.
Tests:
1. Speed floor respected (never drops below base_speed).
2. Auto speed boost without ceiling when words exceed time slot.
3. Two-stage atempo fine-tuning when audio exceeds slot.
4. Total duration and silence pauses accurately wait for next start.
"""

import asyncio
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Add py_engine to sys.path
engine_dir = Path(__file__).parent.parent.resolve()
if str(engine_dir) not in sys.path:
    sys.path.insert(0, str(engine_dir))

from tts_studio_tool import (
    calculate_timeline_speed,
    fine_tune_audio_duration,
    render_full_batch,
    generate_silence_audio,
)


class TestTtsTimelineLock(unittest.TestCase):
    def test_calculate_timeline_speed_floor_respected(self):
        """Khi số từ ít trong slot thời gian dài, tốc độ không được giảm xuống dưới base_speed."""
        # Slot 5.0s, 2 từ (thời lượng tự nhiên ~0.8s) -> required speed ~0.16x
        base_speed = 1.15
        calculated_speed, is_boosted = calculate_timeline_speed(
            text="Xin chào",
            slot_duration=5.0,
            base_speed=base_speed,
        )
        self.assertFalse(is_boosted)
        self.assertAlmostEqual(calculated_speed, base_speed, places=2)

    def test_calculate_timeline_speed_auto_boost_no_ceiling(self):
        """Khi số từ nhiều trong slot thời gian ngắn, tự động tăng tốc độ vượt trần (> 2.0x, lên tới 3.0x+)."""
        # Slot 2.0s, text dài 16 từ (thời lượng tự nhiên ~6.8s) -> required speed ~3.4x
        long_text = "Hệ thống kiến trúc hướng sự kiện giúp mở rộng quy mô và xử lý khối lượng lớn tin nhắn đồng thời một cách đáng tin cậy."
        base_speed = 1.0
        calculated_speed, is_boosted = calculate_timeline_speed(
            text=long_text,
            slot_duration=2.0,
            base_speed=base_speed,
        )
        self.assertTrue(is_boosted)
        self.assertGreater(calculated_speed, 2.0)
        self.assertGreaterEqual(calculated_speed, 3.0)

    def test_technical_sentence_in_adequate_slot_stays_at_base_speed(self):
        """Câu có thuật ngữ dài nhưng thời lượng slot đủ rộng: Giữ nguyên 100% base_speed, không bị boost."""
        # 10 words, 87 characters (từ dài: Vector database semantic search approximate nearest neighbor retrieval)
        tech_text = "Vector database semantic search enables approximate nearest neighbor retrieval efficiently."
        base_speed = 1.0
        # 10 words at 140 WPM take ~4.28s. Slot 5.0s is adequate -> MUST NOT boost!
        calculated_speed, is_boosted = calculate_timeline_speed(
            text=tech_text,
            slot_duration=5.0,
            base_speed=base_speed,
        )
        self.assertFalse(is_boosted)
        self.assertEqual(calculated_speed, 1.0)

    def test_fine_tune_audio_duration_atempo(self):
        """Kiểm tra Two-Stage Fine-tuning: Nén audio qua atempo nếu độ dài vượt slot."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_p = Path(tmp_dir)
            test_audio = tmp_p / "long_audio.mp3"
            out_audio = tmp_p / "compressed_audio.mp3"

            # Tạo file audio giả lập 3.0s bằng anullsrc
            generate_silence_audio(3.0, test_audio)
            self.assertTrue(test_audio.exists())

            # Slot mục tiêu là 1.5s -> Cần nén atempo 2.0x
            new_path, final_dur = fine_tune_audio_duration(
                audio_path=test_audio,
                target_slot_sec=1.5,
                output_path=out_audio,
            )
            self.assertTrue(new_path.exists())
            self.assertLessEqual(final_dur, 1.55)

    def test_render_full_batch_timeline_locked(self):
        """Kiểm tra render_full_batch khi lock_timeline=True:
        - Câu 1: [1.0s - 3.0s], đọc xong lúc 2.2s -> Nghỉ đến 5.0s
        - Câu 2: [5.0s - 7.0s]
        - Tổng thời gian xuất ra khớp chính xác với mốc cuối 7.0s.
        """
        sample_segments = [
            {
                "id": 1,
                "text": "Câu thứ nhất.",
                "start_sec": 1.0,
                "end_sec": 3.0,
                "duration": 2.0,
                "speed": 1.0,
            },
            {
                "id": 2,
                "text": "Câu thứ hai bắt đầu ở mốc năm giây.",
                "start_sec": 5.0,
                "end_sec": 7.0,
                "duration": 2.0,
                "speed": 1.0,
            },
        ]

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_p = Path(tmp_dir)
            out_audio = tmp_p / "master_timeline.mp3"
            out_srt = tmp_p / "master_timeline.srt"

            async def mock_synth(text, voice, speed=1.0, pitch=0, output_path=None, sem=None):
                p = output_path or (tmp_p / "seg_mock.mp3")
                # Giả lập file audio 1.2s (đọc xong trước slot 2.0s)
                generate_silence_audio(1.2, p)
                return p, 1.2, True

            with patch("tts_studio_tool.synth_segment_async", side_effect=mock_synth):
                res = asyncio.run(render_full_batch(
                    segments=sample_segments,
                    default_voice="vi-VN-HoaiMyNeural",
                    default_speed=1.0,
                    default_pitch=0,
                    pause_sec=0.35,
                    output_audio=out_audio,
                    output_srt=out_srt,
                    lock_timeline=True,
                ))

            self.assertTrue(res["success"])
            self.assertEqual(res["total_segments"], 2)
            # Tổng thời lượng phải chạm mốc 7.0s của câu cuối
            self.assertAlmostEqual(res["total_duration"], 7.0, delta=0.1)

            # Phụ đề SRT phải giữ mốc [start - end] gốc
            srt_content = out_srt.read_text(encoding="utf-8")
            self.assertIn("00:00:01,000 --> 00:00:03,000", srt_content)
            self.assertIn("00:00:05,000 --> 00:00:07,000", srt_content)

    def test_render_narration_audio_track_silence_rest(self):
        """Kiểm tra render_narration_audio_track chèn silence rest chính xác khi câu ngắn kết thúc sớm."""
        from narration_voice_generator import render_narration_audio_track
        sample_segments = [
            {
                "id": 1,
                "text": "Every company runs on processes.",
                "start_sec": 1.0,
                "end_sec": 3.0,
                "duration": 2.0,
                "has_explicit_timestamps": True,
            },
            {
                "id": 2,
                "text": "Workflow engine coordinates actions.",
                "start_sec": 5.0,
                "end_sec": 7.0,
                "duration": 2.0,
                "has_explicit_timestamps": True,
            },
        ]

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_p = Path(tmp_dir)

            async def mock_synth(text, voice, speed=1.0, pitch=0, output_path=None, sem=None):
                p = output_path or (tmp_p / "seg_mock.mp3")
                # Giả lập file 1.2s (đọc xong sớm trước mốc 3.0s)
                generate_silence_audio(1.2, p)
                return p, 1.2, True

            with patch("narration_voice_generator.synthesize_single_segment_async", side_effect=mock_synth):
                res = asyncio.run(render_narration_audio_track(
                    segments=sample_segments,
                    output_dir=tmp_p,
                    voice="en-US-JennyNeural",
                    speed=1.0,
                    lock_timeline=True,
                ))

            self.assertTrue(res["success"])
            master_audio = Path(res["master_audio"])
            self.assertTrue(master_audio.exists())
            # Kiểm tra thời lượng master audio xấp xỉ 7.0s (bao gồm silence gap đến mốc tiếp theo + MP3 padding)
            from utils.ffmpeg_utils import FFmpegUtils
            dur = FFmpegUtils.get_audio_duration(master_audio)
            self.assertAlmostEqual(dur, 7.0, delta=0.5)


if __name__ == "__main__":
    unittest.main()
