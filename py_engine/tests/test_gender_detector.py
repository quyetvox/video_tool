import unittest
import numpy as np
import soundfile as sf
import tempfile
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent))
from utils.gender_detector import GenderDetector


class TestGenderDetector(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.audio_path = Path(self.temp_dir.name) / "test_dialogue.wav"
        self.sr = 16000
        total_sec = 10.0
        t = np.linspace(0, total_sec, int(self.sr * total_sec), endpoint=False)

        # Create audio with 2 speakers:
        # Segment 0-3s: Male speaker (~120 Hz fundamental + harmonics)
        # Segment 3-4s: Short utterance by Male speaker (~120 Hz)
        # Segment 5-8s: Female speaker (~240 Hz fundamental + harmonics)
        # Segment 8-9s: Short utterance by Female speaker (~240 Hz)
        signal = np.zeros_like(t)

        # Male: 0.0 - 4.0s
        m_mask = (t >= 0.2) & (t <= 3.8)
        signal[m_mask] = 0.5 * np.sin(2 * np.pi * 120.0 * t[m_mask]) + 0.25 * np.sin(2 * np.pi * 240.0 * t[m_mask])

        # Female: 5.0 - 9.0s
        f_mask = (t >= 5.2) & (t <= 8.8)
        signal[f_mask] = 0.5 * np.sin(2 * np.pi * 240.0 * t[f_mask]) + 0.25 * np.sin(2 * np.pi * 480.0 * t[f_mask])

        sf.write(str(self.audio_path), signal, self.sr)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_speaker_clustering_and_gender_aggregation(self):
        segments = [
            {"id": "0", "start": 0.5, "end": 2.5, "text": "Chào em, hôm nay thế nào?"},
            {"id": "1", "start": 3.0, "end": 3.6, "text": "Ừ."},  # Short segment (0.6s)
            {"id": "2", "start": 5.5, "end": 7.5, "text": "Em chào anh, em vẫn khoẻ ạ."},
            {"id": "3", "start": 8.0, "end": 8.6, "text": "Dạ."},  # Short segment (0.6s)
        ]

        result = GenderDetector.classify_segments(self.audio_path, segments)

        # Verify speaker profiles exist
        self.assertIn("speaker_profiles", result)
        profiles = result["speaker_profiles"]
        self.assertGreaterEqual(len(profiles), 2)

        # Verify per-segment consistency
        self.assertIn("0", result)
        self.assertIn("1", result)
        self.assertIn("2", result)
        self.assertIn("3", result)

        # Male segments should share the same speaker and be classified as 'male'
        self.assertEqual(result["0"]["gender"], "male")
        self.assertEqual(result["1"]["gender"], "male")  # Short segment 1 correctly inherits male!
        self.assertEqual(result["0"]["speaker"], result["1"]["speaker"])

        # Female segments should share the same speaker and be classified as 'female'
        self.assertEqual(result["2"]["gender"], "female")
        self.assertEqual(result["3"]["gender"], "female")  # Short segment 3 correctly inherits female!
        self.assertEqual(result["2"]["speaker"], result["3"]["speaker"])

        # Male and female should have different speakers
        self.assertNotEqual(result["0"]["speaker"], result["2"]["speaker"])

        # Confidence should be high
        self.assertGreaterEqual(result["0"]["confidence"], 0.70)
        self.assertGreaterEqual(result["2"]["confidence"], 0.70)
        print("\n[Test Result] Speaker Profiles:", profiles)
        print("[Test Result] Segments:", {k: v for k, v in result.items() if k != "speaker_profiles"})


if __name__ == "__main__":
    unittest.main()
