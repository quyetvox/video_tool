import re
from pathlib import Path
from typing import Optional, Union


def parse_time_str(val: Union[str, float, int, None]) -> Optional[float]:
    """
    Parse a time representation (seconds float/int or string 'mm:ss', 'hh:mm:ss', 'ss')
    into total seconds as float. Returns None if val is None or empty.
    """
    if val is None:
        return None

    if isinstance(val, (int, float)):
        return float(val) if val >= 0 else None

    s = str(val).strip()
    if not s:
        return None

    # Handles hh:mm:ss.ss or mm:ss.ss or ss.ss
    if ":" in s:
        parts = s.split(":")
        try:
            if len(parts) == 2:
                mins, secs = float(parts[0]), float(parts[1])
                return mins * 60.0 + secs
            elif len(parts) == 3:
                hrs, mins, secs = float(parts[0]), float(parts[1]), float(parts[2])
                return hrs * 3600.0 + mins * 60.0 + secs
        except ValueError:
            return None

    try:
        f = float(s)
        return f if f >= 0 else None
    except ValueError:
        return None


def format_seconds_to_time(seconds: Optional[float], show_hours: bool = False) -> str:
    """
    Format total seconds float into 'mm:ss' or 'hh:mm:ss' string representation.
    """
    if seconds is None or seconds < 0:
        return "00:00"

    total_secs = int(seconds)
    millis = int(round((seconds - total_secs) * 10))

    hrs = total_secs // 3600
    mins = (total_secs % 3600) // 60
    secs = total_secs % 60

    if show_hours or hrs > 0:
        base = f"{hrs:02d}:{mins:02d}:{secs:02d}"
    else:
        base = f"{mins:02d}:{secs:02d}"

    if millis > 0:
        base += f".{millis}"
    return base


def get_unique_trim_path(input_path: Path, custom_output: Optional[str] = None) -> Path:
    """
    Determine a non-colliding output Path for trimmed video.
    Auto-increments index (_cut_1, _cut_2, ...) to prevent overwriting existing files.
    """
    input_path = Path(input_path).resolve()
    parent_dir = input_path.parent
    suffix = input_path.suffix.lower() or ".mp4"

    if custom_output and str(custom_output).strip():
        out_candidate = Path(custom_output).resolve()
        if not out_candidate.exists():
            return out_candidate
        
        # If custom output exists, find next increment before suffix
        stem = out_candidate.stem
        parent_dir = out_candidate.parent
        suffix = out_candidate.suffix or suffix
    else:
        stem = input_path.stem

    # Pattern match: stem_cut_N.ext or stem_cut.ext
    # Check all existing files in target directory that match stem_cut*
    existing_files = list(parent_dir.glob(f"{stem}_cut*{suffix}"))
    
    if not existing_files and not (parent_dir / f"{stem}_cut{suffix}").exists():
        # Check if basic _cut_1 is free
        candidate = parent_dir / f"{stem}_cut_1{suffix}"
        if not candidate.exists():
            return candidate

    # Find highest integer N in stem_cut_N
    max_n = 0
    pattern = re.compile(rf"^{re.escape(stem)}_cut(?:_(\d+))?{re.escape(suffix)}$", re.IGNORECASE)

    for f in parent_dir.iterdir():
        if f.is_file():
            m = pattern.match(f.name)
            if m:
                idx_str = m.group(1)
                if idx_str:
                    idx = int(idx_str)
                    if idx > max_n:
                        max_n = idx
                else:
                    # Match stem_cut.ext (equivalent to 0)
                    if max_n < 1:
                        max_n = 1

    next_n = max_n + 1
    return parent_dir / f"{stem}_cut_{next_n}{suffix}"
