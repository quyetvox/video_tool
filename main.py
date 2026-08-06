#!/usr/bin/env python3
import argparse
import os
import sys
from pathlib import Path
from typing import Any, Dict

ROOT_DIR = Path(__file__).parent.resolve()
sys.path.insert(0, str(ROOT_DIR / "lib"))
sys.path.insert(0, str(ROOT_DIR))

import yaml
from rich.console import Console
from rich.table import Table

from lib.core.job_state import JobState
from lib.core.pipeline_runner import PipelineRunner
from lib.core.project_manager import ProjectManager
from lib.steps.s01_probe import StepProbe
from lib.steps.s02_demux import StepDemux
from lib.steps.s03_subtitle_detect import StepSubtitleDetect
from lib.steps.s04_audio_separate import StepAudioSeparate
from lib.steps.s05_asr import StepASR
from lib.steps.s05b_gender_detect import StepGenderDetect
from lib.steps.s06_ocr import StepOCR
from lib.steps.s07_transcript_merge import StepTranscriptMerge
from lib.steps.s08_translation import StepTranslation
from lib.steps.s08b_metadata_gen import StepMetadataGen
from lib.steps.s09_subtitle_gen import StepSubtitleGen
from lib.steps.s10_inpaint import StepInpaint
from lib.steps.s11_subtitle_render import StepSubtitleRender
from lib.steps.s12_tts import StepTTS
from lib.steps.s13_audio_mix import StepAudioMix
from lib.steps.s14_encode import StepEncode

console = Console()


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


def load_config(config_path: Path) -> Dict[str, Any]:
    load_env_file()
    default_config = {}
    if config_path.exists():
        with open(config_path, "r", encoding="utf-8") as f:
            default_config = yaml.safe_load(f) or {}
    return default_config


def build_pipeline() -> PipelineRunner:
    steps = [
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
        StepSubtitleGen(),
        StepInpaint(),
        StepSubtitleRender(),
        StepTTS(),
        StepAudioMix(),
        StepEncode()
    ]
    return PipelineRunner(steps)


def cmd_translate(args, base_config: Dict[str, Any]):
    input_path = Path(args.input_video).resolve()
    if not input_path.exists():
        console.print(f"[bold red]Error:[/bold red] File not found: {input_path}")
        sys.exit(1)

    project_paths = ProjectManager.resolve_project_paths(input_path)
    config = project_paths.load_config()

    duration = getattr(args, "duration", None)
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

    runner = build_pipeline()
    success = runner.run(job_state, config)

    if success:
        encode_output = job_state.get_step_output("s14_encode") or {}
        output_file = encode_output.get("output_file")
        console.print(f"\n[bold green]✨ Video translated successfully![/bold green]")
        console.print(f"[bold cyan]Project:[/bold cyan] {project_paths.project_name}")
        console.print(f"[bold cyan]Job ID:[/bold cyan] {job_id}")
        console.print(f"[bold cyan]Output File:[/bold cyan] {output_file}")
    else:
        console.print(f"\n[bold red]❌ Translation failed for Job ID:[/bold red] {job_state.job_id}")
        console.print(f"You can resume execution with: [yellow]python main.py resume {job_state.job_id}[/yellow]")


def resolve_job_target(target: str) -> tuple[Path, str, str]:
    """
    Resolves job_id and project workspace for a given target string.
    Supports:
    - Path to video or workspace: 'assets/fashions/src/video_001.mp4' or 'assets/fashions/workspace/job_video_001'
    - Project prefix syntax: 'fashions:job_video_001' or 'fashions/job_video_001'
    - Simple job_id: 'job_video_001' or 'video_001'
    Returns: (workspace_dir, actual_job_id, project_name)
    """
    target = target.strip()
    assets_dir = ROOT_DIR / "assets"

    # Case 1: Target is an existing path or contains slashes
    if "/" in target or "\\" in target or Path(target).exists():
        path_target = Path(target).resolve()
        if path_target.is_file():
            proj_paths = ProjectManager.resolve_project_paths(path_target)
            job_id = ProjectManager.get_job_id(path_target)
            return proj_paths.workspace_dir, job_id, proj_paths.project_name
        elif path_target.is_dir():
            # e.g., assets/fashions/workspace/job_video_001
            job_id = path_target.name
            proj_paths = ProjectManager.resolve_project_paths(path_target)
            return proj_paths.workspace_dir, job_id, proj_paths.project_name

    # Case 2: Project prefix syntax e.g. 'fashions:job_video_001' or 'fashions:video_001'
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
        proj_list = ", ".join([m[2] for m in matches])
        console.print(f"[bold yellow]⚠️ Multiple jobs with ID '{clean_id}' found in projects:[/bold yellow] [cyan]{proj_list}[/cyan]")
        console.print(f"Please specify the project explicitly, for example:")
        for m in matches:
            console.print(f"  • [green]python main.py resume {m[2]}:{m[1]}[/green]")
            console.print(f"  • [green]python main.py resume assets/{m[2]}/workspace/{m[1]}[/green]")
        sys.exit(1)
    elif matches:
        return matches[0]

    # Fallback to default workspace
    default_ws = assets_dir / "default" / "workspace"
    return default_ws, clean_id, "default"


def cmd_resume(args, base_config: Dict[str, Any]):
    workspace_dir, job_id, proj_name = resolve_job_target(args.job_id)
    job_dir = workspace_dir / job_id

    if not job_dir.exists():
        console.print(f"[bold red]Error:[/bold red] Job directory not found: {job_dir}")
        sys.exit(1)

    project_paths = ProjectManager.resolve_project_paths(workspace_dir)
    config = project_paths.load_config()

    job_state = JobState(workspace=workspace_dir, job_id=job_id)
    runner = build_pipeline()
    success = runner.run(job_state, config)

    if success:
        encode_output = job_state.get_step_output("s14_encode") or {}
        output_file = encode_output.get("output_file")
        console.print(f"\n[bold green]✨ Job resumed and completed successfully![/bold green]")
        console.print(f"[bold cyan]Project:[/bold cyan] {proj_name}")
        console.print(f"[bold cyan]Job ID:[/bold cyan] {job_id}")
        console.print(f"[bold cyan]Output File:[/bold cyan] {output_file}")


def cmd_status(args, base_config: Dict[str, Any]):
    workspace_dir, job_id, proj_name = resolve_job_target(args.job_id)
    job_dir = workspace_dir / job_id

    if not job_dir.exists():
        console.print(f"[bold red]Error:[/bold red] Job directory not found: {job_dir}")
        sys.exit(1)

    job_state = JobState(workspace=workspace_dir, job_id=job_id)

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



def cmd_jobs(args, base_config: Dict[str, Any]):
    assets_dir = ROOT_DIR / "assets"
    if not assets_dir.exists():
        console.print("No projects found.")
        return

    table = Table(title="Existing Jobs Across Projects")
    table.add_column("Project", style="blue")
    table.add_column("Job ID", style="cyan")
    table.add_column("Status", style="magenta")
    table.add_column("Input Video", style="green")
    table.add_column("Created At", style="yellow")

    found = 0
    for proj in sorted(assets_dir.iterdir()):
        if proj.is_dir():
            ws = proj / "workspace"
            if ws.exists():
                for job_dir in sorted(ws.iterdir()):
                    if job_dir.is_dir() and (job_dir / "state.json").exists():
                        found += 1
                        job_state = JobState(workspace=ws, job_id=job_dir.name)
                        table.add_row(
                            proj.name,
                            job_state.job_id,
                            job_state.data.get("status", "pending"),
                            Path(job_state.data.get("input_video", "")).name,
                            job_state.data.get("created_at", "-")
                        )

    if found == 0:
        console.print("No active jobs found.")
    else:
        console.print(table)


def cmd_batch(args, base_config: Dict[str, Any]):
    from batch_translate import run_batch
    input_dir = Path(args.input_dir)
    run_batch(input_dir, base_config, duration=getattr(args, "duration", None))


def cmd_delete_step(args, base_config: Dict[str, Any]):
    workspace_dir, job_id, proj_name = resolve_job_target(args.job_id)
    job_dir = workspace_dir / job_id

    if not job_dir.exists():
        console.print(f"[bold red]Error:[/bold red] Job directory not found: {job_dir}")
        sys.exit(1)

    job_state = JobState(workspace=workspace_dir, job_id=job_id)
    affected = job_state.clear_step(args.step_id)

    console.print(f"[bold green]🗑️ Successfully cleared step '[cyan]{args.step_id}[/cyan]' cache for job '[cyan]{job_id}[/cyan]' in project '[cyan]{proj_name}[/cyan]'![/bold green]")
    console.print(f"[bold yellow]Invalidated & cleaned artifact steps:[/bold yellow] {', '.join(affected)}")
    console.print(f"You can re-run/resume execution with: [cyan]python main.py resume {proj_name}:{job_id}[/cyan]")


def cmd_delete_job(args, base_config: Dict[str, Any]):
    workspace_dir, job_id, proj_name = resolve_job_target(args.job_id)
    job_dir = workspace_dir / job_id

    if not job_dir.exists():
        console.print(f"[bold red]Error:[/bold red] Job directory not found: {job_dir}")
        sys.exit(1)

    job_state = JobState(workspace=workspace_dir, job_id=job_id)
    job_state.delete_job()

    console.print(f"[bold green]🗑️ Successfully deleted job workspace '[cyan]{job_id}[/cyan]' from project '[cyan]{proj_name}[/cyan]'![/bold green]")


def main():
    parser = argparse.ArgumentParser(description="AI Video Translator CLI (MVP v1)")
    parser.add_argument("--config", default="config.yaml", help="Path to config.yaml")

    subparsers = parser.add_subparsers(dest="command", required=True)

    # translate command
    p_trans = subparsers.add_parser("translate", help="Translate single video")
    p_trans.add_argument("input_video", help="Path to input video file")
    p_trans.add_argument("-t", "--t", "--duration", dest="duration", type=float, default=None, help="Process only the first N seconds of video (default: full video)")

    # batch command
    p_batch = subparsers.add_parser("batch", help="Batch translate all videos in a folder")
    p_batch.add_argument("input_dir", nargs="?", default="assets/foods/src", help="Directory containing input videos (default: assets/foods/src)")
    p_batch.add_argument("--output_dir", default=None, help="Directory to save output videos")
    p_batch.add_argument("-t", "--t", "--duration", dest="duration", type=float, default=None, help="Process only the first N seconds of each video (default: full video)")

    # resume command
    p_res = subparsers.add_parser("resume", help="Resume failed or interrupted job")
    p_res.add_argument("job_id", help="ID of job to resume (or video name)")

    # status command
    p_stat = subparsers.add_parser("status", help="Check job status")
    p_stat.add_argument("job_id", help="ID of job to inspect")

    # jobs command
    subparsers.add_parser("jobs", help="List all jobs")

    # delete-step command
    p_del_step = subparsers.add_parser("delete-step", help="Delete cache for a specific step and downstream steps")
    p_del_step.add_argument("job_id", help="ID of job (or project:job_id)")
    p_del_step.add_argument("step_id", help="Step ID to invalidate (e.g. s08_translation)")

    # delete-job command
    p_del_job = subparsers.add_parser("delete-job", help="Delete entire job workspace directory")
    p_del_job.add_argument("job_id", help="ID of job to delete (or project:job_id)")

    args = parser.parse_args()
    config = load_config(Path(args.config))

    if args.command == "translate":
        cmd_translate(args, config)
    elif args.command == "batch":
        cmd_batch(args, config)
    elif args.command == "resume":
        cmd_resume(args, config)
    elif args.command == "status":
        cmd_status(args, config)
    elif args.command == "jobs":
        cmd_jobs(args, config)
    elif args.command == "delete-step":
        cmd_delete_step(args, config)
    elif args.command == "delete-job":
        cmd_delete_job(args, config)


if __name__ == "__main__":
    main()

