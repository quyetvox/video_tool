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
        tts_delay = float(config.get("tts_delay_sec") if config.get("tts_delay_sec") is not None else (config.get("delay_sec") if config.get("delay_sec") is not None else 0.25))

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

                if next_start is not None and next_start > seg_start:
                    avail_slot = max(0.4, next_start - seg_start - 0.05)
                else:
                    avail_slot = max(0.4, seg_end - seg_start + 2.0)

                # Vietnamese natural speaking rate: ~15.0 chars/second (at 1.0x)
                char_count = len(text)
                est_natural_dur = char_count / 15.0
                required_speed = est_natural_dur / avail_slot

                # Strict Floor: Cannot be lower than base_speed configured in config.yaml
                # Ceiling: Capped at 2.2x to prevent extreme audio artifacting
                item_speed = min(2.2, max(base_speed, required_speed))

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

        # 2. Fast convert raw MP3s to 44.1kHz stereo WAV & Trim leading/trailing padding
        import soundfile as sf
        import numpy as np

        def _trim_audio_padding(wav_path: Path):
            try:
                y, sr = sf.read(str(wav_path), dtype="float32")
                mono = np.max(np.abs(y), axis=1) if y.ndim > 1 else np.abs(y)
                threshold = 10.0 ** (-42.0 / 20.0)  # -42dB amplitude threshold
                voiced = np.where(mono > threshold)[0]
                if len(voiced) > 0:
                    first_idx = max(0, voiced[0] - int(sr * 0.02))
                    last_idx = min(len(y), voiced[-1] + int(sr * 0.05))
                    if last_idx > first_idx:
                        sf.write(str(wav_path), y[first_idx:last_idx], sr)
            except Exception:
                pass

        segment_results = [None] * len(segments)
        for idx, raw_mp3, is_ok in synth_results:
            if is_ok and raw_mp3.exists() and raw_mp3.stat().st_size > 500:
                _, wav_seg = seg_id_map[idx]
                cmd_conv = [
                    "ffmpeg", "-y", "-i", str(raw_mp3),
                    "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", str(wav_seg)
                ]
                res = subprocess.run(cmd_conv, capture_output=True, check=False)
                if wav_seg.exists() and wav_seg.stat().st_size > 500:
                    _trim_audio_padding(wav_seg)
                    segment_results[idx] = wav_seg

        # 3. Audio Alignment & Mixing
        if enable_gender:
            # ─────────────────────────────────────────────────────────────
            # MULTI-TRACK TIMELINE OVERLAY MIXER (Polyphonic Dialogue Mode)
            # ─────────────────────────────────────────────────────────────
            sr = 44100
            total_samples = int(max(total_duration, 1.0) * sr)
            for orig_idx, seg in enumerate(segments):
                seg_out = segment_results[orig_idx]
                if seg_out and seg_out.exists():
                    d = FFmpegUtils.get_audio_duration(seg_out)
                    s = float(seg.get("start", 0.0)) + tts_delay
                    total_samples = max(total_samples, int((s + d + 3.0) * sr))

            master_pcm = np.zeros((total_samples, 2), dtype=np.float32)
            speaker_intervals = []

            for orig_idx, seg in enumerate(segments):
                seg_out = segment_results[orig_idx]
                if not seg_out or not seg_out.exists() or seg_out.stat().st_size <= 500:
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

                if next_same_speaker_start is not None:
                    avail_slot = max(0.4, next_same_speaker_start - effective_start - 0.05)
                else:
                    avail_slot = max(0.4, (seg_end - seg_start) + 3.0)

                audio_dur = FFmpegUtils.get_audio_duration(seg_out)
                required_speed = audio_dur / avail_slot
                speed_cap = max(base_speed, 1.35)
                speed_factor = min(speed_cap, max(base_speed, required_speed))

                processed_seg = seg_out
                if abs(speed_factor - 1.0) > 0.03 and audio_dur > 0.1:
                    adjusted_file = tts_dir / f"adjusted_{orig_idx:04d}.wav"
                    cmd_speed = [
                        "ffmpeg", "-y", "-i", str(seg_out),
                        "-filter:a", f"atempo={speed_factor:.2f}",
                        "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", str(adjusted_file)
                    ]
                    try:
                        res = subprocess.run(cmd_speed, capture_output=True, text=True)
                        if res.returncode == 0 and adjusted_file.exists() and adjusted_file.stat().st_size > 0:
                            processed_seg = adjusted_file
                    except Exception:
                        processed_seg = seg_out

                y_seg, _ = sf.read(str(processed_seg), dtype="float32")
                if y_seg.ndim == 1:
                    y_seg = np.column_stack((y_seg, y_seg))

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
        # SINGLE-TRACK LINEAR MODE (When enable_gender == False)
        # ─────────────────────────────────────────────────────────────────
        sorted_segments = sorted(enumerate(segments), key=lambda x: float(x[1].get("start", 0.0)))
        aligned_audio_files = []
        current_time = 0.0

        for seq_idx, (orig_idx, seg) in enumerate(sorted_segments):
            seg_start = float(seg.get("start", 0.0))
            seg_end = float(seg.get("end", seg_start + 1.5))
            effective_start = seg_start + tts_delay
            effective_end = seg_end + tts_delay

            # Lookahead next segment start time to prevent overlapping/cascade drift
            next_seg_start = None
            next_effective_start = None
            if seq_idx + 1 < len(sorted_segments):
                next_seg_start = float(sorted_segments[seq_idx + 1][1].get("start", seg_end + 1.0))
                next_effective_start = next_seg_start + tts_delay

            if next_effective_start is not None and effective_start + 0.35 > next_effective_start:
                effective_start = max(seg_start, next_effective_start - 0.4)

            # Maximum available slot for this sentence before next sentence must begin
            if next_effective_start is not None and next_effective_start > effective_start:
                max_slot = max(0.4, next_effective_start - effective_start - 0.05)
                target_dur = min(max(0.4, effective_end - effective_start), max_slot)
            else:
                target_dur = max(0.4, effective_end - effective_start)
                max_slot = target_dur + 1.0

            seg_out = segment_results[orig_idx]
            if not seg_out or not seg_out.exists() or seg_out.stat().st_size <= 500:
                current_time = max(current_time, effective_start)
                continue

            # Silence padding before segment using instant memory PCM writer
            if effective_start > current_time + 0.02:
                silence_gap = effective_start - current_time
                silence_file = tts_dir / f"silence_{seq_idx:04d}.wav"
                write_pcm_silence(silence_file, silence_gap)
                aligned_audio_files.append(silence_file)
                current_time = effective_start

            # Measure audio duration
            audio_dur = FFmpegUtils.get_audio_duration(seg_out)

            # Local Inter-Sentence Gap Utilization: speech can safely fill available slot before next sentence starts
            local_avail_slot = max(0.35, (next_effective_start - effective_start - 0.05) if next_effective_start else (target_dur + 3.0))

            # Detect if segment was synthesized with gTTS (raw 1.0x) or EdgeTTS (pre-scaled)
            is_gtts = str(voice_default).strip().lower() in (
                "vi-vn-banmai", "vi-banmai", "banmai", "gtts", "google", "vi_gtts", "vi", "default", "preset"
            )

            if is_gtts:
                # gTTS is always synthesized at raw 1.0x from Google:
                # - Short sentences MUST be boosted to base_speed floor (e.g. 1.5x)
                # - Long sentences are boosted dynamically (up to 2.2x) to fit the slot perfectly
                required_speed = audio_dur / local_avail_slot
                speed_factor = min(2.2, max(base_speed, required_speed))
            else:
                # EdgeTTS was already synthesized at item_speed (>= base_speed):
                # - Fine-tune only if audio_dur still exceeds local_avail_slot
                required_speed = audio_dur / local_avail_slot
                speed_factor = min(2.2, max(1.0, required_speed))

            processed_seg = seg_out
            if abs(speed_factor - 1.0) > 0.03 and audio_dur > 0.1:
                adjusted_file = tts_dir / f"adjusted_{orig_idx:04d}.wav"
                cmd_speed = [
                    "ffmpeg", "-y", "-i", str(seg_out),
                    "-filter:a", f"atempo={speed_factor:.2f}",
                    "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", str(adjusted_file)
                ]
                try:
                    res = subprocess.run(cmd_speed, capture_output=True, text=True)
                    if res.returncode == 0 and adjusted_file.exists() and adjusted_file.stat().st_size > 0:
                        processed_seg = adjusted_file
                        audio_dur = FFmpegUtils.get_audio_duration(adjusted_file)
                except Exception:
                    processed_seg = seg_out

            aligned_audio_files.append(processed_seg)
            current_time = effective_start + audio_dur

        # Pad final silence up to total_duration if needed
        if total_duration > current_time + 0.1:
            final_silence = total_duration - current_time
            silence_file = tts_dir / "silence_final.wav"
            write_pcm_silence(silence_file, final_silence)
            aligned_audio_files.append(silence_file)

        concat_list = tts_dir / "concat_list.txt"
        final_voice_wav = workspace / "translated_voice.wav"

        with open(concat_list, "w", encoding="utf-8") as list_f:
            for af in aligned_audio_files:
                list_f.write(f"file '{af.absolute()}'\n")

        # Concat audio files using single ffmpeg concat demuxer
        if aligned_audio_files:
            cmd = [
                "ffmpeg", "-y", "-f", "concat", "-safe", "0",
                "-i", str(concat_list),
                "-c:a", "pcm_s16le", str(final_voice_wav)
            ]
            subprocess.run(cmd, capture_output=True, check=False)

        if not final_voice_wav.exists() or final_voice_wav.stat().st_size == 0:
            dur = max(1.0, total_duration)
            write_pcm_silence(final_voice_wav, dur)

        print(f"[TTS Complete] Successfully generated translated voice audio in {len(aligned_audio_files)} aligned segments.", flush=True)

        return {
            "translated_voice": str(final_voice_wav),
            "segment_count": len(aligned_audio_files),
            "mode": "single_track_linear"
        }
