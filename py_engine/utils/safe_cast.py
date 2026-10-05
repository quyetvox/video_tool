"""
safe_cast.py — Cross-platform safe numeric conversion utilities.

Prevents ValueError crash when config values are 'auto', 'none', '', or None.
Used across all pipeline steps and plugins that read numeric config keys.
"""

_AUTO_STRINGS = {"auto", "none", "", "null", "0auto"}


def safe_int(val, default: int) -> int:
    """Convert val to int, returning default if val is None, 'auto', or non-numeric."""
    if val is None:
        return default
    if str(val).strip().lower() in _AUTO_STRINGS:
        return default
    try:
        return int(float(str(val).strip()))
    except (ValueError, TypeError):
        return default


def safe_float(val, default: float) -> float:
    """Convert val to float, returning default if val is None, 'auto', or non-numeric."""
    if val is None:
        return default
    if str(val).strip().lower() in _AUTO_STRINGS:
        return default
    try:
        return float(str(val).strip())
    except (ValueError, TypeError):
        return default
