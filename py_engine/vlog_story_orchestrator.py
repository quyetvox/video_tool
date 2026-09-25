#!/usr/bin/env python3
"""
Vlog Story Orchestrator — Hệ Thống Tự Động Kể Chuyện & Lồng Tiếng Cho Video Vlog
- Bảo toàn 100% dòng thời gian 1:1 của video gốc (Zero-Cut Law)
- Phân tích thị giác trực tiếp bằng Gemini Files API 1-pass (~20s) hoặc Ollama Vision Fallback
- Word-Budget Engine & Dynamic Pacing (Khoảng thở âm nhạc, Adaptive Speed)
- TTS đa giọng đọc (Hoài My, Ban Mai, Nam Minh) với Cache MD5 & Smart Ducking
- Phụ đề nhịp điệu (Rhythmic Subtitles 4-6 từ) căn giữa an toàn
"""

import argparse
import asyncio
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT_DIR = Path(__file__).parent.parent.resolve()
ENGINE_DIR = Path(__file__).parent.resolve()
sys.path.insert(0, str(ENGINE_DIR))
sys.path.insert(0, str(ROOT_DIR))

from utils.ffmpeg_utils import FFmpegUtils, ensure_system_path
ensure_system_path()
from utils.movie_review_tts import MovieReviewTTS, normalize_vietnamese_text
from utils.vlog_story_prompts import build_gemini_vlog_prompt, PRESET_INSTRUCTIONS
from movie_review.common import (
    emit_json,
    emit_log,
    emit_progress,
    safe_ensure_dir,
    load_project_config,
    resolve_gemini_config,
    clean_json_str,
)
from movie_review.subtitles import (
    split_subtitle_into_rhythmic_cues,
    _color_to_ass,
    build_inpaint_filter,
)



def generate_vlog_ass_subtitles(
    dialogues: List[Dict[str, Any]],
    output_ass_path: Path,
    video_width: int = 1920,
    video_height: int = 1080,
    project_config: Optional[Dict[str, Any]] = None
) -> Path:
    """Tạo file phụ đề .ass chuẩn hóa khớp chính xác timing tuyệt đối từng cue thoại."""
    cfg = project_config or {}
    sub_cfg = cfg.get("subtitle", {})

    font_name = sub_cfg.get("font_name") or cfg.get("subtitle_font_name") or "Arial"
    is_vertical = video_height > video_width
    font_size = int(sub_cfg.get("font_size") or cfg.get("subtitle_font_size") or (46 if is_vertical else 34))
    font_color = _color_to_ass(sub_cfg.get("font_color") or cfg.get("subtitle_font_color"), "&H00FFFFFF")
    outline_color = _color_to_ass(sub_cfg.get("outline_color") or cfg.get("subtitle_outline_color"), "&H00000000")
    outline_width = int(sub_cfg.get("outline_width") or cfg.get("subtitle_outline_width") or 3)

    # Tọa độ vùng phụ đề từ Gizmo: [top, left, bottom, right]
    pri_region = sub_cfg.get("region") or cfg.get("subtitle_region") or [0.76, 0.05, 0.86, 0.95]
    if isinstance(pri_region, (list, tuple)) and len(pri_region) == 4:
        top, left, bottom, right = [float(v) for v in pri_region]
    else:
        top, left, bottom, right = 0.76, 0.05, 0.86, 0.95

    center_x = max(10, min(video_width - 10, int(video_width * (left + right) / 2.0)))
    center_y = max(10, min(video_height - 10, int(video_height * (top + bottom) / 2.0)))

    ass_lines = [
        "[Script Info]",
        "ScriptType: v4.00+",
        f"PlayResX: {video_width}",
        f"PlayResY: {video_height}",
        "ScaledBorderAndShadow: yes",
        "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        f"Style: VlogDefault,{font_name},{font_size},{font_color},&H000000FF,{outline_color},&H80000000,-1,0,0,0,100,100,0,0,1,{outline_width},1,5,10,10,10,1",
        "",
        "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]

    def format_ass_time(sec: float) -> str:
        h = int(sec // 3600)
        m = int((sec % 3600) // 60)
        s = int(sec % 60)
        cs = int(round((sec - int(sec)) * 100))
        if cs >= 100:
            cs = 99
        return f"{h}:{m:02d}:{s:02d}.{cs:02d}"

    for d in dialogues:
        start_str = format_ass_time(d["start"])
        end_str = format_ass_time(d["end"])
        cue_text = d["text"]
        ass_lines.append(f"Dialogue: 0,{start_str},{end_str},VlogDefault,,0,0,0,,{{\\an5\\pos({center_x},{center_y})}}{cue_text}")

    output_ass_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_ass_path, "w", encoding="utf-8") as f:
        f.write("\n".join(ass_lines) + "\n")

    return output_ass_path


class VlogStoryOrchestrator:
    """Bộ điều phối toàn diện cho quy trình Kể chuyện Vlog từ hình ảnh."""

    def __init__(self, video_path: Path, config: Optional[Dict[str, Any]] = None):
        self.video_path = Path(video_path).resolve()
        if not self.video_path.exists():
            raise FileNotFoundError(f"Video không tồn tại: {self.video_path}")

        self.config = config or {}
        if not self.config:
            loaded, _ = load_project_config(video_path=self.video_path)
            self.config = loaded

        # Thiết lập Workspace
        self.safe_video_name = re.sub(r'[^a-zA-Z0-9_\-]', '_', self.video_path.stem)
        self.project_dir = self._detect_project_dir()
        raw_ws = self.project_dir / "workspace" / "vlog_story" / self.safe_video_name
        self.workspace_dir = safe_ensure_dir(raw_ws, fallback_subdir="vlog_story")
        self.tts_dir = safe_ensure_dir(self.workspace_dir / "tts_segments", fallback_subdir="vlog_story")

        # Probe thông tin video
        probe_data = FFmpegUtils.probe(self.video_path)
        fmt = probe_data.get("format", {})
        self.duration = float(fmt.get("duration", 0.0))
        streams = probe_data.get("streams", [])
        video_streams = [s for s in streams if s.get("codec_type") == "video"]
        audio_streams = [s for s in streams if s.get("codec_type") == "audio"]
        
        self.has_audio = len(audio_streams) > 0
        if video_streams:
            vs = video_streams[0]
            self.width = int(vs.get("width", 1920))
            self.height = int(vs.get("height", 1080))
            self.fps = 30.0
            r_frame = vs.get("r_frame_rate", "30/1")
            if "/" in r_frame:
                num, den = r_frame.split("/")
                if float(den) > 0:
                    self.fps = float(num) / float(den)
        else:
            self.width, self.height, self.fps = 1920, 1080, 30.0

        emit_log("info", f"🎬 Sẵn sàng xử lý Vlog: {self.video_path.name} ({self.duration:.1f}s, {self.width}x{self.height}, Audio: {self.has_audio})", "vlog_story")

    def _detect_project_dir(self) -> Path:
        """Tự động xác định thư mục gốc của project (resources/<project>)."""
        curr = self.video_path.parent
        for _ in range(5):
            if (curr / "config.yaml").exists() or (curr / "workspace").exists() or curr.name == "resources":
                if curr.name == "resources":
                    return curr / "default"
                return curr
            curr = curr.parent
        return ROOT_DIR / "resources" / "default"

    # ──────────────────────────────────────────────────────────────────────────
    # BƯỚC 1: TẠO PROXY PHẦN CỨNG 720P SIÊU TỐC
    # ──────────────────────────────────────────────────────────────────────────

    def create_hardware_proxy(self, target_height: int = 720) -> Path:
        """Nén nhanh bản sao proxy nhẹ (~15–25MB) bằng hardware acceleration trong 1–3s."""
        proxy_path = self.workspace_dir / f"proxy_{target_height}p.mp4"
        if proxy_path.exists() and proxy_path.stat().st_size > 1024 * 50:
            emit_log("info", f"⚡ Đã có sẵn Proxy video tại cache: {proxy_path.name}", "vlog_story")
            return proxy_path

        emit_progress(0.05, "Đang nén bản sao Proxy 720p siêu tốc...", "vlog_story")
        emit_log("info", f"Tạo proxy 720p từ {self.video_path.name} để gửi lên Gemini...", "vlog_story")

        is_mac = sys.platform == "darwin"
        codec = "h264_videotoolbox" if is_mac else "libx264"
        extra_args = ["-b:v", "1800k"] if is_mac else ["-preset", "ultrafast", "-crf", "26"]

        cmd = [
            "ffmpeg", "-y",
            "-i", str(self.video_path),
            "-vf", f"scale=-2:{target_height}",
            "-c:v", codec,
            *extra_args,
            "-an",  # Thị giác không cần audio
            "-pix_fmt", "yuv420p",
            str(proxy_path)
        ]

        t0 = time.time()
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0 or not proxy_path.exists():
            # Fallback CPU chuẩn
            cmd_fallback = [
                "ffmpeg", "-y", "-i", str(self.video_path),
                "-vf", f"scale=-2:{target_height}",
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "28",
                "-an", "-pix_fmt", "yuv420p", str(proxy_path)
            ]
            subprocess.run(cmd_fallback, capture_output=True, check=True)

        elapsed = time.time() - t0
        size_mb = proxy_path.stat().st_size / (1024 * 1024)
        emit_log("info", f"✓ Đã tạo Proxy xong trong {elapsed:.1f}s (Dung lượng: {size_mb:.1f}MB)", "vlog_story")
        return proxy_path

    # ──────────────────────────────────────────────────────────────────────────
    # BƯỚC 2: PHÂN TÍCH HÌNH ẢNH & SINH KỊCH BẢN (GEMINI 1-PASS & LOCAL BACKUP)
    # ──────────────────────────────────────────────────────────────────────────

    def generate_script(
        self,
        style: str = "daily_chill",
        custom_prompt: Optional[str] = None,
        engine: str = "gemini",
        tts_speed: float = 1.0,
    ) -> List[Dict[str, Any]]:
        """Phân tích hình ảnh và tạo kịch bản phân cảnh theo mốc thời gian."""
        script_file = self.workspace_dir / "vlog_script.json"
        
        raw_segments: List[Dict[str, Any]] = []

        if engine == "gemini":
            try:
                raw_segments = self._generate_script_gemini(style, custom_prompt, tts_speed)
            except Exception as e:
                emit_log("warning", f"⚠️ Gemini Cloud gặp sự cố ({e}), tự động chuyển sang Ollama Vision Local...", "vlog_story")
                raw_segments = self._generate_script_ollama(style, custom_prompt, tts_speed)
        else:
            raw_segments = self._generate_script_ollama(style, custom_prompt, tts_speed)

        # Chuẩn hóa kịch bản: Word-Budget Engine & Timecode Sanitizer
        sanitized = self._sanitize_and_calibrate_script(raw_segments, tts_speed)

        with open(script_file, "w", encoding="utf-8") as f:
            json.dump(sanitized, f, ensure_ascii=False, indent=2)

        # Sinh file vlog_metadata.json chuẩn SEO cho Kể Chuyện Vlog
        meta_file = self.workspace_dir / "vlog_metadata.json"
        video_stem = Path(self.video_path).stem
        first_texts = [s.get("text", "") for s in sanitized[:3] if s.get("text")]
        desc = " ".join(first_texts) if first_texts else f"Video kể chuyện Vlog {video_stem} hấp dẫn và giàu cảm xúc."
        clean_style = style.replace("auto", "chill").replace("_", "")
        vlog_meta = {
            "title": f"Vlog: {video_stem} | Câu Chuyện Thường Nhật",
            "description": desc,
            "hashtags": ["#vlog", "#storytelling", f"#{clean_style}", "#dailyvlog", "#subvideo"]
        }
        with open(meta_file, "w", encoding="utf-8") as f:
            json.dump(vlog_meta, f, ensure_ascii=False, indent=2)

        emit_progress(0.40, f"Đã lập xong kịch bản gồm {len(sanitized)} phân cảnh!", "vlog_story")
        emit_log("info", f"✓ Lưu kịch bản visual thành công ({len(sanitized)} phân đoạn)", "vlog_story")
        return sanitized

    def _generate_script_gemini(
        self,
        style: str,
        custom_prompt: Optional[str],
        tts_speed: float
    ) -> List[Dict[str, Any]]:
        """Gửi Proxy Video lên Google Gemini Files API để phân tích 1-pass (~15-20s)."""
        api_key, model_name = resolve_gemini_config(workspace=self.workspace_dir, video_path=self.video_path)
        if not api_key:
            raise ValueError("Chưa cấu hình GEMINI_API_KEY. Vui lòng thiết lập trong Cài đặt hoặc config.yaml.")

        proxy_path = self.create_hardware_proxy(720)

        emit_progress(0.12, "Đang tải video lên Google Gemini Cloud...", "vlog_story")
        from utils.pkg_bootstrap import ensure_package
        if not ensure_package("google.genai", "google-genai>=2.23.0",
                              extras=["google-cloud-storage>=2.0.0", "google-auth>=2.0.0"]):
            raise ImportError("Không thể cài google-genai. Kiểm tra kết nối mạng hoặc cài thủ công: pip install google-genai")
        from google import genai

        client = genai.Client(api_key=api_key)

        video_file = None
        try:
            video_file = client.files.upload(file=str(proxy_path))
            emit_log("info", f"Đã upload video lên Gemini Files API (URI: {video_file.name})", "vlog_story")

            # Chờ Google xử lý video với timeout 90s
            emit_progress(0.20, "Gemini đang tiếp nhận và giải mã khung hình...", "vlog_story")
            t_start = time.time()
            while video_file.state.name == "PROCESSING":
                if time.time() - t_start > 90:
                    raise TimeoutError("Gemini xử lý video quá thời gian cho phép (90s).")
                time.sleep(2)
                video_file = client.files.get(name=video_file.name)

            if video_file.state.name == "FAILED":
                raise ValueError("Google Gemini giải mã video thất bại.")

            emit_progress(0.28, "AI đang xem video và sáng tác lời dẫn...", "vlog_story")
            prompt = build_gemini_vlog_prompt(
                duration=self.duration,
                style=style,
                custom_prompt=custom_prompt,
                words_per_sec=2.2,
                tts_speed=tts_speed,
            )

            # Chọn model hỗ trợ video tốt: gemini-2.5-flash / gemini-3.5-flash-lite / gemini-2.0-flash
            effective_model = model_name if ("flash" in model_name.lower()) else "gemini-2.5-flash"
            
            response = client.models.generate_content(
                model=effective_model,
                contents=[video_file, prompt]
            )

            raw_text = response.text or ""
            clean_json = clean_json_str(raw_text)
            data = json.loads(clean_json)
            if isinstance(data, list):
                return data
            elif isinstance(data, dict) and "segments" in data:
                return data["segments"]
            return []

        finally:
            # 100% dọn dẹp file cloud sau khi sử dụng
            if video_file:
                try:
                    client.files.delete(name=video_file.name)
                    emit_log("info", "✓ Đã xóa file video tạm trên Google Cloud an toàn", "vlog_story")
                except Exception:
                    pass

    def _generate_script_ollama(
        self,
        style: str,
        custom_prompt: Optional[str],
        tts_speed: float
    ) -> List[Dict[str, Any]]:
        """Fallback cục bộ: Trích xuất keyframes đại diện và gọi Ollama Vision."""
        emit_progress(0.15, "Đang trích xuất khung hình cảnh cho Ollama...", "vlog_story")
        import requests

        ollama_host = self.config.get("ollama_host", "http://localhost:11434").rstrip("/")
        vision_model = self.config.get("narrate", {}).get("vision_model", "minicpm-v")
        text_model = self.config.get("translator_model", "gemma4:31b-cloud")

        # Chia đều video thành các cảnh 5s-7s
        step_dur = 6.0
        curr = 0.0
        scene_segments = []
        while curr < self.duration:
            nxt = min(self.duration, curr + step_dur)
            scene_segments.append({"start": round(curr, 2), "end": round(nxt, 2)})
            curr = nxt

        frames_dir = self.workspace_dir / "ollama_frames"
        frames_dir.mkdir(parents=True, exist_ok=True)

        descs = []
        for i, sc in enumerate(scene_segments):
            mid = (sc["start"] + sc["end"]) / 2.0
            frame_img = frames_dir / f"frame_{i:03d}.jpg"
            subprocess.run([
                "ffmpeg", "-y", "-ss", f"{mid:.2f}", "-i", str(self.video_path),
                "-frames:v", "1", "-q:v", "3", str(frame_img)
            ], capture_output=True)

            # Đọc mô tả qua vision
            desc = ""
            if frame_img.exists():
                import base64
                with open(frame_img, "rb") as f:
                    b64 = base64.b64encode(f.read()).decode("utf-8")
                try:
                    resp = requests.post(
                        f"{ollama_host}/api/chat",
                        json={
                            "model": vision_model,
                            "messages": [{"role": "user", "content": "Describe briefly what you see in this image in 1 short sentence.", "images": [b64]}],
                            "stream": False
                        },
                        timeout=30
                    )
                    if resp.status_code == 200:
                        desc = resp.json().get("message", {}).get("content", "").strip()
                except Exception:
                    pass
            descs.append(desc or "Cảnh quay vlog.")

        # Tạo kịch bản qua LLM
        prompt_ollama = f"""Dưới đây là mô tả các cảnh liên tiếp của một video dài {self.duration:.1f}s:
{json.dumps([{'time': f"{s['start']}s-{s['end']}s", 'desc': d} for s, d in zip(scene_segments, descs)], ensure_ascii=False, indent=2)}

Hãy viết lời dẫn lồng tiếng tiếng Việt cho từng cảnh (phong cách {style}):
Trả về JSON array: [{{"start": 0.0, "end": 6.0, "visual_desc": "...", "text": "..."}}]"""

        try:
            r = requests.post(f"{ollama_host}/api/generate", json={"model": text_model, "prompt": prompt_ollama, "stream": False}, timeout=60)
            if r.status_code == 200:
                parsed = json.loads(clean_json_str(r.json().get("response", "")))
                if isinstance(parsed, list):
                    return parsed
        except Exception:
            pass

        # Fallback cơ bản nếu text LLM lỗi
        return [{"start": s["start"], "end": s["end"], "visual_desc": d, "text": d} for s, d in zip(scene_segments, descs)]

    def _sanitize_and_calibrate_script(
        self,
        raw_segments: List[Dict[str, Any]],
        tts_speed: float
    ) -> List[Dict[str, Any]]:
        """Chuẩn hóa timecodes, tính ngân sách từ và chống trôi dòng thời gian."""
        if not raw_segments:
            return []

        # 1. Sắp xếp theo start_time
        sorted_items = sorted(raw_segments, key=lambda x: float(x.get("start", 0.0)))
        sanitized = []
        last_end = 0.0
        words_per_sec = 2.2 * tts_speed

        for i, item in enumerate(sorted_items):
            start = max(last_end, float(item.get("start", 0.0)))
            end = float(item.get("end", start + 4.0))

            # Giới hạn không vượt quá duration video
            if start >= self.duration:
                break
            end = min(self.duration, max(start + 1.0, end))

            dur = round(end - start, 2)
            max_words = max(0, int(round(dur * words_per_sec)))

            text = item.get("text", "").strip()
            desc = item.get("visual_desc", "").strip()

            # Tránh câu quá dài vượt quá ngân sách từ
            w_count = len(text.split()) if text else 0
            if dur < 2.0 or max_words < 4:
                # Quá ngắn: để khoảng thở âm nhạc
                text = ""

            sanitized.append({
                "id": i + 1,
                "start": round(start, 2),
                "end": round(end, 2),
                "duration": dur,
                "visual_desc": desc,
                "text": text,
                "max_words": max_words,
                "word_count": w_count,
            })
            last_end = end

        return sanitized

    # ──────────────────────────────────────────────────────────────────────────
    # BƯỚC 3: TỔNG HỢP GIỌNG ĐỌC TTS & PHỤ ĐỀ NHỊP ĐIỆU (AUDIO ANCHOR)
    # ──────────────────────────────────────────────────────────────────────────

    def synthesize_tts_and_subtitles(
        self,
        script_segments: List[Dict[str, Any]],
        voice: str = "hoai_my",
        tts_speed: float = 1.0,
    ) -> Tuple[Path, Path]:
        """Sinh giọng đọc cho toàn bộ phân cảnh, căn chỉnh timeline và tạo file ASS."""
        emit_progress(0.45, "Đang tổng hợp giọng đọc TTS (Ban Mai/Hoài My/Nam Minh)...", "vlog_story")
        voice_wav = self.workspace_dir / "vlog_voice.wav"
        ass_sub = self.workspace_dir / "vlog_subtitles.ass"

        aligned_audio_files: List[Path] = []
        current_time = 0.0
        all_dialogues: List[Dict[str, Any]] = []

        total = len(script_segments)
        for idx, seg in enumerate(script_segments, 1):
            seg_start = float(seg.get("start", 0.0))
            seg_end = float(seg.get("end", seg_start + 4.0))
            seg_dur = seg_end - seg_start
            text = seg.get("text", "").strip()

            out_seg_wav = self.tts_dir / f"tts_seg_{idx:04d}.wav"
            actual_tts_dur = 0.0

            if text:
                # Gọi MovieReviewTTS với MD5 cache
                actual_tts_dur = MovieReviewTTS.synthesize_single(
                    text=text,
                    out_file=out_seg_wav,
                    voice=voice,
                    speed_factor=tts_speed
                )

                # Adaptive Pacing: Nếu audio hơi dài hơn cảnh <= 25%, tăng tốc độ đọc nhẹ
                if actual_tts_dur > seg_dur and (actual_tts_dur / seg_dur) <= 1.25:
                    speedup = min(1.25, actual_tts_dur / seg_dur)
                    adjusted_wav = self.tts_dir / f"tts_seg_{idx:04d}_adj.wav"
                    cmd_tempo = [
                        "ffmpeg", "-y", "-i", str(out_seg_wav),
                        "-filter:a", f"atempo={speedup:.3f}",
                        "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", str(adjusted_wav)
                    ]
                    subprocess.run(cmd_tempo, capture_output=True)
                    if adjusted_wav.exists() and adjusted_wav.stat().st_size > 0:
                        out_seg_wav = adjusted_wav
                        actual_tts_dur = FFmpegUtils.get_audio_duration(adjusted_wav)
                else:
                    norm_wav = self.tts_dir / f"tts_seg_{idx:04d}_norm.wav"
                    cmd_norm = [
                        "ffmpeg", "-y", "-i", str(out_seg_wav),
                        "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le",
                        str(norm_wav)
                    ]
                    subprocess.run(cmd_norm, capture_output=True)
                    if norm_wav.exists() and norm_wav.stat().st_size > 0:
                        out_seg_wav = norm_wav
                        actual_tts_dur = FFmpegUtils.get_audio_duration(norm_wav)

            # Chèn khoảng lặng trước câu thoại nếu có khoảng cách
            if seg_start > current_time + 0.05:
                silence_gap = seg_start - current_time
                silence_file = self.tts_dir / f"silence_{idx:04d}.wav"
                subprocess.run([
                    "ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                    "-t", f"{silence_gap:.3f}", "-c:a", "pcm_s16le", str(silence_file)
                ], capture_output=True, check=True)
                aligned_audio_files.append(silence_file)
                current_time = seg_start

            audio_start_pos = current_time
            if out_seg_wav.exists() and out_seg_wav.stat().st_size > 0:
                aligned_audio_files.append(out_seg_wav)
                current_time += actual_tts_dur

                # Tạo phụ đề nhịp điệu Rhythmic Cues 4-6 từ
                cues = split_subtitle_into_rhythmic_cues(
                    text=text,
                    audio_duration=actual_tts_dur,
                    max_words_per_cue=5
                )
                for start_rel, end_rel, cue_text in cues:
                    all_dialogues.append({
                        "start": audio_start_pos + start_rel,
                        "end": audio_start_pos + end_rel,
                        "text": cue_text
                    })

            pct = 0.45 + (idx / total) * 0.25
            emit_progress(pct, f"Đã sinh giọng đọc {idx}/{total} câu...", "vlog_story")

        # Bù khoảng lặng cuối cùng nếu còn dư thời lượng video
        if self.duration > current_time + 0.05:
            final_gap = self.duration - current_time
            silence_end = self.tts_dir / "silence_final.wav"
            subprocess.run([
                "ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                "-t", f"{final_gap:.3f}", "-c:a", "pcm_s16le", str(silence_end)
            ], capture_output=True, check=True)
            aligned_audio_files.append(silence_end)

        # Ghép nối toàn bộ audio track
        concat_list = self.tts_dir / "concat_audio.txt"
        with open(concat_list, "w", encoding="utf-8") as f:
            for af in aligned_audio_files:
                f.write(f"file '{af.absolute()}'\n")

        subprocess.run([
            "ffmpeg", "-y", "-f", "concat", "-safe", "0",
            "-i", str(concat_list),
            "-c:a", "pcm_s16le", "-ar", "44100", "-ac", "2",
            str(voice_wav)
        ], capture_output=True, check=True)

        # Tạo file ASS phụ đề
        generate_vlog_ass_subtitles(
            dialogues=all_dialogues,
            output_ass_path=ass_sub,
            video_width=self.width,
            video_height=self.height,
            project_config=self.config
        )

        emit_log("info", f"✓ Đã tổng hợp toàn bộ giọng đọc và phụ đề ASS ({len(all_dialogues)} cues)", "vlog_story")
        return voice_wav, ass_sub

    # ──────────────────────────────────────────────────────────────────────────
    # BƯỚC 4: HÒA ÂM ĐA NGUỒN & SMART DUCKING
    # ──────────────────────────────────────────────────────────────────────────

    def mix_audio_track(
        self,
        voice_wav: Path,
        bgm_path: Optional[Path] = None,
        bgm_volume: float = 0.15,
        tts_volume: float = 1.0,
    ) -> Path:
        """Hòa âm giọng đọc với nhạc nền (âm thanh gốc hoặc BGM ngoài) kèm Smart Ducking."""
        emit_progress(0.75, "Đang hòa âm đa nguồn (Smart Ducking BGM)...", "vlog_story")
        mixed_wav = self.workspace_dir / "vlog_mixed.wav"

        has_bgm = bgm_path and Path(bgm_path).exists()
        use_original_audio = self.has_audio and not has_bgm
        effective_tts = max(0.0, min(2.0, float(tts_volume)))
        effective_bgm = max(0.0, min(1.0, float(bgm_volume)))

        if has_bgm:
            # Dùng file BGM ngoài (Loop và fade out)
            emit_log("info", f"Sử dụng nhạc nền ngoài: {Path(bgm_path).name} (BGM: {effective_bgm*100:.0f}%, TTS: {effective_tts*100:.0f}%)", "vlog_story")
            cmd = [
                "ffmpeg", "-y",
                "-i", str(voice_wav),
                "-stream_loop", "-1", "-i", str(bgm_path),
                "-filter_complex",
                f"[1:a]volume={effective_bgm:.2f},afade=t=out:st={max(0.0, self.duration - 2.0):.2f}:d=2.0[bgm];"
                f"[0:a]volume={effective_tts:.2f}[v_voice];[v_voice][bgm]amix=inputs=2:duration=first:dropout_transition=2[out]",
                "-map", "[out]",
                "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2",
                str(mixed_wav)
            ]
            subprocess.run(cmd, capture_output=True, check=True)

        elif use_original_audio:
            # Video có âm thanh gốc: Ducking âm lượng gốc xuống khi có giọng đọc
            emit_log("info", f"Áp dụng Smart Ducking lên âm thanh gốc của video (Gốc: {effective_bgm*100:.0f}%, TTS: {effective_tts*100:.0f}%)", "vlog_story")
            cmd = [
                "ffmpeg", "-y",
                "-i", str(voice_wav),
                "-i", str(self.video_path),
                "-filter_complex",
                f"[1:a]volume={effective_bgm:.2f}[ducked_bg];"
                f"[0:a]volume={effective_tts:.2f}[v_voice];[v_voice][ducked_bg]amix=inputs=2:duration=first:dropout_transition=2[out]",
                "-map", "[out]",
                "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2",
                str(mixed_wav)
            ]
            res = subprocess.run(cmd, capture_output=True)
            if res.returncode != 0 or not mixed_wav.exists():
                shutil.copy2(voice_wav, mixed_wav)

        else:
            # Video hoàn toàn câm và không có BGM ngoài
            if abs(effective_tts - 1.0) > 0.01:
                emit_log("info", f"Điều chỉnh âm lượng giọng đọc ({effective_tts*100:.0f}%)", "vlog_story")
                cmd = [
                    "ffmpeg", "-y",
                    "-i", str(voice_wav),
                    "-filter:a", f"volume={effective_tts:.2f}",
                    "-c:a", "pcm_s16le", "-ar", "48000", "-ac", "2",
                    str(mixed_wav)
                ]
                res = subprocess.run(cmd, capture_output=True)
                if res.returncode != 0 or not mixed_wav.exists():
                    shutil.copy2(voice_wav, mixed_wav)
            else:
                emit_log("info", "Video câm hoàn toàn, xuất trực tiếp giọng đọc làm master audio", "vlog_story")
                shutil.copy2(voice_wav, mixed_wav)

        return mixed_wav

    # ──────────────────────────────────────────────────────────────────────────
    # BƯỚC 5: RENDER VIDEO CUỐI & BẢN XUẤT OUTPUT (1:1 ZERO-CUT)
    # ──────────────────────────────────────────────────────────────────────────

    def render_final_video(
        self,
        mixed_audio: Path,
        ass_sub: Path,
        burn_subtitles: bool = True,
        enable_inpaint: bool = False,
        output_dir: Optional[Path] = None
    ) -> Path:
        """Ghép audio, inpaint, watermark và phụ đề ASS lên video gốc giữ nguyên 1:1 timeline."""
        emit_progress(0.85, "Đang kết xuất video hoàn thiện (1:1 Timeline)...", "vlog_story")

        raw_out = output_dir or (self.project_dir / "output")
        out_dir = safe_ensure_dir(raw_out, fallback_subdir="output")
        final_mp4 = out_dir / f"{self.safe_video_name}_vlog_story.mp4"

        is_mac = sys.platform == "darwin"
        video_codec = "h264_videotoolbox" if is_mac else "libx264"
        extra_args = ["-b:v", "6000k"] if is_mac else ["-preset", "fast", "-crf", "20"]

        inputs = ["-i", str(self.video_path), "-i", str(mixed_audio)]
        filter_complex_steps: List[str] = []
        current_stream = "[0:v]"

        # 1. Inpaint làm mờ phụ đề cũ (nếu bật)
        if enable_inpaint:
            inpaint_filter = build_inpaint_filter(self.width, self.height, self.config)
            if inpaint_filter:
                filter_complex_steps.append(f"{current_stream}{inpaint_filter}[v_inpaint]")
                current_stream = "[v_inpaint]"
                emit_log("info", "✓ Đã kích hoạt Inpaint làm mờ vùng phụ đề cũ trong Vlog.", "vlog_story")

        # 2. Watermark bản quyền (nếu bật trong self.config)
        wm_cfg = self.config.get("watermark", {})
        has_watermark = wm_cfg.get("enabled", False)
        if has_watermark and wm_cfg:
            current_stream, wm_filters = FFmpegUtils.build_watermark_filters(
                last_stream=current_stream,
                width=self.width,
                height=self.height,
                watermark_config=wm_cfg,
                inputs=inputs
            )
            filter_complex_steps.extend(wm_filters)
            emit_log("info", "✓ Đã kích hoạt vẽ Watermark bản quyền lên video Vlog.", "vlog_story")

        # 3. Phụ đề ASS kèm fontsdir chuẩn hóa
        if burn_subtitles and ass_sub.exists():
            fonts_dir = ROOT_DIR / "resources" / "fonts"
            fonts_arg = f":fontsdir='{fonts_dir}'" if fonts_dir.exists() else ""
            safe_ass_path = str(ass_sub).replace("\\", "/").replace(":", "\\:")
            filter_complex_steps.append(f"{current_stream}subtitles='{safe_ass_path}'{fonts_arg}[v_sub]")
            current_stream = "[v_sub]"
            emit_log("info", f"✓ Đã ghép phụ đề ASS nhịp điệu kèm font chuẩn: {ass_sub.name}", "vlog_story")

        t0 = time.time()

        if filter_complex_steps:
            full_fc = ";".join(filter_complex_steps)
            cmd = [
                "ffmpeg", "-y",
                *inputs,
                "-filter_complex", full_fc,
                "-map", current_stream,
                "-map", "1:a:0",
                "-c:v", video_codec,
                *extra_args,
                "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
                "-shortest",
                str(final_mp4)
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode != 0:
                emit_log("warning", f"Lỗi encoder {video_codec} ({res.stderr[:200]}), đang thử lại với libx264 tiêu chuẩn...", "vlog_story")
                cmd_fb = [
                    "ffmpeg", "-y",
                    *inputs,
                    "-filter_complex", full_fc,
                    "-map", current_stream,
                    "-map", "1:a:0",
                    "-c:v", "libx264", "-preset", "ultrafast", "-crf", "22",
                    "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
                    "-shortest",
                    str(final_mp4)
                ]
                subprocess.run(cmd_fb, capture_output=True, check=True)
        else:
            emit_log("info", "Remux video 1:1 siêu tốc không nén lại hình ảnh (Stream Copy)...", "vlog_story")
            cmd = [
                "ffmpeg", "-y",
                "-i", str(self.video_path),
                "-i", str(mixed_audio),
                "-c:v", "copy",
                "-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2",
                "-map", "0:v:0",
                "-map", "1:a:0",
                "-shortest",
                str(final_mp4)
            ]
            subprocess.run(cmd, capture_output=True, check=True)

        elapsed = time.time() - t0
        emit_progress(1.0, "Hoàn tất! Video đã sẵn sàng trong thư mục output.", "vlog_story")
        emit_log("info", f"🎉 Xuất video thành công trong {elapsed:.1f}s -> {final_mp4}", "vlog_story")
        return final_mp4


def main():
    parser = argparse.ArgumentParser(description="Vlog Story Orchestrator — Kể Chuyện Vlog Từ Hình Ảnh")
    parser.add_argument("input_video", help="Đường dẫn đến file video gốc")
    parser.add_argument("--action", default="full", choices=["generate_script", "preview_tts", "synthesize_tts", "render_video", "full"], help="Hành động cần thực thi")
    parser.add_argument("--style", default="daily_chill", choices=["daily_chill", "cinematic", "humorous", "auto"], help="Phong cách kịch bản")
    parser.add_argument("--prompt", default="", help="Prompt gợi ý ý tưởng / thông điệp")
    parser.add_argument("--voice", default="hoai_my", help="Mã giọng đọc (hoai_my, ban_mai, nam_minh)")
    parser.add_argument("--tts-speed", type=float, default=1.0, help="Tốc độ đọc TTS (1.0 đến 1.5)")
    parser.add_argument("--tts-volume", type=float, default=None, help="Âm lượng giọng đọc TTS (0.0 đến 2.0)")
    parser.add_argument("--engine", default="gemini", choices=["gemini", "ollama"], help="AI Engine phân tích thị giác")
    parser.add_argument("--bgm", default="", help="Đường dẫn file BGM ngoài")
    parser.add_argument("--bgm-volume", type=float, default=0.15, help="Âm lượng nhạc nền khi có giọng đọc")
    parser.add_argument("--no-burn-sub", action="store_true", help="Không in cứng phụ đề vào video")
    parser.add_argument("--enable-inpaint", action="store_true", default=False, help="Kích hoạt Inpaint làm mờ phụ đề cũ")
    parser.add_argument("--no-inpaint", action="store_true", default=False, help="Tắt Inpaint làm mờ phụ đề cũ")
    parser.add_argument("--preview-text", default="", help="Văn bản cần nghe thử TTS")
    parser.add_argument("--preview-out", default="", help="File audio xuất cho xem thử TTS")
    parser.add_argument("--json-output", action="store_true", help="Chỉ xuất kết quả dạng JSON thuần")

    args = parser.parse_args()

    # 1. Action: Preview TTS 1 câu đơn lẻ cho GUI
    if args.action == "preview_tts":
        text = args.preview_text.strip()
        out_p = Path(args.preview_out).resolve() if args.preview_out else Path("/tmp/vlog_tts_preview.mp3")
        dur = MovieReviewTTS.synthesize_single(text=text, out_file=out_p, voice=args.voice, speed_factor=args.tts_speed)
        res = {"success": out_p.exists() and out_p.stat().st_size > 0, "audio_path": str(out_p), "duration": dur}
        if args.json_output:
            print(json.dumps(res, ensure_ascii=False))
        else:
            emit_json(res)
        sys.exit(0)

    # 2. Khởi tạo Orchestrator
    orchestrator = VlogStoryOrchestrator(video_path=Path(args.input_video))

    # 3. Action: generate_script
    if args.action == "generate_script":
        segments = orchestrator.generate_script(
            style=args.style,
            custom_prompt=args.prompt,
            engine=args.engine,
            tts_speed=args.tts_speed
        )
        if args.json_output:
            print(json.dumps(segments, ensure_ascii=False))
        sys.exit(0)

    # 4. Action: synthesize_tts
    script_file = orchestrator.workspace_dir / "vlog_script.json"
    if not script_file.exists():
        segments = orchestrator.generate_script(style=args.style, custom_prompt=args.prompt, engine=args.engine, tts_speed=args.tts_speed)
    else:
        with open(script_file, "r", encoding="utf-8") as f:
            segments = json.load(f)

    if args.action == "synthesize_tts":
        voice_wav, ass_sub = orchestrator.synthesize_tts_and_subtitles(segments, voice=args.voice, tts_speed=args.tts_speed)
        sys.exit(0)

    # 5. Action: render_video hoặc full
    voice_wav, ass_sub = orchestrator.synthesize_tts_and_subtitles(segments, voice=args.voice, tts_speed=args.tts_speed)
    bgm_path = Path(args.bgm).resolve() if args.bgm else None

    # Phân giải cấu hình hiệu dụng cho audio & inpaint
    cfg_audio = orchestrator.config.get("audio", {}).get("volumes", {})
    cfg_inpaint = orchestrator.config.get("inpaint", {})

    effective_tts_volume = args.tts_volume if args.tts_volume is not None else float(cfg_audio.get("tts_voice", 1.0))
    if args.enable_inpaint:
        effective_enable_inpaint = True
    elif args.no_inpaint:
        effective_enable_inpaint = False
    else:
        effective_enable_inpaint = bool(cfg_inpaint.get("show_box", False))

    mixed_audio = orchestrator.mix_audio_track(
        voice_wav=voice_wav,
        bgm_path=bgm_path,
        bgm_volume=args.bgm_volume,
        tts_volume=effective_tts_volume
    )
    final_video = orchestrator.render_final_video(
        mixed_audio=mixed_audio,
        ass_sub=ass_sub,
        burn_subtitles=not args.no_burn_sub,
        enable_inpaint=effective_enable_inpaint
    )

    if args.json_output:
        print(json.dumps({"success": True, "output_video": str(final_video)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
