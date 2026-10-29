"""
Visual Renderer & Scene Compositor for AI Lecture Illustrator.
- Hoàn toàn KHÔNG sử dụng hình ảnh hay âm thanh từ video gốc.
- Tạo cảnh animation / ảnh sinh mới cho từng batch (chụp frame theo thời gian ảo).
- Ghép nối tuần tự các cảnh, lồng tiếng TTS đích và chèn phụ đề ASS song ngữ/đơn ngữ.
- Tăng tốc phần cứng (macOS VideoToolbox / Windows NVENC / CPU).
"""

try:
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
except ModuleNotFoundError:
    import sys as _sys
    from pathlib import Path as _P
    _sys.path.insert(0, str(next(p.parent for p in _P(__file__).resolve().parents if p.name == "engine")))
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
import atexit
import hashlib
import json
import os
import platform
import subprocess
import time
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from engine.shared.ffmpeg_utils import FFmpegUtils
from engine.shared.movie_review_tts import MovieReviewTTS

from .common import (
    emit_log,
    emit_progress,
    resolve_hardware_config,
    load_audio_manifest,
    save_audio_manifest,
    compute_sentence_audio_fingerprint,
)
from .models import LectureProject, LectureProjectConfig, LectureBatch
from .subtitles import generate_lecture_ass, generate_batch_ass
from .scene_renderer import render_scene_video, _get_playwright, _launch
from .scene_validator import validate_scene


ROOT_DIR = _ENGINE_DIR.parent


def get_hardware_video_encoder() -> Tuple[str, List[str]]:
    """Xác định encoder tối ưu theo config.yaml và hệ điều hành."""
    _, encoder, enc_args = resolve_hardware_config()
    return encoder, enc_args


def compute_batch_fingerprint(batch: LectureBatch, config: Optional[LectureProjectConfig] = None) -> str:
    """Tính mã băm MD5 chuẩn xác đại diện cho nội dung hiển thị và âm thanh của batch."""
    scene_dict = getattr(batch, "scene", {}) or {}
    sents = getattr(batch, "sentences", []) or []
    asset_path = ""
    asset_layout = ""
    if getattr(batch, "active_asset", None):
        asset_path = getattr(batch.active_asset, "file_path", "") or ""
        asset_layout = getattr(batch.active_asset, "layout", "") or ""

    aspect_ratio = getattr(config, "aspect_ratio", "16:9") if config else "16:9"
    html_content_hash = ""
    if scene_dict.get("mode") == "authored" and scene_dict.get("html_path"):
        try:
            h_path = Path(scene_dict["html_path"])
            if h_path.exists():
                html_content_hash = hashlib.md5(h_path.read_bytes()).hexdigest()
        except Exception:
            pass

    raw_data = {
        "template": scene_dict.get("template", ""),
        "mode": scene_dict.get("mode", "template"),
        "html_path": scene_dict.get("html_path", ""),
        "html_content_hash": html_content_hash,
        "title": scene_dict.get("title", ""),
        "steps": scene_dict.get("steps", []),
        "aspect_ratio": aspect_ratio,
        "sentences": [{"text": str(s.get("text", "")).strip(), "audio": str(s.get("audio_file", "")).strip(), "sec": str(s.get("text_secondary", "")).strip()} for s in sents],
        "step_starts": [round(float(st), 2) for st in (getattr(batch, "step_starts", []) or [])],
        "scene_duration": round(float(getattr(batch, "scene_duration", 0.0) or 0.0), 2),
        "asset_path": asset_path,
        "asset_layout": asset_layout,
        "voice_mode": getattr(config, "voice_mode", "tts_dub") if config else "tts_dub",
        "tts_voice": getattr(config, "tts_voice", "ban_mai") if config else "ban_mai",
        "tts_speed": getattr(config, "tts_speed", 1.15) if config else 1.15,
        "fps": int(getattr(config, "fps", 24) or 24) if config else 24,
        "burn_subtitles": bool(getattr(config, "burn_subtitles", True)) if config else True,
        "font_name": str(getattr(config, "font_name", "Arial") or "Arial") if config else "Arial",
        "font_size": str(getattr(config, "font_size", "26") or "26") if config else "26",
        "font_color": str(getattr(config, "font_color", "&H00FFFFFF") or "&H00FFFFFF") if config else "&H00FFFFFF",
        "outline_color": str(getattr(config, "outline_color", "&H00000000") or "&H00000000") if config else "&H00000000",
        "subtitle_mode": str(getattr(config, "subtitle_mode", "bilingual") or "bilingual") if config else "bilingual",
        "subtitle_secondary_show": bool(getattr(config, "subtitle_secondary_show", True)) if config else True,
        "subtitle_order": str(getattr(config, "subtitle_order", "primary_top") or "primary_top") if config else "primary_top",
        "secondary_scale": float(getattr(config, "secondary_scale", 0.70) or 0.70) if config else 0.70,
        "secondary_font_color": str(getattr(config, "secondary_font_color", "&H00E7E1DC") or "&H00E7E1DC") if config else "&H00E7E1DC",
        "secondary_font_name": str(getattr(config, "secondary_font_name", "") or "") if config else "",
    }
    encoded = json.dumps(raw_data, sort_keys=True, ensure_ascii=False).encode("utf-8")
    return hashlib.md5(encoded).hexdigest()


def create_batch_audio(
    batch: LectureBatch,
    workspace_dir: Path,
    config: LectureProjectConfig,
    out_wav: Path,
    sentence_offset: int = 0,
) -> bool:
    """Tạo track audio chuẩn cho batch dài đúng batch.scene_duration khớp mốc step_starts."""
    dur = max(0.5, float(batch.scene_duration or (batch.end_sec - batch.start_sec) or 3.0))
    sentences = getattr(batch, "sentences", []) or []
    step_starts = getattr(batch, "step_starts", []) or []

    # Nếu không có câu nào, sinh silence audio
    if not sentences:
        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", f"anullsrc=r=44100:cl=stereo",
            "-t", f"{dur:.3f}",
            "-acodec", "pcm_s16le", str(out_wav)
        ]
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return res.returncode == 0 and out_wav.exists()

    tts_dir = workspace_dir / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)
    voice = config.tts_voice or "ban_mai"
    if (getattr(config, "target_lang", "vi") or "").lower().startswith("en"):
        if str(voice).lower().startswith("vi-") or str(voice).lower() in ("ban_mai", "hoai_my", "nam_minh", "vi"):
            voice = "en-US-JennyNeural"
    speed = float(config.tts_speed or 1.15)

    audio_manifest = load_audio_manifest(tts_dir)
    manifest_dirty = False

    audio_inputs: List[Tuple[Path, float]] = []
    for idx, s in enumerate(sentences):
        text = str(s.get("text", "")).strip()
        if not text:
            continue
        st = float(step_starts[idx]) if idx < len(step_starts) else (idx * 2.0)
        
        # Tìm đúng file audio toàn cục của câu này (tránh lặp lại câu của batch 1)
        audio_name = s.get("audio_file")
        if not audio_name:
            if "index" in s:
                audio_name = f"s_{int(s['index']):04d}.mp3"
            else:
                global_idx = sentence_offset + idx
                audio_name = f"s_{global_idx:04d}.mp3"

        candidate = tts_dir / audio_name
        sig_hash = compute_sentence_audio_fingerprint(text, voice, speed)
        cached_entry = audio_manifest.get(audio_name)
        cached_hash = cached_entry.get("hash") if isinstance(cached_entry, dict) else cached_entry
        cached_dur = float(cached_entry.get("duration", 0.0)) if isinstance(cached_entry, dict) else 0.0

        is_valid = (
            candidate.exists()
            and candidate.stat().st_size >= 300
            and cached_hash == sig_hash
        )

        if not is_valid:
            if s.get("skip_tts"):
                cmd = [
                    "ffmpeg", "-y", "-loglevel", "error",
                    "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                    "-t", "2.0", "-q:a", "9", "-acodec", "libmp3lame", str(candidate)
                ]
                subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                audio_manifest[audio_name] = {"hash": sig_hash, "duration": 2.0}
            else:
                # Tái tổng hợp audio với tốc độ và giọng đọc chuẩn theo config
                dur = MovieReviewTTS.synthesize_single(text=text, out_file=candidate, voice=voice, speed_factor=speed)
                audio_manifest[audio_name] = {
                    "hash": sig_hash,
                    "voice": voice,
                    "speed": speed,
                    "duration": round(dur if dur > 0 else 1.5, 3),
                }
            manifest_dirty = True

        if candidate.exists() and candidate.stat().st_size >= 300:
            audio_inputs.append((candidate, max(0.0, st)))

    if manifest_dirty:
        save_audio_manifest(tts_dir, audio_manifest)

    if not audio_inputs:
        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", f"anullsrc=r=44100:cl=stereo",
            "-t", f"{dur:.3f}",
            "-acodec", "pcm_s16le", str(out_wav)
        ]
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return res.returncode == 0 and out_wav.exists()

    inputs = []
    filter_parts = []
    for i, (a_path, st) in enumerate(audio_inputs):
        inputs.extend(["-i", str(a_path)])
        delay_ms = int(round(st * 1000))
        filter_parts.append(f"[{i}:a]adelay={delay_ms}|{delay_ms}[a{i}]")

    mix_in = "".join(f"[a{i}]" for i in range(len(audio_inputs)))
    filter_parts.append(f"{mix_in}amix=inputs={len(audio_inputs)}:dropout_transition=0:normalize=0[mixed]")
    # Cắt hoặc đệm (pad) đúng độ dài batch.scene_duration kèm điều chỉnh voice_volume
    voice_vol = float(getattr(config, "voice_volume", 1.0) or 1.0)
    vol_filter = f",volume={voice_vol:.2f}" if abs(voice_vol - 1.0) > 0.01 else ""
    filter_parts.append(f"[mixed]apad=whole_dur={dur:.3f},atrim=0:{dur:.3f}{vol_filter}[afinal]")

    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        *inputs,
        "-filter_complex", ";".join(filter_parts),
        "-map", "[afinal]",
        "-ar", "44100", "-ac", "2",
        "-acodec", "pcm_s16le", str(out_wav)
    ]
    res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return res.returncode == 0 and out_wav.exists()


def render_batch_visual(
    batch: LectureBatch,
    workspace_dir: Path,
    config: LectureProjectConfig,
    out_mp4: Path,
    width: int = 1920,
    height: int = 1080,
    fps: int = 24,
    encoder: Optional[str] = None,
    encoder_args: Optional[List[str]] = None,
    audio_path: Optional[Path] = None,
    ass_path: Optional[Path] = None,
    browser: Optional[Any] = None,
) -> bool:
    """Render video hình ảnh/animation cho một batch đơn lẻ (hỗ trợ single-pass muxing với audio và subtitle)."""
    dur = max(0.5, float(batch.scene_duration or (batch.end_sec - batch.start_sec) or 3.0))

    # 1. Nếu người dùng tự import ảnh/video minh họa thủ công và khóa lại
    if batch.active_asset and batch.active_asset.file_path:
        asset_path = Path(batch.active_asset.file_path)
        if not asset_path.is_absolute():
            asset_path = workspace_dir / asset_path
        if asset_path.exists():
            enc = encoder or "libx264"
            enc_args = encoder_args or ["-crf", "18"]
            vf = f"scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,format=yuv420p"
            if ass_path and Path(ass_path).exists():
                fonts_dir = _ENGINE_DIR.parent / "resources" / "fonts"
                fonts_arg = ""
                if fonts_dir.exists():
                    safe_fonts_dir = str(fonts_dir).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
                    fonts_arg = f":fontsdir='{safe_fonts_dir}'"
                safe_ass = str(Path(ass_path).resolve()).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
                vf = f"{vf},subtitles='{safe_ass}'{fonts_arg}"

            cmd = [
                "ffmpeg", "-y", "-loglevel", "error",
                "-loop", "1", "-i", str(asset_path),
            ]
            has_audio = bool(audio_path and Path(audio_path).exists() and Path(audio_path).stat().st_size > 100)
            if has_audio:
                cmd.extend(["-i", str(Path(audio_path).resolve())])
            cmd.extend([
                "-t", f"{dur:.3f}",
                "-vf", vf,
                "-r", str(fps), "-c:v", enc, *enc_args,
            ])
            if has_audio:
                cmd.extend(["-c:a", "aac", "-b:a", "192k", "-shortest"])
            cmd.append(str(out_mp4))
            res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return res.returncode == 0 and out_mp4.exists()

    # 2. Render animation HTML qua Chromium (thời gian ảo)
    scene = getattr(batch, "scene", None)
    sents = [s.get("text", "") for s in getattr(batch, "sentences", [])]
    if not scene or not isinstance(scene, dict):
        scene = validate_scene(scene, sents)
    else:
        scene = validate_scene(scene, sents)

    step_starts = getattr(batch, "step_starts", []) or [0.0] * len(sents)

    try:
        render_scene_video(
            scene=scene,
            step_starts=step_starts,
            duration=dur,
            out_mp4=out_mp4,
            fps=fps,
            width=width,
            height=height,
            encoder=encoder,
            encoder_args=encoder_args,
            audio_path=audio_path,
            ass_path=ass_path,
            browser=browser,
        )
        return out_mp4.exists()
    except Exception as e:
        emit_log("error", f"Render cảnh {batch.id} thất bại: {e}")
        enc = encoder or "libx264"
        enc_args = encoder_args or ["-pix_fmt", "yuv420p"]
        vf_fallback = "format=yuv420p"
        if ass_path and Path(ass_path).exists():
            fonts_dir = _ENGINE_DIR.parent / "resources" / "fonts"
            fonts_arg = ""
            if fonts_dir.exists():
                safe_fonts_dir = str(fonts_dir).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
                fonts_arg = f":fontsdir='{safe_fonts_dir}'"
            safe_ass = str(Path(ass_path).resolve()).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
            vf_fallback = f"subtitles='{safe_ass}'{fonts_arg}"

        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", f"color=c=0xf4efe3:s={width}x{height}:r={fps}",
        ]
        has_audio = bool(audio_path and Path(audio_path).exists() and Path(audio_path).stat().st_size > 100)
        if has_audio:
            cmd.extend(["-i", str(Path(audio_path).resolve())])
        cmd.extend([
            "-t", f"{dur:.3f}",
            "-vf", vf_fallback,
            "-c:v", enc, *enc_args,
        ])
        if has_audio:
            cmd.extend(["-c:a", "aac", "-b:a", "192k", "-shortest"])
        cmd.append(str(out_mp4))
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return res.returncode == 0 and out_mp4.exists()


_worker_playwright = None
_worker_browser = None


def _get_worker_browser():
    """Khởi tạo một instance Chromium duy nhất cho worker process và giữ ấm (warm)."""
    global _worker_playwright, _worker_browser
    if _worker_browser is None:
        try:
            sync_pw = _get_playwright()
            _worker_playwright = sync_pw()
            p = _worker_playwright.__enter__()
            _worker_browser = _launch(p)
        except Exception as e:
            emit_log("warn", f"Không thể khởi tạo warm browser cho worker: {e}")
            _worker_browser = None
    return _worker_browser


def _cleanup_worker_browser():
    """Dọn dẹp Chromium khi tiến trình worker kết thúc."""
    global _worker_playwright, _worker_browser
    if _worker_browser is not None:
        try:
            _worker_browser.close()
        except Exception:
            pass
        _worker_browser = None
    if _worker_playwright is not None:
        try:
            _worker_playwright.__exit__(None, None, None)
        except Exception:
            pass
        _worker_playwright = None


atexit.register(_cleanup_worker_browser)


def _render_batch_worker_task(task: Dict[str, Any]) -> Tuple[str, Optional[str], str]:
    """Hàm worker task độc lập, an toàn đa tiến trình cho ProcessPoolExecutor."""
    batch_dict = task["batch"]
    config_dict = task["config"]
    workspace_dir = Path(task["workspace_dir"])
    scenes_dir = Path(task["scenes_dir"])
    sentence_offset = int(task.get("sentence_offset", 0))
    vw = int(task.get("vw", 1920))
    vh = int(task.get("vh", 1080))
    fps = int(task.get("fps", 24))
    hw_encoder = task.get("hw_encoder")
    hw_args = task.get("hw_args", [])
    curr_hash = task["curr_hash"]

    b = LectureBatch.from_dict(batch_dict)
    cfg = LectureProjectConfig.from_dict(config_dict)

    a_path = scenes_dir / f"{b.id}_audio.wav"
    combined_path = scenes_dir / f"{b.id}_combined.mp4"

    # Xóa file cũ của batch này để bảo đảm tính toàn vẹn
    for old_f in (a_path, combined_path, scenes_dir / f"{b.id}_video.mp4", scenes_dir / f"{b.id}.ass"):
        if old_f.exists():
            try:
                old_f.unlink()
            except OSError:
                pass

    # 1. Render audio với offset câu toàn cục
    create_batch_audio(b, workspace_dir, cfg, a_path, sentence_offset=sentence_offset)

    # 2. Sinh phụ đề ASS tương đối cho riêng batch này nếu bật burn_subtitles
    b_ass_path = None
    if getattr(cfg, "burn_subtitles", True):
        b_ass_path = scenes_dir / f"{b.id}.ass"
        generate_batch_ass(b, b_ass_path, cfg, video_width=vw, video_height=vh)

    # 3. Single-Pass: Render visual với warm browser instance
    active_browser = _get_worker_browser()
    render_batch_visual(
        b,
        workspace_dir,
        cfg,
        combined_path,
        width=vw,
        height=vh,
        fps=fps,
        encoder=hw_encoder,
        encoder_args=hw_args,
        audio_path=a_path,
        ass_path=b_ass_path,
        browser=active_browser,
    )

    if combined_path.exists() and combined_path.stat().st_size > 1000:
        return b.id, str(combined_path), curr_hash
    return b.id, None, curr_hash


def render_lecture_video(
    project: LectureProject,
    output_mp4_path: Path,
    workspace_dir: Path,
) -> bool:
    """
    Biên tập & Render video bài giảng hoàn chỉnh:
    - Tạo các cảnh animation mới cho từng batch (chạy song song đa tiến trình theo num_workers).
    - Đồng bộ âm thanh TTS theo đúng mốc thời gian của từng câu.
    - Ghép nối toàn bộ các cảnh và chèn phụ đề ASS song ngữ/đơn ngữ.
    - Tuyệt đối không sử dụng khung hình video gốc.
    """
    vw = int(project.video_width or 1920)
    vh = int(project.video_height or 1080)
    cfg = project.config
    batches = project.batches

    if not batches:
        emit_log("error", "Dự án không có phân đoạn batch nào để render!")
        return False

    scenes_dir = workspace_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = scenes_dir / ".batch_manifest.json"

    # Đọc manifest cache cũ nếu có
    manifest: Dict[str, Any] = {}
    if manifest_path.exists():
        try:
            with open(manifest_path, "r", encoding="utf-8") as f:
                manifest = json.load(f)
        except Exception:
            manifest = {}

    total_batches = len(batches)

    # Đọc cấu hình phần cứng: num_workers và hardware encoder từ project config hoặc config.yaml
    workers, hw_encoder, hw_args = resolve_hardware_config(cfg)
    fps = int(getattr(cfg, "fps", 24) or 24)
    emit_log("info", f"Kích hoạt Multi-Process Render: {workers} workers, FPS={fps}, encoder={hw_encoder}")
    emit_progress(0.70, f"Kiểm tra cache & chuẩn bị dựng {total_batches} cảnh ({workers} workers)...")

    # Bản đồ offset câu toàn cục cho từng batch (chống lặp lại âm thanh batch 1)
    sentence_offsets: Dict[str, int] = {}
    curr_offset = 0
    for b in batches:
        sentence_offsets[b.id] = curr_offset
        curr_offset += len(getattr(b, "sentences", []) or [])

    tasks_to_run: List[Dict[str, Any]] = []

    for b in batches:
        combined_path = scenes_dir / f"{b.id}_combined.mp4"
        curr_hash = compute_batch_fingerprint(b, cfg)
        old_entry = manifest.get(b.id, {})
        old_hash = old_entry.get("hash") if isinstance(old_entry, dict) else old_entry

        # Cache Hit: Nội dung và style không đổi VÀ file clip hợp lệ -> tái sử dụng ngay lập tức
        if old_hash == curr_hash and combined_path.exists() and combined_path.stat().st_size > 1000:
            emit_log("info", f"[Smart Resume] Cảnh {b.id} không thay đổi, tái sử dụng clip có sẵn.")
            b.scene_video = str(combined_path)
            continue

        emit_log("info", f"[Smart Resume] Cảnh {b.id} có thay đổi hoặc chưa render, xếp hàng dựng lại...")
        task_data = {
            "batch": b.to_dict(),
            "config": cfg.to_dict(),
            "workspace_dir": str(workspace_dir),
            "scenes_dir": str(scenes_dir),
            "sentence_offset": sentence_offsets.get(b.id, 0),
            "vw": vw,
            "vh": vh,
            "fps": fps,
            "hw_encoder": hw_encoder,
            "hw_args": hw_args,
            "curr_hash": curr_hash,
        }
        tasks_to_run.append(task_data)

    done_count = total_batches - len(tasks_to_run)
    if tasks_to_run:
        emit_progress(
            0.70 + 0.22 * (done_count / max(1, total_batches)),
            f"Đang render {len(tasks_to_run)} cảnh ({workers} workers, {fps} FPS)..."
        )
        if workers > 1:
            try:
                with ProcessPoolExecutor(max_workers=max(1, workers)) as executor:
                    futures = {executor.submit(_render_batch_worker_task, t): t["batch"]["id"] for t in tasks_to_run}
                    for fut in as_completed(futures):
                        b_id = futures[fut]
                        try:
                            res_id, res_path_str, b_hash = fut.result()
                            if res_path_str and Path(res_path_str).exists():
                                manifest[res_id] = {
                                    "hash": b_hash,
                                    "updated_at": time.time(),
                                }
                        except Exception as e:
                            emit_log("warn", f"Lỗi dựng cảnh {b_id} (ProcessPool): {e}")
                        done_count += 1
                        pct = 0.70 + 0.22 * (done_count / max(1, total_batches))
                        emit_progress(pct, f"Đã hoàn thành {done_count}/{total_batches} cảnh...")
            except Exception as e:
                emit_log("warn", f"ProcessPoolExecutor gặp sự cố ({e}), chuyển fallback tuần tự...")
                for t in tasks_to_run:
                    b_id = t["batch"]["id"]
                    try:
                        res_id, res_path_str, b_hash = _render_batch_worker_task(t)
                        if res_path_str and Path(res_path_str).exists():
                            manifest[res_id] = {"hash": b_hash, "updated_at": time.time()}
                    except Exception as err:
                        emit_log("warn", f"Lỗi dựng cảnh {b_id} (Fallback): {err}")
                    done_count += 1
                    pct = 0.70 + 0.22 * (done_count / max(1, total_batches))
                    emit_progress(pct, f"Đã hoàn thành {done_count}/{total_batches} cảnh...")
        else:
            for t in tasks_to_run:
                b_id = t["batch"]["id"]
                try:
                    res_id, res_path_str, b_hash = _render_batch_worker_task(t)
                    if res_path_str and Path(res_path_str).exists():
                        manifest[res_id] = {"hash": b_hash, "updated_at": time.time()}
                except Exception as err:
                    emit_log("warn", f"Lỗi dựng cảnh {b_id}: {err}")
                done_count += 1
                pct = 0.70 + 0.22 * (done_count / max(1, total_batches))
                emit_progress(pct, f"Đã hoàn thành {done_count}/{total_batches} cảnh...")

        _cleanup_worker_browser()

    # Lưu lại manifest sau khi render xong các cảnh
    try:
        with open(manifest_path, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
    except Exception as e:
        emit_log("warn", f"Không thể lưu .batch_manifest.json: {e}")

    # Thu thập clip theo đúng thứ tự mảng batches ban đầu
    batch_clip_paths: List[Path] = []
    for b in batches:
        c_path = scenes_dir / f"{b.id}_combined.mp4"
        if c_path.exists() and c_path.stat().st_size > 1000:
            batch_clip_paths.append(c_path)
            b.scene_video = str(c_path)

    if not batch_clip_paths:
        emit_log("error", "Không tạo được clip cảnh nào thành công!")
        return False

    # 2. Ghép nối danh sách các clip bằng Concat Demuxer
    emit_progress(0.94, "Đang ghép nối toàn bộ các cảnh bài giảng...")
    concat_list_file = workspace_dir / "concat_scenes.txt"
    with open(concat_list_file, "w", encoding="utf-8") as f:
        for p in batch_clip_paths:
            # Escape đường dẫn an toàn cho concat demuxer
            safe_p = str(p.resolve()).replace("\\", "/")
            f.write(f"file '{safe_p}'\n")

    # Tạo sẵn file phụ đề ASS toàn cục trong workspace để lưu trữ hoặc dùng ngoài
    if getattr(cfg, "burn_subtitles", True):
        ass_path = workspace_dir / "lecture_subtitles.ass"
        generate_lecture_ass(batches, ass_path, cfg, video_width=vw, video_height=vh)

    # 3. Xuất final video: Zero Re-encode Concat (-c copy siêu tốc) hoặc Watermark overlay nếu có
    emit_progress(0.97, "Đang xuất bản video bài giảng hoàn chỉnh...")
    watermark_enabled = getattr(cfg, "watermark_enabled", False)
    watermark_path = getattr(cfg, "watermark_path", "")

    cmd_concat = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "concat", "-safe", "0",
        "-i", str(concat_list_file),
    ]

    if watermark_enabled and watermark_path and Path(watermark_path).exists():
        wm_file = str(Path(watermark_path).resolve()).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
        cmd_concat.extend([
            "-filter_complex", f"movie='{wm_file}'[wm];[0:v][wm]overlay=W-w-20:20[v_wm]",
            "-map", "[v_wm]", "-map", "0:a",
            "-c:v", hw_encoder, *hw_args,
            "-c:a", "copy",
        ])
    else:
        # Zero Re-encode: Stream Copy trực tiếp siêu tốc! (1 - 2 giây)
        cmd_concat.extend([
            "-c", "copy",
        ])

    cmd_concat.extend([
        "-movflags", "+faststart",
        str(output_mp4_path),
    ])

    emit_log("info", "Xuất video bài giảng qua Concat Demuxer Stream Copy...")
    res_final = subprocess.run(cmd_concat, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if res_final.returncode != 0:
        emit_log("error", f"Lỗi xuất video bài giảng:\n{res_final.stderr[-400:]}")
        return False

    emit_progress(1.0, "Đã xuất video bài giảng hoàn chỉnh thành công!")
    emit_log("info", f"Video xuất thành công tại: {output_mp4_path}")
    return True


def render_single_batch_complete(
    batch: LectureBatch,
    workspace_dir: Path,
    config: LectureProjectConfig,
    sentence_offset: int = 0,
    force_rerender: bool = True,
    update_manifest: bool = True,
) -> Tuple[Optional[Path], str]:
    """Render một batch đơn lẻ (audio + visual + ASS + muxing) và cập nhật .batch_manifest.json (nếu update_manifest=True)."""
    scenes_dir = workspace_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = scenes_dir / ".batch_manifest.json"
    manifest = {}
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except Exception:
            manifest = {}

    is_portrait = getattr(config, "aspect_ratio", "16:9") == "9:16"
    vw = 1080 if is_portrait else 1920
    vh = 1920 if is_portrait else 1080

    _, hw_encoder, hw_args = resolve_hardware_config(config)
    a_path = scenes_dir / f"{batch.id}_audio.wav"
    combined_path = scenes_dir / f"{batch.id}_combined.mp4"
    curr_hash = compute_batch_fingerprint(batch, config)

    if not force_rerender:
        old_entry = manifest.get(batch.id, {})
        old_hash = old_entry.get("hash") if isinstance(old_entry, dict) else old_entry
        if old_hash == curr_hash and combined_path.exists() and combined_path.stat().st_size > 1000:
            batch.scene_video = str(combined_path)
            return combined_path, curr_hash

    for old_f in (a_path, combined_path, scenes_dir / f"{batch.id}_video.mp4", scenes_dir / f"{batch.id}.ass"):
        if old_f.exists():
            try:
                old_f.unlink()
            except OSError:
                pass

    create_batch_audio(batch, workspace_dir, config, a_path, sentence_offset=sentence_offset)
    b_ass_path = None
    if getattr(config, "burn_subtitles", True):
        b_ass_path = scenes_dir / f"{batch.id}.ass"
        generate_batch_ass(batch, b_ass_path, config, video_width=vw, video_height=vh)

    render_batch_visual(
        batch,
        workspace_dir,
        config,
        combined_path,
        width=vw,
        height=vh,
        fps=24,
        encoder=hw_encoder,
        encoder_args=hw_args,
        audio_path=a_path,
        ass_path=b_ass_path,
    )

    if combined_path.exists() and combined_path.stat().st_size > 1000:
        batch.scene_video = str(combined_path)
        if update_manifest:
            manifest[batch.id] = {
                "hash": curr_hash,
                "mtime": time.time(),
                "path": str(combined_path),
            }
            try:
                manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
            except Exception:
                pass
        return combined_path, curr_hash
    return None, curr_hash

