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


def resolve_project_subfolder(input_path: Path, subfolder: str = "cut") -> Path:
    """
    Finds the appropriate destination subfolder (cut, merge, output) within the project.
    If input is in assets/<project>/src, returns assets/<project>/<subfolder>.
    Otherwise returns input_path.parent.
    """
    input_path = Path(input_path).resolve()
    parent = input_path.parent

    # Check if parent is inside a project directory (e.g. assets/<project>/src)
    if parent.name in ("src", "cut", "merge", "workspace", "output", "downloaded"):
        project_dir = parent.parent
        if project_dir.parent.name == "assets" or (project_dir / "src").exists():
            target = project_dir / subfolder
            target.mkdir(parents=True, exist_ok=True)
            return target

    return parent


def get_unique_trim_path(input_path: Path, custom_output: Optional[str] = None, tag: str = "cut", target_folder: str = "cut") -> Path:
    """
    Determine a non-colliding output Path for trimmed/cut video.
    Defaults to assets/<project>/cut/<stem>_<tag>_N.mp4 when input is in project directory.
    Auto-increments index (_cut_1, _cut_2, ...) to prevent overwriting existing files.
    """
    input_path = Path(input_path).resolve()
    suffix = input_path.suffix.lower() or ".mp4"

    if custom_output and str(custom_output).strip():
        out_candidate = Path(custom_output).resolve()
        if not out_candidate.exists():
            out_candidate.parent.mkdir(parents=True, exist_ok=True)
            return out_candidate
        stem = out_candidate.stem
        parent_dir = out_candidate.parent
        suffix = out_candidate.suffix or suffix
    else:
        stem = input_path.stem
        parent_dir = resolve_project_subfolder(input_path, target_folder)

    # Pattern match: stem_<tag>_N.ext or stem_<tag>.ext
    existing_files = list(parent_dir.glob(f"{stem}_{tag}*{suffix}"))
    
    if not existing_files and not (parent_dir / f"{stem}_{tag}{suffix}").exists():
        candidate = parent_dir / f"{stem}_{tag}_1{suffix}"
        if not candidate.exists():
            return candidate

    max_n = 0
    pattern = re.compile(rf"^{re.escape(stem)}_{re.escape(tag)}(?:_(\d+))?{re.escape(suffix)}$", re.IGNORECASE)

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
                    if max_n < 1:
                        max_n = 1

    next_n = max_n + 1
    return parent_dir / f"{stem}_{tag}_{next_n}{suffix}"


def get_unique_concat_path(input_path: Path, custom_output: Optional[str] = None) -> Path:
    """
    Determine a non-colliding output Path for merged video.
    Defaults to assets/<project>/merge/<stem>_merged.mp4.
    """
    return get_unique_trim_path(input_path, custom_output=custom_output, tag="merged", target_folder="merge")
