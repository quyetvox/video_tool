import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import List, Tuple, Optional, Dict, Any

from utils.ffmpeg_utils import FFmpegUtils
from utils.trimmer_utils import get_unique_trim_path, parse_time_str


def calculate_keep_ranges(total_duration: float, remove_ranges: List[Tuple[float, float]]) -> List[Tuple[float, float]]:
    """
    Given a total video duration and a list of (start, end) tuples to remove,
    calculate the complementary list of (start, end) tuples to keep.
    """
    if not remove_ranges:
        return [(0.0, total_duration)]

    # Sort and merge overlapping remove ranges
    sorted_removes = sorted(remove_ranges, key=lambda x: x[0])
    merged_removes = []
    for r in sorted_removes:
        start, end = max(0.0, r[0]), min(total_duration, r[1])
        if start >= end:
            continue
        if not merged_removes:
            merged_removes.append([start, end])
        else:
            prev = merged_removes[-1]
            if start <= prev[1]:
                prev[1] = max(prev[1], end)
            else:
                merged_removes.append([start, end])

    keep_ranges = []
    curr_pos = 0.0

    for rem_start, rem_end in merged_removes:
        if rem_start > curr_pos + 0.1:  # ignore segments < 0.1s
            keep_ranges.append((curr_pos, rem_start))
        curr_pos = rem_end

    if curr_pos + 0.1 < total_duration:
        keep_ranges.append((curr_pos, total_duration))

    return keep_ranges


def concat_videos(input_paths: List[Path], output_path: Optional[Path] = None, bitrate: str = "4.0M") -> Path:
    """
    Concatenate multiple video files into a single video output.
    Uses fast stream copy if all inputs share matching specs, or scale+pad re-encode if specs differ.
    """
    if not input_paths:
        raise ValueError("No input video files provided for concatenation.")

    resolved_inputs = [Path(p).resolve() for p in input_paths]
    for p in resolved_inputs:
        if not p.exists():
            raise FileNotFoundError(f"Input video not found: {p}")

    if output_path is None:
        first_input = resolved_inputs[0]
        output_path = get_unique_trim_path(first_input, str(first_input.parent / f"{first_input.stem}_merged.mp4"))
    else:
        output_path = Path(output_path).resolve()

    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Use temporary export file if output_path is one of the input files
    is_same_file = any(output_path == p for p in resolved_inputs)
    actual_export_path = output_path.parent / f".tmp_{output_path.name}" if is_same_file else output_path

    if len(resolved_inputs) == 1:
        if not is_same_file:
            shutil.copy2(resolved_inputs[0], output_path)
        return output_path

    # Probe all videos to check matching dimensions & codecs
    probes = [FFmpegUtils.probe(p) for p in resolved_inputs]
    
    def get_v_info(data):
        v = next((s for s in data.get("streams", []) if s.get("codec_type") == "video"), {})
        return (v.get("codec_name"), int(v.get("width", 0)), int(v.get("height", 0)), v.get("r_frame_rate"))

    specs = [get_v_info(p) for p in probes]
    all_matching = len(set(specs)) == 1

    if all_matching:
        # Fast Stream Copy Concat via concat demuxer
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
            list_file = Path(f.name)
            for p in resolved_inputs:
                f.write(f"file '{str(p).replace(chr(92), '/')}'\n")

        try:
            cmd = [
                "ffmpeg", "-y",
                "-f", "concat",
                "-safe", "0",
                "-i", str(list_file),
                "-c", "copy",
                str(actual_export_path)
            ]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0 and actual_export_path.exists() and actual_export_path.stat().st_size > 0:
                list_file.unlink(missing_ok=True)
                if is_same_file:
                    shutil.move(actual_export_path, output_path)
                return output_path
        except Exception:
            pass
        finally:
            list_file.unlink(missing_ok=True)

    # Re-encode Concat with Scale + Pad Letterbox & VideoToolbox Hardware Acceleration
    target_w = specs[0][1] or 1080
    target_h = specs[0][2] or 1920
    target_w = target_w & ~1
    target_h = target_h & ~1

    inputs = []
    filters = []

    for idx, p in enumerate(resolved_inputs):
        inputs.extend(["-i", str(p)])
        v_filter = (
            f"[{idx}:v]scale={target_w}:{target_h}:force_original_aspect_ratio=decrease,"
            f"pad={target_w}:{target_h}:(ow-ih)/2:(oh-ih)/2:black,setsar=1,format=nv12[v{idx}];"
        )
        a_filter = f"[{idx}:a]aresample=44100[a{idx}];"
        filters.append(v_filter + a_filter)

    concat_inputs = "".join(f"[v{i}][a{i}]" for i in range(len(resolved_inputs)))
    concat_filter = f"{concat_inputs}concat=n={len(resolved_inputs)}:v=1:a=1[vout][aout]"
    filters.append(concat_filter)

    filter_complex = "".join(filters)

    cmd_hw = [
        "ffmpeg", "-y"
    ] + inputs + [
        "-filter_complex", filter_complex,
        "-map", "[vout]",
        "-map", "[aout]",
        "-c:v", "h264_videotoolbox", "-b:v", str(bitrate),
        "-c:a", "aac", "-b:a", "192k",
        str(actual_export_path)
    ]

    res = subprocess.run(cmd_hw, capture_output=True, text=True)
    if res.returncode != 0 or not actual_export_path.exists() or actual_export_path.stat().st_size == 0:
        cmd_sw = [
            "ffmpeg", "-y"
        ] + inputs + [
            "-filter_complex", filter_complex,
            "-map", "[vout]",
            "-map", "[aout]",
            "-c:v", "libx264", "-preset", "ultrafast", "-b:v", str(bitrate),
            "-c:a", "aac", "-b:a", "192k",
            str(actual_export_path)
        ]
        subprocess.run(cmd_sw, capture_output=True, check=True)

    if is_same_file:
        shutil.move(actual_export_path, output_path)

    return output_path


def remove_video_ranges(
    input_path: Path,
    remove_ranges: List[Tuple[float, float]],
    output_path: Optional[Path] = None,
    bitrate: str = "4.0M"
) -> Path:
    """
    Remove specified time ranges from a single video and stitch the remaining clean segments together.
    """
    input_path = Path(input_path).resolve()
    if not input_path.exists():
        raise FileNotFoundError(f"Input video not found: {input_path}")

    probe_data = FFmpegUtils.probe(input_path)
    total_duration = float(probe_data.get("format", {}).get("duration", 0))
    if total_duration <= 0:
        raise ValueError(f"Could not determine video duration for: {input_path}")

    has_audio = any(s.get("codec_type") == "audio" for s in probe_data.get("streams", []))

    keep_ranges = calculate_keep_ranges(total_duration, remove_ranges)

    if not keep_ranges:
        raise ValueError("All video content was marked for removal. Nothing left to keep.")

    target_output = Path(output_path).resolve() if output_path else get_unique_trim_path(input_path, str(input_path.parent / f"{input_path.stem}_cut_clean.mp4"))
    target_output.parent.mkdir(parents=True, exist_ok=True)

    # Temporary file output if overwriting the input video file directly
    is_same_file = (target_output == input_path)
    actual_export_path = target_output.parent / f".tmp_{target_output.name}" if is_same_file else target_output

    # If only 1 keep range spanning the whole video, copy or simple trim
    if len(keep_ranges) == 1:
        k_start, k_end = keep_ranges[0]
        if k_start <= 0.1 and k_end >= total_duration - 0.1:
            if not is_same_file:
                shutil.copy2(input_path, target_output)
            return target_output
        FFmpegUtils.trim_video(input_path, actual_export_path, start_sec=k_start, end_sec=k_end, accurate=True)
        if is_same_file:
            shutil.move(actual_export_path, target_output)
        return target_output

    # Multiple keep ranges -> build FFmpeg trim & concat filtergraph
    filters = []
    concat_parts = []

    for idx, (k_start, k_end) in enumerate(keep_ranges):
        v_tr = f"[0:v]trim=start={k_start:.3f}:end={k_end:.3f},setpts=PTS-STARTPTS,format=nv12[v{idx}];"
        filters.append(v_tr)
        if has_audio:
            a_tr = f"[0:a]atrim=start={k_start:.3f}:end={k_end:.3f},asetpts=PTS-STARTPTS[a{idx}];"
            filters.append(a_tr)
            concat_parts.append(f"[v{idx}][a{idx}]")
        else:
            concat_parts.append(f"[v{idx}]")

    a_flag = "1" if has_audio else "0"
    concat_str = f"{''.join(concat_parts)}concat=n={len(keep_ranges)}:v=1:a={a_flag}[vout]" + ("[aout]" if has_audio else "")
    filters.append(concat_str)

    filter_complex = "".join(filters)

    cmd_hw = ["ffmpeg", "-y", "-i", str(input_path), "-filter_complex", filter_complex, "-map", "[vout]"]
    if has_audio:
        cmd_hw.extend(["-map", "[aout]"])
    cmd_hw.extend(["-c:v", "h264_videotoolbox", "-b:v", str(bitrate)])
    if has_audio:
        cmd_hw.extend(["-c:a", "aac", "-b:a", "192k"])
    cmd_hw.append(str(actual_export_path))

    res = subprocess.run(cmd_hw, capture_output=True, text=True)
    if res.returncode != 0 or not actual_export_path.exists() or actual_export_path.stat().st_size == 0:
        cmd_sw = ["ffmpeg", "-y", "-i", str(input_path), "-filter_complex", filter_complex, "-map", "[vout]"]
        if has_audio:
            cmd_sw.extend(["-map", "[aout]"])
        cmd_sw.extend(["-c:v", "libx264", "-preset", "ultrafast", "-b:v", str(bitrate)])
        if has_audio:
            cmd_sw.extend(["-c:a", "aac", "-b:a", "192k"])
        cmd_sw.append(str(actual_export_path))
        res_sw = subprocess.run(cmd_sw, capture_output=True, text=True)
        if res_sw.returncode != 0:
            raise RuntimeError(f"FFmpeg multi-cut failed:\n{res_sw.stderr}")

    if is_same_file:
        shutil.move(actual_export_path, target_output)

    return target_output
