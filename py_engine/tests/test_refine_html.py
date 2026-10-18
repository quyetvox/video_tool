import argparse
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.scene_author import build_scene_refine_user_prompt, author_scene_with_retry
from lecture_illustrator_orchestrator import run_reauthor_batch_flow


class TestRefineHtml(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name)
        self.scenes_dir = self.workspace / "scenes"
        self.scenes_dir.mkdir(parents=True, exist_ok=True)
        self.proj_file = self.workspace / "lecture_project.json"

        # Khởi tạo kịch bản mẫu
        sample_data = {
            "version": "1.0",
            "video_path": "test.mp4",
            "batches": [
                {
                    "id": "batch_001",
                    "transcript_original": "Intro",
                    "transcript_translated": "Mở đầu bài giảng",
                    "start_sec": 0.0,
                    "end_sec": 5.0,
                    "scene_duration": 5.0,
                    "step_starts": [0.0],
                    "sentences": [
                        {
                            "index": 0,
                            "text": "Mở đầu bài giảng",
                            "text_orig": "Intro",
                            "start": 0.0,
                            "end": 5.0,
                            "duration": 5.0,
                        }
                    ],
                    "scene": {"template": "bullet_list", "title": "Mở đầu"},
                }
            ],
            "config": {
                "aspect_ratio": "16:9",
                "voice_mode": "tts_dub",
                "tts_voice": "ban_mai",
            },
        }
        self.proj_file.write_text(json.dumps(sample_data, ensure_ascii=False, indent=2), encoding="utf-8")

        # Tạo file HTML mẫu sẵn có
        self.existing_html = """<!DOCTYPE html>
<html>
<head><style>body { margin: 0; }</style></head>
<body>
  <div id="stage"><svg id="svg" viewBox="0 0 1920 1080">
    <g id="header-group" transform="translate(960, 80)"><text>TIÊU ĐỀ</text></g>
    <rect id="old-box" x="200" y="200" width="300" height="150" fill="#ffffff" />
  </svg></div>
  <script>
    window.__load = function() {};
    window.__renderAt = function(t, steps) {};
  </script>
</body>
</html>"""
        self.html_file = self.scenes_dir / "batch_001.html"
        self.html_file.write_text(self.existing_html, encoding="utf-8")

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_build_scene_refine_user_prompt(self):
        feedback = "Dời old-box sang phải và đổi màu viền sang đỏ"
        prompt = build_scene_refine_user_prompt(
            existing_html=self.existing_html,
            user_feedback=feedback,
            sentences=["Mở đầu bài giảng"],
            step_starts=[0.0],
            duration=5.0,
            aspect_ratio="16:9",
        )

        self.assertIn(feedback, prompt)
        self.assertIn("EXISTING HTML CODE", prompt)
        self.assertIn('id="old-box"', prompt)
        self.assertIn("SURGICAL REFINEMENT DIRECTIVE", prompt)

    @patch("lecture_illustrator.visual_renderer.render_single_batch_complete")
    def test_reauthor_batch_with_refine_creates_backup(self, mock_render):
        mock_render.return_value = (self.scenes_dir / "batch_001_video.mp4", "hash123")
        (self.scenes_dir / "batch_001_video.mp4").touch()

        # Mock LLM caller trả về HTML đã được tinh chỉnh
        new_html_content = self.existing_html.replace('id="old-box"', 'id="refined-box"')

        def mock_llm(*args, **kwargs):
            return f"```html\n{new_html_content}\n```"

        with patch("lecture_illustrator.scene_author.call_llm_api", side_effect=mock_llm):
            args = argparse.Namespace(
                mode="reauthor_batch",
                project_file=str(self.proj_file),
                workspace=str(self.workspace),
                batch_id="batch_001",
                feedback="Sửa thành refined-box",
                refine=True,
                api_key="test_key",
                model=None,
                base_url=None,
                html_author_api_key=None,
                html_author_model=None,
                html_author_base_url=None,
            )

            ret = run_reauthor_batch_flow(args)
            self.assertEqual(ret, 0)

            # File backup .bak phải được tạo ra chứa nội dung cũ
            bak_file = self.scenes_dir / "batch_001.html.bak"
            self.assertTrue(bak_file.exists())
            self.assertIn('id="old-box"', bak_file.read_text(encoding="utf-8"))

            # File HTML chính thức đã được cập nhật thành bản tinh chỉnh
            updated_html = self.html_file.read_text(encoding="utf-8")
            self.assertIn('id="refined-box"', updated_html)


if __name__ == "__main__":
    unittest.main()
