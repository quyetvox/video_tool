"""
Unit and integration tests for TTS Speed sync and Multi-Process Render Acceleration.
- Test 1: LectureProjectConfig serialization with num_workers & fps
- Test 2: compute_batch_fingerprint sensitivity to FPS change
- Test 3: Audio manifest save/load and sentence audio fingerprinting
- Test 4: ensure_project_audio_and_timeline_sync detects speed change and recalculates audio-anchor timeline
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

ROOT_PY_ENGINE = Path(__file__).resolve().parent.parent
if str(ROOT_PY_ENGINE) not in sys.path:
    sys.path.insert(0, str(ROOT_PY_ENGINE))

from lecture_illustrator.models import LectureBatch, LectureProject, LectureProjectConfig
from lecture_illustrator.common import (
    load_audio_manifest,
    save_audio_manifest,
    compute_sentence_audio_fingerprint,
    LEAD_IN,
    SENTENCE_GAP,
    TAIL,
)
from lecture_illustrator.visual_renderer import compute_batch_fingerprint
from lecture_illustrator_orchestrator import ensure_project_audio_and_timeline_sync


class TestTtsSpeedAndRenderAcceleration(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name)
        (self.workspace / "tts").mkdir(parents=True, exist_ok=True)
        (self.workspace / "scenes").mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_lecture_project_config_serialization(self):
        """Kiểm tra LectureProjectConfig lưu và đọc chính xác num_workers và fps."""
        cfg = LectureProjectConfig(
            tts_speed=1.35,
            num_workers=4,
            fps=18,
        )
        d = cfg.to_dict()
        self.assertEqual(d["tts_speed"], 1.35)
        self.assertEqual(d["num_workers"], 4)
        self.assertEqual(d["fps"], 18)

        restored = LectureProjectConfig.from_dict(d)
        self.assertEqual(restored.tts_speed, 1.35)
        self.assertEqual(restored.num_workers, 4)
        self.assertEqual(restored.fps, 18)

    def test_compute_batch_fingerprint_fps_sensitivity(self):
        """Kiểm tra compute_batch_fingerprint đổi giá trị khi đổi FPS."""
        batch = LectureBatch(
            id="batch_001",
            start_sec=0.0,
            end_sec=10.0,
            transcript_original="Test batch",
            transcript_translated="Phân cảnh kiểm thử",
            scene_duration=10.0,
            step_starts=[0.0, 5.0],
        )

        cfg_24 = LectureProjectConfig(fps=24)
        cfg_18 = LectureProjectConfig(fps=18)

        fp_24 = compute_batch_fingerprint(batch, cfg_24)
        fp_18 = compute_batch_fingerprint(batch, cfg_18)

        self.assertNotEqual(fp_24, fp_18, "Fingerprint phải khác nhau khi FPS thay đổi để kích hoạt re-render")

    def test_audio_manifest_save_load_and_fingerprint(self):
        """Kiểm tra đọc ghi .audio_manifest.json và tính toán fingerprint câu."""
        fp1 = compute_sentence_audio_fingerprint("Xin chào các bạn", "ban_mai", 1.15)
        fp2 = compute_sentence_audio_fingerprint("Xin chào các bạn", "ban_mai", 1.35)
        fp3 = compute_sentence_audio_fingerprint("Xin chào các bạn", "hoai_my", 1.15)

        self.assertNotEqual(fp1, fp2, "Fingerprint phải đổi khi speed đổi")
        self.assertNotEqual(fp1, fp3, "Fingerprint phải đổi khi voice đổi")

        manifest = {
            "s_0001.mp3": {
                "hash": fp1,
                "duration": 2.5,
                "text": "Xin chào các bạn",
                "voice": "ban_mai",
                "speed": 1.15,
            }
        }
        tts_dir = self.workspace / "tts"
        save_audio_manifest(tts_dir, manifest)

        loaded = load_audio_manifest(tts_dir)
        self.assertIn("s_0001.mp3", loaded)
        self.assertEqual(loaded["s_0001.mp3"]["hash"], fp1)
        self.assertEqual(loaded["s_0001.mp3"]["duration"], 2.5)

    @patch("utils.movie_review_tts.MovieReviewTTS.get_audio_duration")
    @patch("utils.movie_review_tts.MovieReviewTTS.synthesize_single")
    def test_ensure_project_audio_sync_detects_speed_change(self, mock_synthesize, mock_get_duration):
        """
        Kiểm tra ensure_project_audio_and_timeline_sync tự động phát hiện khi tts_speed đổi:
        - Tổng hợp lại file âm thanh câu
        - Cập nhật lại step_starts và scene_duration
        - Lưu lại .audio_manifest.json mới
        """
        tts_dir = self.workspace / "tts"
        s1_file = tts_dir / "s_0000.mp3"
        s1_file.write_bytes(b"dummy_mp3_content" * 50)

        old_fp = compute_sentence_audio_fingerprint("Kiến trúc hướng sự kiện là gì?", "ban_mai", 1.15)
        old_manifest = {
            "s_0000.mp3": {
                "hash": old_fp,
                "duration": 4.0,
                "text": "Kiến trúc hướng sự kiện là gì?",
                "voice": "ban_mai",
                "speed": 1.15,
            }
        }
        save_audio_manifest(tts_dir, old_manifest)

        batch = LectureBatch(
            id="batch_001",
            start_sec=0.0,
            end_sec=5.8,
            transcript_original="What is Event-Driven Architecture?",
            transcript_translated="Kiến trúc hướng sự kiện là gì?",
            scene_duration=5.8,
            step_starts=[1.2],
            sentences=[
                {
                    "text": "Kiến trúc hướng sự kiện là gì?",
                    "text_orig": "What is Event-Driven Architecture?",
                    "start": 0.0,
                    "end": 4.0,
                    "audio_file": "s_0000.mp3",
                }
            ],
        )

        new_config = LectureProjectConfig(
            tts_voice="ban_mai",
            tts_speed=1.35,
        )
        project = LectureProject(
            project_name="test_project",
            video_path=str(self.workspace / "source.mp4"),
            config=new_config,
            batches=[batch],
        )

        # Giả lập TTS trả về audio mới ngắn hơn (3.2s do tăng speed 1.35x)
        mock_synthesize.return_value = 3.2
        mock_get_duration.return_value = 3.2

        changed = ensure_project_audio_and_timeline_sync(project, self.workspace, force_resynth=False)

        self.assertTrue(changed, "Hàm phải phát hiện audio thay đổi do speed lệch")
        self.assertTrue(mock_synthesize.called, "Phải gọi synthesize_single lại câu có speed mới")

        # Kiểm tra timeline mới được dồn lại:
        # Lead-in = 1.2
        # scene_duration = 1.2 + 3.2 + TAIL (0.6) = 5.0s
        self.assertAlmostEqual(project.batches[0].scene_duration, 1.2 + 3.2 + TAIL, places=2)
        self.assertEqual(project.batches[0].step_starts, [1.2])

        # Kiểm tra manifest mới đã được cập nhật speed 1.35
        new_manifest = load_audio_manifest(tts_dir)
        expected_new_fp = compute_sentence_audio_fingerprint("Kiến trúc hướng sự kiện là gì?", "ban_mai", 1.35)
        self.assertEqual(new_manifest["s_0000.mp3"]["hash"], expected_new_fp)
        self.assertAlmostEqual(new_manifest["s_0000.mp3"]["duration"], 3.2, places=2)


if __name__ == "__main__":
    unittest.main()
