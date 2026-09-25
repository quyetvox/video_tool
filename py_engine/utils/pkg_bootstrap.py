"""
pkg_bootstrap.py — Runtime auto-install cho các optional dependencies.

Dùng khi package không được bundle sẵn trong embedded Python (Windows),
giúp user cũ không cần cài lại app để dùng được tính năng Google Cloud AI.
"""
import sys
import subprocess


def ensure_package(import_path: str, pip_spec: str, extras: list[str] | None = None) -> bool:
    """
    Kiểm tra xem `import_path` có import được không.
    Nếu không → chạy pip install `pip_spec` (và `extras`) rồi retry.

    Returns:
        True nếu import thành công (hoặc sau khi install), False nếu vẫn thất bại.
    """
    # Thử import nhanh trước khi tốn thời gian pip install
    try:
        _deep_import(import_path)
        return True
    except (ImportError, AttributeError):
        pass

    # Cài package
    pkgs = [pip_spec] + (extras or [])
    try:
        subprocess.check_call(
            [sys.executable, "-m", "pip", "install", "--quiet", "--no-cache-dir"] + pkgs,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return False

    # Retry import sau khi cài
    import importlib
    importlib.invalidate_caches()
    try:
        _deep_import(import_path)
        return True
    except (ImportError, AttributeError):
        return False


def _deep_import(import_path: str) -> None:
    """Import dạng 'google.genai' dùng importlib để hỗ trợ namespace packages."""
    import importlib
    importlib.import_module(import_path)
