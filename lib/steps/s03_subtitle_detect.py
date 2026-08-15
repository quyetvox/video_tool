import logging
from pathlib import Path
from typing import Any, Dict, Optional

import cv2
import numpy as np

from core.step_base import StepBase

logger = logging.getLogger("sub_video")


class StepSubtitleDetect(StepBase):
    step_id = "s03_subtitle_detect"
    depends_on = ["s01_probe", "s02_demux"]
    STEP_CONFIG_KEYS = ["show_subtitle", "inpaint_region", "subtitle_detect_start_sec", "subtitle_detect_duration_sec"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        import json
        probe_info = job_state.get_step_output("s01_probe") or {}
        demux_info = job_state.get_step_output("s02_demux") or {}

        # If subtitle display is disabled and no manual inpaint region override, skip detection entirely (~0s)
        show_sub = config.get("show_subtitle", True)
        override_region = config.get("inpaint_region")
        if show_sub is False and not override_region:
            logger.info("[s03_subtitle_detect] show_subtitle is False: Bypassing subtitle region auto-detection (~0s).")
            return {
                "mode": "none",
                "embedded_sub": None,
                "burnin_region": None,
                "skipped": True
            }

        # Priority 1: Embedded Subtitle Track
        if probe_info.get("has_embedded_subtitles") and demux_info.get("embedded_sub"):
            return {
                "mode": "embedded",
                "embedded_sub": demux_info["embedded_sub"],
                "burnin_region": None
            }

        # Priority 2: Manual inpaint_region override in config
        if override_region and isinstance(override_region, list) and len(override_region) == 4:
            return {
                "mode": "burnin",
                "embedded_sub": None,
                "burnin_region": override_region
            }

        # Priority 3: Auto-detect burnin region
        video_path = Path(demux_info["video_stream"])
        duration = probe_info.get("duration", 0)
        width = probe_info.get("width", 1080)
        height = probe_info.get("height", 1920)

        detect_duration = float(config.get("subtitle_detect_duration_sec", 10.0))
        font_size = config.get("subtitle_font_size")

        # In ocr_only mode, prioritize PaddleOCR sampling on first 10s for high-precision Y bounds
        region = None
        if config.get("ocr_only"):
            region = self._detect_burnin_ocr(video_path, config, workspace)

        if region is None:
            region = self._detect_burnin_framediff_multi_window(
                video_path, duration, detect_duration,
                height, width, font_size
            )

        if region is not None:
            logger.info(f"[s03_subtitle_detect] Auto-detected inpaint_region: {region}")
            return {
                "mode": "burnin",
                "embedded_sub": None,
                "burnin_region": region
            }

        # Priority 4: No subtitle found
        return {
            "mode": "audio_only",
            "embedded_sub": None,
            "burnin_region": None
        }

    def _detect_burnin_ocr(self, video_path: Path, config: Dict[str, Any], workspace: Path) -> Optional[list]:
        """
        Fast scan of first N seconds using PaddleOCR to accurately detect fixed subtitle Y bounds.
        Uses extract_text_for_region_detect (1fps + early exit at min_hits) for speed.
        """
        try:
            from core.plugin_loader import PluginLoader
            ocr_plugin = PluginLoader.load_plugin("ocr", config.get("ocr", "paddle_ocr"), config)

            max_sec = float(config.get("subtitle_detect_duration_sec", 10.0))
            min_hits = 5

            # Use fast region-detect method if available (scans 1fps + early exit)
            if hasattr(ocr_plugin, "extract_text_for_region_detect"):
                segments = ocr_plugin.extract_text_for_region_detect(
                    video_path, [0.10, 0.0, 0.95, 1.0],
                    max_seconds=max_sec, min_hits=min_hits
                )
            else:
                segments = ocr_plugin.extract_text(video_path, [0.10, 0.0, 0.95, 1.0])

            if not segments:
                return None

            early_segs = [s for s in segments if float(s.get("start", 0)) <= 10.0 and "bbox" in s]
            if not early_segs:
                early_segs = [s for s in segments if "bbox" in s]
            if not early_segs:
                return None

            import numpy as np

            # Filter: keep only boxes that look like centered subtitles
            #   - span at least 30% of screen width (X range)
            #   - center of box is within X = 0.20 to 0.80 (not far-edge text)
            #   - Y position is in top 50% (for top-positioned subs like Douyin)
            subtitle_segs = []
            for s in early_segs:
                b = s["bbox"]  # [ymin, xmin, ymax, xmax]
                box_w = b[3] - b[1]
                box_cx = (b[1] + b[3]) / 2.0
                if box_w >= 0.30 and 0.15 <= box_cx <= 0.85:
                    subtitle_segs.append(b)

            # Fallback: if filter is too strict, use all segs in upper half
            if not subtitle_segs:
                subtitle_segs = [s["bbox"] for s in early_segs if s["bbox"][0] < 0.50]
            if not subtitle_segs:
                subtitle_segs = [s["bbox"] for s in early_segs]

            ymins = [b[0] for b in subtitle_segs]
            ymaxs = [b[2] for b in subtitle_segs]

            tight_ymin = float(np.median(ymins))
            tight_ymax = float(np.median(ymaxs))

            padding_y = float(config.get("blur_box_padding_y", 0.02))
            fixed_ymin = max(0.0, tight_ymin - padding_y)
            fixed_ymax = min(1.0, tight_ymax + padding_y)

            logger.info(f"[s03_subtitle_detect] OCR region from {len(subtitle_segs)} hits: Y={fixed_ymin:.3f}-{fixed_ymax:.3f} (padding_y={padding_y})")
            return [round(fixed_ymin, 3), 0.05, round(fixed_ymax, 3), 0.95]
        except Exception as e:
            logger.warning(f"[s03_subtitle_detect] OCR auto-detect failed, falling back to FrameDiff: {e}")
            return None

    def _find_clusters(self, active_rows: np.ndarray, gap_tolerance: int = 5) -> list:
        """Group consecutive row indices into clusters, tolerating small gaps."""
        if len(active_rows) == 0:
            return []

        clusters = []
        start = active_rows[0]
        prev = active_rows[0]

        for row in active_rows[1:]:
            if row - prev > gap_tolerance:
                clusters.append((start, prev))
                start = row
            prev = row

        clusters.append((start, prev))
        return clusters

    def _detect_burnin_framediff_multi_window(
        self,
        video_path: Path,
        total_duration: float,
        window_duration: float,      # kept for API compat, now unused
        video_h: int,
        video_w: int,
        subtitle_font_size: Optional[int] = None,
    ) -> Optional[list]:
        """
        Full-video sparse sampling strategy.
        Sample 40 frames evenly across 5%-95% of video duration.
        Background noise cancels out; the subtitle band (consistently present) dominates.
        """
        if not video_path.exists():
            return None

        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            return None

        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if total_frames < 10:
            cap.release()
            return None

        # Skip first 5% and last 5% — avoid intros/outros
        skip_start = max(int(total_frames * 0.05), int(3 * fps))
        skip_end   = min(total_frames - 1, int(total_frames * 0.95))

        sample_count = min(40, (skip_end - skip_start) // 5)
        if sample_count < 5:
            cap.release()
            return None

        frame_indices = np.linspace(skip_start, skip_end, sample_count, dtype=int)

        # Accumulate absolute frame diffs into one heat map
        heat_map = np.zeros((video_h, video_w), dtype=np.float32)
        prev_gray = None
        valid_diffs = 0

        for idx in frame_indices:
            cap.set(cv2.CAP_PROP_POS_FRAMES, int(idx))
            ret, frame = cap.read()
            if not ret or frame is None:
                continue
            fh, fw = frame.shape[:2]
            if fh != video_h or fw != video_w:
                frame = cv2.resize(frame, (video_w, video_h))
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            if prev_gray is not None:
                diff = cv2.absdiff(gray, prev_gray)
                heat_map += diff.astype(np.float32)
                valid_diffs += 1
            prev_gray = gray

        cap.release()

        if valid_diffs < 5:
            return None

        # Row-wise activity sum
        row_activity = heat_map.sum(axis=1)

        # Threshold: mean + 1.2 std (more sensitive to thin/middle subtitles)
        threshold = row_activity.mean() + 1.2 * row_activity.std()
        active_rows = np.where(row_activity > threshold)[0]

        if len(active_rows) == 0:
            return None

        # Consider top 30% or bottom 50% subtitle zones (covering 50% -> 95% height)
        top_zone_max = int(video_h * 0.30)
        bot_zone_min = int(video_h * 0.50)

        filtered_top = active_rows[active_rows <= top_zone_max]
        filtered_bot = active_rows[active_rows >= bot_zone_min]

        clusters_top = self._find_clusters(filtered_top) if len(filtered_top) > 0 else []
        clusters_bot = self._find_clusters(filtered_bot) if len(filtered_bot) > 0 else []

        # Min/max cluster height filter: subtitles are typically 3-18% of frame height
        min_h_px = max(10, int(video_h * 0.03))
        max_h_px = int(video_h * 0.18)

        def score_cluster(cluster):
            c_top, c_bot = cluster
            cluster_h = c_bot - c_top
            # Reject clusters that are too thin or too tall
            if cluster_h < min_h_px or cluster_h > max_h_px:
                return -1.0
            total_act = float(row_activity[c_top:c_bot + 1].sum())
            return total_act / max(1, cluster_h)  # density per row

        if not clusters_top and not clusters_bot:
            return None

        # Score clusters by activity density per pixel row
        def get_best_cluster(clusters):
            scored = [(score_cluster(c), c) for c in clusters]
            valid = [(s, c) for s, c in scored if s > 0]
            if not valid:
                return None
            return max(valid, key=lambda sc: sc[0])[1]

        # Priority: prefer bottom zone (Douyin subs are almost always at bottom)
        # Only fall back to top zone if bottom has no valid cluster
        best_bot = get_best_cluster(clusters_bot)
        best_top = get_best_cluster(clusters_top)

        if best_bot is not None:
            best_cluster = best_bot
        elif best_top is not None:
            best_cluster = best_top
        else:
            # Last resort: pick largest cluster ignoring height filter
            all_clusters = clusters_top + clusters_bot
            best_cluster = max(all_clusters, key=lambda c: c[1] - c[0])

        cluster_top_px, cluster_bottom_px = best_cluster

        # Padding based on blur_box_padding_y config (default 0.02 = 2% frame height)
        padding_y = float(self.config.get("blur_box_padding_y", 0.02)) if hasattr(self, "config") else 0.02
        pad_px = max(3, int(video_h * padding_y))

        top_px    = max(0, cluster_top_px - pad_px)
        bottom_px = min(video_h, cluster_bottom_px + pad_px)

        return [
            round(float(top_px) / video_h, 3),
            0.05,
            round(float(bottom_px) / video_h, 3),
            0.95
        ]
