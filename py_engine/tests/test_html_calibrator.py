from pathlib import Path
import json
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.html_calibrator import calibrate_imported_html, import_and_calibrate_scene_html
from lecture_illustrator.models import LectureProjectConfig, LectureBatch, LectureProject
import lecture_illustrator_orchestrator as orch


class TestHtmlCalibrator(unittest.TestCase):
    def test_calibrate_imported_html_replaces_durations(self):
        sample_html = """<!DOCTYPE html>
<html>
<head><title>Test</title></head>
<body>
  <div id="stage"><svg id="svg" viewBox="0 0 1920 1080"></svg></div>
  <script>
    const SCENE_DURATION = 12.0;
    const STEP_STARTS = [0.0, 4.0, 8.0];
    window.__renderAt = function(t, stepStarts) {
      console.log(t, stepStarts);
    };
  </script>
</body>
</html>"""
        calibrated = calibrate_imported_html(
            raw_html=sample_html,
            actual_duration=7.5,
            actual_step_starts=[0.0, 2.5, 5.0],
        )

        self.assertIn("const SCENE_DURATION = 7.5;", calibrated)
        self.assertIn("const STEP_STARTS = [0.0, 2.5, 5.0];", calibrated)
        self.assertIn("var actualDur = 7.5;", calibrated)
        self.assertIn("window.__ACTUAL_SCENE_DURATION = actualDur;", calibrated)
        self.assertIn("Sub-Video Auto-Calibration Bridge", calibrated)

    def test_calibrate_markdown_fenced_html(self):
        fenced_html = """```html
<!DOCTYPE html>
<html><body><h1>Heading</h1></body></html>
```"""
        calibrated = calibrate_imported_html(
            raw_html=fenced_html,
            actual_duration=5.0,
            actual_step_starts=[0.0, 2.0],
        )
        self.assertFalse(calibrated.startswith("```"))
        self.assertIn("Sub-Video Auto-Calibration Bridge", calibrated)

    def test_import_and_calibrate_file(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            in_file = Path(tmpdir) / "source.html"
            out_file = Path(tmpdir) / "scenes" / "batch_001.html"
            in_file.write_text("<!DOCTYPE html><html><body><svg></svg></body></html>", encoding="utf-8")

            res_path = import_and_calibrate_scene_html(
                input_html_path=in_file,
                output_html_path=out_file,
                actual_duration=8.2,
                actual_step_starts=[0.0, 3.1],
            )
            self.assertTrue(res_path.exists())
            content = res_path.read_text(encoding="utf-8")
            self.assertIn("var actualDur = 8.2;", content)
            self.assertIn("var actualSteps = [0.0, 3.1];", content)

    def test_run_import_batch_html_flow(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            proj_file = tmp_path / "lecture_project.json"
            cfg = LectureProjectConfig(aspect_ratio="16:9")
            batch = LectureBatch(
                id="batch_001",
                start_sec=0.0,
                end_sec=6.0,
                transcript_original="Hello world",
                transcript_translated="Xin chào thế giới",
                sentences=[{"text": "Xin chào thế giới"}],
                step_starts=[0.0],
                scene_duration=6.0,
                scene={"mode": "template", "template": "bullet_list"},
            )
            proj = LectureProject(
                project_name="TestProj",
                video_path=str(tmp_path / "dummy.mp4"),
                video_duration=6.0,
                video_width=1920,
                video_height=1080,
                config=cfg,
                batches=[batch],
            )
            proj_file.write_text(json.dumps(proj.to_dict()), encoding="utf-8")

            imported_html = tmp_path / "external.html"
            imported_html.write_text("<!DOCTYPE html><html><body><svg></svg></body></html>", encoding="utf-8")

            import argparse
            args = argparse.Namespace(
                project_file=str(proj_file),
                batch_id="batch_001",
                html_file=str(imported_html),
            )

            from unittest.mock import patch
            mock_video = tmp_path / "scenes" / "batch_001_combined.mp4"
            mock_video.parent.mkdir(parents=True, exist_ok=True)
            mock_video.touch()

            with patch("lecture_illustrator.visual_renderer.render_single_batch_complete", return_value=(mock_video, "hash123")):
                ret = orch.run_import_batch_html_flow(args)
                self.assertEqual(ret, 0)

            # Kiểm tra file đã được ghi và cập nhật
            out_html = tmp_path / "scenes" / "batch_001.html"
            self.assertTrue(out_html.exists())
            meta_json = tmp_path / "scenes" / "batch_001.meta.json"
            self.assertTrue(meta_json.exists())

            updated_proj = json.loads(proj_file.read_text(encoding="utf-8"))
            b0 = updated_proj["batches"][0]
            self.assertEqual(b0["scene"]["mode"], "authored")
            self.assertTrue(b0["scene"].get("imported"))
            self.assertIn("batch_001_combined.mp4", b0.get("scene_video", ""))

    def test_evaluate_and_calibrate_scene_html_quality_scoring(self):
        from lecture_illustrator.html_calibrator import evaluate_and_calibrate_scene_html
        sample_html = """<!DOCTYPE html>
<html>
<head><title>Test Quality</title></head>
<body>
  <div id="stage"><svg id="svg" viewBox="0 0 1920 1080">
    <g id="main-canvas">
      <text x="100" y="200" font-size="14">Small Text</text>
      <text x="500" y="300" font-size="28">Big Title</text>
    </g>
  </svg></div>
  <script>
    const SCENE_DURATION = 8.0;
    const STEP_STARTS = [0.0, 4.0];
    window.__load = function() {};
    window.__renderAt = function(t, s) {};
  </script>
</body>
</html>"""
        calibrated, report = evaluate_and_calibrate_scene_html(
            html_str=sample_html,
            duration=8.0,
            step_starts=[0.0, 4.0],
            aspect_ratio="16:9",
        )
        self.assertIn("quality_score", report)
        self.assertGreaterEqual(report["quality_score"], 75)
        self.assertTrue(report["passed"])
        self.assertIn("eval_details", report)
        self.assertTrue(report["eval_details"]["timing_contract"]["passed"])

    def test_latex_math_auto_sanitizer(self):
        from lecture_illustrator.html_calibrator import sanitize_latex_formulas, evaluate_and_calibrate_scene_html
        raw_text = "Thứ tự: ASC $\\leftrightarrow$ DESC và $O(n^2)$ $\\le$ $O(n^3)$"
        clean = sanitize_latex_formulas(raw_text)
        self.assertIn("⟷", clean)
        self.assertIn("O(n²)", clean)
        self.assertIn("≤", clean)
        self.assertIn("O(n³)", clean)

        html_with_latex = """<!DOCTYPE html>
<html>
<body>
  <div id="stage"><svg id="svg" viewBox="0 0 1920 1080">
    <text id="math-tx" x="960" y="500">Tăng dần $\\leftrightarrow$ Giảm dần</text>
  </svg></div>
  <script>window.__renderAt = function(t, s) {};</script>
</body>
</html>"""
        calibrated, rep = evaluate_and_calibrate_scene_html(html_with_latex, duration=5.0, step_starts=[0.0])
        self.assertIn("⟷", calibrated)
        self.assertNotIn("$\\leftrightarrow$", calibrated)
        self.assertTrue(any("sanitized_latex" in c for c in rep.get("calibrations", [])))

    def test_row_level_subgroup_auto_centering(self):
        from lecture_illustrator.html_calibrator import evaluate_and_calibrate_scene_html
        # Row group bị lệch hẳn sang trái (x = 300..900, tâm 600, lệch 360px so với 960)
        off_center_html = """<!DOCTYPE html>
<html>
<body>
  <div id="stage"><svg id="svg" viewBox="0 0 1920 1080">
    <g id="scene-1">
      <g id="s1-cards-row">
        <rect x="300" y="400" width="100" height="80" />
        <rect x="500" y="400" width="100" height="80" />
        <rect x="700" y="400" width="100" height="80" />
      </g>
    </g>
  </svg></div>
  <script>window.__renderAt = function(t, s) {};</script>
</body>
</html>"""
        calibrated, rep = evaluate_and_calibrate_scene_html(off_center_html, duration=5.0, step_starts=[0.0])
        calibs = rep.get("calibrations", [])
        self.assertTrue(any("auto_centered_row_s1-cards-row" in c for c in calibs))
        self.assertIn("translate(410", calibrated)

    def test_vertical_auto_balance(self):
        from lecture_illustrator.html_calibrator import evaluate_and_calibrate_scene_html
        # Nội dung bị dồn sát đáy (Y = 700..850, để lại khoảng trống khổng lồ > 500px bên trên)
        bottom_heavy_html = """<!DOCTYPE html>
<html>
<body>
  <div id="stage"><svg id="svg" viewBox="0 0 1920 1080">
    <g id="header-group" transform="translate(960, 80)">
      <text font-size="56">TIÊU ĐỀ</text>
    </g>
    <g id="scene-2">
      <rect x="600" y="720" width="700" height="120" />
      <text x="960" y="780">Nội dung đáy</text>
    </g>
  </svg></div>
  <script>window.__renderAt = function(t, s) {};</script>
</body>
</html>"""
        calibrated, rep = evaluate_and_calibrate_scene_html(bottom_heavy_html, duration=5.0, step_starts=[0.0])
        calibs = rep.get("calibrations", [])
        self.assertTrue(any("auto_vertical_balance_scene-2" in c for c in calibs))
        self.assertTrue(rep["passed"])
        self.assertNotIn("text_legibility", rep["eval_details"])
        self.assertNotIn("scene_focus", rep["eval_details"])
        self.assertNotIn("flow_dots", rep["eval_details"])

    def test_container_squeeze_and_controls_rejected(self):
        from lecture_illustrator.html_calibrator import evaluate_and_calibrate_scene_html
        # 1. Bọc container thu nhỏ
        container_html = """<!DOCTYPE html>
<html>
<head>
  <style>
    .container { width: 920px; height: 540px; }
  </style>
</head>
<body>
  <div class="container">
    <svg id="svg" viewBox="0 0 1920 1080">
      <rect x="200" y="200" width="340" height="180" />
    </svg>
  </div>
  <script>window.__renderAt = function(t, s) {};</script>
</body>
</html>"""
        _, rep1 = evaluate_and_calibrate_scene_html(container_html, duration=5.0, step_starts=[0.0])
        self.assertFalse(rep1["passed"])
        self.assertFalse(rep1["eval_details"]["layout_occupancy"]["passed"])
        self.assertIn("container thu nhỏ", rep1["eval_details"]["layout_occupancy"]["warning"])

        # 2. Tạo input scrubber / footer player controls cấm
        scrubber_html = """<!DOCTYPE html>
<html>
<body>
  <div id="stage">
    <svg id="svg" viewBox="0 0 1920 1080">
      <rect x="200" y="200" width="340" height="180" />
    </svg>
    <div class="footer-bar">
      <input type="range" class="scrubber">
    </div>
  </div>
  <script>window.__renderAt = function(t, s) {};</script>
</body>
</html>"""
        _, rep2 = evaluate_and_calibrate_scene_html(scrubber_html, duration=5.0, step_starts=[0.0])
        self.assertFalse(rep2["passed"])
        self.assertFalse(rep2["eval_details"]["timing_contract"]["passed"])
        self.assertIn("player controls / scrubber", rep2["eval_details"]["timing_contract"]["message"])

    def test_title_and_subtitle_auto_amplification(self):
        from lecture_illustrator.html_calibrator import evaluate_and_calibrate_scene_html
        small_title_html = """<!DOCTYPE html>
<html>
<body>
  <div id="stage">
    <svg id="svg" viewBox="0 0 1920 1080">
      <g id="header-group">
        <text x="960" y="80" font-size="44">Tiêu đề chính cũ 44px</text>
        <path d="M 600 120 L 1320 120" stroke="red" stroke-width="4"></path>
        <text x="960" y="125" font-size="32">Dòng text phụ cũ quá to 32px</text>
      </g>
      <g id="server-card">
        <rect x="300" y="300" width="400" height="260" />
        <text class="title-text" x="500" y="440" font-size="34">MÁY CHỦ A</text>
        <rect x="390" y="530" width="220" height="44" />
      </g>
    </svg>
  </div>
  <script>window.__renderAt = function(t, s) {};</script>
</body>
</html>"""
        calibrated, rep = evaluate_and_calibrate_scene_html(small_title_html, duration=5.0, step_starts=[0.0])
        # Tiêu đề chính phải được nâng lên >= 58px
        self.assertIn('font-size="58"', calibrated)
        # Text phụ dưới tiêu đề phải được giảm size về 24px
        self.assertIn('font-size="24"', calibrated)
        # Pill đè viền đáy (y=530, h=44 -> bottom 574 > boxBottom 560 - 18) phải được rút lên an toàn
        calibs = rep.get("calibrations", [])
        self.assertTrue(any("retracted_pill" in c for c in calibs) or any("retracted" in c for c in calibs))

    def test_connector_anchor_snap_point_a_to_b(self):
        from lecture_illustrator.html_calibrator import evaluate_and_calibrate_scene_html
        # Sơ đồ phân nhánh: 1 Load Balancer (A) trỏ đến 2 Server (B1 trên, B2 dưới)
        # Các mũi tên ban đầu bị lơ lửng ở khoảng trống giữa 2 server
        branch_html = """<!DOCTYPE html>
<html>
<body>
  <div id="stage"><svg id="svg" viewBox="0 0 1920 1080">
    <g id="scene-2">
      <!-- Box A: Load Balancer (right=500, centerY=550) -->
      <g id="lb" transform="translate(160, 420)">
        <rect width="340" height="260" stroke="#1e40af" />
        <text x="170" y="140">LOAD BALANCER</text>
      </g>
      <!-- Mũi tên đỏ và xanh ban đầu bị hở, trỏ vào khoảng không Y=540 -->
      <path id="path-fail" d="M 510 560 L 760 540" stroke="#b5533c" marker-end="url(#arrow-red)" />
      <path id="path-active" d="M 510 560 L 760 540" stroke="#2e7d52" marker-end="url(#arrow-green)" />
      <!-- Box B1: Máy chủ chính FAIL (left=800, centerY=315) -->
      <g id="server-primary" transform="translate(800, 200)">
        <rect width="380" height="230" stroke="#b5533c" />
        <text x="190" y="75">MÁY CHỦ CHÍNH (FAIL)</text>
      </g>
      <!-- Box B2: Máy chủ dự phòng ACTIVE (left=800, centerY=695) -->
      <g id="server-secondary" transform="translate(800, 580)">
        <rect width="380" height="230" stroke="#2e7d52" />
        <text x="190" y="75">MÁY CHỦ DỰ PHÒNG</text>
      </g>
    </g>
  </svg></div>
  <script>window.__renderAt = function(t, s) {};</script>
</body>
</html>"""
        calibrated, rep = evaluate_and_calibrate_scene_html(branch_html, duration=10.0, step_starts=[0.0])
        calibs = rep.get("calibrations", [])
        # Cả 2 mũi tên đều phải được snap dính vào mép hộp
        self.assertTrue(any("snapped_arrow_path-fail_to_anchor" in c for c in calibs))
        self.assertTrue(any("snapped_arrow_path-active_to_anchor" in c for c in calibs))
        # path-fail phải uốn lên và cắm dính vào Máy Chủ Chính tại Y ≈ 315
        self.assertIn("315", calibrated)
        # path-active phải uốn xuống và cắm dính vào Máy Chủ Dự Phòng tại Y ≈ 695
        self.assertIn("695", calibrated)


if __name__ == "__main__":
    unittest.main()



