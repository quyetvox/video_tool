#!/usr/bin/env python3
"""
Unit and Integration Tests for Long Video Smart Chunker & Resumable Pipeline.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import sys
ROOT_DIR = Path(__file__).parent.parent.resolve()
PY_ENGINE_DIR = ROOT_DIR / "py_engine"
if str(PY_ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(PY_ENGINE_DIR))

from utils.resource_guard import ResourceGuard
from utils.smart_splitter import SmartSplitter
from utils.chunk_manifest import ChunkManifestManager, ChunkStatus
from long_video_orchestrator import LongVideoOrchestrator


class TestLongVideoChunker(unittest.TestCase):

    def setUp(self):
        self.test_dir = Path(tempfile.mkdtemp(prefix="test_chunker_"))

    def tearDown(self):
        if self.test_dir.exists():
            shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_resource_guard_calculation(self):
        alloc = ResourceGuard.calculate_allocation()
        self.assertGreater(alloc.total_ram_gb, 0.0)
        self.assertGreater(alloc.available_ram_gb, 0.0)
        self.assertLessEqual(alloc.max_allowed_ram_gb, alloc.available_ram_gb * 0.71)
        self.assertGreaterEqual(alloc.safe_workers, 1)
        self.assertIn(alloc.recommended_chunk_duration_sec, [360, 720])

        # Test custom parameters
        custom_alloc = ResourceGuard.calculate_allocation(
            max_ram_usage_gb=8.0,
            custom_workers=2,
            custom_chunk_minutes=5.0
        )
        self.assertLessEqual(custom_alloc.max_allowed_ram_gb, 8.0)
        self.assertLessEqual(custom_alloc.safe_workers, 2)
        self.assertEqual(custom_alloc.recommended_chunk_duration_sec, 300)

    def test_chunk_manifest_manager_lifecycle(self):
        video_dummy = self.test_dir / "sample_podcast.mp4"
        video_dummy.touch()

        mgr = ChunkManifestManager(workspace_root=self.test_dir, video_path=video_dummy)
        boundaries = [(0.0, 180.0), (180.0, 360.0), (360.0, 540.0)]
        
        manifest = mgr.load_or_create_manifest(
            boundaries=boundaries,
            total_duration_sec=540.0,
            target_chunk_duration_sec=180.0,
            final_output_path=str(self.test_dir / "sample_podcast_vi.mp4")
        )

        self.assertEqual(manifest.total_chunks, 3)
        self.assertEqual(len(manifest.chunks), 3)
        self.assertEqual(manifest.chunks[0].status, ChunkStatus.PENDING)

        # Update chunk 1
        mgr.update_chunk(1, status=ChunkStatus.PROCESSING, progress=50.0, current_step="s08_translation")
        self.assertEqual(mgr.data.chunks[0].status, ChunkStatus.PROCESSING)
        self.assertEqual(mgr.data.chunks[0].progress, 50.0)
        self.assertEqual(mgr.calculate_overall_progress(), round(50.0 / 3, 1))

        # Complete chunk 1 and create dummy output
        out_1 = Path(mgr.data.chunks[0].output_file)
        out_1.write_bytes(b"dummy_mp4_bytes_1234567890" * 100)
        mgr.update_chunk(1, status=ChunkStatus.COMPLETED, progress=100.0)
        self.assertEqual(mgr.calculate_overall_progress(), round(100.0 / 3, 1))

        # Re-instantiate manager and verify persistence
        mgr_reload = ChunkManifestManager(workspace_root=self.test_dir, video_path=video_dummy)
        reloaded = mgr_reload.load_or_create_manifest(
            boundaries=boundaries,
            total_duration_sec=540.0,
            target_chunk_duration_sec=180.0
        )
        self.assertEqual(reloaded.chunks[0].status, ChunkStatus.COMPLETED)
        self.assertEqual(len(mgr_reload.get_pending_or_failed_chunks()), 2)

    def test_synthetic_video_split_and_merge(self):
        """Creates a synthetic 6s MP4 video, splits into 2 chunks, and merges them losslessly."""
        src_video = self.test_dir / "synthetic_test.mp4"
        
        # Generate a 6-second video with color test pattern & audio tone + silence
        cmd_gen = [
            "ffmpeg", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=6:size=640x360:rate=30",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=6",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-g", "30",
            "-c:a", "aac",
            str(src_video)
        ]
        res = subprocess.run(cmd_gen, capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"FFmpeg failed to create test video: {res.stderr}")
        self.assertTrue(src_video.exists())

        dur = SmartSplitter.get_video_duration(src_video)
        self.assertAlmostEqual(dur, 6.0, delta=0.5)

        # Test smart boundaries computation with small target length
        boundaries = SmartSplitter.compute_chunk_boundaries(
            video_path=src_video,
            total_duration=dur,
            target_chunk_duration_sec=3.0
        )
        self.assertGreaterEqual(len(boundaries), 2)

        # Split chunks
        mgr = ChunkManifestManager(workspace_root=self.test_dir, video_path=src_video)
        manifest = mgr.load_or_create_manifest(
            boundaries=boundaries,
            total_duration_sec=dur,
            target_chunk_duration_sec=3.0
        )

        for c in manifest.chunks:
            ok = SmartSplitter.split_chunk_lossless(
                input_video=src_video,
                start_sec=c.start_sec,
                end_sec=c.end_sec,
                output_chunk_path=c.raw_chunk_file
            )
            self.assertTrue(ok)
            self.assertTrue(Path(c.raw_chunk_file).exists())
            
            # Simulate pipeline producing output
            shutil.copy2(c.raw_chunk_file, c.output_file)
            mgr.update_chunk(c.id, status=ChunkStatus.COMPLETED, progress=100.0)

        self.assertTrue(mgr.is_all_completed())

        # Test concat list generation & final lossless merge
        concat_list = mgr.generate_concat_list()
        self.assertTrue(concat_list.exists())

        final_out = self.test_dir / "final_merged_vi.mp4"
        cmd_merge = [
            "ffmpeg", "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", str(concat_list),
            "-c", "copy",
            str(final_out)
        ]
        res_merge = subprocess.run(cmd_merge, capture_output=True, text=True)
        self.assertEqual(res_merge.returncode, 0, f"FFmpeg concat failed: {res_merge.stderr}")
        self.assertTrue(final_out.exists())
        self.assertGreater(final_out.stat().st_size, 1024)

        merged_dur = SmartSplitter.get_video_duration(final_out)
        self.assertAlmostEqual(merged_dur, dur, delta=0.5)

    def test_long_video_cut_folder_and_cache_reuse(self):
        """Tests that raw chunks are saved in cut_dir, outputs in output_dir, and cached chunks are auto-completed."""
        cut_dir = self.test_dir / "cut"
        output_dir = self.test_dir / "output"
        workspace_dir = self.test_dir / "workspace"
        src_video = self.test_dir / "my_master_video.mp4"
        src_video.touch()

        mgr = ChunkManifestManager(
            workspace_root=workspace_dir,
            video_path=src_video,
            cut_dir=cut_dir,
            output_dir=output_dir
        )
        boundaries = [(0.0, 120.0), (120.0, 240.0)]
        manifest = mgr.load_or_create_manifest(
            boundaries=boundaries,
            total_duration_sec=240.0,
            target_chunk_duration_sec=120.0,
            final_output_path=str(output_dir / "my_master_video_vi.mp4")
        )

        self.assertEqual(manifest.total_chunks, 2)
        # Verify raw chunks are located inside cut_dir with expected naming
        self.assertEqual(Path(manifest.chunks[0].raw_chunk_file).parent, cut_dir.resolve())
        self.assertEqual(Path(manifest.chunks[0].raw_chunk_file).name, "my_master_video_part_001.mp4")
        self.assertEqual(Path(manifest.chunks[1].raw_chunk_file).name, "my_master_video_part_002.mp4")

        # Verify output files are located inside output_dir with expected naming
        self.assertEqual(Path(manifest.chunks[0].output_file).parent, output_dir.resolve())
        self.assertEqual(Path(manifest.chunks[0].output_file).name, "my_master_video_part_001_vi.mp4")

        # Test smart cache auto-recovery: create chunk 1 output
        c1_out = Path(manifest.chunks[0].output_file)
        c1_out.parent.mkdir(parents=True, exist_ok=True)
        c1_out.write_bytes(b"dummy_rendered_mp4" * 100)

        # Re-load manifest - chunk 1 should be recognized as COMPLETED immediately
        mgr_cache = ChunkManifestManager(
            workspace_root=workspace_dir,
            video_path=src_video,
            cut_dir=cut_dir,
            output_dir=output_dir
        )
        reloaded = mgr_cache.load_or_create_manifest(
            boundaries=boundaries,
            total_duration_sec=240.0,
            target_chunk_duration_sec=120.0
        )
        self.assertEqual(reloaded.chunks[0].status, ChunkStatus.COMPLETED)
        self.assertEqual(reloaded.chunks[0].progress, 100.0)
        self.assertEqual(reloaded.chunks[1].status, ChunkStatus.PENDING)


if __name__ == "__main__":
    unittest.main()

