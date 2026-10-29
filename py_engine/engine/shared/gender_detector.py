from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
import numpy as np
import soundfile as sf
from scipy.signal import fftconvolve


class GenderDetector:
    """
    Audio Pitch (F0) & Acoustic Spectral Clustering Gender Detector.
    Approach A:
    1. Extracts multi-dimensional acoustic features per segment (F0, Spectral Centroid, Rolloff, ZCR).
    2. Clusters segments into Speaker profiles (SPEAKER_00, SPEAKER_01, ...) using Adaptive Spectral Clustering.
    3. Aggregates all voiced frames per Speaker cluster across the entire audio to calculate robust F0 median.
    4. Eliminates intra-character voice flips and accurately handles short utterances (< 1.2s).
    """

    @staticmethod
    def extract_segment_features(
        audio_path: str | Path,
        start_sec: float,
        end_sec: float,
        fmin: float = 70.0,
        fmax: float = 350.0,
    ) -> Dict[str, Any]:
        """
        Extracts multi-feature acoustic representation for an audio slice.
        Returns: {
            "f0_median": float | None,
            "f0_list": List[float],
            "voiced_count": int,
            "spectral_centroid": float | None,
            "spectral_rolloff": float | None,
            "zcr": float,
            "energy": float
        }
        """
        audio_path = Path(audio_path)
        default_res = {
            "f0_median": None,
            "f0_list": [],
            "voiced_count": 0,
            "spectral_centroid": None,
            "spectral_rolloff": None,
            "zcr": 0.0,
            "energy": 0.0,
        }
        if not audio_path.exists() or end_sec <= start_sec:
            return default_res

        try:
            info = sf.info(str(audio_path))
            sr = info.samplerate
            total_duration = info.duration

            if start_sec >= total_duration:
                return default_res

            start_frame = int(max(0, start_sec) * sr)
            num_frames = int(min(end_sec - start_sec, total_duration - start_sec) * sr)

            if num_frames < int(sr * 0.08):  # segment too short (<80ms)
                return default_res

            y, _ = sf.read(str(audio_path), start=start_frame, frames=num_frames, dtype="float32")

            if y.ndim > 1:
                y = np.mean(y, axis=1)

            # Energy and Zero Crossing Rate
            energy = float(np.sqrt(np.mean(y**2)))
            zcr = float(np.mean(np.abs(np.diff(np.signbit(y)))))

            # Spectral analysis via FFT
            fft_len = 1024
            if len(y) >= fft_len:
                spec = np.abs(np.fft.rfft(y[:fft_len] * np.hanning(fft_len)))
                freqs = np.fft.rfftfreq(fft_len, d=1.0 / sr)
                sum_spec = np.sum(spec)
                if sum_spec > 1e-6:
                    spectral_centroid = float(np.sum(freqs * spec) / sum_spec)
                    # Spectral rolloff (85% energy threshold)
                    cum_energy = np.cumsum(spec)
                    rolloff_idx = np.searchsorted(cum_energy, 0.85 * sum_spec)
                    spectral_rolloff = float(freqs[min(rolloff_idx, len(freqs) - 1)])
                else:
                    spectral_centroid = None
                    spectral_rolloff = None
            else:
                spectral_centroid = None
                spectral_rolloff = None

            # Pitch (F0) Extraction via Autocorrelation
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

                norm_frame = frame - np.mean(frame)
                corr = fftconvolve(norm_frame, norm_frame[::-1], mode="full")
                corr = corr[len(norm_frame) - 1 :]

                if max_tau >= len(corr):
                    continue

                peak_tau = min_tau + np.argmax(corr[min_tau:max_tau])

                if corr[0] > 0 and corr[peak_tau] / corr[0] > 0.35:
                    f0 = sr / peak_tau
                    if fmin <= f0 <= fmax:
                        f0_list.append(float(f0))

            median_f0 = float(np.median(f0_list)) if len(f0_list) >= 2 else None

            return {
                "f0_median": median_f0,
                "f0_list": f0_list,
                "voiced_count": len(f0_list),
                "spectral_centroid": spectral_centroid,
                "spectral_rolloff": spectral_rolloff,
                "zcr": zcr,
                "energy": energy,
            }

        except Exception:
            return default_res

    @staticmethod
    def extract_segment_f0(
        audio_path: str | Path,
        start_sec: float,
        end_sec: float,
        fmin: float = 70.0,
        fmax: float = 350.0,
    ) -> Tuple[Optional[float], int]:
        """Backward compatible helper."""
        res = GenderDetector.extract_segment_features(audio_path, start_sec, end_sec, fmin, fmax)
        return res["f0_median"], res["voiced_count"]

    @staticmethod
    def estimate_segment_f0(
        audio_path: str | Path,
        start_sec: float,
        end_sec: float,
        gender_threshold_hz: float = 195.0,
    ) -> str:
        """Single segment fallback classification."""
        f0, _ = GenderDetector.extract_segment_f0(audio_path, start_sec, end_sec)
        if f0 is None:
            return "unknown"
        return "male" if f0 < gender_threshold_hz else "female"

    @classmethod
    def classify_segments(
        cls,
        audio_path: str | Path,
        segments: List[Dict[str, Any]],
        min_threshold: float = 165.0,
        max_threshold: float = 215.0,
        default_threshold: float = 195.0,
    ) -> Dict[str, Any]:
        """
        Classifies all segments in a video using Speaker Clustering + Speaker Profile Aggregation.
        Output dictionary contains:
          - "speaker_profiles": Dict of metadata for SPEAKER_00, SPEAKER_01, etc.
          - "<seg_id>": Dict of per-segment classification result.
        """
        if not segments:
            return {"speaker_profiles": {}}

        raw_features = []
        valid_indices = []
        valid_vectors = []

        for idx, seg in enumerate(segments):
            seg_id = str(seg.get("id", idx))
            start = float(seg.get("start", 0.0))
            end = float(seg.get("end", start + 1.0))
            text = str(seg.get("text", "")).strip()

            feat = cls.extract_segment_features(audio_path, start, end)
            feat["id"] = seg_id
            feat["start"] = start
            feat["end"] = end
            feat["text"] = text
            raw_features.append(feat)

            # Segments with sufficient voiced frames or spectral information
            if feat["f0_median"] is not None and feat["voiced_count"] >= 3:
                sc = feat["spectral_centroid"] or 2000.0
                sr_val = feat["spectral_rolloff"] or 3500.0
                valid_vectors.append([
                    feat["f0_median"] * 2.0,      # High weight on pitch
                    sc / 10.0,                   # Normalized Spectral Centroid
                    sr_val / 20.0,               # Normalized Rolloff
                    feat["zcr"] * 500.0          # Normalized ZCR
                ])
                valid_indices.append(idx)

        # 1. Speaker Clustering
        speaker_assignments = ["SPEAKER_00"] * len(raw_features)
        has_multiple_speakers = False

        if len(valid_indices) >= 4:
            vec_arr = np.array(valid_vectors, dtype=np.float32)
            # Feature standardization
            norm_vec = (vec_arr - np.mean(vec_arr, axis=0)) / (np.std(vec_arr, axis=0) + 1e-6)

            # Check if 2 distinct clusters exist using 2-Means
            c1 = norm_vec[np.argmin(norm_vec[:, 0])]
            c2 = norm_vec[np.argmax(norm_vec[:, 0])]

            for _ in range(10):
                d1 = np.sum((norm_vec - c1) ** 2, axis=1)
                d2 = np.sum((norm_vec - c2) ** 2, axis=1)
                g1 = norm_vec[d1 <= d2]
                g2 = norm_vec[d1 > d2]
                if len(g1) > 0:
                    c1 = np.mean(g1, axis=0)
                if len(g2) > 0:
                    c2 = np.mean(g2, axis=0)

            dist_between_clusters = np.linalg.norm(c1 - c2)
            # Check cluster separation and pitch spread
            f0_arr = np.array([raw_features[i]["f0_median"] for i in valid_indices])
            pitch_spread = np.percentile(f0_arr, 85) - np.percentile(f0_arr, 15)

            if dist_between_clusters > 1.8 and pitch_spread >= 35.0 and len(g1) >= 2 and len(g2) >= 2:
                has_multiple_speakers = True
                for i_idx, val_idx in enumerate(valid_indices):
                    d1 = np.sum((norm_vec[i_idx] - c1) ** 2)
                    d2 = np.sum((norm_vec[i_idx] - c2) ** 2)
                    speaker_assignments[val_idx] = "SPEAKER_00" if d1 <= d2 else "SPEAKER_01"

                # Propagate cluster labels to unvoiced / short segments by temporal proximity
                for i in range(len(raw_features)):
                    if i not in valid_indices:
                        # Find closest valid neighbor
                        distances = [abs(i - v) for v in valid_indices]
                        nearest_val = valid_indices[int(np.argmin(distances))]
                        speaker_assignments[i] = speaker_assignments[nearest_val]

        # 2. Aggregate Voiced Frames & Build Speaker Profiles
        speaker_profiles: Dict[str, Dict[str, Any]] = {}
        speaker_ids = ["SPEAKER_00", "SPEAKER_01"] if has_multiple_speakers else ["SPEAKER_00"]

        all_valid_f0s = [f for f in [feat["f0_median"] for feat in raw_features] if f is not None]
        adaptive_th = default_threshold
        if len(all_valid_f0s) >= 4:
            f0_arr = np.array(all_valid_f0s)
            mid = float(np.median(f0_arr))
            adaptive_th = float(np.clip(mid, min_threshold, max_threshold))

        for spk_id in speaker_ids:
            spk_f0_frames: List[float] = []
            spk_seg_count = 0
            for idx, feat in enumerate(raw_features):
                if speaker_assignments[idx] == spk_id:
                    spk_seg_count += 1
                    spk_f0_frames.extend(feat["f0_list"])

            if len(spk_f0_frames) >= 4:
                spk_f0_median = float(np.median(spk_f0_frames))
                spk_f0_std = float(np.std(spk_f0_frames))
                gender = "male" if spk_f0_median < adaptive_th else "female"
                delta = abs(spk_f0_median - adaptive_th)
                confidence = float(np.clip(0.65 + (delta / 60.0), 0.70, 0.98))
            elif len(spk_f0_frames) > 0:
                spk_f0_median = float(np.median(spk_f0_frames))
                spk_f0_std = 0.0
                gender = "male" if spk_f0_median < adaptive_th else "female"
                confidence = 0.75
            else:
                spk_f0_median = None
                spk_f0_std = 0.0
                gender = "unknown"
                confidence = 0.50

            speaker_profiles[spk_id] = {
                "gender": gender,
                "confidence": round(confidence, 2),
                "f0_median": round(spk_f0_median, 1) if spk_f0_median is not None else None,
                "f0_std": round(spk_f0_std, 1),
                "total_voiced_frames": len(spk_f0_frames),
                "segment_count": spk_seg_count,
            }

        # 3. Build Result Map with Per-Segment Speaker & Gender Association
        result_map: Dict[str, Any] = {
            "speaker_profiles": speaker_profiles
        }

        for idx, feat in enumerate(raw_features):
            spk = speaker_assignments[idx]
            prof = speaker_profiles.get(spk, {"gender": "unknown", "confidence": 0.5, "f0_median": None})
            
            # Segment-level result (fully backward-compatible with legacy keys)
            result_map[feat["id"]] = {
                "start": feat["start"],
                "end": feat["end"],
                "text": feat["text"],
                "speaker": spk,
                "gender": prof["gender"],
                "confidence": prof["confidence"],
                "f0": round(feat["f0_median"], 1) if feat["f0_median"] is not None else prof["f0_median"],
            }

        return result_map
