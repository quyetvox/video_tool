import argparse
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.models import LectureBatch, LectureProject, LectureProjectConfig
from lecture_illustrator_orchestrator import _recalculate_project_timeline, run_sync_batch_audio_flow


class TestSyncBatchAudio(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name)
        self.proj_file = self.workspace / "lecture_project.json"
        self.tts_dir = self.workspace / "tts"
        self.tts_dir.mkdir(parents=True, exist_ok=True)

        sample_data = {
            "version": "1.0",
            "video_path": "test.mp4",
            "batches": [
                {
                    "id": "batch_001",
                    "transcript_original": "Intro",
                    "transcript_translated": "Khái niệm mở đầu",
                    "start_sec": 0.0,
                    "end_sec": 4.0,
                    "scene_duration": 4.0,
                    "step_starts": [0.0],
                    "sentences": [
                        {
                            "index": 0,
                            "text": "Khái niệm mở đầu",
                            "text_orig": "Intro",
                            "start": 0.0,
                            "end": 4.0,
                            "duration": 4.0,
                            "audio_file": "s_0000.mp3",
                        }
                    ],
                    "scene": {"template": "bullet_list", "title": "Mở đầu"},
                },
                {
                    "id": "batch_002",
                    "transcript_original": "Body",
                    "transcript_translated": "Phần thân bài",
                    "start_sec": 4.0,
                    "end_sec": 9.0,
                    "scene_duration": 5.0,
                    "step_starts": [0.0],
                    "sentences": [
                        {
                            "index": 1,
                            "text": "Phần thân bài",
                            "text_orig": "Body",
                            "start": 0.0,
                            "end": 5.0,
                            "duration": 5.0,
                            "audio_file": "s_0001.mp3",
                        }
                    ],
                    "scene": {"template": "bullet_list", "title": "Thân bài"},
                },
            ],
            "config": {
                "aspect_ratio": "16:9",
                "voice_mode": "tts_dub",
                "tts_voice": "vi-VN-HoaiMyNeural",
                "tts_speed": 1.15,
            },
        }
        self.proj_file.write_text(json.dumps(sample_data, ensure_ascii=False, indent=2), encoding="utf-8")

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_recalculate_project_timeline(self):
        data = json.loads(self.proj_file.read_text(encoding="utf-8"))
        proj = LectureProject.from_dict(data)

        # Giả lập batch_001 tăng thời lượng từ 4s lên 7s
        proj.batches[0].scene_duration = 7.0
        _recalculate_project_timeline(proj)

        self.assertEqual(proj.batches[0].start_sec, 0.0)
        self.assertEqual(proj.batches[0].end_sec, 7.0)
        self.assertEqual(proj.batches[1].start_sec, 7.0)
        self.assertEqual(proj.batches[1].end_sec, 12.0)

    @patch("utils.movie_review_tts.MovieReviewTTS.synthesize_single", return_value=3.5)
    def test_sync_batch_audio_update(self, mock_tts):
        args = argparse.Namespace(
            mode="sync_batch_audio",
            project_file=str(self.proj_file),
            workspace=str(self.workspace),
            batch_id="batch_001",
            text="Nội dung mới của mở đầu đã được sửa.",
            action="update",
            insert_at=None,
        )

        ret = run_sync_batch_audio_flow(args)
        self.assertEqual(ret, 0)

        # Kiểm tra nội dung project sau cập nhật
        data = json.loads(self.proj_file.read_text(encoding="utf-8"))
        b1 = data["batches"][0]
        self.assertEqual(b1["transcript_translated"], "Nội dung mới của mở đầu đã được sửa.")
        self.assertEqual(b1["scene_duration"], 3.5)
        self.assertEqual(b1["start_sec"], 0.0)
        self.assertEqual(b1["end_sec"], 3.5)

        # Batch 2 phải tự dồn timeline
        b2 = data["batches"][1]
        self.assertEqual(b2["start_sec"], 3.5)
        self.assertEqual(b2["end_sec"], 8.5)

    @patch("utils.movie_review_tts.MovieReviewTTS.synthesize_single", return_value=4.0)
    def test_sync_batch_audio_create(self, mock_tts):
        args = argparse.Namespace(
            mode="sync_batch_audio",
            project_file=str(self.proj_file),
            workspace=str(self.workspace),
            batch_id="batch_new",
            text="Đây là phân cảnh mới được thêm vào.",
            action="create",
            insert_at=1,  # Chèn vào giữa batch_001 và batch_002
        )

        ret = run_sync_batch_audio_flow(args)
        self.assertEqual(ret, 0)

        data = json.loads(self.proj_file.read_text(encoding="utf-8"))
        self.assertEqual(len(data["batches"]), 3)
        inserted = data["batches"][1]
        self.assertEqual(inserted["id"], "batch_new")
        self.assertEqual(inserted["transcript_translated"], "Đây là phân cảnh mới được thêm vào.")
        self.assertEqual(inserted["scene_duration"], 4.0)
        self.assertEqual(inserted["start_sec"], 4.0)
        self.assertEqual(inserted["end_sec"], 8.0)

        # Batch cuối dồn tiếp
        b_last = data["batches"][2]
        self.assertEqual(b_last["id"], "batch_002")
        self.assertEqual(b_last["start_sec"], 8.0)
        self.assertEqual(b_last["end_sec"], 13.0)

    def test_sync_batch_audio_delete(self):
        args = argparse.Namespace(
            mode="sync_batch_audio",
            project_file=str(self.proj_file),
            workspace=str(self.workspace),
            batch_id="batch_001",
            text=None,
            action="delete",
            insert_at=None,
        )

        ret = run_sync_batch_audio_flow(args)
        self.assertEqual(ret, 0)

        data = json.loads(self.proj_file.read_text(encoding="utf-8"))
        self.assertEqual(len(data["batches"]), 1)
        remaining = data["batches"][0]
        self.assertEqual(remaining["id"], "batch_002")
        self.assertEqual(remaining["start_sec"], 0.0)
        self.assertEqual(remaining["end_sec"], 5.0)


if __name__ == "__main__":
    unittest.main()
