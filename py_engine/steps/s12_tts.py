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
        "tts", "tts_voice", "tts_voice_volume", "tts_speed_factor", 
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

        enable_gender = config.get("enable_gender_tts", False)
        gender_map = {}
        if enable_gender:
            gender_info = job_state.get_step_output("s05b_gender_detect") or {}
            gender_file = Path(gender_info.get("gender_file", workspace / "s05b_gender.json"))
            if gender_file.exists():
                with open(gender_file, "r", encoding="utf-8") as f:
                    gender_map = json.load(f)

        voice_male = config.get("tts_voice_male", "vi-VN-NamMinhNeural")
        voice_female = config.get("tts_voice_female", "vi")
        voice_default = config.get("tts_voice", "vi")

        # 1. Prepare batch synthesis items
        batch_items = []
        seg_id_map = {}
        for idx, seg in enumerate(segments):
            text = (seg.get("translated_text") or seg.get("text_vi") or seg.get("text") or "").strip()
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

            raw_mp3 = tts_dir / f"raw_{idx:04d}.mp3"
            wav_seg = tts_dir / f"seg_{idx:04d}.wav"
            seg_id_map[idx] = (raw_mp3, wav_seg)

            batch_items.append({
                "id": idx,
                "text": text,
                "output_path": raw_mp3,
                "voice": selected_voice
            })

        print(f"[TTS Async Batch] Synthesizing {len(batch_items)} segments with connection pooling (Rate={base_speed:.2f}x)...", flush=True)

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

        # 2. Fast convert raw MP3s to 44.1kHz stereo WAV
        segment_results = [None] * len(segments)
        for idx, raw_mp3, is_ok in synth_results:
            if is_ok and raw_mp3.exists() and raw_mp3.stat().st_size > 500:
                _, wav_seg = seg_id_map[idx]
                cmd_conv = [
                    "ffmpeg", "-y", "-i", str(raw_mp3),
                    "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", str(wav_seg)
                ]
                subprocess.run(cmd_conv, capture_output=True, check=False)
                if wav_seg.exists() and wav_seg.stat().st_size > 500:
                    segment_results[idx] = wav_seg

        # 3. Timed Audio Alignment with Strict Anti-Drift Slot Fitting
        sorted_segments = sorted(enumerate(segments), key=lambda x: float(x[1].get("start", 0.0)))
        aligned_audio_files = []
        current_time = 0.0

        for seq_idx, (orig_idx, seg) in enumerate(sorted_segments):
            seg_start = float(seg.get("start", 0.0))
            seg_end = float(seg.get("end", seg_start + 1.5))

            # Lookahead next segment start time to prevent overlapping/cascade drift
            next_seg_start = None
            if seq_idx + 1 < len(sorted_segments):
                next_seg_start = float(sorted_segments[seq_idx + 1][1].get("start", seg_end + 1.0))

            # Maximum available slot for this sentence before next sentence must begin
            if next_seg_start is not None and next_seg_start > seg_start:
                max_slot = max(0.5, next_seg_start - seg_start - 0.05)
                target_dur = min(max(0.5, seg_end - seg_start), max_slot)
            else:
                target_dur = max(0.5, seg_end - seg_start)
                max_slot = target_dur + 1.0

            seg_out = segment_results[orig_idx]
            if not seg_out or not seg_out.exists() or seg_out.stat().st_size <= 500:
                current_time = max(current_time, seg_start)
                continue

            # Silence padding before segment using instant memory PCM writer
            if seg_start > current_time + 0.02:
                silence_gap = seg_start - current_time
                silence_file = tts_dir / f"silence_{seq_idx:04d}.wav"
                write_pcm_silence(silence_file, silence_gap)
                aligned_audio_files.append(silence_file)
                current_time = seg_start

            # Measure audio duration
            audio_dur = FFmpegUtils.get_audio_duration(seg_out)

            # Minimum config speed floor & strict anti-drift slot fitting
            avail_dur = max(0.35, min(target_dur, (next_seg_start - current_time - 0.05) if next_seg_start else target_dur))
            required_speed = audio_dur / avail_dur
            speed_factor = min(2.5, max(base_speed, required_speed))

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
            current_time += audio_dur

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
            "segment_count": len(aligned_audio_files)
        }
