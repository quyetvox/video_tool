from pathlib import Path
from typing import Any, Dict

import cv2
import numpy as np

from core.step_base import StepBase


class StepSubtitleDetect(StepBase):
    step_id = "s03_subtitle_detect"
    depends_on = ["s01_probe", "s02_demux"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        probe_info = job_state.get_step_output("s01_probe") or {}
        demux_info = job_state.get_step_output("s02_demux") or {}

        # Tier 1: Embedded Subtitle Track
        if probe_info.get("has_embedded_subtitles") and demux_info.get("embedded_sub"):
            return {
                "mode": "embedded",
                "embedded_sub": demux_info["embedded_sub"],
                "burnin_region": None
            }

        # Check config for manual inpaint_region override
        override_region = config.get("inpaint_region")
        if override_region and isinstance(override_region, list) and len(override_region) == 4:
            return {
                "mode": "burnin",
                "embedded_sub": None,
                "burnin_region": override_region
            }

        # Tier 2: Check for Burn-in Subtitles using OpenCV Heuristic
        video_path = Path(demux_info["video_stream"])
        is_burnin, region = self._detect_burnin_subtitles(video_path, probe_info.get("duration", 0))

        if is_burnin:
            return {
                "mode": "burnin",
                "embedded_sub": None,
                "burnin_region": region  # [ymin, xmin, ymax, xmax] relative
            }

        # Tier 3: Audio Only
        return {
            "mode": "audio_only",
            "embedded_sub": None,
            "burnin_region": None
        }

    def _detect_burnin_subtitles(self, video_path: Path, duration: float) -> tuple[bool, list[float]]:
        """Sample frames across video duration to detect burn-in subtitle position [ymin, xmin, ymax, xmax]."""
        if not video_path.exists():
            return False, [0.75, 0.05, 0.95, 0.95]

        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            return False, [0.75, 0.05, 0.95, 0.95]

        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if total_frames <= 0:
            cap.release()
            return False, [0.75, 0.05, 0.95, 0.95]

        sample_ratios = [0.1, 0.25, 0.4, 0.55, 0.7, 0.85]
        detected_regions = []

        for ratio in sample_ratios:
            frame_idx = int(total_frames * ratio)
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            ret, frame = cap.read()
            if not ret or frame is None:
                continue

            h, w = frame.shape[:2]
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            
            # Focus on bottom 30% first (most common), then top 30%
            regions_to_check = [
                ("bottom", int(h * 0.70), h, 0.70, 1.0),
                ("top", 0, int(h * 0.30), 0.0, 0.30)
            ]

            for loc, y_start, y_end, y_rel_start, y_rel_end in regions_to_check:
                crop = gray[y_start:y_end, :]
                edges = cv2.Canny(crop, 100, 200)
                edge_density = np.sum(edges > 0) / (edges.shape[0] * edges.shape[1])

                if edge_density > 0.025:
                    # Find tight bounding box of edges in crop
                    y_indices, x_indices = np.where(edges > 0)
                    if len(y_indices) > 0:
                        c_ymin = (y_start + np.min(y_indices)) / h
                        c_ymax = (y_start + np.max(y_indices)) / h
                        c_xmin = np.min(x_indices) / w
                        c_xmax = np.max(x_indices) / w
                        detected_regions.append((c_ymin, c_xmin, c_ymax, c_xmax))
                    break

        cap.release()

        if len(detected_regions) >= 2:
            # Average bounding box across detected frames
            avg_ymin = max(0.0, min(r[0] for r in detected_regions) - 0.02)
            avg_xmin = max(0.0, min(r[1] for r in detected_regions) - 0.02)
            avg_ymax = min(1.0, max(r[2] for r in detected_regions) + 0.02)
            avg_xmax = min(1.0, max(r[3] for r in detected_regions) + 0.02)
            
            region = [round(avg_ymin, 3), round(avg_xmin, 3), round(avg_ymax, 3), round(avg_xmax, 3)]
            return True, region

        # Default bottom region if not enough detections
        default_region = [0.75, 0.05, 0.95, 0.95]
        return False, default_region
