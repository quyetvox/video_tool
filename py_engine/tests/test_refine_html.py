import argparse
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.scene_author import (
    build_scene_refine_user_prompt,
    author_scene_with_retry,
    extract_refinement_plan,
)
from lecture_illustrator.knowledge_extractor import call_llm_api
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
        self.assertIn("KẾ HOẠCH TINH CHỈNH", prompt)

    def test_extract_refinement_plan(self):
        raw = """KẾ HOẠCH TINH CHỈNH:
- Dời khối sang phải
- Đổi viền sang đỏ
```html
<!DOCTYPE html><html><body></body></html>
```"""
        plan = extract_refinement_plan(raw)
        self.assertIn("Dời khối sang phải", plan)
        self.assertIn("Đổi viền sang đỏ", plan)
        self.assertNotIn("<!DOCTYPE", plan)

    def test_identical_code_guard_triggers_reflection(self):
        calls = []
        new_html_content = self.existing_html.replace('id="old-box"', 'id="refined-box"')

        def mock_llm(prompt=None, *args, **kwargs):
            actual_prompt = prompt or kwargs.get("prompt") or ""
            calls.append(actual_prompt)
            if len(calls) == 1:
                # Vòng 1: AI lười trả về đúng mã y hệt mã cũ
                return f"```html\n{self.existing_html}\n```"
            # Vòng 2: AI tự sửa sau reflection
            return f"```html\n{new_html_content}\n```"

        with patch("lecture_illustrator.scene_author.call_llm_api", side_effect=mock_llm):
            ok, sc_data, sc_meta = author_scene_with_retry(
                batch_id="batch_001",
                sentences=["Mở đầu bài giảng"],
                step_starts=[0.0],
                duration=5.0,
                aspect_ratio="16:9",
                out_html_path=self.html_file,
                refine_existing_html=self.existing_html,
                user_feedback="Đổi thành refined-box",
            )
            self.assertTrue(ok)
            self.assertEqual(len(calls), 2)
            # Vòng 2 phải là reflection prompt chứa feedback của người dùng
            self.assertIn("Đổi thành refined-box", calls[1])
            self.assertIn("REFINEMENT MANDATE", calls[1])

    def test_refine_failure_preserves_original_scene(self):
        def mock_llm(*args, **kwargs):
            return "Khong the sinh ma"

        with patch("lecture_illustrator.scene_author.call_llm_api", side_effect=mock_llm):
            ok, sc_data, sc_meta = author_scene_with_retry(
                batch_id="batch_001",
                sentences=["Mở đầu bài giảng"],
                step_starts=[0.0],
                duration=5.0,
                aspect_ratio="16:9",
                out_html_path=self.html_file,
                refine_existing_html=self.existing_html,
                user_feedback="Thử nghiệm thất bại",
                max_retries=1,
            )
            self.assertFalse(ok)
            # File HTML gốc phải được bảo toàn, không bị fallback tối giản ghi đè
            content = self.html_file.read_text(encoding="utf-8")
            self.assertEqual(content, self.existing_html)

    @patch("urllib.request.urlopen")
    def test_call_llm_api_temperature_support(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "candidates": [{"content": {"parts": [{"text": "OK"}]}}]
        }).encode("utf-8")
        mock_resp.__enter__.return_value = mock_resp
        mock_urlopen.return_value = mock_resp

        call_llm_api(
            prompt="test",
            api_key="AIzaSyTestKey123",
            model_name="gemini-flash-lite-latest",
            temperature=0.45,
        )

        args, kwargs = mock_urlopen.call_args
        req = args[0]
        data = json.loads(req.data.decode("utf-8"))
        self.assertEqual(data["generationConfig"]["temperature"], 0.45)

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
