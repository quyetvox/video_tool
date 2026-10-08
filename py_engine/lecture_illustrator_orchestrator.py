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
                emit_log("info", f"Tái sử dụng transcript Whisper sẵn có: {cached_asr.name}")
                return data
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
        config = {"asr": "mlx_whisper"} if sys.platform == "darwin" else {"asr": "faster_whisper"}
        if source_lang and source_lang != "auto":
            config["source_lang"] = source_lang
        asr_plugin = PluginLoader.load_plugin("asr", config.get("asr", "mlx_whisper"), config)
        raw_segments = asr_plugin.transcribe(audio_wav)
        
        # Lưu cache s05_asr.json
        cached_asr.write_text(json.dumps(raw_segments, ensure_ascii=False, indent=2), encoding="utf-8")
        emit_log("info", f"Whisper hoàn tất nhận diện {len(raw_segments)} câu thoại.")
        return raw_segments
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
    else:
        # Lấy mặc định từ config.yaml nếu không truyền CLI
        yaml_speed = float(cfg_yaml.get("tts", {}).get("speed_factor", 1.15))
        init_speed = float(args.tts_speed) if args.tts_speed is not None else yaml_speed
        yaml_sec_lang = str(cfg_yaml.get("app", {}).get("secondary_lang", "en"))
        yaml_sec_show = bool(cfg_yaml.get("subtitle", {}).get("secondary", {}).get("show", True))
        yaml_order = str(cfg_yaml.get("subtitle", {}).get("order", "primary_top"))

        cfg = LectureProjectConfig(
            source_lang=args.source_lang or "auto",
            target_lang=args.target_lang or cfg_yaml.get("app", {}).get("target_lang", "vi"),
            secondary_lang=getattr(args, "secondary_lang", None) or (yaml_sec_lang if yaml_sec_lang else "en"),
            pronoun_mode=args.pronoun_mode or "formal",
            voice_mode=args.voice_mode or "tts_dub",
            tts_voice=args.tts_voice or "ban_mai",
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
            secondary_scale=float(getattr(args, "secondary_scale", None) or cfg_yaml.get("subtitle", {}).get("secondary", {}).get("font_scale", 0.70)),
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
        )

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


def main():
    parser = argparse.ArgumentParser(description="AI Lecture Illustrator Orchestrator")
    parser.add_argument("--mode", choices=["analyze", "render"], required=True, help="Chế độ chạy: analyze hoặc render")
    parser.add_argument("--input", type=str, help="Đường dẫn file đầu vào bài giảng (video, audio, text)")
    parser.add_argument("--video", type=str, help="Đường dẫn file video bài giảng nguồn (tương thích ngược)")
    parser.add_argument("--raw-article", action="store_true", help="Bật chế độ AI biên soạn bài giảng từ tài liệu/bài viết thô")
    parser.add_argument("--workspace", type=str, help="Thư mục làm việc của dự án")
    parser.add_argument("--project-name", type=str, help="Tên dự án bài giảng")
    parser.add_argument("--project-file", type=str, help="Đường dẫn file lecture_project.json")
    parser.add_argument("--output", type=str, help="Đường dẫn file video đầu ra .mp4")

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
    parser.add_argument("--tts-voice", type=str, default="ban_mai", help="Giọng TTS: ban_mai / hoai_my / nam_minh")
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

    # Tham số Visual
    parser.add_argument("--layout-preset", choices=["pip", "full", "split"], default="pip", help="Bố cục visual")

    args = parser.parse_args()

    if args.mode == "analyze":
        if not args.input and not args.video:
            parser.error("--input hoặc --video là bắt buộc khi dùng --mode analyze")
        sys.exit(run_analyze_flow(args))
    elif args.mode == "render":
        if not args.project_file:
            parser.error("--project-file là bắt buộc khi dùng --mode render")
        sys.exit(run_render_flow(args))


if __name__ == "__main__":
    main()
