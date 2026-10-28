"""
Unit tests for TTS Cache Manager (py_engine/utils/tts_cache_manager.py).
"""

import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT_PY_ENGINE = Path(__file__).resolve().parent.parent
if str(ROOT_PY_ENGINE) not in sys.path:
    sys.path.insert(0, str(ROOT_PY_ENGINE))

from utils.tts_cache_manager import auto_clean_tts_cache, get_tts_cache_dir


class TestTTSCacheManager(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.cache_dir = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def test_force_all_cleanup(self):
        """Kiểm tra force_all xóa toàn bộ file trong cache."""
        for i in range(5):
            f = self.cache_dir / f"test_{i}.mp3"
            f.write_bytes(b"test_content" * 10)

        self.assertEqual(len(list(self.cache_dir.glob("*.mp3"))), 5)
        del_count, freed = auto_clean_tts_cache(cache_dir=self.cache_dir, force_all=True)
        self.assertEqual(del_count, 5)
        self.assertGreater(freed, 0)
        self.assertEqual(len(list(self.cache_dir.glob("*.mp3"))), 0)

    def test_age_based_pruning(self):
        """Kiểm tra xóa các file cũ hơn max_age_days."""
        now = time.time()
        # File 1: Rất cũ (4 ngày trước)
        old_file = self.cache_dir / "old.mp3"
        old_file.write_bytes(b"old")
        os.utime(old_file, (now - 4 * 86400, now - 4 * 86400))

        # File 2: Mới tạo (vừa xong)
        fresh_file = self.cache_dir / "fresh.mp3"
        fresh_file.write_bytes(b"fresh")

        del_count, _ = auto_clean_tts_cache(
            cache_dir=self.cache_dir,
            max_age_days=3,
            ignore_cooldown=True,
        )

        self.assertEqual(del_count, 1)
        self.assertFalse(old_file.exists())
        self.assertTrue(fresh_file.exists())

    def test_size_based_lru_pruning(self):
        """Kiểm tra xóa file cũ nhất khi dung lượng vượt max_size_mb."""
        now = time.time()
        # Tạo 3 file, mỗi file ~1MB
        f1 = self.cache_dir / "f1.mp3"
        f1.write_bytes(b"A" * (1024 * 1024))
        os.utime(f1, (now - 300, now - 300))

        f2 = self.cache_dir / "f2.mp3"
        f2.write_bytes(b"B" * (1024 * 1024))
        os.utime(f2, (now - 200, now - 200))

        f3 = self.cache_dir / "f3.mp3"
        f3.write_bytes(b"C" * (1024 * 1024))
        os.utime(f3, (now - 100, now - 100))

        # Tổng dung lượng 3MB. Giới hạn 2MB -> Cần prune bớt file cũ nhất (f1)
        del_count, _ = auto_clean_tts_cache(
            cache_dir=self.cache_dir,
            max_size_mb=2.0,
            max_age_days=30,
            ignore_cooldown=True,
        )

        self.assertGreaterEqual(del_count, 1)
        self.assertFalse(f1.exists())  # f1 cũ nhất phải bị xóa trước
        self.assertTrue(f3.exists())  # f3 mới nhất được giữ lại


if __name__ == "__main__":
    unittest.main()
