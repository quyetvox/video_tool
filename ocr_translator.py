#!/usr/bin/env python3
"""
Sub-Video (AI Video Translator) - Visual OCR Subtitle Translator CLI
====================================================================
Translates visual hardsub text directly from video frames while preserving 100% original audio.
"""
import argparse
import os
import sys
from pathlib import Path
from typing import Any, Dict, List

ROOT_DIR = Path(__file__).parent.resolve()
sys.path.insert(0, str(ROOT_DIR / "lib"))
sys.path.insert(0, str(ROOT_DIR))

import yaml
from rich.console import Console

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
from lib.steps.s08c_timing import StepSubtitleTiming
from lib.steps.s09_subtitle_gen import StepSubtitleGen
from lib.steps.s10_inpaint import StepInpaint
from lib.steps.s11_subtitle_render import StepSubtitleRender
from lib.steps.s12_tts import StepTTS
from lib.steps.s13_audio_mix import StepAudioMix
from lib.steps.s14_encode import StepEncode

console = Console()

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".mov", ".avi", ".webm", ".flv"}


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


def get_all_steps() -> List[Any]:
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
        StepEncode(),
    ]


def process_single_video(
    video_path: Path,
    override_config: Dict[str, Any]
) -> bool:
    video_path = video_path.resolve()
    if not video_path.exists():
        console.print(f"[bold red]❌ Lỗi: Không tìm thấy video: {video_path}[/bold red]")
        return False

    project_paths = ProjectManager.resolve_project_paths(video_path)
    config = project_paths.load_config()

    config["ocr_only"] = True
    config.update(override_config)

    duration = config.get("duration")
    if duration is not None and float(duration) > 0:
        duration_val = float(duration)
        config["duration"] = duration_val
        job_id = f"{ProjectManager.get_job_id(video_path)}_{int(duration_val)}s"
    else:
        config.pop("duration", None)
        job_id = ProjectManager.get_job_id(video_path)

    console.print(f"\n[bold magenta]==========================================================[/bold magenta]")
    console.print(f"[bold cyan]📸 VISUAL OCR SUBTITLE TRANSLATOR[/bold cyan]")
    console.print(f"[bold white]Dự án:[/bold white] [green]{project_paths.project_name}[/green]")
    console.print(f"[bold white]Video:[/bold white] [yellow]{video_path.name}[/yellow]")
    console.print(f"[bold white]Job ID:[/bold white] {job_id}")
    console.print(f"[bold white]Chế độ:[/bold white] [bold gold1]OCR-Only (Preserving 100% Original Audio)[/bold gold1]")
    if config.get("duration"):
        console.print(f"[bold white]Test Duration:[/bold white] {config['duration']}s")
    console.print(f"[bold magenta]==========================================================[/bold magenta]\n")

    job_state = JobState(
        workspace=project_paths.workspace_dir,
        job_id=job_id,
        input_video=str(video_path),
        config=config
    )

    runner = PipelineRunner(get_all_steps())
    success = runner.run(job_state, config)

    if success:
        encode_output = job_state.get_step_output("s14_encode") or {}
        out_file = encode_output.get("output_file")
        console.print(f"\n[bold green]🎉 Hoàn thành dịch sub cứng cho {video_path.name}![/bold green]")
        console.print(f"[bold white]Output:[/bold white] [cyan]{out_file}[/cyan]\n")
        return True
    else:
        console.print(f"\n[bold red]❌ Tiến trình dịch sub cứng thất bại cho {video_path.name}.[/bold red]\n")
        return False


def main():
    load_env_file()
    parser = argparse.ArgumentParser(
        description="Visual OCR Subtitle Translator: Detect visual hardsubs, translate text, blur old sub, and render new sub with 100% original audio."
    )
    parser.add_argument(
        "target",
        type=str,
        help="Đường dẫn file video (.mp4/.mov) hoặc thư mục src/ của dự án (ví dụ: assets/foods/src/video_001.mp4)",
    )
    parser.add_argument(
        "-t", "--duration",
        type=float,
        default=None,
        help="Thời lượng video cần xử lý (giây) để test nhanh (ví dụ: -t 10 hoặc -t 20)",
    )
    parser.add_argument(
        "-l", "--target-lang",
        type=str,
        default=None,
        help="Ngôn ngữ đích (mặc định: vi)",
    )
    parser.add_argument(
        "-i", "--inpaint",
        type=str,
        choices=["ffmpeg_blur", "opencv"],
        default=None,
        help="Thuật toán làm mờ sub cũ: ffmpeg_blur (~1s) hoặc opencv (~15s)",
    )
    parser.add_argument(
        "--blur-radius",
        type=int,
        default=None,
        help="Độ mịn mờ kính (mặc định: 15)",
    )
    parser.add_argument(
        "--translator",
        type=str,
        default=None,
        help="Provider dịch thuật (ollama | openai | groq | deepseek)",
    )
    parser.add_argument(
        "--model",
        type=str,
        default=None,
        help="Tên model LLM dịch thuật (ví dụ: gemma4:31b-cloud, gpt-4o-mini)",
    )

    args = parser.parse_args()
    target_path = Path(args.target).resolve()

    if not target_path.exists():
        console.print(f"[bold red]❌ Lỗi: Đường dẫn '{target_path}' không tồn tại.[/bold red]")
        sys.exit(1)

    override_config = {}
    if args.duration:
        override_config["duration"] = args.duration
    if args.target_lang:
        override_config["target_lang"] = args.target_lang
    if args.inpaint:
        override_config["inpaint"] = args.inpaint
    if args.blur_radius:
        override_config["blur_radius"] = args.blur_radius
    if args.translator:
        if "translator" not in override_config:
            override_config["translator"] = {}
        override_config["translator"]["type"] = args.translator
    if args.model:
        if "translator" not in override_config:
            override_config["translator"] = {}
        override_config["translator"]["model"] = args.model

    if target_path.is_file():
        if target_path.suffix.lower() not in VIDEO_EXTENSIONS:
            console.print(f"[bold red]❌ Lỗi: File '{target_path.name}' không phải định dạng video hỗ trợ.[/bold red]")
            sys.exit(1)
        success = process_single_video(target_path, override_config)
        sys.exit(0 if success else 1)
    elif target_path.is_dir():
        video_files = sorted([p for p in target_path.iterdir() if p.is_file() and p.suffix.lower() in VIDEO_EXTENSIONS])
        if not video_files:
            console.print(f"[bold yellow]⚠️ Không tìm thấy file video nào trong '{target_path}'.[/bold yellow]")
            sys.exit(0)

        console.print(f"[bold green]🔍 Tìm thấy {len(video_files)} video để dịch sub cứng (Visual OCR)...[/bold green]")
        success_count = 0
        for vid in video_files:
            if process_single_video(vid, override_config):
                success_count += 1

        console.print(f"\n[bold green]✅ Đã hoàn thành {success_count}/{len(video_files)} video.[/bold green]")
        sys.exit(0 if success_count == len(video_files) else 1)


if __name__ == "__main__":
    main()
