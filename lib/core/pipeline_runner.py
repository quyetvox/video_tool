import logging
from pathlib import Path
from typing import List

from rich.console import Console
from rich.logging import RichHandler

from core.job_state import JobState
from core.step_base import StepBase

console = Console()
logging.basicConfig(
    level=logging.INFO,
    format="%(message)s",
    datefmt="[%X]",
    handlers=[RichHandler(console=console, rich_tracebacks=True)]
)
logger = logging.getLogger("sub_video")


STEP_CONFIG_KEYS = {
    "s01_probe": ["duration"],
    "s02_demux": ["duration"],
    "s03_subtitle_detect": ["inpaint_region", "subtitle_detect_start_sec", "subtitle_detect_duration_sec"],
    "s04_audio_separate": ["device", "noise_reduction_strength", "ambient_split_threshold", "ocr_only"],
    "s05_asr": ["asr", "asr_model", "ocr_only"],
    "s05b_gender_detect": ["enable_gender_tts", "ocr_only"],
    "s06_ocr": ["ocr", "ocr_mode", "ocr_only", "inpaint_region"],
    "s07_transcript_merge": [],
    "s08_translation": ["translator", "translator_model", "target_lang"],
    "s08b_metadata_gen": ["enable_metadata_gen", "metadata_hashtags_count", "target_lang", "translator", "translator_model"],
    "s09_subtitle_gen": ["inpaint_region", "subtitle_font_size"],
    "s10_inpaint": [
        "inpaint", "inpaint_region", "blur_radius",
        "watermark_enable", "watermark_region", "watermark_image",
        "watermark_text", "watermark_blur_bg", "watermark_opacity", "watermark_font_color"
    ],
    "s11_subtitle_render": ["show_subtitle"],
    "s12_tts": ["tts", "tts_voice", "tts_speed_factor", "enable_gender_tts", "tts_voice_male", "tts_voice_female"],
    "s13_audio_mix": ["music_volume", "ambient_volume", "tts_voice_volume", "original_voice_volume"],
    "s14_encode": ["output_suffix", "output_dir", "duration"]
}


class PipelineRunner:
    def __init__(self, steps: List[StepBase]):
        self.steps = steps

    def run(self, job_state: JobState, config: dict) -> bool:
        logger.info(f"Starting pipeline execution for job: [bold green]{job_state.job_id}[/bold green]")
        
        # Smart Config Change Detection & Step Auto-Invalidation
        invalidated_steps = set()
        for step in self.steps:
            step_id = step.step_id
            relevant_keys = getattr(step, "STEP_CONFIG_KEYS", STEP_CONFIG_KEYS.get(step_id, []))
            
            dep_invalidated = any(dep in invalidated_steps for dep in step.depends_on)
            old_step_cfg = job_state.data.get("steps", {}).get(step_id, {}).get("config", {})
            
            config_changed = False
            changed_key_name = ""
            for k in relevant_keys:
                old_val = old_step_cfg.get(k)
                new_val = config.get(k)
                if old_val != new_val and (old_val is not None or new_val is not None):
                    config_changed = True
                    changed_key_name = k
                    break

            if config_changed or dep_invalidated:
                if job_state.is_step_done(step_id):
                    reason = f"config '{changed_key_name}' changed ({old_step_cfg.get(changed_key_name)} -> {config.get(changed_key_name)})" if config_changed else "upstream step updated"
                    console.print(f"[bold yellow][↺] Invalidating {step_id}[/bold yellow] ({reason})")
                    job_state.invalidate_step(step_id)
                invalidated_steps.add(step_id)

        for step in self.steps:
            step_id = step.step_id
            relevant_keys = getattr(step, "STEP_CONFIG_KEYS", STEP_CONFIG_KEYS.get(step_id, []))
            
            # Check dependencies
            for dep in step.depends_on:
                if not job_state.is_step_done(dep):
                    error_msg = f"Step '{step_id}' dependency '{dep}' is not completed."
                    logger.error(f"[bold red]Pipeline Error:[/bold red] {error_msg}")
                    job_state.mark_failed(error_msg)
                    return False

            # Check if step can be skipped
            if step.can_skip(job_state.job_dir) and job_state.is_step_done(step_id):
                console.print(f"[bold blue][✓] {step_id}[/bold blue] (cached)")
                continue

            console.print(f"[yellow][→] Executing {step_id}...[/yellow]")
            job_state.set_step_status(step_id, "running")

            try:
                output = step.run(job_state.job_dir, config, job_state)
                step.mark_done(job_state.job_dir)
                step_cfg_snapshot = {k: config.get(k) for k in relevant_keys if k in config}
                if step_id not in job_state.data["steps"]:
                    job_state.data["steps"][step_id] = {}
                job_state.data["steps"][step_id]["config"] = step_cfg_snapshot
                job_state.set_step_status(step_id, "done", output=output)
                console.print(f"[bold green][✓] {step_id} completed successfully.[/bold green]")
            except Exception as e:
                error_msg = f"Step '{step_id}' failed: {str(e)}"
                logger.exception(error_msg)
                job_state.set_step_status(step_id, "failed", error=error_msg)
                job_state.mark_failed(error_msg)
                return False

        job_state.mark_completed()
        console.print(f"[bold green]🎉 Pipeline completed for job {job_state.job_id}![/bold green]")
        return True
