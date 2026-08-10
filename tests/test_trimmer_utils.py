import sys
import unittest
from pathlib import Path
import tempfile

# Add lib directory to sys.path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from utils.trimmer_utils import parse_time_str, format_seconds_to_time, get_unique_trim_path


class TestTrimmerUtils(unittest.TestCase):

    def test_parse_time_str(self):
        self.assertEqual(parse_time_str("90"), 90.0)
        self.assertEqual(parse_time_str("90.5"), 90.5)
        self.assertEqual(parse_time_str("01:30"), 90.0)
        self.assertEqual(parse_time_str("01:30.5"), 90.5)
        self.assertEqual(parse_time_str("01:02:15"), 3735.0)
        self.assertIsNone(parse_time_str(None))
        self.assertIsNone(parse_time_str(""))
        self.assertIsNone(parse_time_str("invalid"))

    def test_format_seconds_to_time(self):
        self.assertEqual(format_seconds_to_time(90.0), "01:30")
        self.assertEqual(format_seconds_to_time(3735.0), "01:02:15")
        self.assertEqual(format_seconds_to_time(0), "00:00")
        self.assertEqual(format_seconds_to_time(None), "00:00")

    def test_get_unique_trim_path(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            video = tmp_path / "video_001.mp4"
            video.touch()

            # First cut -> video_001_cut_1.mp4
            cut1 = get_unique_trim_path(video)
            self.assertEqual(cut1.name, "video_001_cut_1.mp4")
            cut1.touch()

            # Second cut -> video_001_cut_2.mp4
            cut2 = get_unique_trim_path(video)
            self.assertEqual(cut2.name, "video_001_cut_2.mp4")
            cut2.touch()

            # Third cut -> video_001_cut_3.mp4
            cut3 = get_unique_trim_path(video)
            self.assertEqual(cut3.name, "video_001_cut_3.mp4")

            # Nested cut from video_001_cut_1.mp4 -> video_001_cut_1_cut_1.mp4
            nested1 = get_unique_trim_path(cut1)
            self.assertEqual(nested1.name, "video_001_cut_1_cut_1.mp4")


if __name__ == "__main__":
    unittest.main()
