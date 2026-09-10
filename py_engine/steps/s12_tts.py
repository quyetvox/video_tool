import json
import subprocess
import wave
from pathlib import Path
from typing import Any, Dict, List

from core.plugin_loader import PluginLoader
from core.step_base import StepBase


def write_pcm_silence(output_path: Path, duration_sec: float, sample_rate: int = 44100, channels: int = 2) -> None:
    """Generate exact zero-byte PCM 16-bit silence WAV in microseconds without FFmpeg subprocess."""
    num_frames = int(max(0.01, duration_sec) * sample_rate)
    with wave.open(str(output_path), 'wb') as wf:
        wf.setnchannels(channels)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        wf.writeframes(b'\x00' * (num_frames * channels * 2))


class StepTTS(StepBase):
    step_id = "s12_tts"
    depends_on = ["s08_translation"]
    STEP_CONFIG_KEYS = [
        "tts", "tts_voice", "tts_voice_volume", "tts_speed_factor", "tts_delay_sec", "delay_sec",
        "enable_gender_tts", "tts_voice_male", "tts_voice_female", "tts_num_workers", "num_workers"
    ]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        final_voice_wav = workspace / "translated_voice.wav"

        tts_vol = float(config.get("tts_voice_volume", 1.0))
        tts_voice_setting = str(config.get("tts_voice", "")).strip().lower()

        if config.get("ocr_only", False) or tts_vol == 0.0 or tts_voice_setting in ["0", "none", "off"]:
            print("[TTS] TTS voice disabled (volume=0 or voice=none/0): Bypassing TTS voice generation (~0s).")
            return {
                "skipped": True,
                "translated_voice": str(final_voice_wav),
                "segment_count": 0
            }

        trans_info = job_state.get_step_output("s08_translation") or {}
        trans_file = Path(trans_info.get("translation_file") or workspace / "s08c_timing.json" or workspace / "s08_translation.json")

        with open(trans_file, "r", encoding="utf-8") as f:
            segments = json.load(f)

        tts_dir = workspace / "tts_segments"
        tts_dir.mkdir(parents=True, exist_ok=True)
        for old_f in tts_dir.glob("*"):
            try:
                if old_f.is_file():
                    old_f.unlink()
            except Exception:
                pass

        tts_val = config.get("tts", "preset")
        if isinstance(tts_val, dict) or hasattr(tts_val, "get"):
            tts_plugin_name = str(tts_val.get("engine", "preset"))
        else:
            tts_plugin_name = str(tts_val)
        tts_plugin_name = tts_plugin_name.replace("-", "_")
        if tts_plugin_name == "preset":
            tts_plugin_name = "preset_tts"

        tts_plugin = PluginLoader.load_plugin("tts", tts_plugin_name, config)

        probe_info = job_state.get_step_output("s01_probe") or {}
        total_duration = float(probe_info.get("duration", 0.0))

        from utils.ffmpeg_utils import FFmpegUtils

        FILLER_WORDS = {"ừm", "a", "ah", "hì hì", "ha ha", "ừ", "ơ", "ồ", "này", "dạ", "ừm...", "ha"}

        def _is_filler(text: str) -> bool:
            t = text.strip().lower().rstrip(".,!?")
            return t in FILLER_WORDS or (len(t) <= 1 and t not in {"y", "ơ", "ô"})

        base_speed = float(config.get("tts_speed_factor", 1.2))
        tts_delay = float(config.get("tts_delay_sec") if config.get("tts_delay_sec") is not None else (config.get("delay_sec") if config.get("delay_sec") is not None else 0.03))

        enable_gender = config.get("enable_gender_tts", False)
        gender_map = {}
        if enable_gender:
            gender_info = job_state.get_step_output("s05b_gender_detect") or {}
            gender_file = Path(gender_info.get("gender_file", workspace / "s05b_gender.json"))
            if gender_file.exists():
                with open(gender_file, "r", encoding="utf-8") as f:
                    gender_map = json.load(f)

        voice_male = config.get("tts_voice_male", "vi-VN-NamMinhNeural")
        voice_female = config.get("tts_voice_female", "vi-VN-HoaiMyNeural")
        voice_default = config.get("tts_voice", "vi-VN-BanMai")

        # 1. Prepare batch synthesis items with Adaptive Speed Calculation for Single Voice
        batch_items = []
        seg_id_map = {}
        for idx, seg in enumerate(segments):
            text = (seg.get("text_vi") or seg.get("translated_text") or seg.get("text") or "").strip()
            if _is_filler(text):
                continue
            seg_id = str(seg.get("id", idx))
            selected_voice = voice_default
            if enable_gender and seg_id in gender_map:
                seg_gender = gender_map[seg_id].get("gender", "unknown")
                if seg_gender == "male":
                    selected_voice = voice_male
                elif seg_gender == "female":
                    selected_voice = voice_female

            # ─────────────────────────────────────────────────────────────
            # Adaptive Speed Calculation (Single Voice Mode)
            # ─────────────────────────────────────────────────────────────
            item_speed = base_speed
            if not enable_gender:
                seg_start = float(seg.get("start", 0.0))
                seg_end = float(seg.get("end", seg_start + 1.5))
                # Lookahead next valid segment start time
                next_start = None
                for future_idx in range(idx + 1, len(segments)):
                    f_text = (segments[future_idx].get("text_vi") or segments[future_idx].get("translated_text") or segments[future_idx].get("text") or "").strip()
                    if not _is_filler(f_text):
                        next_start = float(segments[future_idx].get("start", seg_end + 1.0))
                        break

                # Sub-Locked target slot
                sub_dur = max(0.35, seg_end - seg_start)
                if next_start is not None and next_start > seg_start:
                    avail_slot = max(0.35, min(sub_dur, next_start - seg_start - 0.05))
                else:
                    avail_slot = sub_dur

                # Vietnamese natural speaking rate: ~14.0 chars/second (at 1.0x)
                char_count = len(text)
                est_natural_dur = char_count / 14.0
                required_speed = est_natural_dur / avail_slot

                # Strict Floor: Cannot be lower than base_speed configured in config.yaml
                # Ceiling: Capped at 2.0x to prevent extreme audio artifacting
                item_speed = min(2.0, max(base_speed, required_speed))

                if item_speed > base_speed + 0.05:
                    print(f"   [Adaptive Speed Boost] Seg #{idx:02d} ({char_count} chars in {avail_slot:.2f}s slot): Boosted {base_speed:.2f}x -> {item_speed:.2f}x", flush=True)
                else:
                    item_speed = base_speed  # Strictly lock to config base_speed for short/normal sentences

            raw_mp3 = tts_dir / f"raw_{idx:04d}.mp3"
            wav_seg = tts_dir / f"seg_{idx:04d}.wav"
            seg_id_map[idx] = (raw_mp3, wav_seg)

            batch_items.append({
                "id": idx,
                "text": text,
                "output_path": raw_mp3,
                "voice": selected_voice,
                "speed_factor": item_speed,
            })

        print(f"[TTS Async Batch] Synthesizing {len(batch_items)} segments with connection pooling (Floor={base_speed:.2f}x)...", flush=True)

        if hasattr(tts_plugin, "synthesize_batch"):
            synth_results = tts_plugin.synthesize_batch(batch_items, default_voice=voice_default, speed_factor=base_speed)
        else:
            synth_results = []
            for itm in batch_items:
                try:
                    tts_plugin.synthesize_segment(itm["text"], itm["output_path"], voice=itm["voice"])
                    synth_results.append((itm["id"], itm["output_path"], True))
                except Exception:
                    synth_results.append((itm["id"], itm["output_path"], False))

        # 2. Fast In-Memory Decode, Resample to 44.1kHz Stereo & Trim Padding (Zero FFmpeg Subprocesses)
        import math
        import soundfile as sf
        import numpy as np
        import scipy.signal as signal

        sr = 44100

        def _resample_to_44100(y: np.ndarray, orig_sr: int) -> np.ndarray:
            if orig_sr == 44100:
                return y.astype(np.float32)
            gcd = math.gcd(44100, orig_sr)
            up = 44100 // gcd
            down = orig_sr // gcd
            return signal.resample_poly(y, up, down).astype(np.float32)

        def _trim_audio_padding_pcm(y: np.ndarray, sample_rate: int = 44100) -> np.ndarray:
            mono = np.max(np.abs(y), axis=1) if y.ndim > 1 else np.abs(y)
            threshold = 10.0 ** (-42.0 / 20.0)  # -42dB amplitude threshold
            voiced = np.where(mono > threshold)[0]
            if len(voiced) > 0:
                first_idx = max(0, voiced[0] - int(sample_rate * 0.02))
                last_idx = min(len(y), voiced[-1] + int(sample_rate * 0.05))
                if last_idx > first_idx:
                    return y[first_idx:last_idx]
            return y

        segment_pcm_results = [None] * len(segments)
        for idx, raw_mp3, is_ok in synth_results:
            if is_ok and raw_mp3.exists() and raw_mp3.stat().st_size > 500:
                try:
                    # Fast direct decode via libsndfile in RAM (bypasses FFmpeg process spawn)
                    y, orig_sr = sf.read(str(raw_mp3), dtype="float32")
                    if y.ndim == 1:
                        y = np.column_stack((y, y))
                    elif y.shape[1] == 1:
                        y = np.repeat(y, 2, axis=1)

                    if orig_sr != sr:
                        y_l = _resample_to_44100(y[:, 0], orig_sr)
                        y_r = _resample_to_44100(y[:, 1], orig_sr)
                        y = np.column_stack((y_l, y_r))

                    y = _trim_audio_padding_pcm(y, sr)
                    if len(y) > int(sr * 0.05):  # Keep if >= 50ms
                        segment_pcm_results[idx] = y
                except Exception:
                    # Fallback to FFmpeg if libsndfile cannot decode MP3 directly on rare OS environments
                    _, wav_seg = seg_id_map[idx]
                    cmd_conv = [
                        "ffmpeg", "-y", "-i", str(raw_mp3),
                        "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", str(wav_seg)
                    ]
                    subprocess.run(cmd_conv, capture_output=True, check=False)
                    if wav_seg.exists() and wav_seg.stat().st_size > 500:
                        try:
                            y_fb, _ = sf.read(str(wav_seg), dtype="float32")
                            if y_fb.ndim == 1:
                                y_fb = np.column_stack((y_fb, y_fb))
                            y_fb = _trim_audio_padding_pcm(y_fb, sr)
                            if len(y_fb) > int(sr * 0.05):
                                segment_pcm_results[idx] = y_fb
                        except Exception:
                            pass

        # 3. Audio Alignment & Mixing
        if enable_gender:
            # ─────────────────────────────────────────────────────────────
            # MULTI-TRACK TIMELINE OVERLAY MIXER (Polyphonic Dialogue Mode)
            # ─────────────────────────────────────────────────────────────
            total_samples = int(max(total_duration, 1.0) * sr)
            for orig_idx, seg in enumerate(segments):
                y_seg = segment_pcm_results[orig_idx]
                if y_seg is not None and len(y_seg) > 0:
                    d = len(y_seg) / sr
                    s = float(seg.get("start", 0.0)) + tts_delay
                    total_samples = max(total_samples, int((s + d + 3.0) * sr))

            master_pcm = np.zeros((total_samples, 2), dtype=np.float32)
            speaker_intervals = []

            for orig_idx, seg in enumerate(segments):
                y_seg = segment_pcm_results[orig_idx]
                if y_seg is None or len(y_seg) == 0:
                    continue

                seg_id = str(seg.get("id", orig_idx))
                seg_info = gender_map.get(seg_id, {})
                seg_speaker = seg_info.get("speaker") or seg_info.get("gender", "unknown")
                seg_start = float(seg.get("start", 0.0))
                seg_end = float(seg.get("end", seg_start + 1.5))
                effective_start = seg_start + tts_delay

                # Find the next segment of the SAME speaker
                next_same_speaker_start = None
                for future_idx in range(orig_idx + 1, len(segments)):
                    f_seg = segments[future_idx]
                    f_id = str(f_seg.get("id", future_idx))
                    f_info = gender_map.get(f_id, {})
                    f_speaker = f_info.get("speaker") or f_info.get("gender", "unknown")
                    if f_speaker == seg_speaker:
                        next_same_speaker_start = float(f_seg.get("start", 0.0)) + tts_delay
                        break

                if next_same_speaker_start is not None and next_same_speaker_start > effective_start:
                    max_allowed_samples = int((next_same_speaker_start - effective_start - 0.02) * sr)
                    if max_allowed_samples > int(sr * 0.2) and len(y_seg) > max_allowed_samples:
                        y_seg = y_seg[:max_allowed_samples].copy()
                        fade_len = min(len(y_seg), int(sr * 0.05))
                        if fade_len > 0:
                            y_seg[-fade_len:] *= np.linspace(1.0, 0.0, fade_len)[:, None]

                start_sample = int(effective_start * sr)
                end_sample = min(total_samples, start_sample + len(y_seg))
                actual_len = end_sample - start_sample

                if actual_len > 0:
                    speaker_intervals.append({
                        "speaker": seg_speaker,
                        "start_sample": start_sample,
                        "end_sample": end_sample,
                        "audio": y_seg[:actual_len],
                        "orig_idx": orig_idx,
                    })

            # Smart Cross-Ducking on Interruption
            for i, itm_curr in enumerate(speaker_intervals):
                curr_audio = itm_curr["audio"].copy()
                c_start = itm_curr["start_sample"]
                c_end = itm_curr["end_sample"]

                for j in range(i + 1, len(speaker_intervals)):
                    itm_next = speaker_intervals[j]
                    n_start = itm_next["start_sample"]
                    if n_start < c_end and itm_next["speaker"] != itm_curr["speaker"]:
                        overlap_start_local = n_start - c_start
                        if 0 <= overlap_start_local < len(curr_audio):
                            curr_audio[overlap_start_local:] *= 0.65

                master_pcm[c_start:c_end] += curr_audio

            # Soft peak limiting
            max_amp = np.max(np.abs(master_pcm))
            if max_amp > 0.98:
                master_pcm = master_pcm / max_amp * 0.98

            final_voice_wav = workspace / "translated_voice.wav"
            sf.write(str(final_voice_wav), master_pcm, sr, subtype="PCM_16")

            return {
                "translated_voice": str(final_voice_wav),
                "segment_count": len(speaker_intervals),
                "mode": "multitrack_timeline"
            }

        # ─────────────────────────────────────────────────────────────────
        # SINGLE-TRACK IN-MEMORY BUFFER (When enable_gender == False)
        # ─────────────────────────────────────────────────────────────────
        total_samples = int(max(total_duration, 1.0) * sr)
        for orig_idx, seg in enumerate(segments):
            y_seg = segment_pcm_results[orig_idx]
            if y_seg is not None and len(y_seg) > 0:
                s = float(seg.get("start", 0.0)) + tts_delay
                d = len(y_seg) / sr
                total_samples = max(total_samples, int((s + d + 3.0) * sr))

        master_pcm = np.zeros((total_samples, 2), dtype=np.float32)
        sorted_segments = sorted(enumerate(segments), key=lambda x: float(x[1].get("start", 0.0)))

        is_gtts = str(voice_default).strip().lower() in (
            "vi-vn-banmai", "vi-banmai", "banmai", "gtts", "google", "vi_gtts", "vi", "default", "preset"
        )

        # Pre-process atempo in parallel only for gTTS (since EdgeTTS synthesizes with rate pre-scaled)
        atempo_tasks = []
        if is_gtts:
            for seq_idx, (orig_idx, seg) in enumerate(sorted_segments):
                y_seg = segment_pcm_results[orig_idx]
                if y_seg is None or len(y_seg) == 0:
                    continue
                seg_start = float(seg.get("start", 0.0))
                seg_end = float(seg.get("end", seg_start + 1.5))
                effective_start = seg_start + tts_delay
                next_effective_start = None
                if seq_idx + 1 < len(sorted_segments):
                    next_seg_start = float(sorted_segments[seq_idx + 1][1].get("start", seg_end + 1.0))
                    next_effective_start = next_seg_start + tts_delay

                if next_effective_start is not None and next_effective_start > effective_start:
                    target_slot = max(0.35, min(seg_end - seg_start, next_effective_start - effective_start - 0.05))
                else:
                    target_slot = max(0.35, seg_end - seg_start)

                audio_dur = len(y_seg) / sr
                scale_speed = audio_dur / target_slot
                speed_factor = min(2.35, max(base_speed, scale_speed))
                if abs(speed_factor - 1.0) > 0.03:
                    atempo_tasks.append((orig_idx, y_seg, speed_factor))

        if atempo_tasks:
            from concurrent.futures import ThreadPoolExecutor
            def _apply_atempo(item):
                o_idx, y_arr, spd = item
                temp_in = tts_dir / f"atempo_in_{o_idx:04d}.wav"
                temp_out = tts_dir / f"atempo_out_{o_idx:04d}.wav"
                sf.write(str(temp_in), y_arr, sr, subtype="PCM_16")
                atempo_filter = f"atempo={spd:.3f}" if spd <= 2.0 else f"atempo=2.0,atempo={spd / 2.0:.3f}"
                cmd = [
                    "ffmpeg", "-y", "-i", str(temp_in),
                    "-filter:a", atempo_filter,
                    "-ar", str(sr), "-ac", "2", "-c:a", "pcm_s16le", str(temp_out)
                ]
                res = subprocess.run(cmd, capture_output=True, check=False)
                if temp_out.exists() and temp_out.stat().st_size > 500:
                    try:
                        y_res, _ = sf.read(str(temp_out), dtype="float32")
                        if y_res.ndim == 1:
                            y_res = np.column_stack((y_res, y_res))
                        segment_pcm_results[o_idx] = _trim_audio_padding_pcm(y_res, sr)
                    except Exception:
                        pass
                temp_in.unlink(missing_ok=True)
                temp_out.unlink(missing_ok=True)

            with ThreadPoolExecutor(max_workers=min(8, len(atempo_tasks))) as pool:
                list(pool.map(_apply_atempo, atempo_tasks))

        # Direct absolute timeline mapping (Zero-Drift & Anti-Phantom Leap)
        placed_count = 0
        for seq_idx, (orig_idx, seg) in enumerate(sorted_segments):
            y_seg = segment_pcm_results[orig_idx]
            if y_seg is None or len(y_seg) == 0:
                continue

            seg_start = float(seg.get("start", 0.0))
            seg_end = float(seg.get("end", seg_start + 1.5))
            effective_start = seg_start + tts_delay

            next_effective_start = None
            if seq_idx + 1 < len(sorted_segments):
                next_seg_start = float(sorted_segments[seq_idx + 1][1].get("start", seg_end + 1.0))
                next_effective_start = next_seg_start + tts_delay

            # Sub-Locked Slot Clamping: prevent overlapping speech with next sentence
            if next_effective_start is not None and next_effective_start > effective_start:
                max_allowed_samples = int((next_effective_start - effective_start - 0.02) * sr)
                if max_allowed_samples > int(sr * 0.2) and len(y_seg) > max_allowed_samples:
                    y_seg = y_seg[:max_allowed_samples].copy()
                    fade_len = min(len(y_seg), int(sr * 0.05))
                    if fade_len > 0:
                        y_seg[-fade_len:] *= np.linspace(1.0, 0.0, fade_len)[:, None]

            start_sample = int(effective_start * sr)
            end_sample = min(total_samples, start_sample + len(y_seg))
            actual_len = end_sample - start_sample

            if actual_len > 0:
                master_pcm[start_sample:end_sample] += y_seg[:actual_len]
                placed_count += 1

        # Soft peak limiting
        max_amp = np.max(np.abs(master_pcm))
        if max_amp > 0.98:
            master_pcm = master_pcm / max_amp * 0.98

        final_voice_wav = workspace / "translated_voice.wav"
        sf.write(str(final_voice_wav), master_pcm, sr, subtype="PCM_16")

        if not final_voice_wav.exists() or final_voice_wav.stat().st_size == 0:
            dur = max(1.0, total_duration)
            write_pcm_silence(final_voice_wav, dur)

        print(f"[TTS Complete] Successfully synthesized voice audio ({placed_count} segments) directly in RAM.", flush=True)

        return {
            "translated_voice": str(final_voice_wav),
            "segment_count": placed_count,
            "mode": "single_track_in_memory"
        }
