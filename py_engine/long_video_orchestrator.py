#!/usr/bin/env python3
"""
Long Video Smart Chunker & Resumable Pipeline Orchestrator.
Coordinates the entire lifecycle for long/large video translation:
1. Resource Guard & Auto Safety Allocation (RAM <= 70% cap).
2. Smart Splitter (Triple-lock: Silence + Keyframe aligned -c copy).
3. Manifest-based Resumable Execution (Zero lost progress on crash/disconnect).
4. Lossless Concat Merge to final project output.
"""

import copy
import json
import logging
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

from rich.console import Console

# Add parent directories to sys.path
ROOT_DIR = Path(__file__).parent.parent.resolve()
ENGINE_DIR = Path(__file__).parent.resolve()
if str(ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(ENGINE_DIR))
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from core.config_adapter import wrap_config, ConfigDict
from core.job_state import JobState
from core.pipeline_runner import PipelineRunner
from core.project_manager import ProjectManager
from steps.s01_probe import StepProbe
from steps.s02_demux import StepDemux
from steps.s03_subtitle_detect import StepSubtitleDetect
from steps.s04_audio_separate import StepAudioSeparate
from steps.s05_asr import StepASR
from steps.s05b_gender_detect import StepGenderDetect
from steps.s06_ocr import StepOCR
from steps.s07_transcript_merge import StepTranscriptMerge
from steps.s08_translation import StepTranslation
from steps.s08b_metadata_gen import StepMetadataGen
from steps.s08c_timing import StepSubtitleTiming
from steps.s09_subtitle_gen import StepSubtitleGen
from steps.s10_inpaint import StepInpaint
from steps.s11_subtitle_render import StepSubtitleRender
from steps.s12_tts import StepTTS
from steps.s13_audio_mix import StepAudioMix
from steps.s14_encode import StepEncode
from utils.chunk_manifest import ChunkItem, ChunkManifestManager, ChunkStatus
from utils.resource_guard import ResourceGuard
from utils.smart_splitter import SmartSplitter

console = Console()
logger = logging.getLogger("sub_video.orchestrator")


def get_default_pipeline_steps() -> List[Any]:
    return [
        StepProbe(),
        StepDemux(),
        StepSubtitleDetect(),
        StepAudioSeparate(),
        StepASR(),
        StepGenderDetect(),
        StepOCR(),
        StepTranscriptMerge(),
        StepTranslation(),
        StepMetadataGen(),
        StepSubtitleTiming(),
        StepSubtitleGen(),
        StepInpaint(),
        StepSubtitleRender(),
        StepTTS(),
        StepAudioMix(),
        StepEncode()
    ]


class LongVideoOrchestrator:
    # Thresholds: Videos exceeding either duration or file size will trigger Smart Chunking
    SINGLE_PASS_THRESHOLD_SEC: float = 600.0           # 10 minutes
    SINGLE_PASS_MAX_SIZE_BYTES: int = 1024 * 1024 * 1024  # 1.0 GB

    def __init__(
        self,
        input_video: Path | str,
        project_dir: Optional[Path | str] = None,
        config: Optional[Dict[str, Any]] = None,
        emit_json: bool = False,
        custom_chunk_minutes: Optional[float] = None,
        custom_workers: Optional[int] = None,
        force_chunking: bool = False,
        on_log: Optional[Callable[[str, str], None]] = None,
        on_progress: Optional[Callable[[int, int, float, float, str], None]] = None
    ):
        self.input_video = Path(input_video).resolve()
        self.project_paths = ProjectManager.resolve_project_paths(
            Path(project_dir).resolve() if project_dir else self.input_video
        )
        self.config = config or self.project_paths.load_config()
        self.emit_json = emit_json
        self.custom_chunk_minutes = custom_chunk_minutes
        self.custom_workers = custom_workers
        self.force_chunking = force_chunking
        self.on_log = on_log
        self.on_progress = on_progress

        # Manifest Manager for isolated tracking
        self.manifest_mgr = ChunkManifestManager(
            workspace_root=self.project_paths.workspace_dir,
            video_path=self.input_video
        )

    def _emit(self, data: dict):
        if self.emit_json:
            print(json.dumps(data, ensure_ascii=False), flush=True)

    def _log_info(self, message: str, step: str = "orchestrator"):
        formatted_msg = f"[LongVideo] {message}" if not message.startswith("[LongVideo]") else message
        if self.on_log:
            self.on_log(step, formatted_msg)
        elif self.emit_json:
            self._emit({
                "type": "log",
                "step_id": step,
                "message": formatted_msg,
                "level": "info"
            })
        else:
            console.print(f"[bold cyan][LongVideo][/bold cyan] {message}")

    def _log_progress(self, chunk_id: int, total_chunks: int, chunk_p: float, overall_p: float, current_step: str):
        if self.on_progress:
            self.on_progress(chunk_id, total_chunks, chunk_p, overall_p, current_step)
        if self.emit_json:
            self._emit({
                "type": "long_video_progress",
                "video_name": self.input_video.name,
                "chunk_id": chunk_id,
                "total_chunks": total_chunks,
                "chunk_progress": chunk_p,
                "overall_progress": overall_p,
                "current_step": current_step
            })

    def run(self) -> bool:
        if not self.input_video.exists():
            self._log_info(f"Input video not found: {self.input_video}", step="error")
            return False

        # 1. Resource Guard Check
        alloc = ResourceGuard.calculate_allocation(
            max_ram_usage_gb=self.config.get("max_ram_usage_gb"),
            custom_workers=self.custom_workers,
            custom_chunk_minutes=self.custom_chunk_minutes
        )

        total_duration = SmartSplitter.get_video_duration(self.input_video)
        if total_duration <= 0:
            self._log_info(f"Failed to probe video duration for {self.input_video}", step="error")
            return False

        file_size_bytes = self.input_video.stat().st_size
        file_size_mb = round(file_size_bytes / (1024 * 1024), 1)
        duration_min = round(total_duration / 60.0, 1)
        
        self._log_info(
            f"Video: '{self.input_video.name}' | Size: {file_size_mb} MB | Duration: {duration_min} mins | "
            f"System RAM: {alloc.total_ram_gb}GB (Avail: {alloc.available_ram_gb}GB, Safe Cap: {alloc.max_allowed_ram_gb}GB) | "
            f"Safe Workers: {alloc.safe_workers}"
        )

        # 2. Determine Single-Pass vs Chunking Mode
        # Only single-pass if both duration <= 10 min AND file_size <= 1.0 GB
        if not self.force_chunking and total_duration <= self.SINGLE_PASS_THRESHOLD_SEC and file_size_bytes <= self.SINGLE_PASS_MAX_SIZE_BYTES:
            self._log_info(f"Video is under {self.SINGLE_PASS_THRESHOLD_SEC/60:.0f} mins and {self.SINGLE_PASS_MAX_SIZE_BYTES/(1024**3):.1f}GB. Running in Standard Single-Pass Mode.")
            return self._run_single_pass()

        trigger_reason = []
        if total_duration > self.SINGLE_PASS_THRESHOLD_SEC:
            trigger_reason.append(f"thời lượng dài {duration_min} phút (> 10 phút)")
        if file_size_bytes > self.SINGLE_PASS_MAX_SIZE_BYTES:
            trigger_reason.append(f"dung lượng lớn {file_size_mb} MB (> 1.0 GB)")
        if self.force_chunking:
            trigger_reason.append("yêu cầu bắt buộc từ người dùng")

        self._log_info(f"⚡ Kích hoạt Chế Độ Phân Đoạn Thông Minh (Smart Chunking Mode) do: {', '.join(trigger_reason)}.")

        # Destination output path
        output_dir = self.project_paths.output_dir
        output_dir.mkdir(parents=True, exist_ok=True)
        final_video_name = f"{self.input_video.stem}_vi{self.input_video.suffix}"
        final_output_path = str((output_dir / final_video_name).resolve())

        # 3. Phase 1: Smart Boundary Calculation
        boundaries = SmartSplitter.compute_chunk_boundaries(
            video_path=self.input_video,
            total_duration=total_duration,
            target_chunk_duration_sec=alloc.recommended_chunk_duration_sec
        )

        manifest_data = self.manifest_mgr.load_or_create_manifest(
            boundaries=boundaries,
            total_duration_sec=total_duration,
            target_chunk_duration_sec=alloc.recommended_chunk_duration_sec,
            final_output_path=final_output_path
        )

        total_chunks = len(manifest_data.chunks)
        self._log_info(f"Divided into {total_chunks} smart chunks (Avg: {alloc.recommended_chunk_duration_sec/60:.1f} mins/chunk).")

        # Emit GUI Indicator payload
        if self.emit_json:
            self._emit({
                "type": "long_video_initialized",
                "video_name": self.input_video.name,
                "total_duration_sec": total_duration,
                "total_chunks": total_chunks,
                "chunk_details": [
                    {
                        "id": c.id,
                        "start_sec": c.start_sec,
                        "end_sec": c.end_sec,
                        "duration_sec": c.duration_sec,
                        "status": c.status.value
                    } for c in manifest_data.chunks
                ]
            })

        # 4. Phase 1b: Split Raw Chunks on-demand (if not already created)
        for chunk in manifest_data.chunks:
            raw_p = Path(chunk.raw_chunk_file)
            if not raw_p.exists() or raw_p.stat().st_size == 0:
                self._log_info(f"Splitting Chunk {chunk.id}/{total_chunks} ({chunk.start_sec}s -> {chunk.end_sec}s)...")
                ok = SmartSplitter.split_chunk_lossless(
                    input_video=self.input_video,
                    start_sec=chunk.start_sec,
                    end_sec=chunk.end_sec,
                    output_chunk_path=raw_p
                )
                if not ok:
                    self._log_info(f"Failed to split raw chunk {chunk.id}", step="error")
                    self.manifest_mgr.update_chunk(chunk.id, status=ChunkStatus.FAILED, error_message="Split failed")
                    return False

        # 5. Phase 2: Execute Chunks with Smart Checkpoint & Step-Level Resume
        for chunk in manifest_data.chunks:
            # Memory health check before processing
            if not ResourceGuard.check_memory_threshold(alloc.max_allowed_ram_gb):
                self._log_info("System RAM low. Waiting 5s for resource stabilization...")
                time.sleep(5)

            self._log_info(f"Processing Chunk {chunk.id}/{total_chunks} (Duration: {chunk.duration_sec}s)...")
            self.manifest_mgr.update_chunk(chunk.id, status=ChunkStatus.PROCESSING)

            chunk_success = self._run_chunk_pipeline(chunk, total_chunks)
            if not chunk_success:
                self._log_info(f"❌ Chunk {chunk.id}/{total_chunks} FAILED. Execution paused.", step="error")
                self.manifest_mgr.update_chunk(
                    chunk.id,
                    status=ChunkStatus.FAILED,
                    error_message=f"Pipeline error on step {chunk.current_step}"
                )
                return False

            self.manifest_mgr.update_chunk(chunk.id, status=ChunkStatus.COMPLETED, progress=100.0)
            overall_p = self.manifest_mgr.calculate_overall_progress()
            self._log_info(f"✔ Chunk {chunk.id}/{total_chunks} COMPLETED! (Overall Progress: {overall_p}%)")
            self._log_progress(chunk.id, total_chunks, 100.0, overall_p, "chunk_completed")

        # 6. Phase 3: Lossless Concat Merge
        if not self.manifest_mgr.is_all_completed():
            self._log_info("Not all chunks completed. Cannot merge final video.", step="error")
            return False

        self._log_info(f"Merging {total_chunks} chunks into final video: {final_output_path}...")
        merge_ok = self._merge_chunks_lossless(final_output_path)
        if not merge_ok:
            self._log_info("Failed to merge final video chunks.", step="error")
            return False

        self.manifest_mgr.data.status = "completed"
        self.manifest_mgr.save_manifest()

        self._log_info(f"🎉 SUCCESS! Long video fully translated and saved to: {final_output_path}")
        if self.emit_json:
            self._emit({
                "type": "long_video_completed",
                "video_name": self.input_video.name,
                "output_file": final_output_path,
                "total_chunks": total_chunks,
                "total_duration_sec": total_duration
            })
        return True

    def _run_chunk_pipeline(self, chunk: ChunkItem, total_chunks: int) -> bool:
        """Executes the standard 15-step pipeline on an isolated chunk."""
        chunk_ws = Path(chunk.workspace_dir)
        chunk_ws.mkdir(parents=True, exist_ok=True)
        chunk_job_id = f"job_chunk_{chunk.id:03d}"

        # Prepare isolated chunk config
        raw_cfg = copy.deepcopy(dict(self.config))
        raw_cfg.pop("duration", None)
        # Prevent s14_encode from moving intermediate chunks to the project's official output folder
        raw_cfg["output_dir"] = ""
        chunk_config = wrap_config(raw_cfg)

        job_state = JobState(
            workspace=chunk_ws,
            job_id=chunk_job_id,
            input_video=chunk.raw_chunk_file,
            config=chunk_config
        )

        steps = get_default_pipeline_steps()

        def on_chunk_log(step_id: str, message: str, level: str = "info"):
            self._log_info(f"[Chunk {chunk.id}/{total_chunks}] [{step_id}] {message}", step=step_id)

        def on_step_status(step_id: str, status: str, progress: Optional[float]):
            p = progress or 0.0
            self.manifest_mgr.update_chunk(chunk.id, progress=p, current_step=step_id)
            overall_p = self.manifest_mgr.calculate_overall_progress()
            self._log_progress(chunk.id, total_chunks, p, overall_p, step_id)
            if status == "running" or status == "done":
                self._log_info(f"[Chunk {chunk.id}/{total_chunks}] [{step_id}] Trạng thái: {status} ({p:.0f}%) -> Tổng thể: {overall_p:.1f}%", step=step_id)

        runner = PipelineRunner(
            steps=steps,
            on_log=on_chunk_log,
            on_step_status=on_step_status,
            emit_json=False  # Handled at orchestrator level
        )

        success = runner.run(job_state, chunk_config)
        if not success:
            return False

        # Locate s14_encode output and copy to chunk_outputs
        s14_out = job_state.get_step_output("s14_encode") or {}
        produced_file = s14_out.get("output_file") or s14_out.get("workspace_output_file")
        if not produced_file or not Path(produced_file).exists():
            # Fallback check inside chunk workspace
            candidates = list(chunk_ws.glob("*.mp4"))
            if candidates:
                produced_file = str(candidates[0])
            else:
                return False

        # Copy to official chunk output file inside workspace/chunks
        dest_out = Path(chunk.output_file)
        dest_out.parent.mkdir(parents=True, exist_ok=True)
        if str(produced_file) != str(dest_out):
            shutil.copy2(produced_file, dest_out)
        return dest_out.exists() and dest_out.stat().st_size > 1024

    def _cleanup_intermediate_chunks(self):
        """Deletes temporary video chunks and raw split files to free up disk space."""
        self._log_info("🧹 Đang dọn dẹp các video chunk trung gian để giải phóng dung lượng ổ cứng...")
        for chunk in self.manifest_mgr.data.chunks:
            # 1. Xóa file raw chunk cắt ban đầu
            try:
                raw_p = Path(chunk.raw_chunk_file)
                if raw_p.exists():
                    raw_p.unlink(missing_ok=True)
            except Exception:
                pass
            # 2. Xóa file output chunk tạm
            try:
                out_p = Path(chunk.output_file)
                if out_p.exists():
                    out_p.unlink(missing_ok=True)
            except Exception:
                pass
            # 3. Xóa các video mp4 trung gian trong workspace từng chunk
            try:
                ws = Path(chunk.workspace_dir)
                if ws.exists():
                    for vid in ws.rglob("*.mp4"):
                        vid.unlink(missing_ok=True)
            except Exception:
                pass

        # 4. Xóa toàn bộ video chunk tạm trong chunk_workspaces/output và chunk_outputs
        try:
            chunks_base = self.manifest_mgr.chunks_base_dir
            for extra_dir in [chunks_base / "chunk_workspaces" / "output", chunks_base / "chunk_outputs", chunks_base / "raw_chunks"]:
                if extra_dir.exists():
                    for vid in extra_dir.glob("*.mp4"):
                        vid.unlink(missing_ok=True)
        except Exception:
            pass

    def _merge_chunks_lossless(self, final_output_path: str) -> bool:
        concat_list_p = self.manifest_mgr.generate_concat_list()
        dest = Path(final_output_path)
        dest.parent.mkdir(parents=True, exist_ok=True)

        cmd = [
            "ffmpeg", "-y",
            "-f", "concat",
            "-safe", "0",
            "-i", str(concat_list_p),
            "-c", "copy",
            str(dest)
        ]
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, check=True)
            merged_ok = dest.exists() and dest.stat().st_size > 1024
            if merged_ok:
                # Automatically clean up intermediate chunk mp4 files to free up GBs of disk space
                self._cleanup_intermediate_chunks()
            return merged_ok
        except subprocess.CalledProcessError as e:
            logger.error(f"FFmpeg concat merge failed: {e.stderr}")
            return False

    def _run_single_pass(self) -> bool:
        """Fallback for short videos."""
        job_id = ProjectManager.get_job_id(self.input_video)
        job_state = JobState(
            workspace=self.project_paths.workspace_dir,
            job_id=job_id,
            input_video=str(self.input_video),
            config=self.config
        )
        runner = PipelineRunner(
            steps=get_default_pipeline_steps(),
            emit_json=self.emit_json
        )
        return runner.run(job_state, self.config)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Long Video Smart Chunker Orchestrator")
    parser.add_argument("input_video", help="Path to input video file")
    parser.add_argument("--project", "-p", help="Optional project directory path")
    parser.add_argument("--chunk-mins", type=float, help="Target duration per chunk in minutes (e.g. 5, 8, 10)")
    parser.add_argument("--workers", type=int, help="Maximum concurrent workers")
    parser.add_argument("--force-chunk", action="store_true", help="Force chunking even if video is short (<10 min)")
    parser.add_argument("--json", action="store_true", help="Emit structured JSON progress messages")
    parser.add_argument("--ocr-only", action="store_true", help="OCR subtitle translation mode only")

    args = parser.parse_args()

    orchestrator = LongVideoOrchestrator(
        input_video=args.input_video,
        project_dir=args.project,
        emit_json=args.json,
        custom_chunk_minutes=args.chunk_mins,
        custom_workers=args.workers,
        force_chunking=args.force_chunk
    )
    if args.ocr_only:
        orchestrator.config["ocr_only"] = True

    success = orchestrator.run()
    sys.exit(0 if success else 1)
