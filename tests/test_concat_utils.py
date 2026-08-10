import sys
import unittest
from pathlib import Path

# Add lib directory to sys.path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

from utils.concat_utils import calculate_keep_ranges


class TestConcatUtils(unittest.TestCase):

    def test_calculate_keep_ranges(self):
        # 100s video, remove [15, 30] and [70, 80]
        removes = [(15.0, 30.0), (70.0, 80.0)]
        keeps = calculate_keep_ranges(100.0, removes)
        expected = [(0.0, 15.0), (30.0, 70.0), (80.0, 100.0)]
        self.assertEqual(keeps, expected)

    def test_overlapping_removes(self):
        # 100s video, overlapping removes [10, 30] and [20, 40] -> merged [10, 40]
        removes = [(10.0, 30.0), (20.0, 40.0)]
        keeps = calculate_keep_ranges(100.0, removes)
        expected = [(0.0, 10.0), (40.0, 100.0)]
        self.assertEqual(keeps, expected)

    def test_no_removes(self):
        keeps = calculate_keep_ranges(50.0, [])
        self.assertEqual(keeps, [(0.0, 50.0)])


if __name__ == "__main__":
    unittest.main()
