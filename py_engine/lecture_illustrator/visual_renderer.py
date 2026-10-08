"""
Visual Renderer & Scene Compositor for AI Lecture Illustrator.
- Hoàn toàn KHÔNG sử dụng hình ảnh hay âm thanh từ video gốc.
- Tạo cảnh animation / ảnh sinh mới cho từng batch (chụp frame theo thời gian ảo).
- Ghép nối tuần tự các cảnh, lồng tiếng TTS đích và chèn phụ đề ASS song ngữ/đơn ngữ.
- Tăng tốc phần cứng (macOS VideoToolbox / Windows NVENC / CPU).
"""

import hashlib
import json
import os
import platform
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from utils.ffmpeg_utils import FFmpegUtils
from utils.movie_review_tts import MovieReviewTTS

from .common import emit_log, emit_progress, resolve_hardware_config
from .models import LectureProject, LectureProjectConfig, LectureBatch
from .subtitles import generate_lecture_ass
from .scene_renderer import render_scene_video
from .scene_validator import validate_scene


ROOT_DIR = Path(__file__).resolve().parent.parent.parent


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

    raw_data = {
        "template": scene_dict.get("template", ""),
        "title": scene_dict.get("title", ""),
        "steps": scene_dict.get("steps", []),
        "sentences": [{"text": str(s.get("text", "")).strip(), "audio": str(s.get("audio_file", "")).strip()} for s in sents],
        "step_starts": [round(float(st), 2) for st in (getattr(batch, "step_starts", []) or [])],
        "scene_duration": round(float(getattr(batch, "scene_duration", 0.0) or 0.0), 2),
        "asset_path": asset_path,
        "asset_layout": asset_layout,
        "voice_mode": getattr(config, "voice_mode", "tts_dub") if config else "tts_dub",
        "tts_voice": getattr(config, "tts_voice", "ban_mai") if config else "ban_mai",
        "tts_speed": getattr(config, "tts_speed", 1.15) if config else 1.15,
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
    speed = float(config.tts_speed or 1.15)

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
        if not candidate.exists() or candidate.stat().st_size < 300:
            # Fallback sinh trực tiếp nếu thiếu
            MovieReviewTTS.synthesize_single(text=text, out_file=candidate, voice=voice, speed_factor=speed)

        if candidate.exists() and candidate.stat().st_size >= 300:
            audio_inputs.append((candidate, max(0.0, st)))

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
    fps: int = 30,
    encoder: Optional[str] = None,
    encoder_args: Optional[List[str]] = None,
) -> bool:
    """Render video hình ảnh/animation cho một batch đơn lẻ (hỗ trợ cache và hardware encoder)."""
    dur = max(0.5, float(batch.scene_duration or (batch.end_sec - batch.start_sec) or 3.0))

    # 1. Nếu người dùng tự import ảnh/video minh họa thủ công và khóa lại
    if batch.active_asset and batch.active_asset.file_path:
        asset_path = Path(batch.active_asset.file_path)
        if not asset_path.is_absolute():
            asset_path = workspace_dir / asset_path
        if asset_path.exists():
            enc = encoder or "libx264"
            enc_args = encoder_args or ["-crf", "18"]
            # Dựng video tĩnh/zoom nhẹ từ ảnh
            cmd = [
                "ffmpeg", "-y", "-loglevel", "error",
                "-loop", "1", "-i", str(asset_path),
                "-t", f"{dur:.3f}",
                "-vf", f"scale={width}:{height}:force_original_aspect_ratio=decrease,pad={width}:{height}:(ow-iw)/2:(oh-ih)/2,format=yuv420p",
                "-r", str(fps), "-c:v", enc, *enc_args, str(out_mp4)
            ]
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
        )
        return out_mp4.exists()
    except Exception as e:
        emit_log("error", f"Render cảnh {batch.id} thất bại: {e}")
        enc = encoder or "libx264"
        enc_args = encoder_args or ["-pix_fmt", "yuv420p"]
        # Fallback tạo background màu kem đơn giản
        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-f", "lavfi", "-i", f"color=c=0xf4efe3:s={width}x{height}:r={fps}",
            "-t", f"{dur:.3f}",
            "-c:v", enc, *enc_args, str(out_mp4)
        ]
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return res.returncode == 0 and out_mp4.exists()


def render_lecture_video(
    project: LectureProject,
    output_mp4_path: Path,
    workspace_dir: Path,
) -> bool:
    """
    Biên tập & Render video bài giảng hoàn chỉnh:
    - Tạo các cảnh animation mới cho từng batch (chạy song song theo num_workers).
    - Đồng bộ âm thanh TTS theo đúng mốc thời gian của từng câu.
    - Ghép nối toàn bộ các cảnh và chèn phụ đề ASS song ngữ/đơn ngữ.
    - Tuyệt đối không sử dụng khung hình video gốc.
    """
    from concurrent.futures import ThreadPoolExecutor, as_completed

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

    # Đọc cấu hình phần cứng: num_workers và hardware encoder
    workers, hw_encoder, hw_args = resolve_hardware_config()
    emit_log("info", f"Kích hoạt Smart Resume: {workers} workers, encoder={hw_encoder}")
    emit_progress(0.70, f"Kiểm tra cache & render thông minh {total_batches} cảnh ({workers} workers)...")

    # Bản đồ offset câu toàn cục cho từng batch (chống lặp lại âm thanh batch 1)
    sentence_offsets: Dict[str, int] = {}
    curr_offset = 0
    for b in batches:
        sentence_offsets[b.id] = curr_offset
        curr_offset += len(getattr(b, "sentences", []) or [])

    # Hàm dựng 1 cảnh độc lập có kiểm tra MD5 cache fingerprint
    def _render_one_batch(b: LectureBatch) -> Tuple[Optional[Path], str]:
        v_path = scenes_dir / f"{b.id}_video.mp4"
        a_path = scenes_dir / f"{b.id}_audio.wav"
        combined_path = scenes_dir / f"{b.id}_combined.mp4"

        curr_hash = compute_batch_fingerprint(b, cfg)
        old_entry = manifest.get(b.id, {})
        old_hash = old_entry.get("hash") if isinstance(old_entry, dict) else old_entry

        # Cache Hit: Nội dung không đổi VÀ file clip hợp lệ -> tái sử dụng ngay lập tức
        if old_hash == curr_hash and combined_path.exists() and combined_path.stat().st_size > 1000:
            emit_log("info", f"[Smart Resume] Cảnh {b.id} không thay đổi, tái sử dụng clip có sẵn.")
            b.scene_video = str(combined_path)
            return combined_path, curr_hash

        emit_log("info", f"[Smart Resume] Cảnh {b.id} có thay đổi hoặc chưa render, tiến hành dựng lại...")
        # Xóa file cũ của batch này để bảo đảm tính toàn vẹn (giữ lại v_path nếu đã render xong hợp lệ)
        for old_f in (a_path, combined_path):
            if old_f.exists():
                try:
                    old_f.unlink()
                except OSError:
                    pass

        # 1. Render visual (tái sử dụng nếu đã có sẵn và dung lượng hợp lệ)
        if not v_path.exists() or v_path.stat().st_size < 1000:
            render_batch_visual(b, workspace_dir, cfg, v_path, width=vw, height=vh, encoder=hw_encoder, encoder_args=hw_args)

        # 2. Render audio với offset câu toàn cục
        b_offset = sentence_offsets.get(b.id, 0)
        create_batch_audio(b, workspace_dir, cfg, a_path, sentence_offset=b_offset)

        # 3. Ghép video + audio thành combined clip
        if v_path.exists() and a_path.exists():
            cmd = [
                "ffmpeg", "-y", "-loglevel", "error",
                "-i", str(v_path),
                "-i", str(a_path),
                "-c:v", "copy",
                "-c:a", "aac", "-b:a", "192k",
                "-shortest",
                str(combined_path),
            ]
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if combined_path.exists() and combined_path.stat().st_size > 1000:
                b.scene_video = str(combined_path)
                return combined_path, curr_hash
        return None, curr_hash

    # Thực thi song song qua ThreadPoolExecutor
    done_count = 0
    with ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
        futures = {executor.submit(_render_one_batch, b): b for b in batches}
        for fut in as_completed(futures):
            b = futures[fut]
            try:
                res_path, b_hash = fut.result()
                if res_path and res_path.exists():
                    manifest[b.id] = {
                        "hash": b_hash,
                        "updated_at": time.time(),
                    }
            except Exception as e:
                emit_log("warn", f"Lỗi dựng cảnh {b.id}: {e}")
            done_count += 1
            pct = 0.70 + 0.18 * (done_count / max(1, total_batches))
            emit_progress(pct, f"Đã hoàn thành {done_count}/{total_batches} cảnh...")

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
    emit_progress(0.90, "Đang ghép nối toàn bộ các cảnh bài giảng...")
    concat_list_file = workspace_dir / "concat_scenes.txt"
    with open(concat_list_file, "w", encoding="utf-8") as f:
        for p in batch_clip_paths:
            # Escape đường dẫn an toàn cho concat demuxer
            safe_p = str(p.resolve()).replace("\\", "/")
            f.write(f"file '{safe_p}'\n")

    raw_concat_mp4 = workspace_dir / "raw_illustrated_concat.mp4"
    cmd_concat = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "concat", "-safe", "0",
        "-i", str(concat_list_file),
        "-c", "copy",
        str(raw_concat_mp4)
    ]
    res_concat = subprocess.run(cmd_concat, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if res_concat.returncode != 0 or not raw_concat_mp4.exists():
        emit_log("error", "Ghép nối concat các cảnh thất bại!")
        return False

    # 3. Chèn phụ đề ASS và xuất final video
    emit_progress(0.94, "Đang áp dụng phụ đề bài giảng ASS và tối ưu encode...")
    filter_complex_steps = []
    current_stream = "[0:v]"

    if cfg.burn_subtitles:
        ass_path = workspace_dir / "lecture_subtitles.ass"
        generate_lecture_ass(batches, ass_path, cfg, video_width=vw, video_height=vh)

        fonts_dir = ROOT_DIR / "resources" / "fonts"
        fonts_arg = ""
        if fonts_dir.exists():
            safe_fonts_dir = str(fonts_dir).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
            fonts_arg = f":fontsdir='{safe_fonts_dir}'"

        escaped_ass = str(ass_path).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
        filter_complex_steps.append(f"{current_stream}subtitles='{escaped_ass}'{fonts_arg}[v_sub]")
        current_stream = "[v_sub]"
        emit_log("info", "Đã chèn phụ đề bài giảng ASS đồng bộ theo câu.")

    # 4. Chèn watermark logo nếu có
    watermark_enabled = getattr(cfg, "watermark_enabled", False)
    watermark_path = getattr(cfg, "watermark_path", "")
    if watermark_enabled and watermark_path and Path(watermark_path).exists():
        wm_file = str(Path(watermark_path).resolve()).replace("\\", "/").replace(":", "\\:").replace("'", "'\\''")
        filter_complex_steps.append(f"movie='{wm_file}'[wm];{current_stream}[wm]overlay=W-w-20:20[v_wm]")
        current_stream = "[v_wm]"
        emit_log("info", "Đã chèn watermark logo vào video bài giảng.")

    encoder, enc_args = get_hardware_video_encoder()
    bitrate_raw = getattr(cfg, "video_bitrate", "") or ""
    bitrate_arg = []
    if bitrate_raw:
        b_str = bitrate_raw.strip().lower()
        if b_str.endswith("m"):
            try:
                num = float(b_str[:-1])
                bitrate_arg = ["-b:v", f"{int(num * 1000)}k"]
            except Exception:
                bitrate_arg = ["-b:v", bitrate_raw]
        elif b_str.endswith("k"):
            bitrate_arg = ["-b:v", bitrate_raw]
        else:
            bitrate_arg = ["-b:v", f"{bitrate_raw}k"]

    final_cmd = ["ffmpeg", "-y", "-i", str(raw_concat_mp4)]
    if filter_complex_steps:
        final_cmd.extend(["-filter_complex", ";".join(filter_complex_steps), "-map", current_stream, "-map", "0:a"])
    else:
        final_cmd.extend(["-map", "0:v", "-map", "0:a"])

    final_cmd.extend([
        "-c:v", encoder, *enc_args, *bitrate_arg,
        "-pix_fmt", "yuv420p",
        "-c:a", "copy",
        "-movflags", "+faststart",
        str(output_mp4_path)
    ])

    emit_log("info", f"Chạy render video cuối cùng bằng encoder {encoder}...")
    res_final = subprocess.run(final_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
    if res_final.returncode != 0:
        emit_log("error", f"Lỗi render video cuối cùng:\n{res_final.stderr[-400:]}")
        return False

    emit_progress(1.0, "Đã xuất video bài giảng hoàn chỉnh thành công!")
    emit_log("info", f"Video xuất thành công tại: {output_mp4_path}")
    return True
