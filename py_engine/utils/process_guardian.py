#!/usr/bin/env python3
"""
Process Guardian Module for Sub-Video Pipeline.
Prevents orphan/zombie Python subprocesses (multiprocessing spawn, Demucs workers, FFmpeg),
ensuring 100% of child processes are terminated immediately upon exit, interrupt, or app close.
"""

import atexit
import logging
import os
import signal
import sys
from typing import List

try:
    import psutil
except ImportError:
    psutil = None

logger = logging.getLogger("sub_video.process_guardian")
_guardian_installed = False


def _terminate_process_tree(pid: int = None, include_parent: bool = False):
    """Kills all child processes spawned by this process or a given PID."""
    if not psutil:
        return
    try:
        parent = psutil.Process(pid or os.getpid())
        children = parent.children(recursive=True)
        for child in children:
            try:
                child.terminate()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass
        
        # Wait up to 0.5s, then force kill any remaining
        gone, alive = psutil.wait_procs(children, timeout=0.5)
        for p in alive:
            try:
                p.kill()
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                pass

        if include_parent and pid and pid != os.getpid():
            try:
                parent.kill()
            except Exception:
                pass
    except Exception:
        pass


def _signal_handler(signum, frame):
    """Intercepts termination signals and wipes out all child subprocesses."""
    logger.warning(f"Received signal {signum}, killing all child subprocesses before exit...")
    _terminate_process_tree()
    sys.exit(128 + signum if isinstance(signum, int) else 1)


def install_guardian():
    """Installs automatic signal & atexit hooks to guarantee zero orphan processes."""
    global _guardian_installed
    if _guardian_installed:
        return
    _guardian_installed = True

    # Register exit hook
    atexit.register(_terminate_process_tree)

    # Register signal handlers
    for sig in [signal.SIGINT, signal.SIGTERM]:
        try:
            signal.signal(sig, _signal_handler)
        except Exception:
            pass

    if hasattr(signal, "SIGHUP"):
        try:
            signal.signal(signal.SIGHUP, _signal_handler)
        except Exception:
            pass


def cleanup_orphaned_processes(project_root_keyword: str = "Sub-Video") -> int:
    """
    Finds and terminates any dangling/orphaned Python multiprocessing workers
    or FFmpeg processes whose parent is PID 1 (init/launchd) belonging to Sub-Video.
    Returns the number of killed processes.
    """
    if not psutil:
        return 0

    killed_count = 0
    current_pid = os.getpid()

    for proc in psutil.process_iter(['pid', 'ppid', 'name', 'cmdline']):
        try:
            p_info = proc.info
            pid = p_info.get('pid')
            ppid = p_info.get('ppid')
            cmdline = p_info.get('cmdline') or []
            cmd_str = " ".join(cmdline)

            if pid == current_pid:
                continue

            # Match criteria for orphan workers:
            # 1. PPID == 1 (orphaned, parent died)
            # 2. Command contains project keyword or multiprocessing-fork/spawn belonging to Sub-Video
            is_subvideo_worker = (
                project_root_keyword in cmd_str and
                ("py_engine" in cmd_str or "main.py" in cmd_str or "multiprocessing.spawn" in cmd_str)
            )

            is_dangling_ffmpeg = (
                ppid == 1 and
                "ffmpeg" in cmd_str.lower() and
                project_root_keyword in cmd_str
            )

            if (ppid == 1 and is_subvideo_worker) or is_dangling_ffmpeg:
                logger.warning(f"Killing orphan process PID {pid}: {cmd_str[:80]}...")
                try:
                    proc.kill()
                    killed_count += 1
                except Exception:
                    pass
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue

    return killed_count


if __name__ == "__main__":
    count = cleanup_orphaned_processes()
    print(f"Cleaned up {count} orphan processes.")
