"""Single anchor for filesystem locations (replaces depth-dependent Path(__file__).parent chains)."""
import os
import sys
from pathlib import Path

ENGINE_DIR = Path(__file__).resolve().parent.parent  # .../py_engine
ROOT_DIR = ENGINE_DIR.parent

if str(ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(ENGINE_DIR))

_cur_pp = os.environ.get("PYTHONPATH", "")
_pp_parts = [p for p in _cur_pp.split(os.pathsep) if p] if _cur_pp else []
if str(ENGINE_DIR) not in _pp_parts:
    os.environ["PYTHONPATH"] = os.pathsep.join([str(ENGINE_DIR)] + _pp_parts)

