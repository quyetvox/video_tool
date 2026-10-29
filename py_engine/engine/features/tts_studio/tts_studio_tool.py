#!/usr/bin/env python3
"""
py_engine/tts_studio_tool.py
=============================
Standalone CLI tool & orchestrator for TTS Studio (Tạo Giọng Đọc Từ Kịch Bản).

Supports:
1. Voice catalog listing (Vietnamese & Curated English voices: US, UK, AU).
2. Language-aware text normalization & intelligent sentence splitting.
3. Single-segment instant preview with MD5 caching and speed/pitch control.
4. Full batch synthesis with async concurrency, sentence pause insertion,
   FFmpeg concatenation, and millisecond-accurate SRT/VTT subtitle generation.
"""

from __future__ import annotations

try:
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
except ModuleNotFoundError:
    import sys as _sys
    from pathlib import Path as _P
    _sys.path.insert(0, str(next(p.parent for p in _P(__file__).resolve().parents if p.name == "engine")))
    from engine.paths import ENGINE_DIR as _ENGINE_DIR
import argparse
import asyncio
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT_PY = _ENGINE_DIR
if str(ROOT_PY) not in sys.path:
    sys.path.insert(0, str(ROOT_PY))

try:
    from engine.features.tts_studio.narration_voice_generator import TIMESTAMP_LINE_PATTERN, import_narration_script
except ImportError:
    TIMESTAMP_LINE_PATTERN = None
    import_narration_script = None

# Voice Catalog: Curated High-Quality Voices
VOICE_CATALOG: List[Dict[str, Any]] = [
    # --- Vietnamese ---
    {
        "id": "vi-VN-HoaiMyNeural",
        "name": "Hoài My",
        "lang": "vi",
        "region": "VN",
        "gender": "female",
        "desc": "Nữ miền Bắc truyền cảm, tự nhiên",
        "engine": "edge",
    },
    {
        "id": "vi-VN-NamMinhNeural",
        "name": "Nam Minh",
        "lang": "vi",
        "region": "VN",
        "gender": "male",
        "desc": "Nam miền Bắc ấm áp, đĩnh đạc",
        "engine": "edge",
    },
    {
        "id": "vi-VN-BanMai",
        "name": "Ban Mai",
        "lang": "vi",
        "region": "VN",
        "gender": "female",
        "desc": "Nữ giọng phổ thông quen thuộc (Google TTS)",
        "engine": "gtts",
    },
    {
        "id": "gtts_vi",
        "name": "Ban Mai (Alias)",
        "lang": "vi",
        "region": "VN",
        "gender": "female",
        "desc": "Nữ giọng phổ thông quen thuộc",
        "engine": "gtts",
    },
    # --- English (US) ---
    {
        "id": "en-US-JennyNeural",
        "name": "Jenny (US)",
        "lang": "en",
        "region": "US",
        "gender": "female",
        "desc": "Nữ Mỹ tự nhiên, thân thiện, diễn cảm (vlog, giới thiệu)",
        "engine": "edge",
    },
    {
        "id": "en-US-GuyNeural",
        "name": "Guy (US)",
        "lang": "en",
        "region": "US",
        "gender": "male",
        "desc": "Nam Mỹ tự nhiên, phóng khoáng (podcast, tin tức)",
        "engine": "edge",
    },
    {
        "id": "en-US-AriaNeural",
        "name": "Aria (US)",
        "lang": "en",
        "region": "US",
        "gender": "female",
        "desc": "Nữ Mỹ trang trọng, dẫn chuyện (kể chuyện, sách)",
        "engine": "edge",
    },
    {
        "id": "en-US-ChristopherNeural",
        "name": "Christopher (US)",
        "lang": "en",
        "region": "US",
        "gender": "male",
        "desc": "Nam Mỹ trầm ấm, uy quyền",
        "engine": "edge",
    },
    # --- English (UK) ---
    {
        "id": "en-GB-SoniaNeural",
        "name": "Sonia (UK)",
        "lang": "en",
        "region": "GB",
        "gender": "female",
        "desc": "Nữ Anh London sắc sảo, tự nhiên",
        "engine": "edge",
    },
    {
        "id": "en-GB-RyanNeural",
        "name": "Ryan (UK)",
        "lang": "en",
        "region": "GB",
        "gender": "male",
        "desc": "Nam Anh chuẩn giọng truyền cảm",
        "engine": "edge",
    },
    # --- English (AU) ---
    {
        "id": "en-AU-NatashaNeural",
        "name": "Natasha (AU)",
        "lang": "en",
        "region": "AU",
        "gender": "female",
        "desc": "Nữ Úc hiện đại, trong trẻo",
        "engine": "edge",
    },
    {
        "id": "en-AU-WilliamNeural",
        "name": "William (AU)",
        "lang": "en",
        "region": "AU",
        "gender": "male",
        "desc": "Nam Úc tự nhiên, đĩnh đạc",
        "engine": "edge",
    },
]


def get_cache_dir() -> Path:
    """Get persistent TTS cache directory with auto-pruning."""
    try:
        from engine.features.tts_studio.tts_cache_manager import get_tts_cache_dir, auto_clean_tts_cache
        cache_dir = get_tts_cache_dir()
        auto_clean_tts_cache(cache_dir=cache_dir)
        return cache_dir
    except Exception:
        cache_dir = Path.home() / ".subvideo" / "tts_cache"
        cache_dir.mkdir(parents=True, exist_ok=True)
        return cache_dir


def speed_to_rate_str(speed: float) -> str:
    """Convert numeric speed factor (e.g. 1.20) to EdgeTTS rate string (+20%)."""
    clamped_speed = max(0.5, min(2.5, speed))
    rate_percent = int(round((clamped_speed - 1.0) * 100))
    return f"{rate_percent:+d}%"


def pitch_to_str(pitch: int) -> str:
    """Convert pitch int (-50 to +50) to EdgeTTS pitch string."""
    clamped_pitch = max(-50, min(50, pitch))
    return f"{clamped_pitch:+d}Hz"


def normalize_vietnamese_text(text: str) -> str:
    """Clean & normalize Vietnamese text for natural TTS output."""
    t = text.strip()
    if not t:
        return ""
    # Currency
    t = re.sub(r'(\d+)\s*\$', r'\1 đô la', t)
    t = re.sub(r'\$\s*(\d+)', r'\1 đô la', t)
    t = re.sub(r'(\d+)\s*k(?=\s|$|[.,!?])', r'\1 nghìn', t, flags=re.IGNORECASE)
    t = re.sub(r'(\d+)\s*tr(?=\s|$|[.,!?])', r'\1 triệu', t, flags=re.IGNORECASE)
    # Symbols & Units
    t = re.sub(r'(\d+)\s*%', r'\1 phần trăm', t)
    t = re.sub(r'(\d+)\s*km/h', r'\1 ki lô mét trên giờ', t, flags=re.IGNORECASE)
    t = re.sub(r'(\d+)\s*kg', r'\1 ki lô gam', t, flags=re.IGNORECASE)
    t = re.sub(r'(\d+)\s*m(?=\s|$|[.,!?])', r'\1 mét', t)
    # Acronyms
    t = re.sub(r'\bAI\b', 'Ây Ai', t)
    t = re.sub(r'\bCEO\b', 'Si I Ô', t)
    # Strip markdown & noise
    t = re.sub(r'[\~\|\^\*#_`]', '', t)
    t = re.sub(r'\s+', ' ', t).strip()
    return t


def normalize_english_text(text: str) -> str:
    """Clean & normalize English text for natural TTS output."""
    t = text.strip()
    if not t:
        return ""
    # Currency
    t = re.sub(r'\$\s*(\d+(?:\.\d+)?)', r'\1 dollars', t)
    t = re.sub(r'(\d+(?:\.\d+)?)\s*\$', r'\1 dollars', t)
    t = re.sub(r'£\s*(\d+(?:\.\d+)?)', r'\1 pounds', t)
    t = re.sub(r'€\s*(\d+(?:\.\d+)?)', r'\1 euros', t)
    # Percentage
    t = re.sub(r'(\d+)\s*%', r'\1 percent', t)
    # Curly quotes to standard quotes
    t = t.replace('“', '"').replace('”', '"').replace('‘', "'").replace('’', "'")
    t = t.replace('—', ' - ').replace('–', ' - ')
    # Strip markdown formatting
    t = re.sub(r'[\~\|\^\*#_`]', '', t)
    t = re.sub(r'\s+', ' ', t).strip()
    return t


def normalize_text_by_voice(text: str, voice: str) -> str:
    """Apply appropriate language normalization based on voice selection."""
    v = voice.lower()
    if v.startswith("vi-") or "gtts_vi" in v or "banmai" in v or "hoaimy" in v or "namminh" in v:
        return normalize_vietnamese_text(text)
    return normalize_english_text(text)


def split_script_into_segments(
    raw_text: str,
    max_segment_chars: int = 160,
    speed: float = 1.0,
    pause_sec: float = 0.35,
) -> List[Dict[str, Any]]:
    """
    Intelligently split raw script into readable sentences / phrases and compute audio timings.
    - If raw_text contains timestamp brackets (e.g. [0:00.80 - 0:05.40]), parses explicit timings.
    - Otherwise splits by double newline and sentence delimiters (. ? ! ;), then calculates
      audio timings based on word count and speech speed rate ((140 * speed) / 60 wps).
    """
    if not raw_text or not raw_text.strip():
        return []

    # If script contains timestamp markers, use narration script parser
    if TIMESTAMP_LINE_PATTERN is not None and import_narration_script is not None:
        try:
            lines = raw_text.splitlines()
            has_timestamps = any(TIMESTAMP_LINE_PATTERN.match(l.strip()) for l in lines if l.strip())
            if has_timestamps:
                return import_narration_script(raw_text, speed=speed, pause_sec=pause_sec)
        except Exception:
            pass

    cleaned = raw_text.replace('\r\n', '\n').replace('\r', '\n')
    paragraphs = [p.strip() for p in cleaned.split('\n') if p.strip()]

    raw_sentences: List[str] = []
    sentence_pattern = re.compile(r'(?<=[.?!;…])\s+')

    for para in paragraphs:
        # Check if line looks like markdown bullet or numbered list
        para_clean = re.sub(r'^\s*[-*•\d+.]\s*', '', para).strip()
        if not para_clean:
            continue
        parts = sentence_pattern.split(para_clean)
        for part in parts:
            part = part.strip()
            # Clean residual bracket timestamps if any slipped through
            part = re.sub(r'^\s*[\[\(][\d\s:.,\-_–—−~>]+[\]\)]\s*[:\-]?\s*', '', part).strip()
            if part:
                raw_sentences.append(part)

    # Sub-divide overly long sentences on comma/dash
    final_segments: List[str] = []
    for s in raw_sentences:
        if len(s) <= max_segment_chars:
            final_segments.append(s)
        else:
            # Try comma splitting
            sub_parts = re.split(r'(?<=,)\s+', s)
            current_chunk = ""
            for sp in sub_parts:
                sp = sp.strip()
                if not sp:
                    continue
                if len(current_chunk) + len(sp) + 1 <= max_segment_chars:
                    current_chunk = f"{current_chunk} {sp}".strip()
                else:
                    if current_chunk:
                        final_segments.append(current_chunk)
                    current_chunk = sp
            if current_chunk:
                final_segments.append(current_chunk)

    result: List[Dict[str, Any]] = []
    current_time = 0.0
    speed_factor = max(0.5, min(2.5, speed))
    words_per_sec = (140.0 * speed_factor) / 60.0

    for idx, seg_text in enumerate(final_segments, start=1):
        seg_text = seg_text.strip()
        if not seg_text:
            continue
        words = seg_text.split()
        word_count = len(words)
        dur = round(max(0.8, word_count / words_per_sec), 3)
        start_sec = round(current_time, 3)
        end_sec = round(start_sec + dur, 3)
        current_time = round(end_sec + pause_sec, 3)

        result.append({
            "id": idx,
            "text": seg_text,
            "word_count": word_count,
            "char_count": len(seg_text),
            "start_sec": start_sec,
            "end_sec": end_sec,
            "duration": dur,
            "estimated_duration": dur,
            "has_explicit_timestamps": False,
        })

    return result


def get_audio_duration_ffprobe(audio_path: Path) -> float:
    """Measure exact physical audio duration using ffprobe."""
    try:
        cmd = [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(audio_path)
        ]
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return max(0.1, float(res.stdout.strip()))
    except Exception:
        # Fallback estimation if ffprobe not available
        try:
            size = audio_path.stat().st_size
            # 128kbps mp3 approximation: 16000 bytes/sec
            return max(0.5, size / 16000.0)
        except Exception:
            return 1.0


def calculate_timeline_speed(
    text: str,
    slot_duration: float,
    base_speed: float = 1.0,
    wpm: float = 140.0,
) -> Tuple[float, bool]:
    """
    Calculate required TTS speed to fit within slot_duration [start_sec, end_sec].
    Invariants:
    1. Speed Floor: Must NOT fall below base_speed configured by user.
    2. Auto Speed Boost: If words exceed the time slot at base_speed, automatically increase
       speed with NO ceiling (can scale to 2.5x, 3.0x+) so the sentence completes in time.
    3. Normal/Short Sentences: Keep base_speed strictly. Remaining time in slot becomes silence pause.
    Returns: (applied_speed, is_boosted).
    """
    safe_slot = max(0.1, float(slot_duration))
    base_spd = max(0.5, float(base_speed))
    clean_txt = (text or "").strip()
    words = clean_txt.split()
    word_count = len(words)
    char_count = len(clean_txt)

    # Check for CJK characters (Chinese, Japanese, Korean) without space-delimited words
    is_cjk = any("\u4e00" <= c <= "\u9fff" or "\u3040" <= c <= "\u30ff" or "\uac00" <= c <= "\ud7af" for c in clean_txt)
    if is_cjk:
        est_dur_1x = max(0.4, char_count / 3.5)
    else:
        words_per_sec = wpm / 60.0  # 2.333 words/sec
        est_dur_1x = max(0.4, word_count / words_per_sec) if word_count > 0 else 0.5

    # Duration when spoken naturally at base_speed
    est_dur_at_base = est_dur_1x / base_spd

    # If sentence comfortably fits in slot at base_speed (with 0.05s tolerance), KEEP BASE SPEED!
    if est_dur_at_base <= safe_slot + 0.05:
        return round(base_spd, 2), False

    # Only when sentence cannot fit in slot at base_speed, boost speed to fit within slot
    required_speed = est_dur_1x / safe_slot
    applied_speed = max(base_spd, required_speed)
    is_boosted = applied_speed > (base_spd + 0.04)

    return round(applied_speed, 2), is_boosted


def fine_tune_audio_duration(
    audio_path: Path,
    target_slot_sec: float,
    output_path: Optional[Path] = None,
) -> Tuple[Path, float]:
    """
    Two-Stage Fine-tuning:
    If audio_path duration > target_slot_sec, applies FFmpeg atempo filter to compress
    the audio to fit strictly within target_slot_sec.
    Supports multi-stage atempo when scale factor > 2.0 (e.g. atempo=2.0,atempo=1.5).
    """
    if not audio_path.exists():
        return audio_path, 0.0

    current_dur = get_audio_duration_ffprobe(audio_path)
    target_slot = max(0.1, float(target_slot_sec))

    out_file = output_path or audio_path

    # If already within slot (or within 50ms tolerance), no atempo compression needed
    if current_dur <= target_slot + 0.05:
        if out_file != audio_path:
            shutil.copy2(audio_path, out_file)
        return out_file, current_dur

    scale_factor = current_dur / target_slot

    filters = []
    rem = scale_factor
    while rem > 2.0:
        filters.append("atempo=2.0")
        rem /= 2.0
    if rem > 1.01:
        filters.append(f"atempo={rem:.3f}")

    if not filters:
        if out_file != audio_path:
            shutil.copy2(audio_path, out_file)
        return out_file, current_dur

    filter_str = ",".join(filters)
    tmp_out = out_file.parent / f"_ft_{os.getpid()}_{out_file.name}"
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-i", str(audio_path),
        "-filter:a", filter_str,
        "-acodec", "libmp3lame", "-q:a", "2",
        str(tmp_out)
    ]
    try:
        res = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if res.returncode == 0 and tmp_out.exists() and tmp_out.stat().st_size > 200:
            tmp_out.replace(out_file)
            new_dur = get_audio_duration_ffprobe(out_file)
            return out_file, new_dur
    except Exception:
        pass
    finally:
        tmp_out.unlink(missing_ok=True)

    if out_file != audio_path:
        shutil.copy2(audio_path, out_file)
    return out_file, current_dur


async def synth_segment_async(
    text: str,
    voice: str,
    speed: float = 1.0,
    pitch: int = 0,
    output_path: Optional[Path] = None,
    sem: Optional[asyncio.Semaphore] = None,
) -> Tuple[Path, float, bool]:
    """
    Synthesize a single text segment to audio file.
    Uses MD5 cache and retry mechanism.
    Returns: (output_file_path, duration_seconds, is_success).
    """
    norm_text = normalize_text_by_voice(text, voice)
    if not norm_text:
        return Path(""), 0.0, False

    rate_str = speed_to_rate_str(speed)
    pitch_str = pitch_to_str(pitch)

    # Cache lookup
    cache_dir = get_cache_dir()
    cache_key = f"{norm_text}_{voice}_{rate_str}_{pitch_str}".encode("utf-8")
    cache_file = cache_dir / f"{hashlib.md5(cache_key).hexdigest()}.mp3"

    target_out = output_path or cache_file

    if cache_file.exists() and cache_file.stat().st_size > 500:
        if target_out != cache_file:
            try:
                shutil.copy2(cache_file, target_out)
            except Exception:
                pass
        dur = get_audio_duration_ffprobe(target_out)
        return target_out, dur, True

    async def _do_synth():
        # Case A: gTTS (Ban Mai)
        if voice.lower() in ("gtts_vi", "ban_mai", "banmai", "vi-vn-banmai", "vi-banmai"):
            loop = asyncio.get_event_loop()
            def _run_gtts():
                from gtts import gTTS
                raw_temp = cache_file.with_suffix(f".raw_{os.getpid()}.mp3")
                tts = gTTS(text=norm_text, lang="vi")
                tts.save(str(raw_temp))
                if raw_temp.exists() and raw_temp.stat().st_size > 500:
                    temp_p = cache_file.with_suffix(".tmp.mp3")
                    if abs(speed - 1.0) > 0.01:
                        spd = max(0.5, min(2.5, speed))
                        atempo_filter = f"atempo={spd:.3f}" if spd <= 2.0 else f"atempo=2.0,atempo={spd / 2.0:.3f}"
                        cmd = [
                            "ffmpeg", "-y", "-loglevel", "error",
                            "-i", str(raw_temp),
                            "-filter:a", atempo_filter,
                            "-acodec", "libmp3lame", "-q:a", "2",
                            str(temp_p),
                        ]
                        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        raw_temp.unlink(missing_ok=True)
                    else:
                        raw_temp.replace(temp_p)

                    if temp_p.exists() and temp_p.stat().st_size > 500:
                        temp_p.replace(cache_file)
                        return True
                return False

            ok = await loop.run_in_executor(None, _run_gtts)
            if ok and cache_file.exists():
                if target_out != cache_file:
                    shutil.copy2(cache_file, target_out)
                dur = get_audio_duration_ffprobe(target_out)
                return target_out, dur, True
            return Path(""), 0.0, False

        # Case B: EdgeTTS
        import edge_tts
        last_err = ""
        for attempt in range(4):
            temp_p = cache_file.with_suffix(f".tmp_{os.getpid()}_{attempt}.mp3")
            try:
                communicate = edge_tts.Communicate(norm_text, voice, rate=rate_str, pitch=pitch_str)
                await communicate.save(str(temp_p))
                if temp_p.exists() and temp_p.stat().st_size > 500:
                    temp_p.replace(cache_file)
                    if target_out != cache_file:
                        shutil.copy2(cache_file, target_out)
                    dur = get_audio_duration_ffprobe(target_out)
                    return target_out, dur, True
                if temp_p.exists():
                    temp_p.unlink(missing_ok=True)
            except Exception as e:
                last_err = str(e)
                if temp_p.exists():
                    temp_p.unlink(missing_ok=True)
                await asyncio.sleep(0.3 * (attempt + 1) + random.uniform(0.05, 0.15))

        # Case C: Resilient Fallback to gTTS if EdgeTTS failed
        try:
            from gtts import gTTS
            lang = "vi" if (voice.lower().startswith("vi-") or "banmai" in voice.lower()) else "en"
            loop = asyncio.get_event_loop()

            def _run_gtts_fallback():
                raw_temp = cache_file.with_suffix(f".gtts_raw_{os.getpid()}.mp3")
                tts = gTTS(text=norm_text, lang=lang)
                tts.save(str(raw_temp))
                if raw_temp.exists() and raw_temp.stat().st_size > 500:
                    temp_p = cache_file.with_suffix(f".tmp_gtts_{os.getpid()}.mp3")
                    if abs(speed - 1.0) > 0.01:
                        spd = max(0.5, min(2.5, speed))
                        atempo_filter = f"atempo={spd:.3f}" if spd <= 2.0 else f"atempo=2.0,atempo={spd / 2.0:.3f}"
                        cmd = [
                            "ffmpeg", "-y", "-loglevel", "error",
                            "-i", str(raw_temp),
                            "-filter:a", atempo_filter,
                            "-acodec", "libmp3lame", "-q:a", "2",
                            str(temp_p),
                        ]
                        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        raw_temp.unlink(missing_ok=True)
                    else:
                        raw_temp.replace(temp_p)

                    if temp_p.exists() and temp_p.stat().st_size > 500:
                        temp_p.replace(cache_file)
                        return True
                return False

            ok = await loop.run_in_executor(None, _run_gtts_fallback)
            if ok and cache_file.exists():
                if target_out != cache_file:
                    shutil.copy2(cache_file, target_out)
                dur = get_audio_duration_ffprobe(target_out)
                return target_out, dur, True
        except Exception:
            pass

        return Path(""), 0.0, False

    if sem is not None:
        async with sem:
            return await _do_synth()
    else:
        return await _do_synth()


def generate_silence_audio(duration: float, output_path: Path) -> bool:
    """Generate precise silent MP3 audio of given duration via FFmpeg."""
    try:
        cmd = [
            "ffmpeg", "-y",
            "-f", "lavfi",
            "-i", f"anullsrc=r=24000:cl=mono",
            "-t", f"{duration:.3f}",
            "-c:a", "libmp3lame",
            "-b:a", "64k",
            str(output_path)
        ]
        res = subprocess.run(cmd, capture_output=True)
        return res.returncode == 0 and output_path.exists() and output_path.stat().st_size > 100
    except Exception:
        return False


def format_srt_time(seconds: float) -> str:
    """Format seconds into SRT timestamp HH:MM:SS,mmm."""
    hrs = int(seconds // 3600)
    mins = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    millis = int(round((seconds - int(seconds)) * 1000))
    if millis >= 1000:
        secs += 1
        millis = 0
    return f"{hrs:02d}:{mins:02d}:{secs:02d},{millis:03d}"


def format_vtt_time(seconds: float) -> str:
    """Format seconds into WebVTT timestamp HH:MM:SS.mmm."""
    hrs = int(seconds // 3600)
    mins = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    millis = int(round((seconds - int(seconds)) * 1000))
    if millis >= 1000:
        secs += 1
        millis = 0
    return f"{hrs:02d}:{mins:02d}:{secs:02d}.{millis:03d}"


async def render_full_batch(
    segments: List[Dict[str, Any]],
    default_voice: str,
    default_speed: float,
    default_pitch: int,
    pause_sec: float,
    output_audio: Path,
    output_srt: Optional[Path] = None,
    output_vtt: Optional[Path] = None,
    concurrency: int = 4,
    lock_timeline: bool = False,
) -> Dict[str, Any]:
    """
    Synthesize all segments concurrently, concatenate with silence pauses,
    and generate perfectly synchronized SRT / VTT subtitles.
    If lock_timeline is True:
    - Maintains exact [start, end] timeline for each sentence.
    - Strictly follows base_speed floor (never drops below).
    - Automatically boosts speed if word count exceeds slot duration.
    - Two-stage precision fine-tuning with atempo if audio duration > slot.
    - Waits in silence until the next sentence start time.
    """
    temp_dir = output_audio.parent / f"_tts_temp_{os.getpid()}"
    temp_dir.mkdir(parents=True, exist_ok=True)

    sem = asyncio.Semaphore(concurrency)
    tasks = []

    # Check if segments contain explicit timestamps
    has_explicit = any(
        (s.get("start_sec") is not None and s.get("end_sec") is not None) or
        (s.get("start") is not None and s.get("end") is not None)
        for s in segments
    )
    is_timeline_mode = lock_timeline or (has_explicit and lock_timeline is not False)

    for seg in segments:
        seg_id = seg.get("id", 1)
        text = seg.get("text", "")
        voice = seg.get("voice") or default_voice
        base_spd = float(seg.get("speed") or default_speed)
        pitch = int(seg.get("pitch") if seg.get("pitch") is not None else default_pitch)

        is_boosted = False
        applied_spd = base_spd
        if is_timeline_mode:
            s_sec = float(seg.get("start_sec") if seg.get("start_sec") is not None else (seg.get("start") or 0.0))
            e_sec = float(seg.get("end_sec") if seg.get("end_sec") is not None else (seg.get("end") or s_sec + 2.0))
            slot_dur = max(0.1, e_sec - s_sec)
            applied_spd, is_boosted = calculate_timeline_speed(text, slot_duration=slot_dur, base_speed=base_spd)

        seg_out = temp_dir / f"seg_{seg_id:04d}.mp3"
        tasks.append((seg_id, seg, applied_spd, is_boosted, synth_segment_async(text, voice, applied_spd, pitch, seg_out, sem)))

    # Run all syntheses
    synth_results = {}
    for seg_id, seg, applied_spd, is_boosted, coro in tasks:
        out_p, dur, ok = await coro

        # Stage 2: Fine-tune duration with atempo if timeline mode is enabled
        if is_timeline_mode and ok and out_p.exists():
            s_sec = float(seg.get("start_sec") if seg.get("start_sec") is not None else (seg.get("start") or 0.0))
            e_sec = float(seg.get("end_sec") if seg.get("end_sec") is not None else (seg.get("end") or s_sec + 2.0))
            slot_dur = max(0.1, e_sec - s_sec)
            if dur > slot_dur + 0.05:
                out_p, dur = fine_tune_audio_duration(out_p, target_slot_sec=slot_dur)

        synth_results[seg_id] = {
            "path": out_p,
            "duration": dur,
            "success": ok,
            "text": seg.get("text", ""),
            "effective_speed": applied_spd,
            "is_boosted": is_boosted,
        }

    concat_lines = []
    srt_entries = []
    vtt_entries = ["WEBVTT\n"]
    current_time = 0.0
    processed_segments = []

    if is_timeline_mode:
        # ── TIMELINE LOCKED MODE ──────────────────────────────────────
        silence_idx = 0
        for idx, seg in enumerate(segments, start=1):
            seg_id = seg.get("id", idx)
            info = synth_results.get(seg_id)
            if not info or not info["success"] or not info["path"].exists():
                continue

            seg_path = info["path"]
            dur = info["duration"]

            target_start = float(seg.get("start_sec") if seg.get("start_sec") is not None else (seg.get("start") or current_time))
            target_end = float(seg.get("end_sec") if seg.get("end_sec") is not None else (seg.get("end") or target_start + dur))

            # 1. Fill leading silence gap before target_start
            if target_start > current_time:
                gap = round(target_start - current_time, 3)
                if gap >= 0.02:
                    silence_file = temp_dir / f"silence_gap_{silence_idx:04d}.mp3"
                    silence_idx += 1
                    if generate_silence_audio(gap, silence_file):
                        concat_lines.append(f"file '{silence_file.resolve()}'\n")
                current_time = target_start

            # 2. Add speech audio segment
            concat_lines.append(f"file '{seg_path.resolve()}'\n")
            current_time = round(target_start + dur, 3)

            # 3. Lookahead next segment start or slot end to insert silence pause
            next_start = None
            if idx < len(segments):
                next_seg = segments[idx]
                next_start = float(next_seg.get("start_sec") if next_seg.get("start_sec") is not None else (next_seg.get("start") or target_end))
            else:
                next_start = target_end

            if next_start > current_time:
                rest_gap = round(next_start - current_time, 3)
                if rest_gap >= 0.02:
                    silence_file = temp_dir / f"silence_gap_{silence_idx:04d}.mp3"
                    silence_idx += 1
                    if generate_silence_audio(rest_gap, silence_file):
                        concat_lines.append(f"file '{silence_file.resolve()}'\n")
                current_time = next_start

            # Subtitle uses original designated timeline slot
            srt_entries.append(
                f"{idx}\n{format_srt_time(target_start)} --> {format_srt_time(target_end)}\n{info['text']}\n"
            )
            vtt_entries.append(
                f"\n{format_vtt_time(target_start)} --> {format_vtt_time(target_end)}\n{info['text']}\n"
            )

            processed_segments.append({
                "id": seg_id,
                "text": info["text"],
                "start": round(target_start, 3),
                "end": round(target_end, 3),
                "duration": round(dur, 3),
                "audio_file": str(seg_path),
                "effective_speed": info.get("effective_speed", default_speed),
                "is_boosted": info.get("is_boosted", False),
            })

    else:
        # ── SEQUENTIAL FREE-FORM MODE ──────────────────────────────────
        silence_file = temp_dir / "silence_pause.mp3"
        has_pause = pause_sec > 0.05 and generate_silence_audio(pause_sec, silence_file)

        for idx, seg in enumerate(segments, start=1):
            seg_id = seg.get("id", idx)
            info = synth_results.get(seg_id)
            if not info or not info["success"] or not info["path"].exists():
                continue

            seg_path = info["path"]
            dur = info["duration"]

            start_time = current_time
            end_time = start_time + dur

            concat_lines.append(f"file '{seg_path.resolve()}'\n")

            srt_entries.append(
                f"{idx}\n{format_srt_time(start_time)} --> {format_srt_time(end_time)}\n{info['text']}\n"
            )
            vtt_entries.append(
                f"\n{format_vtt_time(start_time)} --> {format_vtt_time(end_time)}\n{info['text']}\n"
            )

            processed_segments.append({
                "id": seg_id,
                "text": info["text"],
                "start": round(start_time, 3),
                "end": round(end_time, 3),
                "duration": round(dur, 3),
                "audio_file": str(seg_path),
                "effective_speed": info.get("effective_speed", default_speed),
                "is_boosted": False,
            })

            current_time = end_time

            if has_pause and idx < len(segments):
                concat_lines.append(f"file '{silence_file.resolve()}'\n")
                current_time += pause_sec

    # Write concat manifest
    concat_list_file = temp_dir / "concat_list.txt"
    with open(concat_list_file, "w", encoding="utf-8") as f:
        f.writelines(concat_lines)

    # Execute FFmpeg Concat
    cmd = [
        "ffmpeg", "-y",
        "-f", "concat",
        "-safe", "0",
        "-i", str(concat_list_file),
        "-c:a", "libmp3lame",
        "-q:a", "2",
        str(output_audio)
    ]
    res = subprocess.run(cmd, capture_output=True)
    if res.returncode != 0 or not output_audio.exists() or output_audio.stat().st_size == 0:
        raise RuntimeError(f"FFmpeg concat failed: {res.stderr.decode('utf-8', errors='ignore')}")

    # Write SRT if requested
    if output_srt:
        output_srt.parent.mkdir(parents=True, exist_ok=True)
        with open(output_srt, "w", encoding="utf-8") as f:
            f.write("\n".join(srt_entries) + "\n")

    # Write VTT if requested
    if output_vtt:
        output_vtt.parent.mkdir(parents=True, exist_ok=True)
        with open(output_vtt, "w", encoding="utf-8") as f:
            f.write("".join(vtt_entries) + "\n")

    # Clean up temp folder
    try:
        shutil.rmtree(temp_dir, ignore_errors=True)
    except Exception:
        pass

    return {
        "success": True,
        "total_duration": round(current_time, 3),
        "total_segments": len(processed_segments),
        "audio_path": str(output_audio),
        "srt_path": str(output_srt) if output_srt else None,
        "vtt_path": str(output_vtt) if output_vtt else None,
        "segments": processed_segments,
    }


def main():
    parser = argparse.ArgumentParser(description="TTS Studio Backend Tool")
    parser.add_argument("--action", required=True, choices=["get_voices", "split_script", "import_narration", "preview_segment", "render_full", "clear_cache"])
    parser.add_argument("--text", type=str, default="")
    parser.add_argument("--voice", type=str, default="en-US-JennyNeural")
    parser.add_argument("--speed", type=float, default=1.0)
    parser.add_argument("--pitch", type=int, default=0)
    parser.add_argument("--pause", type=float, default=0.35)
    parser.add_argument("--lock-timeline", action="store_true", default=False)
    parser.add_argument("--input-json", type=str, default="")
    parser.add_argument("--output-audio", type=str, default="")
    parser.add_argument("--output-srt", type=str, default="")
    parser.add_argument("--output-vtt", type=str, default="")

    args = parser.parse_args()

    try:
        if args.action == "get_voices":
            print(json.dumps({"success": True, "voices": VOICE_CATALOG}, ensure_ascii=False, indent=2))
            return

        elif args.action in ["split_script", "import_narration"]:
            text = args.text
            if args.input_json and os.path.exists(args.input_json):
                with open(args.input_json, "r", encoding="utf-8") as f:
                    text = f.read()
            segments = split_script_into_segments(text, speed=args.speed, pause_sec=args.pause)
            print(json.dumps({"success": True, "total_segments": len(segments), "segments": segments}, ensure_ascii=False))
            return

        elif args.action == "preview_segment":
            if not args.text:
                print(json.dumps({"success": False, "error": "Thiếu nội dung --text"}))
                sys.exit(1)

            out_p = Path(args.output_audio) if args.output_audio else None
            out_file, dur, ok = asyncio.run(synth_segment_async(
                text=args.text,
                voice=args.voice,
                speed=args.speed,
                pitch=args.pitch,
                output_path=out_p,
            ))
            if ok and out_file.exists():
                print(json.dumps({
                    "success": True,
                    "audio_path": str(out_file),
                    "duration": round(dur, 3),
                }, ensure_ascii=False))
            else:
                print(json.dumps({"success": False, "error": "Lỗi sinh audio preview"}))
                sys.exit(1)
            return

        elif args.action == "render_full":
            if not args.input_json or not os.path.exists(args.input_json):
                print(json.dumps({"success": False, "error": "File --input-json không tồn tại"}))
                sys.exit(1)

            with open(args.input_json, "r", encoding="utf-8") as f:
                data = json.load(f)

            segments = data.get("segments", [])
            default_voice = data.get("default_voice", args.voice)
            default_speed = float(data.get("default_speed", args.speed))
            default_pitch = int(data.get("default_pitch", args.pitch))
            pause_sec = float(data.get("pause_sec", args.pause))
            lock_timeline = bool(data.get("lock_timeline", False) or args.lock_timeline)

            out_audio = Path(args.output_audio or data.get("output_audio", "output_tts.mp3"))
            out_srt = Path(args.output_srt) if args.output_srt else (Path(data.get("output_srt")) if data.get("output_srt") else None)
            out_vtt = Path(args.output_vtt) if args.output_vtt else (Path(data.get("output_vtt")) if data.get("output_vtt") else None)

            result = asyncio.run(render_full_batch(
                segments=segments,
                default_voice=default_voice,
                default_speed=default_speed,
                default_pitch=default_pitch,
                pause_sec=pause_sec,
                output_audio=out_audio,
                output_srt=out_srt,
                output_vtt=out_vtt,
                lock_timeline=lock_timeline,
            ))
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return

        elif args.action == "clear_cache":
            from engine.features.tts_studio.tts_cache_manager import auto_clean_tts_cache
            deleted, freed = auto_clean_tts_cache(force_all=True)
            print(json.dumps({
                "success": True,
                "deleted_files": deleted,
                "freed_mb": round(freed / (1024 * 1024), 2),
            }, ensure_ascii=False))
            return

    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}, ensure_ascii=False))
        sys.exit(1)


if __name__ == "__main__":
    main()
