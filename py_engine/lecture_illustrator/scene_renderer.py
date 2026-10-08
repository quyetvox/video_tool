"""Render một cảnh minh họa HTML thành mp4: chụp frame theo thời gian ảo (seek t) rồi pipe vào FFmpeg."""
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

TEMPLATES_DIR = Path(__file__).parent / "templates"
STAGE_W, STAGE_H = 1920, 1080


def _launch(p):
    """Dùng Chrome/Edge có sẵn trên máy (macOS + Windows), hoặc Chromium mặc định."""
    last_err = None
    for channel in ("chrome", "msedge", None):
        try:
            if channel:
                return p.chromium.launch(channel=channel)
            return p.chromium.launch()
        except Exception as e:  # noqa: BLE001
            last_err = e
    raise RuntimeError(
        f"Không thể khởi động trình duyệt để render cảnh minh họa: {last_err}"
    )


def _get_playwright():
    """Lazy import playwright và tự động bootstrap nếu thiếu."""
    try:
        from playwright.sync_api import sync_playwright
        return sync_playwright
    except ImportError:
        try:
            from utils.pkg_bootstrap import ensure_package
            if ensure_package("playwright", "playwright>=1.40.0"):
                from playwright.sync_api import sync_playwright
                return sync_playwright
        except Exception:
            pass
    raise RuntimeError(
        "Thiếu thư viện 'playwright'. Vui lòng cài đặt bằng lệnh: pip install playwright"
    )


def render_scene_video(
    scene: Dict[str, Any],
    step_starts: List[float],
    duration: float,
    out_mp4: Path,
    fps: int = 30,
    width: int = 1920,
    height: int = 1080,
    encoder: Optional[str] = None,
    encoder_args: Optional[List[str]] = None,
) -> Path:
    """scene: JSON cảnh (template, title, steps). step_starts[k]: giây câu k bắt đầu trong cảnh."""
    template = TEMPLATES_DIR / f"{scene['template']}.html"
    out_mp4.parent.mkdir(parents=True, exist_ok=True)
    total = max(1, int(round(duration * fps)))

    if not encoder:
        from .common import resolve_hardware_config
        _, enc, enc_args = resolve_hardware_config()
    else:
        enc = encoder
        enc_args = encoder_args or (["-b:v", "1800k", "-maxrate", "2500k", "-allow_sw", "1"] if enc == "h264_videotoolbox" else ["-preset", "fast", "-crf", "23", "-tune", "animation"])

    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", str(fps),
         "-c:v", "mjpeg", "-i", "-", "-vf", f"scale={width}:{height}",
         "-c:v", enc, *enc_args, "-pix_fmt", "yuv420p", str(out_mp4)],
        stdin=subprocess.PIPE,
    )
    sync_pw = _get_playwright()
    try:
        with sync_pw() as p:
            browser = _launch(p)
            page = browser.new_page(viewport={"width": STAGE_W, "height": STAGE_H})
            page.goto(template.as_uri())
            page.evaluate("document.fonts.ready")
            page.evaluate("s => window.__load(s)", scene)
            for i in range(total):
                page.evaluate("([t, s]) => window.__renderAt(t, s)", [i / fps, step_starts])
                ff.stdin.write(page.screenshot(type="jpeg", quality=92))
            browser.close()
    finally:
        ff.stdin.close()
        ff.wait()
    if ff.returncode != 0:
        raise RuntimeError("FFmpeg ghép frame thất bại")
    return out_mp4
