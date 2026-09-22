"""
Audio voiceover synthesis and video assembly pipeline for Movie Review engine:
- VoiceoverSynthesizer (TTS synthesis via MovieReviewTTS)
- MovieReviewAssembler (Segment assembly, Audio-Anchor, Concat & 1-Pass Post-Production)
"""

import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

from utils.ffmpeg_utils import FFmpegUtils, ensure_system_path
ensure_system_path()
from utils.movie_review_tts import MovieReviewTTS, normalize_vietnamese_text
from .common import (
    emit_log,
    emit_progress,
    load_project_config,
)
from .subtitles import (
    build_inpaint_filter,
    generate_review_ass_subtitles,
)

ROOT_DIR = Path(__file__).parent.parent.parent.resolve()


class VoiceoverSynthesizer:
    """Sinh giọng đọc TTS đa tầng (EdgeTTS & gTTS) và đo thời lượng vật lý chuẩn xác (Audio-Anchor).
    Được ủy quyền xử lý độc lập qua utils/movie_review_tts.py (Hash Cache MD5, Retry 5 lần, Dual-Engine Fallback).
    """

    VOICE_CONFIG = MovieReviewTTS.VOICE_MAP

    @staticmethod
    def _normalize_text(text: str) -> str:
        """Chuẩn hóa ký tự, số, đơn vị đo lường cho tiếng Việt."""
        return normalize_vietnamese_text(text)

    @staticmethod
    def synthesize_single(
        text: str,
        out_file: Path,
        voice: str = "hoai_my",
        speed_factor: float = 1.15
    ) -> float:
        """Tổng hợp giọng đọc cho 1 câu văn bản kèm fallback chéo và trả về thời lượng thực tế."""
        return MovieReviewTTS.synthesize_single(
            text=text,
            out_file=out_file,
            voice=voice,
            speed_factor=speed_factor,
            log_callback=emit_log
        )

    @staticmethod
    def synthesize_script(
        script_items: List[Dict[str, Any]],
        output_dir: Path,
        voice: str = "hoai_my",
        speed_factor: float = 1.15,
        start_progress: float = 0.0,
        end_progress: float = 0.30
    ) -> List[Dict[str, Any]]:
        """Tổng hợp giọng đọc cho toàn bộ kịch bản phân đoạn Storyboard."""
        return MovieReviewTTS.synthesize_script(
            script_items=script_items,
            output_dir=output_dir,
            voice=voice,
            speed_factor=speed_factor,
            log_callback=emit_log,
            progress_callback=emit_progress,
            start_progress=start_progress,
            end_progress=end_progress
        )


class MovieReviewAssembler:
    """Cắt ghép video thô, điều chỉnh tốc độ khớp Audio-Anchor và xuất video."""

    @staticmethod
    def assemble_segment(
        video_path: Path,
        scenes_to_use: List[Dict[str, Any]],
        audio_duration: float,
        out_segment_video: Path,
        aspect_ratio: str = "16:9",
        temp_dir: Optional[Path] = None,
        out_segment_bg_audio: Optional[Path] = None,
        extract_bg_audio: bool = True,
        enable_breathing_room: bool = True,
        max_breathing_room: float = 1.5,
        target_duration_out: Optional[List[float]] = None
    ) -> Path:
        """Ghép các scene và khớp chuẩn theo audio_duration, hỗ trợ Cinematic Breathing Room."""
        temp_dir = temp_dir or out_segment_video.parent
        clip_paths = []
        clip_audio_paths = []
        total_assigned_dur = sum(
            max(0.5, float(sc.get("end_sec", 0)) - float(sc.get("start_sec", 0)))
            for sc in scenes_to_use
        ) if scenes_to_use else 0.0

        # Cinematic Breathing Room: nếu cảnh phim dài hơn câu thoại, giữ cảnh chạy tiếp 0.5s - 1.5s
        breathing_room = 0.0
        if enable_breathing_room and total_assigned_dur > audio_duration + 0.4:
            breathing_room = min(max_breathing_room, total_assigned_dur - audio_duration)

        target_segment_dur = audio_duration + breathing_room
        if target_duration_out is not None:
            target_duration_out.extend([target_segment_dur, breathing_room])

        needed_extra = max(0.0, target_segment_dur - total_assigned_dur)

        # 1. Cắt từng cảnh nhỏ
        num_scenes = max(1, len(scenes_to_use))
        per_scene_target = target_segment_dur / float(num_scenes)

        for j, sc in enumerate(scenes_to_use):
            s_val = float(sc.get("start_sec", 0))
            e_val = float(sc.get("end_sec", s_val + 2.0))
            dur = max(0.5, e_val - s_val)

            # Auto-Extend trực tiếp từ phim gốc: Đảm bảo thời lượng cảnh luôn >= per_scene_target
            # Triệt tiêu hoàn toàn tình trạng shot ngắn phải loop -stream_loop -1
            if dur < per_scene_target:
                dur = round(per_scene_target + 0.1, 3)

            # Auto-Extend cảnh cuối cùng ở tốc độ 1.0x bình thường để đủ khớp target_segment_dur
            if j == len(scenes_to_use) - 1 and needed_extra > 0:
                dur += needed_extra + 0.5

            clip_file = temp_dir / f"clip_{out_segment_video.stem}_{j:02d}.mp4"

            # Cắt nhanh video
            cmd = [
                "ffmpeg", "-y",
                "-ss", f"{s_val:.3f}",
                "-i", str(video_path),
                "-t", f"{dur:.3f}",
                "-an",
                "-c:v", "libx264", "-preset", "ultrafast",
                "-pix_fmt", "yuv420p",
                str(clip_file)
            ]
            subprocess.run(cmd, capture_output=True)
            if clip_file.exists() and clip_file.stat().st_size > 0:
                clip_paths.append(clip_file)

            # Cắt audio gốc của cảnh nếu cần hòa âm
            if extract_bg_audio and out_segment_bg_audio:
                clip_a_file = temp_dir / f"clip_a_{out_segment_video.stem}_{j:02d}.wav"
                cmd_a = [
                    "ffmpeg", "-y",
                    "-ss", f"{s_val:.3f}",
                    "-i", str(video_path),
                    "-t", f"{dur:.3f}",
                    "-vn",
                    "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2",
                    str(clip_a_file)
                ]
                subprocess.run(cmd_a, capture_output=True)
                if clip_a_file.exists() and clip_a_file.stat().st_size > 0:
                    clip_audio_paths.append(clip_a_file)

        if not clip_paths:
            # Cắt tạm 1 đoạn an toàn từ 0s
            cmd = [
                "ffmpeg", "-y", "-i", str(video_path),
                "-t", f"{target_segment_dur:.3f}", "-an",
                "-c:v", "libx264", "-preset", "ultrafast",
                str(out_segment_video)
            ]
            subprocess.run(cmd, capture_output=True)
            if out_segment_bg_audio:
                cmd_a = [
                    "ffmpeg", "-y", "-i", str(video_path),
                    "-t", f"{target_segment_dur:.3f}", "-vn",
                    "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2",
                    str(out_segment_bg_audio)
                ]
                subprocess.run(cmd_a, capture_output=True)
            return out_segment_video

        # 2. Nối các cảnh nhỏ thành Video_Tho
        raw_video = temp_dir / f"raw_{out_segment_video.stem}.mp4"
        list_txt = None
        if len(clip_paths) == 1:
            raw_video = clip_paths[0]
        else:
            list_txt = temp_dir / f"list_{out_segment_video.stem}.txt"
            list_txt.write_text("\n".join([f"file '{c.resolve()}'" for c in clip_paths]))
            cmd_concat = [
                "ffmpeg", "-y", "-f", "concat", "-safe", "0",
                "-i", str(list_txt),
                "-c", "copy",
                str(raw_video)
            ]
            subprocess.run(cmd_concat, capture_output=True)

        # Nối các audio clip nhỏ thành raw_audio
        raw_audio = None
        list_a_txt = None
        if extract_bg_audio and out_segment_bg_audio and clip_audio_paths:
            raw_audio = temp_dir / f"raw_audio_{out_segment_video.stem}.wav"
            if len(clip_audio_paths) == 1:
                raw_audio = clip_audio_paths[0]
            else:
                list_a_txt = temp_dir / f"list_a_{out_segment_video.stem}.txt"
                list_a_txt.write_text("\n".join([f"file '{c.resolve()}'" for c in clip_audio_paths]))
                cmd_concat_a = [
                    "ffmpeg", "-y", "-f", "concat", "-safe", "0",
                    "-i", str(list_a_txt),
                    "-c:a", "pcm_s16le",
                    str(raw_audio)
                ]
                subprocess.run(cmd_concat_a, capture_output=True)

        # 3. Đo độ dài Video_Tho
        probe = FFmpegUtils.probe(raw_video)
        video_dur = float(probe.get("format", {}).get("duration", target_segment_dur))

        # 4. Áp dụng thuật toán Audio-Anchor (Chống lẹm cảnh, ZERO SLOW-MOTION)
        hw_enc = FFmpegUtils.get_hardware_h264_encoder()

        # Aspect ratio filter:
        if aspect_ratio == "9:16":
            # Split-Layer: Nền mờ 1080x1920 + video gốc sắc nét ở giữa (dùng split=2 tránh lỗi stream reuse)
            vf_base = (
                "split=2[in_bg][in_fg];"
                "[in_bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=20:5[bg];"
                "[in_fg]scale=1080:-2[fg];"
                "[bg][fg]overlay=(W-w)/2:(H-h)/2"
            )
        else:
            # 16:9 ngang 1080p
            vf_base = "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2"

        if video_dur >= target_segment_dur:
            # Trim đuôi chính xác video ở tốc độ 1.0x
            cmd_fix = [
                "ffmpeg", "-y",
                "-i", str(raw_video),
                "-t", f"{target_segment_dur:.3f}",
                "-vf", vf_base,
                "-c:v", hw_enc if hw_enc != "libx264" else "libx264",
                "-preset", "ultrafast",
                "-pix_fmt", "yuv420p",
                str(out_segment_video)
            ]
            # Trim đuôi audio gốc
            if raw_audio and out_segment_bg_audio:
                cmd_fix_a = [
                    "ffmpeg", "-y",
                    "-i", str(raw_audio),
                    "-t", f"{target_segment_dur:.3f}",
                    "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2",
                    str(out_segment_bg_audio)
                ]
                subprocess.run(cmd_fix_a, capture_output=True)
        else:
            # ZERO SLOW-MOTION: Giữ nguyên 100% tốc độ 1.0x bình thường
            # Dùng -stream_loop -1 lặp lại video/audio ở 1.0x thay vì kéo chậm giật cục
            cmd_fix = [
                "ffmpeg", "-y",
                "-stream_loop", "-1",
                "-i", str(raw_video),
                "-t", f"{target_segment_dur:.3f}",
                "-vf", vf_base,
                "-c:v", hw_enc if hw_enc != "libx264" else "libx264",
                "-preset", "ultrafast",
                "-pix_fmt", "yuv420p",
                str(out_segment_video)
            ]
            if raw_audio and out_segment_bg_audio:
                cmd_fix_a = [
                    "ffmpeg", "-y",
                    "-stream_loop", "-1",
                    "-i", str(raw_audio),
                    "-t", f"{target_segment_dur:.3f}",
                    "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2",
                    str(out_segment_bg_audio)
                ]
                subprocess.run(cmd_fix_a, capture_output=True)

        subprocess.run(cmd_fix, capture_output=True)

        # Dọn dẹp clip nhỏ
        for c in clip_paths:
            if c != raw_video:
                c.unlink(missing_ok=True)
        for ca in clip_audio_paths:
            if ca != raw_audio:
                ca.unlink(missing_ok=True)
        if raw_video.exists() and raw_video != out_segment_video:
            raw_video.unlink(missing_ok=True)
        if raw_audio and raw_audio.exists() and raw_audio != out_segment_bg_audio:
            raw_audio.unlink(missing_ok=True)
        if list_txt and list_txt.exists():
            list_txt.unlink(missing_ok=True)
        if list_a_txt and list_a_txt.exists():
            list_a_txt.unlink(missing_ok=True)

        return out_segment_video

    @staticmethod
    def render_full_review(
        video_path: Path,
        script_data: Dict[str, Any],
        workspace_dir: Path,
        output_mp4: Path,
        aspect_ratio: str = "16:9",
        tts_volume: float = 1.0,
        original_audio_volume: float = 0.15,
        bgm_volume: float = 0.20,
        burn_subtitles: bool = True,
        enable_inpaint: bool = True,
        flip_horizontal: bool = False,
        crop_zoom: bool = False,
        mute_movie_audio: bool = False,
        from_step: Optional[str] = None
    ) -> Path:
        """Dựng toàn bộ các segments và ghép lại thành MP4 hoàn thiện."""
        segments = script_data.get("script", [])
        if not segments:
            raise ValueError("Kịch bản không có câu thoại nào.")

        effective_tts = max(0.0, min(2.0, float(tts_volume)))
        effective_orig = 0.0 if mute_movie_audio else max(0.0, min(1.0, float(original_audio_volume)))
        effective_bgm = max(0.0, min(1.0, float(bgm_volume)))

        segments_dir = workspace_dir / "rendered_segments"
        segments_dir.mkdir(parents=True, exist_ok=True)
        audio_dir = workspace_dir / "audio_segments"

        segment_files = []
        total_segs = len(segments)

        skip_assembly = False
        if from_step in ["mr06_subtitle", "mr07_encode"]:
            concat_txt = workspace_dir / "concat_review.txt"
            if concat_txt.is_file():
                lines = [
                    line.strip().replace("file '", "").rstrip("'")
                    for line in concat_txt.read_text().splitlines()
                    if line.strip()
                ]
                if lines and all(Path(f).is_file() and Path(f).stat().st_size > 0 for f in lines):
                    skip_assembly = True
                    segment_files = [Path(f) for f in lines]
                    emit_log("info", f"Tái sử dụng {len(segment_files)} phân đoạn video đã dựng từ rendered_segments...")

        if not skip_assembly:
            emit_log(
                "info",
                f"Bắt đầu cắt ghép {total_segs} phân đoạn theo kịch bản (TTS: {effective_tts*100:.0f}%, Tiếng gốc: {effective_orig*100:.0f}%, BGM: {effective_bgm*100:.0f}%)..."
            )

            for idx, seg in enumerate(segments):
                seg_id = seg.get("id", idx + 1)
                audio_file = seg.get("audio_file")
                audio_path = audio_dir / audio_file if audio_file else None
                audio_dur = float(seg.get("audio_duration", 5.0))
                scenes = seg.get("scenes_to_use", [])

                # Adaptive Voice Speedup: Nếu cảnh ngắn hơn giọng đọc và không kéo dài được, tự động tăng nhẹ tốc độ đọc
                total_assigned_dur = sum(
                    max(0.5, float(sc.get("end_sec", 0)) - float(sc.get("start_sec", 0)))
                    for sc in scenes
                ) if scenes else 0.0

                if total_assigned_dur >= 1.5 and total_assigned_dur < audio_dur - 0.3:
                    ratio = audio_dur / total_assigned_dur
                    if ratio <= 1.28 and audio_path and audio_path.exists():
                        sped_audio = segments_dir / f"sped_tts_{seg_id:03d}.wav"
                        cmd_speed = [
                            "ffmpeg", "-y",
                            "-i", str(audio_path),
                            "-filter:a", f"atempo={ratio:.3f}",
                            "-c:a", "pcm_s16le",
                            str(sped_audio)
                        ]
                        subprocess.run(cmd_speed, capture_output=True)
                        if sped_audio.exists() and sped_audio.stat().st_size > 0:
                            audio_path = sped_audio
                            audio_dur = total_assigned_dur
                            seg["audio_duration"] = audio_dur

                out_v = segments_dir / f"seg_v_{seg_id:03d}.mp4"
                out_bg_a = segments_dir / f"seg_bga_{seg_id:03d}.wav"
                out_final_seg = segments_dir / f"seg_final_{seg_id:03d}.mp4"

                # 1. Cắt ghép hình ảnh và audio nền khớp nhịp (hỗ trợ Cinematic Breathing Room)
                dur_info: List[float] = []
                MovieReviewAssembler.assemble_segment(
                    video_path=video_path,
                    scenes_to_use=scenes,
                    audio_duration=audio_dur,
                    out_segment_video=out_v,
                    aspect_ratio=aspect_ratio,
                    temp_dir=segments_dir,
                    out_segment_bg_audio=out_bg_a,
                    extract_bg_audio=(effective_orig > 0),
                    target_duration_out=dur_info
                )
                actual_seg_dur = dur_info[0] if dur_info else audio_dur
                breathing_room = dur_info[1] if len(dur_info) > 1 else 0.0
                seg["segment_duration"] = actual_seg_dur
                seg["breathing_room"] = breathing_room

                # 2. Ghép audio: Hòa âm Ducking (TTS effective_tts + Movie Audio effective_orig) hoặc chỉ TTS
                has_tts = bool(audio_path and audio_path.exists() and audio_path.stat().st_size > 0 and effective_tts > 0)
                has_orig = bool(effective_orig > 0 and out_bg_a.exists() and out_bg_a.stat().st_size > 0)

                if has_tts and has_orig:
                    # Nếu có breathing room: Nhả ducking (đẩy tiếng phim lên) khi dứt giọng đọc
                    boost_vol = min(1.0, max(0.50, effective_orig * 2.5))
                    if breathing_room > 0.1:
                        filter_str = (
                            f"[1:a]volume={effective_tts:.2f},apad[tts];"
                            f"[2:a]volume=enable='between(t,0,{audio_dur:.3f})':volume={effective_orig:.2f},"
                            f"volume=enable='gte(t,{audio_dur:.3f})':volume={boost_vol:.2f}[bg];"
                            f"[tts][bg]amix=inputs=2:duration=first:dropout_transition=0.3[aout]"
                        )
                    else:
                        filter_str = (
                            f"[1:a]volume={effective_tts:.2f}[tts];"
                            f"[2:a]volume={effective_orig:.2f}[bg];"
                            f"[tts][bg]amix=inputs=2:duration=first:dropout_transition=2[aout]"
                        )

                    cmd_merge = [
                        "ffmpeg", "-y",
                        "-i", str(out_v),
                        "-i", str(audio_path),
                        "-i", str(out_bg_a),
                        "-filter_complex", filter_str,
                        "-map", "0:v",
                        "-map", "[aout]",
                        "-c:v", "copy",
                        "-c:a", "aac",
                        "-b:a", "192k",
                        "-ar", "48000",
                        "-ac", "2",
                        "-t", f"{actual_seg_dur:.3f}",
                        str(out_final_seg)
                    ]
                elif has_tts:
                    # Chỉ có giọng đọc TTS
                    cmd_filter = f"[1:a]volume={effective_tts:.2f}"
                    if breathing_room > 0.1:
                        cmd_filter += ",apad[aout]"
                    else:
                        cmd_filter += "[aout]"
                    cmd_merge = [
                        "ffmpeg", "-y",
                        "-i", str(out_v),
                        "-i", str(audio_path),
                        "-filter_complex", cmd_filter,
                        "-map", "0:v",
                        "-map", "[aout]",
                        "-c:v", "copy",
                        "-c:a", "aac",
                        "-b:a", "192k",
                        "-ar", "48000",
                        "-ac", "2",
                        "-t", f"{actual_seg_dur:.3f}",
                        str(out_final_seg)
                    ]
                elif has_orig:
                    # Chỉ có tiếng phim
                    cmd_merge = [
                        "ffmpeg", "-y",
                        "-i", str(out_v),
                        "-i", str(out_bg_a),
                        "-filter_complex", f"[1:a]volume={effective_orig:.2f}[aout]",
                        "-map", "0:v",
                        "-map", "[aout]",
                        "-c:v", "copy",
                        "-c:a", "aac",
                        "-b:a", "192k",
                        "-ar", "48000",
                        "-ac", "2",
                        "-t", f"{actual_seg_dur:.3f}",
                        str(out_final_seg)
                    ]
                else:
                    # Tạo audio câm nhưng chuẩn hóa AAC stereo 48k để concat không bao giờ bị lỗi
                    cmd_merge = [
                        "ffmpeg", "-y",
                        "-i", str(out_v),
                        "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
                        "-map", "0:v",
                        "-map", "1:a",
                        "-c:v", "copy",
                        "-c:a", "aac",
                        "-b:a", "192k",
                        "-t", f"{actual_seg_dur:.3f}",
                        str(out_final_seg)
                    ]

                subprocess.run(cmd_merge, capture_output=True)
                out_v.unlink(missing_ok=True)
                out_bg_a.unlink(missing_ok=True)

                if out_final_seg.exists() and out_final_seg.stat().st_size > 0:
                    segment_files.append(out_final_seg)
                else:
                    segment_files.append(out_v)

                emit_progress(
                    0.30 + 0.50 * ((idx + 1) / max(1, total_segs)),
                    f"Đang dựng video phân đoạn ({idx+1}/{total_segs})..."
                )

        # 3. Concat toàn bộ segments thành video cuối
        output_mp4.parent.mkdir(parents=True, exist_ok=True)
        concat_txt = workspace_dir / "concat_review.txt"
        concat_txt.write_text("\n".join([f"file '{s.resolve()}'" for s in segment_files]))

        proj_cfg, _ = load_project_config(video_path=video_path, workspace=workspace_dir)
        wm_cfg = FFmpegUtils.validate_watermark_config(proj_cfg, workspace=workspace_dir)
        has_watermark = wm_cfg is not None and bool(wm_cfg.get("enabled"))

        bgm_candidates = [
            workspace_dir / "bgm.mp3",
            workspace_dir / "bgm.wav",
            workspace_dir / "audio_separated" / "music.wav",
            workspace_dir / "music.wav",
        ]
        bgm_file = next((f for f in bgm_candidates if f.is_file() and f.stat().st_size > 0), None)
        has_bgm_track = bgm_file is not None and effective_bgm > 0

        needs_post_filter = burn_subtitles or enable_inpaint or flip_horizontal or crop_zoom or has_watermark or has_bgm_track
        temp_concat = workspace_dir / "temp_concat_review.mp4" if needs_post_filter else output_mp4

        emit_progress(0.82, "Đang nối toàn bộ các phân đoạn video...")
        emit_log("info", "Đang nối toàn bộ video hoàn chỉnh bằng FFmpeg concat demuxer...")
        cmd_final = [
            "ffmpeg", "-y",
            "-f", "concat", "-safe", "0",
            "-i", str(concat_txt),
            "-c", "copy",
            str(temp_concat)
        ]
        subprocess.run(cmd_final, capture_output=True, check=True)

        if needs_post_filter:
            emit_progress(0.88, "Đang áp dụng bộ lọc phụ đề ASS, inpaint, âm thanh và watermark...")
            emit_log("info", "Áp dụng bộ lọc phụ đề ASS, Inpaint, Watermark & Copyright Shield...")
            probe_info = FFmpegUtils.probe(temp_concat)
            v_stream = next((s for s in probe_info.get("streams", []) if s.get("codec_type") == "video"), {})
            vw = int(v_stream.get("width", 1920 if aspect_ratio == "16:9" else 1080))
            vh = int(v_stream.get("height", 1080 if aspect_ratio == "16:9" else 1920))

            inputs = ["-i", str(temp_concat)]
            filter_complex_steps = []
            current_stream = "[0:v]"
            audio_map = ["-map", "0:a?"]
            audio_codec = ["-c:a", "copy"]

            if has_bgm_track and bgm_file:
                inputs.extend(["-stream_loop", "-1", "-i", str(bgm_file)])
                filter_complex_steps.append(
                    f"[1:a]volume={effective_bgm:.2f}[bgm_vol];[0:a][bgm_vol]amix=inputs=2:duration=first:dropout_transition=2[a_out]"
                )
                audio_map = ["-map", "[a_out]"]
                audio_codec = ["-c:a", "aac", "-b:a", "192k"]
                emit_log("info", f"Đã hòa âm nhạc nền BGM ({effective_bgm*100:.0f}%): {bgm_file.name}")

            if enable_inpaint:
                inpaint_filter = build_inpaint_filter(vw, vh, proj_cfg)
                if inpaint_filter:
                    filter_complex_steps.append(f"{current_stream}{inpaint_filter}[v_inpaint]")
                    current_stream = "[v_inpaint]"
                    emit_log("info", "Đã kích hoạt Inpaint làm mờ vùng phụ đề cũ của phim.")

            if flip_horizontal:
                filter_complex_steps.append(f"{current_stream}hflip[v_flip]")
                current_stream = "[v_flip]"
                emit_log("info", "Đã kích hoạt Copyright Shield: Lật gương video (hflip).")

            if crop_zoom:
                filter_complex_steps.append(f"{current_stream}scale=1.03*iw:1.03*ih,crop=iw:ih[v_cropzoom]")
                current_stream = "[v_cropzoom]"
                emit_log("info", "Đã kích hoạt Copyright Shield: Thu phóng 3% (crop zoom).")

            if has_watermark and wm_cfg:
                current_stream, wm_filters = FFmpegUtils.build_watermark_filters(
                    last_stream=current_stream,
                    width=vw,
                    height=vh,
                    watermark_config=wm_cfg,
                    inputs=inputs
                )
                filter_complex_steps.extend(wm_filters)
                emit_log("info", "Đã kích hoạt vẽ Watermark bản quyền lên video.")

            if burn_subtitles:
                ass_file = workspace_dir / "subtitles_review.ass"
                generate_review_ass_subtitles(
                    segments=segments,
                    output_ass_path=ass_file,
                    video_width=vw,
                    video_height=vh,
                    project_config=proj_cfg
                )
                fonts_dir = ROOT_DIR / "resources" / "fonts"
                fonts_arg = f":fontsdir='{fonts_dir}'" if fonts_dir.exists() else ""
                ass_escaped = str(ass_file).replace("\\", "/").replace(":", "\\:")
                filter_complex_steps.append(f"{current_stream}subtitles='{ass_escaped}'{fonts_arg}[v_sub]")
                current_stream = "[v_sub]"
                emit_log("info", f"Đã sinh phụ đề ASS đồng bộ nhịp đọc: {ass_file.name}")

            if filter_complex_steps:
                full_fc = ";".join(filter_complex_steps)
                cmd_filter = [
                    "ffmpeg", "-y",
                    *inputs,
                    "-filter_complex", full_fc,
                    "-map", current_stream,
                    *audio_map,
                    "-c:v", "libx264", "-preset", "veryfast", "-crf", "20",
                    *audio_codec,
                    str(output_mp4)
                ]
                emit_progress(0.94, "Đang xuất video hoàn thiện...")
                try:
                    subprocess.run(cmd_filter, capture_output=True, check=True)
                except subprocess.CalledProcessError as err:
                    err_msg = err.stderr.decode("utf-8", errors="ignore") if err.stderr else str(err)
                    emit_log("error", f"FFmpeg hậu kỳ thất bại (mã {err.returncode}): {err_msg}")
                    raise RuntimeError(f"FFmpeg hậu kỳ thất bại: {err_msg}") from err
                temp_concat.unlink(missing_ok=True)
            else:
                shutil.move(str(temp_concat), str(output_mp4))

        emit_progress(1.0, "Hoàn thành dựng video Review Phim!")
        emit_log("success", f"Xuất video thành công: {output_mp4.resolve()}")
        return output_mp4
