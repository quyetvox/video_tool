"""Pytest bootstrap: ensures py_engine is on sys.path and engine.compat is installed."""
import sys
from pathlib import Path

_PY_ENGINE_DIR = Path(__file__).resolve().parent.parent
if str(_PY_ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(_PY_ENGINE_DIR))

import engine  # noqa: E402, F401

