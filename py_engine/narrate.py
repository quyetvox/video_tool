#!/usr/bin/env python3
"""
Narrate Module (Option C Standalone Script)
Automatically understands video visual content using local Vision AI (LLaVA/MiniCPM-V) or Gemini API,
generates scene-synced emotional Vietnamese narration script, synthesizes TTS voiceover, and renders final video.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT_DIR = Path(__file__).parent.parent.resolve()
ENGINE_DIR = Path(__file__).parent.resolve()
sys.path.insert(0, str(ENGINE_DIR))
sys.path.insert(0, str(ROOT_DIR))

import requests
import yaml
from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn

from core.plugin_loader import PluginLoader
from core.project_manager import ProjectManager
from utils.ffmpeg_utils import FFmpegUtils

console = Console()

VIDEO_EXTENSIONS = {".mp4", ".mkv", ".avi", ".mov", ".webm", ".flv"}


def load_env_file():
    os.environ.pop("MallocStackLogging", None)
    os.environ.pop("MallocScribble", None)
    env_file = Path(".env")
    if env_file.exists():
        with open(env_file, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip().strip("'\""))


def load_config(config_path: Path) -> Dict[str, Any]:
    load_env_file()
    if config_path.exists():
        with open(config_path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    return {}


def detect_scenes(video_path: Path, duration: float, scene_threshold: float = 0.4, max_scenes: int = 30) -> List[float]:
    """Detect scene change timestamps (in seconds) using FFmpeg select filter."""
    console.print(f"[bold cyan]🔍 [1/7] Detecting scenes in video...[/bold cyan]")
    cmd = [
        "ffmpeg", "-i", str(video_path),
        "-vf", f"select='gt(scene,{scene_threshold})',showinfo",
        "-f", "null", "-"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    
    timestamps = [0.0]
    pattern = re.compile(r"pts_time:\s*([\d\.]+)")
    
    for line in res.stderr.splitlines():
        match = pattern.search(line)
        if match:
            t = float(match.group(1))
            if t > timestamps[-1] + 1.0:  # Enforce at least 1s between scenes
                timestamps.append(round(t, 2))
    
    # Fallback: if no scene changes detected, divide video duration evenly into 5s-8s scenes
    if len(timestamps) <= 1 and duration > 3.0:
        segment_len = max(4.0, min(8.0, duration / 5.0))
        curr = 0.0
        timestamps = []
        while curr < duration:
            timestamps.append(round(curr, 2))
            curr += segment_len

    if len(timestamps) > max_scenes:
        timestamps = timestamps[:max_scenes]

    console.print(f"  └─ Detected [bold green]{len(timestamps)}[/bold green] scene segment(s): {timestamps}")
    return timestamps


def _ollama_vision(img_path: Path, prompt: str, vision_model: str, ollama_host: str, timeout: int = 60) -> str:
    """Call Ollama vision model on a single image. Returns description string."""
    import base64
    if not img_path.exists() or img_path.stat().st_size == 0:
        return ""
    with open(img_path, "rb") as f:
        img_b64 = base64.b64encode(f.read()).decode("utf-8")
    try:
        resp = requests.post(
            f"{ollama_host}/api/chat",
            json={"model": vision_model, "messages": [{"role": "user", "content": prompt, "images": [img_b64]}], "stream": False},
            timeout=timeout
        )
        if resp.status_code == 200:
            return resp.json().get("message", {}).get("content", "").strip()
    except Exception:
        pass
    return ""


def _ollama_text(prompt: str, model: str, ollama_host: str, timeout: int = 180) -> str:
    """Call Ollama text generation model. Returns raw response string."""
    try:
        resp = requests.post(
            f"{ollama_host}/api/generate",
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=timeout
        )
        if resp.status_code == 200:
            return resp.json().get("response", "").strip()
    except Exception:
        pass
    return ""


def _parse_json_response(raw: str) -> Any:
    """Strip markdown code fence and parse JSON. Returns None on failure."""
    if "```json" in raw:
        raw = raw.split("```json")[1].split("```")[0].strip()
    elif "```" in raw:
        raw = raw.split("```")[1].split("```")[0].strip()
    try:
        return json.loads(raw)
    except Exception:
        return None


def extract_scene_frames(
    video_path: Path, timestamps: List[float], duration: float, frames_dir: Path
) -> List[Dict[str, Any]]:
    """Extract up to 3 frames per scene: frame_in (start+0.5s), frame_mid, frame_out (end-0.5s)."""
    console.print(f"[bold cyan]📸 [2/7] Extracting scene frames (3 per scene)...[/bold cyan]")
    frames_dir.mkdir(parents=True, exist_ok=True)
    scenes = []

    def extract_frame(t: float, out_path: Path) -> bool:
        cmd = ["ffmpeg", "-y", "-ss", f"{t:.3f}", "-i", str(video_path),
               "-frames:v", "1", "-q:v", "2", str(out_path)]
        subprocess.run(cmd, capture_output=True, check=False)
        return out_path.exists() and out_path.stat().st_size > 0

    for i, t_start in enumerate(timestamps):
        t_end = timestamps[i + 1] if i + 1 < len(timestamps) else duration
        t_mid = (t_start + t_end) / 2.0
        dur = t_end - t_start
        scene_idx = i + 1

        frame_paths: List[Path] = []
        if dur < 1.5:
            # Short scene: only mid frame
            p = frames_dir / f"scene_{scene_idx:03d}_mid.jpg"
            extract_frame(t_mid, p)
            frame_paths = [p]
        else:
            t_in = t_start + min(0.5, dur * 0.15)
            t_out = t_end - min(0.5, dur * 0.15)
            for label, t in [("in", t_in), ("mid", t_mid), ("out", t_out)]:
                p = frames_dir / f"scene_{scene_idx:03d}_{label}.jpg"
                extract_frame(t, p)
                frame_paths.append(p)

        scenes.append({"scene": scene_idx, "start": t_start, "end": t_end, "frames": frame_paths})

    console.print(f"  └─ Extracted frames for [bold green]{len(scenes)}[/bold green] scene(s).")
    return scenes


def analyze_and_consolidate_scenes(
    scenes: List[Dict[str, Any]], config: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """PASS 1A: Describe each frame via Vision AI, then consolidate to a per-scene summary via LLM."""
    console.print(f"[bold cyan]🤖 [3/7] Analyzing & consolidating scenes (Pass 1)...[/bold cyan]")

    narrate_cfg = config.get("narrate", {})
    ollama_host = config.get("ollama_host", "http://localhost:11434").rstrip("/")
    vision_model = narrate_cfg.get("vision_model", "minicpm-v")
    text_model = config.get("translator_model", "gemma4:31b-cloud")
    vision_prompt = "Describe briefly what you see in this image (1-2 short sentences): main subject, action, setting."

    scene_summaries = []
    for sc in scenes:
        idx = sc["scene"]
        t_start, t_end = sc["start"], sc["end"]
        frames = sc["frames"]

        # --- A: Describe each frame ---
        frame_descs = []
        for fp in frames:
            d = _ollama_vision(fp, vision_prompt, vision_model, ollama_host, timeout=60)
            if d:
                frame_descs.append(d)

        if not frame_descs:
            frame_descs = [f"Scene at {t_start:.1f}s"]

        # --- B: Consolidate frame descriptions into 1 scene summary ---
        if len(frame_descs) == 1:
            summary = frame_descs[0]
        else:
            labels = ["Opening frame", "Middle frame", "Closing frame"]
            frame_block = "\n".join(f"{labels[j] if j < len(labels) else 'Frame'}: {d}" for j, d in enumerate(frame_descs))
            consolidate_prompt = f"""Below are descriptions of {len(frame_descs)} frames from a single video scene [{t_start:.1f}s → {t_end:.1f}s]:
{frame_block}

Summarize in 1-2 sentences (Vietnamese) what this scene shows. Be specific about subjects and actions."""
            summary = _ollama_text(consolidate_prompt, text_model, ollama_host, timeout=90)
            if not summary:
                summary = " | ".join(frame_descs)

        console.print(f"  └─ Scene {idx} ({t_start:.1f}s-{t_end:.1f}s): {summary[:80]}{'...' if len(summary) > 80 else ''}")
        scene_summaries.append({"scene": idx, "start": t_start, "end": t_end, "summary": summary})

    return scene_summaries


def synthesize_global_story(scene_summaries: List[Dict[str, Any]], config: Dict[str, Any]) -> Dict[str, str]:
    """PASS 1B: Synthesize global story (theme, characters, plot flow) from all scene summaries."""
    console.print(f"[bold cyan]🌐 Synthesizing global video story...[/bold cyan]")

    ollama_host = config.get("ollama_host", "http://localhost:11434").rstrip("/")
    text_model = config.get("translator_model", "gemma4:31b-cloud")

    scene_list = "\n".join(
        f"Scene {s['scene']} ({s['start']:.1f}s-{s['end']:.1f}s): {s['summary']}"
        for s in scene_summaries
    )
    prompt = f"""Dưới đây là tóm tắt {len(scene_summaries)} cảnh theo thứ tự thời gian của một video:
{scene_list}

Hãy phân tích và trả lời bằng tiếng Việt:
1. Chủ đề/nội dung tổng quát của video (1-2 câu)
2. Nhân vật chính là ai? (1 câu)
3. Diễn biến chính từ đầu đến cuối? (2-3 câu ngắn)

Format trả lời:
CHỦ ĐỀ: ...
NHÂN VẬT: ...
DIỄN BIẾN: ..."""

    raw = _ollama_text(prompt, text_model, ollama_host, timeout=120)

    global_story = {"theme": "", "characters": "", "plot_flow": ""}
    if raw:
        for line in raw.splitlines():
            if line.startswith("CHỦ ĐỀ:"):
                global_story["theme"] = line.replace("CHỦ ĐỀ:", "").strip()
            elif line.startswith("NHÂN VẬT:"):
                global_story["characters"] = line.replace("NHÂN VẬT:", "").strip()
            elif line.startswith("DIỄN BIẾN:"):
                global_story["plot_flow"] = line.replace("DIỄN BIẾN:", "").strip()
        if not global_story["theme"]:
            global_story["theme"] = raw[:200]

    console.print(f"  └─ Theme: {global_story['theme'][:80]}")
    return global_story


def _truncate_at_sentence_boundary(text: str, max_words: int) -> str:
    """Truncate text at the last complete sentence within max_words."""
    words = text.split()
    if len(words) <= max_words:
        return text
    # Try to end at a sentence boundary within the budget
    truncated = " ".join(words[:max_words])
    # Find last sentence terminator
    for sep in (".", "!", "?", ";", ","):
        last = truncated.rfind(sep)
        if last > len(truncated) // 2:  # at least halfway
            return truncated[:last + 1].strip()
    return truncated.rstrip(",;:") + "."


def generate_narration_script_v2(
    scene_summaries: List[Dict[str, Any]],
    global_story: Dict[str, str],
    config: Dict[str, Any]
) -> List[Dict[str, Any]]:
    """PASS 2: Generate scene-locked narration script with global story context and per-scene word budgets."""
    console.print(f"[bold cyan]✍️ [4/7] Generating narration script (Pass 2, context-aware)...[/bold cyan]")

    narrate_cfg = config.get("narrate", {})
    style = narrate_cfg.get("script_style", "storytelling")
    ollama_host = config.get("ollama_host", "http://localhost:11434").rstrip("/")
    model_name = config.get("translator_model", "gemma4:31b-cloud")
    words_per_sec = float(narrate_cfg.get("words_per_sec", 2.5))

    # Build scene list with word budget for the prompt
    scene_items = []
    for s in scene_summaries:
        dur = round(float(s["end"]) - float(s["start"]), 2)
        max_words = max(0, int(dur * words_per_sec))
        scene_items.append({
            "scene": s["scene"],
            "start": s["start"],
            "end": s["end"],
            "duration_sec": dur,
            "max_words": max_words,
            "scene_summary": s["summary"]
        })

    prompt = f"""Bạn là biên tập viên thuyết minh video chuyên nghiệp.

NGỮ CẢNH TOÀN BỘ VIDEO:
- Chủ đề: {global_story.get('theme', 'Không rõ')}
- Nhân vật: {global_story.get('characters', 'Không rõ')}
- Diễn biến: {global_story.get('plot_flow', 'Không rõ')}

DANH SÁCH SCENE:
{json.dumps(scene_items, ensure_ascii=False, indent=2)}

NHIỆM VỤ:
1. Viết câu thuyết minh tiếng Việt cho MỖI scene, CÓ ngữ cảnh xuyên suốt của toàn bộ video.
2. Mỗi câu là 1 câu hoàn chỉnh (có chủ ngữ + vị ngữ), phong cách {style}.
3. Số từ PHẢI nhỏ hơn hoặc bằng max_words của scene đó. Nếu max_words < 5: viết text rỗng "" (bỏ qua scene quá ngắn).
4. Nếu không đủ chỗ cho câu đầy đủ: viết câu ngắn hơn nhưng vẫn có nghĩa, KHÔNG CẮT GIỮA CÂU.
5. Giữ nguyên start và end từ input.

OUTPUT: JSON array hợp lệ, không kèm markdown hay lời giải thích:
[
  {{"start": 0.0, "end": 4.2, "text": "Câu thuyết minh phù hợp với scene."}},
  {{"start": 4.2, "end": 5.0, "text": ""}},
  ...
]"""

    raw = _ollama_text(prompt, model_name, ollama_host, timeout=180)
    script_segments = _parse_json_response(raw) if raw else None

    if not script_segments:
        console.print(f"  [yellow]⚠️ LLM script generation failed. Falling back to scene summaries.[/yellow]")
        script_segments = [
            {"start": s["start"], "end": s["end"], "text": s["summary"]}
            for s in scene_summaries
        ]

    # Safety net: enforce word budget (truncate at sentence boundary)
    for seg, sc in zip(script_segments, scene_items):
        seg["start"] = float(seg.get("start", 0.0))
        seg["end"] = float(seg.get("end", seg["start"] + 2.0))
        text = seg.get("text", "").strip()
        max_w = sc.get("max_words", 20)
        if max_w < 5:
            seg["text"] = ""  # too short to narrate
        elif text and len(text.split()) > int(max_w * 1.3):
            seg["text"] = _truncate_at_sentence_boundary(text, max_w)
        else:
            seg["text"] = text

    console.print(f"  └─ Generated [bold green]{len(script_segments)}[/bold green] narration segment(s).")
    for seg in script_segments:
        dur = round(float(seg['end']) - float(seg['start']), 1)
        txt = seg.get('text', '')
        words = len(txt.split()) if txt else 0
        status = "[green]✓[/green]" if words <= int(dur * words_per_sec) + 2 else "[yellow]⚠[/yellow]"
        console.print(f"  {status} [{seg['start']}s-{seg['end']}s | {dur}s | {words}w/{int(dur*words_per_sec)}max] {txt[:60]}{'...' if len(txt) > 60 else ''}")

    return script_segments


def generate_srt_from_tts_timing(tts_timing: List[Dict[str, Any]], srt_path: Path):
    """Generate SRT from actual TTS timing: start=scene_start, end=scene_start + actual_tts_duration."""
    def format_time(seconds: float) -> str:
        ms = int((seconds - int(seconds)) * 1000)
        m, s = divmod(int(seconds), 60)
        h, m = divmod(m, 60)
        return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

    blocks = []
    for idx, seg in enumerate(tts_timing, 1):
        s_start = float(seg.get("start", 0.0))
        s_end = float(seg.get("tts_end", s_start + 2.0))
        text = seg.get("text", "").strip()
        if text:
            blocks.append(f"{idx}\n{format_time(s_start)} --> {format_time(s_end)}\n{text}\n")

    with open(srt_path, "w", encoding="utf-8") as f:
        f.write("\n".join(blocks))


# Pipeline step ordering (for cache/resume logic)
_STEP_ORDER = ["vision", "script", "tts", "render", "encode"]


def _step_idx(step: str) -> int:
    try:
        return _STEP_ORDER.index(step)
    except ValueError:
        return 0


def _load_json(path: Path) -> Any:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def run_narrate(input_video_path: Path, config: Dict[str, Any], from_step: str = "vision"):
    """Main execution entry point for narration.

    Args:
        from_step: Resume from this step, skipping earlier cached results.
                   One of: vision | script | tts | render | encode
    """
    input_video = input_video_path.resolve()
    if not input_video.exists():
        console.print(f"[bold red]Error:[/bold red] Input video not found: {input_video}")
        sys.exit(1)

    workspace_dir = Path(config.get("workspace_dir", "workspace")).resolve()
    job_id = f"job_narrate_{input_video.stem}"
    job_workspace = workspace_dir / job_id
    job_workspace.mkdir(parents=True, exist_ok=True)

    step = _step_idx(from_step)
    resume_label = f" [bold yellow](resume from: {from_step})[/bold yellow]" if from_step != "vision" else ""
    console.print(f"\n[bold magenta]🎬 Starting Video Narration Pipeline[/bold magenta]{resume_label}")
    console.print(f"📹 Input Video: [yellow]{input_video}[/yellow]")
    console.print(f"📁 Workspace:   [yellow]{job_workspace}[/yellow]\n")

    # Probe Video (always needed)
    raw_probe = FFmpegUtils.probe(input_video)
    format_data = raw_probe.get("format", {})
    streams = raw_probe.get("streams", [])
    audio_streams = [s for s in streams if s.get("codec_type") == "audio"]
    duration = float(format_data.get("duration", 0.0))
    has_audio = len(audio_streams) > 0

    narrate_cfg = config.get("narrate", {})

    # ───────────────────────────────────────────────
    # STEP: vision  (Pass 1A + 1B)
    # ───────────────────────────────────────────────
    scene_summaries_file = job_workspace / "scene_summaries.json"
    global_story_file = job_workspace / "global_story.json"

    if step <= _step_idx("vision"):
        scene_threshold = float(narrate_cfg.get("scene_threshold", 0.4))
        max_scenes = int(narrate_cfg.get("max_scenes", 30))
        timestamps = detect_scenes(input_video, duration, scene_threshold, max_scenes)
        frames_dir = job_workspace / "frames"
        scenes = extract_scene_frames(input_video, timestamps, duration, frames_dir)
        scene_summaries = analyze_and_consolidate_scenes(scenes, config)
        global_story = synthesize_global_story(scene_summaries, config)
        with open(scene_summaries_file, "w", encoding="utf-8") as f:
            json.dump(scene_summaries, f, ensure_ascii=False, indent=2)
        with open(global_story_file, "w", encoding="utf-8") as f:
            json.dump(global_story, f, ensure_ascii=False, indent=2)
    else:
        console.print(f"  [dim]⏭️  Skipping vision analysis — loading cache[/dim]")
        if not scene_summaries_file.exists() or not global_story_file.exists():
            console.print(f"[bold red]Error:[/bold red] Cannot resume from '{from_step}': missing scene_summaries.json or global_story.json in workspace. Run without --from-step first.")
            sys.exit(1)
        scene_summaries = _load_json(scene_summaries_file)
        global_story = _load_json(global_story_file)
        console.print(f"  └─ Loaded {len(scene_summaries)} scene summaries from cache.")

    # ───────────────────────────────────────────────
    # STEP: script  (Pass 2 — LLM narration writing)
    # ───────────────────────────────────────────────
    script_file = job_workspace / "narration_script.json"

    if step <= _step_idx("script"):
        script_segments = generate_narration_script_v2(scene_summaries, global_story, config)
        with open(script_file, "w", encoding="utf-8") as f:
            json.dump(script_segments, f, ensure_ascii=False, indent=2)
    else:
        console.print(f"  [dim]⏭️  Skipping script generation — loading {script_file.name}[/dim]")
        if not script_file.exists():
            console.print(f"[bold red]Error:[/bold red] Cannot resume from '{from_step}': narration_script.json not found. Run without --from-step first.")
            sys.exit(1)
        script_segments = _load_json(script_file)
        console.print(f"  └─ Loaded [bold green]{len(script_segments)}[/bold green] segments from narration_script.json.")
        for seg in script_segments:
            txt = seg.get("text", "")
            console.print(f"     [{seg.get('start', 0.0)}s-{seg.get('end', 0.0)}s] {txt[:70]}{'...' if len(txt) > 70 else ''}")

    # ───────────────────────────────────────────────
    # STEP: tts  (TTS synthesis + SRT generation)
    # ───────────────────────────────────────────────
    srt_file = job_workspace / "narration.srt"
    final_voice_wav = job_workspace / "narrate_voice.wav"
    # video_for_render may be updated if freeze frame is added
    video_for_render = input_video

    if step <= _step_idx("tts"):
        console.print(f"[bold cyan]🎙️ [5/7] Synthesizing TTS narration voiceover...[/bold cyan]")
        tts_dir = job_workspace / "tts_segments"
        tts_dir.mkdir(parents=True, exist_ok=True)

        tts_plugin = PluginLoader.load_plugin("tts", "preset_tts", config)
        speed_factor = float(config.get("tts_speed_factor", 1.5))

        tts_timing: List[Dict[str, Any]] = []
        aligned_audio_files = []
        current_time = 0.0

        for idx, seg in enumerate(script_segments, 1):
            seg_start = float(seg.get("start", 0.0))
            text = seg.get("text", "").strip()

            raw_mp3 = tts_dir / f"raw_{idx:04d}.mp3"
            wav_seg = tts_dir / f"seg_{idx:04d}.wav"
            actual_tts_dur = 0.0

            if text:
                tts_plugin.synthesize_segment(text, raw_mp3)
                if raw_mp3.exists() and raw_mp3.stat().st_size > 0:
                    filter_cmd = ["-filter:a", f"atempo={speed_factor:.2f}"] if abs(speed_factor - 1.0) > 0.05 else []
                    cmd_conv = ["ffmpeg", "-y", "-i", str(raw_mp3)] + filter_cmd + ["-ar", "44100", "-ac", "2", "-c:a", "pcm_s16le", str(wav_seg)]
                    subprocess.run(cmd_conv, capture_output=True, check=False)

            if seg_start > current_time + 0.05:
                silence_gap = seg_start - current_time
                silence_file = tts_dir / f"silence_{idx:04d}.wav"
                subprocess.run([
                    "ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo",
                    "-t", f"{silence_gap:.3f}", "-c:a", "pcm_s16le", str(silence_file)
                ], capture_output=True, check=True)
                aligned_audio_files.append(silence_file)
                current_time = seg_start

            audio_start_pos = current_time
            if wav_seg.exists() and wav_seg.stat().st_size > 0:
                actual_tts_dur = FFmpegUtils.get_audio_duration(wav_seg)
                aligned_audio_files.append(wav_seg)
                current_time += actual_tts_dur

            tts_timing.append({
                "start": audio_start_pos,
                "tts_end": round(audio_start_pos + actual_tts_dur, 3),
                "text": text
            })
            console.print(f"  └─ Seg {idx}: '{text[:40]}...' → TTS {actual_tts_dur:.2f}s [audio: {audio_start_pos:.2f}s → {audio_start_pos + actual_tts_dur:.2f}s]")

        # SRT from actual TTS timing
        generate_srt_from_tts_timing(tts_timing, srt_file)

        # Freeze frame if TTS overflows video end
        total_tts_duration = current_time
        freeze_extra = max(0.0, total_tts_duration - duration)
        if freeze_extra > 0.1:
            console.print(f"  [yellow]⚠️ TTS overflows {freeze_extra:.2f}s past video end → appending freeze frame[/yellow]")
            last_frame_img = tts_dir / "last_frame.jpg"
            freeze_clip = tts_dir / "freeze_clip.mp4"
            subprocess.run(["ffmpeg", "-y", "-sseof", "-0.1", "-i", str(input_video), "-frames:v", "1", "-q:v", "2", str(last_frame_img)], capture_output=True, check=False)
            subprocess.run(["ffmpeg", "-y", "-loop", "1", "-i", str(last_frame_img), "-t", f"{freeze_extra + 0.2:.3f}", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", "25", str(freeze_clip)], capture_output=True, check=False)
            extended_video = tts_dir / "extended_video.mp4"
            concat_video_list = tts_dir / "concat_video_list.txt"
            with open(concat_video_list, "w") as vf:
                vf.write(f"file '{input_video.absolute()}'\n")
                vf.write(f"file '{freeze_clip.absolute()}'\n")
            subprocess.run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(concat_video_list), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-an", str(extended_video)], capture_output=True, check=False)
            if extended_video.exists() and extended_video.stat().st_size > 0:
                video_for_render = extended_video
                duration = total_tts_duration

        # Pad audio to final video duration
        if duration > current_time + 0.1:
            silence_file = tts_dir / "silence_final.wav"
            subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", f"{(duration - current_time):.3f}", "-c:a", "pcm_s16le", str(silence_file)], capture_output=True, check=True)
            aligned_audio_files.append(silence_file)

        concat_list = tts_dir / "concat_list.txt"
        with open(concat_list, "w", encoding="utf-8") as lf:
            for af in aligned_audio_files:
                lf.write(f"file '{af.absolute()}'\n")
        subprocess.run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", str(concat_list), "-c:a", "pcm_s16le", str(final_voice_wav)], capture_output=True, check=False)
    else:
        console.print(f"  [dim]⏭️  Skipping TTS — loading cached narrate_voice.wav + narration.srt[/dim]")
        if not final_voice_wav.exists():
            console.print(f"[bold red]Error:[/bold red] narrate_voice.wav not found. Run with --from-step tts or earlier.")
            sys.exit(1)
        # Check if extended video was previously built
        extended_video = job_workspace / "tts_segments" / "extended_video.mp4"
        if extended_video.exists() and extended_video.stat().st_size > 0:
            video_for_render = extended_video
            tts_duration = FFmpegUtils.get_audio_duration(final_voice_wav)
            duration = tts_duration
        console.print(f"  └─ Loaded cached TTS audio ({FFmpegUtils.get_audio_duration(final_voice_wav):.2f}s).")

    # ───────────────────────────────────────────────
    # STEP: render  (inpaint + subtitle burn)
    # ───────────────────────────────────────────────
    rendered_video = job_workspace / "rendered_video.mp4"

    if step <= _step_idx("render"):
        console.print(f"[bold cyan]🧹 Inpainting old subtitles...[/bold cyan]")
        clean_video = job_workspace / "clean_video.mp4"
        inpaint_region = config.get("inpaint_region") or [0.82, 0.10, 0.92, 0.90]
        try:
            inpaint_plugin = PluginLoader.load_plugin("inpaint", "opencv_inpaint", config)
            inpaint_plugin.remove_subtitles(video_for_render, inpaint_region, clean_video)
        except Exception as e:
            console.print(f"  [yellow]⚠️ Inpaint warning ({e}), using raw video.[/yellow]")
            shutil.copy(str(video_for_render), str(clean_video))

        console.print(f"[bold cyan]🎞️ [6/7] Rendering new subtitles onto video...[/bold cyan]")
        show_sub = config.get("show_subtitle", True)
        if show_sub and srt_file.exists():
            FFmpegUtils.burn_subtitles(clean_video, srt_file, rendered_video)
        else:
            shutil.copy(str(clean_video), str(rendered_video))
    else:
        console.print(f"  [dim]⏭️  Skipping render — loading cached rendered_video.mp4[/dim]")
        if not rendered_video.exists():
            console.print(f"[bold red]Error:[/bold red] rendered_video.mp4 not found. Run with --from-step render or earlier.")
            sys.exit(1)
        console.print(f"  └─ Using cached rendered video.")

    # ───────────────────────────────────────────────
    # STEP: encode  (audio mix + final output)
    # ───────────────────────────────────────────────
    console.print(f"[bold cyan]🎛️ [7/7] Mixing audio & Encoding final video...[/bold cyan]")
    mixed_audio = job_workspace / "mixed_audio.wav"
    orig_voice_vol = float(config.get("original_voice_volume", 0.10)) if config.get("keep_original_voice", True) else 0.0
    music_src = input_video if (has_audio and orig_voice_vol > 0.0) else Path("")
    FFmpegUtils.mix_audio(
        music_path=music_src,
        voice_path=final_voice_wav,
        output_path=mixed_audio,
        music_volume=orig_voice_vol,
        voice_volume=1.0
    )

    suffix = narrate_cfg.get("output_suffix", "_narrated")
    out_filename = f"{input_video.stem}{suffix}.mp4"
    workspace_out = job_workspace / out_filename
    FFmpegUtils.encode_final(rendered_video, mixed_audio, workspace_out)

    output_dir_str = narrate_cfg.get("output_dir") or config.get("output_dir", "output")
    output_dir = Path(output_dir_str).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    final_dest = output_dir / out_filename
    shutil.copy(str(workspace_out), str(final_dest))

    console.print(f"\n[bold green]✨ Narration completed successfully![/bold green]")
    console.print(f"[bold cyan]Output File:[/bold cyan] {final_dest}\n")


def main():
    parser = argparse.ArgumentParser(
        description="Auto Narration Tool (Vision AI + Local TTS)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Resume examples:
  --from-step tts     # Re-synthesize TTS after editing narration_script.json
  --from-step render  # Re-render subtitles after changing show_subtitle/inpaint_region
  --from-step encode  # Re-encode after changing original_voice_volume
  --from-step script  # Re-generate LLM script from cached vision results
"""
    )
    parser.add_argument("input_video", help="Path to input video file")
    parser.add_argument("--config", default="config.yaml", help="Path to config.yaml")
    parser.add_argument("--output_dir", default=None, help="Directory to save output video")
    parser.add_argument(
        "--from-step",
        dest="from_step",
        default="vision",
        choices=["vision", "script", "tts", "render", "encode"],
        help="Resume from this pipeline step (skips earlier cached results)"
    )

    args = parser.parse_args()
    config = load_config(Path(args.config))

    if args.output_dir:
        config["output_dir"] = args.output_dir

    input_video = Path(args.input_video)
    run_narrate(input_video, config, from_step=args.from_step)


if __name__ == "__main__":
    main()
