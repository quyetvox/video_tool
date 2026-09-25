#!/usr/bin/env python3
"""
Movie Review Orchestrator — Hệ Thống Tự Động Tạo Video Review Phim
CLI Entrypoint, Action Dispatcher & Backward-Compatible Facade.

All core modules are organized under `py_engine/movie_review/`:
- `common`: IPC Emitters, Word Budget & Config Resolvers
- `subtitles`: Speed-Calibrated Splitter, Rhythmic Cues, ASS Subtitles & Inpaint Filter
- `detectors`: TargetedSceneDetector & Keyframe Extraction
- `alignment`: VisualAlignmentEngine & Zero-Duplicate Law
- `generators`: NarrativeBlueprintGenerator & GoldenScriptGenerator
- `assembler`: VoiceoverSynthesizer & MovieReviewAssembler
"""

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT_DIR = Path(__file__).parent.parent.resolve()
ENGINE_DIR = Path(__file__).parent.resolve()
sys.path.insert(0, str(ENGINE_DIR))
sys.path.insert(0, str(ROOT_DIR))

from utils.ffmpeg_utils import FFmpegUtils, ensure_system_path
ensure_system_path()
from utils.movie_review_tts import MovieReviewTTS, normalize_vietnamese_text

# Re-export all symbols from the modular movie_review package for 100% backward compatibility
from movie_review import (
    emit_json,
    emit_log,
    emit_progress,
    safe_ensure_dir,
    calculate_optimal_review_duration,
    calculate_word_budget,
    clean_json_str,
    load_project_config,
    resolve_gemini_config,
    resolve_gemini_api_key,
    split_long_segments_by_speed,
    wrap_subtitle_text,
    split_subtitle_into_rhythmic_cues,
    _color_to_ass,
    generate_review_ass_subtitles,
    build_inpaint_filter,
    TargetedSceneDetector,
    VisualAlignmentEngine,
    NarrativeBlueprintGenerator,
    GoldenScriptGenerator,
    VoiceoverSynthesizer,
    MovieReviewAssembler,
)


class MovieReviewOrchestrator:
    """Bộ điều phối toàn diện cho quy trình Movie Review."""

    def __init__(self, workspace_root: Path):
        self.workspace_root = safe_ensure_dir(workspace_root, fallback_subdir="movie_review")

    def run_stage1_blueprint(
        self,
        video_path: Path,
        genre: str = "linear_action",
        target_duration_sec: Optional[int] = None,
        speed_factor: float = 1.45,
        api_key: Optional[str] = None,
        model_name: Optional[str] = None,
        target_lang: str = "vi",
        review_style: str = "story_review",
        custom_prompt: Optional[str] = None
    ) -> Dict[str, Any]:
        """Chạy Stage 1: Tách audio nhẹ và tạo dàn ý cốt truyện đa chương."""
        probe = FFmpegUtils.probe(video_path)
        video_dur = float(probe.get("format", {}).get("duration", 3600.0))

        gen = NarrativeBlueprintGenerator(
            api_key=api_key,
            model_name=model_name,
            workspace=self.workspace_root,
            video_path=video_path
        )
        audio_preview = self.workspace_root / "audio_low.mp3"
        gen.extract_audio_preview(video_path, audio_preview)

        blueprint = gen.generate_blueprint(
            audio_path=audio_preview,
            genre=genre,
            target_duration_sec=target_duration_sec,
            speed_factor=speed_factor,
            video_duration_sec=video_dur,
            target_lang=target_lang,
            review_style=review_style,
            custom_prompt=custom_prompt
        )

        blueprint_file = self.workspace_root / "blueprint.json"
        blueprint_file.write_text(json.dumps(blueprint, indent=2, ensure_ascii=False))
        emit_json({"type": "blueprint_ready", "data": blueprint})
        return blueprint

    def run_stage2_scenes_and_script(
        self,
        video_path: Path,
        blueprint: Dict[str, Any],
        api_key: Optional[str] = None,
        model_name: Optional[str] = None,
        target_lang: str = "vi",
        audio_path: Optional[Path] = None,
        review_style: str = "story_review",
        skip_scene_detect: bool = False,
        acts_config: Optional[Dict[str, Any]] = None,
        custom_prompt: Optional[str] = None
    ) -> Dict[str, Any]:
        """Chạy Stage 2: Quét cảnh mục tiêu và sinh kịch bản tỷ lệ vàng."""
        keyframes_dir = self.workspace_root / "keyframes"
        scenes_file = self.workspace_root / "scenes_meta.json"

        if skip_scene_detect and scenes_file.is_file():
            emit_log("info", f"Tái sử dụng danh sách cảnh có sẵn từ: {scenes_file.name}")
            scenes = json.loads(scenes_file.read_text())
        else:
            ranges = blueprint.get("blueprint_ranges", [])
            target_dur = int(blueprint.get("target_duration_sec", 360))
            target_shots = max(60, min(300, int(target_dur // 3.5)))

            scenes = TargetedSceneDetector.detect_scenes_for_ranges(
                video_path=video_path,
                ranges=ranges,
                output_dir=keyframes_dir,
                max_total_scenes=max(350, target_shots * 2),
                target_shots=target_shots
            )
            scenes_file.write_text(json.dumps(scenes, indent=2, ensure_ascii=False))

        # Tự động tìm kiếm file audio của phim nếu chưa được truyền vào
        if not audio_path:
            for cand_name in ["audio_low.mp3", "audio_preview.mp3", "audio.mp3", "audio_stream.wav"]:
                cand_path = self.workspace_root / cand_name
                if cand_path.is_file():
                    audio_path = cand_path
                    break

        gen = GoldenScriptGenerator(
            api_key=api_key,
            model_name=model_name,
            workspace=self.workspace_root,
            video_path=video_path
        )
        script_data = gen.generate_montage_script(
            scenes=scenes,
            blueprint=blueprint,
            keyframes_dir=keyframes_dir,
            target_lang=target_lang,
            audio_path=audio_path,
            review_style=review_style,
            acts_config=acts_config,
            custom_prompt=custom_prompt
        )

        script_file = self.workspace_root / "review_script.json"
        script_file.write_text(json.dumps(script_data, indent=2, ensure_ascii=False))

        # Sinh file metadata.json chuẩn SEO cho Movie Review
        items = script_data.get("script", [])
        movie_title = blueprint.get("movie_title") or Path(video_path).stem
        first_texts = [seg.get("voiceover_text", "") for seg in items[:3] if seg.get("voiceover_text")]
        desc = " ".join(first_texts) if first_texts else blueprint.get("summary", "")
        if not desc:
            desc = f"Video review tóm tắt nội dung phim {movie_title} kịch tính và hấp dẫn."
        genre_tag = blueprint.get("genre", "reviewphim")

        meta_dict = {
            "title": f"Tóm Tắt Phim: {movie_title} | Cú Twist Nghẹt Thở",
            "description": desc,
            "hashtags": ["#reviewphim", "#tomtatphim", "#phimhay", f"#{genre_tag}", "#cinema"]
        }
        meta_file = self.workspace_root / "metadata.json"
        meta_file.write_text(json.dumps(meta_dict, indent=2, ensure_ascii=False), encoding="utf-8")

        emit_json({"type": "script_ready", "data": script_data, "metadata": meta_dict})
        return script_data

    def run_stage3_and_4_render(
        self,
        video_path: Path,
        script_data: Dict[str, Any],
        output_mp4: Path,
        voice: str = "hoai_my",
        speed_factor: float = 1.15,
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
        """Chạy Stage 3 & 4: Sinh TTS và dựng video hoàn chỉnh."""
        audio_dir = self.workspace_root / "audio_segments"
        items = script_data.get("script", [])
        items = split_long_segments_by_speed(items, speed_factor=speed_factor)
        script_data["script"] = items

        skip_tts = from_step in ["mr05_assembly", "mr06_subtitle", "mr07_encode"]
        if skip_tts:
            emit_log("info", "Bỏ qua sinh TTS, tái sử dụng các file audio đã có...")
            emit_progress(0.30, "Đã sẵn sàng giọng đọc, bắt đầu ghép cảnh...")
            for idx, seg in enumerate(items):
                seg_id = seg.get("id", idx + 1)
                audio_file = seg.get("audio_file") or f"tts_{seg_id:03d}.mp3"
                seg["audio_file"] = audio_file
                af_path = audio_dir / audio_file
                if af_path.is_file() and not seg.get("audio_duration"):
                    try:
                        p_info = FFmpegUtils.probe(af_path)
                        seg["audio_duration"] = float(p_info.get("format", {}).get("duration", 4.0))
                    except Exception:
                        seg["audio_duration"] = 4.0
            updated_items = items
        else:
            # Sinh TTS
            updated_items = VoiceoverSynthesizer.synthesize_script(
                script_items=items,
                output_dir=audio_dir,
                voice=voice,
                speed_factor=speed_factor,
                start_progress=0.0,
                end_progress=0.30
            )
        script_data["script"] = updated_items

        # Lưu lại script có thời lượng audio thực tế
        (self.workspace_root / "review_script_synced.json").write_text(
            json.dumps(script_data, indent=2, ensure_ascii=False)
        )

        # Dựng video
        return MovieReviewAssembler.render_full_review(
            video_path=video_path,
            script_data=script_data,
            workspace_dir=self.workspace_root,
            output_mp4=output_mp4,
            aspect_ratio=aspect_ratio,
            tts_volume=tts_volume,
            original_audio_volume=original_audio_volume,
            bgm_volume=bgm_volume,
            burn_subtitles=burn_subtitles,
            enable_inpaint=enable_inpaint,
            flip_horizontal=flip_horizontal,
            crop_zoom=crop_zoom,
            mute_movie_audio=mute_movie_audio,
            from_step=from_step
        )


def main():
    parser = argparse.ArgumentParser(description="Sub-Video AI Movie Review Orchestrator")
    parser.add_argument("--action", choices=["analyze", "render", "auto", "test_word_budget", "test_tts"], required=True)
    parser.add_argument("--video", type=str, help="Đường dẫn file video gốc")
    parser.add_argument("--workspace", type=str, default="workspace/movie_review", help="Thư mục workspace")
    parser.add_argument("--genre", type=str, default="linear_action", choices=["linear_action", "complex_psychological", "shorts", "custom"])
    parser.add_argument("--duration", type=int, default=None, help="Thời lượng review mục tiêu (giây, mặc định tự căn theo độ dài phim)")
    parser.add_argument("--speed", type=float, default=1.45, help="Tốc độ đọc Voiceover TTS (1.0x - 1.8x, mặc định 1.45)")
    parser.add_argument("--voice", type=str, default=None, help="Giọng đọc (hoai_my, nam_minh, ban_mai hoặc tự đọc từ config.yaml)")
    parser.add_argument("--style", type=str, default="story_review", choices=["story_review", "critique"], help="Phong cách kịch bản (story_review: Kể chuyện kịch tính triệu view, critique: Phê bình tác phẩm)")
    parser.add_argument("--ratio", type=str, default="16:9", choices=["16:9", "9:16"])
    parser.add_argument("--output", type=str, default="output/movie_review.mp4", help="Đường dẫn file video xuất")
    parser.add_argument("--api-key", type=str, default=None, help="Google Gemini API Key")
    parser.add_argument("--model", type=str, default=None, help="Google Gemini Model (e.g. gemini-3.5-flash-lite, gemini-2.5-flash)")
    parser.add_argument("--acts-config", type=str, default=None, help="Cấu hình bố cục hồi và danh sách chương (JSON string hoặc đường dẫn file JSON)")
    parser.add_argument("--tts-volume", type=float, default=1.0, help="Âm lượng giọng đọc TTS (0.0 - 1.0, mặc định 1.0)")
    parser.add_argument("--original-audio-volume", type=float, default=0.15, help="Âm lượng tiếng phim gốc (0.0 - 1.0, mặc định 0.15)")
    parser.add_argument("--bgm-volume", type=float, default=0.20, help="Âm lượng nhạc nền BGM (0.0 - 1.0, mặc định 0.20)")
    parser.add_argument("--lang", type=str, default="vi", help="Ngôn ngữ review kịch bản (vi, en, zh,...)")
    parser.add_argument("--burn-subtitles", dest="burn_subtitles", action="store_true", default=True, help="Ghép phụ đề ASS vào video")
    parser.add_argument("--no-subtitles", dest="burn_subtitles", action="store_false", help="Không ghép phụ đề")
    parser.add_argument("--enable-inpaint", dest="enable_inpaint", action="store_true", default=True, help="Làm mờ/xóa sub cũ bằng Inpaint")
    parser.add_argument("--no-inpaint", dest="enable_inpaint", action="store_false", help="Bỏ qua Inpaint")
    parser.add_argument("--flip-horizontal", dest="flip_horizontal", action="store_true", default=False, help="Lật gương video để tránh quét bản quyền")
    parser.add_argument("--crop-zoom", dest="crop_zoom", action="store_true", default=False, help="Thu phóng 3%% khung hình để tránh quét bản quyền")
    parser.add_argument("--mute-movie-audio", dest="mute_movie_audio", action="store_true", default=False, help="Tắt hoàn toàn tiếng phim gốc")
    parser.add_argument("--prompt", type=str, default=None, help="Gợi ý nội dung / thông điệp kịch bản review tùy biến")
    parser.add_argument("--text", type=str, default=None, help="Văn bản cần kiểm tra hoặc nghe thử TTS")
    parser.add_argument(
        "--from-step",
        type=str,
        default=None,
        choices=[
            "mr01_blueprint",
            "mr02_scene_detect",
            "mr03_script_gen",
            "mr04_tts",
            "mr05_assembly",
            "mr06_subtitle",
            "mr07_encode",
        ],
        help="Chạy lại từ bước được chỉ định (bỏ qua các bước trước nếu đã có kết quả)"
    )

    args = parser.parse_args()

    video_path = Path(args.video).resolve() if args.video else None
    workspace = safe_ensure_dir(Path(args.workspace).resolve(), fallback_subdir="movie_review")
    output_mp4 = Path(args.output).resolve()
    output_parent = safe_ensure_dir(output_mp4.parent, fallback_subdir="output")
    output_mp4 = output_parent / output_mp4.name

    # Parse acts_config nếu có
    acts_config = None
    if args.acts_config:
        try:
            p_acts = Path(args.acts_config)
            if p_acts.is_file():
                acts_config = json.loads(p_acts.read_text())
            else:
                acts_config = json.loads(args.acts_config)
        except Exception as e:
            emit_log("warning", f"Không thể parse --acts-config: {e}")

    # Tự động căn chỉnh thời lượng review tối ưu nếu người dùng không truyền --duration
    if args.duration is None:
        if video_path and video_path.is_file():
            try:
                from core.step_base import probe_video
                v_meta = probe_video(video_path)
                v_dur = float(v_meta.get("duration", 0.0))
                args.duration = calculate_optimal_review_duration(v_dur)
            except Exception:
                args.duration = 360
        else:
            args.duration = 360

    # Tự động nạp giọng đọc từ config.yaml nếu người dùng không chỉ định --voice
    if not args.voice:
        cfg, _ = load_project_config(video_path=video_path, workspace=workspace)
        tts_cfg = cfg.get("tts", {})
        mr_cfg = cfg.get("movie_review", {})
        args.voice = mr_cfg.get("voice") or tts_cfg.get("voice") or "ban_mai"

    orchestrator = MovieReviewOrchestrator(workspace)

    if args.action == "test_word_budget":
        budget = calculate_word_budget(args.duration, args.speed, acts_config=acts_config)
        print(json.dumps(budget, indent=2, ensure_ascii=False))
        return

    if args.action == "test_tts":
        text = args.text or "Chào bạn, đây là giọng đọc thử nghiệm của Sub-Video Review."
        out_f = output_mp4
        dur = VoiceoverSynthesizer.synthesize_single(
            text=text,
            out_file=out_f,
            voice=args.voice,
            speed_factor=args.speed
        )
        emit_json({"type": "tts_ready", "audio_path": str(out_f), "duration": dur})
        return

    if args.action == "analyze":
        if not video_path or not video_path.exists():
            emit_log("error", f"Không tìm thấy file video: {video_path}")
            sys.exit(1)

        from_step = args.from_step
        bp_file = workspace / "blueprint.json"

        if from_step in ["mr02_scene_detect", "mr03_script_gen"]:
            if not bp_file.is_file():
                emit_log("error", f"Không tìm thấy {bp_file.name} để chạy lại từ {from_step}. Hãy chạy từ mr01_blueprint.")
                sys.exit(1)
            emit_log("info", f"Tái sử dụng Blueprint có sẵn: {bp_file.name}")
            bp = json.loads(bp_file.read_text())
        else:
            emit_log("info", f"Bắt đầu phân tích video: {video_path.name} (phong cách: {args.style})")
            bp = orchestrator.run_stage1_blueprint(
                video_path=video_path,
                genre=args.genre,
                target_duration_sec=args.duration,
                speed_factor=args.speed,
                api_key=args.api_key,
                model_name=args.model,
                target_lang=args.lang,
                review_style=args.style,
                custom_prompt=args.prompt
            )

        skip_scenes = (from_step == "mr03_script_gen")
        orchestrator.run_stage2_scenes_and_script(
            video_path=video_path,
            blueprint=bp,
            api_key=args.api_key,
            model_name=args.model,
            target_lang=args.lang,
            review_style=args.style,
            skip_scene_detect=skip_scenes,
            acts_config=acts_config,
            custom_prompt=args.prompt
        )

    elif args.action == "render":
        if not video_path or not video_path.exists():
            emit_log("error", f"Không tìm thấy file video: {video_path}")
            sys.exit(1)

        script_path = workspace / "review_script.json"
        if not script_path.exists():
            emit_log("error", f"Không tìm thấy kịch bản review_script.json tại {workspace}")
            sys.exit(1)

        script_data = json.loads(script_path.read_text())
        orchestrator.run_stage3_and_4_render(
            video_path=video_path,
            script_data=script_data,
            output_mp4=output_mp4,
            voice=args.voice,
            speed_factor=args.speed,
            aspect_ratio=args.ratio,
            tts_volume=args.tts_volume,
            original_audio_volume=args.original_audio_volume,
            bgm_volume=args.bgm_volume,
            burn_subtitles=args.burn_subtitles,
            enable_inpaint=args.enable_inpaint,
            flip_horizontal=args.flip_horizontal,
            crop_zoom=args.crop_zoom,
            mute_movie_audio=args.mute_movie_audio,
            from_step=args.from_step
        )

    elif args.action == "auto":
        if not video_path or not video_path.exists():
            emit_log("error", f"Không tìm thấy file video: {video_path}")
            sys.exit(1)

        emit_log("info", "Chạy chế độ tự động hoàn toàn (Auto Full-Pipeline)...")
        bp = orchestrator.run_stage1_blueprint(
            video_path=video_path,
            genre=args.genre,
            target_duration_sec=args.duration,
            speed_factor=args.speed,
            api_key=args.api_key,
            model_name=args.model,
            target_lang=args.lang,
            custom_prompt=args.prompt
        )
        script_data = orchestrator.run_stage2_scenes_and_script(
            video_path=video_path,
            blueprint=bp,
            api_key=args.api_key,
            model_name=args.model,
            target_lang=args.lang,
            acts_config=acts_config,
            custom_prompt=args.prompt
        )
        orchestrator.run_stage3_and_4_render(
            video_path=video_path,
            script_data=script_data,
            output_mp4=output_mp4,
            voice=args.voice,
            speed_factor=args.speed,
            aspect_ratio=args.ratio,
            tts_volume=args.tts_volume,
            original_audio_volume=args.original_audio_volume,
            bgm_volume=args.bgm_volume,
            burn_subtitles=args.burn_subtitles,
            enable_inpaint=args.enable_inpaint
        )


__all__ = [
    # Facade & CLI
    "MovieReviewOrchestrator",
    "main",
    "FFmpegUtils",
    # Re-exported from movie_review
    "emit_json",
    "emit_log",
    "emit_progress",
    "calculate_optimal_review_duration",
    "calculate_word_budget",
    "clean_json_str",
    "load_project_config",
    "resolve_gemini_config",
    "resolve_gemini_api_key",
    "split_long_segments_by_speed",
    "wrap_subtitle_text",
    "split_subtitle_into_rhythmic_cues",
    "_color_to_ass",
    "generate_review_ass_subtitles",
    "build_inpaint_filter",
    "TargetedSceneDetector",
    "VisualAlignmentEngine",
    "NarrativeBlueprintGenerator",
    "GoldenScriptGenerator",
    "VoiceoverSynthesizer",
    "MovieReviewAssembler",
]

if __name__ == "__main__":
    main()
