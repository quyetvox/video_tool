import os
import subprocess
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List, Optional

import cv2
import numpy as np

from plugins.interfaces import InpaintBase


def _inpaint_chunk_worker(
    video_path: str,
    start_frame: int,
    frame_count: int,
    default_region: List[float],
    segments: Optional[List[Dict[str, Any]]],
    chunk_out_path: str,
    fps: float,
    width: int,
    height: int
) -> str:
    os.environ.pop("MallocStackLogging", None)
    os.environ.pop("MallocScribble", None)
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video in worker: {video_path}")

    cap.set(cv2.CAP_PROP_POS_FRAMES, start_frame)
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(chunk_out_path, fourcc, fps, (width, height))

    processed = 0
    frame_idx = start_frame

    while processed < frame_count and cap.isOpened():
        ret, frame = cap.read()
        if not ret or frame is None:
            break

        t_frame = frame_idx / fps
        mask = np.zeros((height, width), dtype=np.uint8)
        active_boxes = []

        if segments:
            for seg in segments:
                s_start = float(seg.get("start", 0.0))
                s_end = float(seg.get("end", 0.0))
                if s_start <= t_frame <= s_end:
                    box = seg.get("bbox") or default_region
                    if box:
                        active_boxes.append(box)
        else:
            if default_region:
                active_boxes.append(default_region)

        # Apply inpainting if active boxes exist
        if not active_boxes:
            out.write(frame)
        else:
            for box in active_boxes:
                ymin, xmin, ymax, xmax = box
                rymin, rxmin = int(height * ymin), int(width * xmin)
                rymax, rxmax = int(height * ymax), int(width * xmax)
                # Expand box slightly (3px padding) to cover border stroke
                rymin, rxmin = max(0, rymin - 3), max(0, rxmin - 3)
                rymax, rxmax = min(height, rymax + 3), min(width, rxmax + 3)
                mask[rymin:rymax, rxmin:rxmax] = 255

            inpainted = cv2.inpaint(frame, mask, inpaintRadius=3, flags=cv2.INPAINT_TELEA)
            out.write(inpainted)

        processed += 1
        frame_idx += 1

    cap.release()
    out.release()
    return chunk_out_path


class Plugin(InpaintBase):
    def remove_subtitles(
        self,
        video_path: Path,
        region: List[float],
        output_video: Path,
        segments: Optional[List[Dict[str, Any]]] = None
    ) -> Path:
        inpaint_color = str(self.config.get("inpaint_color", "transparent")).strip().lower()
        if inpaint_color not in ["transparent", "", "none"]:
            from plugins.inpaint.ffmpeg_blur import Plugin as FFmpegBlurPlugin
            return FFmpegBlurPlugin(self.config).remove_subtitles(video_path, region, output_video, segments=segments)

        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            raise RuntimeError(f"Cannot open video for inpainting: {video_path}")

        fps = cap.get(cv2.CAP_PROP_FPS) or 24.0
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        cap.release()

        num_workers = max(1, min(os.cpu_count() or 4, 8))

        if total_frames <= 0 or num_workers == 1:
            return Path(_inpaint_chunk_worker(
                str(video_path), 0, total_frames or 100000, region, segments, str(output_video), fps, width, height
            ))

        chunk_size = (total_frames + num_workers - 1) // num_workers
        temp_dir = Path(output_video.parent) / f"inpaint_chunks_{output_video.stem}"
        temp_dir.mkdir(parents=True, exist_ok=True)

        futures = []
        chunk_files = []

        with ProcessPoolExecutor(max_workers=num_workers) as executor:
            for i in range(num_workers):
                start_f = i * chunk_size
                count_f = min(chunk_size, total_frames - start_f)
                if count_f <= 0:
                    break
                chunk_file = temp_dir / f"chunk_{i:03d}.mp4"
                chunk_files.append(chunk_file)
                
                future = executor.submit(
                    _inpaint_chunk_worker,
                    str(video_path),
                    start_f,
                    count_f,
                    region,
                    segments,
                    str(chunk_file),
                    fps,
                    width,
                    height
                )
                futures.append(future)

            for f in as_completed(futures):
                f.result()

        concat_list = temp_dir / "concat_list.txt"
        with open(concat_list, "w", encoding="utf-8") as list_f:
            for cf in chunk_files:
                list_f.write(f"file '{cf.name}'\n")

        cmd = [
            "ffmpeg", "-y", "-f", "concat", "-safe", "0",
            "-i", str(concat_list),
            "-c", "copy", str(output_video)
        ]
        subprocess.run(cmd, capture_output=True, check=True)

        try:
            for cf in chunk_files:
                if cf.exists():
                    cf.unlink()
            if concat_list.exists():
                concat_list.unlink()
            if temp_dir.exists():
                temp_dir.rmdir()
        except Exception:
            pass

        return output_video
