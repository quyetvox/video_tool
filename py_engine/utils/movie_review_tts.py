"""
movie_review_tts.py - Module tổng hợp giọng đọc độc lập chuyên trách cho Movie Review Studio.
Cover toàn bộ cơ chế chống rớt kết nối (Retry 5 lần), bộ đệm Cache MD5 và điều tốc âm thanh
từ Pipeline chính mà không làm ảnh hưởng đến mã nguồn của Pipeline Dịch Video.
"""

import asyncio
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple


def normalize_vietnamese_text(text: str) -> str:
    """Chuẩn hóa ký tự, số, đơn vị đo lường cho tiếng Việt."""
    t = text.strip()
    if not t:
        return ""

    # Ký hiệu tiền tệ
    t = re.sub(r'(\d+)\s*\$', r'\1 đô la', t)
    t = re.sub(r'\$\s*(\d+)', r'\1 đô la', t)
    t = re.sub(r'(\d+)\s*k(?=\s|$|[.,!?])', r'\1 nghìn', t, flags=re.IGNORECASE)
    t = re.sub(r'(\d+)\s*tr(?=\s|$|[.,!?])', r'\1 triệu', t, flags=re.IGNORECASE)

    # Đơn vị & Ký hiệu
    t = re.sub(r'(\d+)\s*%', r'\1 phần trăm', t)
    t = re.sub(r'(\d+)\s*km/h', r'\1 ki lô mét trên giờ', t, flags=re.IGNORECASE)
    t = re.sub(r'(\d+)\s*kg', r'\1 ki lô gam', t, flags=re.IGNORECASE)
    t = re.sub(r'(\d+)\s*m(?=\s|$|[.,!?])', r'\1 mét', t)

    # Từ viết tắt công nghệ phổ biến
    t = re.sub(r'\bAI\b', 'Ây Ai', t)
    t = re.sub(r'\bCEO\b', 'Si I Ô', t)

    # Dọn dẹp ký tự thừa
    t = re.sub(r'[\~\|\^\*]', '', t)
    t = re.sub(r'\s+', ' ', t).strip()
    return t


class MovieReviewTTS:
    """Bộ tổng hợp giọng đọc chuyên trách cho Movie Review: Retry 5 lần, Hash Cache MD5, Dual-Engine Fallback."""

    # Bảng ánh xạ mã giọng tường minh 1-1 (Translate Standard vs Movie Review UI)
    VOICE_MAP: Dict[str, Tuple[str, str]] = {
        # 1. Giọng Ban Mai (Google TTS - gTTS vi)
        "vi-VN-BanMai": ("gtts", "vi"),
        "ban_mai": ("gtts", "vi"),

        # 2. Giọng Hoài My (Microsoft EdgeTTS Nữ)
        "vi-VN-HoaiMyNeural": ("edge", "vi-VN-HoaiMyNeural"),
        "hoai_my": ("edge", "vi-VN-HoaiMyNeural"),

        # 3. Giọng Nam Minh (Microsoft EdgeTTS Nam)
        "vi-VN-NamMinhNeural": ("edge", "vi-VN-NamMinhNeural"),
        "nam_minh": ("edge", "vi-VN-NamMinhNeural"),
    }

    _CACHE_DIR: Optional[Path] = None

    @classmethod
    def get_cache_dir(cls) -> Path:
        if cls._CACHE_DIR is None:
            cache_dir = Path.home() / ".subvideo" / "tts_cache"
            cache_dir.mkdir(parents=True, exist_ok=True)
            cls._CACHE_DIR = cache_dir
        return cls._CACHE_DIR

    @classmethod
    def _get_cache_path(cls, text: str, voice_code: str, rate_str: str) -> Path:
        key = f"{text}_{voice_code}_{rate_str}".encode("utf-8")
        h = hashlib.md5(key).hexdigest()
        return cls.get_cache_dir() / f"{h}.mp3"

    @classmethod
    def resolve_voice(cls, voice: Optional[str]) -> Tuple[str, str]:
        """Phân giải mã giọng thành (engine_type, voice_code). Mặc định là Hoài My nếu không tìm thấy."""
        if not voice:
            return ("edge", "vi-VN-HoaiMyNeural")
        clean = voice.strip()
        if clean in cls.VOICE_MAP:
            return cls.VOICE_MAP[clean]
        # Thử case-insensitive
        for k, v in cls.VOICE_MAP.items():
            if k.lower() == clean.lower():
                return v
        return ("edge", "vi-VN-HoaiMyNeural")

    @classmethod
    def get_audio_duration(cls, audio_file: Path) -> float:
        """Đo thời lượng vật lý chính xác của file audio bằng ffprobe."""
        if not audio_file.exists() or audio_file.stat().st_size <= 500:
            return 0.0
        try:
            cmd = [
                "ffprobe", "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                str(audio_file)
            ]
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return float(res.stdout.strip())
        except Exception:
            return 0.0

    @classmethod
    async def _async_synth_edge_single(
        cls,
        text: str,
        voice_code: str,
        speed_factor: float,
        out_file: Path
    ) -> bool:
        """Sinh audio qua EdgeTTS với cơ chế Retry 5 lần và Exponential Backoff chống rớt WebSocket."""
        rate_pct = int(round((speed_factor - 1.0) * 100))
        rate_str = f"+{rate_pct}%" if rate_pct >= 0 else f"{rate_pct}%"

        # 1. Kiểm tra cache trên đĩa trước
        cache_file = cls._get_cache_path(text, voice_code, rate_str)
        if cache_file.exists() and cache_file.stat().st_size > 500:
            try:
                shutil.copy2(cache_file, out_file)
                return True
            except Exception:
                pass

        # 2. Vòng lặp Retry 5 lần
        for attempt in range(5):
            try:
                import edge_tts
                comm = edge_tts.Communicate(text, voice_code, rate=rate_str)
                await comm.save(str(out_file))

                if out_file.exists() and out_file.stat().st_size > 500:
                    try:
                        shutil.copy2(out_file, cache_file)
                    except Exception:
                        pass
                    return True

                if out_file.exists() and out_file.stat().st_size <= 500:
                    out_file.unlink(missing_ok=True)
            except Exception:
                if out_file.exists() and out_file.stat().st_size <= 500:
                    out_file.unlink(missing_ok=True)
                # Đợi theo lũy tiến ngẫu nhiên
                delay = 0.4 * (attempt + 1) + random.uniform(0.05, 0.15)
                await asyncio.sleep(delay)

        return False

    @classmethod
    def _synth_gtts_single(
        cls,
        text: str,
        out_file: Path,
        speed_factor: float = 1.0
    ) -> bool:
        """Sinh audio qua Google TTS (Ban Mai) kèm cache và FFmpeg atempo điều tốc."""
        rate_str = f"{speed_factor:.2f}"
        cache_file = cls._get_cache_path(text, "vi-VN-BanMai", rate_str)
        if cache_file.exists() and cache_file.stat().st_size > 500:
            try:
                shutil.copy2(cache_file, out_file)
                return True
            except Exception:
                pass

        try:
            from gtts import gTTS
            tts = gTTS(text=text, lang="vi")
            raw_tmp = out_file.parent / f"tmp_raw_{out_file.name}"
            tts.save(str(raw_tmp))

            if not raw_tmp.exists() or raw_tmp.stat().st_size < 300:
                raw_tmp.unlink(missing_ok=True)
                return False

            if abs(speed_factor - 1.0) > 0.05:
                cmd = [
                    "ffmpeg", "-y", "-i", str(raw_tmp),
                    "-filter:a", f"atempo={speed_factor:.2f}",
                    str(out_file)
                ]
                subprocess.run(cmd, capture_output=True, check=True)
                raw_tmp.unlink(missing_ok=True)
            else:
                shutil.move(str(raw_tmp), str(out_file))

            if out_file.exists() and out_file.stat().st_size > 500:
                try:
                    shutil.copy2(out_file, cache_file)
                except Exception:
                    pass
                return True
        except Exception:
            pass

        return False

    @classmethod
    def synthesize_single(
        cls,
        text: str,
        out_file: Path,
        voice: str = "hoai_my",
        speed_factor: float = 1.15,
        log_callback: Optional[Callable[[str, str], None]] = None
    ) -> float:
        """
        Tổng hợp giọng đọc cho một câu thoại đơn lẻ kèm fallback chéo an toàn.
        Trả về thời lượng vật lý thực tế của file audio sinh ra (chuẩn Audio-Anchor).
        """
        out_file.parent.mkdir(parents=True, exist_ok=True)
        norm_text = normalize_vietnamese_text(text)
        if not norm_text:
            return 0.0

        engine_type, voice_code = cls.resolve_voice(voice)
        success = False

        if engine_type == "gtts":
            # Ưu tiên gTTS Ban Mai
            success = cls._synth_gtts_single(norm_text, out_file, speed_factor)
            if not success:
                if log_callback:
                    log_callback("warning", f"gTTS Ban Mai gặp sự cố, tự động chuyển fallback EdgeTTS (Hoài My)...")
                success = asyncio.run(
                    cls._async_synth_edge_single(norm_text, "vi-VN-HoaiMyNeural", speed_factor, out_file)
                )
        else:
            # Ưu tiên EdgeTTS (Hoài My hoặc Nam Minh) với 5 lần retry
            success = asyncio.run(
                cls._async_synth_edge_single(norm_text, voice_code, speed_factor, out_file)
            )
            if not success:
                # Nếu EdgeTTS sau 5 lần retry vẫn rớt mạng -> Fallback sang gTTS Ban Mai
                if log_callback:
                    log_callback("warning", f"EdgeTTS ({voice_code}) sau 5 lần retry rớt mạng, chuyển fallback sang gTTS Ban Mai...")
                success = cls._synth_gtts_single(norm_text, out_file, speed_factor)

        # Fallback khẩn cấp nếu cả hai vẫn chưa ra file
        if not success or not out_file.exists() or out_file.stat().st_size < 500:
            # Thử lại lần cuối với giọng EdgeTTS Nam Minh
            asyncio.run(
                cls._async_synth_edge_single(norm_text, "vi-VN-NamMinhNeural", speed_factor, out_file)
            )

        if out_file.exists():
            return cls.get_audio_duration(out_file)
        return 0.0

    @classmethod
    def synthesize_script(
        cls,
        script_items: List[Dict[str, Any]],
        output_dir: Path,
        voice: str = "hoai_my",
        speed_factor: float = 1.15,
        log_callback: Optional[Callable[[str, str], None]] = None,
        progress_callback: Optional[Callable[[float, str], None]] = None,
        start_progress: float = 0.0,
        end_progress: float = 0.30
    ) -> List[Dict[str, Any]]:
        """Tổng hợp giọng đọc cho toàn bộ kịch bản phân đoạn Storyboard."""
        output_dir.mkdir(parents=True, exist_ok=True)
        engine_type, voice_code = cls.resolve_voice(voice)

        if log_callback:
            log_callback("info", f"Bắt đầu sinh giọng đọc {voice} (engine: {engine_type}, mã: {voice_code}, tốc độ: {speed_factor:.2f}x)...")

        updated_items = []
        total = len(script_items)

        for i, item in enumerate(script_items):
            raw_text = item.get("voiceover_text", "").strip()
            item_id = item.get("id", i + 1)
            audio_path = output_dir / f"voice_{item_id:03d}.mp3"

            if not raw_text:
                continue

            dur = cls.synthesize_single(
                text=raw_text,
                out_file=audio_path,
                voice=voice,
                speed_factor=speed_factor,
                log_callback=log_callback
            )

            item_copy = dict(item)
            item_copy["audio_file"] = str(audio_path.name)
            item_copy["audio_duration"] = round(dur, 2)
            updated_items.append(item_copy)

            if progress_callback:
                pct = start_progress + (end_progress - start_progress) * ((i + 1) / max(1, total))
                progress_callback(
                    pct,
                    f"Đang sinh giọng đọc AI ({i+1}/{total})..."
                )

        return updated_items
