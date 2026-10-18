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
from lecture_illustrator_orchestrator import (
    _recalculate_project_timeline,
    run_sync_batch_audio_flow,
    split_text_into_lecture_sentences,
)


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

    def test_split_text_into_lecture_sentences(self):
        # 1. Câu ngắn giữ nguyên
        s1 = "Khái niệm mở đầu bài giảng."
        self.assertEqual(split_text_into_lecture_sentences(s1), ["Khái niệm mở đầu bài giảng."])

        # 2. Danh sách bullet / numbering markdown được làm sạch và tách câu riêng biệt
        s2 = """1. Giới thiệu kiến trúc Microservices.
2. Phân tích ưu nhược điểm so với Monolith.
3. Các giải pháp triển khai."""
        res2 = split_text_into_lecture_sentences(s2)
        self.assertEqual(len(res2), 3)
        self.assertEqual(res2[0], "Giới thiệu kiến trúc Microservices.")
        self.assertEqual(res2[1], "Phân tích ưu nhược điểm so với Monolith.")
        self.assertEqual(res2[2], "Các giải pháp triển khai.")

        # 3. Câu dài > 95 ký tự được tách theo dấu phẩy / mệnh đề
        s3 = "Trong mô hình MVC truyền thống, controller nhận request từ client, tương tác với model để lấy hoặc cập nhật dữ liệu, sau đó trả về view tương ứng cho người dùng."
        res3 = split_text_into_lecture_sentences(s3, max_chars=95)
        self.assertTrue(len(res3) >= 2)
        for part in res3:
            self.assertLessEqual(len(part), 95)

        # 4. Text rỗng trả về list rỗng
        self.assertEqual(split_text_into_lecture_sentences("   \n  "), [])

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

    @patch("utils.movie_review_tts.MovieReviewTTS.synthesize_single", return_value=2.0)
    def test_sync_batch_audio_splits_multiple_sentences(self, mock_tts):
        # Người dùng nhập nội dung gồm 3 câu / bullet points
        multi_text = """- Chào mừng các bạn đến với bài học hôm nay.
- Chúng ta sẽ tìm hiểu về kiến trúc Event Driven.
- Hệ thống sẽ xử lý thông điệp bất đồng bộ qua message queue."""

        args = argparse.Namespace(
            mode="sync_batch_audio",
            project_file=str(self.proj_file),
            workspace=str(self.workspace),
            batch_id="batch_001",
            text=multi_text,
            action="update",
            insert_at=None,
        )

        ret = run_sync_batch_audio_flow(args)
        self.assertEqual(ret, 0)

        data = json.loads(self.proj_file.read_text(encoding="utf-8"))
        b1 = data["batches"][0]

        # Kiểm tra batch_001 đã tự tách thành 3 câu
        self.assertEqual(len(b1["sentences"]), 3)
        self.assertEqual(len(b1["step_starts"]), 3)

        # Câu 1 bắt đầu từ 0.0s, dài 2.0s
        self.assertEqual(b1["step_starts"][0], 0.0)
        self.assertEqual(b1["sentences"][0]["text"], "Chào mừng các bạn đến với bài học hôm nay.")
        self.assertEqual(b1["sentences"][0]["audio_file"], "batch_001_s00.mp3")

        # Câu 2 bắt đầu từ 2.25s (2.0s + 0.25s gap)
        self.assertEqual(b1["step_starts"][1], 2.25)
        self.assertEqual(b1["sentences"][1]["text"], "Chúng ta sẽ tìm hiểu về kiến trúc Event Driven.")
        self.assertEqual(b1["sentences"][1]["audio_file"], "batch_001_s01.mp3")

        # Câu 3 bắt đầu từ 4.5s (2.25s + 2.0s + 0.25s gap)
        self.assertEqual(b1["step_starts"][2], 4.5)
        self.assertEqual(b1["sentences"][2]["audio_file"], "batch_001_s02.mp3")

        # Tổng thời lượng batch = 4.5s + 2.0s + 0.35s tail = 6.85s
        expected_dur = 6.85
        self.assertAlmostEqual(b1["scene_duration"], expected_dur, places=2)
        self.assertAlmostEqual(b1["end_sec"], expected_dur, places=2)

        # Batch 2 tự dồn sau batch 1
        b2 = data["batches"][1]
        self.assertAlmostEqual(b2["start_sec"], expected_dur, places=2)

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
