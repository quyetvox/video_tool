#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path
from typing import Any, Dict, List

ROOT_DIR = Path(__file__).parent.resolve()
sys.path.insert(0, str(ROOT_DIR / "lib"))
sys.path.insert(0, str(ROOT_DIR))

from rich.console import Console
from rich.table import Table

from lib.core.job_state import JobState
from lib.core.project_manager import ProjectManager
from main import build_pipeline, load_config

console = Console()

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".avi", ".mov", ".webm", ".flv"}


def run_batch(input_dir: Path, base_config: Dict[str, Any], duration: float | None = None):
    input_dir = Path(input_dir).resolve()
    if not input_dir.exists() or not input_dir.is_dir():
        console.print(f"[bold red]Error:[/bold red] Input directory not found or is not a folder: {input_dir}")
        sys.exit(1)

    project_paths = ProjectManager.resolve_project_paths(input_dir)
    config = project_paths.load_config()

    if duration is not None and duration > 0:
        config["duration"] = float(duration)

    video_files: List[Path] = [
        f for f in sorted(input_dir.iterdir())
        if f.is_file() and f.suffix.lower() in VIDEO_EXTENSIONS and not f.name.startswith(".")
    ]

    if not video_files:
        console.print(f"[yellow]No video files found in {input_dir}[/yellow]")
        return

    output_dir = project_paths.output_dir
    workspace_dir = project_paths.workspace_dir

    console.print(f"\n[bold cyan]🎬 Batch Video Translation Started[/bold cyan]")
    console.print(f"📁 Project:       [bold green]{project_paths.project_name}[/bold green]")
    console.print(f"📁 Input Folder:  [yellow]{input_dir}[/yellow]")
    console.print(f"📁 Output Folder: [yellow]{output_dir}[/yellow]")
    if duration and duration > 0:
        console.print(f"⏱️ Test Duration:  [bold yellow]{duration:.1f}s[/bold yellow]")
    console.print(f"📹 Found [bold green]{len(video_files)}[/bold green] video file(s)\n")

    results = []

    for idx, video_file in enumerate(video_files, 1):
        console.print(f"[bold blue]════════════════════════════════════════════════════════════[/bold blue]")
        console.print(f"[bold green]▶ [{idx}/{len(video_files)}] Processing:[/bold green] [bold white]{video_file.name}[/bold white]")
        console.print(f"[bold blue]════════════════════════════════════════════════════════════[/bold blue]")

        if duration and duration > 0:
            job_id = f"{ProjectManager.get_job_id(video_file)}_{int(duration)}s"
        else:
            job_id = ProjectManager.get_job_id(video_file)

        try:
            job_state = JobState(
                workspace=workspace_dir,
                job_id=job_id,
                input_video=str(video_file),
                config=config
            )
            runner = build_pipeline()
            success = runner.run(job_state, config)

            if success:
                encode_output = job_state.get_step_output("s14_encode") or {}
                out_path = encode_output.get("output_file", "")
                results.append({
                    "file": video_file.name,
                    "status": "Success",
                    "output": out_path,
                    "job_id": job_id
                })
            else:
                results.append({
                    "file": video_file.name,
                    "status": "Failed",
                    "output": "-",
                    "job_id": job_id
                })
        except Exception as e:
            console.print(f"[bold red]Error processing {video_file.name}: {e}[/bold red]")
            results.append({
                "file": video_file.name,
                "status": f"Error: {e}",
                "output": "-",
                "job_id": job_id
            })

    table = Table(title="Batch Processing Summary")
    table.add_column("No.", style="cyan", justify="center")
    table.add_column("Input Video", style="white")
    table.add_column("Job ID", style="yellow")
    table.add_column("Status", style="magenta")
    table.add_column("Result Output Path", style="green")

    for idx, r in enumerate(results, 1):
        status_style = "bold green" if r["status"] == "Success" else "bold red"
        table.add_row(
            str(idx),
            r["file"],
            r["job_id"],
            f"[{status_style}]{r['status']}[/{status_style}]",
            r["output"]
        )

    console.print("\n")
    console.print(table)


def main():
    parser = argparse.ArgumentParser(description="Batch translate all videos in a folder")
    parser.add_argument("input_dir", nargs="?", default="assets/foods/src", help="Directory containing source videos (default: assets/foods/src)")
    parser.add_argument("--output_dir", default=None, help="Directory to save translated videos")
    parser.add_argument("--config", default="config.yaml", help="Path to config.yaml")
    parser.add_argument("-t", "--t", "--duration", dest="duration", type=float, default=None, help="Process only the first N seconds of each video (default: full video)")

    args = parser.parse_args()
    config = load_config(Path(args.config))

    input_dir = Path(args.input_dir)
    run_batch(input_dir, config, duration=getattr(args, "duration", None))


if __name__ == "__main__":
    main()
