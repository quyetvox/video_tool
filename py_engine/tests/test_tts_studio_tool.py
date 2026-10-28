#!/usr/bin/env python3
"""
Unit tests for py_engine/tts_studio_tool.py
"""

import unittest
from pathlib import Path
import sys

# Ensure py_engine is in sys.path
PY_ENGINE_DIR = Path(__file__).resolve().parent.parent
if str(PY_ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(PY_ENGINE_DIR))

from tts_studio_tool import (
    VOICE_CATALOG,
    speed_to_rate_str,
    pitch_to_str,
    normalize_english_text,
    normalize_vietnamese_text,
    split_script_into_segments,
    format_srt_time,
    format_vtt_time,
)


class TestTtsStudioTool(unittest.TestCase):
    def test_voice_catalog_contains_vietnamese_and_english(self):
        """Ensure catalog contains both Vietnamese and English voices across regions."""
        langs = {v["lang"] for v in VOICE_CATALOG}
        self.assertIn("vi", langs)
        self.assertIn("en", langs)

        regions = {v["region"] for v in VOICE_CATALOG}
        self.assertIn("VN", regions)
        self.assertIn("US", regions)
        self.assertIn("GB", regions)
        self.assertIn("AU", regions)

        for voice in VOICE_CATALOG:
            self.assertIn("id", voice)
            self.assertIn("name", voice)
            self.assertIn("gender", voice)
            self.assertIn("engine", voice)

    def test_speed_to_rate_str(self):
        """Verify speed factor conversion to EdgeTTS rate string."""
        self.assertEqual(speed_to_rate_str(1.0), "+0%")
        self.assertEqual(speed_to_rate_str(1.20), "+20%")
        self.assertEqual(speed_to_rate_str(1.15), "+15%")
        self.assertEqual(speed_to_rate_str(0.85), "-15%")
        self.assertEqual(speed_to_rate_str(0.5), "-50%")

    def test_pitch_to_str(self):
        """Verify pitch integer conversion."""
        self.assertEqual(pitch_to_str(0), "+0Hz")
        self.assertEqual(pitch_to_str(10), "+10Hz")
        self.assertEqual(pitch_to_str(-8), "-8Hz")

    def test_text_normalization(self):
        """Verify language-specific normalization."""
        # English
        en_raw = '“Welcome!” We made $100 and grew by 25% — it’s great.'
        en_norm = normalize_english_text(en_raw)
        self.assertIn("100 dollars", en_norm)
        self.assertIn("25 percent", en_norm)
        self.assertNotIn("“", en_norm)
        self.assertNotIn("”", en_norm)
        self.assertNotIn("—", en_norm)

        # Vietnamese
        vi_raw = 'Chào mừng bạn! Chúng tôi kiếm được $100 và tăng trưởng 50% trong năm nay.'
        vi_norm = normalize_vietnamese_text(vi_raw)
        self.assertIn("100 đô la", vi_norm)
        self.assertIn("50 phần trăm", vi_norm)

    def test_split_script_into_segments(self):
        """Verify intelligent sentence and paragraph splitting."""
        script = """Xin chào mọi người. Hôm nay chúng ta sẽ tìm hiểu về hệ thống phân tán!
        Liệu nó có dễ không? Chắc chắn là có.

        Phân đoạn thứ hai bắt đầu ở đây. Cùng đón xem nhé."""
        segments = split_script_into_segments(script)
        self.assertGreaterEqual(len(segments), 4)

        texts = [s["text"] for s in segments]
        self.assertTrue(any("Xin chào mọi người" in t for t in texts))
        self.assertTrue(any("Liệu nó có dễ không" in t for t in texts))
        self.assertTrue(any("Phân đoạn thứ hai" in t for t in texts))

        for seg in segments:
            self.assertGreater(seg["word_count"], 0)
            self.assertGreater(seg["char_count"], 0)

    def test_srt_and_vtt_formatting(self):
        """Verify subtitle timestamp format accuracy."""
        # 0 seconds
        self.assertEqual(format_srt_time(0.0), "00:00:00,000")
        self.assertEqual(format_vtt_time(0.0), "00:00:00.000")

        # 65.456 seconds -> 1 min 5 sec 456 ms
        self.assertEqual(format_srt_time(65.456), "00:01:05,456")
        self.assertEqual(format_vtt_time(65.456), "00:01:05.456")

        # 3661.020 seconds -> 1 hr 1 min 1 sec 20 ms
        self.assertEqual(format_srt_time(3661.020), "01:01:01,020")
        self.assertEqual(format_vtt_time(3661.020), "01:01:01.020")


if __name__ == "__main__":
    unittest.main()
