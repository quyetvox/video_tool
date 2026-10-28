"""
py_engine/utils/tts_cache_manager.py
====================================
Unified TTS Cache Manager with Automated LRU & Age Pruning.
Prevents disk exhaustion from cumulative TTS audio segment caches (~/.subvideo/tts_cache).
"""

import os
import shutil
import time
from pathlib import Path
from typing import Optional, Tuple

DEFAULT_MAX_CACHE_SIZE_MB: float = 100.0   # Prune if cache exceeds 100MB
DEFAULT_MAX_CACHE_AGE_DAYS: int = 3        # Delete files older than 3 days
_LAST_CLEANUP_TS: float = 0.0
_CLEANUP_COOLDOWN_SEC: float = 300.0       # Minimum 5 minutes between auto-checks


def get_tts_cache_dir() -> Path:
    """Return central cache directory for synthesized TTS audio segments."""
    cache_dir = Path.home() / ".subvideo" / "tts_cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    return cache_dir


def auto_clean_tts_cache(
    cache_dir: Optional[Path] = None,
    max_size_mb: float = DEFAULT_MAX_CACHE_SIZE_MB,
    max_age_days: int = DEFAULT_MAX_CACHE_AGE_DAYS,
    force_all: bool = False,
    ignore_cooldown: bool = False,
) -> Tuple[int, float]:
    """
    Automatically clean up the TTS cache directory.
    
    Parameters:
    - cache_dir: Optional specific directory (default: ~/.subvideo/tts_cache).
    - max_size_mb: Max allowed total cache size in Megabytes.
    - max_age_days: Max age in days before a file is deleted.
    - force_all: If True, deletes all files immediately.
    - ignore_cooldown: If True, bypasses the 5-minute cooldown throttle.
    
    Returns:
    (deleted_count, freed_bytes)
    """
    global _LAST_CLEANUP_TS
    now = time.time()

    if not force_all and not ignore_cooldown:
        if (now - _LAST_CLEANUP_TS) < _CLEANUP_COOLDOWN_SEC:
            return 0, 0.0

    target_dir = cache_dir or get_tts_cache_dir()
    if not target_dir.exists():
        return 0, 0.0

    deleted_count = 0
    freed_bytes = 0.0

    # 1. Force All Wipe
    if force_all:
        try:
            for item in target_dir.iterdir():
                try:
                    if item.is_file() or item.is_symlink():
                        sz = item.stat().st_size
                        item.unlink(missing_ok=True)
                        deleted_count += 1
                        freed_bytes += sz
                    elif item.is_dir():
                        shutil.rmtree(item, ignore_errors=True)
                except Exception:
                    pass
        except Exception:
            pass
        _LAST_CLEANUP_TS = now
        return deleted_count, freed_bytes

    # 2. Age-based and Size-based LRU pruning
    try:
        cutoff_time = now - (max_age_days * 86400.0)
        max_bytes = max_size_mb * 1024.0 * 1024.0
        target_shrink_bytes = max_bytes * 0.75

        file_entries = []
        total_size = 0.0

        for entry in os.scandir(target_dir):
            if not entry.is_file():
                continue
            try:
                st = entry.stat()
                mtime = st.st_mtime
                size = st.st_size

                # Age eviction
                if mtime < cutoff_time:
                    try:
                        os.unlink(entry.path)
                        deleted_count += 1
                        freed_bytes += size
                        continue
                    except Exception:
                        pass

                file_entries.append((mtime, size, entry.path))
                total_size += size
            except Exception:
                continue

        # Size quota eviction (LRU oldest first)
        if total_size > max_bytes and file_entries:
            file_entries.sort(key=lambda x: x[0])  # Sort by mtime ascending
            for mtime, size, path in file_entries:
                if total_size <= target_shrink_bytes:
                    break
                try:
                    os.unlink(path)
                    deleted_count += 1
                    freed_bytes += size
                    total_size -= size
                except Exception:
                    pass

        _LAST_CLEANUP_TS = now
    except Exception:
        pass

    return deleted_count, freed_bytes
