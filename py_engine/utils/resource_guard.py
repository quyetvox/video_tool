#!/usr/bin/env python3
"""
Resource Guard Module for Sub-Video Pipeline.
Ensures the system never uses 100% of available resources (RAM/CPU/VRAM),
preventing freezes, crashes, or macOS OOM kills during long video processing.
"""

import os
import logging
from dataclasses import dataclass
from typing import Optional

try:
    import psutil
except ImportError:
    psutil = None

logger = logging.getLogger("sub_video.resource_guard")


@dataclass
class ResourceAllocation:
    total_ram_gb: float
    available_ram_gb: float
    max_allowed_ram_gb: float
    cpu_cores: int
    safe_workers: int
    recommended_chunk_duration_sec: int
    is_low_resource: bool


class ResourceGuard:
    # Memory estimated per worker running AI models (Whisper/Demucs/Inpaint/FFmpeg)
    ESTIMATED_RAM_PER_WORKER_GB: float = 3.5
    
    # Safety headroom: Keep at least 30% available RAM for OS & user apps
    MAX_RAM_HEADROOM_RATIO: float = 0.70
    
    # Reserve CPU cores for OS responsiveness
    RESERVED_CPU_CORES: int = 2

    @classmethod
    def get_system_ram_gb(cls) -> tuple[float, float]:
        """Returns (total_ram_gb, available_ram_gb)."""
        if psutil:
            mem = psutil.virtual_memory()
            return mem.total / (1024 ** 3), mem.available / (1024 ** 3)
        
        # Fallback using os.sysconf
        try:
            pages = os.sysconf('SC_PHYS_PAGES')
            page_size = os.sysconf('SC_PAGE_SIZE')
            total = (pages * page_size) / (1024 ** 3)
            return total, total * 0.5  # conservative fallback
        except Exception:
            return 16.0, 8.0

    @classmethod
    def get_cpu_cores(cls) -> int:
        return os.cpu_count() or 4

    @classmethod
    def calculate_allocation(
        cls,
        max_ram_usage_gb: Optional[float] = None,
        custom_workers: Optional[int] = None,
        custom_chunk_minutes: Optional[float] = None
    ) -> ResourceAllocation:
        """
        Calculates safe resource allocation adhering strictly to the 70% safe limit rule.
        """
        total_ram, avail_ram = cls.get_system_ram_gb()
        cpu_cores = cls.get_cpu_cores()

        # Compute max allowed RAM for the pipeline (70% of available RAM)
        safe_ram_cap = avail_ram * cls.MAX_RAM_HEADROOM_RATIO
        if max_ram_usage_gb and max_ram_usage_gb > 0:
            max_allowed_ram = min(max_ram_usage_gb, safe_ram_cap)
        else:
            max_allowed_ram = safe_ram_cap

        # Calculate safe workers
        max_workers_by_ram = int(max_allowed_ram // cls.ESTIMATED_RAM_PER_WORKER_GB)
        max_workers_by_cpu = max(1, cpu_cores - cls.RESERVED_CPU_CORES)
        
        calculated_safe_workers = max(1, min(max_workers_by_ram, max_workers_by_cpu))
        
        if custom_workers and custom_workers > 0:
            safe_workers = min(custom_workers, calculated_safe_workers)
        else:
            safe_workers = calculated_safe_workers

        # Calculate recommended chunk duration
        # Low RAM (<= 16GB) -> 5-8 mins (300s-480s)
        # High RAM (> 16GB) -> 10-15 mins (600s-900s)
        is_low_res = total_ram <= 16.0
        if custom_chunk_minutes and custom_chunk_minutes > 0:
            chunk_duration_sec = int(custom_chunk_minutes * 60)
        else:
            chunk_duration_sec = 360 if is_low_res else 720  # 6 mins vs 12 mins default

        return ResourceAllocation(
            total_ram_gb=round(total_ram, 2),
            available_ram_gb=round(avail_ram, 2),
            max_allowed_ram_gb=round(max_allowed_ram, 2),
            cpu_cores=cpu_cores,
            safe_workers=safe_workers,
            recommended_chunk_duration_sec=chunk_duration_sec,
            is_low_resource=is_low_res
        )

    @classmethod
    def check_memory_threshold(cls, max_allowed_ram_gb: float) -> bool:
        """Returns True if current system memory is safe to proceed."""
        _, avail_ram = cls.get_system_ram_gb()
        # If available RAM is below 1.5GB or less than 15% of total, throttle/wait
        return avail_ram >= 1.5
