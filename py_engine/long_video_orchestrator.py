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
        self.video_name = self.input_video.name
        self.video_stem = self.input_video.stem
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

        # Long video configuration
        long_vid_cfg = self.config.get("long_video", {}) if isinstance(self.config, dict) else {}
        self.long_video_enabled = long_vid_cfg.get("enabled", False) if isinstance(long_vid_cfg, dict) else False
        configured_chunk_mins = float(long_vid_cfg.get("chunk_duration_min", 2.0)) if isinstance(long_vid_cfg, dict) else 2.0
        if self.custom_chunk_minutes is None:
            self.custom_chunk_minutes = configured_chunk_mins

        # Manifest Manager for isolated tracking
        self.manifest_mgr = ChunkManifestManager(
            workspace_root=self.project_paths.workspace_dir,
            video_path=self.input_video,
            cut_dir=self.project_paths.cut_dir,
            output_dir=self.project_paths.output_dir
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

    def _log_progress(self, chunk_id: int, total_chunks: int, chunk_p: float, overall_p: float, current_step: str, raw_chunk_file: str = ""):
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
                "current_step": current_step,
                "raw_chunk_file": raw_chunk_file
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
        is_long_mode_active = self.force_chunking or self.long_video_enabled
        target_chunk_sec = self.custom_chunk_minutes * 60.0

        if not is_long_mode_active and total_duration <= self.SINGLE_PASS_THRESHOLD_SEC and file_size_bytes <= self.SINGLE_PASS_MAX_SIZE_BYTES:
            self._log_info(f"Video is under {self.SINGLE_PASS_THRESHOLD_SEC/60:.0f} mins and {self.SINGLE_PASS_MAX_SIZE_BYTES/(1024**3):.1f}GB. Running in Standard Single-Pass Mode.")
            return self._run_single_pass()

        trigger_reason = []
        if is_long_mode_active:
            trigger_reason.append(f"Chế độ Video Dài đã bật (cắt mỗi {self.custom_chunk_minutes:.1f} phút)")
        if total_duration > self.SINGLE_PASS_THRESHOLD_SEC:
            trigger_reason.append(f"thời lượng dài {duration_min} phút (> 10 phút)")
        if file_size_bytes > self.SINGLE_PASS_MAX_SIZE_BYTES:
            trigger_reason.append(f"dung lượng lớn {file_size_mb} MB (> 1.0 GB)")

        self._log_info(f"⚡ Kích hoạt Chế Độ Phân Đoạn Thông Minh (Smart Chunking Mode) do: {', '.join(trigger_reason)}.")

        # Destination output path
        output_dir = self.project_paths.output_dir
        output_dir.mkdir(parents=True, exist_ok=True)
        final_video_name = f"{self.input_video.stem}_vi{self.input_video.suffix}"
        final_output_path = str((output_dir / final_video_name).resolve())

        # 3. Phase 1: Smart Boundary Calculation
        effective_chunk_duration_sec = target_chunk_sec if is_long_mode_active else alloc.recommended_chunk_duration_sec
        boundaries = SmartSplitter.compute_chunk_boundaries(
            video_path=self.input_video,
            total_duration=total_duration,
            target_chunk_duration_sec=effective_chunk_duration_sec
        )

        manifest_data = self.manifest_mgr.load_or_create_manifest(
            boundaries=boundaries,
            total_duration_sec=total_duration,
            target_chunk_duration_sec=effective_chunk_duration_sec,
            final_output_path=final_output_path
        )

        total_chunks = len(manifest_data.chunks)
        self._log_info(f"Divided into {total_chunks} smart chunks (Avg: {effective_chunk_duration_sec/60:.1f} mins/chunk).")

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
                        "status": c.status.value,
                        "raw_chunk_file": c.raw_chunk_file,
                        "output_file": c.output_file
                    } for c in manifest_data.chunks
                ]
            })

        # 4. Phase 1b: Split Raw Chunks on-demand (if not already created)
        for chunk in manifest_data.chunks:
            raw_p = Path(chunk.raw_chunk_file)
            if not raw_p.exists() or raw_p.stat().st_size <= 1024:
                self._log_info(f"Splitting Chunk {chunk.id}/{total_chunks} ({chunk.start_sec}s -> {chunk.end_sec}s) vào {raw_p.name}...")
                ok = SmartSplitter.split_chunk_frame_accurate(
                    input_video=self.input_video,
                    start_sec=chunk.start_sec,
                    end_sec=chunk.end_sec,
                    output_chunk_path=raw_p
                )
                if not ok:
                    self._log_info(f"Failed to split raw chunk {chunk.id}", step="error")
                    self.manifest_mgr.update_chunk(chunk.id, status=ChunkStatus.FAILED, error_message="Split failed")
                    return False
            else:
                self._log_info(f"Chunk {chunk.id}/{total_chunks} đã có sẵn trong folder cut/ ({raw_p.name}), dùng lại cache.")

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
            self._log_progress(chunk.id, total_chunks, 100.0, overall_p, "chunk_completed", raw_chunk_file=str(chunk.raw_chunk_file))

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
        """Executes the standard 15-step pipeline on a chunk using standard flat workspace."""
        chunk_stem = Path(chunk.raw_chunk_file).stem
        chunk_job_id = chunk.job_id or f"job_{chunk_stem}"
        dest_out = Path(chunk.output_file)

        # Flat workspace directory directly inside project_paths.workspace_dir
        # e.g. resources/<project>/workspace/job_video_020_part_001
        job_state = JobState(
            workspace=self.project_paths.workspace_dir,
            job_id=chunk_job_id,
            input_video=chunk.raw_chunk_file,
            config=self.config
        )
        chunk_ws = job_state.job_dir
        chunk_ws.mkdir(parents=True, exist_ok=True)

        # Prepare chunk config pointing to the official project output folder
        raw_cfg = copy.deepcopy(dict(self.config))
        raw_cfg.pop("duration", None)
        raw_cfg["output_dir"] = str(self.project_paths.output_dir)
        # Strictly enforce 100% sequential execution for chunk pipeline: No background threads, no dual-track races
        raw_cfg["enable_dual_track"] = False

        # Chunk language inheritance: pass down detected language from manifest if available
        if not raw_cfg.get("source_lang") and self.manifest_mgr.data and getattr(self.manifest_mgr.data, "detected_language", None):
            inherited_lang = self.manifest_mgr.data.detected_language
            raw_cfg["source_lang"] = inherited_lang
            raw_cfg["detected_language"] = inherited_lang
            self._log_info(f"[Chunk {chunk.id}/{total_chunks}] Inheriting source language from manifest: '{inherited_lang}'")

        chunk_config = wrap_config(raw_cfg)

        steps = get_default_pipeline_steps()

        # Emit chunk processing started
        self._log_progress(chunk.id, total_chunks, 0.0, self.manifest_mgr.calculate_overall_progress(), "started", raw_chunk_file=str(chunk.raw_chunk_file))

        def on_chunk_log(step_id: str, message: str, level: str = "info"):
            self._log_info(f"[Chunk {chunk.id}/{total_chunks}] [{step_id}] {message}", step=step_id)

        def on_step_status(step_id: str, status: str, progress: Optional[float]):
            p = progress or 0.0
            self.manifest_mgr.update_chunk(chunk.id, progress=p, current_step=step_id)
            overall_p = self.manifest_mgr.calculate_overall_progress()
            self._log_progress(chunk.id, total_chunks, p, overall_p, step_id, raw_chunk_file=str(chunk.raw_chunk_file))
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

        # Record detected language from s05_asr into manifest for subsequent chunks
        s05_out = job_state.get_step_output("s05_asr") or {}
        det_lang = s05_out.get("detected_language")
        if det_lang and self.manifest_mgr.data and not getattr(self.manifest_mgr.data, "detected_language", None):
            self.manifest_mgr.update_detected_language(det_lang)
            self._log_info(f"Recorded detected source language '{det_lang}' into manifest for subsequent chunks.")


        # Locate s14_encode output and ensure dest_out exists
        s14_out = job_state.get_step_output("s14_encode") or {}
        produced_file = s14_out.get("output_file") or s14_out.get("workspace_output_file")
        if not produced_file or not Path(produced_file).exists():
            candidates = list(chunk_ws.glob("*.mp4"))
            if candidates:
                produced_file = str(candidates[0])
            elif dest_out.exists() and dest_out.stat().st_size > 1024:
                produced_file = str(dest_out)
            else:
                return False

        dest_out.parent.mkdir(parents=True, exist_ok=True)
        if Path(produced_file).resolve() != dest_out.resolve():
            shutil.copy2(produced_file, dest_out)
        return dest_out.exists() and dest_out.stat().st_size > 1024

    def _cleanup_intermediate_chunks(self):
        """Deletes temporary video renders while preserving clean_video.mp4 for fast resume."""
        for chunk in self.manifest_mgr.data.chunks:
            try:
                ws = Path(chunk.workspace_dir)
                if ws.exists():
                    for vid in ws.rglob("*.mp4"):
                        # Keep clean_video.mp4 and demux/video_stream.mp4 to allow fast re-render and resume
                        if vid.name in ("clean_video.mp4", "video_stream.mp4") or vid.parent.name == "demux":
                            continue
                        vid.unlink(missing_ok=True)
            except Exception:
                pass

    def _merge_subtitles_lossless(self) -> bool:
        """Merges all chunks' subtitles into a unified master subtitle file for the parent video."""
        master_job_id = ProjectManager.get_job_id(self.input_video)
        master_job_dir = self.project_paths.workspace_dir / master_job_id
        master_job_dir.mkdir(parents=True, exist_ok=True)

        if not self.manifest_mgr.data:
            if self.manifest_mgr.manifest_file.exists():
                self.manifest_mgr.load_or_create_manifest([], 0.0, 0.0)
            else:
                return False

        if not self.manifest_mgr.data or not self.manifest_mgr.data.chunks:
            return False

        merged_subtitles = []
        global_idx = 0

        for chunk in self.manifest_mgr.data.chunks:
            chunk_job_id = chunk.job_id or f"job_{Path(chunk.raw_chunk_file).stem}"
            chunk_job_dir = self.project_paths.workspace_dir / chunk_job_id

            timing_file = chunk_job_dir / "s08c_timing.json"
            trans_file = chunk_job_dir / "s08_translation.json"
            sub_src = timing_file if timing_file.exists() else (trans_file if trans_file.exists() else None)

            if not sub_src:
                continue

            try:
                with open(sub_src, "r", encoding="utf-8") as f:
                    chunk_subs = json.load(f)

                offset = float(chunk.start_sec)
                for item in chunk_subs:
                    item_copy = dict(item)
                    if "start" in item_copy:
                        item_copy["start"] = round(float(item_copy["start"]) + offset, 3)
                    if "end" in item_copy:
                        item_copy["end"] = round(float(item_copy["end"]) + offset, 3)
                    item_copy["index"] = global_idx
                    global_idx += 1
                    merged_subtitles.append(item_copy)
            except Exception as e:
                logger.warning(f"Failed to merge subtitles for chunk {chunk.id}: {e}")

        if merged_subtitles:
            merged_subtitles.sort(key=lambda x: x.get("start", 0.0))
            # 1. Save master s08c_timing.json in master job directory
            master_timing = master_job_dir / "s08c_timing.json"
            with open(master_timing, "w", encoding="utf-8") as f:
                json.dump(merged_subtitles, f, ensure_ascii=False, indent=2)

            # 2. Save master s08_translation.json
            master_trans = master_job_dir / "s08_translation.json"
            with open(master_trans, "w", encoding="utf-8") as f:
                json.dump(merged_subtitles, f, ensure_ascii=False, indent=2)

            # 3. Export unified SRT to master job workspace directory (never to output_dir to prevent media player auto-loading)
            master_srt = master_job_dir / "subtitles_vi.srt"
            self._export_srt(merged_subtitles, master_srt)
            # Also keep subtitles.srt for backward compatibility
            self._export_srt(merged_subtitles, master_job_dir / "subtitles.srt")

            # Clean up any lingering srt file in output_dir to avoid player collision
            v_stem = getattr(self, "video_stem", None) or self.input_video.stem
            lingering_srt = self.project_paths.output_dir / f"{v_stem}_vi.srt"
            if lingering_srt.exists():
                try:
                    lingering_srt.unlink(missing_ok=True)
                except Exception:
                    pass

            self._log_info(f"✔ Đã gộp và xuất phụ đề master cho video cha ({len(merged_subtitles)} câu) -> {master_timing.name}")
            return True
        return False

    @staticmethod
    def _export_srt(subtitles: list, out_path: Path):
        def _fmt_time(sec: float) -> str:
            hrs = int(sec // 3600)
            mins = int((sec % 3600) // 60)
            secs = int(sec % 60)
            ms = int(round((sec - int(sec)) * 1000))
            return f"{hrs:02d}:{mins:02d}:{secs:02d},{ms:03d}"

        lines = []
        for i, sub in enumerate(subtitles, 1):
            s = _fmt_time(sub.get("start", 0.0))
            e = _fmt_time(sub.get("end", 0.0))
            txt = str(sub.get("text_vi") or sub.get("translated_text") or sub.get("translation") or sub.get("vi") or sub.get("text") or "").strip()
            lines.append(f"{i}\n{s} --> {e}\n{txt}\n")

        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text("\n".join(lines), encoding="utf-8")

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
                # Merge subtitles for the parent video
                self._merge_subtitles_lossless()
                # Clean up redundant temp mp4 files
                self._cleanup_intermediate_chunks()
            return merged_ok
        except subprocess.CalledProcessError as e:
            logger.error(f"FFmpeg concat merge failed: {e.stderr}")
            return False

    @classmethod
    def merge_manifest_video(cls, video_or_project_path: Path | str, video_path: Optional[Path | str] = None, emit_json: bool = False) -> bool:
        """Utility to re-merge a long video and its subtitles from manifest on demand."""
        resolved = Path(video_or_project_path).resolve()
        if resolved.is_file() and resolved.name == "manifest.json":
            with open(resolved, "r", encoding="utf-8") as f:
                data = json.load(f)
            src_video = Path(data.get("source_video_path") or "")
            project_dir = resolved.parent.parent.parent.parent
            orchestrator = cls(input_video=src_video, project_dir=project_dir, emit_json=emit_json)
            final_out = data.get("final_output_path") or str(orchestrator.project_paths.output_dir / f"{src_video.stem}_vi.mp4")
            return orchestrator._merge_chunks_lossless(final_out)
        else:
            target_vid = Path(video_path or resolved).resolve()
            proj_dir = resolved if resolved.is_dir() else target_vid.parent.parent
            orchestrator = cls(input_video=target_vid, project_dir=proj_dir, emit_json=emit_json)
            if orchestrator.manifest_mgr.manifest_file.exists():
                orchestrator.manifest_mgr.load_or_create_manifest([], 0.0, 0.0)
                final_out = orchestrator.manifest_mgr.data.final_output_path or str(orchestrator.project_paths.output_dir / f"{target_vid.stem}_vi.mp4")
                return orchestrator._merge_chunks_lossless(final_out)
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
