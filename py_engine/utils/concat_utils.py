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


def check_video_compatibility(input_paths: List[Path]) -> Dict[str, Any]:
    """
    Probe and compare multiple video files to check if they are 100% compatible for lossless stream copy.
    Returns a dictionary with compatibility status, differences list, and per-video details.
    """
    if not input_paths:
        return {"compatible": True, "diffs": [], "videos": []}

    resolved_inputs = [Path(p).resolve() for p in input_paths]
    for p in resolved_inputs:
        if not p.exists():
            raise FileNotFoundError(f"Input video not found: {p}")

    video_details = []
    for p in resolved_inputs:
        probe = FFmpegUtils.probe(p)
        v_stream = next((s for s in probe.get("streams", []) if s.get("codec_type") == "video"), {})
        a_stream = next((s for s in probe.get("streams", []) if s.get("codec_type") == "audio"), {})

        w = int(v_stream.get("width", 0))
        h = int(v_stream.get("height", 0))
        v_codec = v_stream.get("codec_name", "unknown")
        pix_fmt = v_stream.get("pix_fmt", "unknown")
        
        # Calculate fps
        r_fps_str = v_stream.get("r_frame_rate", "30/1")
        try:
            if "/" in r_fps_str:
                num, den = r_fps_str.split("/")
                fps_val = round(float(num) / max(1, float(den)), 2)
            else:
                fps_val = round(float(r_fps_str), 2)
        except Exception:
            fps_val = 30.0

        # Audio stream info
        has_audio = bool(a_stream)
        a_codec = a_stream.get("codec_name", "none") if has_audio else "none"
        a_sr = int(a_stream.get("sample_rate", 0)) if has_audio else 0
        a_channels = int(a_stream.get("channels", 0)) if has_audio else 0

        dur = float(probe.get("format", {}).get("duration", 0) or v_stream.get("duration", 0) or 0)

        aspect = "9:16" if (h > w and w > 0) else ("16:9" if (w > h and h > 0) else "1:1")

        video_details.append({
            "path": str(p),
            "filename": p.name,
            "width": w,
            "height": h,
            "resolution": f"{w}x{h}",
            "aspect_ratio": aspect,
            "video_codec": v_codec,
            "pix_fmt": pix_fmt,
            "fps": fps_val,
            "has_audio": has_audio,
            "audio_codec": a_codec,
            "audio_sample_rate": a_sr,
            "audio_channels": a_channels,
            "duration": dur,
            "size_bytes": p.stat().st_size if p.exists() else 0
        })

    if len(video_details) <= 1:
        return {"compatible": True, "diffs": [], "videos": video_details, "can_stream_copy": True}

    diffs = []
    resolutions = set(v["resolution"] for v in video_details)
    if len(resolutions) > 1:
        diffs.append(f"Độ phân giải khác nhau: {', '.join(resolutions)}")

    codecs = set(v["video_codec"] for v in video_details)
    if len(codecs) > 1:
        diffs.append(f"Codec video khác nhau: {', '.join(codecs)}")

    fps_set = set(v["fps"] for v in video_details)
    if len(fps_set) > 1:
        diffs.append(f"Tốc độ khung hình (FPS) khác nhau: {', '.join(str(f) for f in fps_set)} fps")

    audio_status = set(v["has_audio"] for v in video_details)
    if len(audio_status) > 1:
        diffs.append("Một số video có tiếng và một số video không có âm thanh")
    elif True in audio_status:
        a_srs = set(v["audio_sample_rate"] for v in video_details if v["has_audio"])
        if len(a_srs) > 1:
            diffs.append(f"Tần số lấy mẫu âm thanh khác nhau: {', '.join(str(s) for s in a_srs)} Hz")
        a_codecs = set(v["audio_codec"] for v in video_details if v["has_audio"])
        if len(a_codecs) > 1:
            diffs.append(f"Codec âm thanh khác nhau: {', '.join(a_codecs)}")

    is_compat = len(diffs) == 0

    return {
        "compatible": is_compat,
        "can_stream_copy": is_compat,
        "diffs": diffs,
        "videos": video_details
    }


def concat_videos(
    input_paths: List[Path],
    output_path: Optional[Path] = None,
    bitrate: str = "4.0M",
    auto_normalize: bool = False
) -> Path:
    """
    Concatenate multiple video files into a single video output.
    - If all inputs are 100% compatible: Uses ultra-fast stream copy via concat demuxer (<0.5s).
    - If inputs differ:
      - If auto_normalize is False: Raises ValueError with compatibility differences.
      - If auto_normalize is True: Re-encodes with Apple Silicon hardware acceleration,
        standardizing resolution (scale+pad), FPS (30fps), and Audio (44.1kHz stereo with silent stream generator).
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

    # Check compatibility across all video inputs
    compat_info = check_video_compatibility(resolved_inputs)

    if compat_info["compatible"]:
        # 🚀 Mode 1: Fast Stream Copy Concat via concat demuxer (<0.5s Lossless)
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

    # If not compatible and user hasn't explicitly allowed Auto-Normalize
    if not auto_normalize and not compat_info["compatible"]:
        diffs_str = "; ".join(compat_info["diffs"])
        raise ValueError(f"Các video không cùng định dạng ({diffs_str}). Vui lòng bật Auto-Normalize để chuẩn hóa và ghép video.")

    # 🎯 Mode 2: Hardware-Accelerated Auto-Normalize Concat (Apple Silicon VideoToolbox)
    v_details = compat_info["videos"]
    # Determine target resolution (max width and height or first video resolution)
    target_w = v_details[0]["width"] or 1080
    target_h = v_details[0]["height"] or 1920
    target_w = target_w & ~1
    target_h = target_h & ~1

    inputs = []
    filters = []

    for idx, (p, v_info) in enumerate(zip(resolved_inputs, v_details)):
        inputs.extend(["-i", str(p)])
        
        # Video filter: Scale with aspect ratio preservation + pad with centered (ow-iw)/2:(oh-ih)/2 + fixed 30fps
        v_filter = (
            f"[{idx}:v]scale={target_w}:{target_h}:force_original_aspect_ratio=decrease,"
            f"pad={target_w}:{target_h}:(ow-iw)/2:(oh-ih)/2:black,setsar=1,fps=30,format=nv12[v{idx}];"
        )

        # Audio filter: Resample to 44.1kHz Stereo or generate silent audio if video is mute
        dur = max(0.1, v_info.get("duration", 1.0))
        if v_info.get("has_audio"):
            a_filter = f"[{idx}:a]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[a{idx}];"
        else:
            # Generate silent stereo stream matching segment duration
            a_filter = f"anullsrc=r=44100:cl=stereo,atrim=0:{dur:.3f}[a{idx}];"

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
        # Software fallback via libx264 ultrafast
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
    bitrate: str = "4.0M",
    accurate: bool = False
) -> Path:
    """
    Remove specified time ranges from a single video and stitch the remaining clean segments together.
    - accurate=False (Default / Giải pháp 1): Stream copy các đoạn sạch + concat demuxer (<0.3s siêu tốc).
    - accurate=True (Giải pháp 2): Fast Input Seeking + Encode phần cứng VideoToolbox (chính xác từng frame).
    """
    input_path = Path(input_path).resolve()
    if not input_path.exists():
        raise FileNotFoundError(f"Input video not found: {input_path}")

    probe_data = FFmpegUtils.probe(input_path)
    total_duration = float(probe_data.get("format", {}).get("duration", 0))
    if total_duration <= 0:
        raise ValueError(f"Could not determine video duration for: {input_path}")

    keep_ranges = calculate_keep_ranges(total_duration, remove_ranges)

    if not keep_ranges:
        raise ValueError("All video content was marked for removal. Nothing left to keep.")

    target_output = Path(output_path).resolve() if output_path else get_unique_trim_path(input_path, str(input_path.parent / f"{input_path.stem}_cut_clean.mp4"))
    target_output.parent.mkdir(parents=True, exist_ok=True)

    # Temporary file output if overwriting the input video file directly
    is_same_file = (target_output == input_path)
    actual_export_path = target_output.parent / f".tmp_{target_output.name}" if is_same_file else target_output

    expected_keep_duration = sum(k_end - k_start for k_start, k_end in keep_ranges)

    # If only 1 keep range spanning the whole video, copy or simple trim
    if len(keep_ranges) == 1:
        k_start, k_end = keep_ranges[0]
        if k_start <= 0.1 and k_end >= total_duration - 0.1:
            if not is_same_file:
                shutil.copy2(input_path, target_output)
            return target_output
        FFmpegUtils.trim_video(input_path, actual_export_path, start_sec=k_start, end_sec=k_end, accurate=accurate)
        if is_same_file:
            shutil.move(actual_export_path, target_output)
        return target_output

    # Mode 1: Ultra-fast Stream Copy Concat (Giải pháp 1)
    if not accurate:
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                chunk_files = []
                for idx, (k_start, k_end) in enumerate(keep_ranges):
                    dur = k_end - k_start
                    chunk_p = os.path.join(temp_dir, f"chunk_{idx:03d}.mp4")
                    chunk_files.append(chunk_p)
                    # Fast seek before -i with -t duration and make_zero timestamp
                    cmd_cut = [
                        "ffmpeg", "-y",
                        "-ss", f"{k_start:.3f}",
                        "-i", str(input_path),
                        "-t", f"{dur:.3f}",
                        "-c", "copy",
                        "-avoid_negative_ts", "make_zero",
                        chunk_p
                    ]
                    subprocess.run(cmd_cut, capture_output=True, check=True)

                list_file = os.path.join(temp_dir, "chunks.txt")
                with open(list_file, "w", encoding="utf-8") as f:
                    for cf in chunk_files:
                        f.write(f"file '{cf}'\n")

                cmd_concat = [
                    "ffmpeg", "-y",
                    "-f", "concat",
                    "-safe", "0",
                    "-i", list_file,
                    "-c", "copy",
                    str(actual_export_path)
                ]
                res = subprocess.run(cmd_concat, capture_output=True)
                if res.returncode == 0 and actual_export_path.exists() and actual_export_path.stat().st_size > 0:
                    probe_out = FFmpegUtils.probe(actual_export_path)
                    out_dur = float(probe_out.get("format", {}).get("duration", 0))
                    # If stream copy produced accurate cut duration within 0.5s tolerance
                    if abs(out_dur - expected_keep_duration) <= 0.5:
                        if is_same_file:
                            shutil.move(actual_export_path, target_output)
                        return target_output
        except Exception:
            # If stream copy encounters codec/keyframe issues, seamlessly fallback to Mode 2
            pass

    # Mode 2: Hardware-Accelerated Fast-Seek Frame Accurate (Tier 1 HW -> Tier 2 CPU libx264)
    hw_encoder = FFmpegUtils.get_hardware_h264_encoder()
    with tempfile.TemporaryDirectory() as temp_dir:
        chunk_files = []
        for idx, (k_start, k_end) in enumerate(keep_ranges):
            dur = k_end - k_start
            chunk_p = os.path.join(temp_dir, f"chunk_{idx:03d}.mp4")
            chunk_files.append(chunk_p)
            cmd_chunk = [
                "ffmpeg", "-y",
                "-ss", f"{k_start:.3f}",
                "-i", str(input_path),
                "-t", f"{dur:.3f}",
                "-c:v", hw_encoder, "-b:v", str(bitrate), "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-b:a", "192k",
                chunk_p
            ]
            res_chunk = subprocess.run(cmd_chunk, capture_output=True)
            if res_chunk.returncode != 0 or not os.path.exists(chunk_p):
                cmd_sw = [
                    "ffmpeg", "-y",
                    "-ss", f"{k_start:.3f}",
                    "-i", str(input_path),
                    "-t", f"{dur:.3f}",
                    "-c:v", "libx264", "-preset", "ultrafast", "-b:v", str(bitrate), "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "192k",
                    chunk_p
                ]
                subprocess.run(cmd_sw, capture_output=True, check=True)

        list_file = os.path.join(temp_dir, "chunks.txt")
        with open(list_file, "w", encoding="utf-8") as f:
            for cf in chunk_files:
                f.write(f"file '{cf}'\n")

        cmd_concat = [
            "ffmpeg", "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", list_file,
            "-c", "copy",
            str(actual_export_path)
        ]
        res = subprocess.run(cmd_concat, capture_output=True)
        if res.returncode == 0 and actual_export_path.exists() and actual_export_path.stat().st_size > 0:
            if is_same_file:
                shutil.move(actual_export_path, target_output)
            return target_output

    if is_same_file:
        shutil.move(actual_export_path, target_output)

    return target_output
