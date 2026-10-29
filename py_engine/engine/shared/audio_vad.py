import wave
import numpy as np
from pathlib import Path
from typing import Any, Dict, List


class AudioVAD:
    """
    Audio Voice Activity & Onset Refiner.
    Analyzes vocal energy in voice.wav (separated by Demucs) to snap
    whisper/OCR timestamps precisely to actual voice onsets and offsets.
    Eliminates silence bleed and premature subtitle/TTS triggering on scene cuts.
    """

    @staticmethod
    def refine_timestamps(audio_path: Path, segments: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        if not segments or not audio_path.exists():
            return segments

        try:
            with wave.open(str(audio_path), "rb") as wf:
                sr = wf.getframerate()
                n_channels = wf.getnchannels()
                n_frames = wf.getnframes()
                raw_bytes = wf.readframes(n_frames)

            # Convert to float numpy array normalized [-1.0, 1.0]
            if wf.getsampwidth() == 2:  # 16-bit PCM
                samples = np.frombuffer(raw_bytes, dtype=np.int16).astype(np.float32) / 32768.0
            elif wf.getsampwidth() == 4:  # 32-bit PCM
                samples = np.frombuffer(raw_bytes, dtype=np.int32).astype(np.float32) / 2147483648.0
            else:
                return segments

            if n_channels > 1:
                # Convert to mono by averaging channels
                samples = samples.reshape(-1, n_channels).mean(axis=1)

            total_duration = len(samples) / sr
            frame_ms = 20  # 20ms analysis window
            frame_len = int(sr * (frame_ms / 1000.0))

            if frame_len <= 0 or len(samples) < frame_len:
                return segments

            # Global noise floor estimate (15th percentile RMS of voice.wav)
            hop_step = max(1, len(samples) // (frame_len * 500))
            frame_energies = []
            for i in range(0, len(samples) - frame_len, frame_len * hop_step):
                chunk = samples[i : i + frame_len]
                rms = float(np.sqrt(np.mean(chunk**2) + 1e-12))
                frame_energies.append(rms)

            global_noise_floor = float(np.percentile(frame_energies, 15)) if frame_energies else 0.001
            speech_threshold = max(0.005, global_noise_floor * 3.5)

            refined = []
            prev_end = 0.0
            for seg in segments:
                s_time = float(seg.get("start", 0.0))
                e_time = float(seg.get("end", s_time + 1.0))
                orig_s = s_time
                orig_e = e_time

                # Search window for onset: search backward up to 0.8s into gap to catch soft onsets/exclamations,
                # but never earlier than (prev_end + 0.05)
                search_s_time = max(prev_end + 0.05, s_time - 0.8)
                start_sample = max(0, int(search_s_time * sr))
                end_sample = min(len(samples), int(min(total_duration, s_time + 3.0) * sr))

                if start_sample < end_sample and (end_sample - start_sample) >= frame_len:
                    # Scan forward to find speech onset
                    for idx in range(start_sample, end_sample - frame_len, frame_len // 2):
                        chunk = samples[idx : idx + frame_len]
                        rms = float(np.sqrt(np.mean(chunk**2) + 1e-12))
                        if rms >= speech_threshold:
                            detected_sec = idx / sr
                            # If voice started earlier than reported start, snap to earlier onset with 50ms buffer
                            if detected_sec < s_time - 0.05:
                                s_time = max(search_s_time, detected_sec - 0.05)
                            # If voice started significantly later than reported start, snap forward
                            elif detected_sec > s_time + 0.15:
                                s_time = max(orig_s, detected_sec - 0.05)
                            break

                # Search window for offset: [max(s_time, e_time - 2.5), min(total_duration, e_time + 0.5)]
                tail_start_sample = max(0, int(max(s_time + 0.2, e_time - 2.5) * sr))
                tail_end_sample = min(len(samples), int(min(total_duration, e_time + 0.5) * sr))

                if tail_start_sample < tail_end_sample and (tail_end_sample - tail_start_sample) >= frame_len:
                    # Scan backward from tail to find actual voice offset
                    for idx in range(tail_end_sample - frame_len, tail_start_sample, -(frame_len // 2)):
                        chunk = samples[idx : idx + frame_len]
                        rms = float(np.sqrt(np.mean(chunk**2) + 1e-12))
                        if rms >= speech_threshold:
                            detected_offset = (idx + frame_len) / sr
                            # If speech ended >= 0.3s earlier than reported end, snap to offset with 80ms post-buffer
                            if e_time - detected_offset >= 0.3:
                                e_time = min(orig_e, max(s_time + 0.3, detected_offset + 0.08))
                            break

                seg_copy = dict(seg)
                seg_copy["start"] = round(s_time, 3)
                seg_copy["end"] = round(max(s_time + 0.2, e_time), 3)
                prev_end = float(seg_copy["end"])
                refined.append(seg_copy)

            return refined

        except Exception as e:
            print(f"[VAD] Timestamp refinement warning: {e}. Keeping original timestamps.")
            return segments

    @staticmethod
    def find_peak_voice_window(audio_path: Path, window_sec: float = 15.0, hop_sec: float = 2.0) -> tuple[float, float, float]:
        """
        Scans voice.wav in RAM using a sliding window to locate the time range
        with the highest vocal energy (RMS).
        Returns: (best_start_sec, best_end_sec, peak_rms_db)
        If file is invalid or empty, returns (0.0, min(window_sec, total_dur), -100.0).
        """
        if not audio_path.exists():
            return 0.0, window_sec, -100.0

        try:
            with wave.open(str(audio_path), "rb") as wf:
                sr = wf.getframerate()
                n_channels = wf.getnchannels()
                n_frames = wf.getnframes()
                raw_bytes = wf.readframes(n_frames)

            if wf.getsampwidth() == 2:
                samples = np.frombuffer(raw_bytes, dtype=np.int16).astype(np.float32) / 32768.0
            elif wf.getsampwidth() == 4:
                samples = np.frombuffer(raw_bytes, dtype=np.int32).astype(np.float32) / 2147483648.0
            else:
                return 0.0, window_sec, -100.0

            if n_channels > 1:
                samples = samples.reshape(-1, n_channels).mean(axis=1)

            total_dur = len(samples) / sr
            if total_dur <= window_sec:
                rms = float(np.sqrt(np.mean(samples**2) + 1e-12))
                rms_db = 20.0 * np.log10(rms + 1e-9)
                return 0.0, total_dur, float(rms_db)

            win_len = int(window_sec * sr)
            hop_len = max(1, int(hop_sec * sr))

            best_rms = -100.0
            best_start = 0.0

            for i in range(0, len(samples) - win_len, hop_len):
                chunk = samples[i : i + win_len]
                rms = float(np.sqrt(np.mean(chunk**2) + 1e-12))
                rms_db = 20.0 * np.log10(rms + 1e-9)
                if rms_db > best_rms:
                    best_rms = rms_db
                    best_start = i / sr

            return round(best_start, 2), round(best_start + window_sec, 2), round(float(best_rms), 1)
        except Exception as e:
            print(f"[VAD] Error finding peak voice window: {e}")
            return 0.0, window_sec, -100.0

