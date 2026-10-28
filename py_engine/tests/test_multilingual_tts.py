import sys
import unittest
from pathlib import Path

# Add py_engine root to sys.path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from plugins.tts.preset_tts import (
    Plugin,
    normalize_english_text,
    normalize_vietnamese_text,
    normalize_text_by_voice,
)


class TestMultilingualTTS(unittest.TestCase):
    def setUp(self):
        self.plugin = Plugin()

    def test_normalize_english_text(self):
        # Currency
        self.assertEqual(normalize_english_text("Price is $50 today"), "Price is 50 dollars today")
        self.assertEqual(normalize_english_text("Cost: 100$ and £20"), "Cost: 100 dollars and 20 pounds")
        self.assertEqual(normalize_english_text("Tax is €15"), "Tax is 15 euros")

        # Percentage & units
        self.assertEqual(normalize_english_text("Discount 25% off"), "Discount 25 percent off")
        self.assertEqual(normalize_english_text("Speed 120km/h"), "Speed 120 kilometers per hour")

        # Quotes & markdown
        self.assertEqual(normalize_english_text('“Hello world” — *good*'), '"Hello world" - good')

    def test_normalize_text_by_voice(self):
        # English voice
        en_res = normalize_text_by_voice("$100 for 10% discount", "en-US-JennyNeural")
        self.assertIn("dollars", en_res)
        self.assertIn("percent", en_res)

        # Vietnamese voice
        vi_res = normalize_text_by_voice("$100 cho 10% giảm giá", "vi-VN-HoaiMyNeural")
        self.assertIn("đô la", vi_res)
        self.assertIn("phần trăm", vi_res)

    def test_resolve_voice_multilingual(self):
        # Vietnamese voices
        self.assertEqual(self.plugin._resolve_voice("vi-VN-BanMai"), "gtts_vi")
        self.assertEqual(self.plugin._resolve_voice("vi-VN-HoaiMyNeural"), "vi-VN-HoaiMyNeural")
        self.assertEqual(self.plugin._resolve_voice("namminh"), "vi-VN-NamMinhNeural")

        # English voices
        self.assertEqual(self.plugin._resolve_voice("en-US-JennyNeural"), "en-US-JennyNeural")
        self.assertEqual(self.plugin._resolve_voice("en-GB-RyanNeural"), "en-GB-RyanNeural")
        self.assertEqual(self.plugin._resolve_voice("english_female"), "en-US-JennyNeural")
        self.assertEqual(self.plugin._resolve_voice("english_male"), "en-US-GuyNeural")
        self.assertEqual(self.plugin._resolve_voice("gtts_en"), "gtts_en")


if __name__ == "__main__":
    unittest.main()
