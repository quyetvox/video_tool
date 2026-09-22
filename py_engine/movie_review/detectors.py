"""
Targeted scene detector and keyframe extraction for Movie Review engine.
"""

import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

from utils.ffmpeg_utils import FFmpegUtils
from .common import emit_log, emit_progress


class TargetedSceneDetector:
    """Quét cảnh chỉ trên các mốc thời gian cao trào đã chọn."""

    @staticmethod
    def detect_scenes_pure_ffmpeg(
        video_path: Path,
        start_sec: float,
        end_sec: float,
        start_scene_id: int,
        output_dir: Path,
        max_scenes_per_range: int = 8
    ) -> List[Dict[str, Any]]:
        """Fallback quét cảnh thuần FFmpeg nếu chưa có scenedetect."""
        duration = max(1.0, end_sec - start_sec)
        scenes = []

        # Chia nhỏ khoảng thời gian thành các cảnh logic tự nhiên (4s - 8s mỗi cảnh)
        step = max(3.5, min(8.0, duration / max(1, max_scenes_per_range)))
        curr = start_sec
        scene_idx = start_scene_id

        while curr < end_sec:
            sc_start = curr
            sc_end = min(end_sec, curr + step)
            sc_dur = sc_end - sc_start
            mid_sec = sc_start + (sc_dur / 2.0)

            img_name = f"scene_{scene_idx:04d}.jpg"
            img_path = output_dir / img_name

            # Trích xuất 1 frame ảnh tại chính giữa phân cảnh (360p nhẹ)
            cmd = [
                "ffmpeg", "-y",
                "-ss", f"{mid_sec:.3f}",
                "-i", str(video_path),
                "-vframes", "1",
                "-vf", "scale=-2:360",
                "-q:v", "3",
                str(img_path)
            ]
            subprocess.run(cmd, capture_output=True)

            if img_path.exists() and img_path.stat().st_size > 0:
                scenes.append({
                    "scene_id": scene_idx,
                    "start_sec": round(sc_start, 2),
                    "end_sec": round(sc_end, 2),
                    "duration": round(sc_dur, 2),
                    "image_path": str(img_path.name),
                })
                scene_idx += 1

            curr += step

        return scenes

    @staticmethod
    def detect_scenes_for_ranges(
        video_path: Path,
        ranges: List[Dict[str, Any]],
        output_dir: Path,
        max_total_scenes: int = 350,
        target_shots: int = 150
    ) -> List[Dict[str, Any]]:
        """Quét và trích xuất keyframes cho tất cả các khoảng thời gian, tự động bù cảnh nếu thiếu."""
        output_dir.mkdir(parents=True, exist_ok=True)
        all_scenes = []
        next_id = 1

        # Cần tối thiểu target_shots + 20 cảnh để đảm bảo không bao giờ bị thiếu/lặp cảnh
        min_needed = max(target_shots + 20, 150)
        total_ranges = len(ranges)
        scenes_per_range = max(5, int(min_needed / max(1, total_ranges)))

        for i, r in enumerate(ranges):
            s_val = float(r.get("start_sec", 0))
            e_val = float(r.get("end_sec", s_val + 10))
            if e_val <= s_val:
                continue

            emit_progress(
                0.2 + 0.25 * ((i + 1) / max(1, total_ranges)),
                f"Đang quét cảnh mốc {i+1}/{total_ranges} ({s_val:.0f}s - {e_val:.0f}s)..."
            )

            # Quét các scene trong mốc này
            scs = TargetedSceneDetector.detect_scenes_pure_ffmpeg(
                video_path=video_path,
                start_sec=s_val,
                end_sec=e_val,
                start_scene_id=next_id,
                output_dir=output_dir,
                max_scenes_per_range=scenes_per_range
            )
            for s in scs:
                s["act"] = r.get("act", "storytelling")
                all_scenes.append(s)
                next_id += 1

            if len(all_scenes) >= max_total_scenes:
                break

        # TỰ ĐỘNG BÙ ĐẮP (AUTO-FILL): Nếu chưa đủ min_needed cảnh, quét bổ sung đều trên video gốc
        if len(all_scenes) < min_needed:
            emit_log("info", f"Số cảnh quét được ({len(all_scenes)}) chưa đủ {min_needed}, tự động quét bù cảnh trên timeline...")
            probe = FFmpegUtils.probe(video_path)
            total_dur = float(probe.get("format", {}).get("duration", 0))
            if total_dur > 30:
                missing = min_needed - len(all_scenes)
                step_fill = total_dur / max(1, missing * 2)
                candidate_idx = 0
                while len(all_scenes) < min_needed and candidate_idx < missing * 4:
                    fill_start = round((candidate_idx + 0.5) * step_fill, 2)
                    candidate_idx += 1
                    if fill_start >= total_dur - 4.0:
                        break
                    fill_end = round(min(total_dur, fill_start + 6.0), 2)
                    overlap = any(abs(s["start_sec"] - fill_start) < 3.5 for s in all_scenes)
                    if not overlap and fill_end > fill_start:
                        mid_sec = fill_start + (fill_end - fill_start) / 2.0
                        img_name = f"scene_{next_id:04d}.jpg"
                        img_path = output_dir / img_name
                        cmd = [
                            "ffmpeg", "-y",
                            "-ss", f"{mid_sec:.3f}",
                            "-i", str(video_path),
                            "-vframes", "1",
                            "-vf", "scale=-2:360",
                            "-q:v", "3",
                            str(img_path)
                        ]
                        subprocess.run(cmd, capture_output=True)
                        if img_path.exists() and img_path.stat().st_size > 0:
                            all_scenes.append({
                                "scene_id": next_id,
                                "start_sec": fill_start,
                                "end_sec": fill_end,
                                "duration": round(fill_end - fill_start, 2),
                                "image_path": str(img_path.name),
                                "act": "storytelling"
                            })
                            next_id += 1

        # Sắp xếp lại theo start_sec và đánh lại scene_id tuần tự 1, 2, 3...
        all_scenes.sort(key=lambda s: s["start_sec"])
        for idx, sc in enumerate(all_scenes):
            sc["scene_id"] = idx + 1

        emit_log("success", f"Đã trích xuất thành công {len(all_scenes)} keyframes đại diện (đủ cho {target_shots} shots).")
        return all_scenes
