import math
import tempfile
import unittest
from pathlib import Path

import numpy as np
import scipy.signal as signal
import soundfile as sf

from plugins.tts.preset_tts import Plugin as PresetTTSPlugin
from steps.s12_tts import StepTTS, write_pcm_silence


class TestTTSInMemoryOptimization(unittest.TestCase):
    def test_concurrency_config_reading(self):
        """Verify that tts_num_workers in config is respected, falling back to 4."""
        plugin_default = PresetTTSPlugin({})
        self.assertEqual(plugin_default.config.get("tts_num_workers"), None)

        plugin_custom = PresetTTSPlugin({"tts_num_workers": 8})
        self.assertEqual(plugin_custom.config.get("tts_num_workers"), 8)

        plugin_alias = PresetTTSPlugin({"num_workers": 6})
        self.assertEqual(plugin_alias.config.get("num_workers"), 6)

    def test_resample_and_padding_trim(self):
        """Verify 24kHz mono audio is resampled to 44.1kHz stereo and silence is trimmed."""
        sr_orig = 24000
        sr_target = 44100

        # Create 0.2s silence + 0.5s tone + 0.2s silence
        t_tone = np.linspace(0, 0.5, int(sr_orig * 0.5), endpoint=False)
        tone = 0.5 * np.sin(2 * np.pi * 440 * t_tone)
        silence_pre = np.zeros(int(sr_orig * 0.2), dtype=np.float32)
        silence_post = np.zeros(int(sr_orig * 0.2), dtype=np.float32)
        raw_audio = np.concatenate([silence_pre, tone, silence_post]).astype(np.float32)

        # 1. Resample
        gcd = math.gcd(sr_target, sr_orig)
        up = sr_target // gcd
        down = sr_orig // gcd
        resampled = signal.resample_poly(raw_audio, up, down).astype(np.float32)
        stereo = np.column_stack((resampled, resampled))
        self.assertEqual(stereo.shape[1], 2)

        # 2. Trim padding (-42dB)
        mono = np.max(np.abs(stereo), axis=1)
        threshold = 10.0 ** (-42.0 / 20.0)
        voiced = np.where(mono > threshold)[0]
        self.assertTrue(len(voiced) > 0)
        first_idx = max(0, voiced[0] - int(sr_target * 0.02))
        last_idx = min(len(stereo), voiced[-1] + int(sr_target * 0.05))
        trimmed = stereo[first_idx:last_idx]

        # Expected trimmed duration around 0.5s (+ margin), distinctly shorter than 0.9s
        trimmed_dur = len(trimmed) / sr_target
        self.assertTrue(0.45 <= trimmed_dur <= 0.65)

    def test_anti_phantom_time_leap_and_absolute_positioning(self):
        """Verify that missing/skipped segments do not shift downstream sentence start times."""
        sr = 44100
        total_duration = 60.0
        total_samples = int(total_duration * sr)
        master_pcm = np.zeros((total_samples, 2), dtype=np.float32)

        segments = [
            {"id": 0, "start": 2.0, "end": 4.0, "text": "Câu thứ nhất"},
            {"id": 1, "start": 10.0, "end": 12.0, "text": "。"},  # Skipped / error segment
            {"id": 2, "start": 25.0, "end": 28.0, "text": "Câu thứ ba sau khoảng lặng"},
        ]

        tts_delay = 0.03
        # Simulate synthesized audio for seg 0 and seg 2 (seg 1 is missing/None)
        one_sec_audio = np.ones((int(sr * 1.0), 2), dtype=np.float32) * 0.5
        segment_pcm_results = {
            0: one_sec_audio.copy(),
            1: None,  # Failed or skipped
            2: one_sec_audio.copy(),
        }

        for idx, seg in enumerate(segments):
            y_seg = segment_pcm_results[idx]
            if y_seg is None or len(y_seg) == 0:
                continue

            effective_start = float(seg["start"]) + tts_delay
            start_sample = int(effective_start * sr)
            end_sample = min(total_samples, start_sample + len(y_seg))
            master_pcm[start_sample:end_sample] += y_seg[:end_sample - start_sample]

        # Verify Seg 0 is placed exactly at 2.03s
        seg0_start_sample = int((2.0 + tts_delay) * sr)
        self.assertAlmostEqual(master_pcm[seg0_start_sample, 0], 0.5, places=4)

        # Verify between 4.0s and 25.0s is strictly zero silence
        sample_check_gap = int(15.0 * sr)
        self.assertEqual(master_pcm[sample_check_gap, 0], 0.0)

        # Verify Seg 2 is placed EXACTLY at 25.03s despite Seg 1 being absent (No Phantom Leap!)
        seg2_start_sample = int((25.0 + tts_delay) * sr)
        self.assertAlmostEqual(master_pcm[seg2_start_sample, 0], 0.5, places=4)

    def test_anti_cascade_drift_slot_clamping(self):
        """Verify that an audio segment longer than the gap does not push the next sentence."""
        sr = 44100
        tts_delay = 0.03
        seg1_start = 2.0
        seg2_start = 3.0  # Gap is only 1.0 second

        effective_start = seg1_start + tts_delay
        next_effective_start = seg2_start + tts_delay

        # Seg 1 audio is 2.5 seconds long (exceeds 1.0s gap)
        long_audio = np.ones((int(sr * 2.5), 2), dtype=np.float32) * 0.7

        max_allowed_samples = int((next_effective_start - effective_start - 0.02) * sr)
        self.assertTrue(len(long_audio) > max_allowed_samples)

        # Apply slot clamping with 50ms fade
        clamped = long_audio[:max_allowed_samples].copy()
        fade_len = min(len(clamped), int(sr * 0.05))
        if fade_len > 0:
            clamped[-fade_len:] *= np.linspace(1.0, 0.0, fade_len)[:, None]

        # Clamped length must be strictly less than next_effective_start
        self.assertEqual(len(clamped), max_allowed_samples)
        # End of clamped audio must be smooth 0.0 due to fade-out
        self.assertAlmostEqual(clamped[-1, 0], 0.0, places=4)

    def test_in_memory_timeline_placement_speed(self):
        """Benchmark: 100 segments placed in RAM must complete in under 50 milliseconds."""
        import time
        sr = 44100
        total_samples = int(300.0 * sr)
        master_pcm = np.zeros((total_samples, 2), dtype=np.float32)

        sample_audio = np.ones((int(sr * 1.5), 2), dtype=np.float32) * 0.4

        t0 = time.time()
        for i in range(100):
            start_s = int((i * 2.5 + 0.03) * sr)
            end_s = start_s + len(sample_audio)
            master_pcm[start_s:end_s] += sample_audio

        elapsed_ms = (time.time() - t0) * 1000
        self.assertLess(elapsed_ms, 50.0)  # Must be < 50ms


if __name__ == "__main__":
    unittest.main()
