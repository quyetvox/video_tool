#!/usr/bin/env python3
import argparse
import json
import os
import sys
import warnings
from pathlib import Path
from typing import Any, Dict, List, Optional

# Suppress harmless third-party and multiprocessing runtime warnings
os.environ["PYTHONWARNINGS"] = "ignore"
os.environ["TOKENIZERS_PARALLELISM"] = "false"
os.environ["LOKY_MAX_CPU_COUNT"] = "1"
warnings.filterwarnings("ignore")

ROOT_DIR = Path(__file__).parent.parent.resolve()
ENGINE_DIR = Path(__file__).parent.resolve()
sys.path.insert(0, str(ENGINE_DIR))
sys.path.insert(0, str(ROOT_DIR))

# Ensure Homebrew and common paths are in PATH
for _p in ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin", os.path.expanduser("~/.local/bin")]:
    if os.path.exists(_p) and _p not in os.environ.get("PATH", "").split(os.pathsep):
        os.environ["PATH"] = f"{_p}{os.pathsep}{os.environ.get('PATH', '')}"

import yaml
from rich.console import Console
from rich.table import Table

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

from utils.process_guardian import install_guardian, cleanup_orphaned_processes

# Install automatic signal & child process killer
install_guardian()

console = Console()


def emit_json(data: dict):
    print(json.dumps(data, ensure_ascii=False), flush=True)


def load_env_file():
    os.environ.setdefault("PYTHONPYCACHEPREFIX", str((ROOT_DIR / ".venv" / "pycache").resolve()))
    os.environ.pop("MallocStackLogging", None)
    os.environ.pop("MallocScribble", None)

    env_file = ROOT_DIR / ".env"
    if env_file.exists():
        with open(env_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip().strip("'\""))


def load_config(config_path: Path) -> ConfigDict:
    load_env_file()
    default_config = {}
    if config_path.exists():
        with open(config_path, "r", encoding="utf-8") as f:
            default_config = yaml.safe_load(f) or {}
    return wrap_config(default_config)


def get_default_steps() -> List[Any]:
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


def build_pipeline(emit_json_mode: bool = False) -> PipelineRunner:
    steps = get_default_steps()
    return PipelineRunner(steps, emit_json=emit_json_mode)


def cmd_translate(args, base_config: Dict[str, Any]):
    # Support both translate <video_file> and translate <project_dir> <video_file>
    if getattr(args, "video_file", None):
        project_dir_arg = Path(args.input_video).resolve()
        input_path = Path(args.video_file).resolve()
    else:
        input_path = Path(args.input_video).resolve()
        project_dir_arg = None

    if not input_path.exists():
        err_msg = f"File not found: {input_path}"
        if getattr(args, "json", False):
            emit_json({"type": "error", "message": err_msg})
        else:
            console.print(f"[bold red]Error:[/bold red] {err_msg}")
        sys.exit(1)

    project_paths = ProjectManager.resolve_project_paths(project_dir_arg if project_dir_arg and project_dir_arg.is_dir() else input_path)
    config = project_paths.load_config()

    if getattr(args, "ocr_only", False):
        config["ocr_only"] = True
    elif getattr(args, "voice", False):
        config["ocr_only"] = False

    duration = getattr(args, "duration", None)
    
    # Check if video qualifies for Long Video Smart Chunking automatically
    from long_video_orchestrator import LongVideoOrchestrator
    from utils.smart_splitter import SmartSplitter

    video_duration = SmartSplitter.get_video_duration(input_path)
    file_size_bytes = input_path.stat().st_size
    emit_json_mode = getattr(args, "json", False)
    
    if (
        (duration is None or duration <= 0) and
        (video_duration > LongVideoOrchestrator.SINGLE_PASS_THRESHOLD_SEC or file_size_bytes > LongVideoOrchestrator.SINGLE_PASS_MAX_SIZE_BYTES)
    ):
        orchestrator = LongVideoOrchestrator(
            input_video=input_path,
            project_dir=project_paths.project_dir,
            config=config,
            emit_json=emit_json_mode
        )
        success = orchestrator.run()
        if not success:
            sys.exit(1)
        return

    if duration is not None and duration > 0:
        config["duration"] = float(duration)
        job_id = f"{ProjectManager.get_job_id(input_path)}_{int(duration)}s"
    else:
        config.pop("duration", None)
        job_id = ProjectManager.get_job_id(input_path)

    job_state = JobState(
        workspace=project_paths.workspace_dir,
        job_id=job_id,
        input_video=str(input_path),
        config=config
    )

    if emit_json_mode:
        emit_json({
            "type": "job_started",
            "job_id": job_id,
            "video_path": str(input_path),
            "project_path": str(project_paths.project_dir)
        })

    runner = build_pipeline(emit_json_mode=emit_json_mode)
    success = runner.run(job_state, config)

    encode_output = job_state.get_step_output("s14_encode") or {}
    output_file = encode_output.get("output_file", "")

    if emit_json_mode:
        emit_json({
            "type": "job_completed",
            "job_id": job_id,
            "success": success,
            "status": job_state.data.get("status", "completed" if success else "failed"),
            "output_file": output_file
        })
    else:
        if success:
            console.print(f"\n[bold green]✨ Video translated successfully![/bold green]")
            console.print(f"[bold cyan]Project:[/bold cyan] {project_paths.project_name}")
            console.print(f"[bold cyan]Job ID:[/bold cyan] {job_id}")
            console.print(f"[bold cyan]Output File:[/bold cyan] {output_file}")
        else:
            console.print(f"\n[bold red]❌ Translation failed for Job ID:[/bold red] {job_state.job_id}")
            console.print(f"You can resume execution with: [yellow]python main.py resume {job_state.job_id}[/yellow]")


def cmd_translate_long(args, base_config: Dict[str, Any]):
    from long_video_orchestrator import LongVideoOrchestrator
    
    if getattr(args, "video_file", None):
        project_dir_arg = Path(args.input_video).resolve()
        input_path = Path(args.video_file).resolve()
    else:
        input_path = Path(args.input_video).resolve()
        project_dir_arg = None

    if not input_path.exists():
        err_msg = f"File not found: {input_path}"
        if getattr(args, "json", False):
            emit_json({"type": "error", "message": err_msg})
        else:
            console.print(f"[bold red]Error:[/bold red] {err_msg}")
        sys.exit(1)

    orchestrator = LongVideoOrchestrator(
        input_video=input_path,
        project_dir=project_dir_arg,
        config=base_config,
        emit_json=getattr(args, "json", False),
        custom_chunk_minutes=getattr(args, "chunk_mins", None),
        custom_workers=getattr(args, "workers", None),
        force_chunking=getattr(args, "force_chunk", False)
    )
    if getattr(args, "ocr_only", False):
        orchestrator.config["ocr_only"] = True
    elif getattr(args, "voice", False):
        orchestrator.config["ocr_only"] = False

    success = orchestrator.run()
    if not success:
        sys.exit(1)


def resolve_job_target(target: str, project_dir_override: Path = None) -> tuple[Path, str, str]:
    if project_dir_override and project_dir_override.exists():
        ws_dir = project_dir_override / "workspace"
        clean_id = target if target.startswith("job_") else f"job_{target}"
        return ws_dir, clean_id, project_dir_override.name

    target = target.strip()
    assets_dir = ROOT_DIR / "resources"
    if not assets_dir.exists():
        assets_dir = ROOT_DIR / "assets"

    # Case 1: Target is an existing path or contains slashes
    if "/" in target or "\\" in target or Path(target).exists():
        path_target = Path(target).resolve()
        if path_target.is_file():
            proj_paths = ProjectManager.resolve_project_paths(path_target)
            job_id = ProjectManager.get_job_id(path_target)
            return proj_paths.workspace_dir, job_id, proj_paths.project_name
        elif path_target.is_dir():
            job_id = path_target.name
            proj_paths = ProjectManager.resolve_project_paths(path_target)
            return proj_paths.workspace_dir, job_id, proj_paths.project_name

    # Case 2: Project prefix syntax e.g. 'fashions:job_video_001' or 'fashions/job_video_001'
    if ":" in target:
        proj_name, j_id = target.split(":", 1)
        proj_dir = assets_dir / proj_name.strip()
        ws_dir = proj_dir / "workspace"
        clean_id = j_id.strip()
        actual_id = clean_id if clean_id.startswith("job_") else f"job_{clean_id}"
        return ws_dir, actual_id, proj_name.strip()

    # Case 3: Simple job ID search across projects
    clean_id = target if target.startswith("job_") else f"job_{target}"
    matches = []

    if assets_dir.exists():
        for proj in assets_dir.iterdir():
            if proj.is_dir():
                ws = proj / "workspace"
                if (ws / clean_id).exists():
                    matches.append((ws, clean_id, proj.name))
                elif (ws / target).exists():
                    matches.append((ws, target, proj.name))

    if len(matches) == 1:
        return matches[0]
    elif len(matches) > 1:
        return matches[0]
    elif matches:
        return matches[0]

    # Fallback to default workspace
    default_ws = assets_dir / "default" / "workspace"
    return default_ws, clean_id, "default"


def cmd_resume(args, base_config: Dict[str, Any]):
    proj_dir_arg = Path(args.project_dir).resolve() if getattr(args, "project_dir", None) and Path(args.project_dir).is_dir() else None
    workspace_dir, job_id, proj_name = resolve_job_target(args.job_id, project_dir_override=proj_dir_arg)
    job_dir = workspace_dir / job_id

    if not job_dir.exists():
        err_msg = f"Job directory not found: {job_dir}"
        if getattr(args, "json", False):
            emit_json({"type": "error", "message": err_msg})
        else:
            console.print(f"[bold red]Error:[/bold red] {err_msg}")
        sys.exit(1)

    project_paths = ProjectManager.resolve_project_paths(workspace_dir)
    config = project_paths.load_config()

    emit_json_mode = getattr(args, "json", False)
    if emit_json_mode:
        emit_json({
            "type": "job_started",
            "job_id": job_id,
            "project_path": str(project_paths.project_dir)
        })

    job_state = JobState(workspace=workspace_dir, job_id=job_id)
    runner = build_pipeline(emit_json_mode=emit_json_mode)
    success = runner.run(job_state, config)

    encode_output = job_state.get_step_output("s14_encode") or {}
    output_file = encode_output.get("output_file", "")

    if emit_json_mode:
        emit_json({
            "type": "job_completed",
            "job_id": job_id,
            "success": success,
            "status": job_state.data.get("status", "completed" if success else "failed"),
            "output_file": output_file
        })
    else:
        if success:
            console.print(f"\n[bold green]✨ Job resumed and completed successfully![/bold green]")
            console.print(f"[bold cyan]Project:[/bold cyan] {proj_name}")
            console.print(f"[bold cyan]Job ID:[/bold cyan] {job_id}")
            console.print(f"[bold cyan]Output File:[/bold cyan] {output_file}")


def cmd_status(args, base_config: Dict[str, Any]):
    proj_dir_arg = Path(args.project_dir).resolve() if getattr(args, "project_dir", None) and Path(args.project_dir).is_dir() else None
    workspace_dir, job_id, proj_name = resolve_job_target(args.job_id, project_dir_override=proj_dir_arg)
    job_dir = workspace_dir / job_id

    if not job_dir.exists():
        if getattr(args, "json", False):
            emit_json({
                "type": "status_result",
                "job_id": job_id,
                "status": "not_found",
                "steps": {}
            })
        else:
            console.print(f"[bold red]Error:[/bold red] Job directory not found: {job_dir}")
        sys.exit(1)

    job_state = JobState(workspace=workspace_dir, job_id=job_id)

    if getattr(args, "json", False):
        emit_json({
            "type": "status_result",
            "job_id": job_state.job_id,
            "status": job_state.data.get("status", "pending"),
            "steps": job_state.data.get("steps", {}),
            "video_info": job_state.data.get("video_info", {})
        })
    else:
        console.print(f"[bold cyan]Project:[/bold cyan] {proj_name}")
        console.print(f"[bold cyan]Job ID:[/bold cyan] {job_state.job_id}")
        console.print(f"[bold cyan]Status:[/bold cyan] {job_state.data.get('status')}")
        console.print(f"[bold cyan]Input Video:[/bold cyan] {job_state.data.get('input_video')}")

        table = Table(title="Pipeline Steps Status")
        table.add_column("Step ID", style="cyan")
        table.add_column("Status", style="magenta")
        table.add_column("Updated At", style="green")

        for step_id, info in job_state.data.get("steps", {}).items():
            table.add_row(step_id, info.get("status", "pending"), info.get("updated_at", "-"))

        console.print(table)


def cmd_run_step(args, base_config: Dict[str, Any]):
    proj_dir_arg = Path(args.project_dir).resolve() if getattr(args, "project_dir", None) and Path(args.project_dir).is_dir() else None
    workspace_dir, job_id, proj_name = resolve_job_target(args.job_id, project_dir_override=proj_dir_arg)
    job_dir = workspace_dir / job_id

    if not job_dir.exists():
        err_msg = f"Job directory not found: {job_dir}"
        if getattr(args, "json", False):
            emit_json({"type": "error", "message": err_msg})
        else:
            console.print(f"[bold red]Error:[/bold red] {err_msg}")
        sys.exit(1)

    project_paths = ProjectManager.resolve_project_paths(workspace_dir)
    config = project_paths.load_config()
    job_state = JobState(workspace=workspace_dir, job_id=job_id)

    step_id = args.step_id
    default_steps = get_default_steps()
    step = next((s for s in default_steps if s.step_id == step_id), None)
    if not step:
        err_msg = f"Step not found: {step_id}"
        if getattr(args, "json", False):
            emit_json({"type": "error", "message": err_msg})
        else:
            console.print(f"[bold red]Error:[/bold red] {err_msg}")
        sys.exit(1)

    if getattr(args, "json", False):
        emit_json({"type": "step_started", "job_id": job_id, "step_id": step_id})

    try:
        job_state.set_step_status(step_id, "running")
        output = step.run(job_state.job_dir, config, job_state)
        step.mark_done(job_state.job_dir)
        job_state.set_step_status(step_id, "done", output=output)

        if getattr(args, "json", False):
            emit_json({
                "type": "step_completed",
                "job_id": job_id,
                "step_id": step_id,
                "output": output
            })
        else:
            console.print(f"[bold green]✓ Step '{step_id}' completed successfully![/bold green]")
    except Exception as e:
        err_msg = str(e)
        job_state.set_step_status(step_id, "failed", error=err_msg)
        if getattr(args, "json", False):
            emit_json({
                "type": "error",
                "step_id": step_id,
                "message": err_msg
            })
        else:
            console.print(f"[bold red]❌ Step '{step_id}' failed:[/bold red] {err_msg}")
        sys.exit(1)


def cmd_delete_step(args, base_config: Dict[str, Any]):
    proj_dir_arg = Path(args.project_dir).resolve() if getattr(args, "project_dir", None) and Path(args.project_dir).is_dir() else None
    workspace_dir, job_id, proj_name = resolve_job_target(args.job_id, project_dir_override=proj_dir_arg)
    job_dir = workspace_dir / job_id

    if not job_dir.exists():
        err_msg = f"Job directory not found: {job_dir}"
        if getattr(args, "json", False):
            emit_json({"type": "error", "message": err_msg})
        else:
            console.print(f"[bold red]Error:[/bold red] {err_msg}")
        sys.exit(1)

    job_state = JobState(workspace=workspace_dir, job_id=job_id)
    affected = job_state.clear_step(args.step_id)

    if getattr(args, "json", False):
        emit_json({
            "type": "step_deleted",
            "job_id": job_id,
            "step_id": args.step_id,
            "affected_steps": affected,
            "status": "success"
        })
    else:
        console.print(f"[bold green]🗑️ Successfully cleared step '[cyan]{args.step_id}[/cyan]' cache for job '[cyan]{job_id}[/cyan]' in project '[cyan]{proj_name}[/cyan]'![/bold green]")
        console.print(f"[bold yellow]Invalidated & cleaned artifact steps:[/bold yellow] {', '.join(affected)}")


def cmd_delete_job(args, base_config: Dict[str, Any]):
    proj_dir_arg = Path(args.project_dir).resolve() if getattr(args, "project_dir", None) and Path(args.project_dir).is_dir() else None
    workspace_dir, job_id, proj_name = resolve_job_target(args.job_id, project_dir_override=proj_dir_arg)
    job_dir = workspace_dir / job_id

    if not job_dir.exists():
        err_msg = f"Job directory not found: {job_dir}"
        if getattr(args, "json", False):
            emit_json({"type": "error", "message": err_msg})
        else:
            console.print(f"[bold red]Error:[/bold red] {err_msg}")
        sys.exit(1)

    job_state = JobState(workspace=workspace_dir, job_id=job_id)
    job_state.delete_job()

    if getattr(args, "json", False):
        emit_json({
            "type": "job_deleted",
            "job_id": job_id,
            "status": "success"
        })
    else:
        console.print(f"[bold green]🗑️ Successfully deleted job workspace '[cyan]{job_id}[/cyan]' from project '[cyan]{proj_name}[/cyan]'![/bold green]")


def main():
    parser = argparse.ArgumentParser(description="Sub-Video AI Python Sidecar Engine CLI")
    parser.add_argument("--config", default="config.yaml", help="Path to config.yaml")
    parser.add_argument("--json", action="store_true", default=False, help="Emit structured JSON lines output for GUI bridges")

    subparsers = parser.add_subparsers(dest="command", required=True)

    # translate command
    p_trans = subparsers.add_parser("translate", help="Translate single video")
    p_trans.add_argument("input_video", help="Path to input video file (or project_dir)")
    p_trans.add_argument("video_file", nargs="?", default=None, help="Optional video file if first arg is project_dir")
    p_trans.add_argument("-t", "--t", "--duration", dest="duration", type=float, default=None, help="Process only first N seconds")
    p_trans.add_argument("--ocr-only", dest="ocr_only", action="store_true", default=None, help="Force OCR-only hardsub translation")
    p_trans.add_argument("--voice", dest="voice", action="store_true", default=None, help="Force full Voice AI translation with TTS voiceover")
    p_trans.add_argument("--json", action="store_true", default=False, help="Emit JSON lines")

    # translate-long command (Smart Chunker & Resumable Orchestrator)
    p_trans_long = subparsers.add_parser("translate-long", help="Translate long/large video using Smart Chunking & Resume")
    p_trans_long.add_argument("input_video", help="Path to input video file (or project_dir)")
    p_trans_long.add_argument("video_file", nargs="?", default=None, help="Optional video file if first arg is project_dir")
    p_trans_long.add_argument("--chunk-mins", type=float, default=None, help="Target duration per chunk in minutes (e.g. 5, 8, 10)")
    p_trans_long.add_argument("--workers", type=int, default=None, help="Maximum concurrent workers")
    p_trans_long.add_argument("--force-chunk", action="store_true", default=False, help="Force chunking even if video is short (<10 min)")
    p_trans_long.add_argument("--ocr-only", dest="ocr_only", action="store_true", default=None, help="Force OCR-only hardsub translation")
    p_trans_long.add_argument("--voice", dest="voice", action="store_true", default=None, help="Force full Voice AI translation with TTS voiceover")
    p_trans_long.add_argument("--json", action="store_true", default=False, help="Emit JSON lines")

    # resume command
    p_res = subparsers.add_parser("resume", help="Resume failed or interrupted job")
    p_res.add_argument("project_dir", nargs="?", default=None, help="Optional project directory")
    p_res.add_argument("job_id", help="ID of job to resume")
    p_res.add_argument("--json", action="store_true", default=False, help="Emit JSON lines")

    # status command
    p_stat = subparsers.add_parser("status", help="Check job status")
    p_stat.add_argument("project_dir", nargs="?", default=None, help="Optional project directory")
    p_stat.add_argument("job_id", help="ID of job to inspect")
    p_stat.add_argument("--json", action="store_true", default=False, help="Emit JSON lines")

    # run-step command
    p_step = subparsers.add_parser("run-step", help="Run a single step")
    p_step.add_argument("project_dir", nargs="?", default=None, help="Optional project directory")
    p_step.add_argument("job_id", help="ID of job")
    p_step.add_argument("step_id", help="Step ID to run (e.g. s08_translation)")
    p_step.add_argument("--json", action="store_true", default=False, help="Emit JSON lines")

    # delete-step command
    p_del_step = subparsers.add_parser("delete-step", help="Delete cache for a specific step and downstream steps")
    p_del_step.add_argument("project_dir", nargs="?", default=None, help="Optional project directory")
    p_del_step.add_argument("job_id", help="ID of job")
    p_del_step.add_argument("step_id", help="Step ID to invalidate (e.g. s08_translation)")
    p_del_step.add_argument("--json", action="store_true", default=False, help="Emit JSON lines")

    # delete-job command
    p_del_job = subparsers.add_parser("delete-job", help="Delete entire job workspace directory")
    p_del_job.add_argument("project_dir", nargs="?", default=None, help="Optional project directory")
    p_del_job.add_argument("job_id", help="ID of job to delete")
    p_del_job.add_argument("--json", action="store_true", default=False, help="Emit JSON lines")

    # cleanup-orphans command
    p_clean = subparsers.add_parser("cleanup-orphans", help="Find and kill dangling orphan Python/Demucs/FFmpeg processes")
    p_clean.add_argument("--json", action="store_true", default=False, help="Emit JSON lines")

    args = parser.parse_args()
    config = load_config(Path(args.config))

    # Auto-propagate root --json flag to subcommands
    if getattr(args, "json", False) is True:
        pass

    if args.command == "translate":
        cmd_translate(args, config)
    elif args.command == "translate-long":
        cmd_translate_long(args, config)
    elif args.command == "cleanup-orphans":
        count = cleanup_orphaned_processes()
        if getattr(args, "json", False):
            emit_json({"type": "cleanup_completed", "killed_count": count})
        else:
            console.print(f"[bold green]🧹 Đã dọn dẹp sạch {count} tiến trình mồ côi![/bold green]")
    elif args.command == "resume":
        cmd_resume(args, config)
    elif args.command == "status":
        cmd_status(args, config)
    elif args.command == "run-step":
        cmd_run_step(args, config)
    elif args.command == "delete-step":
        cmd_delete_step(args, config)
    elif args.command == "delete-job":
        cmd_delete_job(args, config)


if __name__ == "__main__":
    main()
