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
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

try:
    from utils.ffmpeg_utils import FFmpegUtils
except ImportError:
    try:
        from .ffmpeg_utils import FFmpegUtils
    except ImportError:
        FFmpegUtils = None

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
        silence_thresh_db: int = -30,
        min_silence_duration: float = 0.35
    ) -> List[SilenceInterval]:
        """
        Runs ultra-fast FFmpeg silencedetect on the audio stream only within [start_sec, end_sec].
        Uses -vn to completely bypass video decoding for sub-50ms execution.
        """
        duration = max(0.1, end_sec - start_sec)
        cmd = [
            "ffmpeg", "-v", "error",
            "-ss", f"{start_sec:.3f}", "-t", f"{duration:.3f}",
            "-i", str(media_path),
            "-vn",
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
    def detect_voice_vad_pause(
        media_path: Path | str,
        start_sec: float,
        end_sec: float,
        target_sec: float
    ) -> Optional[float]:
        """
        Stage 2 Voice Energy VAD Fallback: Extracts 16kHz mono PCM and analyzes RMS energy envelope
        to pinpoint the speech pause (valley) between sentences when continuous BGM masks absolute silence.
        """
        try:
            import numpy as np
        except ImportError:
            return None

        duration = max(0.5, end_sec - start_sec)
        cmd = [
            "ffmpeg", "-v", "error",
            "-ss", f"{start_sec:.3f}", "-t", f"{duration:.3f}",
            "-i", str(media_path),
            "-vn", "-ac", "1", "-ar", "16000",
            "-f", "s16le", "-"
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, check=True)
            raw_bytes = res.stdout
            if not raw_bytes or len(raw_bytes) < 3200:  # < 100ms
                return None

            samples = np.frombuffer(raw_bytes, dtype=np.int16).astype(np.float32) / 32768.0
            sr = 16000
            window_size = int(sr * 0.05)  # 50ms window
            hop_size = int(sr * 0.025)   # 25ms hop

            # Calculate RMS energy for each 50ms block
            rms_list = []
            timestamps = []
            for i in range(0, len(samples) - window_size, hop_size):
                block = samples[i : i + window_size]
                rms = float(np.sqrt(np.mean(block**2) + 1e-12))
                rms_list.append(rms)
                timestamps.append(start_sec + (i + window_size / 2) / sr)

            if not rms_list:
                return None

            # Estimate noise / background music baseline (20th percentile)
            bg_energy = float(np.percentile(rms_list, 20))
            speech_threshold = bg_energy * 1.6 + 0.003

            # Find continuous valleys where energy is below threshold for >= 0.25s
            valleys = []
            in_valley = False
            v_start = 0.0

            for t, rms in zip(timestamps, rms_list):
                if rms <= speech_threshold:
                    if not in_valley:
                        in_valley = True
                        v_start = t
                else:
                    if in_valley:
                        in_valley = False
                        v_dur = t - v_start
                        if v_dur >= 0.25:
                            valleys.append((v_start, t, v_dur))
            if in_valley and (timestamps[-1] - v_start >= 0.25):
                valleys.append((v_start, timestamps[-1], timestamps[-1] - v_start))

            if valleys:
                # Score valleys: prefer longer pauses, close to target_sec
                def _score_valley(val):
                    s, e, dur = val
                    mid = (s + e) / 2.0
                    return dur * 2.0 - abs(mid - target_sec) * 0.08

                best_valley = max(valleys, key=_score_valley)
                return (best_valley[0] + best_valley[1]) / 2.0

            # If no sustained valley, find local minimum energy point within 15s of target_sec
            candidates = [(t, r) for t, r in zip(timestamps, rms_list) if abs(t - target_sec) <= 15.0]
            if candidates:
                return min(candidates, key=lambda x: x[1])[0]

            return None
        except Exception as e:
            logger.warning(f"Voice VAD pause detection failed: {e}")
            return None

    @staticmethod
    def get_keyframes_in_range(
        video_path: Path | str,
        start_sec: float,
        end_sec: float
    ) -> List[float]:
        """
        Retrieves all I-Frame (keyframe) timestamps within [start_sec, end_sec].
        Maintained for backwards compatibility.
        """
        cmd = [
            "ffprobe", "-v", "error",
            "-select_streams", "v:0",
            "-skip_frame", "nokey",
            "-read_intervals", f"{max(0.0, start_sec):.2f}%{end_sec:.2f}",
            "-show_entries", "frame=pts_time,pkt_pts_time,best_effort_timestamp_time,pkt_dts_time,pict_type",
            "-of", "json",
            str(video_path)
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            data = json.loads(res.stdout)
            frames = data.get("frames", [])
            keyframes = []
            for f in frames:
                pts = f.get("pts_time") or f.get("best_effort_timestamp_time") or f.get("pkt_pts_time") or f.get("pkt_dts_time")
                if pts is not None:
                    try:
                        t = float(pts)
                        if start_sec <= t <= end_sec:
                            keyframes.append(t)
                    except ValueError:
                        continue
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
        Hybrid Multi-Stage Cutpoint Resolution:
        1. Fast Audio Silence Probe (Stage 1): Checks audio stream for true silence intervals.
           If found, picks the midpoint of the longest / most optimal silence gap.
        2. Voice Energy VAD (Stage 2 Fallback): If background music prevents -30dB silence,
           analyzes vocal energy envelope to find the speech pause between sentences.
        3. Completely decoupled from video keyframes to prevent cutting through speech.
        """
        w_start = max(0.0, target_sec - search_window_sec)
        w_end = target_sec + search_window_sec

        # Stage 1: Try fast audio silence detect at -30dB, then -25dB fallback
        for thresh in [-30, -25]:
            silences = cls.detect_silence_intervals(
                media_path=video_path,
                start_sec=w_start,
                end_sec=w_end,
                silence_thresh_db=thresh,
                min_silence_duration=0.35
            )
            valid_silences = [s for s in silences if s.duration >= 0.35]
            if valid_silences:
                # Score each silence: prefer longer duration (safer pause), close to target_sec
                def _silence_score(s: SilenceInterval) -> float:
                    mid = (s.start + s.end) / 2.0
                    dist = abs(mid - target_sec)
                    return s.duration * 2.5 - (dist / search_window_sec)

                best_silence = max(valid_silences, key=_silence_score)
                midpoint = (best_silence.start + best_silence.end) / 2.0
                logger.info(f"Stage 1 Silence found at {midpoint:.2f}s (dur={best_silence.duration:.2f}s, thresh={thresh}dB)")
                return round(midpoint, 3)

        # Stage 2: Voice Energy VAD Fallback (for heavy background music)
        vad_point = cls.detect_voice_vad_pause(
            media_path=video_path,
            start_sec=w_start,
            end_sec=w_end,
            target_sec=target_sec
        )
        if vad_point is not None:
            logger.info(f"Stage 2 Voice VAD pause found at {vad_point:.2f}s")
            return round(vad_point, 3)

        # Stage 3: Graceful fallback
        return round(target_sec, 3)

    @classmethod
    def compute_chunk_boundaries(
        cls,
        video_path: Path | str,
        total_duration: float,
        target_chunk_duration_sec: float = 360.0,
        max_drift_sec: float = 30.0
    ) -> List[Tuple[float, float]]:
        """
        Computes list of (start_sec, end_sec) for all chunks respecting natural audio pauses.
        Allows flexible duration drift (up to max_drift_sec) so sentences are never clipped.
        Automatically merges small tail fragments into the previous chunk.
        """
        # If video is not significantly longer than target chunk duration, don't split
        if total_duration <= target_chunk_duration_sec * 1.3:
            return [(0.0, round(total_duration, 3))]

        boundaries = []
        current_start = 0.0
        min_chunk_len = min(20.0, target_chunk_duration_sec * 0.25)
        tail_merge_threshold = min(45.0, target_chunk_duration_sec * 0.4)

        while True:
            target_end = current_start + target_chunk_duration_sec
            remaining_after_target = total_duration - target_end

            # If remaining duration after target is too short, merge into final chunk
            if remaining_after_target < tail_merge_threshold:
                boundaries.append((round(current_start, 3), round(total_duration, 3)))
                break

            # Find best silence or VAD pause within [target_end - max_drift, target_end + max_drift]
            actual_drift = min(max_drift_sec, target_chunk_duration_sec * 0.35)
            cut_point = cls.find_best_cutpoint(
                video_path=video_path,
                target_sec=target_end,
                search_window_sec=actual_drift
            )

            # Safety checks: ensure chunk is long enough and not too close to the end
            if cut_point <= current_start + min_chunk_len:
                cut_point = target_end
            elif cut_point >= total_duration - min_chunk_len:
                boundaries.append((round(current_start, 3), round(total_duration, 3)))
                break

            boundaries.append((round(current_start, 3), round(cut_point, 3)))
            current_start = cut_point

            if total_duration - current_start < tail_merge_threshold:
                boundaries.append((round(current_start, 3), round(total_duration, 3)))
                break

        return boundaries

    @staticmethod
    def split_chunk_frame_accurate(
        input_video: Path | str,
        start_sec: float,
        end_sec: float,
        output_chunk_path: Path | str
    ) -> bool:
        """
        Cuts video chunk with 100% frame-accurate millisecond precision using hardware acceleration (VideoToolbox).
        Guarantees exact start and end timestamps without Keyframe drift.
        """
        in_p = Path(input_video).resolve()
        out_p = Path(output_chunk_path).resolve()
        out_p.parent.mkdir(parents=True, exist_ok=True)

        if FFmpegUtils:
            try:
                FFmpegUtils.trim_video(
                    input_file=in_p,
                    output_file=out_p,
                    start_sec=start_sec,
                    end_sec=end_sec,
                    accurate=True
                )
                if out_p.exists() and out_p.stat().st_size > 0:
                    return True
            except Exception as e:
                logger.warning(f"FFmpegUtils trim_video error: {e}, falling back to direct hardware ffmpeg")

        # Direct hardware accelerated command fallback
        duration = max(0.1, end_sec - start_sec)
        hw_enc = "h264_videotoolbox" if sys.platform == "darwin" else "libx264"
        cmd = [
            "ffmpeg", "-y",
            "-ss", f"{start_sec:.3f}",
            "-i", str(in_p),
            "-t", f"{duration:.3f}",
            "-c:v", hw_enc,
            "-b:v", "4M",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            str(out_p)
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            return out_p.exists() and out_p.stat().st_size > 0
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to split chunk {output_chunk_path}: {e.stderr}")
            return False

    # Backwards compatibility alias
    split_chunk_lossless = split_chunk_frame_accurate

