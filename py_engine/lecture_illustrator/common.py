"""
Common IPC utilities and file helpers for the Lecture Illustrator engine.
"""

import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional


def emit_json(data: Dict[str, Any]):
    """Emit JSON protocol line for Flutter Desktop UI IPC."""
    print(json.dumps(data, ensure_ascii=False), flush=True)


def emit_log(level: str, message: str, step_id: str = "lecture_illustrator"):
    """Emit structured log for Flutter Desktop console."""
    emit_json({
        "type": "log",
        "level": level,
        "step_id": step_id,
        "message": message,
        "timestamp": time.time(),
    })


def emit_progress(progress: float, status: str, step_id: str = "lecture_illustrator"):
    """Emit progress update for Flutter Desktop progress indicators."""
    emit_json({
        "type": "progress",
        "step_id": step_id,
        "progress": round(progress, 3),
        "status": status,
        "timestamp": time.time(),
    })


def safe_ensure_dir(target_dir: Path, fallback_subdir: str = "lecture_illustrator") -> Path:
    """Ensure directory exists and has write permission, with sandbox fallback."""
    target = Path(target_dir).resolve()
    try:
        target.mkdir(parents=True, exist_ok=True)
        probe_file = target / f".probe_write_{os.getpid()}"
        probe_file.write_text("ok")
        probe_file.unlink(missing_ok=True)
        return target
    except (PermissionError, OSError) as e:
        home_dir = Path.home()
        fallback_dir = home_dir / ".subvideo" / fallback_subdir
        fallback_dir.mkdir(parents=True, exist_ok=True)
        emit_log("warn", f"Target dir '{target}' not writable ({e}). Using fallback: {fallback_dir}")
        return fallback_dir


def clean_json_str(raw_text: str) -> str:
    """Remove markdown codeblocks and extraneous text around JSON output."""
    raw = raw_text.strip()
    match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", raw, re.IGNORECASE)
    if match:
        return match.group(1).strip()
    return raw


def load_engine_config(context_path: Optional[Path] = None) -> Dict[str, Any]:
    """Nạp file config.yaml từ context_path (workspace, project) hoặc root project."""
    try:
        import yaml
        search_paths = []
        if context_path:
            cp = Path(context_path).resolve()
            search_paths.extend([
                cp / "config.yaml",
                cp.parent / "config.yaml",
                cp.parent.parent / "config.yaml",
                cp.parent.parent.parent / "config.yaml",
            ])
        root_dir = Path(__file__).resolve().parent.parent.parent
        search_paths.append(root_dir / "config.yaml")

        for p in search_paths:
            if p.exists() and p.is_file():
                with open(p, "r", encoding="utf-8") as f:
                    data = yaml.safe_load(f)
                    if isinstance(data, dict):
                        return data
    except Exception:
        pass
    return {}


def resolve_hardware_config(cfg: Optional[Dict[str, Any]] = None) -> tuple[int, str, List[str]]:
    """
    Tự động đọc num_workers và device từ config.yaml:
    - num_workers: số worker chạy song song (app.num_workers)
    - device: auto | mps | cuda | cpu -> chọn encoder tối ưu (h264_videotoolbox, h264_nvenc, libx264)
    """
    if cfg is None:
        cfg = load_engine_config()

    try:
        from core.concurrency import ConcurrencyManager
        workers = ConcurrencyManager.get_num_workers(cfg)
    except Exception:
        workers = int(cfg.get("app", {}).get("num_workers", 4)) if isinstance(cfg, dict) else 4

    app_cfg = cfg.get("app", {}) if isinstance(cfg, dict) else {}
    device = str(app_cfg.get("device", "auto")).strip().lower()

    sys_plat = sys.platform
    if device in ("auto", "mps") and sys_plat == "darwin":
        encoder = "h264_videotoolbox"
        enc_args = ["-b:v", "1800k", "-maxrate", "2500k", "-bufsize", "3600k", "-allow_sw", "1"]
    elif device == "cuda" or (device == "auto" and sys_plat.startswith("win")):
        encoder = "h264_nvenc"
        enc_args = ["-b:v", "1800k", "-maxrate", "2500k", "-preset", "p4", "-cq", "24"]
    elif device == "cpu":
        encoder = "libx264"
        enc_args = ["-preset", "fast", "-crf", "23", "-tune", "animation", "-threads", "0"]
    else:
        if sys_plat == "darwin":
            encoder = "h264_videotoolbox"
            enc_args = ["-b:v", "1800k", "-maxrate", "2500k", "-bufsize", "3600k", "-allow_sw", "1"]
        else:
            encoder = "libx264"
            enc_args = ["-preset", "fast", "-crf", "23", "-tune", "animation", "-threads", "0"]

    return max(1, workers), encoder, enc_args

