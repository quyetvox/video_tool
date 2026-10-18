#!/usr/bin/env python3
"""
AI Lecture Illustrator Orchestrator — Điều Phối Minh Họa Bài Giảng Tự Động
Module thứ 4 độc lập của Sub-Video:
- Ingest video bài giảng & Whisper Speech-to-Text (Word timestamps)
- Trích xuất tri thức, Educational Intent & sinh Prompt Pack 3-trong-1
- Ghi và nạp trạng thái project: `lecture_project.json`
- Composite Render FFmpeg: Inpaint làm mờ sub cũ, Visual Overlays (PiP, Full, Split),
  Lồng tiếng TTS đa giọng (Ban Mai, Hoài My...) + Phụ đề ASS song ngữ.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

ROOT_DIR = Path(__file__).parent.parent.resolve()
ENGINE_DIR = Path(__file__).parent.resolve()
sys.path.insert(0, str(ENGINE_DIR))
sys.path.insert(0, str(ROOT_DIR))

from utils.ffmpeg_utils import FFmpegUtils, ensure_system_path
ensure_system_path()

from lecture_illustrator.common import (
    emit_json,
    emit_log,
    emit_progress,
    safe_ensure_dir,
)
from lecture_illustrator.models import (
    LectureProject,
    LectureProjectConfig,
    LectureBatch,
    BatchPrompts,
    BatchActiveAsset,
)
from lecture_illustrator.scene_planner import (
    build_timeline,
    group_sentences,
    plan_scenes,
    stitch_sentence_boundaries,
    synthesize_sentences,
    translate_sentences,
)
from lecture_illustrator.visual_renderer import render_lecture_video


from lecture_illustrator.text_script_parser import parse_text_file_to_sentences


def detect_input_type(file_path: Path) -> str:
    """Xác định loại tệp đầu vào: video, audio hoặc text."""
    ext = file_path.suffix.lower()
    if ext in [".txt", ".md", ".markdown"]:
        return "text"
    if ext in [".wav", ".mp3", ".m4a", ".aac", ".flac", ".ogg", ".wma"]:
        return "audio"
    return "video"


def extract_audio_wav(video_path: Path, output_wav: Path) -> bool:
    """Trích xuất âm thanh mono 16kHz chuẩn cho Whisper từ video."""
    cmd = [
        "ffmpeg", "-y",
        "-i", str(video_path),
        "-vn",
        "-acodec", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        str(output_wav),
    ]
    res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return res.returncode == 0 and output_wav.exists()


def extract_original_audio_sentences(
    audio_path: Path,
    sentences: List[Dict[str, Any]],
    workspace_dir: Path,
) -> List[float]:
    """
    Khi giữ giọng gốc (voice_mode: original), cắt từng câu từ audio gốc thành s_XXXX.mp3
    trong thư mục tts/ để visual_renderer tái sử dụng đồng bộ.
    """
    tts_dir = workspace_dir / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)
    durations: List[float] = []

    emit_progress(0.40, f"Đang trích xuất {len(sentences)} đoạn giọng nói từ audio gốc...")
    for i, s in enumerate(sentences):
        out_mp3 = tts_dir / f"s_{i:04d}.mp3"
        st = max(0.0, float(s.get("start", 0.0)))
        en = max(st + 0.5, float(s.get("end", st + 1.5)))
        dur = round(en - st, 3)

        cmd = [
            "ffmpeg", "-y", "-loglevel", "error",
            "-ss", f"{st:.3f}",
            "-to", f"{en:.3f}",
            "-i", str(audio_path),
            "-vn", "-acodec", "libmp3lame",
            "-ar", "44100", "-ac", "2",
            str(out_mp3),
        ]
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if out_mp3.exists() and out_mp3.stat().st_size > 200:
            durations.append(dur)
        else:
            durations.append(max(1.5, dur))
        emit_progress(0.40 + 0.25 * (i + 1) / max(1, len(sentences)), f"Đã trích xuất giọng gốc {i + 1}/{len(sentences)}...")

    return durations


def transcribe_media_audio(media_path: Path, workspace_dir: Path, source_lang: str = "auto", input_type: str = "video") -> List[Dict[str, Any]]:
    """
    Thực hiện nhận diện giọng nói cho Video hoặc Audio:
    Ưu tiên đọc file s05_asr.json sẵn có trong workspace (tiết kiệm thời gian).
    Nếu chưa có, trích xuất audio 16kHz chuẩn và gọi Whisper plugin.
    """
    cached_asr = workspace_dir / "s05_asr.json"
    if cached_asr.exists():
        try:
            data = json.loads(cached_asr.read_text(encoding="utf-8"))
            if isinstance(data, list) and len(data) > 0:
                from utils.repetition_cleaner import RepetitionCleaner
                cleaned = RepetitionCleaner.clean_segments(data)
                if len(cleaned) < len(data):
                    emit_log("info", f"Tự động loại bỏ {len(data) - len(cleaned)} câu lặp ảo giác Whisper trong {cached_asr.name}.")
                    cached_asr.write_text(json.dumps(cleaned, ensure_ascii=False, indent=2), encoding="utf-8")
                emit_log("info", f"Tái sử dụng transcript Whisper sẵn có: {cached_asr.name}")
                return cleaned
        except Exception:
            pass

    emit_progress(0.05, f"Đang chuẩn bị âm thanh từ {input_type} bài giảng...")
    audio_wav = workspace_dir / "lecture_audio_16k.wav"
    if not extract_audio_wav(media_path, audio_wav):
        emit_log("warn", "Không thể trích xuất audio 16k bằng FFmpeg, dùng file gốc.")
        audio_wav = media_path

    emit_progress(0.10, "Đang chạy nhận diện giọng nói Whisper (Word Timestamps)...")
    try:
        from core.plugin_loader import PluginLoader
        from utils.repetition_cleaner import RepetitionCleaner
        config = {"asr": "mlx_whisper"} if sys.platform == "darwin" else {"asr": "faster_whisper"}
        if source_lang and source_lang != "auto":
            config["source_lang"] = source_lang
        asr_plugin = PluginLoader.load_plugin("asr", config.get("asr", "mlx_whisper"), config)
        raw_segments = asr_plugin.transcribe(audio_wav)
        cleaned_segments = RepetitionCleaner.clean_segments(raw_segments)
        
        # Lưu cache s05_asr.json
        cached_asr.write_text(json.dumps(cleaned_segments, ensure_ascii=False, indent=2), encoding="utf-8")
        emit_log("info", f"Whisper hoàn tất nhận diện {len(cleaned_segments)} câu thoại (sau khi lọc lặp từ).")
        return cleaned_segments
    except Exception as e:
        emit_log("warn", f"Chạy Whisper thất bại ({e}). Thử fallback audio probe...")
        probe = FFmpegUtils.probe(media_path)
        dur = float(probe.get("format", {}).get("duration", 60.0))
        return [
            {"start": 0.0, "end": min(dur, 20.0), "text": "Phần mở đầu bài giảng và giới thiệu khái niệm chính."},
            {"start": min(dur, 20.0), "end": dur, "text": "Phân tích nội dung chi tiết và quy trình thực hiện."},
        ]


def generate_lecture_metadata(
    video_name: str,
    batches: List[LectureBatch],
    workspace_dir: Path,
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
) -> Dict[str, Any]:
    """Tạo metadata AI (tiêu đề, mô tả, hashtags) cho bài giảng."""
    meta_path = workspace_dir / "lecture_metadata.json"
    if meta_path.exists():
        try:
            return json.loads(meta_path.read_text(encoding="utf-8"))
        except Exception:
            pass

    first_texts = [b.transcript_translated or b.transcript_original for b in batches[:4] if (b.transcript_translated or b.transcript_original)]
    summary_hint = " ".join(first_texts)[:500]

    clean_name = video_name.replace("_", " ").replace("-", " ").title()
    title = f"Bài Giảng: {clean_name}"
    desc = summary_hint if summary_hint else "Video bài giảng trực quan minh họa sơ đồ, khái niệm và hoạt cảnh dễ hiểu."
    hashtags = ["#baigiang", "#kienthuc", "#hoctap", "#congnghe", "#giaoduc"]

    if (api_key or base_url) and summary_hint:
        prompt = (
            "Dựa trên nội dung bài giảng sau, hãy tạo metadata YouTube/TikTok hấp dẫn:\n"
            f"Nội dung: {summary_hint}\n"
            "Trả về DUY NHẤT một JSON object có format:\n"
            '{"title": "Tiêu đề cuốn hút dưới 80 ký tự", "description": "Mô tả 2-3 câu tóm tắt nội dung chính", "hashtags": ["#tag1", "#tag2", "#tag3", "#tag4", "#tag5"]}'
        )
        try:
            from lecture_illustrator.knowledge_extractor import call_llm_api
            from lecture_illustrator.common import clean_json_str
            resp = call_llm_api(prompt, api_key or "", model or "gemma4:31b-cloud", base_url)
            parsed = json.loads(clean_json_str(resp or ""))
            if isinstance(parsed, dict) and "title" in parsed:
                title = str(parsed.get("title", title))
                desc = str(parsed.get("description", desc))
                if isinstance(parsed.get("hashtags"), list):
                    hashtags = [str(t) for t in parsed.get("hashtags", hashtags)]
        except Exception as e:
            emit_log("warn", f"Sinh metadata AI thất bại ({e}), dùng metadata chuẩn.")

    meta_data = {
        "title": title,
        "description": desc,
        "hashtags": hashtags,
    }
    try:
        meta_path.write_text(json.dumps(meta_data, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        pass
    return meta_data


def run_analyze_flow(args: argparse.Namespace) -> int:
    """Luồng 1: Phân tích nguồn bài giảng (video, audio, text) -> sinh lecture_project.json."""
    input_str = getattr(args, "input", None) or getattr(args, "video", None)
    if not input_str:
        emit_log("error", "Chưa chỉ định đường dẫn tệp đầu vào (--input hoặc --video)")
        return 1

    input_path = Path(input_str).resolve()
    if not input_path.exists():
        emit_log("error", f"Tệp đầu vào không tồn tại: {input_path}")
        return 1

    input_type = detect_input_type(input_path)
    workspace_dir = Path(args.workspace or (input_path.parent / ".lecture_workspace")).resolve()
    safe_ensure_dir(workspace_dir)

    emit_progress(0.02, f"Khởi tạo dự án minh họa bài giảng từ {input_type}: {input_path.name}")
    if input_type == "video":
        probe = FFmpegUtils.probe(input_path)
        v_stream = next((s for s in probe.get("streams", []) if s.get("codec_type") == "video"), {})
        vw = int(v_stream.get("width", 1920))
        vh = int(v_stream.get("height", 1080))
        dur = float(probe.get("format", {}).get("duration", 0.0))
    elif input_type == "audio":
        probe = FFmpegUtils.probe(input_path)
        dur = float(probe.get("format", {}).get("duration", 0.0))
        vw, vh = 1920, 1080
    else:  # text
        vw, vh = 1920, 1080
        dur = 0.0

    # Nạp config.yaml toàn cục của dự án để đảm bảo kế thừa 100% tham số
    from lecture_illustrator.common import load_engine_config
    cfg_yaml = load_engine_config(workspace_dir)

    out_json = Path(args.project_file or (workspace_dir / "lecture_project.json"))
    existing_cfg = None
    if out_json.exists():
        try:
            old_data = json.loads(out_json.read_text(encoding="utf-8"))
            if "config" in old_data and isinstance(old_data["config"], dict):
                existing_cfg = LectureProjectConfig.from_dict(old_data["config"])
                emit_log("info", "Kế thừa cấu hình tùy biến từ lecture_project.json sẵn có.")
        except Exception as e:
            emit_log("warn", f"Không thể nạp config cũ: {e}")

    # Cấu hình dự án (kế thừa toàn bộ config cũ, chỉ ghi đè tham số chỉ định)
    if existing_cfg:
        cfg = existing_cfg
        if args.source_lang: cfg.source_lang = args.source_lang
        if args.target_lang: cfg.target_lang = args.target_lang
        if getattr(args, "secondary_lang", None): cfg.secondary_lang = args.secondary_lang
        if args.pronoun_mode: cfg.pronoun_mode = args.pronoun_mode
        if args.voice_mode: cfg.voice_mode = args.voice_mode
        if args.tts_voice: cfg.tts_voice = args.tts_voice
        if args.tts_speed is not None: cfg.tts_speed = float(args.tts_speed)
        if args.bgm_volume is not None: cfg.bgm_volume = float(args.bgm_volume)
        if getattr(args, "voice_volume", None) is not None: cfg.voice_volume = float(args.voice_volume)
        if args.burn_subtitles is not None: cfg.burn_subtitles = bool(args.burn_subtitles != "false")
        if args.subtitle_mode: cfg.subtitle_mode = args.subtitle_mode
        if getattr(args, "subtitle_secondary_show", None) is not None:
            cfg.subtitle_secondary_show = bool(args.subtitle_secondary_show != "false")
        if getattr(args, "subtitle_order", None): cfg.subtitle_order = args.subtitle_order
        if args.layout_preset: cfg.visual_layout_preset = args.layout_preset
        if getattr(args, "font_name", None): cfg.font_name = args.font_name
        if getattr(args, "secondary_font_name", None): cfg.secondary_font_name = args.secondary_font_name
        if getattr(args, "font_size", None): cfg.font_size = args.font_size
        if getattr(args, "font_color", None): cfg.font_color = args.font_color
        if getattr(args, "outline_color", None): cfg.outline_color = args.outline_color
        if getattr(args, "secondary_font_color", None): cfg.secondary_font_color = args.secondary_font_color
        if getattr(args, "secondary_scale", None) is not None: cfg.secondary_scale = float(args.secondary_scale)
        if getattr(args, "video_bitrate", None): cfg.video_bitrate = args.video_bitrate
        if getattr(args, "watermark_enabled", None) is not None: cfg.watermark_enabled = bool(args.watermark_enabled != "false")
        if getattr(args, "watermark_path", None): cfg.watermark_path = args.watermark_path
        if getattr(args, "enable_inpaint", None) is not None: cfg.enable_inpaint = bool(args.enable_inpaint != "false")
        if getattr(args, "inpaint_engine", None): cfg.inpaint_engine = args.inpaint_engine
        if getattr(args, "inpaint_blur_radius", None) is not None: cfg.inpaint_blur_radius = int(args.inpaint_blur_radius)
        if getattr(args, "box_bg_color", None): cfg.box_bg_color = args.box_bg_color
        if getattr(args, "box_opacity", None) is not None: cfg.box_opacity = float(args.box_opacity)
        if getattr(args, "inpaint_method", None): cfg.inpaint_method = args.inpaint_method
        if getattr(args, "subtitle_region", None):
            raw_s = str(args.subtitle_region).strip()
            parts = [float(p.strip()) for p in raw_s.split(",") if p.strip()]
            if len(parts) == 4: cfg.subtitle_region = parts
        if getattr(args, "aspect_ratio", None): cfg.aspect_ratio = args.aspect_ratio
        if getattr(args, "ai_authored", None) is not None:
            cfg.ai_authored = bool(args.ai_authored != "false")
        if getattr(args, "html_author_model", None):
            cfg.html_author_model = args.html_author_model
        if getattr(args, "html_author_base_url", None):
            cfg.html_author_base_url = args.html_author_base_url
        if getattr(args, "html_author_api_key", None):
            cfg.html_author_api_key = args.html_author_api_key
        if getattr(args, "num_workers", None) is not None:
            cfg.num_workers = int(args.num_workers)
    else:
        # Lấy mặc định từ config.yaml nếu không truyền CLI
        yaml_speed = float(cfg_yaml.get("tts", {}).get("speed_factor", 1.15))
        init_speed = float(args.tts_speed) if args.tts_speed is not None else yaml_speed
        yaml_sec_lang = str(cfg_yaml.get("app", {}).get("secondary_lang", "en"))
        yaml_sec_show = bool(cfg_yaml.get("subtitle", {}).get("secondary", {}).get("show", True))
        yaml_order = str(cfg_yaml.get("subtitle", {}).get("order", "primary_top"))
        yaml_ai_authored = bool(cfg_yaml.get("lecture_illustrator", {}).get("ai_authored", True))
        init_ai_authored = bool(args.ai_authored != "false") if getattr(args, "ai_authored", None) is not None else yaml_ai_authored

        raw_yaml_voice = str(cfg_yaml.get("tts", {}).get("voice", "ban_mai"))
        if "hoaimy" in raw_yaml_voice.lower() or "hoai_my" in raw_yaml_voice.lower():
            yaml_voice = "hoai_my"
        elif "namminh" in raw_yaml_voice.lower() or "nam_minh" in raw_yaml_voice.lower():
            yaml_voice = "nam_minh"
        elif "banmai" in raw_yaml_voice.lower() or "ban_mai" in raw_yaml_voice.lower() or raw_yaml_voice.lower() == "vi":
            yaml_voice = "ban_mai"
        else:
            yaml_voice = raw_yaml_voice

        # Phân tích subtitle.region từ CLI hoặc config.yaml
        init_sub_reg = None
        if getattr(args, "subtitle_region", None):
            try:
                parts = [float(p.strip()) for p in str(args.subtitle_region).split(",") if p.strip()]
                if len(parts) == 4:
                    init_sub_reg = parts
            except Exception:
                init_sub_reg = None
        if init_sub_reg is None:
            yaml_sub_reg = cfg_yaml.get("subtitle", {}).get("region")
            if isinstance(yaml_sub_reg, (list, tuple)) and len(yaml_sub_reg) == 4:
                init_sub_reg = [float(v) for v in yaml_sub_reg]

        yaml_sec_scale = (
            cfg_yaml.get("subtitle", {}).get("secondary", {}).get("font_size_scale")
            or cfg_yaml.get("subtitle", {}).get("secondary", {}).get("font_scale")
            or 0.70
        )

        cfg = LectureProjectConfig(
            source_lang=args.source_lang or "auto",
            target_lang=args.target_lang or cfg_yaml.get("app", {}).get("target_lang", "vi"),
            secondary_lang=getattr(args, "secondary_lang", None) or (yaml_sec_lang if yaml_sec_lang else "en"),
            pronoun_mode=args.pronoun_mode or "formal",
            voice_mode=args.voice_mode or "tts_dub",
            tts_voice=args.tts_voice or yaml_voice,
            tts_speed=init_speed,
            bgm_volume=float(args.bgm_volume if args.bgm_volume is not None else cfg_yaml.get("audio", {}).get("volumes", {}).get("music", 0.10)),
            voice_volume=float(getattr(args, "voice_volume", 1.0) or cfg_yaml.get("audio", {}).get("volumes", {}).get("voice", 1.0)),
            burn_subtitles=bool(args.burn_subtitles != "false"),
            subtitle_mode=args.subtitle_mode or "bilingual",
            subtitle_secondary_show=bool(getattr(args, "subtitle_secondary_show", str(yaml_sec_show)) != "false"),
            subtitle_order=getattr(args, "subtitle_order", None) or yaml_order,
            font_name=getattr(args, "font_name", None) or cfg_yaml.get("subtitle", {}).get("font_name", "Be Vietnam Pro"),
            secondary_font_name=getattr(args, "secondary_font_name", None),
            font_size=getattr(args, "font_size", None) or str(cfg_yaml.get("subtitle", {}).get("font_size", "26")),
            font_color=getattr(args, "font_color", None) or cfg_yaml.get("subtitle", {}).get("font_color", "&H00FFFFFF"),
            outline_color=getattr(args, "outline_color", None) or cfg_yaml.get("subtitle", {}).get("outline_color", "&H00000000"),
            secondary_font_color=getattr(args, "secondary_font_color", None) or cfg_yaml.get("subtitle", {}).get("secondary", {}).get("font_color", "&H00E7E1DC"),
            secondary_scale=float(getattr(args, "secondary_scale", None) or yaml_sec_scale),
            subtitle_region=init_sub_reg,
            video_bitrate=getattr(args, "video_bitrate", None) or cfg_yaml.get("app", {}).get("video_bitrate", "6000k"),
            watermark_enabled=bool(getattr(args, "watermark_enabled", "false") != "false" or cfg_yaml.get("watermark", {}).get("enabled", False)),
            watermark_path=getattr(args, "watermark_path", None) or cfg_yaml.get("watermark", {}).get("image", ""),
            enable_inpaint=bool(getattr(args, "enable_inpaint", "false") != "false" or cfg_yaml.get("inpaint", {}).get("show_box", False)),
            inpaint_engine=getattr(args, "inpaint_engine", None) or cfg_yaml.get("inpaint", {}).get("engine", "ffmpeg_blur"),
            inpaint_blur_radius=int(getattr(args, "inpaint_blur_radius", None) or cfg_yaml.get("inpaint", {}).get("blur_radius", 20)),
            box_bg_color=getattr(args, "box_bg_color", None) or cfg_yaml.get("inpaint", {}).get("box", {}).get("bg_color", "#000000"),
            box_opacity=float(getattr(args, "box_opacity", None) or cfg_yaml.get("inpaint", {}).get("box", {}).get("bg_opacity", 0.85)),
            inpaint_method=getattr(args, "inpaint_method", None) or cfg_yaml.get("inpaint", {}).get("method", "vertical_gradient"),
            visual_layout_preset=args.layout_preset or "pip",
            aspect_ratio=getattr(args, "aspect_ratio", None) or cfg_yaml.get("app", {}).get("aspect_ratio", "16:9"),
            ai_authored=init_ai_authored,
            html_author_model=getattr(args, "html_author_model", None),
            html_author_base_url=getattr(args, "html_author_base_url", None),
            html_author_api_key=getattr(args, "html_author_api_key", None),
            num_workers=int(args.num_workers) if getattr(args, "num_workers", None) is not None else (int(cfg_yaml.get("app", {}).get("num_workers")) if cfg_yaml.get("app", {}).get("num_workers") is not None else None),
        )

    if cfg.aspect_ratio == "9:16":
        vw, vh = 1080, 1920
    elif getattr(args, "aspect_ratio", None) == "16:9" or input_type != "video":
        vw, vh = 1920, 1080

    t_cfg = cfg_yaml.get("translator", {}) if isinstance(cfg_yaml, dict) else {}
    translator_type = getattr(args, "translator_type", None) or t_cfg.get("type", "ollama")
    api_key = args.api_key or t_cfg.get("api_key") or os.environ.get("GEMINI_API_KEY", "")
    model = args.model or t_cfg.get("model") or "gemma4:31b-cloud"
    base_url = getattr(args, "base_url", None) or t_cfg.get("base_url") or "http://localhost:11434"

    # 1. Trích xuất câu bài giảng (sentences) theo loại nguồn
    if input_type == "text":
        emit_progress(0.15, "Đang phân tích kịch bản bài giảng từ văn bản...")
        sentences = parse_text_file_to_sentences(
            file_path=input_path,
            config=cfg,
            api_key=api_key,
            model=model,
            base_url=base_url,
            is_raw_article=bool(getattr(args, "raw_article", False)),
        )
        if not sentences:
            emit_log("error", f"Không trích xuất được câu nào từ văn bản: {input_path.name}")
            return 1
    else:
        # Video hoặc Audio: Trích xuất Whisper transcript & dịch
        raw_segments = transcribe_media_audio(input_path, workspace_dir, source_lang=cfg.source_lang, input_type=input_type)
        emit_progress(0.20, f"Đang dịch toàn bộ lời thuyết minh sang ngôn ngữ đích ({translator_type}: {model})...")
        sentences = translate_sentences(raw_segments, cfg, api_key=api_key, model=model, base_url=base_url)

    # 2. Gom nhóm câu
    groups = group_sentences(sentences)
    emit_log("info", f"Gom {len(sentences)} câu thành {len(groups)} nhóm minh họa.")

    # 3. Đo thời lượng và tạo âm thanh từng câu
    if cfg.voice_mode == "original" and input_type in ["audio", "video"]:
        durations = extract_original_audio_sentences(input_path, sentences, workspace_dir)
    else:
        if cfg.voice_mode == "original" and input_type == "text":
            emit_log("warn", "Đầu vào văn bản không có giọng gốc, tự động chuyển sang lồng tiếng AI (TTS).")
        durations = synthesize_sentences(sentences, cfg, workspace_dir)

    # 4. Dựng timeline và scene plan
    timeline = build_timeline(groups, durations)
    emit_progress(0.70, "Đang lập kịch bản cảnh minh họa...")
    scenes = plan_scenes(groups, api_key=api_key, model=model, base_url=base_url)

    # 4b. AI-Authored Scenes: Kế thừa cảnh HTML hợp lệ có sẵn nếu có (Smart Resume không gọi AI mới khi phân tích)
    scenes_dir = workspace_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    for i, tl in enumerate(timeline):
        batch_id = f"batch_{i + 1:03d}"
        out_html = scenes_dir / f"{batch_id}.html"
        meta_json = scenes_dir / f"{batch_id}.meta.json"
        if out_html.exists() and meta_json.exists():
            try:
                meta_data = json.loads(meta_json.read_text(encoding="utf-8"))
                if meta_data.get("passed") and meta_data.get("aspect_ratio") == cfg.aspect_ratio:
                    scenes[i]["mode"] = "authored"
                    scenes[i]["html_path"] = str(out_html)
                    scenes[i]["inferred"] = bool(meta_data.get("inferred", False))
                    emit_log("info", f"[Smart Resume] Kế thừa cảnh HTML hợp lệ có sẵn: {batch_id}")
            except Exception:
                pass

    batches = [
        LectureBatch(
            id=f"batch_{i + 1:03d}",
            start_sec=tl["start"],
            end_sec=tl["end"],
            transcript_original=" ".join(s["text_orig"] for s in tl["sentences"]),
            transcript_translated=" ".join(s["text"] for s in tl["sentences"]),
            sentences=tl["sentences"],
            scene=scenes[i],
            step_starts=tl["step_starts"],
            scene_duration=tl["scene_duration"],
        )
        for i, tl in enumerate(timeline)
    ]
    dur = timeline[-1]["end"] if timeline else 0.0  # thời lượng video đầu ra phụ thuộc giọng đọc

    # 5. Sinh Metadata AI (Tiêu đề, Mô tả, Hashtags)
    meta = generate_lecture_metadata(
        video_name=input_path.stem,
        batches=batches,
        workspace_dir=workspace_dir,
        api_key=api_key,
        model=model,
        base_url=base_url,
    )

    # 6. Tạo project object & ghi file JSON
    proj = LectureProject(
        project_name=args.project_name or input_path.stem,
        video_path=str(input_path),
        video_duration=dur,
        video_width=vw,
        video_height=vh,
        config=cfg,
        batches=batches,
    )

    out_json.write_text(json.dumps(proj.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")

    emit_progress(1.0, f"Phân tích hoàn tất! Đã lưu: {out_json.name}")
    emit_json({
        "type": "result",
        "action": "analyze",
        "project_file": str(out_json),
        "batch_count": len(batches),
        "metadata": meta,
    })
    return 0


def run_render_flow(args: argparse.Namespace) -> int:
    """Luồng 2: Đọc lecture_project.json và xuất video hoàn chỉnh."""
    proj_path = Path(args.project_file).resolve()
    if not proj_path.exists():
        emit_log("error", f"File kịch bản bài giảng không tồn tại: {proj_path}")
        return 1

    workspace_dir = proj_path.parent
    data = json.loads(proj_path.read_text(encoding="utf-8"))
    project = LectureProject.from_dict(data)

    if getattr(args, "num_workers", None) is not None:
        project.config.num_workers = int(args.num_workers)

    # Nạp config.yaml toàn cục để dự phòng API key và model nếu CLI args không truyền
    from lecture_illustrator.common import load_engine_config
    cfg_yaml = load_engine_config(workspace_dir)
    t_cfg = cfg_yaml.get("translator", {}) if isinstance(cfg_yaml, dict) else {}
    fallback_api_key = getattr(args, "api_key", None) or t_cfg.get("api_key") or os.environ.get("GEMINI_API_KEY", "")
    fallback_model = getattr(args, "model", None) or t_cfg.get("model") or "gemma4:31b-cloud"
    fallback_base_url = getattr(args, "base_url", None) or t_cfg.get("base_url") or "http://localhost:11434"

    # Tự động đồng bộ/dịch text_secondary nếu bật song ngữ nhưng phụ đề phụ chưa được dịch
    sec_lang = (project.config.secondary_lang or "").strip().lower()
    target_lang = (project.config.target_lang or "vi").strip().lower()
    if project.config.subtitle_mode == "bilingual" and sec_lang and sec_lang not in ("none", target_lang):
        needs_sec_trans = False
        all_sents = []
        for b in project.batches:
            for s in getattr(b, "sentences", []):
                all_sents.append(s)
                sec = str(s.get("text_secondary", "")).strip()
                pri = str(s.get("text", "")).strip()
                if pri and (not sec or sec == pri):
                    needs_sec_trans = True
        if needs_sec_trans and all_sents:
            from lecture_illustrator.scene_planner import translate_secondary_subtitles
            emit_log("info", f"Phát hiện {len(all_sents)} câu phụ chưa có bản dịch '{sec_lang}', tiến hành tự động dịch...")
            translate_secondary_subtitles(
                all_sents,
                project.config,
                api_key=fallback_api_key,
                model=fallback_model,
                base_url=fallback_base_url,
            )
            try:
                proj_path.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
                emit_log("info", "Đã lưu bản dịch phụ đề phụ vào file dự án.")
            except Exception as e:
                emit_log("warn", f"Không thể lưu project JSON: {e}")

    # Tự động cho AI viết mã HTML animation cho các batch còn thiếu nếu bật ai_authored
    if getattr(project.config, "ai_authored", True):
        scenes_dir = workspace_dir / "scenes"
        scenes_dir.mkdir(parents=True, exist_ok=True)
        from lecture_illustrator.scene_author import author_scene_with_retry

        author_model = getattr(args, "html_author_model", None) or project.config.html_author_model or fallback_model
        author_base_url = getattr(args, "html_author_base_url", None) or project.config.html_author_base_url or fallback_base_url
        author_api_key = getattr(args, "html_author_api_key", None) or project.config.html_author_api_key or fallback_api_key

        batches_to_author = []
        for i, b in enumerate(project.batches):
            if b.active_asset and b.active_asset.file_path:
                continue

            out_html = scenes_dir / f"{b.id}.html"
            meta_json = scenes_dir / f"{b.id}.meta.json"
            is_valid = False
            if out_html.exists() and meta_json.exists():
                try:
                    meta_data = json.loads(meta_json.read_text(encoding="utf-8"))
                    if meta_data.get("passed") and meta_data.get("aspect_ratio") == project.config.aspect_ratio:
                        is_valid = True
                        if isinstance(b.scene, dict):
                            b.scene["mode"] = "authored"
                            b.scene["html_path"] = str(out_html)
                            b.scene["inferred"] = bool(meta_data.get("inferred", False))
                except Exception:
                    is_valid = False

            if not is_valid:
                batches_to_author.append((i, b))

        if batches_to_author:
            from lecture_illustrator.common import resolve_hardware_config
            from concurrent.futures import ThreadPoolExecutor, as_completed
            import threading

            workers, _, _ = resolve_hardware_config(project.config)
            author_workers = min(max(1, workers), len(batches_to_author))
            emit_log("info", f"[Auto-Author] Phát hiện {len(batches_to_author)}/{len(project.batches)} cảnh chưa có animation HTML. AI đang tạo animation song song ({author_workers} workers)...")

            completed_count = 0
            count_lock = threading.Lock()

            def _author_task(orig_idx: int, b: LectureBatch):
                nonlocal completed_count
                out_html = scenes_dir / f"{b.id}.html"
                sents = getattr(b, "sentences", []) or []
                sents_text = [s.get("text", "") for s in sents if isinstance(s, dict)]
                if not sents_text:
                    sents_text = [b.transcript_translated or b.transcript_original]
                step_starts = getattr(b, "step_starts", []) or [0.0]
                scene_dur = float(getattr(b, "scene_duration", 0.0) or (b.end_sec - b.start_sec) or 3.0)
                fallback_tmpl = b.scene.get("template", "bullet_list") if isinstance(b.scene, dict) else "bullet_list"

                ok, sc_data, sc_meta = author_scene_with_retry(
                    batch_id=b.id,
                    sentences=sents_text,
                    step_starts=step_starts,
                    duration=scene_dur,
                    aspect_ratio=project.config.aspect_ratio,
                    out_html_path=out_html,
                    api_key=author_api_key,
                    model=author_model,
                    base_url=author_base_url,
                    fallback_template=fallback_tmpl,
                    subtitle_region=getattr(project.config, "subtitle_region", None),
                )

                with count_lock:
                    completed_count += 1
                    curr_completed = completed_count

                emit_progress(
                    0.05 + 0.50 * (curr_completed / len(batches_to_author)),
                    f"AI đang viết mã HTML cho cảnh {curr_completed}/{len(batches_to_author)} ({b.id})..."
                )
                return orig_idx, b, sc_data

            with ThreadPoolExecutor(max_workers=author_workers) as executor:
                futures = [executor.submit(_author_task, orig_idx, b) for orig_idx, b in batches_to_author]
                for fut in as_completed(futures):
                    orig_idx, b, sc_data = fut.result()
                    b.scene = sc_data
                    project.batches[orig_idx].scene = sc_data

            try:
                proj_path.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
                emit_log("info", "Đã cập nhật mã HTML của các cảnh vào file dự án.")
            except Exception as e:
                emit_log("warn", f"Không thể lưu project JSON: {e}")

    output_path = Path(args.output).resolve() if args.output else workspace_dir / f"{Path(project.video_path).stem}_illustrated.mp4"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    success = render_lecture_video(
        project=project,
        output_mp4_path=output_path,
        workspace_dir=workspace_dir,
    )

    if success:
        emit_json({
            "type": "result",
            "action": "render",
            "output_video": str(output_path),
            "status": "success",
        })
        return 0
    return 1


def run_reauthor_batch_flow(args: argparse.Namespace) -> int:
    """Luồng 3: Tái tạo HTML cho 1 batch đơn lẻ theo phản hồi (feedback) của người dùng và render lại clip xem trước."""
    if not args.batch_id:
        emit_log("error", "Thiếu tham số bắt buộc --batch-id")
        return 1

    proj_file = None
    if args.project_file:
        proj_file = Path(args.project_file).resolve()
    elif args.workspace:
        proj_file = Path(args.workspace).resolve() / "lecture_project.json"
    elif args.video or args.input:
        in_p = Path(args.video or args.input).resolve()
        p_name = args.project_name or "default"
        safe_name = re.sub(r"[^\w\-]+", "_", in_p.stem)
        proj_file = ROOT_DIR / "resources" / p_name / "workspace" / "lecture_illustrator" / safe_name / "lecture_project.json"

    if not proj_file or not proj_file.exists():
        emit_log("error", f"Không tìm thấy file kịch bản lecture_project.json: {proj_file}")
        return 1

    workspace_dir = proj_file.parent
    try:
        data = json.loads(proj_file.read_text(encoding="utf-8"))
        project = LectureProject.from_dict(data)
    except Exception as e:
        emit_log("error", f"Lỗi đọc file project: {e}")
        return 1

    cfg = project.config
    target_batch = None
    sentence_offset = 0
    found_idx = -1
    for i, b in enumerate(project.batches):
        if b.id == args.batch_id:
            target_batch = b
            found_idx = i
            break
        sentence_offset += len(getattr(b, "sentences", []) or [])

    if not target_batch:
        emit_log("error", f"Không tìm thấy batch với ID: {args.batch_id}")
        return 1

    emit_log("info", f"[Reauthor] Bắt đầu tái tạo HTML cho {target_batch.id}...")
    scenes_dir = workspace_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    out_html = scenes_dir / f"{target_batch.id}.html"

    # Lấy danh sách câu thoại và mốc thời gian của batch
    sents = getattr(target_batch, "sentences", []) or []
    if sents:
        sents_text = [s.get("translated") or s.get("text") or "" for s in sents]
    else:
        sents_text = [target_batch.transcript_translated or target_batch.transcript_original]
    step_starts = getattr(target_batch, "step_starts", []) or [0.0]
    scene_dur = float(getattr(target_batch, "scene_duration", 0.0) or (target_batch.end_sec - target_batch.start_sec) or 3.0)

    # API key & Model (kế thừa từ config.yaml nếu không truyền CLI)
    from lecture_illustrator.common import load_engine_config
    root_cfg = load_engine_config(workspace_dir)
    trans_cfg = root_cfg.get("translator", {}) if isinstance(root_cfg, dict) else {}

    api_key = args.html_author_api_key or args.api_key or cfg.html_author_api_key or getattr(cfg, "api_key", None) or trans_cfg.get("api_key")
    model = args.html_author_model or args.model or cfg.html_author_model or trans_cfg.get("model") or "gemini-flash-lite-latest"
    base_url = args.html_author_base_url or args.base_url or cfg.html_author_base_url or trans_cfg.get("base_url")

    from lecture_illustrator.scene_author import author_scene_with_retry
    ok, sc_data, sc_meta = author_scene_with_retry(
        batch_id=target_batch.id,
        sentences=sents_text,
        step_starts=step_starts,
        duration=scene_dur,
        aspect_ratio=cfg.aspect_ratio,
        out_html_path=out_html,
        api_key=api_key,
        model=model,
        base_url=base_url,
        fallback_template=target_batch.scene.get("template", "bullet_list") if isinstance(target_batch.scene, dict) else "bullet_list",
        user_feedback=args.feedback or "",
        subtitle_region=getattr(cfg, "subtitle_region", None),
    )

    if not ok:
        err_msg = "; ".join(sc_meta.get("errors", [])[:2]) if sc_meta.get("errors") else "AI không phản hồi hoặc mã HTML không đạt chuẩn"
        emit_log("error", f"[Reauthor] AI thiết kế lại cảnh {target_batch.id} không thành công: {err_msg}. Vui lòng kiểm tra API key / model hoặc chỉnh lại lời nhắc.")
        emit_json({
            "type": "result",
            "action": "reauthor_batch",
            "batch_id": target_batch.id,
            "status": "failed",
            "errors": sc_meta.get("errors", []),
        })
        return 2

    # Cập nhật thông tin cảnh trong batch
    sc_data["mode"] = "authored"
    sc_data["html_path"] = str(out_html)
    target_batch.scene = sc_data

    # Render lại video clip MP4 (single-pass kết hợp audio và phụ đề)
    emit_log("info", f"[Reauthor] Đang render lại video clip xem trước cho {target_batch.id}...")
    from lecture_illustrator.visual_renderer import render_single_batch_complete
    res_clip, b_hash = render_single_batch_complete(
        batch=target_batch,
        workspace_dir=workspace_dir,
        config=cfg,
        sentence_offset=sentence_offset,
        force_rerender=True,
    )

    if res_clip and res_clip.exists():
        target_batch.scene_video = str(res_clip)

    # Lưu lại lecture_project.json
    project.batches[found_idx] = target_batch
    try:
        proj_file.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
        emit_log("info", f"[Reauthor] Đã cập nhật {proj_file.name}")
    except Exception as e:
        emit_log("error", f"Không thể lưu project JSON: {e}")
        return 1

    emit_json({
        "type": "result",
        "action": "reauthor_batch",
        "batch_id": target_batch.id,
        "html_path": str(out_html),
        "scene_video": target_batch.scene_video,
        "status": "success",
    })
    return 0


def run_import_batch_html_flow(args: argparse.Namespace) -> int:
    """Luồng 4: Import file HTML từ ngoài vào 1 batch, tự căn chỉnh tốc độ và render clip xem trước."""
    proj_path = Path(args.project_file).resolve()
    if not proj_path.exists():
        emit_log("error", f"File kịch bản bài giảng không tồn tại: {proj_path}")
        return 1

    workspace_dir = proj_path.parent
    data = json.loads(proj_path.read_text(encoding="utf-8"))
    project = LectureProject.from_dict(data)
    cfg = project.config

    if not args.batch_id:
        emit_log("error", "Thiếu tham số --batch-id")
        return 1
    if not args.html_file:
        emit_log("error", "Thiếu tham số --html-file")
        return 1

    imported_html_path = Path(args.html_file).resolve()
    if not imported_html_path.exists():
        emit_log("error", f"File HTML cần import không tồn tại: {imported_html_path}")
        return 1

    found_idx = -1
    target_batch: Optional[LectureBatch] = None
    for idx, b in enumerate(project.batches):
        if b.id == args.batch_id:
            found_idx = idx
            target_batch = b
            break

    if target_batch is None:
        emit_log("error", f"Không tìm thấy batch với ID: {args.batch_id}")
        return 1

    sentence_offset = 0
    for idx in range(found_idx):
        sentence_offset += len(project.batches[idx].sentences)

    scenes_dir = workspace_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    out_html = scenes_dir / f"{target_batch.id}.html"
    meta_json = scenes_dir / f"{target_batch.id}.meta.json"

    scene_dur = float(getattr(target_batch, "scene_duration", 0.0) or (target_batch.end_sec - target_batch.start_sec) or 3.0)
    step_starts = getattr(target_batch, "step_starts", []) or [0.0]

    emit_log("info", f"[Import HTML] Đang cân chỉnh mốc thời gian và tốc độ cho {target_batch.id} ({scene_dur:.2f}s)...")
    from lecture_illustrator.html_calibrator import import_and_calibrate_scene_html
    try:
        import_and_calibrate_scene_html(
            input_html_path=imported_html_path,
            output_html_path=out_html,
            actual_duration=scene_dur,
            actual_step_starts=step_starts,
        )
    except Exception as e:
        emit_log("error", f"Lỗi khi cân chỉnh file HTML: {e}")
        return 1

    meta_data = {
        "batch_id": target_batch.id,
        "passed": True,
        "mode": "authored",
        "imported": True,
        "aspect_ratio": cfg.aspect_ratio,
        "scene_duration": scene_dur,
        "step_starts": step_starts,
    }
    meta_json.write_text(json.dumps(meta_data, ensure_ascii=False, indent=2), encoding="utf-8")

    sc_data = target_batch.scene if isinstance(target_batch.scene, dict) else {}
    sc_data["mode"] = "authored"
    sc_data["html_path"] = str(out_html)
    sc_data["imported"] = True
    target_batch.scene = sc_data

    # Xóa asset tĩnh thủ công nếu có để ưu tiên HTML mới import
    target_batch.active_asset = None

    emit_log("info", f"[Import HTML] Đang render lại video clip xem trước cho {target_batch.id}...")
    from lecture_illustrator.visual_renderer import render_single_batch_complete
    res_clip, b_hash = render_single_batch_complete(
        batch=target_batch,
        workspace_dir=workspace_dir,
        config=cfg,
        sentence_offset=sentence_offset,
        force_rerender=True,
    )

    if res_clip and res_clip.exists():
        target_batch.scene_video = str(res_clip)

    project.batches[found_idx] = target_batch
    try:
        proj_path.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
        emit_log("info", f"[Import HTML] Đã cập nhật {proj_path.name}")
    except Exception as e:
        emit_log("error", f"Không thể lưu project JSON: {e}")
        return 1

    emit_json({
        "type": "result",
        "action": "import_batch_html",
        "batch_id": target_batch.id,
        "html_path": str(out_html),
        "scene_video": target_batch.scene_video,
        "status": "success",
    })
    return 0


def run_merge_batches_flow(args: argparse.Namespace) -> int:
    """Luồng 5: Gộp 2 phân cảnh liền kề, tự động khâu câu dở dang, tính lại timeline, tái tạo HTML và render clip xem trước."""
    proj_path = None
    if args.project_file:
        proj_path = Path(args.project_file).resolve()
    elif args.workspace:
        proj_path = Path(args.workspace).resolve() / "lecture_project.json"

    if not proj_path or not proj_path.exists():
        emit_log("error", f"Không tìm thấy file kịch bản lecture_project.json: {proj_path}")
        return 1

    workspace_dir = proj_path.parent
    try:
        data = json.loads(proj_path.read_text(encoding="utf-8"))
        project = LectureProject.from_dict(data)
    except Exception as e:
        emit_log("error", f"Lỗi đọc file project: {e}")
        return 1

    cfg = project.config
    if not args.batch_id:
        emit_log("error", "Thiếu tham số bắt buộc --batch-id")
        return 1

    found_idx1 = -1
    for idx, b in enumerate(project.batches):
        if b.id == args.batch_id:
            found_idx1 = idx
            break

    if found_idx1 == -1:
        emit_log("error", f"Không tìm thấy batch với ID: {args.batch_id}")
        return 1

    if args.merge_with_id:
        found_idx2 = -1
        for idx, b in enumerate(project.batches):
            if b.id == args.merge_with_id:
                found_idx2 = idx
                break
        if found_idx2 == -1:
            emit_log("error", f"Không tìm thấy batch thứ hai với ID: {args.merge_with_id}")
            return 1
    else:
        found_idx2 = found_idx1 + 1

    if found_idx2 >= len(project.batches):
        emit_log("error", f"Batch {args.batch_id} là phân cảnh cuối cùng, không có phân cảnh tiếp theo để gộp.")
        return 1

    if found_idx1 == found_idx2:
        emit_log("error", "Không thể gộp một batch với chính nó.")
        return 1

    # Đảm bảo idx1 < idx2
    if found_idx1 > found_idx2:
        found_idx1, found_idx2 = found_idx2, found_idx1

    b1 = project.batches[found_idx1]
    b2 = project.batches[found_idx2]
    emit_log("info", f"[Merge Batches] Tiến hành gộp {b1.id} và {b2.id}...")

    # 1. Ghép danh sách câu và tự động khâu câu dở dang (stitch_sentence_boundaries)
    sents_1 = list(getattr(b1, "sentences", []) or [])
    sents_2 = list(getattr(b2, "sentences", []) or [])
    combined_raw_sents = sents_1 + sents_2

    tts_dir = workspace_dir / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)

    def _concat_audio(f1_name: str, f2_name: str):
        p1 = tts_dir / f1_name
        p2 = tts_dir / f2_name
        if p1.exists() and p2.exists():
            tmp_out = tts_dir / f"tmp_concat_{f1_name}"
            cmd = [
                "ffmpeg", "-y", "-loglevel", "error",
                "-i", str(p1), "-i", str(p2),
                "-filter_complex", "[0:a][1:a]concat=n=2:v=0:a=1[a]",
                "-map", "[a]", str(tmp_out),
            ]
            r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if r.returncode == 0 and tmp_out.exists():
                tmp_out.replace(p1)

    merged_sentences = stitch_sentence_boundaries(combined_raw_sents, concat_audio_fn=_concat_audio)

    # Đo lại thời lượng thật cho từng câu
    durations = []
    for s in merged_sentences:
        af = s.get("audio_file")
        dur = float(s.get("duration", 0.0))
        if af and (tts_dir / af).exists():
            try:
                real_d = FFmpegUtils.probe_duration(tts_dir / af)
                if real_d > 0.1:
                    dur = real_d
            except Exception:
                pass
        durations.append(dur if dur > 0.1 else 2.0)

    # 2. Tính lại Timeline cho b1
    LEAD_IN = 1.2
    TAIL = 0.6
    SENTENCE_GAP = 0.25

    step_starts = []
    local = LEAD_IN
    for i, s in enumerate(merged_sentences):
        d = durations[i]
        s["duration"] = round(d, 3)
        step_starts.append(round(local, 3))
        s["start"] = round(b1.start_sec + local, 3)
        s["end"] = round(b1.start_sec + local + d, 3)
        local += d + SENTENCE_GAP

    new_scene_duration = round(local - SENTENCE_GAP + TAIL, 3)
    new_end_sec = round(b1.start_sec + new_scene_duration, 3)
    time_delta = new_end_sec - b2.end_sec

    b1.sentences = merged_sentences
    b1.step_starts = step_starts
    b1.scene_duration = new_scene_duration
    b1.end_sec = new_end_sec

    # Nối transcripts
    b1.transcript_original = f"{b1.transcript_original.strip()} {b2.transcript_original.strip()}".strip()
    b1.transcript_translated = f"{b1.transcript_translated.strip()} {b2.transcript_translated.strip()}".strip()

    # 3. Tịnh tiến thời gian cho các batch phía sau b2
    for k in range(found_idx2 + 1, len(project.batches)):
        b_k = project.batches[k]
        b_k.start_sec = round(b_k.start_sec + time_delta, 3)
        b_k.end_sec = round(b_k.end_sec + time_delta, 3)
        for s in getattr(b_k, "sentences", []) or []:
            s["start"] = round(s["start"] + time_delta, 3)
            s["end"] = round(s["end"] + time_delta, 3)

    # 4. Xóa b2 khỏi danh sách project.batches
    removed_batch_id = b2.id
    project.batches.pop(found_idx2)

    # 5. Dọn dẹp cache của b1 và b2 trong scenes
    scenes_dir = workspace_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = scenes_dir / ".batch_manifest.json"
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest.pop(b1.id, None)
            manifest.pop(removed_batch_id, None)
            manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
        except Exception:
            pass

    for bid in (b1.id, removed_batch_id):
        for f in (
            scenes_dir / f"{bid}.html",
            scenes_dir / f"{bid}.meta.json",
            scenes_dir / f"{bid}_audio.wav",
            scenes_dir / f"{bid}_video.mp4",
            scenes_dir / f"{bid}_combined.mp4",
            scenes_dir / f"{bid}.ass",
        ):
            if f.exists():
                try:
                    f.unlink()
                except OSError:
                    pass

    # 6. Tự động gọi AI tái tạo HTML cho batch đã gộp (Full AI Reauthor)
    emit_log("info", f"[Merge Batches] Đang tái tạo HTML minh họa cho {b1.id} ({len(merged_sentences)} câu)...")
    out_html = scenes_dir / f"{b1.id}.html"
    sents_text = [s.get("translated") or s.get("text") or "" for s in merged_sentences]

    api_key = args.html_author_api_key or args.api_key or cfg.html_author_api_key or getattr(cfg, "api_key", None)
    model = args.html_author_model or args.model or cfg.html_author_model
    base_url = args.html_author_base_url or args.base_url or cfg.html_author_base_url

    from lecture_illustrator.scene_author import author_scene_with_retry
    ok, sc_data, sc_meta = author_scene_with_retry(
        batch_id=b1.id,
        sentences=sents_text,
        step_starts=step_starts,
        duration=new_scene_duration,
        aspect_ratio=cfg.aspect_ratio,
        out_html_path=out_html,
        api_key=api_key,
        model=model,
        base_url=base_url,
        fallback_template=b1.scene.get("template", "bullet_list") if isinstance(b1.scene, dict) else "bullet_list",
        user_feedback=args.feedback or "Tạo bố cục minh họa liền mạch và logic sau khi gộp hai phân cảnh bài giảng.",
        subtitle_region=getattr(cfg, "subtitle_region", None),
    )

    if ok:
        sc_data["mode"] = "authored"
        sc_data["html_path"] = str(out_html)
        b1.scene = sc_data
    else:
        emit_log("warn", f"[Merge Batches] AI tác giả HTML cảnh {b1.id} cảnh báo: {sc_meta.get('errors')}, tiếp tục dùng fallback.")

    # 7. Render lại video clip preview cho b1
    emit_log("info", f"[Merge Batches] Đang render lại clip xem trước cho {b1.id}...")
    sentence_offset = 0
    for idx in range(found_idx1):
        sentence_offset += len(project.batches[idx].sentences)

    from lecture_illustrator.visual_renderer import render_single_batch_complete
    res_clip, b_hash = render_single_batch_complete(
        batch=b1,
        workspace_dir=workspace_dir,
        config=cfg,
        sentence_offset=sentence_offset,
        force_rerender=True,
    )

    if res_clip and res_clip.exists():
        b1.scene_video = str(res_clip)

    project.batches[found_idx1] = b1
    try:
        proj_path.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
        emit_log("info", f"[Merge Batches] Đã lưu cập nhật dự án vào {proj_path.name}")
    except Exception as e:
        emit_log("error", f"Không thể lưu project JSON: {e}")
        return 1

    emit_json({
        "type": "result",
        "action": "merge_batches",
        "batch_id": b1.id,
        "merged_with_id": removed_batch_id,
        "total_batches": len(project.batches),
        "html_path": str(out_html) if out_html.exists() else "",
        "scene_video": b1.scene_video,
        "status": "success",
    })
    return 0


def run_sync_subtitles_flow(args: argparse.Namespace) -> int:
    """Luồng 6: Đồng bộ và dịch phụ đề phụ cho toàn bộ project, cập nhật các file .ass tương đối."""
    proj_file = None
    if args.project_file:
        proj_file = Path(args.project_file).resolve()
    elif args.workspace:
        proj_file = Path(args.workspace).resolve() / "lecture_project.json"

    if not proj_file or not proj_file.exists():
        emit_log("error", f"Không tìm thấy file dự án: {proj_file}")
        return 1

    workspace_dir = proj_file.parent
    data = json.loads(proj_file.read_text(encoding="utf-8"))
    project = LectureProject.from_dict(data)

    if getattr(args, "subtitle_mode", None):
        project.config.subtitle_mode = args.subtitle_mode
    if getattr(args, "secondary_lang", None):
        project.config.secondary_lang = args.secondary_lang
    if getattr(args, "subtitle_secondary_show", None) is not None:
        project.config.subtitle_secondary_show = bool(args.subtitle_secondary_show != "false")

    all_sents = []
    for b in project.batches:
        for s in getattr(b, "sentences", []):
            all_sents.append(s)

    from lecture_illustrator.scene_planner import translate_secondary_subtitles
    translate_secondary_subtitles(
        all_sents,
        project.config,
        api_key=getattr(args, "api_key", None),
        model=getattr(args, "model", None),
        base_url=getattr(args, "base_url", None),
    )

    # Cập nhật lại các file ASS batch và file ASS toàn cục
    scenes_dir = workspace_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    vw = int(project.video_width or 1920)
    vh = int(project.video_height or 1080)
    from lecture_illustrator.subtitles import generate_batch_ass, generate_lecture_ass

    for b in project.batches:
        b_ass = scenes_dir / f"{b.id}.ass"
        generate_batch_ass(b, b_ass, project.config, video_width=vw, video_height=vh)

    ass_path = workspace_dir / "lecture_subtitles.ass"
    generate_lecture_ass(project.batches, ass_path, project.config, video_width=vw, video_height=vh)

    proj_file.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
    emit_log("info", f"Đã hoàn thành đồng bộ phụ đề song ngữ cho {len(project.batches)} phân cảnh!")
    emit_json({
        "type": "result",
        "action": "sync_subtitles",
        "batch_count": len(project.batches),
        "sentence_count": len(all_sents),
        "status": "success",
    })
    return 0


def _recalculate_project_timeline(project: LectureProject) -> None:
    """Tự động dồn lại mốc thời gian start_sec, end_sec của toàn bộ các batch trong project.
    Đồng thời cập nhật mốc start, end cho từng câu con bên trong mỗi batch."""
    curr_t = 0.0
    for b in project.batches:
        b.start_sec = round(curr_t, 3)
        dur = float(getattr(b, "scene_duration", 0.0) or (b.end_sec - b.start_sec) or 3.0)
        dur = max(0.5, dur)
        b.scene_duration = round(dur, 3)
        b.end_sec = round(curr_t + dur, 3)

        sents = getattr(b, "sentences", []) or []
        if sents:
            s_curr = 0.0
            for s in sents:
                s_dur = float(s.get("duration", 0.0) or 0.0)
                if s_dur <= 0:
                    s_dur = round(dur / max(1, len(sents)), 3)
                    s["duration"] = s_dur
                s["start"] = round(s_curr, 3)
                s["end"] = round(s_curr + s_dur, 3)
                s_curr = s["end"]
        curr_t = b.end_sec


def run_sync_batch_audio_flow(args: argparse.Namespace) -> int:
    """Luồng: Tạo mới, cập nhật thoại/TTS hoặc xóa batch trong kịch bản và dồn lại timeline."""
    proj_path = None
    if getattr(args, "project_file", None):
        proj_path = Path(args.project_file).resolve()
    elif getattr(args, "workspace", None):
        proj_path = Path(args.workspace).resolve() / "lecture_project.json"

    if not proj_path or not proj_path.exists():
        emit_log("error", f"Không tìm thấy file kịch bản lecture_project.json: {proj_path}")
        return 1

    workspace_dir = proj_path.parent
    try:
        data = json.loads(proj_path.read_text(encoding="utf-8"))
        project = LectureProject.from_dict(data)
    except Exception as e:
        emit_log("error", f"Lỗi đọc file project: {e}")
        return 1

    cfg = project.config
    action = getattr(args, "action", "update") or "update"
    batch_id = getattr(args, "batch_id", None)
    text = (getattr(args, "text", "") or "").strip()

    tts_dir = workspace_dir / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)
    voice = getattr(cfg, "tts_voice", "ban_mai") or "ban_mai"
    speed = float(getattr(cfg, "tts_speed", 1.15) or 1.15)

    from utils.movie_review_tts import MovieReviewTTS

    if action == "create":
        if not batch_id:
            idx_counter = len(project.batches) + 1
            existing_ids = {b.id for b in project.batches}
            batch_id = f"batch_{idx_counter:03d}"
            while batch_id in existing_ids:
                idx_counter += 1
                batch_id = f"batch_{idx_counter:03d}"

        out_audio = tts_dir / f"{batch_id}.mp3"
        try:
            dur = MovieReviewTTS.synthesize_single(text=text, out_file=out_audio, voice=voice, speed_factor=speed)
            dur = round(float(dur), 3) if dur and dur > 0 else 3.5
        except Exception as e:
            emit_log("warn", f"Lỗi sinh giọng TTS: {e}. Dùng thời lượng mặc định 3.5s")
            dur = 3.5

        new_batch = LectureBatch(
            id=batch_id,
            start_sec=0.0,
            end_sec=dur,
            transcript_original=text,
            transcript_translated=text,
            scene_duration=dur,
            step_starts=[0.0],
            sentences=[
                {
                    "index": 0,
                    "text": text,
                    "text_orig": text,
                    "start": 0.0,
                    "end": dur,
                    "duration": dur,
                    "audio_file": out_audio.name,
                }
            ],
            scene={"template": "bullet_list", "title": text[:30], "steps": []},
            educational_intent="PROCESS",
        )

        insert_at = getattr(args, "insert_at", None)
        if insert_at is not None and 0 <= int(insert_at) <= len(project.batches):
            project.batches.insert(int(insert_at), new_batch)
        else:
            project.batches.append(new_batch)

        _recalculate_project_timeline(project)
        emit_log("info", f"[Sync Audio] Đã tạo thành công phân cảnh mới {batch_id} (thời lượng {dur}s)")

    elif action == "update":
        if not batch_id:
            emit_log("error", "Thiếu tham số --batch-id để cập nhật")
            return 1

        target_batch = None
        for b in project.batches:
            if b.id == batch_id:
                target_batch = b
                break

        if not target_batch:
            emit_log("error", f"Không tìm thấy batch: {batch_id}")
            return 1

        if text:
            target_batch.transcript_translated = text
            out_audio = tts_dir / f"{batch_id}.mp3"
            try:
                dur = MovieReviewTTS.synthesize_single(text=text, out_file=out_audio, voice=voice, speed_factor=speed)
                dur = round(float(dur), 3) if dur and dur > 0 else 3.5
            except Exception as e:
                emit_log("warn", f"Lỗi sinh giọng TTS: {e}. Giữ nguyên thời lượng cũ")
                dur = target_batch.scene_duration or 3.5

            target_batch.scene_duration = dur
            target_batch.sentences = [
                {
                    "index": 0,
                    "text": text,
                    "text_orig": target_batch.transcript_original or text,
                    "start": 0.0,
                    "end": dur,
                    "duration": dur,
                    "audio_file": out_audio.name,
                }
            ]
            target_batch.step_starts = [0.0]

        _recalculate_project_timeline(project)
        emit_log("info", f"[Sync Audio] Đã cập nhật thoại & giọng đọc cho {batch_id}")

    elif action == "delete":
        if not batch_id:
            emit_log("error", "Thiếu tham số --batch-id để xóa")
            return 1

        if len(project.batches) <= 1:
            emit_log("error", "Không thể xóa phân cảnh duy nhất còn lại của dự án.")
            return 1

        target_idx = -1
        for idx, b in enumerate(project.batches):
            if b.id == batch_id:
                target_idx = idx
                break

        if target_idx == -1:
            emit_log("error", f"Không tìm thấy batch để xóa: {batch_id}")
            return 1

        project.batches.pop(target_idx)
        _recalculate_project_timeline(project)

        # Dọn dẹp cache của batch bị xóa
        scenes_dir = workspace_dir / "scenes"
        if scenes_dir.exists():
            for f in scenes_dir.glob(f"{batch_id}*"):
                try:
                    f.unlink()
                except OSError:
                    pass

        emit_log("info", f"[Sync Audio] Đã xóa phân cảnh {batch_id} và dồn lại timeline.")

    else:
        emit_log("error", f"Hành động không hợp lệ: {action}")
        return 1

    try:
        proj_path.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
        emit_log("info", f"[Sync Audio] Đã lưu project vào {proj_path.name}")
    except Exception as e:
        emit_log("error", f"Không thể lưu project JSON: {e}")
        return 1

    emit_json({
        "type": "result",
        "action": "sync_batch_audio",
        "sub_action": action,
        "batch_id": batch_id,
        "total_batches": len(project.batches),
        "status": "success",
    })
    return 0


def main():
    parser = argparse.ArgumentParser(description="AI Lecture Illustrator Orchestrator")
    parser.add_argument("--mode", choices=["analyze", "render", "reauthor_batch", "import_batch_html", "merge_batches", "sync_subtitles", "sync_batch_audio"], required=True, help="Chế độ chạy")
    parser.add_argument("--action", choices=["create", "update", "delete"], default="update", help="Hành động khi dùng sync_batch_audio")
    parser.add_argument("--text", type=str, default="", help="Nội dung văn bản thoại khi tạo hoặc sửa phân cảnh")
    parser.add_argument("--insert-at", type=int, default=None, help="Vị trí chèn phân cảnh mới (0-indexed)")
    parser.add_argument("--input", type=str, help="Đường dẫn file đầu vào bài giảng (video, audio, text)")
    parser.add_argument("--video", type=str, help="Đường dẫn file video bài giảng nguồn (tương thích ngược)")
    parser.add_argument("--raw-article", action="store_true", help="Bật chế độ AI biên soạn bài giảng từ tài liệu/bài viết thô")
    parser.add_argument("--workspace", type=str, help="Thư mục làm việc của dự án")
    parser.add_argument("--project-name", type=str, help="Tên dự án bài giảng")
    parser.add_argument("--project-file", type=str, help="Đường dẫn file lecture_project.json")
    parser.add_argument("--output", type=str, help="Đường dẫn file video đầu ra .mp4")
    parser.add_argument("--batch-id", type=str, help="ID phân đoạn cần xử lý (ví dụ: batch_003)")
    parser.add_argument("--merge-with-id", type=str, help="ID phân đoạn thứ hai cần gộp (mặc định là phân đoạn tiếp theo)")
    parser.add_argument("--html-file", type=str, help="Đường dẫn file HTML cần import từ ngoài vào batch")
    parser.add_argument("--feedback", type=str, default="", help="Yêu cầu chỉnh sửa của người dùng cho AI")

    # Tham số AI & Kịch bản
    parser.add_argument("--api-key", type=str, help="Google Gemini hoặc LLM API Key")
    parser.add_argument("--base-url", type=str, help="OpenAI-compatible base URL")
    parser.add_argument("--model", type=str, default=None, help="AI Model")
    parser.add_argument("--translator-type", type=str, default=None, help="Provider dịch thuật (ollama/openai/gemini)")
    parser.add_argument("--source-lang", type=str, default="auto", help="Ngôn ngữ nguồn")
    parser.add_argument("--target-lang", type=str, default="vi", help="Ngôn ngữ đích")
    parser.add_argument("--secondary-lang", type=str, default="en", help="Ngôn ngữ phụ dòng 2 (song ngữ)")
    parser.add_argument("--pronoun-mode", type=str, default="formal", help="Ngôi xưng hô: formal / teacher_student / casual")

    # Tham số Audio, TTS & Phụ đề
    parser.add_argument("--voice-mode", choices=["original", "tts_dub"], default="tts_dub", help="original hoặc tts_dub")
    parser.add_argument("--tts-voice", type=str, default=None, help="Giọng TTS: ban_mai / hoai_my / nam_minh")
    parser.add_argument("--tts-speed", type=float, default=None, help="Tốc độ đọc TTS (1.0 - 2.0)")
    parser.add_argument("--bgm-volume", type=float, default=None, help="Âm lượng hạ nhạc nền Ducking")
    parser.add_argument("--voice-volume", type=float, default=None, help="Âm lượng giọng đọc TTS")
    parser.add_argument("--burn-subtitles", type=str, default="true", help="true/false")
    parser.add_argument("--subtitle-mode", choices=["single", "bilingual"], default="bilingual", help="Kiểu sub")
    parser.add_argument("--subtitle-secondary-show", type=str, default="true", help="Hiện dòng sub phụ: true/false")
    parser.add_argument("--subtitle-order", choices=["primary_top", "primary_bottom", "secondary_top"], default="primary_top", help="Thứ tự dòng sub")

    # Tham số Phông chữ & Subtitle ASS
    parser.add_argument("--font-name", type=str, help="Tên phông chữ ASS")
    parser.add_argument("--secondary-font-name", type=str, help="Tên phông chữ phụ ASS (tiếng gốc)")
    parser.add_argument("--font-size", type=str, help="Cỡ chữ ASS")
    parser.add_argument("--font-color", type=str, help="Màu chữ ASS (&H00FFFFFF)")
    parser.add_argument("--outline-color", type=str, help="Màu viền chữ ASS (&H00000000)")
    parser.add_argument("--secondary-font-color", type=str, help="Màu chữ phụ ASS (&H00E7E1DC)")
    parser.add_argument("--secondary-scale", type=float, help="Tỷ lệ cỡ chữ phụ so với chính (0.5 - 1.0)")
    parser.add_argument("--subtitle-region", type=str, default=None, help="Tọa độ vùng phụ đề [top,left,bottom,right] phân cách bằng dấu phẩy")
    parser.add_argument("--video-bitrate", type=str, help="Bitrate video xuất ra (ví dụ: 6000k, 4.0M)")
    parser.add_argument("--watermark-enabled", type=str, help="Bật watermark: true/false")
    parser.add_argument("--watermark-path", type=str, help="Đường dẫn file ảnh watermark logo")

    # Tham số Inpaint & Xóa Sub
    parser.add_argument("--enable-inpaint", type=str, help="Bật inpaint: true/false")
    parser.add_argument("--inpaint-engine", type=str, help="Engine inpaint: ffmpeg_blur / box_color / apple_vision_inpaint / opencv")
    parser.add_argument("--inpaint-blur-radius", type=int, help="Độ mờ kính blur radius (5-50)")
    parser.add_argument("--box-bg-color", type=str, help="Màu nền hộp che (#000000)")
    parser.add_argument("--box-opacity", type=float, help="Độ mờ hộp nền (0.1 - 1.0)")
    parser.add_argument("--inpaint-method", type=str, help="Thuật toán inpaint: vertical_gradient / navier_stokes / telea")

    # Tham số Visual & Tỉ lệ khung hình
    parser.add_argument("--layout-preset", choices=["pip", "full", "split"], default="pip", help="Bố cục visual")
    parser.add_argument("--aspect-ratio", choices=["16:9", "9:16"], default=None, help="Tỉ lệ khung hình: 16:9 hoặc 9:16")
    parser.add_argument("--ai-authored", type=str, default=None, help="Bật AI tự viết HTML cảnh minh họa: true/false")
    parser.add_argument("--html-author-model", type=str, default=None, help="Model LLM riêng cho AI tự viết HTML")
    parser.add_argument("--html-author-base-url", type=str, default=None, help="Base URL riêng cho AI tự viết HTML")
    parser.add_argument("--html-author-api-key", type=str, default=None, help="API Key riêng cho AI tự viết HTML")
    parser.add_argument("--num-workers", type=int, default=None, help="Số luồng xử lý song song (multi-threads / workers)")

    args = parser.parse_args()

    if args.mode == "analyze":
        if not args.input and not args.video:
            parser.error("--input hoặc --video là bắt buộc khi dùng --mode analyze")
        sys.exit(run_analyze_flow(args))
    elif args.mode == "render":
        if not args.project_file:
            parser.error("--project-file là bắt buộc khi dùng --mode render")
        sys.exit(run_render_flow(args))
    elif args.mode == "reauthor_batch":
        sys.exit(run_reauthor_batch_flow(args))
    elif args.mode == "import_batch_html":
        sys.exit(run_import_batch_html_flow(args))
    elif args.mode == "merge_batches":
        sys.exit(run_merge_batches_flow(args))
    elif args.mode == "sync_subtitles":
        sys.exit(run_sync_subtitles_flow(args))
    elif args.mode == "sync_batch_audio":
        sys.exit(run_sync_batch_audio_flow(args))


if __name__ == "__main__":
    main()


