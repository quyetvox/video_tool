"""
HTML to MP4 Converter Module.
Provides high-performance HTML/SVG/CSS-to-video conversion with:
- Playwright virtual time seek and screenshot piping to FFmpeg stdin (Zero disk file bloat).
- Hardware-accelerated encoding (VideoToolbox on macOS, NVENC on Windows, libx264 fallback).
- Single-pass audio muxing and ASS subtitle burning.
- Support for file path, URL, or raw HTML content string.
- Command-line interface (CLI) and clean Python API.
"""

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Union

# Ensure root paths
ROOT_DIR = Path(__file__).resolve().parent.parent
PY_ENGINE_DIR = Path(__file__).resolve().parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))
if str(PY_ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(PY_ENGINE_DIR))

from utils.ffmpeg_utils import FFmpegUtils, ensure_system_path
from lecture_illustrator.common import resolve_hardware_config
from lecture_illustrator.scene_renderer import (
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

    try {
        if (typeof fit === 'function') fit();
    } catch(e) {}
    window.dispatchEvent(new Event('resize'));
}
"""


class HTMLToMP4Converter:
    """Core converter class for turning HTML content into high-quality MP4 videos."""

    def __init__(
        self,
        fps: int = 24,
        width: int = 1920,
        height: int = 1080,
        encoder: Optional[str] = None,
        encoder_args: Optional[List[str]] = None,
    ):
        self.fps = fps
        self.width = width
        self.height = height

        if not encoder:
            _, resolved_enc, resolved_args = resolve_hardware_config()
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
            on_progress: Optional callback with signature (percent: float, current_frame: int, total_frames: int).
        
        Returns:
            Resolved Path of the created MP4 file.
        """
        out_path = Path(output_mp4).resolve()
        out_path.parent.mkdir(parents=True, exist_ok=True)

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
                    from narration_voice_generator import (
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

                    # Tự động dò tìm thời lượng nếu chưa xác định
                    if actual_duration <= 0:
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
                            if detected_dur and float(detected_dur) > 0:
                                actual_duration = float(detected_dur)
                        except Exception:
                            pass

                    if actual_duration <= 0:
                        actual_duration = 5.0

                    # Build FFmpeg command with video filter & hardware encoding
                    vf_filters: List[str] = [f"scale={self.width}:{self.height}"]
                    if burn_subtitles and ass_path and Path(ass_path).exists():
                        fonts_dir = ROOT_DIR / "resources" / "fonts"
                        fonts_arg = ""
                        if fonts_dir.exists():
                            safe_fonts_dir = str(fonts_dir).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
                            fonts_arg = f":fontsdir='{safe_fonts_dir}'"
                        safe_ass = str(Path(ass_path).resolve()).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
                        vf_filters.append(f"subtitles='{safe_ass}'{fonts_arg}")

                    vf_combined = ",".join(vf_filters)
                    total_frames = max(1, int(round(actual_duration * self.fps)))

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
                    if not safe_step_starts:
                        safe_step_starts = step_starts or []
                    seek_script = """([t, s]) => {
                        window.__mockTimeMs = t * 1000;
                        window.__currentTime = t;

                        // 1. Scene author / lecture illustrator API
                        if (typeof window.__renderAt === 'function') {
                            try { window.__renderAt(t, s); } catch(e) {}
                        }

                        // 2. Explainer / Video timeline API (e.g. window.VIDEO.seek)
                        if (window.VIDEO && typeof window.VIDEO.seek === 'function') {
                            try { window.VIDEO.seek(t); } catch(e) {}
                        } else if (typeof window.seek === 'function') {
                            try { window.seek(t); } catch(e) {}
                        }

                        // 3. Global render function
                        if (typeof window.render === 'function') {
                            try { window.render(t); } catch(e) {}
                        } else if (typeof render === 'function') {
                            try { render(t); } catch(e) {}
                        }

                        // 4. GSAP Global Timeline seek
                        if (window.gsap && window.gsap.globalTimeline) {
                            try { window.gsap.globalTimeline.seek(t, false); } catch(e) {}
                        }

                        // 5. Web Animations API (CSS @keyframes & transitions)
                        if (document.getAnimations) {
                            try {
                                document.getAnimations().forEach(anim => {
                                    try {
                                        anim.pause();
                                        anim.currentTime = t * 1000;
                                    } catch(_) {}
                                });
                            } catch(e) {}
                        }

                        // 6. SVG SMIL Animations
                        try {
                            const svgs = document.querySelectorAll('svg');
                            for (let i = 0; i < svgs.length; i++) {
                                if (typeof svgs[i].setCurrentTime === 'function') {
                                    svgs[i].setCurrentTime(t);
                                }
                            }
                        } catch(e) {}

                        // 7. Video elements
                        try {
                            const vids = document.querySelectorAll('video');
                            for (let i = 0; i < vids.length; i++) {
                                vids[i].currentTime = t;
                            }
                        } catch(e) {}

                        // 8. Custom frame callbacks registered via requestAnimationFrame
                        if (window.__registeredFrameCallbacks && window.__registeredFrameCallbacks.length > 0) {
                            window.__registeredFrameCallbacks.forEach(cb => {
                                try { cb(t * 1000); } catch(e) {}
                            });
                        }
                    }"""

                    for i in range(total_frames):
                        current_t = i / self.fps
                        page.evaluate(seek_script, [current_t, safe_step_starts])
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
                    browser.close()
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
    on_progress: Optional[Callable[[float, int, int], None]] = None,
) -> Path:
    """Convenient functional API to convert HTML to MP4 video."""
    converter = HTMLToMP4Converter(
        fps=fps,
        width=width,
        height=height,
        encoder=encoder,
        encoder_args=encoder_args,
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
        "--clear-tts-cache", action="store_true", default=False,
        help="Clear all global TTS audio cache before processing"
    )

    args = parser.parse_args()

    if args.clear_tts_cache:
        try:
            from utils.tts_cache_manager import auto_clean_tts_cache
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
            on_progress=progress_callback,
        )
        print(f"\n[HTML->MP4] Done! Generated video at: {out}")
    except Exception as e:
        print(f"\n[HTML->MP4] Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
