"""
pkg_bootstrap.py — Runtime auto-install cho các optional dependencies.

Cài đặt an toàn vào User Sandbox:
- Windows: %LOCALAPPDATA%\\.subvideo\\site-packages (hoặc %USERPROFILE%\\.subvideo\\site-packages)
- macOS / Linux: ~/.subvideo/site-packages

Giúp cài đặt thành công 100% khi ứng dụng nằm trong thư mục được bảo vệ (Program Files / Applications)
mà không yêu cầu quyền Administrator và không cần cài lại app.
"""
import importlib
import os
import subprocess
import sys
from pathlib import Path


def get_user_site_packages() -> Path:
    """Trả về thư mục site-packages sandbox của người dùng."""
    local_app = os.environ.get("LOCALAPPDATA") or os.environ.get("USERPROFILE")
    user_base = (Path(local_app) / ".subvideo") if local_app else (Path.home() / ".subvideo")
    site_dir = (user_base / "site-packages").resolve()
    try:
        site_dir.mkdir(parents=True, exist_ok=True)
    except Exception:
        fallback = (Path.home() / ".subvideo" / "site-packages").resolve()
        fallback.mkdir(parents=True, exist_ok=True)
        return fallback
    return site_dir


def _ensure_sys_path():
    """Đảm bảo thư mục user site-packages luôn nằm trong sys.path."""
    site_dir = str(get_user_site_packages())
    if site_dir not in sys.path:
        sys.path.insert(0, site_dir)


def ensure_package(import_path: str, pip_spec: str, extras: list[str] | None = None) -> bool:
    """
    Kiểm tra xem `import_path` có import được không.
    Nếu không → chạy pip install --target <user_site_packages> `pip_spec` (và `extras`) rồi retry.

    Returns:
        True nếu import thành công (hoặc sau khi install), False nếu vẫn thất bại.
    """
    _ensure_sys_path()

    # 1. Thử import nhanh trước khi tốn thời gian pip install
    try:
        _deep_import(import_path)
        return True
    except (ImportError, AttributeError):
        pass

    # 2. Cài package vào user sandbox site-packages
    target_dir = get_user_site_packages()
    pkgs = [pip_spec] + (extras or [])
    try:
        cmd = [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--target",
            str(target_dir),
            "--no-cache-dir",
            "--quiet",
        ] + pkgs
        subprocess.check_call(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return False

    # 3. Retry import sau khi cài
    importlib.invalidate_caches()
    _ensure_sys_path()
    try:
        _deep_import(import_path)
        return True
    except (ImportError, AttributeError):
        return False


def _deep_import(import_path: str) -> None:
    """Import dạng 'google.genai' dùng importlib để hỗ trợ namespace packages."""
    importlib.import_module(import_path)
