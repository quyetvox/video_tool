from pathlib import Path
import json
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.models import LectureProjectConfig, LectureBatch, LectureProject
from lecture_illustrator.scene_author import build_scene_author_prompt, author_scene_with_retry
import lecture_illustrator_orchestrator as orch


class TestReauthorBatch(unittest.TestCase):
    def test_build_scene_author_prompt_with_feedback(self):
        prompt = build_scene_author_prompt(
            sentences=["Khái niệm mạng nơ-ron", "Học sâu"],
            step_starts=[0.0, 2.5],
            duration=5.0,
            user_feedback="Vẽ dạng 3 cột và đổi màu nhấn thành đỏ gạch",
        )
        self.assertIn("YÊU CẦU ĐẶC BIỆT / CHỈNH SỬA TỪ NGƯỜI DÙNG:", prompt)
        self.assertIn("Vẽ dạng 3 cột và đổi màu nhấn thành đỏ gạch", prompt)

    def test_author_scene_with_feedback(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            out_html = Path(tmpdir) / "batch_001.html"
            mock_llm_response = """```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <link rel="stylesheet" href="style_kit.css">
</head>
  <div id="stage">
    <svg id="svg" viewBox="0 0 1920 1080">
      <g id="header-group" transform="translate(960, 80)">
        <text text-anchor="middle" font-size="44px" font-weight="bold">BÀI GIẢNG</text>
      </g>
      <rect x="200" y="250" width="360" height="200" fill="#fff" />
    </svg>
  </div>
  <script src="style_kit.js"></script>
  <script>
    window.__load = function(scene) {};
    window.__renderAt = function(t, stepStarts) {
      const el = document.querySelector('text');
      if (el) el.setAttribute('opacity', Math.min(1, t));
    };
  </script>
</body>
</html>
```"""
            ok, sc_data, sc_meta = author_scene_with_retry(
                batch_id="batch_001",
                sentences=["Câu 1"],
                step_starts=[0.0],
                duration=3.0,
                aspect_ratio="16:9",
                out_html_path=out_html,
                llm_caller=lambda p: mock_llm_response,
                user_feedback="Thêm icon minh họa",
            )
            self.assertTrue(ok)
            self.assertEqual(sc_data["mode"], "authored")
            self.assertTrue(out_html.exists())

    def test_run_reauthor_batch_flow(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            ws = Path(tmpdir)
            proj_file = ws / "lecture_project.json"
            batch = LectureBatch(
                id="batch_002",
                start_sec=10.0,
                end_sec=15.0,
                transcript_original="Nguyên lý hoạt động",
                transcript_translated="Nguyên lý hoạt động",
                sentences=[{"text": "Nguyên lý", "audio_file": "s_0001.mp3"}],
                scene={"mode": "template", "template": "bullet_list"},
                step_starts=[0.0],
                scene_duration=5.0,
            )
            project = LectureProject(
                project_name="test_proj",
                video_path=str(ws / "video.mp4"),
                video_duration=15.0,
                config=LectureProjectConfig(ai_authored=True),
                batches=[batch],
            )
            proj_file.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")

            args = MagicMock()
            args.batch_id = "batch_002"
            args.project_file = str(proj_file)
            args.workspace = str(ws)
            args.feedback = "Đổi sơ đồ thành 3 cột"
            args.html_author_model = None
            args.html_author_base_url = None
            args.html_author_api_key = None
            args.api_key = None
            args.model = None
            args.base_url = None

            with patch("lecture_illustrator.scene_author.author_scene_with_retry") as mock_author, \
                 patch("lecture_illustrator.visual_renderer.render_single_batch_complete") as mock_render:
                mock_author.return_value = (True, {"mode": "authored", "title": "Nguyên lý"}, {})
                dummy_clip = ws / "scenes" / "batch_002_combined.mp4"
                dummy_clip.parent.mkdir(parents=True, exist_ok=True)
                dummy_clip.write_bytes(b"dummy mp4")
                mock_render.return_value = (dummy_clip, "hash123")

                ret = orch.run_reauthor_batch_flow(args)
                self.assertEqual(ret, 0)

                # Kiểm tra project_file đã được cập nhật sang authored
                updated_data = json.loads(proj_file.read_text(encoding="utf-8"))
                self.assertEqual(updated_data["batches"][0]["scene"]["mode"], "authored")


    def test_run_reauthor_batch_flow_failure_preserves_scene(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            ws = Path(tmpdir)
            proj_file = ws / "lecture_project.json"
            batch = LectureBatch(
                id="batch_003",
                start_sec=10.0,
                end_sec=15.0,
                transcript_original="Original text",
                transcript_translated="Bản dịch",
                sentences=[{"text": "Bản dịch", "audio_file": "s_0001.mp3"}],
                scene={"mode": "template", "template": "bullet_list", "title": "Cũ"},
                step_starts=[0.0],
                scene_duration=5.0,
            )
            project = LectureProject(
                project_name="test_proj",
                video_path=str(ws / "video.mp4"),
                video_duration=15.0,
                config=LectureProjectConfig(ai_authored=True),
                batches=[batch],
            )
            proj_file.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")

            args = MagicMock()
            args.batch_id = "batch_003"
            args.project_file = str(proj_file)
            args.workspace = str(ws)
            args.feedback = "Vẽ giấy"
            args.html_author_model = None
            args.html_author_base_url = None
            args.html_author_api_key = None
            args.api_key = None
            args.model = None
            args.base_url = None

            with patch("lecture_illustrator.scene_author.author_scene_with_retry") as mock_author:
                mock_author.return_value = (False, {"mode": "template", "template": "bullet_list"}, {"errors": ["LLM API Key missing"]})

                ret = orch.run_reauthor_batch_flow(args)
                self.assertEqual(ret, 2)

                # Cảnh cũ không bị ghi đè thành authored
                updated_data = json.loads(proj_file.read_text(encoding="utf-8"))
                self.assertEqual(updated_data["batches"][0]["scene"]["mode"], "template")
                self.assertEqual(updated_data["batches"][0]["scene"]["title"], "Cũ")

    def test_core_constraints_in_prompt(self):
        from lecture_illustrator.scene_author import get_core_design_constraints
        constraints = get_core_design_constraints(1920, 1080)
        self.assertIn("MANDATORY AUTO-LAYOUT", constraints)
        self.assertIn("NO NAN / NO NEGATIVE NUMBERS", constraints)
        self.assertIn("STRICT SHAPE ANTI-OVERLAP", constraints)
        self.assertIn("CONCEPT KEYWORDS", constraints)

        prompt = build_scene_author_prompt(
            sentences=["Bước 1"],
            step_starts=[0.0],
            duration=4.0,
        )
        self.assertIn("HAND-DRAWN", prompt)
        self.assertIn("Patrick Hand", prompt)
        self.assertIn("ZERO-TRUNCATION", prompt)

    def test_ensure_templates_dependencies_injects_font(self):
        from lecture_illustrator.scene_author import ensure_templates_dependencies
        raw_html = """<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body>
  <svg id="svg"></svg>
</body>
</html>"""
        final_html = ensure_templates_dependencies(raw_html)
        self.assertIn("PatrickHand", final_html)
        self.assertIn("@font-face", final_html)


if __name__ == "__main__":
    unittest.main()

