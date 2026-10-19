import os
from typing import Any, Dict, Optional


class ConcurrencyManager:
    """
    Centralized Hardware Concurrency & Resource Manager for Sub-Video.
    Applies unified worker limits to PyTorch, OpenMP, macOS Accelerate, ProcessPools, ThreadPools, and FFmpeg.
    """

    @staticmethod
    def get_num_workers(config: Any, override_key: Optional[str] = None) -> int:
        """
        Resolves global workers from config['num_workers'] / config['app']['num_workers'].
        If 'auto' or '0', calculates balanced even core allocation: clamp(cpu_count // 2, 2, 32).
        """
        if config is None:
            config = {}
        elif hasattr(config, "to_dict") and callable(config.to_dict):
            config = config.to_dict()
        elif not isinstance(config, dict):
            try:
                config = dict(config)
            except Exception:
                config = {}

        val = None
        if override_key and isinstance(config, dict) and override_key in config:
            val = config.get(override_key)

        if val is None and isinstance(config, dict):
            val = config.get("num_workers")

        if val is None and isinstance(config, dict):
            app_cfg = config.get("app")
            if isinstance(app_cfg, dict):
                val = app_cfg.get("num_workers")

        if val is None and isinstance(config, dict):
            # Fallback to legacy ocr/tts keys if present
            val = config.get("ocr_num_workers") or config.get("tts_num_workers")

        if val is None or str(val).strip().lower() in ["auto", "0"]:
            cpu_count = os.cpu_count() or 4
            raw_half = cpu_count // 2
            even_cores = raw_half if raw_half % 2 == 0 else max(2, raw_half - 1)
            return max(2, min(even_cores, 32))

        try:
            return max(1, int(val))
        except (ValueError, TypeError):
            return 4

    @staticmethod
    def configure_runtime(config: Dict[str, Any]) -> int:
        """
        Applies worker concurrency constraints across the Python runtime and C/C++ backend libraries.
        """
        workers = ConcurrencyManager.get_num_workers(config)
        str_w = str(workers)

        # 1. C / OpenMP / BLAS / Apple Accelerate Thread Limits
        os.environ["OMP_NUM_THREADS"] = str_w
        os.environ["MKL_NUM_THREADS"] = str_w
        os.environ["OPENBLAS_NUM_THREADS"] = str_w
        os.environ["VECLIB_MAXIMUM_THREADS"] = str_w
        os.environ["NUMEXPR_NUM_THREADS"] = str_w

        # 2. PyTorch Thread Limits
        try:
            import torch
            torch.set_num_threads(workers)
            if hasattr(torch, "set_num_interop_threads"):
                torch.set_num_interop_threads(max(1, min(workers // 2, 4)))
        except Exception:
            pass

        print(f"[ConcurrencyManager] Global hardware concurrency set to {workers} workers.", flush=True)
        return workers
