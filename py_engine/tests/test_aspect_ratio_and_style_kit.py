import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.models import (  # noqa: E402
    LectureBatch,
    LectureProject,
    LectureProjectConfig,
)
from lecture_illustrator.visual_renderer import compute_batch_fingerprint  # noqa: E402
from lecture_illustrator.scene_renderer import render_scene_video, _launch  # noqa: E402
from lecture_illustrator.scene_author import PATRICK_HAND_FONT_PATH, generate_minimal_native_svg_fallback  # noqa: E402
from utils.ffmpeg_utils import FFmpegUtils  # noqa: E402


def test_native_assets_and_tokens_exist():
    """Kiểm tra font Patrick Hand tồn tại trong assets/ và fallback sinh mã Native SVG chuẩn màu."""
    assert PATRICK_HAND_FONT_PATH.exists(), "PatrickHand.ttf phải tồn tại trong assets/fonts/"

    dummy_scene = {
        "title": "Kiến Trúc Tối Giản",
        "steps": [{"label": "Bước 1", "keyword": "Core"}],
    }
    fallback_html = generate_minimal_native_svg_fallback(dummy_scene, width=1920, height=1080)
    assert "#f4efe3" in fallback_html
    assert "#26323d" in fallback_html
    assert "#b5533c" in fallback_html
    assert "#8a8372" in fallback_html
    assert "PatrickHand" in fallback_html
    assert "window.__renderAt" in fallback_html
    assert "<svg" in fallback_html


def test_models_aspect_ratio_parity():
    """Kiểm tra LectureProjectConfig và LectureProject hỗ trợ 16:9 và 9:16."""
    cfg_default = LectureProjectConfig()
    assert cfg_default.aspect_ratio == "16:9"

    cfg_portrait = LectureProjectConfig.from_dict({"aspect_ratio": "9:16"})
    assert cfg_portrait.aspect_ratio == "9:16"

    # LectureProject tự động map dimensions theo aspect_ratio khi không truyền width/height
    proj_16_9 = LectureProject.from_dict({"config": {"aspect_ratio": "16:9"}})
    assert proj_16_9.video_width == 1920
    assert proj_16_9.video_height == 1080

    proj_9_16 = LectureProject.from_dict({"config": {"aspect_ratio": "9:16"}})
    assert proj_9_16.video_width == 1080
    assert proj_9_16.video_height == 1920


def test_batch_fingerprint_changes_on_aspect_ratio():
    """Mã băm MD5 của batch phải khác nhau khi chuyển đổi giữa 16:9 và 9:16."""
    batch = LectureBatch(
        id="batch_001",
        start_sec=0.0,
        end_sec=3.0,
        transcript_original="Hello world",
        scene={"template": "bullet_list", "title": "Test Title", "steps": []},
    )

    cfg_16_9 = LectureProjectConfig(aspect_ratio="16:9")
    cfg_9_16 = LectureProjectConfig(aspect_ratio="9:16")

    h1 = compute_batch_fingerprint(batch, cfg_16_9)
    h2 = compute_batch_fingerprint(batch, cfg_9_16)

    assert h1 != h2, "Mã băm MD5 của batch phải thay đổi khi đổi aspect_ratio"


def test_render_scene_16_9_and_9_16_with_mock_or_real():
    """Verify: render template ở 9:16 cho video 1080x1920 không méo (letterbox), 16:9 cho 1920x1080."""
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            # Kiểm tra xem có chromium/chrome không
            try:
                b = _launch(p)
                b.close()
            except Exception:
                pytest.skip("Trình duyệt Chromium/Chrome/Edge chưa sẵn sàng trên máy test.")
    except Exception:
        pytest.skip("Playwright chưa được cài đặt trong môi trường này.")

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        scene = {
            "template": "title_point",
            "title": "Minh Họa Bài Giảng",
            "steps": [{"label": "Khái niệm cốt lõi"}],
        }

        # 1. Render 16:9 (ngang 1920x1080, thời lượng 0.5s để test nhanh)
        out_16_9 = tmp_path / "scene_16_9.mp4"
        render_scene_video(
            scene=scene,
            step_starts=[0.1],
            duration=0.5,
            out_mp4=out_16_9,
            fps=15,
            width=1920,
            height=1080,
        )
        assert out_16_9.exists() and out_16_9.stat().st_size > 1000
        probe_16_9 = FFmpegUtils.probe(out_16_9)
        v_stream_16_9 = next(s for s in probe_16_9["streams"] if s["codec_type"] == "video")
        assert int(v_stream_16_9["width"]) == 1920
        assert int(v_stream_16_9["height"]) == 1080

        # 2. Render 9:16 (dọc 1080x1920 letterbox pad kem, không méo hình)
        out_9_16 = tmp_path / "scene_9_16.mp4"
        render_scene_video(
            scene=scene,
            step_starts=[0.1],
            duration=0.5,
            out_mp4=out_9_16,
            fps=15,
            width=1080,
            height=1920,
        )
        assert out_9_16.exists() and out_9_16.stat().st_size > 1000
        probe_9_16 = FFmpegUtils.probe(out_9_16)
        v_stream_9_16 = next(s for s in probe_9_16["streams"] if s["codec_type"] == "video")
        assert int(v_stream_9_16["width"]) == 1080
        assert int(v_stream_9_16["height"]) == 1920


def test_render_authored_scene_9_16_native():
    """Verify: scene mode == 'authored' nạp trực tiếp file html với viewport 1080x1920."""
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            try:
                b = _launch(p)
                b.close()
            except Exception:
                pytest.skip("Trình duyệt Chromium/Chrome/Edge chưa sẵn sàng trên máy test.")
    except Exception:
        pytest.skip("Playwright chưa được cài đặt trong môi trường này.")

    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        html_file = tmp_path / "test_authored.html"
        html_file.write_text("""<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="background:#f4efe3;margin:0;">
  <h1 style="color:#26323d;text-align:center;padding-top:200px;">Authored 9:16</h1>
  <script>
    window.__load = function(s) {};
    window.__renderAt = function(t, steps) {};
  </script>
</body>
</html>""", encoding="utf-8")

        authored_scene = {
            "mode": "authored",
            "html_path": str(html_file),
            "title": "Authored Scene",
            "steps": [],
        }

        out_authored = tmp_path / "authored_9_16.mp4"
        render_scene_video(
            scene=authored_scene,
            step_starts=[0.1],
            duration=0.5,
            out_mp4=out_authored,
            fps=15,
            width=1080,
            height=1920,
        )
        assert out_authored.exists() and out_authored.stat().st_size > 1000
        probe = FFmpegUtils.probe(out_authored)
        v_stream = next(s for s in probe["streams"] if s["codec_type"] == "video")
        assert int(v_stream["width"]) == 1080
        assert int(v_stream["height"]) == 1920
