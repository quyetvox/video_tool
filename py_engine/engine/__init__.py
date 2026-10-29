"""Sub-Video engine package. Installs legacy-name aliases (see compat.py) and path anchors on first import."""
from engine import compat as _compat
from engine import paths as _paths  # noqa: F401

_compat.install()

