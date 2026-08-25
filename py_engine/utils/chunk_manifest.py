#!/usr/bin/env python3
"""
Chunk Manifest & Workspace Manager Module.
Tracks the checkpoint state of all video chunks in an isolated folder,
enabling seamless resume on interruption and zero duplicate work.
"""

import json
import logging
import time
from dataclasses import asdict, dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger("sub_video.chunk_manifest")


class ChunkStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass
class ChunkItem:
    id: int
    start_sec: float
    end_sec: float
    duration_sec: float
    raw_chunk_file: str
    workspace_dir: str
    output_file: str
    status: ChunkStatus = ChunkStatus.PENDING
    progress: float = 0.0
    current_step: Optional[str] = None
    error_message: Optional[str] = None
    updated_at: float = field(default_factory=time.time)


@dataclass
class ManifestData:
    video_name: str
    video_stem: str
    source_video_path: str
    total_duration_sec: float
    target_chunk_duration_sec: float
    total_chunks: int
    created_at: float
    updated_at: float
    status: str  # "in_progress", "completed", "failed"
    final_output_path: Optional[str] = None
    chunks: List[ChunkItem] = field(default_factory=list)


class ChunkManifestManager:
    def __init__(self, workspace_root: Path | str, video_path: Path | str):
        self.workspace_root = Path(workspace_root).resolve()
        self.video_path = Path(video_path).resolve()
        self.video_name = self.video_path.name
        self.video_stem = self.video_path.stem

        # Dedicated isolated folder structure
        self.chunks_base_dir = self.workspace_root / "chunks" / self.video_stem
        self.raw_chunks_dir = self.chunks_base_dir / "raw_chunks"
        self.chunk_workspaces_dir = self.chunks_base_dir / "chunk_workspaces"
        self.chunk_outputs_dir = self.chunks_base_dir / "chunk_outputs"
        self.manifest_file = self.chunks_base_dir / "manifest.json"
        self.concat_list_file = self.chunks_base_dir / "concat_list.txt"

        self._ensure_directories()
        self.data: Optional[ManifestData] = None

    def _ensure_directories(self):
        self.raw_chunks_dir.mkdir(parents=True, exist_ok=True)
        self.chunk_workspaces_dir.mkdir(parents=True, exist_ok=True)
        self.chunk_outputs_dir.mkdir(parents=True, exist_ok=True)

    def load_or_create_manifest(
        self,
        boundaries: List[tuple[float, float]],
        total_duration_sec: float,
        target_chunk_duration_sec: float,
        final_output_path: Optional[str] = None
    ) -> ManifestData:
        """
        Loads existing manifest.json if valid; otherwise creates a new one.
        """
        if self.manifest_file.exists():
            try:
                with open(self.manifest_file, "r", encoding="utf-8") as f:
                    raw = json.load(f)
                
                # Reconstruct chunks
                chunks = []
                for c in raw.get("chunks", []):
                    chunks.append(ChunkItem(
                        id=c["id"],
                        start_sec=c["start_sec"],
                        end_sec=c["end_sec"],
                        duration_sec=c["duration_sec"],
                        raw_chunk_file=c["raw_chunk_file"],
                        workspace_dir=c["workspace_dir"],
                        output_file=c["output_file"],
                        status=ChunkStatus(c.get("status", ChunkStatus.PENDING)),
                        progress=c.get("progress", 0.0),
                        current_step=c.get("current_step"),
                        error_message=c.get("error_message"),
                        updated_at=c.get("updated_at", time.time())
                    ))

                self.data = ManifestData(
                    video_name=raw["video_name"],
                    video_stem=raw["video_stem"],
                    source_video_path=raw["source_video_path"],
                    total_duration_sec=raw["total_duration_sec"],
                    target_chunk_duration_sec=raw["target_chunk_duration_sec"],
                    total_chunks=len(chunks),
                    created_at=raw["created_at"],
                    updated_at=raw.get("updated_at", time.time()),
                    status=raw.get("status", "in_progress"),
                    final_output_path=raw.get("final_output_path", final_output_path),
                    chunks=chunks
                )
                logger.info(f"Loaded existing manifest with {len(chunks)} chunks for {self.video_stem}")
                return self.data
            except Exception as e:
                logger.warning(f"Failed to load existing manifest ({e}), recreating new one.")

        # Create new manifest from boundaries
        chunks = []
        for idx, (start, end) in enumerate(boundaries, start=1):
            dur = round(end - start, 3)
            raw_file = str((self.raw_chunks_dir / f"chunk_{idx:03d}.mp4").resolve())
            ws_dir = str((self.chunk_workspaces_dir / f"chunk_{idx:03d}").resolve())
            out_file = str((self.chunk_outputs_dir / f"chunk_{idx:03d}_vi.mp4").resolve())
            Path(ws_dir).mkdir(parents=True, exist_ok=True)

            chunks.append(ChunkItem(
                id=idx,
                start_sec=start,
                end_sec=end,
                duration_sec=dur,
                raw_chunk_file=raw_file,
                workspace_dir=ws_dir,
                output_file=out_file,
                status=ChunkStatus.PENDING
            ))

        now = time.time()
        self.data = ManifestData(
            video_name=self.video_name,
            video_stem=self.video_stem,
            source_video_path=str(self.video_path),
            total_duration_sec=total_duration_sec,
            target_chunk_duration_sec=target_chunk_duration_sec,
            total_chunks=len(chunks),
            created_at=now,
            updated_at=now,
            status="in_progress",
            final_output_path=final_output_path,
            chunks=chunks
        )
        self.save_manifest()
        return self.data

    def save_manifest(self):
        if not self.data:
            return
        self.data.updated_at = time.time()
        
        # Serialize to dict
        raw_chunks = []
        for c in self.data.chunks:
            c_dict = asdict(c)
            c_dict["status"] = c.status.value
            raw_chunks.append(c_dict)

        payload = {
            "video_name": self.data.video_name,
            "video_stem": self.data.video_stem,
            "source_video_path": self.data.source_video_path,
            "total_duration_sec": self.data.total_duration_sec,
            "target_chunk_duration_sec": self.data.target_chunk_duration_sec,
            "total_chunks": self.data.total_chunks,
            "created_at": self.data.created_at,
            "updated_at": self.data.updated_at,
            "status": self.data.status,
            "final_output_path": self.data.final_output_path,
            "chunks": raw_chunks
        }

        tmp_file = self.manifest_file.with_suffix(".tmp")
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
        tmp_file.replace(self.manifest_file)

    def update_chunk(
        self,
        chunk_id: int,
        status: Optional[ChunkStatus] = None,
        progress: Optional[float] = None,
        current_step: Optional[str] = None,
        error_message: Optional[str] = None
    ):
        if not self.data:
            return
        for c in self.data.chunks:
            if c.id == chunk_id:
                if status is not None:
                    c.status = status
                if progress is not None:
                    c.progress = max(0.0, min(100.0, progress))
                if current_step is not None:
                    c.current_step = current_step
                if error_message is not None:
                    c.error_message = error_message
                c.updated_at = time.time()
                break
        self.save_manifest()

    def get_pending_or_failed_chunks(self) -> List[ChunkItem]:
        """Returns chunks that still need execution."""
        if not self.data:
            return []
        pending = []
        for c in self.data.chunks:
            # Check if chunk output file exists and is valid
            out_p = Path(c.output_file)
            if c.status == ChunkStatus.COMPLETED and out_p.exists() and out_p.stat().st_size > 1024:
                continue
            pending.append(c)
        return pending

    def is_all_completed(self) -> bool:
        if not self.data or not self.data.chunks:
            return False
        for c in self.data.chunks:
            out_p = Path(c.output_file)
            if c.status != ChunkStatus.COMPLETED or not out_p.exists() or out_p.stat().st_size <= 1024:
                return False
        return True

    def calculate_overall_progress(self) -> float:
        if not self.data or not self.data.chunks:
            return 0.0
        total_p = sum(100.0 if c.status == ChunkStatus.COMPLETED else c.progress for c in self.data.chunks)
        return round(total_p / len(self.data.chunks), 1)

    def generate_concat_list(self) -> Path:
        """
        Creates concat_list.txt formatted for ffmpeg concat demuxer.
        """
        if not self.data:
            raise ValueError("Manifest not loaded")
        
        lines = []
        for c in self.data.chunks:
            out_p = Path(c.output_file).resolve()
            # FFmpeg concat requires escaped single quotes
            lines.append(f"file '{str(out_p)}'")

        with open(self.concat_list_file, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        return self.concat_list_file
