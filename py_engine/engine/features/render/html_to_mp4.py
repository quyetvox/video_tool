"""
HTML to MP4 Converter Module.
Provides high-performance HTML/SVG/CSS-to-video conversion with:
- Playwright virtual time seek and screenshot piping to FFmpeg stdin (Zero disk file bloat).
- Hardware-accelerated encoding (VideoToolbox on macOS, NVENC on Windows, libx264 fallback).
- Single-pass audio muxing and ASS subtitle burning.
- Support for file path, URL, or raw HTML content string.
- Command-line interface (CLI) and clean Python API.
"""

try:
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
except ModuleNotFoundError:
    import sys as _sys
    from pathlib import Path as _P
    _sys.path.insert(0, str(next(p.parent for p in _P(__file__).resolve().parents if p.name == "engine")))
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
import argparse
import atexit
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple, Union

# Ensure root paths
ROOT_DIR = _ENGINE_DIR.parent
PY_ENGINE_DIR = _ENGINE_DIR
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))
if str(PY_ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(PY_ENGINE_DIR))

from engine.shared.ffmpeg_utils import FFmpegUtils, ensure_system_path
from engine.features.lecture_illustrator.common import resolve_hardware_config
from engine.features.lecture_illustrator.scene_renderer import (
    _get_playwright,
    _launch,
    BROWSER_RENDER_SHIM,
)

ensure_system_path()

HTML_RENDER_SHIM = r"""
() => {
    window.isExternalControl = true;
    window.__registeredFrameCallbacks = [];

    if (!window.origPerformanceNow) {
        window.origPerformanceNow = performance.now.bind(performance);
    }
    performance.now = () => (window.__mockTimeMs !== undefined ? window.__mockTimeMs : window.origPerformanceNow());

    if (typeof animationFrameId !== 'undefined' && animationFrameId) {
        try { cancelAnimationFrame(animationFrameId); } catch(e) {}
    }

    const origRAF = window.requestAnimationFrame;
    window.requestAnimationFrame = function(cb) {
        if (typeof cb === 'function' && !window.__registeredFrameCallbacks.includes(cb)) {
            window.__registeredFrameCallbacks.push(cb);
        }
        return 1;
    };

    if (window.VIDEO && typeof window.VIDEO.pause === 'function') {
        try { window.VIDEO.pause(); } catch(e) {}
    }

    try {
        if (typeof fit === 'function') fit();
    } catch(e) {}
    window.dispatchEvent(new Event('resize'));
}
"""


def _build_time_warp_knots(
    segments: Optional[List[dict]],
    html_duration: Optional[float] = None,
) -> List[tuple]:
    """
    Build monotonic piecewise-linear knots [(audio_t, html_t), ...] mapping
    actual synthesized audio timestamps [start_sec, end_sec] to the script's
    original HTML cue timestamps [orig_start_sec, orig_end_sec].
    """
    if not segments:
        return []
    has_explicit = any(
        s.get("has_explicit_timestamps")
        or (s.get("orig_start_sec") is not None and s.get("orig_end_sec") is not None)
        for s in segments
    )
    if not has_explicit:
        return []

    knots: List[tuple] = [(0.0, 0.0)]
    for seg in segments:
        a_s = float(seg.get("start_sec", 0.0))
        a_e = float(seg.get("end_sec", a_s))
        o_s = float(seg.get("orig_start_sec", a_s))
        o_e = float(seg.get("orig_end_sec", a_e))

        prev_a, prev_o = knots[-1]
        a_s = max(prev_a, a_s)
        o_s = max(prev_o, o_s)
        if a_s > prev_a or o_s > prev_o:
            knots.append((round(a_s, 4), round(o_s, 4)))

        prev_a, prev_o = knots[-1]
        a_e = max(prev_a, a_e)
        o_e = max(prev_o, o_e)
        if a_e > prev_a or o_e > prev_o:
            knots.append((round(a_e, 4), round(o_e, 4)))

    if html_duration is not None and float(html_duration) > knots[-1][1]:
        tail = float(html_duration) - knots[-1][1]
        knots.append((round(knots[-1][0] + tail, 4), round(float(html_duration), 4)))

    return knots


def _interpolate_html_time(t_audio: float, knots: List[tuple]) -> float:
    """Map actual video/audio timestamp t_audio to HTML animation timestamp t_html."""
    if not knots:
        return round(float(t_audio), 4)
    if t_audio <= knots[0][0]:
        return round(float(knots[0][1]), 4)

    for idx in range(len(knots) - 1):
        a0, o0 = knots[idx]
        a1, o1 = knots[idx + 1]
        if t_audio <= a1:
            if a1 <= a0 + 1e-6:
                return round(float(o1), 4)
            ratio = (t_audio - a0) / (a1 - a0)
            return round(float(o0 + ratio * (o1 - o0)), 4)

    a_last, o_last = knots[-1]
    return round(float(o_last + (t_audio - a_last)), 4)


def _interpolate_audio_time(t_html: float, knots: List[tuple]) -> float:
    """Inverse mapping: convert HTML native timestamp t_html to actual audio/video timestamp t_audio."""
    if not knots:
        return round(float(t_html), 4)
    if t_html <= knots[0][1]:
        return round(float(knots[0][0]), 4)

    for idx in range(len(knots) - 1):
        a0, o0 = knots[idx]
        a1, o1 = knots[idx + 1]
        if t_html <= o1:
            if o1 <= o0 + 1e-6:
                return round(float(a1), 4)
            ratio = (t_html - o0) / (o1 - o0)
            return round(float(a0 + ratio * (a1 - a0)), 4)

    a_last, o_last = knots[-1]
    return round(float(a_last + (t_html - o_last)), 4)


def _resolve_num_workers(
    num_workers: Optional[Union[int, str]],
    default_hw_workers: int = 4,
) -> int:
    """Resolve effective worker count from int, string ('auto', '4'), or None."""
    if num_workers is None:
        return 1
    if isinstance(num_workers, str):
        cleaned = num_workers.strip().lower()
        if not cleaned or cleaned == "auto":
            return max(1, min(int(default_hw_workers or 4), 4))
        try:
            return max(1, min(int(cleaned), 16))
        except ValueError:
            return max(1, min(int(default_hw_workers or 4), 4))
    try:
        return max(1, min(int(num_workers), 16))
    except (ValueError, TypeError):
        return 1


def _plan_scene_ranges(
    total_frames: int,
    fps: int,
    num_workers: int,
    html_scene_starts: Optional[List[float]] = None,
    segments: Optional[List[dict]] = None,
    time_warp_knots: Optional[List[tuple]] = None,
) -> List[Tuple[int, int]]:
    """
    Partition [0, total_frames) into scene-aligned and load-balanced frame ranges
    [(start_frame, end_frame), ...] for parallel multi-worker rendering.
    """
    total_frames = max(1, int(total_frames))
    fps = max(1, int(fps))
    workers = max(1, int(num_workers))

    # Do not split short clips (< 6 seconds) or single-worker jobs
    if workers <= 1 or total_frames < max(2, fps * 6):
        return [(0, total_frames)]

    knots = time_warp_knots or []
    candidate_frames = {0, total_frames}

    # 1. Extract natural scene boundaries from HTML metadata (window.VIDEO.scenes)
    if html_scene_starts:
        for h_t in html_scene_starts:
            try:
                a_t = _interpolate_audio_time(float(h_t), knots)
                f_idx = int(round(a_t * fps))
                if 0 < f_idx < total_frames:
                    candidate_frames.add(f_idx)
            except (ValueError, TypeError):
                continue
    # 2. Or extract scene boundaries from narration script pause gaps (>= 1.2s)
    elif segments and len(segments) > 1:
        for idx in range(1, len(segments)):
            prev_seg = segments[idx - 1]
            curr_seg = segments[idx]
            try:
                a_gap = float(curr_seg.get("start_sec", 0.0)) - float(prev_seg.get("end_sec", 0.0))
                o_gap = float(curr_seg.get("orig_start_sec", curr_seg.get("start_sec", 0.0))) - float(
                    prev_seg.get("orig_end_sec", prev_seg.get("end_sec", 0.0))
                )
                if max(a_gap, o_gap) >= 1.2:
                    f_idx = int(round(float(curr_seg.get("start_sec", 0.0)) * fps))
                    if 0 < f_idx < total_frames:
                        candidate_frames.add(f_idx)
            except (ValueError, TypeError):
                continue

    # Filter boundaries to enforce minimum scene length of 2 seconds
    min_scene_frames = max(1, fps * 2)
    sorted_pts = sorted(candidate_frames)
    filtered_pts = [0]
    for pt in sorted_pts[1:-1]:
        if pt - filtered_pts[-1] >= min_scene_frames and (total_frames - pt) >= min_scene_frames:
            filtered_pts.append(pt)
    filtered_pts.append(total_frames)

    raw_ranges = [(filtered_pts[i], filtered_pts[i + 1]) for i in range(len(filtered_pts) - 1)]

    # 3. Subdivide overly long scenes (or monolithic range) to balance load across workers
    target_chunk_frames = max(fps * 3, math.ceil(total_frames / workers))
    balanced_ranges: List[Tuple[int, int]] = []
    for s_f, e_f in raw_ranges:
        span = e_f - s_f
        if (len(raw_ranges) < workers or span > int(target_chunk_frames * 1.25)) and span >= fps * 4:
            sub_count = max(2, int(round(span / target_chunk_frames)))
            for k in range(sub_count):
                sub_s = s_f + int(round(k * span / sub_count))
                sub_e = e_f if k == sub_count - 1 else (s_f + int(round((k + 1) * span / sub_count)))
                if sub_e > sub_s:
                    balanced_ranges.append((sub_s, sub_e))
        else:
            balanced_ranges.append((s_f, e_f))

    return balanced_ranges or [(0, total_frames)]


SEEK_SCRIPT = """([t, s, ht]) => {
    const htmlT = (typeof ht === 'number') ? ht : t;
    window.__mockTimeMs = htmlT * 1000;
    window.__currentTime = t;

    // 1. Scene author / lecture illustrator API (uses audio-anchored time t & stepStarts s)
    if (typeof window.__renderAt === 'function') {
        try { window.__renderAt(t, s); } catch(e) {}
    }

    // 2. Explainer / Video timeline API (e.g. window.VIDEO.seek uses warped htmlT)
    const hasVideoSeek = Boolean(window.VIDEO && typeof window.VIDEO.seek === 'function');
    if (hasVideoSeek) {
        try {
            if (typeof window.VIDEO.pause === 'function') window.VIDEO.pause();
            window.VIDEO.seek(htmlT);
        } catch(e) {}
    } else if (typeof window.seek === 'function') {
        try { window.seek(htmlT); } catch(e) {}
    }

    // 3. Global render function
    if (!hasVideoSeek) {
        if (typeof window.render === 'function') {
            try { window.render(htmlT); } catch(e) {}
        } else if (typeof render === 'function') {
            try { render(htmlT); } catch(e) {}
        }
    }

    // 4. GSAP Global Timeline seek
    if (window.gsap && window.gsap.globalTimeline) {
        try { window.gsap.globalTimeline.seek(htmlT, false); } catch(e) {}
    }

    // 5. Web Animations API (CSS @keyframes & transitions)
    if (document.getAnimations) {
        try {
            document.getAnimations().forEach(anim => {
                try {
                    anim.pause();
                    anim.currentTime = htmlT * 1000;
                } catch(_) {}
            });
        } catch(e) {}
    }

    // 6. SVG SMIL Animations
    try {
        const svgs = document.querySelectorAll('svg');
        for (let i = 0; i < svgs.length; i++) {
            if (typeof svgs[i].setCurrentTime === 'function') {
                svgs[i].setCurrentTime(htmlT);
            }
        }
    } catch(e) {}

    // 7. Video elements
    try {
        const vids = document.querySelectorAll('video');
        for (let i = 0; i < vids.length; i++) {
            vids[i].currentTime = htmlT;
        }
    } catch(e) {}

    // 8. Custom frame callbacks registered via requestAnimationFrame (skip if window.VIDEO.seek already rendered)
    if (!hasVideoSeek && window.__registeredFrameCallbacks && window.__registeredFrameCallbacks.length > 0) {
        window.__registeredFrameCallbacks.forEach(cb => {
            try { cb(htmlT * 1000); } catch(e) {}
        });
    }
}"""

_html_worker_playwright = None
_html_worker_browser = None


def _get_html_worker_browser():
    """Initialize and reuse a warm Chromium instance per worker process."""
    global _html_worker_playwright, _html_worker_browser
    if _html_worker_browser is None:
        sync_pw = _get_playwright()
        _html_worker_playwright = sync_pw()
        p = _html_worker_playwright.__enter__()
        _html_worker_browser = _launch(p)
    return _html_worker_browser


def _cleanup_html_worker_browser():
    """Clean up the worker's warm Chromium instance upon process exit."""
    global _html_worker_playwright, _html_worker_browser
    if _html_worker_browser is not None:
        try:
            _html_worker_browser.close()
        except Exception:
            pass
        _html_worker_browser = None
    if _html_worker_playwright is not None:
        try:
            _html_worker_playwright.__exit__(None, None, None)
        except Exception:
            pass
        _html_worker_playwright = None


atexit.register(_cleanup_html_worker_browser)


def _build_scene_vf_filter(
    width: int,
    height: int,
    fps: int,
    start_frame: int,
    has_burned_ass: bool,
    ass_path: Optional[Union[str, Path]],
) -> str:
    """Build FFmpeg video filter chain for a scene range, including setpts offset for global ASS burn."""
    vf_filters: List[str] = [f"scale={width}:{height}"]
    if has_burned_ass and ass_path and Path(ass_path).exists():
        fonts_dir = ROOT_DIR / "resources" / "fonts"
        fonts_arg = ""
        if fonts_dir.exists():
            safe_fonts_dir = str(fonts_dir).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
            fonts_arg = f":fontsdir='{safe_fonts_dir}'"
        safe_ass = str(Path(ass_path).resolve()).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
        if start_frame > 0:
            t_start = start_frame / max(1, fps)
            vf_filters.append(f"setpts=PTS+{t_start:.6f}/TB")
            vf_filters.append(f"subtitles='{safe_ass}'{fonts_arg}")
            vf_filters.append("setpts=PTS-STARTPTS")
        else:
            vf_filters.append(f"subtitles='{safe_ass}'{fonts_arg}")
    return ",".join(vf_filters)


def _render_html_scene_worker(task: Dict[str, Any]) -> Tuple[int, str, int]:
    """
    Top-level picklable worker function for ProcessPoolExecutor.
    Renders frame range [start_frame, end_frame) into a scene MP4 file.
    """
    scene_idx = int(task["scene_idx"])
    start_frame = int(task["start_frame"])
    end_frame = int(task["end_frame"])
    target_uri = str(task["target_uri"])
    out_scene_mp4 = Path(task["out_scene_mp4"])
    width = int(task["width"])
    height = int(task["height"])
    fps = int(task["fps"])
    encoder = str(task["encoder"])
    encoder_args = list(task.get("encoder_args") or [])
    has_burned_ass = bool(task.get("has_burned_ass", False))
    ass_path = task.get("ass_path")
    cap_texts = list(task.get("cap_texts") or [])
    safe_step_starts = list(task.get("safe_step_starts") or [])
    raw_knots = task.get("time_warp_knots") or []
    time_warp_knots = [tuple(k) for k in raw_knots]

    vf_combined = _build_scene_vf_filter(
        width=width,
        height=height,
        fps=fps,
        start_frame=start_frame,
        has_burned_ass=has_burned_ass,
        ass_path=ass_path,
    )

    ff_cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "image2pipe", "-framerate", str(fps),
        "-c:v", "mjpeg", "-i", "-",
        "-vf", vf_combined,
        "-r", str(fps),
        "-c:v", encoder, *encoder_args,
        "-pix_fmt", "yuv420p",
        "-video_track_timescale", "90000",
        str(out_scene_mp4),
    ]

    stderr_file = tempfile.TemporaryFile()
    ff_proc = subprocess.Popen(ff_cmd, stdin=subprocess.PIPE, stderr=stderr_file)
    page = None

    try:
        browser = _get_html_worker_browser()
        page = browser.new_page(viewport={"width": width, "height": height})
        page.goto(target_uri, wait_until="domcontentloaded")
        try:
            page.wait_for_load_state("networkidle", timeout=4000)
        except Exception:
            pass
        try:
            page.evaluate("document.fonts.ready")
        except Exception:
            pass

        try:
            page.evaluate(BROWSER_RENDER_SHIM)
        except Exception:
            pass
        page.evaluate(HTML_RENDER_SHIM)

        if cap_texts:
            try:
                sync_cap_js = (
                    "(() => {"
                    f"const texts = {json.dumps(cap_texts, ensure_ascii=False)};"
                    f"const hideCap = {'true' if has_burned_ass else 'false'};"
                    "if (window.VIDEO && Array.isArray(window.VIDEO.captions)) {"
                    "  for (let i = 0; i < Math.min(window.VIDEO.captions.length, texts.length); i++) {"
                    "    if (Array.isArray(window.VIDEO.captions[i]) && window.VIDEO.captions[i].length >= 3 && texts[i]) {"
                    "      window.VIDEO.captions[i][2] = texts[i];"
                    "    }"
                    "  }"
                    "}"
                    "if (hideCap) {"
                    "  const capEl = document.getElementById('cap');"
                    "  if (capEl) capEl.style.display = 'none';"
                    "}"
                    "})()"
                )
                page.evaluate(sync_cap_js)
            except Exception:
                pass

        for i in range(start_frame, end_frame):
            current_t = i / fps
            html_t = _interpolate_html_time(current_t, time_warp_knots)
            page.evaluate(SEEK_SCRIPT, [current_t, safe_step_starts, html_t])
            frame_bytes = page.screenshot(type="jpeg", quality=90, animations="disabled", caret="hide")
            try:
                ff_proc.stdin.write(frame_bytes)
            except (BrokenPipeError, IOError):
                break
    finally:
        if page is not None:
            try:
                page.close()
            except Exception:
                pass
        if ff_proc and ff_proc.stdin:
            try:
                ff_proc.stdin.close()
            except Exception:
                pass
        if ff_proc:
            ff_proc.wait()
            if ff_proc.returncode != 0:
                err_msg = ""
                if stderr_file:
                    try:
                        stderr_file.seek(0)
                        err_msg = stderr_file.read().decode("utf-8", errors="replace").strip()
                    except Exception:
                        pass
                detail = f": {err_msg}" if err_msg else ""
                stderr_file.close()
                raise RuntimeError(f"Scene {scene_idx} FFmpeg failed with exit code {ff_proc.returncode}{detail}")
        if stderr_file:
            try:
                stderr_file.close()
            except Exception:
                pass

    if not out_scene_mp4.exists() or out_scene_mp4.stat().st_size == 0:
        raise RuntimeError(f"Scene {scene_idx} failed to produce output file: {out_scene_mp4}")

    return scene_idx, str(out_scene_mp4), (end_frame - start_frame)


def _concat_scene_videos_with_audio(
    scene_files: List[Path],
    out_path: Path,
    audio_file_path: Optional[Path],
    temp_dir: Path,
) -> None:
    """Concatenate rendered scene MP4 files via stream copy (-c:v copy) and mux single master audio track."""
    concat_list_path = temp_dir / "concat_scenes.txt"
    with open(concat_list_path, "w", encoding="utf-8") as f:
        for p in scene_files:
            safe_p = str(p.resolve()).replace("\\", "/").replace("'", "'\\''")
            f.write(f"file '{safe_p}'\n")

    ff_cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "concat", "-safe", "0",
        "-i", str(concat_list_path),
    ]
    if audio_file_path and audio_file_path.exists():
        ff_cmd.extend(["-i", str(audio_file_path)])

    ff_cmd.extend(["-c:v", "copy"])

    if audio_file_path and audio_file_path.exists():
        ff_cmd.extend([
            "-map", "0:v:0", "-map", "1:a:0",
            "-c:a", "aac", "-b:a", "192k",
            "-filter:a", "apad",
            "-shortest",
        ])

    ff_cmd.extend(["-movflags", "+faststart", str(out_path)])
    res = subprocess.run(ff_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if res.returncode != 0:
        detail = res.stderr.strip() if res.stderr else ""
        raise RuntimeError(f"FFmpeg scene concat failed with exit code {res.returncode}: {detail}")


class HTMLToMP4Converter:
    """Core converter class for turning HTML content into high-quality MP4 videos."""

    def __init__(
        self,
        fps: int = 24,
        width: int = 1920,
        height: int = 1080,
        encoder: Optional[str] = None,
        encoder_args: Optional[List[str]] = None,
        num_workers: Optional[Union[int, str]] = None,
    ):
        self.fps = fps
        self.width = width
        self.height = height
        self.num_workers = num_workers

        hw_workers, resolved_enc, resolved_args = resolve_hardware_config()
        self._default_hw_workers = hw_workers
        if not encoder:
            self.encoder = resolved_enc
            self.encoder_args = resolved_args
        else:
            self.encoder = encoder
            self.encoder_args = encoder_args or []

    def convert(
        self,
        html_input: Union[str, Path],
        output_mp4: Union[str, Path],
        duration: Optional[float] = None,
        audio_path: Optional[Union[str, Path]] = None,
        ass_path: Optional[Union[str, Path]] = None,
        script_path: Optional[Union[str, Path]] = None,
        voice: Optional[str] = None,
        speed: float = 1.0,
        language: Optional[str] = None,
        secondary_lang: Optional[str] = None,
        burn_subtitles: bool = True,
        font_size: int = 36,
        secondary_font_size: Optional[int] = None,
        step_starts: Optional[List[float]] = None,
        lock_timeline: Optional[bool] = None,
        num_workers: Optional[Union[int, str]] = None,
        on_progress: Optional[Callable[[float, int, int], None]] = None,
    ) -> Path:
        """
        Convert HTML input (file path, raw HTML, or URL) into an MP4 video.
        
        Args:
            html_input: Path to .html file, or raw HTML string, or file:// / http:// URL.
            output_mp4: Target path for the output .mp4 file.
            duration: Video duration in seconds. If None or <= 0, automatically determined
                      from script metadata, HTML metadata, audio duration, or defaults to 5.0s.
            audio_path: Optional path to audio file (.wav, .mp3, .m4a) to mux.
            ass_path: Optional path to .ass subtitle file to burn.
            script_path: Optional path to narration script (.txt) for auto TTS & subtitle sync.
            voice: Voice name for TTS generation (e.g. en-US-JennyNeural, vi-VN-HoaiMyNeural).
            speed: Speech speed factor (default: 1.0).
            step_starts: Optional animation step milestone list for virtual time seek.
            lock_timeline: Optional boolean. If True, strictly enforces timeline slots;
                           if False (Auto mode), audio duration acts as Master Timekeeper.
            num_workers: Optional worker count ('auto' or int) for parallel scene rendering.
            on_progress: Optional callback with signature (percent: float, current_frame: int, total_frames: int).
        
        Returns:
            Resolved Path of the created MP4 file.
        """
        out_path = Path(output_mp4).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)

        effective_workers = _resolve_num_workers(
            num_workers if num_workers is not None else self.num_workers,
            default_hw_workers=self._default_hw_workers,
        )

        # 1. Đồng bộ và tổng hợp âm thanh & phụ đề từ kịch bản thuyết minh (Narration Script)
        actual_duration = float(duration) if (duration is not None and float(duration) > 0) else 0.0
        safe_step_starts = list(step_starts) if step_starts else []
        script_file_path: Optional[Path] = None
        segments = None
        if script_path:
            p_script = Path(script_path).resolve()
            if p_script.exists():
                script_file_path = p_script
                try:
                    import asyncio
                    from engine.features.tts_studio.narration_voice_generator import (
                        import_narration_script,
                        render_narration_audio_track,
                        export_ass_subtitles,
                    )
                    segments = import_narration_script(
                        script_file_path,
                        speed=speed,
                        secondary_lang=secondary_lang,
                    )
                    if segments:
                        has_explicit = any(s.get("has_explicit_timestamps") for s in segments)
                        should_lock = lock_timeline if lock_timeline is not None else (
                            bool(duration is not None and float(duration) > 0) or has_explicit
                        )

                        script_total_dur = max(float(s.get("end_sec", 0.0)) for s in segments)
                        if actual_duration <= 0 and should_lock:
                            actual_duration = script_total_dur

                        # Trích xuất các mốc chuyển động ban đầu
                        if not safe_step_starts:
                            safe_step_starts = [round(float(s.get("start_sec", 0.0)), 2) for s in segments]

                        # Auto-resolve voice according to language if applicable
                        DEFAULT_VOICES_BY_LANG = {
                            "vi": "vi-VN-BanMai",
                            "en": "en-US-JennyNeural",
                            "zh": "zh-CN-XiaoxiaoNeural",
                            "ja": "ja-JP-NanamiNeural",
                            "ko": "ko-KR-SunHiNeural",
                            "fr": "fr-FR-DeniseNeural",
                            "de": "de-DE-KatjaNeural",
                            "es": "es-ES-ElviraNeural",
                        }
                        chosen_voice = voice
                        if language and (not chosen_voice or chosen_voice == "en-US-JennyNeural"):
                            chosen_voice = DEFAULT_VOICES_BY_LANG.get(language.lower(), chosen_voice or "en-US-JennyNeural")
                        if not chosen_voice:
                            chosen_voice = "en-US-JennyNeural"

                        # Tự động tạo audio nếu chưa có file audio chỉ định
                        if not audio_path:
                            out_audio_dir = out_path.parent / f"{out_path.stem}_audio"
                            render_res = asyncio.run(
                                render_narration_audio_track(
                                    segments=segments,
                                    output_dir=out_audio_dir,
                                    voice=chosen_voice,
                                    speed=speed,
                                    lock_timeline=should_lock,
                                )
                            )
                            master_audio = render_res.get("master_audio") or render_res.get("output_audio")
                            if master_audio and Path(master_audio).exists():
                                audio_path = Path(master_audio)
                            if render_res.get("segments"):
                                segments = render_res["segments"]

                        # CẬP NHẬT ĐỒNG BỘ 100%: Mốc chuyển cảnh bám sát 100% audio thực tế
                        safe_step_starts = [round(float(s.get("start_sec", 0.0)), 2) for s in segments]

                        # Cập nhật actual_duration từ audio thực tế
                        if audio_path and Path(audio_path).exists():
                            probed_dur = FFmpegUtils.get_audio_duration(Path(audio_path))
                            if probed_dur > 0.1:
                                if actual_duration <= 0 or not should_lock:
                                    actual_duration = probed_dur

                        # Tự động tạo phụ đề ASS nếu chưa có file phụ đề chỉ định và bật nhúng phụ đề
                        if not ass_path and burn_subtitles:
                            gen_ass = out_path.parent / f"{out_path.stem}.ass"
                            export_ass_subtitles(
                                segments,
                                gen_ass,
                                font_size=font_size,
                                secondary_font_size=secondary_font_size,
                            )
                            ass_path = gen_ass
                except Exception as e:
                    print(f"[HTML->MP4] Cảnh báo: Lỗi tích hợp narration script ({e}), tiếp tục luồng chuẩn.", file=sys.stderr)

        audio_file_path: Optional[Path] = None
        if audio_path:
            p_audio = Path(audio_path).resolve()
            if p_audio.exists() and p_audio.stat().st_size > 100:
                audio_file_path = p_audio
                if actual_duration <= 0:
                    actual_duration = max(0.5, FFmpegUtils.get_audio_duration(p_audio))

        # Resolve HTML source URL or temp file
        temp_html_file: Optional[Path] = None
        html_input_str = str(html_input).strip()

        if html_input_str.startswith("http://") or html_input_str.startswith("https://"):
            target_uri = html_input_str
        elif Path(html_input_str).is_file():
            target_uri = Path(html_input_str).resolve().as_uri()
        elif "<html" in html_input_str.lower() or "<!doctype" in html_input_str.lower() or "<svg" in html_input_str.lower():
            # Raw HTML string -> Write to a temporary file
            tmp = tempfile.NamedTemporaryFile(suffix=".html", delete=False, mode="w", encoding="utf-8")
            tmp.write(html_input_str)
            tmp.close()
            temp_html_file = Path(tmp.name)
            target_uri = temp_html_file.resolve().as_uri()
        else:
            p = Path(html_input_str).resolve()
            if p.exists():
                target_uri = p.as_uri()
            else:
                raise FileNotFoundError(f"Không tìm thấy file HTML hoặc định dạng đầu vào không hợp lệ: {html_input_str}")

        sync_pw = _get_playwright()
        ff_proc = None
        stderr_file = None
        temp_scenes_dir: Optional[Path] = None

        try:
            with sync_pw() as p:
                browser = _launch(p)
                try:
                    page = browser.new_page(viewport={"width": self.width, "height": self.height})
                    page.goto(target_uri, wait_until="domcontentloaded")
                    try:
                        page.wait_for_load_state("networkidle", timeout=4000)
                    except Exception:
                        pass
                    try:
                        page.evaluate("document.fonts.ready")
                    except Exception:
                        pass

                    # Kích hoạt fit() layout và trigger resize event
                    page.evaluate("""() => {
                        try {
                            if (typeof fit === 'function') fit();
                        } catch(e) {}
                        window.dispatchEvent(new Event('resize'));
                    }""")

                    # Tự động dò tìm thời lượng gốc và danh sách mốc scene của HTML
                    html_native_duration: Optional[float] = None
                    html_scene_starts: List[float] = []
                    try:
                        detected_dur = page.evaluate("""() => {
                            if (window.VIDEO && typeof window.VIDEO.duration === 'number' && window.VIDEO.duration > 0) {
                                return window.VIDEO.duration;
                            }
                            if (typeof D === 'number' && D > 0) {
                                return D;
                            }
                            if (typeof duration === 'number' && duration > 0) {
                                return duration;
                            }
                            if (window.__DURATION && window.__DURATION > 0) {
                                return window.__DURATION;
                            }
                            return null;
                        }""")
                        if (
                            isinstance(detected_dur, (int, float))
                            and not isinstance(detected_dur, bool)
                            and float(detected_dur) > 0
                        ):
                            html_native_duration = float(detected_dur)
                            if actual_duration <= 0:
                                actual_duration = html_native_duration
                    except Exception:
                        pass

                    try:
                        raw_scenes = page.evaluate("""() => {
                            if (window.VIDEO && Array.isArray(window.VIDEO.scenes)) {
                                return window.VIDEO.scenes.map(sc => {
                                    if (typeof sc === 'number') return sc;
                                    if (Array.isArray(sc) && typeof sc[0] === 'number') return sc[0];
                                    if (sc && typeof sc === 'object') {
                                        for (const k of ['start', 't', 'time', 's', 'at']) {
                                            if (typeof sc[k] === 'number') return sc[k];
                                        }
                                    }
                                    return null;
                                }).filter(v => typeof v === 'number' && v >= 0);
                            }
                            return [];
                        }""")
                        if isinstance(raw_scenes, list):
                            html_scene_starts = [
                                float(x) for x in raw_scenes
                                if isinstance(x, (int, float)) and not isinstance(x, bool)
                            ]
                    except Exception:
                        pass

                    if actual_duration <= 0:
                        actual_duration = 5.0

                    # Xây dựng bảng ánh xạ nội suy Piecewise-Linear Time-Warp (t_audio -> t_html)
                    time_warp_knots = _build_time_warp_knots(segments, html_native_duration)
                    if time_warp_knots and time_warp_knots[-1][0] > actual_duration:
                        actual_duration = time_warp_knots[-1][0]

                    has_burned_ass = bool(burn_subtitles and ass_path and Path(ass_path).exists())
                    total_frames = max(1, int(round(actual_duration * self.fps)))
                    if not safe_step_starts:
                        safe_step_starts = step_starts or []
                    cap_texts = [str(s.get("text", "")).strip() for s in segments] if segments else []

                    scene_ranges = _plan_scene_ranges(
                        total_frames=total_frames,
                        fps=self.fps,
                        num_workers=effective_workers,
                        html_scene_starts=html_scene_starts,
                        segments=segments,
                        time_warp_knots=time_warp_knots,
                    )

                    # Nhánh A: Render đa luồng theo Scene (Multi-Worker Scene Split + Concat)
                    if len(scene_ranges) > 1 and effective_workers > 1:
                        # Đóng browser thăm dò để giải phóng RAM cho Worker Pool
                        try:
                            browser.close()
                        except Exception:
                            pass
                        browser = None

                        temp_scenes_dir = out_path.parent / f".{out_path.stem}_scenes_tmp_{os.getpid()}"
                        temp_scenes_dir.mkdir(parents=True, exist_ok=True)

                        print(
                            f"[HTML->MP4] Multi-Worker Scene Render: {len(scene_ranges)} scenes, "
                            f"{effective_workers} workers, {total_frames} frames ({actual_duration:.1f}s @ {self.fps}fps)"
                        )

                        worker_tasks: List[Dict[str, Any]] = []
                        for idx, (s_frame, e_frame) in enumerate(scene_ranges):
                            scene_file = temp_scenes_dir / f"scene_{idx:04d}.mp4"
                            worker_tasks.append({
                                "scene_idx": idx,
                                "start_frame": s_frame,
                                "end_frame": e_frame,
                                "target_uri": target_uri,
                                "out_scene_mp4": str(scene_file),
                                "width": self.width,
                                "height": self.height,
                                "fps": self.fps,
                                "encoder": self.encoder,
                                "encoder_args": self.encoder_args,
                                "has_burned_ass": has_burned_ass,
                                "ass_path": str(Path(ass_path).resolve()) if (has_burned_ass and ass_path) else None,
                                "cap_texts": cap_texts,
                                "safe_step_starts": safe_step_starts,
                                "time_warp_knots": time_warp_knots,
                            })

                        rendered_scene_map: Dict[int, Path] = {}
                        completed_frames = 0

                        try:
                            with ProcessPoolExecutor(max_workers=effective_workers) as pool:
                                future_map = {
                                    pool.submit(_render_html_scene_worker, t): t
                                    for t in worker_tasks
                                }
                                for fut in as_completed(future_map):
                                    t_info = future_map[fut]
                                    s_idx, s_path_str, s_frames = fut.result()
                                    rendered_scene_map[s_idx] = Path(s_path_str)
                                    completed_frames += s_frames
                                    if on_progress:
                                        pct = round(min(99.0, (completed_frames / total_frames) * 100), 1)
                                        on_progress(pct, min(completed_frames, total_frames), total_frames)
                        except Exception as pool_err:
                            print(
                                f"\n[HTML->MP4] Cảnh báo: ProcessPool gặp sự cố ({pool_err}), chuyển fallback tuần tự cho các scene còn lại...",
                                file=sys.stderr,
                            )
                            for t in worker_tasks:
                                s_idx = t["scene_idx"]
                                if s_idx in rendered_scene_map and rendered_scene_map[s_idx].exists():
                                    continue
                                s_idx, s_path_str, s_frames = _render_html_scene_worker(t)
                                rendered_scene_map[s_idx] = Path(s_path_str)
                                completed_frames += s_frames
                                if on_progress:
                                    pct = round(min(99.0, (completed_frames / total_frames) * 100), 1)
                                    on_progress(pct, min(completed_frames, total_frames), total_frames)
                        finally:
                            _cleanup_html_worker_browser()

                        ordered_scene_files = [rendered_scene_map[i] for i in range(len(scene_ranges))]
                        _concat_scene_videos_with_audio(
                            scene_files=ordered_scene_files,
                            out_path=out_path,
                            audio_file_path=audio_file_path,
                            temp_dir=temp_scenes_dir,
                        )
                        if on_progress:
                            on_progress(100.0, total_frames, total_frames)
                    else:
                        # Nhánh B: Luồng 1-Pass Trực Tiếp (Single Worker)
                        vf_combined = _build_scene_vf_filter(
                            width=self.width,
                            height=self.height,
                            fps=self.fps,
                            start_frame=0,
                            has_burned_ass=has_burned_ass,
                            ass_path=ass_path,
                        )

                        ff_cmd = [
                            "ffmpeg", "-y", "-loglevel", "error",
                            "-f", "image2pipe", "-framerate", str(self.fps),
                            "-c:v", "mjpeg", "-i", "-",
                        ]

                        if audio_file_path:
                            ff_cmd.extend(["-i", str(audio_file_path)])

                        ff_cmd.extend([
                            "-vf", vf_combined,
                            "-c:v", self.encoder, *self.encoder_args,
                            "-pix_fmt", "yuv420p",
                        ])

                        if audio_file_path:
                            ff_cmd.extend([
                                "-map", "0:v:0", "-map", "1:a:0",
                                "-c:a", "aac", "-b:a", "192k",
                                "-filter:a", "apad",
                                "-shortest",
                            ])

                        ff_cmd.append(str(out_path))

                        stderr_file = tempfile.TemporaryFile()
                        ff_proc = subprocess.Popen(ff_cmd, stdin=subprocess.PIPE, stderr=stderr_file)
                        try:
                            page.evaluate(BROWSER_RENDER_SHIM)
                        except Exception:
                            pass
                        page.evaluate(HTML_RENDER_SHIM)

                        # Đồng bộ caption nội tại của HTML (window.VIDEO.captions / #cap) với kịch bản thuyết minh
                        if cap_texts:
                            try:
                                sync_cap_js = (
                                    "(() => {"
                                    f"const texts = {json.dumps(cap_texts, ensure_ascii=False)};"
                                    f"const hideCap = {'true' if has_burned_ass else 'false'};"
                                    "if (window.VIDEO && Array.isArray(window.VIDEO.captions)) {"
                                    "  for (let i = 0; i < Math.min(window.VIDEO.captions.length, texts.length); i++) {"
                                    "    if (Array.isArray(window.VIDEO.captions[i]) && window.VIDEO.captions[i].length >= 3 && texts[i]) {"
                                    "      window.VIDEO.captions[i][2] = texts[i];"
                                    "    }"
                                    "  }"
                                    "}"
                                    "if (hideCap) {"
                                    "  const capEl = document.getElementById('cap');"
                                    "  if (capEl) capEl.style.display = 'none';"
                                    "}"
                                    "})()"
                                )
                                page.evaluate(sync_cap_js)
                            except Exception:
                                pass

                        for i in range(total_frames):
                            current_t = i / self.fps
                            html_t = _interpolate_html_time(current_t, time_warp_knots)
                            page.evaluate(SEEK_SCRIPT, [current_t, safe_step_starts, html_t])
                            frame_bytes = page.screenshot(type="jpeg", quality=90)
                            try:
                                ff_proc.stdin.write(frame_bytes)
                            except (BrokenPipeError, IOError) as pipe_err:
                                print(
                                    f"\n[HTML->MP4] Cảnh báo: FFmpeg đã đóng pipe tại frame {i+1}/{total_frames} ({pipe_err}). Dừng gửi frame.",
                                    file=sys.stderr,
                                )
                                break

                            if on_progress:
                                progress_pct = round(((i + 1) / total_frames) * 100, 1)
                                on_progress(progress_pct, i + 1, total_frames)
                finally:
                    if browser is not None:
                        try:
                            browser.close()
                        except Exception:
                            pass
        finally:
            if ff_proc and ff_proc.stdin:
                try:
                    ff_proc.stdin.close()
                except Exception:
                    pass
            if ff_proc:
                ff_proc.wait()
                if ff_proc.returncode != 0:
                    err_msg = ""
                    if stderr_file:
                        try:
                            stderr_file.seek(0)
                            err_msg = stderr_file.read().decode("utf-8", errors="replace").strip()
                        except Exception:
                            pass
                    detail = f": {err_msg}" if err_msg else ""
                    raise RuntimeError(f"FFmpeg encoding failed with exit code {ff_proc.returncode}{detail}")
            if stderr_file:
                try:
                    stderr_file.close()
                except Exception:
                    pass
            if temp_html_file and temp_html_file.exists():
                try:
                    temp_html_file.unlink()
                except Exception:
                    pass
            if temp_scenes_dir and temp_scenes_dir.exists():
                try:
                    shutil.rmtree(temp_scenes_dir, ignore_errors=True)
                except Exception:
                    pass

            # Auto cleanup intermediate segments directory if generated from script
            if script_path:
                try:
                    temp_segs_dir = out_path.parent / f"{out_path.stem}_audio" / "segments"
                    if temp_segs_dir.exists():
                        shutil.rmtree(temp_segs_dir, ignore_errors=True)
                except Exception:
                    pass

        if not out_path.exists() or out_path.stat().st_size == 0:
            raise RuntimeError(f"Failed to produce valid output video: {out_path}")

        return out_path


def html_to_mp4(
    html_input: Union[str, Path],
    output_mp4: Union[str, Path],
    duration: Optional[float] = None,
    fps: int = 24,
    width: int = 1920,
    height: int = 1080,
    audio_path: Optional[Union[str, Path]] = None,
    ass_path: Optional[Union[str, Path]] = None,
    script_path: Optional[Union[str, Path]] = None,
    voice: Optional[str] = None,
    speed: float = 1.0,
    language: Optional[str] = None,
    secondary_lang: Optional[str] = None,
    burn_subtitles: bool = True,
    font_size: int = 36,
    secondary_font_size: Optional[int] = None,
    step_starts: Optional[List[float]] = None,
    lock_timeline: Optional[bool] = None,
    encoder: Optional[str] = None,
    encoder_args: Optional[List[str]] = None,
    num_workers: Optional[Union[int, str]] = None,
    on_progress: Optional[Callable[[float, int, int], None]] = None,
) -> Path:
    """Convenient functional API to convert HTML to MP4 video."""
    converter = HTMLToMP4Converter(
        fps=fps,
        width=width,
        height=height,
        encoder=encoder,
        encoder_args=encoder_args,
        num_workers=num_workers,
    )
    return converter.convert(
        html_input=html_input,
        output_mp4=output_mp4,
        duration=duration,
        audio_path=audio_path,
        ass_path=ass_path,
        script_path=script_path,
        voice=voice,
        speed=speed,
        language=language,
        secondary_lang=secondary_lang,
        burn_subtitles=burn_subtitles,
        font_size=font_size,
        secondary_font_size=secondary_font_size,
        step_starts=step_starts,
        lock_timeline=lock_timeline,
        num_workers=num_workers,
        on_progress=on_progress,
    )


def main():
    """Command-line interface for HTML to MP4 conversion."""
    parser = argparse.ArgumentParser(
        description="Convert HTML/SVG/CSS animated scenes into high-quality MP4 video."
    )
    parser.add_argument(
        "input_pos", nargs="?", default=None, help="Input HTML file path, raw HTML string, or URL (positional)"
    )
    parser.add_argument(
        "-i", "--input", default=None, help="Input HTML file path, raw HTML string, or URL"
    )
    parser.add_argument(
        "-o", "--output", default=None, help="Output MP4 video file path (default: <input_stem>.mp4)"
    )
    parser.add_argument(
        "-d", "--duration", type=float, default=None, help="Video duration in seconds"
    )
    parser.add_argument(
        "--fps", type=int, default=24, help="Frames per second (default: 24)"
    )
    parser.add_argument(
        "--res", "--resolution", default=None, help="Video resolution in WIDTHxHEIGHT format (e.g. 1920x1080, 1080x1920)"
    )
    parser.add_argument(
        "-w", "--width", type=int, default=1920, help="Video frame width (default: 1920)"
    )
    parser.add_argument(
        "-H", "--height", type=int, default=1080, help="Video frame height (default: 1080)"
    )
    parser.add_argument(
        "-a", "--audio", default=None, help="Audio file path to mux into video"
    )
    parser.add_argument(
        "-s", "--subtitles", "--subtitle", default=None, help="ASS Subtitle file path to burn into video"
    )
    parser.add_argument(
        "--script", default=None, help="Narration script (.txt) to automatically sync audio and subtitles"
    )
    parser.add_argument(
        "--voice", default="en-US-JennyNeural", help="TTS voice model (default: en-US-JennyNeural)"
    )
    parser.add_argument(
        "--speed", type=float, default=1.0, help="TTS speech speed factor (default: 1.0)"
    )
    parser.add_argument(
        "--lang", "--language", default=None, help="TTS spoken language (e.g. en, vi, zh, ja, ko)"
    )
    parser.add_argument(
        "--font-size", type=int, default=36, help="ASS subtitle font size (default: 36)"
    )
    parser.add_argument(
        "--secondary-lang", "--sec-lang", default=None, help="Secondary subtitle language for bilingual rendering (e.g. vi, en)"
    )
    parser.add_argument(
        "--secondary-font-size", "--sec-font-size", type=int, default=None, help="Secondary subtitle font size (default: 75%% of primary)"
    )
    parser.add_argument(
        "--burn-subtitles", dest="burn_subtitles", action="store_true", default=True,
        help="Burn subtitles into output video (default: enabled)"
    )
    parser.add_argument(
        "--no-subtitles", "--no-burn-subtitles", dest="burn_subtitles", action="store_false",
        help="Do not burn subtitles into output video"
    )
    parser.add_argument(
        "--lock-timeline", dest="lock_timeline", action="store_true", default=None,
        help="Lock animation and voice timings strictly to timeline slots"
    )
    parser.add_argument(
        "--no-lock-timeline", dest="lock_timeline", action="store_false",
        help="Disable timeline lock (audio determines timeline dynamically in Auto mode)"
    )
    parser.add_argument(
        "--encoder", default=None, help="FFmpeg video encoder (e.g., h264_videotoolbox, h264_nvenc, libx264)"
    )
    parser.add_argument(
        "--num-workers", "--workers", dest="num_workers", default="auto",
        help="Number of parallel worker processes for scene rendering ('auto' or integer, default: auto)"
    )
    parser.add_argument(
        "--clear-tts-cache", action="store_true", default=False,
        help="Clear all global TTS audio cache before processing"
    )

    args = parser.parse_args()

    if args.clear_tts_cache:
        try:
            from engine.features.tts_studio.tts_cache_manager import auto_clean_tts_cache
            deleted, freed = auto_clean_tts_cache(force_all=True)
            print(f"[HTML->MP4] Đã dọn dẹp bộ nhớ đệm TTS: {deleted} files ({freed / (1024*1024):.1f} MB)")
        except Exception as e:
            print(f"[HTML->MP4] Cảnh báo khi dọn dẹp cache: {e}")

    # Determine input
    target_input = args.input or args.input_pos
    if not target_input:
        parser.error("Vui lòng cung cấp file HTML đầu vào (Ví dụ: python py_engine/html_to_mp4.py input.html -o output.mp4)")

    # Determine output
    target_output = args.output
    if not target_output:
        p_in = Path(target_input)
        target_output = str(p_in.with_suffix(".mp4")) if p_in.suffix else f"{target_input}.mp4"

    # Determine resolution from --res if present
    width = args.width
    height = args.height
    if args.res:
        if "x" in str(args.res).lower():
            parts = str(args.res).lower().split("x")
            try:
                width = int(parts[0].strip())
                height = int(parts[1].strip())
            except ValueError:
                pass

    def progress_callback(pct, curr, total):
        print(f"\r[HTML->MP4] Rendering frame {curr}/{total} ({pct:.1f}%)...", end="", flush=True)

    try:
        out = html_to_mp4(
            html_input=target_input,
            output_mp4=target_output,
            duration=args.duration,
            fps=args.fps,
            width=width,
            height=height,
            audio_path=args.audio,
            ass_path=args.subtitles,
            script_path=args.script,
            voice=args.voice,
            speed=args.speed,
            language=args.lang,
            secondary_lang=args.secondary_lang,
            burn_subtitles=args.burn_subtitles,
            font_size=args.font_size,
            secondary_font_size=args.secondary_font_size,
            lock_timeline=args.lock_timeline,
            encoder=args.encoder,
            num_workers=args.num_workers,
            on_progress=progress_callback,
        )
        print(f"\n[HTML->MP4] Done! Generated video at: {out}")
    except Exception as e:
        print(f"\n[HTML->MP4] Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
