import json
import logging
import warnings
from pathlib import Path
from typing import List, Any, Dict, Optional, Set, Callable

warnings.filterwarnings("ignore")

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
    "s03_subtitle_detect": ["show_subtitle", "inpaint_region", "subtitle_detect_start_sec", "subtitle_detect_duration_sec"],
    "s04_audio_separate": ["device", "noise_reduction_strength", "ambient_split_threshold", "ocr_only"],
    "s05_asr": ["asr", "asr_model", "ocr_only"],
    "s05b_gender_detect": ["enable_gender_tts", "ocr_only"],
    "s06_ocr": ["ocr", "ocr_mode", "ocr_only", "inpaint_region"],
    "s07_transcript_merge": [],
    "s08_translation": ["translator", "translator_model", "target_lang"],
    "s08b_metadata_gen": ["enable_metadata_gen", "metadata_hashtags_count", "target_lang", "translator", "translator_model"],
    "s08c_timing": ["subtitle_char_rate", "subtitle_safety_margin", "subtitle_fill_gap"],
    "s09_subtitle_gen": [
        "show_subtitle", "inpaint_region", "subtitle_font_size", "subtitle_font_name", 
        "subtitle_font_color", "subtitle_outline_color", "subtitle_style", 
        "inpaint_box_bg_color", "inpaint_box_bg_opacity", "inpaint_box_border_color", 
        "inpaint_box_border_width", "inpaint_box_border_radius", "blur_box_padding_y",
        "subtitle_order", "subtitle_box_split", "subtitle_box_gap",
        "subtitle_box_lead_in", "subtitle_box_lead_out",
        "subtitle_secondary_show", "subtitle_secondary_font_name", "subtitle_secondary_font_size_scale",
        "subtitle_secondary_font_color", "subtitle_secondary_outline_color", "subtitle_secondary_region"
    ],
    "s10_inpaint": [
        "show_subtitle", "inpaint", "inpaint_region", "inpaint_color", "blur_radius", "blur_box_padding_y", "video_bitrate",
        "watermark_enable", "watermark_region", "watermark_image",
        "watermark_text", "watermark_font_name", "watermark_blur_bg", "watermark_opacity", "watermark_font_color"
    ],
    "s11_subtitle_render": ["show_subtitle", "video_bitrate"],
    "s12_tts": ["tts", "tts_voice", "tts_voice_volume", "tts_speed_factor", "tts_delay_sec", "enable_gender_tts", "tts_voice_male", "tts_voice_female"],
    "s13_audio_mix": ["tts_voice", "music_volume", "ambient_volume", "tts_voice_volume", "original_voice_volume"],
    "s14_encode": ["output_suffix", "output_dir", "duration", "video_bitrate"]
}


def is_config_changed(old_val: Any, new_val: Any) -> bool:
    """Robust comparison between old step config and current active config."""
    if old_val == new_val:
        return False
    # Treat None, empty string, empty list, empty dict as equivalent
    if old_val in (None, "", [], {}) and new_val in (None, "", [], {}):
        return False
    
    # Dict vs String comparison (e.g. {'engine': 'mlx-whisper'} vs 'mlx-whisper')
    if isinstance(old_val, dict) and isinstance(new_val, str):
        extracted = old_val.get("engine") or old_val.get("type") or old_val.get("name")
        if extracted and str(extracted).lower().replace("-", "_") == new_val.lower().replace("-", "_"):
            return False
    if isinstance(new_val, dict) and isinstance(old_val, str):
        extracted = new_val.get("engine") or new_val.get("type") or new_val.get("name")
        if extracted and str(extracted).lower().replace("-", "_") == old_val.lower().replace("-", "_"):
            return False

    # If old_val is None but new_val matches common defaults
    if old_val is None:
        if new_val in ("auto", True, False, "vi", "", "none", 0, 0.0, 0.07, 1.5, 1.2, 1.0):
            return False

    if isinstance(old_val, (int, float)) and isinstance(new_val, (int, float)):
        return abs(float(old_val) - float(new_val)) > 1e-5
    if isinstance(old_val, str) and isinstance(new_val, bool):
        return (old_val.lower() == "true") != new_val
    if isinstance(new_val, str) and isinstance(old_val, bool):
        return (new_val.lower() == "true") != old_val
    
    # String comparison case-insensitive & hyphen-insensitive (e.g. "mlx-whisper" vs "mlx_whisper")
    if isinstance(old_val, str) and isinstance(new_val, str):
        return old_val.lower().replace("-", "_") != new_val.lower().replace("-", "_")

    return old_val != new_val


class PipelineRunner:
    def __init__(
        self,
        steps: List[StepBase],
        on_log: Optional[Callable[[str, str, str], None]] = None,
        on_step_status: Optional[Callable[[str, str, Optional[float]], None]] = None,
        emit_json: bool = False
    ):
        self.steps = steps
        self.on_log = on_log
        self.on_step_status = on_step_status
        self.emit_json = emit_json

    def _log(self, step_id: str, message: str, level: str = "info"):
        if self.on_log:
            self.on_log(step_id, message, level)
        elif self.emit_json:
            print(json.dumps({
                "type": "log",
                "step_id": step_id,
                "message": message,
                "level": level
            }), flush=True)

    def _step_status(self, step_id: str, status: str, progress: Optional[float] = None):
        if self.on_step_status:
            self.on_step_status(step_id, status, progress)
        elif self.emit_json:
            print(json.dumps({
                "type": "step_status",
                "step_id": step_id,
                "status": status,
                "progress": progress
            }), flush=True)

    def run(self, job_state: JobState, config: dict) -> bool:
        from core.config_adapter import wrap_config
        config = wrap_config(config)

        if not self.emit_json:
            logger.info(f"Starting pipeline execution for job: [bold green]{job_state.job_id}[/bold green]")
        from core.concurrency import ConcurrencyManager
        ConcurrencyManager.configure_runtime(config)

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
                if is_config_changed(old_val, new_val):
                    config_changed = True
                    changed_key_name = k
                    break

            # Smart File MTime Check: Auto-detect if user manually edited output files (e.g. s08_translation.json)
            file_modified_reason = None
            step_updated_at_str = job_state.data.get("steps", {}).get(step_id, {}).get("updated_at")
            if step_updated_at_str and not dep_invalidated:
                try:
                    from datetime import datetime
                    step_dt = datetime.fromisoformat(step_updated_at_str)
                    step_ts = step_dt.timestamp()

                    # 1. Check upstream dependencies outputs
                    for dep in step.depends_on:
                        dep_out = job_state.get_step_output(dep) or {}
                        for val in dep_out.values():
                            if isinstance(val, str) and (val.endswith(".json") or val.endswith(".srt") or val.endswith(".ass") or val.endswith(".wav") or val.endswith(".mp4")):
                                p = Path(val)
                                if not p.is_absolute():
                                    p = job_state.job_dir / p
                                if p.exists() and p.stat().st_mtime > step_ts + 0.1:
                                    file_modified_reason = f"phát hiện file '{p.name}' được sửa thủ công"
                                    break
                        if file_modified_reason:
                            break

                    # 2. Directly check s08_translation.json / s07_transcript.json for downstream steps
                    # Exclude s10_inpaint (inpaint only depends on original video + burnin region, NOT on subtitle text!)
                    ocr_only = bool(config.get("ocr_only", False))
                    candidate_sub_downstream = ["s08c_timing", "s09_subtitle_gen", "s11_subtitle_render", "s14_encode"]
                    if not ocr_only:
                        candidate_sub_downstream.extend(["s12_tts", "s13_audio_mix"])

                    if not file_modified_reason and step_id in candidate_sub_downstream:
                        for f_name in ["s08_translation.json", "s07_transcript.json"]:
                            f_path = job_state.job_dir / f_name
                            if f_path.exists() and f_path.stat().st_mtime > step_ts + 0.1:
                                file_modified_reason = f"phát hiện file '{f_name}' được sửa thủ công"
                                break
                except Exception:
                    pass

            # Protection for user-curated manual subtitle edits in s08_translation:
            # Never overwrite s08_translation.json with AI re-translation unless force_translate is explicitly set!
            if step_id == "s08_translation" and (job_state.job_dir / "s08_translation.json").exists() and not config.get("force_translate", False):
                trans_file = job_state.job_dir / "s08_translation.json"
                if not job_state.is_step_done("s08_translation"):
                    job_state.set_step_output("s08_translation", {
                        "translation_file": str(trans_file),
                        "target_lang": config.get("target_lang", "vi"),
                        "secondary_lang": config.get("secondary_lang", ""),
                    })
                    job_state.set_step_status("s08_translation", "done")
                config_changed = False
                dep_invalidated = False
                file_modified_reason = None

            if config_changed or dep_invalidated or file_modified_reason:
                if job_state.is_step_done(step_id):
                    if config_changed:
                        reason = f"config '{changed_key_name}' changed ({old_step_cfg.get(changed_key_name)} -> {config.get(changed_key_name)})"
                    elif file_modified_reason:
                        reason = file_modified_reason
                    else:
                        reason = "upstream step updated"

                    if not self.emit_json:
                        console.print(f"[bold yellow][↺] Invalidating {step_id}[/bold yellow] ({reason})")
                    self._log(step_id, f"Invalidate cache ({reason})", "warning")
                    job_state.invalidate_step(step_id)
                invalidated_steps.add(step_id)

        for step in self.steps:
            step_id = step.step_id
            relevant_keys = getattr(step, "STEP_CONFIG_KEYS", STEP_CONFIG_KEYS.get(step_id, []))
            
            # Check dependencies
            for dep in step.depends_on:
                if not job_state.is_step_done(dep):
                    error_msg = f"Step '{step_id}' dependency '{dep}' is not completed."
                    if not self.emit_json:
                        logger.error(f"[bold red]Pipeline Error:[/bold red] {error_msg}")
                    self._log(step_id, error_msg, "error")
                    self._step_status(step_id, "failed")
                    job_state.mark_failed(error_msg)
                    return False

            # Check if step can be skipped
            if step.can_skip(job_state.job_dir) and job_state.is_step_done(step_id):
                if not self.emit_json:
                    console.print(f"[bold blue][✓] {step_id}[/bold blue] (cached)")
                self._log(step_id, "Đã hoàn thành trước đó (dùng cache)", "info")
                self._step_status(step_id, "done", 1.0)
                continue

            if not self.emit_json:
                console.print(f"[yellow][→] Executing {step_id}...[/yellow]")
            self._log(step_id, f"Bắt đầu xử lý {step_id}...", "info")
            self._step_status(step_id, "running")
            job_state.set_step_status(step_id, "running")

            try:
                output = step.run(job_state.job_dir, config, job_state)
                step.mark_done(job_state.job_dir)
                step_cfg_snapshot = {k: config.get(k) for k in relevant_keys if k in config}
                if step_id not in job_state.data["steps"]:
                    job_state.data["steps"][step_id] = {}
                job_state.data["steps"][step_id]["config"] = step_cfg_snapshot
                job_state.set_step_status(step_id, "done", output=output)
                if not self.emit_json:
                    console.print(f"[bold green][✓] {step_id} completed successfully.[/bold green]")
                self._log(step_id, f"Hoàn thành {step_id} thành công", "success")
                self._step_status(step_id, "done", 1.0)
            except Exception as e:
                error_msg = f"Step '{step_id}' failed: {str(e)}"
                if not self.emit_json:
                    logger.exception(error_msg)
                self._log(step_id, error_msg, "error")
                self._step_status(step_id, "failed")
                job_state.set_step_status(step_id, "failed", error=error_msg)
                job_state.mark_failed(error_msg)
                return False

        job_state.mark_completed()
        if not self.emit_json:
            console.print(f"[bold green]🎉 Pipeline completed for job {job_state.job_id}![/bold green]")
        self._log("pipeline", f"Hoàn tất toàn bộ pipeline cho job {job_state.job_id}!", "success")
        return True
