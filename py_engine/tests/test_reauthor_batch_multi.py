import argparse
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator_orchestrator import run_reauthor_batch_multi_flow


class TestReauthorBatchMulti(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name)
        self.scenes_dir = self.workspace / "scenes"
        self.scenes_dir.mkdir(parents=True, exist_ok=True)
        self.proj_file = self.workspace / "lecture_project.json"

        sample_data = {
            "version": "1.0",
            "video_path": "test.mp4",
            "batches": [
                {
                    "id": "batch_001",
                    "transcript_original": "Intro",
                    "transcript_translated": "Mở đầu",
                    "start_sec": 0.0,
                    "end_sec": 4.0,
                    "scene_duration": 4.0,
                    "step_starts": [0.0],
                    "sentences": [{"text": "Mở đầu", "start": 0.0, "end": 4.0, "duration": 4.0}],
                    "scene": {"template": "bullet_list", "title": "Mở đầu"},
                },
                {
                    "id": "batch_002",
                    "transcript_original": "Body",
                    "transcript_translated": "Thân bài",
                    "start_sec": 4.0,
                    "end_sec": 9.0,
                    "scene_duration": 5.0,
                    "step_starts": [0.0],
                    "sentences": [{"text": "Thân bài", "start": 0.0, "end": 5.0, "duration": 5.0}],
                    "scene": {"template": "bullet_list", "title": "Thân bài"},
                },
                {
                    "id": "batch_003",
                    "transcript_original": "Conclusion",
                    "transcript_translated": "Kết luận",
                    "start_sec": 9.0,
                    "end_sec": 13.0,
                    "scene_duration": 4.0,
                    "step_starts": [0.0],
                    "sentences": [{"text": "Kết luận", "start": 0.0, "end": 4.0, "duration": 4.0}],
                    "scene": {"template": "bullet_list", "title": "Kết luận"},
                },
            ],
            "config": {
                "aspect_ratio": "16:9",
                "voice_mode": "tts_dub",
            },
        }
        self.proj_file.write_text(json.dumps(sample_data, ensure_ascii=False, indent=2), encoding="utf-8")

    def tearDown(self):
        self.temp_dir.cleanup()

    @patch("lecture_illustrator.visual_renderer.render_single_batch_complete")
    @patch("lecture_illustrator.scene_author.author_scene_with_retry")
    def test_reauthor_batch_multi_flow(self, mock_author, mock_render):
        # Mock author_scene_with_retry trả về thành công
        def fake_author(batch_id, **kwargs):
            out_p = self.scenes_dir / f"{batch_id}.html"
            out_p.write_text(f"<html><body>{batch_id}</body></html>", encoding="utf-8")
            return True, {"mode": "authored", "template": "custom"}, {}

        mock_author.side_effect = fake_author

        # Mock render_single_batch_complete
        def fake_render(batch, **kwargs):
            vid = self.scenes_dir / f"{batch.id}_video.mp4"
            vid.touch()
            return vid, "hash_xyz"

        mock_render.side_effect = fake_render

        args = argparse.Namespace(
            mode="reauthor_batch_multi",
            project_file=str(self.proj_file),
            workspace=str(self.workspace),
            batch_ids="batch_001,batch_003",
            num_workers=2,
            workers=2,
            feedback="Tái tạo hàng loạt kiểm thử",
            api_key="test_key",
            model=None,
            base_url=None,
            html_author_api_key=None,
            html_author_model=None,
            html_author_base_url=None,
        )

        ret = run_reauthor_batch_multi_flow(args)
        self.assertEqual(ret, 0)

        # Kiểm tra file HTML của batch_001 và batch_003 được tạo
        self.assertTrue((self.scenes_dir / "batch_001.html").exists())
        self.assertTrue((self.scenes_dir / "batch_003.html").exists())
        # batch_002 không được chọn thì không có html
        self.assertFalse((self.scenes_dir / "batch_002.html").exists())

        # Kiểm tra cập nhật project JSON
        data = json.loads(self.proj_file.read_text(encoding="utf-8"))
        self.assertEqual(data["batches"][0]["scene"]["mode"], "authored")
        self.assertEqual(data["batches"][2]["scene"]["mode"], "authored")


if __name__ == "__main__":
    unittest.main()
