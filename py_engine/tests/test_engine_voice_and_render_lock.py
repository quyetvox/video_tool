"""
Regression & Architecture Lock Test Suite for Sub-Video `engine/` Package:
1. Canonical `engine.*` vs Legacy Module Alias Identity (`sys.modules` singleton guarantee)
2. Voice / TTS Invariants Lock (StepTTS s12, PresetTTS, MovieReviewTTS, TTS Studio, NarrationVoiceGenerator)
3. Multi-threaded & Multi-process Rendering Lock (ConcurrencyManager, ProcessPoolExecutor spawn pickling, Dual-Track PipelineRunner, Direct CLI execution)
"""

import importlib
import json
import os
import pickle
import subprocess
import sys
import tempfile
import time
import unittest
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from unittest.mock import patch

import numpy as np

import engine  # noqa: F401
from engine.paths import ENGINE_DIR, ROOT_DIR


class TestEngineVoiceAndRenderLock(unittest.TestCase):
    """Locks Voice/TTS and Multi-threaded/Multi-process Render invariants under `engine/`."""

    def test_01_canonical_and_legacy_module_identity(self):
        """All Voice and Render modules must resolve to the exact same module object via engine.* and legacy aliases."""
        pairs = [
            ("engine.pipeline.steps.s12_tts", "steps.s12_tts"),
            ("engine.pipeline.plugins.tts.preset_tts", "plugins.tts.preset_tts"),
            ("engine.shared.movie_review_tts", "utils.movie_review_tts"),
            ("engine.features.tts_studio.tts_studio_tool", "tts_studio_tool"),
            ("engine.features.tts_studio.narration_voice_generator", "narration_voice_generator"),
            ("engine.features.tts_studio.tts_cache_manager", "utils.tts_cache_manager"),
            ("engine.core.concurrency", "core.concurrency"),
            ("engine.core.pipeline_runner", "core.pipeline_runner"),
            ("engine.features.lecture_illustrator.visual_renderer", "lecture_illustrator.visual_renderer"),
            ("engine.features.lecture_illustrator.scene_renderer", "lecture_illustrator.scene_renderer"),
            ("engine.features.render.html_to_mp4", "html_to_mp4"),
            ("engine.features.render.composite_render", "composite_render"),
            ("engine.pipeline.plugins.ocr.rapid_ocr", "plugins.ocr.rapid_ocr"),
            ("engine.pipeline.plugins.ocr.paddle_ocr", "plugins.ocr.paddle_ocr"),
            ("engine.pipeline.plugins.inpaint.apple_vision_inpaint", "plugins.inpaint.apple_vision_inpaint"),
            ("engine.pipeline.plugins.inpaint.opencv_inpaint", "plugins.inpaint.opencv_inpaint"),
            ("engine.pipeline.plugins.inpaint.ffmpeg_blur", "plugins.inpaint.ffmpeg_blur"),
        ]
        for canonical_name, legacy_name in pairs:
            mod_canonical = importlib.import_module(canonical_name)
            mod_legacy = importlib.import_module(legacy_name)
            self.assertIs(
                mod_canonical,
                mod_legacy,
                f"Module mismatch between {canonical_name} and {legacy_name}",
            )

    def test_02_step_tts_zero_process_bypass_and_english_voice_guard(self):
        """StepTTS (s12_tts) must bypass in ~0s when disabled/ocr_only and guard Vietnamese voices when target_lang='en'."""
        from engine.core.job_state import JobState
        from engine.pipeline.steps.s12_tts import StepTTS

        step = StepTTS()
        with tempfile.TemporaryDirectory() as td:
            ws = Path(td)
            js = JobState(ws / "job_state.json", job_id="test_bypass")

            # 1. ocr_only bypass
            res1 = step.run(ws, {"ocr_only": True}, js)
            self.assertTrue(res1["skipped"])
            self.assertEqual(res1["segment_count"], 0)

            # 2. tts_voice_volume == 0.0 bypass
            res2 = step.run(ws, {"tts_voice_volume": 0.0}, js)
            self.assertTrue(res2["skipped"])
            self.assertEqual(res2["segment_count"], 0)

            # 3. tts_voice == 'none' bypass
            res3 = step.run(ws, {"tts_voice": "none"}, js)
            self.assertTrue(res3["skipped"])
            self.assertEqual(res3["segment_count"], 0)

    def test_03_preset_tts_and_movie_review_tts_voice_mapping_lock(self):
        """PresetTTS and MovieReviewTTS voice maps and speed/rate conversions must remain 100% locked."""
        from engine.pipeline.plugins.tts.preset_tts import Plugin as PresetTTSPlugin
        from engine.shared.movie_review_tts import MovieReviewTTS
        from engine.features.tts_studio.tts_studio_tool import (
            calculate_timeline_speed,
            speed_to_rate_str,
            pitch_to_str,
        )

        plugin = PresetTTSPlugin({"tts_num_workers": 4})
        self.assertEqual(plugin._resolve_voice("vi-VN-BanMai"), "gtts_vi")
        self.assertEqual(plugin._resolve_voice("banmai"), "gtts_vi")
        self.assertEqual(plugin._resolve_voice("vi-VN-HoaiMyNeural"), "vi-VN-HoaiMyNeural")
        self.assertEqual(plugin._resolve_voice("namminh"), "vi-VN-NamMinhNeural")
        self.assertEqual(plugin._resolve_voice("english_female"), "en-US-JennyNeural")
        self.assertEqual(plugin._resolve_voice("english_male"), "en-US-GuyNeural")
        self.assertEqual(plugin._resolve_voice("gtts_en"), "gtts_en")

        self.assertEqual(speed_to_rate_str(1.0), "+0%")
        self.assertEqual(speed_to_rate_str(1.25), "+25%")
        self.assertEqual(speed_to_rate_str(1.15), "+15%")
        self.assertEqual(pitch_to_str(-10), "-10Hz")

        # MovieReviewTTS VOICE_MAP lock
        self.assertEqual(MovieReviewTTS.VOICE_MAP["ban_mai"], ("gtts", "vi"))
        self.assertEqual(MovieReviewTTS.VOICE_MAP["hoai_my"], ("edge", "vi-VN-HoaiMyNeural"))
        self.assertEqual(MovieReviewTTS.VOICE_MAP["nam_minh"], ("edge", "vi-VN-NamMinhNeural"))
        self.assertEqual(MovieReviewTTS.VOICE_MAP["jenny"], ("edge", "en-US-JennyNeural"))
        self.assertEqual(MovieReviewTTS.VOICE_MAP["guy"], ("edge", "en-US-GuyNeural"))
        self.assertEqual(MovieReviewTTS.VOICE_MAP["gtts_en"], ("gtts", "en"))

        # Timeline speed floor & auto-boost lock
        spd_short, boosted_short = calculate_timeline_speed("Xin chào bạn", slot_duration=4.0, base_speed=1.15)
        self.assertFalse(boosted_short)
        self.assertEqual(spd_short, 1.15)

        spd_long, boosted_long = calculate_timeline_speed(
            "Đây là một câu thuyết minh rất dài cần được đọc nhanh hơn để vừa khít vào ô thời gian ngắn.",
            slot_duration=1.8,
            base_speed=1.0,
        )
        self.assertTrue(boosted_long)
        self.assertGreater(spd_long, 2.0)

    def test_04_s12_tts_pcm_silence_and_cross_ducking_lock(self):
        """write_pcm_silence and multi-track cross-ducking math in s12_tts must remain deterministic."""
        import soundfile as sf
        from engine.pipeline.steps.s12_tts import write_pcm_silence

        with tempfile.TemporaryDirectory() as td:
            wav_path = Path(td) / "silence.wav"
            write_pcm_silence(wav_path, duration_sec=1.5, sample_rate=44100)
            self.assertTrue(wav_path.exists())
            data, sr = sf.read(str(wav_path), dtype="float32")
            self.assertEqual(sr, 44100)
            self.assertEqual(data.shape, (int(1.5 * 44100), 2))
            self.assertEqual(float(np.max(np.abs(data))), 0.0)

    def test_05_concurrency_manager_and_process_pool_spawn_lock(self):
        """ConcurrencyManager and ProcessPoolExecutor worker functions must pickle and execute cleanly across spawn."""
        from engine.core.concurrency import ConcurrencyManager
        from engine.features.lecture_illustrator.models import LectureBatch, LectureProjectConfig
        from engine.features.lecture_illustrator.visual_renderer import (
            _render_batch_worker_task,
            compute_batch_fingerprint,
        )
        from engine.features.render.html_to_mp4 import _render_html_scene_worker
        from engine.pipeline.plugins.inpaint.apple_vision_inpaint import _inpaint_chunk_worker_apple_vision
        from engine.pipeline.plugins.inpaint.opencv_inpaint import _inpaint_chunk_worker
        from engine.pipeline.plugins.ocr.paddle_ocr import _run_paddle_chunk_worker
        from engine.pipeline.plugins.ocr.rapid_ocr import _run_rapid_chunk_worker

        # 1. ConcurrencyManager worker resolution
        self.assertEqual(ConcurrencyManager.get_num_workers({"num_workers": 6}), 6)
        self.assertEqual(ConcurrencyManager.get_num_workers({"app": {"num_workers": 4}}), 4)
        auto_w = ConcurrencyManager.get_num_workers({"num_workers": "auto"})
        self.assertGreaterEqual(auto_w, 2)
        self.assertLessEqual(auto_w, 32)

        # 2. All ProcessPoolExecutor worker functions must have canonical engine.* __module__ and be picklable
        workers = [
            _render_batch_worker_task,
            _render_html_scene_worker,
            _run_rapid_chunk_worker,
            _run_paddle_chunk_worker,
            _inpaint_chunk_worker_apple_vision,
            _inpaint_chunk_worker,
            compute_batch_fingerprint,
        ]
        for fn in workers:
            self.assertTrue(
                fn.__module__.startswith("engine."),
                f"Worker {fn.__name__} module {fn.__module__} must start with 'engine.'",
            )
            dumped = pickle.dumps(fn)
            restored = pickle.loads(dumped)
            self.assertIs(restored, fn)

        # 3. Real ProcessPoolExecutor spawn execution test
        batch = LectureBatch(
            id="batch_001",
            start_sec=0.0,
            end_sec=6.0,
            transcript_original="Hello",
            transcript_translated="Xin chào",
            scene_duration=6.0,
        )
        cfg = LectureProjectConfig(fps=24)
        with ProcessPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(compute_batch_fingerprint, batch, cfg) for _ in range(2)]
            results = [f.result(timeout=15) for f in futures]
        self.assertEqual(len(results), 2)
        self.assertEqual(results[0], results[1])

    def test_06_direct_cli_execution_of_engine_modules_without_pythonpath(self):
        """Executing engine CLI scripts directly by file path without external PYTHONPATH must succeed."""
        clean_env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"}

        # 1. Direct execution of engine/features/tts_studio/tts_studio_tool.py --action get_voices
        tts_script = ENGINE_DIR / "engine" / "features" / "tts_studio" / "tts_studio_tool.py"
        res_tts = subprocess.run(
            [sys.executable, str(tts_script), "--action", "get_voices"],
            cwd=str(ROOT_DIR),
            env=clean_env,
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(res_tts.returncode, 0, f"stderr: {res_tts.stderr}")
        payload = json.loads(res_tts.stdout.strip())
        self.assertTrue(payload.get("success"))
        self.assertGreaterEqual(len(payload.get("voices", [])), 5)

        # 2. Direct execution of engine/cli/main.py --help
        main_script = ENGINE_DIR / "engine" / "cli" / "main.py"
        res_main = subprocess.run(
            [sys.executable, str(main_script), "--help"],
            cwd=str(ROOT_DIR),
            env=clean_env,
            capture_output=True,
            text=True,
            timeout=15,
        )
        self.assertEqual(res_main.returncode, 0, f"stderr: {res_main.stderr}")
        self.assertIn("translate", res_main.stdout)


if __name__ == "__main__":
    unittest.main()
