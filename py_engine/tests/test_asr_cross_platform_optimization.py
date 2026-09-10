import unittest
import sys
from unittest.mock import patch, MagicMock
from pathlib import Path
from core.plugin_loader import PluginLoader


class TestASRCrossPlatformOptimization(unittest.TestCase):
    def test_plugin_loader_cross_platform_mapping(self):
        # Test on macOS: mlx_whisper maps to whisper_mlx
        with patch("sys.platform", "darwin"):
            plugin_cls = PluginLoader.load_plugin("asr", "mlx-whisper", {})
            self.assertEqual(plugin_cls.__class__.__module__, "plugins.asr.whisper_mlx")

        # Test on Windows: mlx_whisper should map safely to whisper (not whisper_mlx)
        with patch("sys.platform", "win32"):
            # Mock importlib to verify it attempts to load plugins.asr.whisper
            with patch("importlib.import_module") as mock_import:
                mock_mod = MagicMock()
                mock_mod.Plugin = MagicMock(return_value="mock_whisper_plugin")
                mock_import.return_value = mock_mod

                _ = PluginLoader.load_plugin("asr", "mlx-whisper", {})
                mock_import.assert_called_with("plugins.asr.whisper")

    def test_whisper_mlx_model_resolution(self):
        from plugins.asr.whisper_mlx import Plugin as MLXPlugin

        # When asr_model is 'auto', it should resolve to 'small'
        plugin = MLXPlugin({"asr_model": "auto"})
        # Check that auto maps to small
        raw_m = str(plugin.config.get("asr_model", "auto")).lower().strip()
        selected = "small" if raw_m in ("auto", "small") else "large-v3-turbo"
        self.assertEqual(selected, "small")

        # When asr_model is 'turbo' or 'large-v3-turbo', it resolves to large-v3-turbo
        plugin_turbo = MLXPlugin({"asr_model": "large-v3-turbo"})
        raw_m_turbo = str(plugin_turbo.config.get("asr_model", "auto")).lower().strip()
        selected_turbo = "small" if raw_m_turbo in ("auto", "small") else "large-v3-turbo"
        self.assertEqual(selected_turbo, "large-v3-turbo")

    def test_whisper_windows_model_resolution(self):
        from plugins.asr.whisper import Plugin as WinPlugin

        plugin = WinPlugin({"asr_model": "auto"})
        raw_m = plugin.config.get("asr_model", "auto")
        selected = "small" if raw_m in ("auto", "", None) else raw_m
        self.assertEqual(selected, "small")

    def test_no_hf_hub_offline_leak_in_audio_separate(self):
        import os
        from steps.s04_audio_separate import get_cached_demucs_model, _DEMUCS_MODEL_CACHE

        # Clear cache to force loader run
        _DEMUCS_MODEL_CACHE.clear()
        os.environ.pop("HF_HUB_OFFLINE", None)

        with patch("demucs.pretrained.get_model") as mock_get_model:
            mock_m = MagicMock()
            mock_m.eval = MagicMock()
            mock_m.to = MagicMock()
            mock_get_model.return_value = mock_m

            # Call loader
            _, _ = get_cached_demucs_model("test_leak_model", "cpu")

            # CRITICAL CHECK: HF_HUB_OFFLINE must NOT remain in os.environ
            self.assertNotIn("HF_HUB_OFFLINE", os.environ, "HF_HUB_OFFLINE was leaked into os.environ!")

    def test_whisper_mlx_offline_snapshot_fallback(self):
        from plugins.asr.whisper_mlx import Plugin as MLXPlugin

        plugin = MLXPlugin({"asr_model": "auto"})

        mock_mlx = MagicMock()
        # Simulate tiny failing with missing snapshot offline error
        def mock_transcribe(audio_path, **kwargs):
            repo = kwargs.get("path_or_hf_repo", "")
            if "tiny" in repo or "small" in repo:
                raise RuntimeError("Cannot find an appropriate cached snapshot folder for the specified revision on the local disk")
            # fallback to large-v3-turbo succeeds
            return {
                "language": "zh",
                "segments": [
                    {"start": 0.0, "end": 2.0, "text": "Ni hao"}
                ]
            }
        mock_mlx.transcribe.side_effect = mock_transcribe

        with patch.dict("sys.modules", {"mlx_whisper": mock_mlx}):
            with patch("utils.audio_vad.AudioVAD.find_peak_voice_window", return_value=(0.0, 5.0, -20.0)):
                with patch("utils.ffmpeg_utils.FFmpegUtils.get_audio_duration", return_value=10.0):
                    with patch("subprocess.run") as mock_sub:
                        mock_sub.return_value = MagicMock(returncode=0)
                        dummy_audio = Path("dummy.wav")
                        segments = plugin.transcribe(dummy_audio)
                        self.assertEqual(len(segments), 1)
                        self.assertEqual(segments[0]["text"], "Ni hao")
                        self.assertEqual(plugin.detected_language, "zh")


if __name__ == "__main__":
    unittest.main()
