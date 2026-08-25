import json
import subprocess
from pathlib import Path
from typing import Any, Dict

from core.plugin_loader import PluginLoader
from core.step_base import StepBase


class StepTTS(StepBase):
    step_id = "s12_tts"
    depends_on = ["s08_translation"]
    STEP_CONFIG_KEYS = [
        "tts", "tts_voice", "tts_voice_volume", "tts_speed_factor", 
        "enable_gender_tts", "tts_voice_male", "tts_voice_female", "tts_num_workers", "num_workers"
    ]

    @staticmethod
    def _resolve_num_workers(config: Dict[str, Any]) -> int:
        from core.concurrency import ConcurrencyManager
        return ConcurrencyManager.get_num_workers(config)

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
        trans_file = Path(trans_info["translation_file"])

        with open(trans_file, "r", encoding="utf-8") as f:
            segments = json.load(f)

        tts_dir = workspace / "tts_segments"
        tts_dir.mkdir(parents=True, exist_ok=True)

        tts_plugin_name = config.get("tts", "preset").replace("-", "_")
        if tts_plugin_name == "preset":
            tts_plugin_name = "preset_tts"

        tts_plugin = PluginLoader.load_plugin("tts", tts_plugin_name, config)

        probe_info = job_state.get_step_output("s01_probe") or {}
        total_duration = float(probe_info.get("duration", 0.0))

        from utils.ffmpeg_utils import FFmpegUtils
        from concurrent.futures import ThreadPoolExecutor

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
        voice_female = config.get("tts_voice_female", "vi-VN-HoaiMyNeural")
        voice_default = config.get("tts_voice", "vi-VN-HoaiMyNeural")

        def _synth_worker(args):
            idx, seg = args
            text = (seg.get("translated_text") or seg.get("text_vi") or seg.get("text") or "").strip()
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
            if not _is_filler(text):
                try:
                    tts_plugin.synthesize_segment(text, raw_mp3, voice=selected_voice)
                except TypeError:
                    tts_plugin.synthesize_segment(text, raw_mp3)

                if raw_mp3.exists() and raw_mp3.stat().st_size > 500:
                    filter_cmd = ["-filter:a", f"atempo={base_speed:.2f}"] if abs(base_speed - 1.0) > 0.05 else []
                    cmd_conv = [
                        "ffmpeg", "-y", "-i", str(raw_mp3)
                    ] + filter_cmd + [
                        "-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", str(wav_seg)
                    ]
                    subprocess.run(cmd_conv, capture_output=True, check=False)
            return idx, wav_seg

        segment_args = [(idx, seg) for idx, seg in enumerate(segments)]
        segment_results = [None] * len(segments)

        num_workers = self._resolve_num_workers(config)
        print(f"[TTS Multi-threaded] Synthesizing {len(segments)} segments with {num_workers} parallel workers...", flush=True)

        with ThreadPoolExecutor(max_workers=num_workers) as executor:
            futures = [executor.submit(_synth_worker, item) for item in segment_args]
            for f in futures:
                idx, seg_out = f.result()
                segment_results[idx] = seg_out


        # Timed Audio Alignment Algorithm
        sorted_segments = sorted(enumerate(segments), key=lambda x: float(x[1].get("start", 0.0)))
        aligned_audio_files = []
        current_time = 0.0

        for seq_idx, (orig_idx, seg) in enumerate(sorted_segments):
            seg_start = float(seg.get("start", 0.0))
            seg_end = float(seg.get("end", seg_start + 1.5))
            target_dur = max(0.5, seg_end - seg_start)

            seg_out = segment_results[orig_idx]
            if not seg_out or not seg_out.exists() or seg_out.stat().st_size <= 500:
                current_time = max(current_time, seg_start)
                continue

            # Silence padding before segment
            if seg_start > current_time + 0.05:
                silence_gap = seg_start - current_time
                silence_file = tts_dir / f"silence_{seq_idx:04d}.wav"
                cmd_silence = [
                    "ffmpeg", "-y", "-f", "lavfi",
                    "-i", "anullsrc=r=44100:cl=stereo",
                    "-t", f"{silence_gap:.3f}",
                    "-c:a", "pcm_s16le", str(silence_file)
                ]
                subprocess.run(cmd_silence, capture_output=True, check=True)
                aligned_audio_files.append(silence_file)
                current_time = seg_start

            # Measure audio duration
            audio_dur = FFmpegUtils.get_audio_duration(seg_out)

            # Speed adjust using atempo if speech exceeds target_dur
            processed_seg = seg_out
            if audio_dur > target_dur + 0.2 and audio_dur > 0.1:
                speed_factor = min(2.0, audio_dur / target_dur)
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
                        audio_dur = audio_dur / speed_factor
                except Exception:
                    processed_seg = seg_out

            aligned_audio_files.append(processed_seg)
            current_time += audio_dur

        # Pad final silence up to total_duration if needed
        if total_duration > current_time + 0.1:
            final_silence = total_duration - current_time
            silence_file = tts_dir / "silence_final.wav"
            cmd_silence = [
                "ffmpeg", "-y", "-f", "lavfi",
                "-i", "anullsrc=r=44100:cl=stereo",
                "-t", f"{final_silence:.3f}",
                "-c:a", "pcm_s16le", str(silence_file)
            ]
            subprocess.run(cmd_silence, capture_output=True, check=True)
            aligned_audio_files.append(silence_file)

        concat_list = tts_dir / "concat_list.txt"
        final_voice_wav = workspace / "translated_voice.wav"

        with open(concat_list, "w", encoding="utf-8") as list_f:
            for af in aligned_audio_files:
                list_f.write(f"file '{af.absolute()}'\n")

        # Concat audio files using ffmpeg concat demuxer if aligned_audio_files exist
        if aligned_audio_files:
            cmd = [
                "ffmpeg", "-y", "-f", "concat", "-safe", "0",
                "-i", str(concat_list),
                "-c:a", "pcm_s16le", str(final_voice_wav)
            ]
            subprocess.run(cmd, capture_output=True, check=False)

        if not final_voice_wav.exists() or final_voice_wav.stat().st_size == 0:
            # Generate 1s silent audio if no segments
            dur = f"{total_duration:.2f}" if total_duration > 0 else "1.00"
            cmd_silent = ["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", dur, "-c:a", "pcm_s16le", str(final_voice_wav)]
            subprocess.run(cmd_silent, capture_output=True, check=True)

        return {
            "translated_voice": str(final_voice_wav),
            "segment_count": len(aligned_audio_files)
        }
