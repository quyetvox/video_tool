"""Sub-Video py_engine root package."""
import sys as _sys
from pathlib import Path as _Path

_DIR = str(_Path(__file__).resolve().parent)
if _DIR not in _sys.path:
    _sys.path.insert(0, _DIR)

import engine  # noqa: E402, F401

