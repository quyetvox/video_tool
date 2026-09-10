import unittest
from pathlib import Path
import tempfile
from utils.ffmpeg_utils import FFmpegUtils


class TestWatermarkGuardAndSinglePass(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_watermark_disabled_returns_none(self):
        # Case 1: watermark explicitly disabled
        config = {
            "watermark_enable": False,
            "watermark_text": "My Branding Logo"
        }
        res = FFmpegUtils.validate_watermark_config(config, workspace=self.workspace)
        self.assertIsNone(res)

        # Case 2: watermark disabled in nested dict
        config2 = {
            "watermark": {
                "enabled": False,
                "text": "My Branding Logo"
            }
        }
        res2 = FFmpegUtils.validate_watermark_config(config2, workspace=self.workspace)
        self.assertIsNone(res2)

        # Case 3: no enabled key provided
        config3 = {
            "watermark_text": "My Branding Logo"
        }
        res3 = FFmpegUtils.validate_watermark_config(config3, workspace=self.workspace)
        self.assertIsNone(res3)

    def test_watermark_misconfigured_content_returns_none(self):
        # Case 4: enabled=True but image does not exist and text is empty
        config = {
            "watermark_enable": True,
            "watermark_image": "non_existent_logo.png",
            "watermark_text": "   "
        }
        res = FFmpegUtils.validate_watermark_config(config, workspace=self.workspace)
        self.assertIsNone(res, "Should disallow watermark when image is missing and text is blank")

    def test_watermark_zero_opacity_returns_none(self):
        # Case 5: enabled=True, text valid, but opacity is 0.0
        config = {
            "watermark_enable": True,
            "watermark_text": "Valid Logo",
            "watermark_opacity": 0.0
        }
        res = FFmpegUtils.validate_watermark_config(config, workspace=self.workspace)
        self.assertIsNone(res, "Should disallow watermark when opacity <= 0")

    def test_watermark_valid_text_allowed(self):
        config = {
            "watermark_enable": True,
            "watermark_text": "Sub-Video AI",
            "watermark_opacity": 0.85,
            "watermark_font_color": "yellow",
            "watermark_blur_bg": True,
            "watermark_region": [0.05, 0.70, 0.10, 0.95]
        }
        res = FFmpegUtils.validate_watermark_config(config, workspace=self.workspace)
        self.assertIsNotNone(res)
        self.assertTrue(res["enabled"])
        self.assertEqual(res["text"], "Sub-Video AI")
        self.assertEqual(res["opacity"], 0.85)
        self.assertEqual(res["font_color"], "yellow")
        self.assertTrue(res["blur_bg"])
        self.assertEqual(res["region"], [0.05, 0.70, 0.10, 0.95])

    def test_watermark_valid_image_allowed(self):
        # Create a mock image file
        mock_img = self.workspace / "logo.png"
        mock_img.write_text("fake image data")

        config = {
            "watermark": {
                "enabled": True,
                "image": "logo.png",
                "opacity": 0.9
            }
        }
        res = FFmpegUtils.validate_watermark_config(config, workspace=self.workspace)
        self.assertIsNotNone(res)
        self.assertTrue(res["enabled"])
        self.assertEqual(res["image_path"], str(mock_img))
        self.assertEqual(res["text"], "")

    def test_build_watermark_filters_text(self):
        wm_cfg = {
            "enabled": True,
            "text": "Hello Watermark",
            "opacity": 0.8,
            "blur_bg": True,
            "region": [0.02, 0.65, 0.08, 0.95],
            "font_name": "Arial",
            "font_color": "white"
        }
        inputs = ["-i", "video.mp4"]
        last_stream, filters = FFmpegUtils.build_watermark_filters(
            last_stream="[0:v]",
            width=1920,
            height=1080,
            watermark_config=wm_cfg,
            inputs=inputs
        )
        self.assertEqual(last_stream, "[v_wm_out]")
        self.assertEqual(len(inputs), 2, "No extra input should be added for text watermark")
        # Should have blur background filter + drawtext filter
        self.assertEqual(len(filters), 2)
        self.assertTrue(any("avgblur" in f for f in filters))
        self.assertTrue(any("drawtext" in f for f in filters))

    def test_build_watermark_filters_image(self):
        mock_img = self.workspace / "test_logo.png"
        mock_img.write_text("fake image")

        wm_cfg = {
            "enabled": True,
            "image_path": str(mock_img),
            "opacity": 0.75,
            "blur_bg": False,
            "region": [0.02, 0.10, 0.08, 0.30]
        }
        inputs = ["-i", "video.mp4"]
        last_stream, filters = FFmpegUtils.build_watermark_filters(
            last_stream="[0:v]",
            width=1920,
            height=1080,
            watermark_config=wm_cfg,
            inputs=inputs
        )
        self.assertEqual(last_stream, "[v_wm_out]")
        self.assertEqual(len(inputs), 4, "Should append -i <image_path> to inputs")
        self.assertEqual(inputs[2], "-i")
        self.assertEqual(inputs[3], str(mock_img))
        self.assertTrue(any("overlay=" in f and "[logo]" in f for f in filters))


if __name__ == "__main__":
    unittest.main()
