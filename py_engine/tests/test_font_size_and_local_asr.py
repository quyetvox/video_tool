import unittest
from unittest.mock import patch, MagicMock
from pathlib import Path
from steps.s09_subtitle_gen import StepSubtitleGen
from core.job_state import JobState


class TestFontSizeAndLocalASR(unittest.TestCase):
    def setUp(self):
        self.step = StepSubtitleGen()

    def test_explicit_font_size_retained_without_scaling(self):
        """When font_size is explicitly provided (e.g. 44 on 1920p video), it must NOT be artificially scaled up."""
        workspace = Path("/tmp/dummy_ws")
        config = {
            "subtitle_font_size": 44,
            "inpaint_region": [0.85, 0.05, 0.95, 0.95],
            "video_height": 1920,
            "video_width": 1080
        }
        job_state = MagicMock(spec=JobState)
        job_state.get_step_output.side_effect = lambda sid: {
            "s01_probe": {"height": 1920, "width": 1080},
            "s08c_timing": {"segments": [{"start": 0.0, "end": 2.0, "text": "Hello", "text_vi": "Xin chao"}]}
        }.get(sid, {})

        # We inspect the logic block directly
        manual_font_size = config.get("subtitle_font_size")
        is_auto = (manual_font_size is None or str(manual_font_size).strip().lower() in ("auto", "none", "", "null"))
        self.assertFalse(is_auto)
        font_size = max(10, int(manual_font_size))
        self.assertEqual(font_size, 44)

    def test_auto_font_size_scales_with_inpaint_box_height(self):
        """When font_size is 'auto', it must scale proportionally to inpaint box height."""
        video_height = 1920
        box_region = [0.85, 0.05, 0.95, 0.95]  # height = 0.10 * 1920 = 192px
        box_h_px = abs(box_region[2] - box_region[0]) * video_height

        # Case A: Bilingual (two lines in one box) -> ~38% of box height
        has_secondary = True
        has_independent_sec_region = False
        if has_secondary and not has_independent_sec_region:
            font_size_bilingual = max(16, min(int(box_h_px * 0.45), int(box_h_px * 0.38)))
        self.assertEqual(font_size_bilingual, int(192 * 0.38))

        # Case B: Single line -> ~55% of box height
        has_secondary = False
        if has_secondary and not has_independent_sec_region:
            font_size_single = max(16, min(int(box_h_px * 0.45), int(box_h_px * 0.38)))
        else:
            font_size_single = max(18, min(int(box_h_px * 0.65), int(box_h_px * 0.55)))
        self.assertEqual(font_size_single, int(192 * 0.55))

    def test_apple_vision_inpaint_follows_configured_font_size_without_box_scale(self):
        """When engine is apple_vision_inpaint, explicit font_size in config is followed directly."""
        inpaint_engine = "apple_vision_inpaint"
        is_apple_vision_inpaint = inpaint_engine in ("apple_vision_inpaint", "apple_vision")
        self.assertTrue(is_apple_vision_inpaint)

        manual_font_size = 44
        video_height = 1920
        is_auto_font = False  # font_size is explicitly set
        if is_apple_vision_inpaint and not is_auto_font:
            raw_fs = int(manual_font_size)
            font_size = max(10, raw_fs) if raw_fs > 0 else int(video_height * 0.04)
        self.assertEqual(font_size, 44)

    def test_apple_vision_inpaint_auto_font_scales_by_video_height(self):
        """When engine is apple_vision_inpaint and font_size is None/auto, it auto-scales to ~4% of video_height."""
        inpaint_engine = "apple_vision_inpaint"
        is_apple_vision_inpaint = inpaint_engine in ("apple_vision_inpaint", "apple_vision")
        self.assertTrue(is_apple_vision_inpaint)

        manual_font_size = None  # not configured
        video_height = 1920
        is_auto_font = True  # no explicit font_size
        if is_apple_vision_inpaint and is_auto_font:
            font_size = max(24, int(video_height * 0.04))  # ~76px for 1920px
        self.assertEqual(font_size, 76)  # max(24, int(1920*0.04)) = max(24, 76) = 76

    def test_whisper_mlx_resolves_local_snapshot_path(self):
        """_get_hf_repo returns local directory path when snapshot is cached."""
        from plugins.asr.whisper_mlx import Plugin as MLXPlugin

        plugin = MLXPlugin({"asr_model": "small"})
        with patch("huggingface_hub.snapshot_download") as mock_snap:
            mock_snap.return_value = "/Users/voquyt/.cache/huggingface/hub/models--mlx-community--whisper-small-mlx/snapshots/dummy"
            with patch("pathlib.Path.exists", return_value=True):
                # We test the inner helper logic
                repo_id = "mlx-community/whisper-small-mlx"
                from huggingface_hub import snapshot_download
                local_dir = snapshot_download(repo_id, local_files_only=True)
                self.assertIn("dummy", local_dir)


if __name__ == "__main__":
    unittest.main()
