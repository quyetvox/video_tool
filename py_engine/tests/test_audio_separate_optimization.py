import unittest
import numpy as np
import soundfile as sf
import tempfile
from pathlib import Path
from steps.s04_audio_separate import StepAudioSeparate, get_cached_demucs_model
from core.job_state import JobState


class TestAudioSeparateOptimization(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.workspace = Path(self.temp_dir.name)
        self.state_file = self.workspace / "job_state.json"
        self.job_state = JobState(self.state_file, job_id="test_demucs_opt")

        # Create a 2-second stereo test audio
        sr = 44100
        t = np.linspace(0, 2.0, int(sr * 2.0))
        sine_wave = (0.2 * np.sin(2 * np.pi * 440 * t)).astype(np.float32)
        stereo_audio = np.stack([sine_wave, sine_wave], axis=-1)

        self.audio_stream = self.workspace / "audio_stream.wav"
        sf.write(str(self.audio_stream), stereo_audio, sr)

        self.job_state.set_step_status(
            "s02_demux",
            "done",
            output={"audio_stream": str(self.audio_stream)}
        )

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_model_cache_reuse(self):
        model1, device1 = get_cached_demucs_model("htdemucs", preferred_device="cpu")
        model2, device2 = get_cached_demucs_model("htdemucs", preferred_device="cpu")
        self.assertIs(model1, model2, "Model instance should be cached in memory")
        self.assertEqual(device1, "cpu")

    def test_step_audio_separate_in_memory_success(self):
        step = StepAudioSeparate()
        config = {
            "device": "cpu",
            "noise_reduction_strength": 0.0
        }
        res = step.run(self.workspace, config, self.job_state)
        self.assertIn("voice", res)
        self.assertIn("music", res)

        voice_path = Path(res["voice"])
        music_path = Path(res["music"])
        self.assertTrue(voice_path.exists(), "voice.wav must exist")
        self.assertTrue(music_path.exists(), "music.wav must exist")
        self.assertGreater(voice_path.stat().st_size, 0)
        self.assertGreater(music_path.stat().st_size, 0)


if __name__ == "__main__":
    unittest.main()
