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
