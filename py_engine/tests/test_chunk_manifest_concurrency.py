import concurrent.futures
import shutil
import tempfile
import unittest
from pathlib import Path

from utils.chunk_manifest import ChunkManifestManager, ChunkStatus


class TestChunkManifestConcurrency(unittest.TestCase):
    def setUp(self):
        self.test_dir = Path(tempfile.mkdtemp(prefix="test_manifest_"))
        self.video_path = self.test_dir / "sample.mp4"
        self.video_path.touch()
        self.mgr = ChunkManifestManager(
            workspace_root=self.test_dir / "workspace",
            video_path=self.video_path
        )
        self.mgr.load_or_create_manifest(
            boundaries=[(0.0, 10.0), (10.0, 20.0), (20.0, 30.0)],
            total_duration_sec=30.0,
            target_chunk_duration_sec=10.0
        )

    def tearDown(self):
        if self.test_dir.exists():
            shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_concurrent_updates_do_not_crash(self):
        """Simulate multiple background and foreground threads updating chunks concurrently."""
        def worker(chunk_id: int, step: str, progress: float):
            for i in range(10):
                self.mgr.update_chunk(
                    chunk_id=chunk_id,
                    status=ChunkStatus.PROCESSING,
                    progress=progress + i,
                    current_step=f"{step}_{i}"
                )

        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = [
                executor.submit(worker, 1, "s04_audio_separate", 10.0),
                executor.submit(worker, 1, "s10_inpaint", 15.0),
                executor.submit(worker, 2, "s01_probe", 0.0),
                executor.submit(worker, 2, "s05_asr", 30.0),
                executor.submit(worker, 3, "s08_translation", 50.0),
            ]
            for f in concurrent.futures.as_completed(futures):
                f.result()

        self.assertTrue(self.mgr.manifest_file.exists())
        # Reload manifest to verify valid JSON without corruption
        reloaded = ChunkManifestManager(
            workspace_root=self.test_dir / "workspace",
            video_path=self.video_path
        )
        manifest_data = reloaded.load_or_create_manifest(
            boundaries=[(0.0, 10.0), (10.0, 20.0), (20.0, 30.0)],
            total_duration_sec=30.0,
            target_chunk_duration_sec=10.0
        )
        self.assertEqual(len(manifest_data.chunks), 3)


if __name__ == "__main__":
    unittest.main()
