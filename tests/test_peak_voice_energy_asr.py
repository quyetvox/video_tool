import json
import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np
from utils.audio_vad import AudioVAD
from utils.chunk_manifest import ChunkManifestManager, ManifestData


class TestPeakVoiceEnergyASR(unittest.TestCase):
    def setUp(self):
        self.tmp_dir = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp_dir.name)

    def tearDown(self):
        self.tmp_dir.cleanup()

    def test_find_peak_voice_window_detects_loudest_speech_region(self):
        # Create 30-second audio: 15s silence (zeros) followed by 15s tone (high amplitude)
        sr = 16000
        dur_silence = 15.0
        dur_tone = 15.0
        total_len = int((dur_silence + dur_tone) * sr)

        samples = np.zeros(total_len, dtype=np.float32)
        # Tone at 440 Hz in second half
        t = np.linspace(0, dur_tone, int(dur_tone * sr), endpoint=False)
        samples[int(dur_silence * sr):] = 0.5 * np.sin(2 * np.pi * 440 * t)

        wav_path = self.tmp_path / "test_peak.wav"
        with wave.open(str(wav_path), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sr)
            wf.writeframes((samples * 32767.0).astype(np.int16).tobytes())

        start_sec, end_sec, peak_rms = AudioVAD.find_peak_voice_window(wav_path, window_sec=10.0, hop_sec=1.0)

        # Peak window should be in the second half (>= 14s)
        self.assertGreaterEqual(start_sec, 14.0)
        self.assertGreater(peak_rms, -20.0)  # Amplitude 0.5 has RMS ~ -9 dB

    def test_find_peak_voice_window_handles_pure_silence(self):
        # Create 10s of pure silence
        sr = 16000
        samples = np.zeros(10 * sr, dtype=np.int16)

        wav_path = self.tmp_path / "test_silence.wav"
        with wave.open(str(wav_path), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sr)
            wf.writeframes(samples.tobytes())

        start_sec, end_sec, peak_rms = AudioVAD.find_peak_voice_window(wav_path, window_sec=5.0)
        self.assertLess(peak_rms, -50.0)

    def test_chunk_manifest_language_inheritance(self):
        # Create a manifest manager and test detected_language persistence
        mgr = ChunkManifestManager(
            workspace_root=self.tmp_path / "workspace",
            video_path=self.tmp_path / "video.mp4"
        )
        data = mgr.load_or_create_manifest(
            boundaries=[(0.0, 10.0), (10.0, 20.0)],
            total_duration_sec=20.0,
            target_chunk_duration_sec=10.0
        )
        self.assertIsNone(data.detected_language)

        # Record detected language
        mgr.update_detected_language("zh")
        self.assertEqual(mgr.data.detected_language, "zh")

        # Reload manifest and verify persistence
        mgr2 = ChunkManifestManager(
            workspace_root=self.tmp_path / "workspace",
            video_path=self.tmp_path / "video.mp4"
        )
        data2 = mgr2.load_or_create_manifest([], 20.0, 10.0)
        self.assertEqual(data2.detected_language, "zh")


if __name__ == "__main__":
    unittest.main()
