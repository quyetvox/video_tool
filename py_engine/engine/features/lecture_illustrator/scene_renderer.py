"""Render một cảnh minh họa HTML thành mp4: chụp frame theo thời gian ảo (seek t) rồi pipe vào FFmpeg."""
try:
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
except ModuleNotFoundError:
    import sys as _sys
    from pathlib import Path as _P
    _sys.path.insert(0, str(next(p.parent for p in _P(__file__).resolve().parents if p.name == "engine")))
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

STAGE_W, STAGE_H = 1920, 1080


def _launch(p):
    """Dùng Chrome/Edge có sẵn trên máy (macOS + Windows), hoặc Chromium mặc định."""
    args = [
        "--disable-background-timer-throttling",
        "--disable-backgrounding-occluded-windows",
        "--disable-renderer-backgrounding",
        "--disable-gpu-watchdog",
        "--mute-audio",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        "--disable-extensions",
        "--disable-component-extensions-with-background-pages",
    ]
    last_err = None
    for channel in ("chrome", "msedge", None):
        try:
            if channel:
                return p.chromium.launch(channel=channel, args=args)
            return p.chromium.launch(args=args)
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
            from engine.shared.pkg_bootstrap import ensure_package
            if ensure_package("playwright", "playwright>=1.40.0"):
                from playwright.sync_api import sync_playwright
                return sync_playwright
        except Exception:
            pass
    raise RuntimeError(
        "Thiếu thư viện 'playwright'. Vui lòng cài đặt bằng lệnh: pip install playwright"
    )


BROWSER_RENDER_SHIM = r"""
() => {
    // 1. Dập tắt triệt để vòng lặp autoplay ngầm (ngăn ngừa race condition đè frame)
    window.isExternalControl = true;
    if (typeof animationFrameId !== 'undefined' && animationFrameId) {
        try { cancelAnimationFrame(animationFrameId); } catch(e) {}
    }
    window.requestAnimationFrame = () => 0;

    // 2. Hàm xây dựng Smart Proxy cho stepStarts (tương thích đa năng mảng lẫn đối tượng)
    function makeProxy(rawArray, defaultObj) {
        if (!Array.isArray(rawArray) || rawArray.length === 0) {
            return defaultObj || rawArray;
        }
        const defaultKeys = (defaultObj && typeof defaultObj === 'object' && !Array.isArray(defaultObj))
            ? Object.keys(defaultObj) : [];
        const target = [...rawArray];
        defaultKeys.forEach((key, idx) => {
            if (idx < rawArray.length) {
                target[key] = rawArray[idx];
            } else if (typeof defaultObj[key] === 'number') {
                target[key] = defaultObj[key];
            }
        });
        rawArray.forEach((val, idx) => {
            target['idea' + (idx + 1)] = val;
            target['step' + (idx + 1)] = val;
            target['idea_' + (idx + 1)] = val;
            target['step_' + (idx + 1)] = val;
        });
        return new Proxy(target, {
            get(obj, prop) {
                if (prop in obj) return obj[prop];
                if (typeof prop === 'string') {
                    const numMatch = prop.match(/\d+/);
                    if (numMatch) {
                        const idx = parseInt(numMatch[0], 10) - 1;
                        if (idx >= 0 && idx < rawArray.length) return rawArray[idx];
                    }
                    if (defaultObj && typeof defaultObj === 'object' && typeof defaultObj[prop] === 'number') {
                        return defaultObj[prop];
                    }
                    if (prop === 'complete' || prop === 'finish' || prop === 'end') {
                        return rawArray[rawArray.length - 1] || 0;
                    }
                    return rawArray[0] || 0;
                }
                return obj[prop];
            }
        });
    }

    // 3. Bao bọc window.__renderAt với Smart Proxy an toàn
    const origRender = window.__renderAt;
    if (typeof origRender === 'function') {
        const defaultStarts = (typeof STEP_STARTS !== 'undefined' && STEP_STARTS)
            ? STEP_STARTS
            : ((typeof stepStarts !== 'undefined' && stepStarts) ? stepStarts : null);
        window.__renderAt = function(t, stepStarts) {
            let safeStarts = stepStarts;
            if (Array.isArray(stepStarts)) {
                safeStarts = makeProxy(stepStarts, defaultStarts);
            } else if (!stepStarts && defaultStarts) {
                safeStarts = defaultStarts;
            }
            try {
                return origRender(t, safeStarts);
            } catch (err) {
                // Nuốt lỗi không nghiêm trọng để không làm gãy pipeline ghép frame
            }
        };
    }
}
"""


def render_scene_video(
    scene: Dict[str, Any],
    step_starts: List[float],
    duration: float,
    out_mp4: Path,
    fps: int = 24,
    width: int = 1920,
    height: int = 1080,
    encoder: Optional[str] = None,
    encoder_args: Optional[List[str]] = None,
    audio_path: Optional[Path] = None,
    ass_path: Optional[Path] = None,
    browser: Optional[Any] = None,
) -> Path:
    """Render một cảnh minh họa HTML thành mp4 (hỗ trợ tích hợp audio + subtitle trong 1-Pass).
    
    Hỗ trợ:
    - mode == 'authored': nạp trực tiếp scene['html_path'] với viewport (width x height).
    - mode != 'authored' ở tỉ lệ 9:16 (dọc): viewport 1920x1080 chuẩn, FFmpeg letterbox pad màu kem #f4efe3.
    - 16:9 (ngang): viewport 1920x1080 chuẩn, scale trực tiếp.
    - Cấu hình FPS linh hoạt (mặc định 24).
    - Tái sử dụng Browser instance ấm (Warm Browser) nếu được truyền vào.
    - Single-Pass muxing: tự động chèn audio và burn phụ đề ASS nếu được truyền vào.
    """
    html_path_str = scene.get("html_path")
    if html_path_str and Path(html_path_str).exists():
        html_target = Path(html_path_str).resolve()
    else:
        from .scene_author import generate_minimal_native_svg_fallback
        fallback_html = generate_minimal_native_svg_fallback(scene, width=width, height=height)
        fallback_path = out_mp4.parent / f"fallback_{out_mp4.stem}.html"
        fallback_path.write_text(fallback_html, encoding="utf-8")
        html_target = fallback_path.resolve()

    viewport_w, viewport_h = width, height
    vf_filter = f"scale={width}:{height}"

    # Tích hợp phụ đề ASS nếu có
    if ass_path and Path(ass_path).exists():
        fonts_dir = _ENGINE_DIR.parent / "resources" / "fonts"
        fonts_arg = ""
        if fonts_dir.exists():
            safe_fonts_dir = str(fonts_dir).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
            fonts_arg = f":fontsdir='{safe_fonts_dir}'"
        safe_ass = str(Path(ass_path).resolve()).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
        vf_filter = f"{vf_filter},subtitles='{safe_ass}'{fonts_arg}"

    out_mp4.parent.mkdir(parents=True, exist_ok=True)
    total = max(1, int(round(duration * fps)))

    if not encoder:
        from .common import resolve_hardware_config
        _, enc, enc_args = resolve_hardware_config()
    else:
        enc = encoder
        enc_args = encoder_args or (["-b:v", "1800k", "-maxrate", "2500k", "-allow_sw", "1"] if enc == "h264_videotoolbox" else ["-preset", "fast", "-crf", "23", "-tune", "animation"])

    ff_cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "image2pipe", "-framerate", str(fps),
        "-c:v", "mjpeg", "-i", "-",
    ]
    has_audio = bool(audio_path and Path(audio_path).exists() and Path(audio_path).stat().st_size > 100)
    if has_audio:
        ff_cmd.extend(["-i", str(Path(audio_path).resolve())])

    ff_cmd.extend([
        "-vf", vf_filter,
        "-c:v", enc, *enc_args,
        "-pix_fmt", "yuv420p",
    ])

    if has_audio:
        ff_cmd.extend(["-c:a", "aac", "-b:a", "192k", "-shortest"])

    ff_cmd.append(str(out_mp4))

    ff = subprocess.Popen(ff_cmd, stdin=subprocess.PIPE)
    owns_browser = False
    pw_context = None

    try:
        active_browser = browser
        if active_browser is None:
            sync_pw = _get_playwright()
            pw_context = sync_pw()
            p = pw_context.__enter__()
            active_browser = _launch(p)
            owns_browser = True

        page = active_browser.new_page(viewport={"width": viewport_w, "height": viewport_h})
        try:
            page.goto(html_target.as_uri())
            page.evaluate("document.fonts.ready")
            page.evaluate("async s => { if (window.__load) await window.__load(s); }", scene)
            page.evaluate(BROWSER_RENDER_SHIM)
            for i in range(total):
                page.evaluate("([t, s]) => window.__renderAt(t, s)", [i / fps, step_starts])
                ff.stdin.write(page.screenshot(type="jpeg", quality=85, animations="disabled", caret="hide"))
        finally:
            try:
                page.close()
            except Exception:
                pass
    finally:
        if owns_browser and active_browser:
            try:
                active_browser.close()
            except Exception:
                pass
            if pw_context:
                try:
                    pw_context.__exit__(None, None, None)
                except Exception:
                    pass
        ff.stdin.close()
        ff.wait()

    if ff.returncode != 0:
        raise RuntimeError("FFmpeg ghép frame thất bại")
    return out_mp4
