from pathlib import Path
from typing import Optional
import numpy as np
import soundfile as sf
from scipy.signal import fftconvolve


class GenderDetector:
    """
    Audio Pitch (Fundamental Frequency F0) Gender Detector.
    Uses Autocorrelation Analysis on audio segments.
    - Male pitch range: ~85 Hz - 165 Hz (average ~120 Hz)
    - Female pitch range: ~165 Hz - 265 Hz (average ~210 Hz)
    """

    @staticmethod
    def estimate_segment_f0(
        audio_path: str | Path,
        start_sec: float,
        end_sec: float,
        fmin: float = 70.0,
        fmax: float = 350.0,
        gender_threshold_hz: float = 165.0,
    ) -> str:
        """
        Estimates the dominant pitch (F0) for a given time window in an audio file.
        Returns: "male", "female", or "unknown"
        """
        audio_path = Path(audio_path)
        if not audio_path.exists() or end_sec <= start_sec:
            return "unknown"

        try:
            info = sf.info(str(audio_path))
            sr = info.samplerate
            total_duration = info.duration

            if start_sec >= total_duration:
                return "unknown"

            # Clamp start and duration
            start_frame = int(max(0, start_sec) * sr)
            num_frames = int(min(end_sec - start_sec, total_duration - start_sec) * sr)

            if num_frames < int(sr * 0.1):  # segment too short (<100ms)
                return "unknown"

            y, _ = sf.read(str(audio_path), start=start_frame, frames=num_frames, dtype="float32")

            # If multi-channel, convert to mono
            if y.ndim > 1:
                y = np.mean(y, axis=1)

            min_tau = int(sr / fmax)
            max_tau = int(sr / fmin)
            frame_len = int(sr * 0.04)  # 40ms frame
            hop = int(sr * 0.02)        # 20ms hop

            f0_list = []
            for start in range(0, len(y) - frame_len, hop):
                frame = y[start : start + frame_len]
                std_dev = np.std(frame)
                if std_dev < 0.01:  # silence / background noise
                    continue

                # Center / normalize frame
                norm_frame = frame - np.mean(frame)
                corr = fftconvolve(norm_frame, norm_frame[::-1], mode="full")
                corr = corr[len(norm_frame) - 1 :]

                if max_tau >= len(corr):
                    continue

                peak_tau = min_tau + np.argmax(corr[min_tau:max_tau])

                # Check peak ratio for voicing strength
                if corr[0] > 0 and corr[peak_tau] / corr[0] > 0.35:
                    f0 = sr / peak_tau
                    if fmin <= f0 <= fmax:
                        f0_list.append(f0)

            if len(f0_list) < 2:
                return "unknown"

            median_f0 = float(np.median(f0_list))

            if median_f0 < gender_threshold_hz:
                return "male"
            else:
                return "female"

        except Exception:
            return "unknown"
