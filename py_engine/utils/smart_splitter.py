#!/usr/bin/env python3
"""
Smart Triple-Lock Video Splitter Module.
Splits long videos into seamless, keyframe-aligned, silence-aware chunks
using FFmpeg copy mode (-c copy) for 0-second re-encode and zero loss.
"""

import json
import logging
import math
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

logger = logging.getLogger("sub_video.smart_splitter")


@dataclass
class SilenceInterval:
    start: float
    end: float
    duration: float


@dataclass
class VideoChunkMeta:
    chunk_index: int
    start_sec: float
    end_sec: float
    duration_sec: float
    raw_video_path: str
    is_last: bool


class SmartSplitter:

    @staticmethod
    def get_video_duration(video_path: Path | str) -> float:
        """Gets exact video duration in seconds via ffprobe."""
        cmd = [
            "ffprobe", "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            str(video_path)
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return float(res.stdout.strip())
        except Exception as e:
            logger.warning(f"Failed to get duration for {video_path}: {e}")
            return 0.0

    @staticmethod
    def detect_silence_intervals(
        media_path: Path | str,
        start_sec: float,
        end_sec: float,
        silence_thresh_db: int = -35,
        min_silence_duration: float = 0.35
    ) -> List[SilenceInterval]:
        """
        Runs FFmpeg silencedetect within a time window [start_sec, end_sec].
        """
        duration = max(0.1, end_sec - start_sec)
        cmd = [
            "ffmpeg", "-ss", str(start_sec), "-t", str(duration),
            "-i", str(media_path),
            "-af", f"silencedetect=noise={silence_thresh_db}dB:d={min_silence_duration}",
            "-f", "null", "-"
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True)
            output = res.stderr
        except Exception as e:
            logger.warning(f"Error running silencedetect on {media_path}: {e}")
            return []

        intervals = []
        silence_start = None
        for line in output.splitlines():
            if "silence_start:" in line:
                m = re.search(r"silence_start:\s*([0-9.]+)", line)
                if m:
                    silence_start = float(m.group(1)) + start_sec
            elif "silence_end:" in line and silence_start is not None:
                m = re.search(r"silence_end:\s*([0-9.]+)", line)
                if m:
                    silence_end = float(m.group(1)) + start_sec
                    intervals.append(SilenceInterval(
                        start=silence_start,
                        end=silence_end,
                        duration=silence_end - silence_start
                    ))
                    silence_start = None
        return intervals

    @staticmethod
    def get_keyframes_in_range(
        video_path: Path | str,
        start_sec: float,
        end_sec: float
    ) -> List[float]:
        """
        Retrieves all I-Frame (keyframe) timestamps within [start_sec, end_sec].
        Uses -skip_frame nokey for instantaneous keyframe probing.
        """
        cmd = [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-skip_frame", "nokey",
            "-show_entries", "frame=pkt_pts_time,pict_type",
            "-of", "json",
            str(video_path)
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            data = json.loads(res.stdout)
            frames = data.get("frames", [])
            keyframes = []
            for f in frames:
                pts = f.get("pkt_pts_time")
                if pts is not None:
                    t = float(pts)
                    if start_sec <= t <= end_sec:
                        keyframes.append(t)
            return sorted(list(set(keyframes)))
        except Exception as e:
            logger.warning(f"Error fetching keyframes via ffprobe: {e}")
            return []

    @classmethod
    def find_best_cutpoint(
        cls,
        video_path: Path | str,
        target_sec: float,
        search_window_sec: float = 30.0
    ) -> float:
        """
        Triple-Lock cutpoint resolution:
        1. Look for silence intervals within [target_sec - window, target_sec + window]
        2. Look for keyframes in that window
        3. Prioritize keyframes that fall strictly inside a silence interval.
        """
        w_start = max(0.0, target_sec - search_window_sec)
        w_end = target_sec + search_window_sec

        silences = cls.detect_silence_intervals(video_path, w_start, w_end)
        keyframes = cls.get_keyframes_in_range(video_path, w_start, w_end)

        if not keyframes:
            # Fallback to middle of best silence or target_sec
            if silences:
                best_silence = min(silences, key=lambda s: abs((s.start + s.end)/2.0 - target_sec))
                return (best_silence.start + best_silence.end) / 2.0
            return target_sec

        # Find keyframes inside silence
        keyframes_in_silence = []
        for kf in keyframes:
            for s in silences:
                if s.start <= kf <= s.end:
                    keyframes_in_silence.append(kf)
                    break

        if keyframes_in_silence:
            # Pick the one closest to target_sec
            return min(keyframes_in_silence, key=lambda k: abs(k - target_sec))

        # If no keyframe in silence, pick the keyframe closest to target_sec
        return min(keyframes, key=lambda k: abs(k - target_sec))

    @classmethod
    def compute_chunk_boundaries(
        cls,
        video_path: Path | str,
        total_duration: float,
        target_chunk_duration_sec: float = 360.0
    ) -> List[Tuple[float, float]]:
        """
        Computes list of (start_sec, end_sec) for all chunks.
        """
        if total_duration <= target_chunk_duration_sec * 1.3:
            return [(0.0, total_duration)]

        num_chunks = max(1, math.ceil(total_duration / target_chunk_duration_sec))
        ideal_chunk_len = total_duration / num_chunks
        min_buffer = min(20.0, ideal_chunk_len * 0.25)

        cutpoints = [0.0]
        current_target = ideal_chunk_len

        for _ in range(num_chunks - 1):
            cut = cls.find_best_cutpoint(
                video_path=video_path,
                target_sec=current_target,
                search_window_sec=min(30.0, ideal_chunk_len * 0.3)
            )
            # Ensure strictly increasing with safety buffer
            if cut > cutpoints[-1] + min_buffer and cut < total_duration - min_buffer:
                cutpoints.append(round(cut, 3))
                current_target = cut + ideal_chunk_len
            else:
                current_target += ideal_chunk_len

        cutpoints.append(round(total_duration, 3))

        # Build pairs
        boundaries = []
        for i in range(len(cutpoints) - 1):
            s = cutpoints[i]
            e = cutpoints[i + 1]
            if e > s:
                boundaries.append((s, e))
        return boundaries

    @staticmethod
    def split_chunk_lossless(
        input_video: Path | str,
        start_sec: float,
        end_sec: float,
        output_chunk_path: Path | str
    ) -> bool:
        """
        Cuts video chunk losslessly with -c copy and -avoid_negative_ts make_zero.
        """
        output_path = Path(output_chunk_path)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        duration = end_sec - start_sec
        cmd = [
            "ffmpeg", "-y",
            "-ss", str(start_sec),
            "-t", str(duration),
            "-i", str(input_video),
            "-c", "copy",
            "-avoid_negative_ts", "make_zero",
            str(output_path)
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return output_path.exists() and output_path.stat().st_size > 0
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to split chunk {output_chunk_path}: {e.stderr}")
            return False
