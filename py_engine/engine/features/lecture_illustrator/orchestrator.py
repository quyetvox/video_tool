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

try:
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
except ModuleNotFoundError:
    import sys as _sys
    from pathlib import Path as _P
    _sys.path.insert(0, str(next(p.parent for p in _P(__file__).resolve().parents if p.name == "engine")))
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT_DIR = _ENGINE_DIR.parent.resolve()
ENGINE_DIR = _ENGINE_DIR.resolve()
sys.path.insert(0, str(ENGINE_DIR))
sys.path.insert(0, str(ROOT_DIR))

from engine.shared.ffmpeg_utils import FFmpegUtils, ensure_system_path
ensure_system_path()

from engine.features.lecture_illustrator.common import (
    emit_json,
    emit_log,
    emit_progress,
    resolve_hardware_config,
    safe_ensure_dir,
)
from engine.features.lecture_illustrator.models import (
    LectureProject,
    LectureProjectConfig,
    LectureBatch,
    BatchPrompts,
    BatchActiveAsset,
)
from engine.features.lecture_illustrator.scene_planner import (
    build_timeline,
    group_sentences,
    plan_scenes,
    stitch_sentence_boundaries,
    synthesize_sentences,
    translate_sentences,
)
from engine.features.lecture_illustrator.visual_renderer import render_lecture_video


from engine.features.lecture_illustrator.text_script_parser import parse_text_file_to_sentences


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
                from engine.shared.repetition_cleaner import RepetitionCleaner
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
        from engine.core.plugin_loader import PluginLoader
        from engine.shared.repetition_cleaner import RepetitionCleaner
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
            from engine.features.lecture_illustrator.knowledge_extractor import call_llm_api
            from engine.features.lecture_illustrator.common import clean_json_str
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
    from engine.features.lecture_illustrator.common import load_engine_config
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
        if getattr(args, "subtitle_show_primary", None) is not None:
            cfg.subtitle_show_primary = bool(args.subtitle_show_primary != "false")
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
        yaml_pri_show = bool(cfg_yaml.get("subtitle", {}).get("show_primary", True))
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
            # pyrefly: ignore[unexpected-keyword]
            subtitle_show_primary=bool(getattr(args, "subtitle_show_primary", str(yaml_pri_show)) != "false"),
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
        sentences = stitch_sentence_boundaries(sentences)
        for i, s in enumerate(sentences):
            s["index"] = i

    # 2. Gom nhóm câu
    groups = group_sentences(sentences, api_key=api_key, model=model, base_url=base_url)
    emit_log("info", f"Gom {len(sentences)} câu thành {len(groups)} cụm tri thức minh họa.")

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


def ensure_project_audio_and_timeline_sync(
    project: LectureProject,
    workspace_dir: Path,
    force_resynth: bool = False,
) -> bool:
    """
    Đảm bảo 100% âm thanh TTS của mọi câu trong project khớp với tts_voice và tts_speed hiện tại.
    Nếu phát hiện lệch tốc độ/giọng đọc hoặc thiếu file, tự động tái tổng hợp và dồn lại mốc timeline.
    """
    from engine.shared.movie_review_tts import MovieReviewTTS
    from engine.features.lecture_illustrator.common import (
        load_audio_manifest,
        save_audio_manifest,
        compute_sentence_audio_fingerprint,
        LEAD_IN,
        SENTENCE_GAP,
        TAIL,
    )

    tts_dir = workspace_dir / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)
    scenes_dir = workspace_dir / "scenes"

    cfg = project.config
    voice = getattr(cfg, "tts_voice", "ban_mai") or "ban_mai"
    if (getattr(cfg, "target_lang", "vi") or "").lower().startswith("en"):
        if str(voice).lower().startswith("vi-") or str(voice).lower() in ("ban_mai", "hoai_my", "nam_minh", "vi"):
            voice = "en-US-JennyNeural"
            cfg.tts_voice = voice
    speed = float(getattr(cfg, "tts_speed", 1.15) or 1.15)

    manifest = load_audio_manifest(tts_dir)
    modified = False

    all_sents = []
    for b in project.batches:
        for s in getattr(b, "sentences", []):
            all_sents.append(s)

    if not all_sents:
        return False

    outdated_entries = []
    for idx, s in enumerate(all_sents):
        audio_name = s.get("audio_file") or f"s_{idx:04d}.mp3"
        s["audio_file"] = audio_name
        audio_file = tts_dir / audio_name

        text = str(s.get("text", "")).strip()
        sig_hash = compute_sentence_audio_fingerprint(text, voice, speed)

        entry = manifest.get(audio_name)
        cached_hash = entry.get("hash") if isinstance(entry, dict) else entry
        cached_dur = float(entry.get("duration", 0.0)) if isinstance(entry, dict) else 0.0

        is_valid = (
            not force_resynth
            and audio_file.exists()
            and audio_file.stat().st_size >= 300
            and cached_hash == sig_hash
            and cached_dur > 0.1
        )
        if not is_valid:
            outdated_entries.append((idx, s, audio_file, text, sig_hash))

    if outdated_entries or force_resynth:
        emit_log("info", f"[Audio Sync] Tự động đồng bộ {len(outdated_entries)}/{len(all_sents)} câu theo giọng '{voice}' và tốc độ {speed}x...")
        modified = True

        for idx, s, audio_file, text, sig_hash in outdated_entries:
            if s.get("skip_tts"):
                cmd = [
                    "ffmpeg", "-y", "-loglevel", "error",
                    "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                    "-t", "2.0", "-q:a", "9", "-acodec", "libmp3lame", str(audio_file)
                ]
                subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                dur = 2.0
            else:
                dur = MovieReviewTTS.synthesize_single(
                    text=text,
                    out_file=audio_file,
                    voice=voice,
                    speed_factor=speed,
                )
            eff_dur = dur if dur > 0 else 1.5
            s["duration"] = round(eff_dur, 3)
            manifest[audio_file.name] = {
                "hash": sig_hash,
                "voice": voice,
                "speed": speed,
                "duration": round(eff_dur, 3),
            }

        save_audio_manifest(tts_dir, manifest)

        # Cập nhật timeline, step_starts và scene_duration theo thời lượng audio thực tế
        t = 0.0
        for b in project.batches:
            step_starts = []
            local = LEAD_IN
            b.start_sec = round(t, 3)
            for s in getattr(b, "sentences", []):
                audio_file = tts_dir / str(s.get("audio_file", ""))
                d = float(s.get("duration", 0.0))
                if d <= 0.1:
                    entry = manifest.get(audio_file.name)
                    if isinstance(entry, dict) and entry.get("duration"):
                        d = float(entry["duration"])
                    else:
                        d = MovieReviewTTS.get_audio_duration(audio_file) if audio_file.exists() else 2.0
                    s["duration"] = round(d if d > 0 else 1.5, 3)
                step_starts.append(round(local, 3))
                s["start"] = round(t + local, 3)
                s["end"] = round(t + local + d, 3)
                local += d + SENTENCE_GAP
            scene_duration = local - SENTENCE_GAP + TAIL
            b.step_starts = step_starts
            b.scene_duration = round(scene_duration, 3)
            b.end_sec = round(t + scene_duration, 3)
            t += scene_duration
        project.video_duration = round(t, 3)

        # Xóa batch manifest để ép dựng lại visual khớp step_starts mới
        manifest_f = scenes_dir / ".batch_manifest.json"
        if manifest_f.exists():
            try:
                manifest_f.unlink()
            except Exception:
                pass

    return modified


def run_render_flow(args: argparse.Namespace) -> int:
    """Luồng 2: Đọc lecture_project.json và xuất video hoàn chỉnh."""
    proj_path = Path(args.project_file).resolve()
    if not proj_path.exists():
        emit_log("error", f"File kịch bản bài giảng không tồn tại: {proj_path}")
        return 1

    workspace_dir = proj_path.parent
    data = json.loads(proj_path.read_text(encoding="utf-8"))
    project = LectureProject.from_dict(data)

    if getattr(args, "target_lang", None):
        project.config.target_lang = str(args.target_lang)
    if getattr(args, "secondary_lang", None) is not None:
        project.config.secondary_lang = str(args.secondary_lang)
    if getattr(args, "tts_voice", None):
        project.config.tts_voice = str(args.tts_voice)
    if getattr(args, "tts_speed", None) is not None:
        try:
            project.config.tts_speed = float(args.tts_speed)
        except (ValueError, TypeError):
            pass
    if getattr(args, "burn_subtitles", None) is not None:
        project.config.burn_subtitles = str(args.burn_subtitles).lower() in ("true", "1", "yes")
    if getattr(args, "subtitle_mode", None):
        project.config.subtitle_mode = str(args.subtitle_mode)
    if getattr(args, "subtitle_show_primary", None) is not None:
        project.config.subtitle_show_primary = str(args.subtitle_show_primary).lower() in ("true", "1", "yes")
    if getattr(args, "subtitle_secondary_show", None) is not None:
        project.config.subtitle_secondary_show = str(args.subtitle_secondary_show).lower() in ("true", "1", "yes")
    if getattr(args, "subtitle_order", None):
        project.config.subtitle_order = str(args.subtitle_order)
    if getattr(args, "font_name", None):
        project.config.font_name = str(args.font_name)
    if getattr(args, "font_size", None):
        project.config.font_size = str(args.font_size)
    if getattr(args, "num_workers", None) is not None:
        project.config.num_workers = int(args.num_workers)
    if getattr(args, "fps", None) is not None:
        project.config.fps = int(args.fps)

    # Nạp config.yaml toàn cục để dự phòng API key và model nếu CLI args không truyền
    from engine.features.lecture_illustrator.common import load_engine_config
    cfg_yaml = load_engine_config(workspace_dir)
    t_cfg = cfg_yaml.get("translator", {}) if isinstance(cfg_yaml, dict) else {}
    fallback_api_key = getattr(args, "api_key", None) or t_cfg.get("api_key") or os.environ.get("GEMINI_API_KEY", "")
    fallback_model = getattr(args, "model", None) or t_cfg.get("model") or "gemma4:31b-cloud"
    fallback_base_url = getattr(args, "base_url", None) or t_cfg.get("base_url") or "http://localhost:11434"

    # Tự động bật burn_subtitles nếu đang ở chế độ song ngữ hoặc có ngôn ngữ phụ
    sec_lang = (project.config.secondary_lang or "").strip().lower()
    target_lang = (project.config.target_lang or "vi").strip().lower()
    if project.config.subtitle_mode in ("bilingual", "primary_only") or (sec_lang and sec_lang != "none"):
        if not getattr(project.config, "burn_subtitles", True):
            project.config.burn_subtitles = True
            emit_log("info", "[Config Sync] Tự động kích hoạt burn_subtitles=True cho chế độ phụ đề bài giảng.")

    # Kiểm tra & Hoán đổi ngôn ngữ (Smart Swap) nếu kịch bản bị ngược chiều
    def _has_vietnamese(txt: str) -> bool:
        return bool(re.search(r'[àáảãạăắằẳẵặâấầẩẫậđèéẻẽẹêếềểễệìíỉĩịòóỏõọôốồổỗộơớờởỡợùúủũụưứừửữựỳýỷỹỵ]', txt, re.IGNORECASE))

    all_sents = []
    for b in project.batches:
        for s in getattr(b, "sentences", []):
            all_sents.append(s)

    project_modified = False
    needs_swap = False

    if all_sents and sec_lang and sec_lang not in ("none", target_lang):
        sample_pri = str(all_sents[0].get("text", "")).strip()
        sample_sec = str(all_sents[0].get("text_secondary", "")).strip()

        # TH1: Target là EN, Sec là VI nhưng câu text chính đang là tiếng Việt, text_secondary là tiếng Anh
        if target_lang.startswith("en") and sec_lang.startswith("vi"):
            if _has_vietnamese(sample_pri) and not _has_vietnamese(sample_sec) and len(sample_sec) > 3:
                needs_swap = True
        # TH2: Target là VI, Sec là EN nhưng câu text chính đang là tiếng Anh, text_secondary là tiếng Việt
        elif target_lang.startswith("vi") and sec_lang.startswith("en"):
            if not _has_vietnamese(sample_pri) and _has_vietnamese(sample_sec) and len(sample_pri) > 3:
                needs_swap = True

    if needs_swap:
        emit_log("info", f"[Smart Swap] Phát hiện kịch bản bị ngược chiều (Target={target_lang}, Sec={sec_lang}). Đang tự động hoán đổi Primary ⇄ Secondary...")
        for b in project.batches:
            for s in getattr(b, "sentences", []):
                old_pri = s.get("text", "")
                old_sec = s.get("text_secondary", "")
                s["text"] = old_sec
                s["text_secondary"] = old_pri
            if b.transcript_original and b.transcript_translated and b.transcript_original != b.transcript_translated:
                b.transcript_original, b.transcript_translated = b.transcript_translated, b.transcript_original

        # Nếu target là tiếng Anh, chuyển tts_voice sang giọng tiếng Anh nếu đang là giọng Việt
        if target_lang.startswith("en"):
            v_curr = str(project.config.tts_voice or "").lower()
            if v_curr.startswith("vi-") or v_curr in ("ban_mai", "hoai_my", "nam_minh", "vi"):
                project.config.tts_voice = "en-US-JennyNeural"
                emit_log("info", f"[Voice Sync] Tự động chuyển tts_voice sang '{project.config.tts_voice}'.")

    # Đảm bảo audio TTS và timeline luôn đồng bộ chính xác theo tts_speed và tts_voice hiện tại
    audio_synced = ensure_project_audio_and_timeline_sync(project, workspace_dir, force_resynth=needs_swap)
    if audio_synced or needs_swap:
        project_modified = True

    # Tự động đồng bộ/dịch text_secondary nếu bật song ngữ nhưng phụ đề phụ chưa được dịch
    if project.config.subtitle_mode == "bilingual" and sec_lang and sec_lang not in ("none", target_lang):
        needs_sec_trans = False
        for s in all_sents:
            sec = str(s.get("text_secondary", "")).strip()
            pri = str(s.get("text", "")).strip()
            if pri and (not sec or sec == pri):
                needs_sec_trans = True
                break
        if needs_sec_trans and all_sents:
            from engine.features.lecture_illustrator.scene_planner import translate_secondary_subtitles
            emit_log("info", f"Phát hiện câu phụ chưa có bản dịch '{sec_lang}', tiến hành tự động dịch...")
            translate_secondary_subtitles(
                all_sents,
                project.config,
                api_key=fallback_api_key,
                model=fallback_model,
                base_url=fallback_base_url,
            )
            project_modified = True

    if project_modified:
        try:
            proj_path.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
            emit_log("info", "Đã cập nhật đồng bộ file dự án lecture_project.json thành công.")
        except Exception as e:
            emit_log("warn", f"Không thể lưu project JSON: {e}")

    # Tự động cho AI viết mã HTML animation cho các batch còn thiếu nếu bật ai_authored
    if getattr(project.config, "ai_authored", True):
        scenes_dir = workspace_dir / "scenes"
        scenes_dir.mkdir(parents=True, exist_ok=True)
        from engine.features.lecture_illustrator.scene_author import author_scene_with_retry

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
            from engine.features.lecture_illustrator.common import resolve_hardware_config
            from engine.features.lecture_illustrator.scene_author import SceneAuthorSession
            from concurrent.futures import ThreadPoolExecutor, as_completed
            import threading

            chunk_size = 3
            chunks = [batches_to_author[i:i + chunk_size] for i in range(0, len(batches_to_author), chunk_size)]
            workers, _, _ = resolve_hardware_config(project.config)
            author_workers = min(max(1, workers), len(chunks))
            emit_log("info", f"[Auto-Author] Phát hiện {len(batches_to_author)}/{len(project.batches)} cảnh chưa có animation HTML. AI đang tạo animation theo cụm Rolling Window ({len(chunks)} cụm, {author_workers} workers)...")

            completed_count = 0
            count_lock = threading.Lock()

            def _author_chunk_task(chunk_items: list):
                nonlocal completed_count
                session = SceneAuthorSession(
                    window_size=len(chunk_items),
                    api_key=author_api_key,
                    model=author_model,
                    base_url=author_base_url,
                )
                chunk_results = []
                for orig_idx, b in chunk_items:
                    out_html = scenes_dir / f"{b.id}.html"
                    sents = getattr(b, "sentences", []) or []
                    sents_text = [s.get("text", "") for s in sents if isinstance(s, dict)]
                    if not sents_text:
                        sents_text = [b.transcript_translated or b.transcript_original]
                    step_starts = getattr(b, "step_starts", []) or [0.0]
                    scene_dur = float(getattr(b, "scene_duration", 0.0) or (b.end_sec - b.start_sec) or 3.0)
                    fallback_tmpl = b.scene.get("template", "bullet_list") if isinstance(b.scene, dict) else "bullet_list"
                    scene_title = b.scene.get("title") if isinstance(b.scene, dict) else None
                    scene_concept = b.scene.get("visual_concept") if isinstance(b.scene, dict) else None
                    scene_diag = b.scene.get("diagram_type") if isinstance(b.scene, dict) else None

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
                        title=scene_title,
                        concept=scene_concept,
                        diagram_type=scene_diag,
                        session=session,
                    )

                    with count_lock:
                        completed_count += 1
                        curr_completed = completed_count

                    emit_progress(
                        0.05 + 0.50 * (curr_completed / len(batches_to_author)),
                        f"AI đang viết mã HTML cho cảnh {curr_completed}/{len(batches_to_author)} ({b.id})..."
                    )
                    chunk_results.append((orig_idx, b, sc_data))
                return chunk_results

            with ThreadPoolExecutor(max_workers=author_workers) as executor:
                futures = [executor.submit(_author_chunk_task, ch) for ch in chunks]
                for fut in as_completed(futures):
                    for orig_idx, b, sc_data in fut.result():
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
    from engine.features.lecture_illustrator.common import load_engine_config
    root_cfg = load_engine_config(workspace_dir)
    trans_cfg = root_cfg.get("translator", {}) if isinstance(root_cfg, dict) else {}

    api_key = args.html_author_api_key or args.api_key or cfg.html_author_api_key or getattr(cfg, "api_key", None) or trans_cfg.get("api_key")
    model = args.html_author_model or args.model or cfg.html_author_model or trans_cfg.get("model") or "gemini-flash-lite-latest"
    base_url = args.html_author_base_url or args.base_url or cfg.html_author_base_url or trans_cfg.get("base_url")

    refine_existing_html = None
    if getattr(args, "refine", False) and out_html.exists():
        try:
            bak_path = out_html.with_suffix(".html.bak")
            existing_content = out_html.read_text(encoding="utf-8")
            bak_path.write_text(existing_content, encoding="utf-8")
            refine_existing_html = existing_content
            emit_log("info", f"[Reauthor] Đã sao lưu HTML cũ vào {bak_path.name} và bật chế độ AI Tinh Chỉnh.")
        except Exception as e:
            emit_log("warn", f"[Reauthor] Không thể tạo file backup .bak: {e}")

    from engine.features.lecture_illustrator.scene_author import author_scene_with_retry
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
        refine_existing_html=refine_existing_html,
        title=target_batch.scene.get("title") if isinstance(target_batch.scene, dict) else None,
        concept=target_batch.scene.get("visual_concept") if isinstance(target_batch.scene, dict) else None,
        diagram_type=target_batch.scene.get("diagram_type") if isinstance(target_batch.scene, dict) else None,
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
    from engine.features.lecture_illustrator.visual_renderer import render_single_batch_complete
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


def run_reauthor_batch_multi_flow(args: argparse.Namespace) -> int:
    """Luồng: Tái tạo HTML đồng thời cho danh sách nhiều batch qua ThreadPoolExecutor theo số lượng workers."""
    raw_ids = getattr(args, "batch_ids", "") or ""
    batch_ids = [bid.strip() for bid in raw_ids.split(",") if bid.strip()]
    if not batch_ids:
        emit_log("error", "Thiếu danh sách --batch-ids (phân cách bằng dấu phẩy)")
        return 1

    proj_file = None
    if getattr(args, "project_file", None):
        proj_file = Path(args.project_file).resolve()
    elif getattr(args, "workspace", None):
        proj_file = Path(args.workspace).resolve() / "lecture_project.json"

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
    scenes_dir = workspace_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)

    from engine.features.lecture_illustrator.common import load_engine_config
    root_cfg = load_engine_config(workspace_dir)
    trans_cfg = root_cfg.get("translator", {}) if isinstance(root_cfg, dict) else {}

    api_key = args.html_author_api_key or args.api_key or cfg.html_author_api_key or getattr(cfg, "api_key", None) or trans_cfg.get("api_key")
    model = args.html_author_model or args.model or cfg.html_author_model or trans_cfg.get("model") or "gemini-flash-lite-latest"
    base_url = args.html_author_base_url or args.base_url or cfg.html_author_base_url or trans_cfg.get("base_url")
    cfg_workers = getattr(cfg, "num_workers", None) or root_cfg.get("author_workers") or root_cfg.get("num_workers")
    requested_workers = getattr(args, "num_workers", None) or getattr(args, "workers", None) or cfg_workers or 2

    target_tasks = []
    sentence_offset = 0
    for idx, b in enumerate(project.batches):
        if b.id in batch_ids:
            target_tasks.append((idx, b, sentence_offset))
        sentence_offset += len(getattr(b, "sentences", []) or [])

    if not target_tasks:
        emit_log("warn", f"Không tìm thấy phân cảnh nào khớp với các ID: {batch_ids}")
        return 1

    chunk_size = 3
    chunks = [target_tasks[i:i + chunk_size] for i in range(0, len(target_tasks), chunk_size)]
    workers = max(1, min(int(requested_workers), len(chunks)))

    emit_log("info", f"[Reauthor Multi] Bắt đầu tái tạo {len(batch_ids)} phân cảnh theo cụm Rolling Window ({len(chunks)} cụm, {workers} workers)...")

    import threading
    lock = threading.Lock()
    completed_count = 0
    failed_count = 0
    total_count = len(target_tasks)

    from engine.features.lecture_illustrator.scene_author import author_scene_with_retry, SceneAuthorSession
    from engine.features.lecture_illustrator.visual_renderer import render_single_batch_complete

    def _chunk_worker(chunk_task_list):
        nonlocal completed_count, failed_count
        session = SceneAuthorSession(
            window_size=len(chunk_task_list),
            api_key=api_key,
            model=model,
            base_url=base_url,
        )
        for task in chunk_task_list:
            idx, target_batch, s_offset = task
            out_html = scenes_dir / f"{target_batch.id}.html"

            sents = getattr(target_batch, "sentences", []) or []
            if sents:
                sents_text = [s.get("translated") or s.get("text") or "" for s in sents]
            else:
                sents_text = [target_batch.transcript_translated or target_batch.transcript_original]
            step_starts = getattr(target_batch, "step_starts", []) or [0.0]
            scene_dur = float(getattr(target_batch, "scene_duration", 0.0) or (target_batch.end_sec - target_batch.start_sec) or 3.0)

            emit_log("info", f"[Reauthor Multi] Đang xử lý phân cảnh {target_batch.id}...")
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
                title=target_batch.scene.get("title") if isinstance(target_batch.scene, dict) else None,
                concept=target_batch.scene.get("visual_concept") if isinstance(target_batch.scene, dict) else None,
                diagram_type=target_batch.scene.get("diagram_type") if isinstance(target_batch.scene, dict) else None,
                session=session,
            )

            if ok:
                sc_data["mode"] = "authored"
                sc_data["html_path"] = str(out_html)
                target_batch.scene = sc_data

                try:
                    res_clip, _ = render_single_batch_complete(
                        batch=target_batch,
                        workspace_dir=workspace_dir,
                        config=cfg,
                        sentence_offset=s_offset,
                        force_rerender=True,
                    )
                    if res_clip and res_clip.exists():
                        target_batch.scene_video = str(res_clip)
                except Exception as e:
                    emit_log("warn", f"[Reauthor Multi] Lỗi render clip cho {target_batch.id}: {e}")

                with lock:
                    completed_count += 1
                    project.batches[idx] = target_batch
                    emit_json({
                        "type": "progress",
                        "action": "reauthor_batch_multi",
                        "completed": completed_count,
                        "total": total_count,
                        "batch_id": target_batch.id,
                        "status": "success",
                    })
            else:
                with lock:
                    failed_count += 1
                    emit_log("warn", f"[Reauthor Multi] Không thể tái tạo phân cảnh {target_batch.id}")
                    emit_json({
                        "type": "progress",
                        "action": "reauthor_batch_multi",
                        "completed": completed_count,
                        "total": total_count,
                        "batch_id": target_batch.id,
                        "status": "failed",
                    })

    from concurrent.futures import ThreadPoolExecutor, as_completed
    with ThreadPoolExecutor(max_workers=workers) as executor:
        futures = [executor.submit(_chunk_worker, ch) for ch in chunks]
        for fut in as_completed(futures):
            fut.result()

    try:
        proj_file.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
        emit_log("info", f"[Reauthor Multi] Đã lưu kết quả {total_count} phân cảnh vào {proj_file.name}")
    except Exception as e:
        emit_log("error", f"Không thể lưu project JSON: {e}")
        return 1

    emit_json({
        "type": "result",
        "action": "reauthor_batch_multi",
        "total": total_count,
        "completed": completed_count,
        "failed": failed_count,
        "status": "success" if failed_count == 0 else "partial",
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

    # 1. Tự động sao lưu phiên bản cũ nếu đã tồn tại để có thể hoàn tác
    if out_html.exists() and imported_html_path.resolve() != out_html.resolve():
        bak_file = scenes_dir / f"{target_batch.id}.html.bak"
        try:
            import shutil
            shutil.copy2(out_html, bak_file)
        except Exception as e:
            emit_log("debug", f"Không thể tạo bản sao lưu .bak: {e}")

    # 2. Ghi đè 100% nguyên vẹn mã nguồn HTML thô không qua Calibrator
    emit_log("info", f"[Import HTML] Nạp trực tiếp 100% mã HTML thô vào {target_batch.id} ({scene_dur:.2f}s)...")
    if imported_html_path.resolve() != out_html.resolve():
        try:
            raw_content = imported_html_path.read_text(encoding="utf-8")
            out_html.write_text(raw_content, encoding="utf-8")
        except Exception as e:
            emit_log("error", f"Lỗi khi đọc/ghi file HTML thô: {e}")
            return 1
        if imported_html_path.name.startswith("temp_pasted_") and imported_html_path.exists():
            try:
                imported_html_path.unlink()
            except Exception:
                pass

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
    from engine.features.lecture_illustrator.visual_renderer import render_single_batch_complete
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


def run_import_folder_html_flow(args: argparse.Namespace) -> int:
    """Luồng Import hàng loạt: Quét một folder chứa các file HTML và tự động phân bổ vào các batch dựa theo tên file."""
    if not args.project_file:
        emit_log("error", "Thiếu tham số --project-file")
        return 1
    proj_path = Path(args.project_file).resolve()
    if not proj_path.exists():
        emit_log("error", f"File kịch bản bài giảng không tồn tại: {proj_path}")
        return 1

    if not args.folder_dir:
        emit_log("error", "Thiếu tham số --folder-dir")
        return 1
    folder_path = Path(args.folder_dir).resolve()
    if not folder_path.exists() or not folder_path.is_dir():
        emit_log("error", f"Thư mục HTML không tồn tại hoặc không hợp lệ: {folder_path}")
        return 1

    workspace_dir = proj_path.parent
    data = json.loads(proj_path.read_text(encoding="utf-8"))
    project = LectureProject.from_dict(data)
    cfg = project.config

    if not project.batches:
        emit_log("warn", "Dự án hiện tại chưa có phân cảnh nào.")
        emit_json({
            "type": "result",
            "action": "import_folder_html",
            "total_matched": 0,
            "matched_batches": [],
            "status": "failed",
            "error": "Dự án chưa có phân cảnh nào.",
        })
        return 1

    # 1. Quét toàn bộ file .html / .htm trong folder_path
    html_files = [
        f for f in sorted(folder_path.iterdir())
        if f.is_file() and f.suffix.lower() in [".html", ".htm"]
    ]
    if not html_files:
        emit_log("warn", f"Không tìm thấy file .html hoặc .htm nào trong thư mục: {folder_path}")
        emit_json({
            "type": "result",
            "action": "import_folder_html",
            "total_matched": 0,
            "matched_batches": [],
            "status": "failed",
            "error": "Không tìm thấy file HTML nào trong thư mục.",
        })
        return 1

    emit_log("info", f"[Import Folder] Đã tìm thấy {len(html_files)} file HTML trong {folder_path.name}. Đang phân tích khớp tên...")

    # 2. Thuật toán so khớp từng file với batch tương ứng
    def match_file_to_batch(file_path: Path, batches: List[LectureBatch]) -> Optional[Tuple[int, LectureBatch]]:
        stem = file_path.stem.strip().lower()
        stem_norm = re.sub(r"[\s\-_]+", "_", stem)

        # Cấp 1: Khớp chính xác ID batch (ví dụ "batch_001", "batch_1")
        for idx, b in enumerate(batches):
            b_id_norm = re.sub(r"[\s\-_]+", "_", b.id.strip().lower())
            if b_id_norm == stem_norm:
                return (idx, b)

        # Cấp 2: Khớp tiền tố hoặc chứa ID batch rõ ràng (ví dụ "batch_001_intro", "batch_001_v2")
        for idx, b in enumerate(batches):
            b_id_norm = re.sub(r"[\s\-_]+", "_", b.id.strip().lower())
            if stem_norm.startswith(f"{b_id_norm}_") or stem_norm.endswith(f"_{b_id_norm}"):
                return (idx, b)

        # Cấp 3: Trích xuất số nguyên từ tên file (ví dụ "01", "001", "scene_1", "scene_01", "batch-1", "phan_canh_1", "1")
        m = re.search(r"(?:batch|scene|canh|phan_canh|slide|unit)?_?0*(\d+)", stem_norm)
        if m:
            file_num = int(m.group(1))
            # So khớp với batch có ID chứa số này
            for idx, b in enumerate(batches):
                b_nums = re.findall(r"\d+", b.id)
                if b_nums and int(b_nums[-1]) == file_num:
                    return (idx, b)
            # Hoặc so khớp với số thứ tự 1-based của batch trong danh sách
            if 1 <= file_num <= len(batches):
                return (file_num - 1, batches[file_num - 1])

        return None

    matched_assignments: Dict[str, Tuple[Path, int, LectureBatch]] = {}
    for hf in html_files:
        matched = match_file_to_batch(hf, project.batches)
        if matched is not None:
            idx, target_batch = matched
            if target_batch.id not in matched_assignments:
                matched_assignments[target_batch.id] = (hf, idx, target_batch)
                emit_log("info", f"  ✓ Ánh xạ: {hf.name} ➔ {target_batch.id} (#{idx + 1:02d})")
            else:
                old_file = matched_assignments[target_batch.id][0]
                emit_log("debug", f"  ! Trùng lặp cho {target_batch.id}: đã có {old_file.name}, bỏ qua {hf.name}")

    if not matched_assignments:
        emit_log("warn", "Không có file HTML nào khớp với các phân cảnh hiện tại trong dự án.")
        emit_json({
            "type": "result",
            "action": "import_folder_html",
            "total_matched": 0,
            "matched_batches": [],
            "status": "failed",
            "error": "Không có file HTML nào khớp với các phân cảnh hiện tại.",
        })
        return 1

    workers, hw_encoder, hw_args = resolve_hardware_config(cfg)
    total_matched = len(matched_assignments)
    emit_log("info", f"[Import Folder] Đã ánh xạ thành công {total_matched} file HTML vào {total_matched} phân cảnh. Kích hoạt {workers} workers (encoder={hw_encoder})...")

    scenes_dir = workspace_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = scenes_dir / ".batch_manifest.json"

    manifest: Dict[str, Any] = {}
    if manifest_path.exists():
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except Exception:
            manifest = {}

    from concurrent.futures import ThreadPoolExecutor, as_completed
    from engine.features.lecture_illustrator.visual_renderer import render_single_batch_complete
    import shutil

    sorted_items = sorted(matched_assignments.values(), key=lambda item: item[1])

    # Pha 1: Chuẩn bị nội dung HTML thô và metadata cho tất cả các batch
    render_tasks = []
    for imported_html_path, found_idx, target_batch in sorted_items:
        sentence_offset = sum(len(project.batches[i].sentences) for i in range(found_idx))
        out_html = scenes_dir / f"{target_batch.id}.html"
        meta_json = scenes_dir / f"{target_batch.id}.meta.json"

        scene_dur = float(getattr(target_batch, "scene_duration", 0.0) or (target_batch.end_sec - target_batch.start_sec) or 3.0)
        step_starts = getattr(target_batch, "step_starts", []) or [0.0]

        # Sao lưu phiên bản cũ nếu đã tồn tại
        if out_html.exists() and imported_html_path.resolve() != out_html.resolve():
            bak_file = scenes_dir / f"{target_batch.id}.html.bak"
            try:
                shutil.copy2(out_html, bak_file)
            except Exception as e:
                emit_log("debug", f"Không thể tạo bản sao lưu .bak: {e}")

        # Ghi nội dung HTML
        try:
            raw_content = imported_html_path.read_text(encoding="utf-8")
            out_html.write_text(raw_content, encoding="utf-8")
        except Exception as e:
            emit_log("error", f"Lỗi đọc/ghi {imported_html_path.name}: {e}")
            continue

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
        target_batch.active_asset = None

        render_tasks.append((imported_html_path, found_idx, target_batch, sentence_offset))

    # Pha 2: Render song song với ThreadPoolExecutor (Smart Resume + Fault-tolerant)
    def _render_worker(task_item):
        imp_path, f_idx, t_batch, s_offset = task_item
        res_clip, b_hash = render_single_batch_complete(
            batch=t_batch,
            workspace_dir=workspace_dir,
            config=cfg,
            sentence_offset=s_offset,
            force_rerender=False,
            # pyrefly: ignore[unexpected-keyword]
            update_manifest=False,
        )
        return t_batch.id, f_idx, t_batch, imp_path.name, res_clip, b_hash

    done_count = 0
    successful_batches = []
    failed_batches = []

    with ThreadPoolExecutor(max_workers=max(1, workers)) as executor:
        futures = {executor.submit(_render_worker, item): item for item in render_tasks}
        for fut in as_completed(futures):
            orig_item = futures[fut]
            done_count += 1
            try:
                b_id, f_idx, t_batch, f_name, res_clip, b_hash = fut.result()
                if res_clip and Path(res_clip).exists():
                    t_batch.scene_video = str(res_clip)
                    project.batches[f_idx] = t_batch
                    manifest[b_id] = {
                        "hash": b_hash,
                        "mtime": time.time(),
                        "path": str(res_clip),
                    }
                    successful_batches.append(b_id)
                    emit_log("info", f"[Import Folder] ({done_count}/{total_matched}) Render clip thành công cho {b_id} từ {f_name}")
                else:
                    failed_batches.append(b_id)
                    emit_log("warn", f"[Import Folder] ({done_count}/{total_matched}) Không tạo được clip cho {b_id} từ {f_name}")
            except Exception as e:
                b_id = orig_item[2].id
                failed_batches.append(b_id)
                emit_log("warn", f"[Import Folder] ({done_count}/{total_matched}) Lỗi render cảnh {b_id}: {e}")

            emit_json({
                "type": "progress",
                "action": "import_folder_html",
                "current": done_count,
                "total": total_matched,
                "batch_id": orig_item[2].id,
                "file_name": orig_item[0].name,
                "message": f"({done_count}/{total_matched}) Đã nạp {orig_item[0].name} vào {orig_item[2].id}"
            })

    # Pha 3: Lưu lại manifest và project JSON tập trung trên Main Thread
    try:
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception as e:
        emit_log("warn", f"Không thể lưu .batch_manifest.json: {e}")

    try:
        proj_path.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
        emit_log("info", f"[Import Folder] Hoàn tất nạp thư mục HTML! Thành công {len(successful_batches)}/{total_matched} cảnh. Đã cập nhật {proj_path.name}")
    except Exception as e:
        emit_log("error", f"Không thể lưu project JSON: {e}")
        return 1

    emit_json({
        "type": "result",
        "action": "import_folder_html",
        "total_matched": total_matched,
        "matched_batches": [b.id for _, _, b in sorted_items],
        "successful_batches": successful_batches,
        "failed_batches": failed_batches,
        "status": "success" if successful_batches else "failed",
    })
    return 0 if successful_batches else 1


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

    # 6. Đặt lại trạng thái scene cho batch đã gộp (Instant Merge: bỏ qua gọi AI và bỏ qua render clip)
    emit_log("info", f"[Merge Batches] Đã khâu {len(merged_sentences)} câu thoại và cập nhật timeline cho {b1.id}...")
    sc_data = b1.scene if isinstance(b1.scene, dict) else {}
    sc_data["mode"] = "authored"
    sc_data["html_path"] = str(scenes_dir / f"{b1.id}.html")
    sc_data["imported"] = False
    b1.scene = sc_data
    b1.scene_video = None

    project.batches[found_idx1] = b1
    try:
        proj_path.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")
        emit_log("info", f"[Merge Batches] Đã gộp thành công {b1.id} và {removed_batch_id}! Đã lưu cập nhật dự án vào {proj_path.name}")
    except Exception as e:
        emit_log("error", f"Không thể lưu project JSON: {e}")
        return 1

    emit_json({
        "type": "result",
        "action": "merge_batches",
        "batch_id": b1.id,
        "merged_with_id": removed_batch_id,
        "total_batches": len(project.batches),
        "html_path": str(scenes_dir / f"{b1.id}.html"),
        "scene_video": None,
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

    from engine.features.lecture_illustrator.scene_planner import translate_secondary_subtitles
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
    from engine.features.lecture_illustrator.subtitles import generate_batch_ass, generate_lecture_ass

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


def split_text_into_lecture_sentences(text: str, max_chars: int = 95) -> List[str]:
    """Tách đoạn văn thành các câu / vế câu ngắn gọn tự nhiên (<= max_chars),
    tránh để phụ đề và nội dung thoại quá dài hiển thị tràn khung hình video."""
    if not text or not text.strip():
        return []

    # 1. Tách theo dòng thô
    raw_lines = [line.strip() for line in text.splitlines() if line.strip()]
    raw_sentences: List[str] = []

    for line in raw_lines:
        # Bỏ bullet / numbering markdown ở đầu dòng (- , * , • , 1. )
        clean_line = re.sub(r"^(\s*[-*•]|\s*\d+[\.\)])\s+", "", line).strip()
        if not clean_line:
            continue
        # Tách theo các dấu kết thúc câu: . ! ? … hoặc các biến thể tiếng Á Đông
        parts = re.split(r"(?<=[.!?…。！？])\s+", clean_line)
        for p in parts:
            p_strip = p.strip()
            if p_strip:
                raw_sentences.append(p_strip)

    # 2. Xử lý các câu dài > max_chars bằng cách ngắt theo dấu phẩy, chấm phẩy, hai chấm, gạch ngang
    refined_sentences: List[str] = []
    for s in raw_sentences:
        if len(s) <= max_chars:
            refined_sentences.append(s)
            continue

        clauses = re.split(r"(?<=[,;:–—|])\s+", s)
        cur = ""
        for c in clauses:
            c = c.strip()
            if not c:
                continue
            if not cur:
                cur = c
            elif len(cur) + 1 + len(c) <= max_chars:
                cur = f"{cur} {c}"
            else:
                refined_sentences.append(cur)
                cur = c
        if cur:
            refined_sentences.append(cur)

    # 3. Quét lần cuối: nếu câu nào vẫn vượt quá max_chars (do không có dấu ngắt), ngắt theo từ
    final_sentences: List[str] = []
    for s in refined_sentences:
        if len(s) <= max_chars:
            final_sentences.append(s)
            continue
        words = s.split()
        cur_w: List[str] = []
        cur_len = 0
        for w in words:
            added_len = len(w) + (1 if cur_w else 0)
            if cur_len + added_len <= max_chars:
                cur_w.append(w)
                cur_len += added_len
            else:
                if cur_w:
                    final_sentences.append(" ".join(cur_w))
                cur_w = [w]
                cur_len = len(w)
        if cur_w:
            final_sentences.append(" ".join(cur_w))

    return final_sentences or [text.strip()]


def _synthesize_batch_sentences(
    batch_id: str,
    sentences: List[str],
    tts_dir: Path,
    voice: str,
    speed: float,
) -> Tuple[List[str], List[float], List[float], float]:
    """Sinh file âm thanh TTS cho từng câu trong batch.
    - Nếu batch chỉ có 1 câu: lưu file {batch_id}.mp3
    - Nếu batch có nhiều câu: lưu từng file {batch_id}_s00.mp3, {batch_id}_s01.mp3...
    Trả về: (audio_files, durations, step_starts, total_scene_duration)"""
    from engine.shared.movie_review_tts import MovieReviewTTS

    durations: List[float] = []
    audio_files: List[str] = []

    is_single = len(sentences) <= 1
    for idx, s_text in enumerate(sentences):
        audio_name = f"{batch_id}.mp3" if is_single else f"{batch_id}_s{idx:02d}.mp3"
        out_file = tts_dir / audio_name
        try:
            dur = MovieReviewTTS.synthesize_single(text=s_text, out_file=out_file, voice=voice, speed_factor=speed)
            dur = round(float(dur), 3) if dur and dur > 0 else max(1.5, round(len(s_text) * 0.08, 3))
        except Exception as e:
            emit_log("warn", f"Lỗi sinh giọng TTS cho câu {idx} ({batch_id}): {e}")
            dur = max(1.5, round(len(s_text) * 0.08, 3))

        durations.append(dur)
        audio_files.append(audio_name)

    if is_single:
        step_starts = [0.0]
        total_duration = durations[0] if durations else 3.5
    else:
        gap = 0.25
        local = 0.0
        step_starts = []
        for d in durations:
            step_starts.append(round(local, 3))
            local += d + gap
        total_duration = round(local - gap + 0.35, 3)

    return audio_files, durations, step_starts, total_duration


def translate_batch_sentences_to_secondary(
    sentences: List[str],
    config: LectureProjectConfig,
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
) -> List[str]:
    """Dịch danh sách các câu đã tách sang ngôn ngữ phụ (secondary_lang, mặc định 'en')
    để làm phụ đề dòng 2 (bilingual subtitle) hiển thị song ngữ chuẩn trên khung hình."""
    sec_lang = (getattr(config, "secondary_lang", "en") or "en").strip().lower()
    target_lang = (getattr(config, "target_lang", "vi") or "vi").strip().lower()

    if not sentences:
        return []

    if not sec_lang or sec_lang in ("none", target_lang):
        return list(sentences)

    results: List[Optional[str]] = [None] * len(sentences)

    # 1. Thử dịch theo lô bằng LLM nếu có api_key hoặc base_url
    if api_key or base_url:
        try:
            from engine.features.lecture_illustrator.scene_author import call_llm_api
            from engine.features.lecture_illustrator.common import clean_json_str
            prompt = (
                f"Translate each of the following sentences to '{sec_lang}'. "
                "Keep each translation natural, concise, and suitable for video subtitles. "
                "Do not include markdown or extra explanations. "
                f"Return strictly a JSON array of exactly {len(sentences)} strings in the same order.\n"
                + json.dumps(sentences, ensure_ascii=False)
            )
            raw_resp = call_llm_api(prompt, api_key, model or "gemini-2.5-flash", base_url) or ""
            parsed = json.loads(clean_json_str(raw_resp))
            if isinstance(parsed, list) and len(parsed) == len(sentences):
                for idx, t in enumerate(parsed):
                    if isinstance(t, str) and t.strip():
                        results[idx] = t.strip()
        except Exception as e:
            emit_log("debug", f"LLM dịch phụ đề dòng 2 lỗi ({e}), chuyển sang fallback...")

    # 2. Fallback bằng translate_text_free đa luồng
    missing_indices = [i for i, r in enumerate(results) if not r]
    if missing_indices:
        from engine.features.lecture_illustrator.knowledge_extractor import translate_text_free
        from concurrent.futures import ThreadPoolExecutor

        def _trans_worker(idx: int) -> Tuple[int, str]:
            try:
                res = translate_text_free(sentences[idx], target_lang=sec_lang)
                return idx, res.strip() if res else sentences[idx]
            except Exception:
                return idx, sentences[idx]

        with ThreadPoolExecutor(max_workers=min(4, len(missing_indices))) as pool:
            for idx, res in pool.map(_trans_worker, missing_indices):
                results[idx] = res

    # 3. Đảm bảo toàn bộ câu có kết quả hợp lệ
    final_sec: List[str] = []
    for idx, s in enumerate(sentences):
        trans = results[idx] if results[idx] else s
        clean_trans = " ".join(trans.split())
        final_sec.append(clean_trans)

    return final_sec


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
        step_starts = getattr(b, "step_starts", []) or []
        if sents:
            for idx, s in enumerate(sents):
                s_dur = float(s.get("duration", 0.0) or 0.0)
                if s_dur <= 0:
                    s_dur = round(dur / max(1, len(sents)), 3)
                    s["duration"] = s_dur
                st_rel = float(step_starts[idx]) if idx < len(step_starts) else round(idx * (dur / len(sents)), 3)
                if idx + 1 < len(step_starts):
                    et_rel = min(dur, float(step_starts[idx + 1]))
                else:
                    et_rel = dur
                s["start"] = round(b.start_sec + st_rel, 3)
                s["end"] = round(b.start_sec + et_rel, 3)
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

    if getattr(args, "tts_voice", None):
        cfg.tts_voice = args.tts_voice
    if getattr(args, "tts_speed", None) is not None:
        try:
            cfg.tts_speed = float(args.tts_speed)
        except (ValueError, TypeError):
            pass
    if getattr(args, "target_lang", None):
        cfg.target_lang = args.target_lang
    if getattr(args, "secondary_lang", None):
        cfg.secondary_lang = args.secondary_lang
    if getattr(args, "subtitle_mode", None):
        cfg.subtitle_mode = args.subtitle_mode
    if getattr(args, "subtitle_show_primary", None) is not None:
        cfg.subtitle_show_primary = bool(args.subtitle_show_primary != "false")
    if getattr(args, "subtitle_secondary_show", None) is not None:
        cfg.subtitle_secondary_show = bool(args.subtitle_secondary_show != "false")

    tts_dir = workspace_dir / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)
    voice = getattr(cfg, "tts_voice", "ban_mai") or "ban_mai"
    speed = float(getattr(cfg, "tts_speed", 1.15) or 1.15)

    if action == "create":
        if not batch_id:
            idx_counter = len(project.batches) + 1
            existing_ids = {b.id for b in project.batches}
            batch_id = f"batch_{idx_counter:03d}"
            while batch_id in existing_ids:
                idx_counter += 1
                batch_id = f"batch_{idx_counter:03d}"

        split_sents = split_text_into_lecture_sentences(text, max_chars=95)
        if not split_sents:
            split_sents = [text] if text else ["Phân cảnh mới"]

        sec_raw = getattr(args, "text_secondary", None) or getattr(args, "secondary_text", None)
        candidate_sec = split_text_into_lecture_sentences(sec_raw, max_chars=105) if sec_raw else []
        if candidate_sec and len(candidate_sec) == len(split_sents):
            sec_sents = candidate_sec
        else:
            sec_sents = translate_batch_sentences_to_secondary(
                sentences=split_sents,
                config=cfg,
                api_key=getattr(args, "api_key", None),
                model=getattr(args, "model", None),
                base_url=getattr(args, "base_url", None),
            )

        audio_files, durations, step_starts, dur = _synthesize_batch_sentences(
            batch_id=batch_id,
            sentences=split_sents,
            tts_dir=tts_dir,
            voice=voice,
            speed=speed,
        )

        sent_objects = []
        for idx, s_text in enumerate(split_sents):
            d_i = durations[idx]
            st_rel = step_starts[idx]
            et_rel = min(dur, step_starts[idx + 1]) if idx + 1 < len(step_starts) else dur
            s_sec = sec_sents[idx] if idx < len(sec_sents) else s_text
            sent_objects.append({
                "index": idx,
                "text": s_text,
                "text_secondary": s_sec,
                "text_orig": s_sec,
                "start": st_rel,
                "end": et_rel,
                "duration": d_i,
                "audio_file": audio_files[idx],
            })

        new_batch = LectureBatch(
            id=batch_id,
            start_sec=0.0,
            end_sec=dur,
            transcript_original=" ".join(sec_sents) if sec_sents else text,
            transcript_translated=text,
            scene_duration=dur,
            step_starts=step_starts,
            sentences=sent_objects,
            scene={"template": "bullet_list", "title": text[:30], "steps": []},
            educational_intent="PROCESS",
        )

        insert_at = getattr(args, "insert_at", None)
        if insert_at is not None and 0 <= int(insert_at) <= len(project.batches):
            project.batches.insert(int(insert_at), new_batch)
        else:
            project.batches.append(new_batch)

        _recalculate_project_timeline(project)

        # Composite audio và cập nhật file ASS
        scenes_dir = workspace_dir / "scenes"
        if scenes_dir.exists():
            a_path = scenes_dir / f"{batch_id}_audio.wav"
            try:
                from engine.features.lecture_illustrator.visual_renderer import create_batch_audio
                create_batch_audio(new_batch, workspace_dir, cfg, a_path)
            except Exception as e:
                emit_log("debug", f"Không thể tạo audio batch {batch_id}: {e}")

            out_audio = tts_dir / f"{batch_id}.mp3"
            if len(split_sents) > 1 and a_path.exists() and a_path.stat().st_size > 0:
                try:
                    subprocess.run(
                        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(a_path), "-q:a", "2", str(out_audio)],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        check=False,
                    )
                except Exception:
                    pass

            try:
                from engine.features.lecture_illustrator.subtitles import generate_batch_ass
                vw, vh = (1920, 1080) if cfg.aspect_ratio != "9:16" else (1080, 1920)
                generate_batch_ass(new_batch, scenes_dir / f"{batch_id}.ass", cfg, video_width=vw, video_height=vh)
            except Exception as e:
                emit_log("debug", f"Không thể sinh batch .ass: {e}")

        try:
            from engine.features.lecture_illustrator.subtitles import generate_lecture_ass
            vw, vh = (1920, 1080) if cfg.aspect_ratio != "9:16" else (1080, 1920)
            generate_lecture_ass(project.batches, workspace_dir / "lecture_subtitles.ass", cfg, video_width=vw, video_height=vh)
        except Exception as e:
            emit_log("debug", f"Không thể sinh lecture_subtitles.ass: {e}")

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
            split_sents = split_text_into_lecture_sentences(text, max_chars=95)
            if not split_sents:
                split_sents = [text]

            sec_raw = getattr(args, "text_secondary", None) or getattr(args, "secondary_text", None)
            candidate_sec = split_text_into_lecture_sentences(sec_raw, max_chars=105) if sec_raw else []
            if candidate_sec and len(candidate_sec) == len(split_sents):
                sec_sents = candidate_sec
            else:
                sec_sents = translate_batch_sentences_to_secondary(
                    sentences=split_sents,
                    config=cfg,
                    api_key=getattr(args, "api_key", None),
                    model=getattr(args, "model", None),
                    base_url=getattr(args, "base_url", None),
                )

            audio_files, durations, step_starts, dur = _synthesize_batch_sentences(
                batch_id=batch_id,
                sentences=split_sents,
                tts_dir=tts_dir,
                voice=voice,
                speed=speed,
            )

            target_batch.transcript_translated = text
            if sec_sents:
                target_batch.transcript_original = " ".join(sec_sents)
            target_batch.scene_duration = dur
            target_batch.step_starts = step_starts

            sent_objects = []
            for idx, s_text in enumerate(split_sents):
                d_i = durations[idx]
                st_rel = step_starts[idx]
                et_rel = min(dur, step_starts[idx + 1]) if idx + 1 < len(step_starts) else dur
                s_sec = sec_sents[idx] if idx < len(sec_sents) else s_text
                sent_objects.append({
                    "index": idx,
                    "text": s_text,
                    "text_secondary": s_sec,
                    "text_orig": s_sec,
                    "start": st_rel,
                    "end": et_rel,
                    "duration": d_i,
                    "audio_file": audio_files[idx],
                })
            target_batch.sentences = sent_objects

        _recalculate_project_timeline(project)

        # Composite audio và cập nhật file ASS
        scenes_dir = workspace_dir / "scenes"
        if scenes_dir.exists():
            a_path = scenes_dir / f"{batch_id}_audio.wav"
            try:
                from engine.features.lecture_illustrator.visual_renderer import create_batch_audio
                create_batch_audio(target_batch, workspace_dir, cfg, a_path)
            except Exception as e:
                emit_log("debug", f"Không thể tạo audio batch {batch_id}: {e}")

            out_audio = tts_dir / f"{batch_id}.mp3"
            if len(target_batch.sentences) > 1 and a_path.exists() and a_path.stat().st_size > 0:
                try:
                    subprocess.run(
                        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(a_path), "-q:a", "2", str(out_audio)],
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                        check=False,
                    )
                except Exception:
                    pass

            for old_v in (scenes_dir / f"{batch_id}_combined.mp4", scenes_dir / f"{batch_id}_video.mp4"):
                if old_v.exists():
                    try:
                        old_v.unlink()
                    except OSError:
                        pass

            manifest_file = scenes_dir / ".batch_manifest.json"
            if manifest_file.exists():
                try:
                    m_data = json.loads(manifest_file.read_text(encoding="utf-8"))
                    if batch_id in m_data:
                        del m_data[batch_id]
                        manifest_file.write_text(json.dumps(m_data, indent=2, ensure_ascii=False), encoding="utf-8")
                except Exception:
                    pass

            try:
                from engine.features.lecture_illustrator.subtitles import generate_batch_ass
                vw, vh = (1920, 1080) if cfg.aspect_ratio != "9:16" else (1080, 1920)
                generate_batch_ass(target_batch, scenes_dir / f"{batch_id}.ass", cfg, video_width=vw, video_height=vh)
            except Exception as e:
                emit_log("debug", f"Không thể sinh batch .ass: {e}")

        try:
            from engine.features.lecture_illustrator.subtitles import generate_lecture_ass
            vw, vh = (1920, 1080) if cfg.aspect_ratio != "9:16" else (1080, 1920)
            generate_lecture_ass(project.batches, workspace_dir / "lecture_subtitles.ass", cfg, video_width=vw, video_height=vh)
        except Exception as e:
            emit_log("debug", f"Không thể sinh lecture_subtitles.ass: {e}")

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

        try:
            from engine.features.lecture_illustrator.subtitles import generate_lecture_ass
            vw, vh = (1920, 1080) if cfg.aspect_ratio != "9:16" else (1080, 1920)
            generate_lecture_ass(project.batches, workspace_dir / "lecture_subtitles.ass", cfg, video_width=vw, video_height=vh)
        except Exception as e:
            emit_log("debug", f"Không thể sinh lecture_subtitles.ass: {e}")

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
    parser.add_argument("--mode", choices=["analyze", "render", "reauthor_batch", "reauthor_batch_multi", "import_batch_html", "import_folder_html", "merge_batches", "sync_subtitles", "sync_batch_audio"], required=True, help="Chế độ chạy")
    parser.add_argument("--action", choices=["create", "update", "delete"], default="update", help="Hành động khi dùng sync_batch_audio")
    parser.add_argument("--text", type=str, default="", help="Nội dung văn bản thoại khi tạo hoặc sửa phân cảnh")
    parser.add_argument("--text-secondary", "--secondary-text", dest="text_secondary", type=str, default=None, help="Nội dung phụ đề dòng 2 (nếu có)")
    parser.add_argument("--insert-at", type=int, default=None, help="Vị trí chèn phân cảnh mới (0-indexed)")
    parser.add_argument("--input", type=str, help="Đường dẫn file đầu vào bài giảng (video, audio, text)")
    parser.add_argument("--video", type=str, help="Đường dẫn file video bài giảng nguồn (tương thích ngược)")
    parser.add_argument("--raw-article", action="store_true", help="Bật chế độ AI biên soạn bài giảng từ tài liệu/bài viết thô")
    parser.add_argument("--workspace", type=str, help="Thư mục làm việc của dự án")
    parser.add_argument("--project-name", type=str, help="Tên dự án bài giảng")
    parser.add_argument("--project-file", type=str, help="Đường dẫn file lecture_project.json")
    parser.add_argument("--output", type=str, help="Đường dẫn file video đầu ra .mp4")
    parser.add_argument("--batch-id", type=str, help="ID phân đoạn cần xử lý (ví dụ: batch_003)")
    parser.add_argument("--batch-ids", type=str, default="", help="Danh sách các ID phân đoạn phân cách bằng dấu phẩy (ví dụ: batch_001,batch_003)")
    parser.add_argument("--merge-with-id", type=str, help="ID phân đoạn thứ hai cần gộp (mặc định là phân đoạn tiếp theo)")
    parser.add_argument("--html-file", type=str, help="Đường dẫn file HTML cần import từ ngoài vào batch")
    parser.add_argument("--folder-dir", type=str, help="Đường dẫn thư mục chứa các file HTML phân cảnh cần import hàng loạt")
    parser.add_argument("--feedback", type=str, default="", help="Yêu cầu chỉnh sửa của người dùng cho AI")
    parser.add_argument("--refine", action="store_true", help="Bật chế độ AI tinh chỉnh từ mã HTML hiện có thay vì sinh lại từ đầu")

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
    parser.add_argument("--subtitle-show-primary", type=str, default=None, help="Hiện dòng sub chính: true/false")
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
    parser.add_argument("--fps", type=int, default=None, help="Tốc độ khung hình render video (18-24 FPS)")

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
    elif args.mode == "reauthor_batch_multi":
        sys.exit(run_reauthor_batch_multi_flow(args))
    elif args.mode == "import_batch_html":
        sys.exit(run_import_batch_html_flow(args))
    elif args.mode == "import_folder_html":
        sys.exit(run_import_folder_html_flow(args))
    elif args.mode == "merge_batches":
        sys.exit(run_merge_batches_flow(args))
    elif args.mode == "sync_subtitles":
        sys.exit(run_sync_subtitles_flow(args))
    elif args.mode == "sync_batch_audio":
        sys.exit(run_sync_batch_audio_flow(args))


if __name__ == "__main__":
    main()


