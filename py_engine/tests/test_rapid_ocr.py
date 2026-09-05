import sys
import unittest
from pathlib import Path
from unittest.mock import patch

# Ensure py_engine is in sys.path
ENGINE_DIR = Path(__file__).resolve().parent.parent
if str(ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(ENGINE_DIR))

from plugins.ocr.rapid_ocr import _parse_rapid_result


class TestRapidOCR(unittest.TestCase):
    def test_parse_rapid_result(self):
        # Mock RapidOCR result: list of [box, text, confidence]
        # box: [[x0, y0], [x1, y1], [x2, y2], [x3, y3]]
        # crop: 1000 x 200 (width=1000, height=200)
        # full image region: ymin=0.8, xmin=0.0, ymax=1.0, xmax=1.0
        mock_result = [
            [
                [[100, 20], [500, 20], [500, 80], [100, 80]],
                "你好世界",
                0.98
            ],
            [
                [[50, 100], [250, 100], [250, 150], [50, 150]],
                "Sub-Video Test",
                0.95
            ],
            [
                [[0, 0], [10, 0], [10, 10], [0, 10]],
                "low_conf",
                0.10  # should be filtered out because confidence < 0.35
            ]
        ]

        crop_w = 1000
        crop_h = 200
        xmin, xmax, ymin, ymax = 0.0, 1.0, 0.8, 1.0

        texts, boxes = _parse_rapid_result(mock_result, crop_w, crop_h, xmin, xmax, ymin, ymax)

        self.assertEqual(len(texts), 2)
        self.assertEqual(texts[0], "你好世界")
        self.assertEqual(texts[1], "Sub-Video Test")

        # Box 0 check
        # xs: min 100, max 500 => xmin = 0.1, xmax = 0.5
        # ys: min 20, max 80 => ymin = 0.8 + (20/200)*0.2 = 0.82, ymax = 0.8 + (80/200)*0.2 = 0.88
        b0 = boxes[0]
        self.assertAlmostEqual(b0[0], 0.82)
        self.assertAlmostEqual(b0[1], 0.10)
        self.assertAlmostEqual(b0[2], 0.88)
        self.assertAlmostEqual(b0[3], 0.50)

    def test_plugin_loader_ocr_routing_windows(self):
        with patch("sys.platform", "win32"):
            # Re-import or test PluginLoader routing
            from core.plugin_loader import PluginLoader
            # Test that loading 'apple_vision' or 'paddle_ocr' redirects to rapid_ocr
            # We verify the module path resolution logic by catching the import
            with patch("importlib.import_module") as mock_import:
                mock_module = mock_import.return_value
                mock_module.Plugin = lambda config: "mock_rapid_plugin"

                plugin = PluginLoader.load_plugin("ocr", "apple_vision", {})
                mock_import.assert_called_with("plugins.ocr.rapid_ocr")

                plugin2 = PluginLoader.load_plugin("ocr", "paddleocr", {})
                mock_import.assert_called_with("plugins.ocr.rapid_ocr")

    def test_plugin_loader_inpaint_routing_windows(self):
        with patch("sys.platform", "win32"):
            from core.plugin_loader import PluginLoader
            with patch("importlib.import_module") as mock_import:
                mock_module = mock_import.return_value
                mock_module.Plugin = lambda config: "mock_blur_plugin"

                # apple_vision or apple_vision_inpaint should map to ffmpeg_blur on Windows
                plugin = PluginLoader.load_plugin("inpaint", "apple_vision_inpaint", {})
                mock_import.assert_called_with("plugins.inpaint.ffmpeg_blur")

                plugin2 = PluginLoader.load_plugin("inpaint", "apple_vision", {})
                mock_import.assert_called_with("plugins.inpaint.ffmpeg_blur")


if __name__ == "__main__":
    unittest.main()
