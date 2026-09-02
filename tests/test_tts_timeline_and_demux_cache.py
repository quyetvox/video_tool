import unittest
from pathlib import Path
import tempfile
from utils.repetition_cleaner import RepetitionCleaner
from steps.s02_demux import StepDemux


class TestTTSTimelineAndDemuxCache(unittest.TestCase):
    def test_repetition_cleaner_filters_punctuation_only(self):
        """Ensures segments with only punctuation, symbols or whitespace are completely filtered out."""
        raw_segments = [
            {"start": 0.0, "end": 1.0, "text": "。"},
            {"start": 1.5, "end": 2.5, "text": "..."},
            {"start": 3.0, "end": 4.0, "text": "  , ! ? 。 "},
            {"start": 5.0, "end": 6.5, "text": "Xin chào các bạn"},
            {"start": 7.0, "end": 8.0, "text": "OK,"},
            {"start": 8.5, "end": 9.5, "text": "显卡准备保养"},
        ]
        cleaned = RepetitionCleaner.clean_segments(raw_segments)
        self.assertEqual(len(cleaned), 3)
        self.assertEqual(cleaned[0]["text"], "Xin chào các bạn")
        self.assertEqual(cleaned[1]["text"], "OK,")
        self.assertEqual(cleaned[2]["text"], "显卡准备保养")

    def test_step_demux_can_skip_validation(self):
        """Ensures StepDemux.can_skip verifies both marker and file existence."""
        step = StepDemux()
        with tempfile.TemporaryDirectory() as td:
            ws = Path(td)
            marker = ws / "s02_demux.done"
            demux_dir = ws / "demux"
            demux_dir.mkdir(parents=True, exist_ok=True)
            v_out = demux_dir / "video_stream.mp4"
            a_out = demux_dir / "audio_stream.wav"

            # Case 1: No marker
            self.assertFalse(step.can_skip(ws))

            # Case 2: Marker exists, but output files missing
            marker.touch()
            self.assertFalse(step.can_skip(ws))

            # Case 3: Marker and 0-byte files
            v_out.touch()
            a_out.touch()
            self.assertFalse(step.can_skip(ws))

            # Case 4: Marker and valid files (>1024 bytes)
            v_out.write_bytes(b"0" * 2048)
            a_out.write_bytes(b"0" * 2048)
            self.assertTrue(step.can_skip(ws))

            # Case 5: Video deleted by cleanup -> must NOT skip!
            v_out.unlink()
            self.assertFalse(step.can_skip(ws))


if __name__ == "__main__":
    unittest.main()
