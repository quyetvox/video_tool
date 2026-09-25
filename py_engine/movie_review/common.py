"""
Common utilities, IPC emitters, word budget calculators, and config resolvers
for the Movie Review engine.
"""

import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

ROOT_DIR = Path(__file__).parent.parent.parent.resolve()
ENGINE_DIR = Path(__file__).parent.parent.resolve()


# ─── IPC STREAMING LOGS TO FLUTTER ───────────────────────────────────────────

def emit_json(data: Dict[str, Any]):
    """Emit JSON protocol line for Flutter Desktop UI IPC."""
    print(json.dumps(data, ensure_ascii=False), flush=True)


def emit_log(level: str, message: str, step_id: str = "movie_review"):
    """Emit structured log for Flutter Desktop console."""
    emit_json({
        "type": "log",
        "level": level,
        "step_id": step_id,
        "message": message,
        "timestamp": time.time(),
    })


def emit_progress(progress: float, status: str, step_id: str = "movie_review"):
    """Emit progress update for Flutter Desktop progress indicators."""
    emit_json({
        "type": "progress",
        "step_id": step_id,
        "progress": round(progress, 3),
        "status": status,
        "timestamp": time.time(),
    })


def safe_ensure_dir(target_dir: Path, fallback_subdir: str = "movie_review") -> Path:
    """
    Đảm bảo thư mục tồn tại và có quyền ghi.
    Nếu target_dir nằm trong thư mục được bảo vệ (như Program Files trên Windows, /Applications trên macOS)
    hoặc ném ra PermissionError / OSError:
    Tự động fallback sang thư mục Sandbox người dùng (~/.subvideo hoặc %LOCALAPPDATA%/.subvideo).
    """
    target = Path(target_dir).resolve()
    try:
        target.mkdir(parents=True, exist_ok=True)
        # Test quyền ghi thực tế
        probe_file = target / f".probe_write_{os.getpid()}"
        probe_file.write_text("ok")
        probe_file.unlink(missing_ok=True)
        return target
    except (PermissionError, OSError) as e:
        local_app = os.environ.get("LOCALAPPDATA") or os.environ.get("USERPROFILE")
        user_base = (Path(local_app) / ".subvideo") if local_app else (Path.home() / ".subvideo")

        parts = target.parts
        if "resources" in parts:
            idx = parts.index("resources")
            rel_sub = Path(*parts[idx:])
        else:
            rel_sub = Path("workspace") / fallback_subdir / target.name

        fallback_dir = (user_base / rel_sub).resolve()
        try:
            fallback_dir.mkdir(parents=True, exist_ok=True)
        except Exception:
            # Cuối cùng fallback về home directory
            fallback_dir = (Path.home() / ".subvideo" / rel_sub).resolve()
            fallback_dir.mkdir(parents=True, exist_ok=True)

        emit_log("warning", f"⚠️ Không có quyền ghi vào '{target}' ({e}). Đã tự động chuyển vùng làm việc sang: '{fallback_dir}'")
        return fallback_dir


# ─── WORD COUNT & DURATION CALIBRATION (SOP) ─────────────────────────────────

def calculate_optimal_review_duration(movie_duration_sec: float) -> int:
    """
    Căn chỉnh thời lượng review tối ưu (Sweet-Spot) theo thời lượng thực tế của phim:
    - Phim ngắn <= 20 phút (<=1200s): review 180s - 240s (3-4 phút)
    - Tập phim 20-60 phút (1200-3600s): review 300s - 480s (5-8 phút)
    - Phim điện ảnh 60-150 phút (3600-9000s): review 480s - 720s (8-12 phút)
    - Phim siêu dài > 150 phút (>9000s): review 720s - 900s (12-15 phút, cap ở 15 phút tránh lan man)
    """
    if movie_duration_sec <= 1200:
        return 180
    elif movie_duration_sec <= 3600:
        raw = int(round(movie_duration_sec * 0.12 / 60.0)) * 60
        return max(300, min(480, raw))
    elif movie_duration_sec <= 9000:
        raw = int(round(movie_duration_sec * 0.08 / 60.0)) * 60
        return max(480, min(720, raw))
    else:
        return 900


def calculate_word_budget(
    target_duration_sec: Optional[int] = None,
    speed_factor: float = 1.45,
    movie_duration_sec: Optional[float] = None,
    review_style: str = "critique",
    acts_config: Optional[Dict[str, Any]] = None
) -> Dict[str, Any]:
    """
    SOP Công thức quy đổi số chữ theo tốc độ đọc TTS (Thesis-Driven Review):
    Total Words = (Duration_min) x (140 x speed_factor)
    Hỗ trợ phân rã số Chương (Chapters) linh hoạt.
    Khi target_duration_sec is None: Tự động tính toán theo thời lượng phim gốc (Content-Driven Deep-Dive).
    Khi acts_config được truyền: Tùy chỉnh bật/tắt và tỷ lệ % cho từng hồi Hook, Story, Review, Outro.
    """
    speed = max(0.8, min(2.0, speed_factor))
    words_per_min = 140.0 * speed

    # Content-Driven Deep-Dive: Tự động xác định thời lượng và số chương nếu không có target_duration_sec
    if target_duration_sec is None or target_duration_sec <= 0:
        m_dur = movie_duration_sec or 3600.0
        if m_dur <= 1800.0:  # <= 30 phút
            target_sec = 600   # 10 phút review
            num_chapters = 6
        elif m_dur <= 3600.0:  # <= 60 phút
            target_sec = 840   # 14 phút review
            num_chapters = 8
        else:                  # > 60 phút
            target_sec = 1080  # 18 phút review
            num_chapters = 10
    else:
        target_sec = target_duration_sec
        # Phân chương động dựa theo target_sec, luôn đảm bảo tối thiểu 4 chương nếu là story_review
        if target_sec <= 360:
            num_chapters = 4 if review_style == "story_review" else 0
        elif target_sec <= 600:
            num_chapters = 4
        elif target_sec <= 840:
            num_chapters = 6
        else:
            num_chapters = 8

    # Nếu acts_config có danh sách chapters cụ thể được chọn
    if acts_config:
        selected_ch = (
            acts_config.get("selected_chapters")
            or acts_config.get("selected_chapter_ids")
            or acts_config.get("chapters")
            or (acts_config.get("story", {}).get("chapters") if isinstance(acts_config.get("story"), dict) else None)
        )
        if isinstance(selected_ch, (list, tuple)) and len(selected_ch) > 0:
            num_chapters = len(selected_ch)

    minutes = max(1.0, target_sec / 60.0)
    total_words = int(round(minutes * words_per_min))

    if acts_config:
        def _parse_act(key: str, default_pct: float):
            val = acts_config.get(key)
            if isinstance(val, dict):
                enabled = bool(val.get("enabled", True))
                pct = float(val.get("pct", default_pct))
            elif isinstance(val, bool):
                enabled = val
                pct = float(acts_config.get(f"{key}_pct", default_pct))
            else:
                enabled = bool(acts_config.get(f"enable_{key}", True))
                pct = float(acts_config.get(f"{key}_pct", default_pct))
            return enabled, pct

        default_h_pct = 0.10 if review_style == "story_review" else 0.15
        default_r_pct = 0.10 if review_style == "story_review" else 0.30
        default_o_pct = 0.05 if review_style == "story_review" else 0.10

        hook_enabled, hook_pct = _parse_act("hook", default_h_pct)
        story_enabled, story_pct = _parse_act("story", 0.75 if review_style == "story_review" else 0.45)
        review_enabled, review_pct = _parse_act("review", default_r_pct)
        outro_enabled, outro_pct = _parse_act("outro", default_o_pct)

        hook_words = max(20, int(round(total_words * hook_pct))) if hook_enabled and hook_pct > 0 else 0
        review_words = max(30, int(round(total_words * review_pct))) if review_enabled and review_pct > 0 else 0
        outro_words = max(20, int(round(total_words * outro_pct))) if outro_enabled and outro_pct > 0 else 0

        if story_enabled:
            story_words = max(50, total_words - hook_words - review_words - outro_words)
        else:
            story_words = 0
            num_chapters = 0
    elif review_style == "story_review":
        hook_words = max(30, int(round(total_words * 0.10)))
        review_words = max(50, int(round(total_words * 0.10)))
        outro_words = max(30, int(round(total_words * 0.05)))
        story_words = max(80, total_words - hook_words - review_words - outro_words)
    else:
        hook_words = max(30, int(round(total_words * 0.15)))
        review_words = max(60, int(round(total_words * 0.30)))
        outro_words = max(30, int(round(total_words * 0.10)))
        story_words = max(80, total_words - hook_words - review_words - outro_words)

    chapter_words = max(150, story_words // max(1, num_chapters)) if num_chapters > 0 else story_words

    return {
        "total_words": total_words,
        "target_duration_sec": target_sec,
        "hook_words": hook_words,
        "story_words": story_words,
        "review_words": review_words,
        "outro_words": outro_words,
        "words_per_min": int(round(words_per_min)),
        "num_chapters": num_chapters,
        "chapter_words": chapter_words,
        "acts_config": acts_config,
    }


def clean_json_str(raw_text: str) -> str:
    """Loại bỏ markdown code fences (```json ... ```) và khoảng trắng thừa từ response LLM."""
    if not raw_text:
        return ""
    text = raw_text.strip()
    match = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", text, re.IGNORECASE)
    if match:
        return match.group(1).strip()
    if text.startswith("```") and text.endswith("```"):
        lines = text.splitlines()
        if len(lines) >= 2:
            return "\n".join(lines[1:-1]).strip()
    return text


def load_project_config(
    video_path: Optional[Path] = None,
    workspace: Optional[Path] = None
) -> Tuple[Dict[str, Any], Optional[Path]]:
    """Tìm và đọc file config.yaml của project gần nhất."""
    search_paths = []
    if video_path:
        vp = Path(video_path).resolve()
        search_paths.append(vp.parent / "config.yaml")
        search_paths.append(vp.parent.parent / "config.yaml")
        for parent in vp.parents:
            search_paths.append(parent / "config.yaml")
            if parent == ROOT_DIR:
                break

    if workspace:
        w = Path(workspace).resolve()
        search_paths.append(w / "config.yaml")
        for parent in w.parents:
            search_paths.append(parent / "config.yaml")
            if parent == ROOT_DIR:
                break

    search_paths.append(ROOT_DIR / "config.yaml")

    for p in search_paths:
        try:
            if p.is_file():
                import yaml
                data = yaml.safe_load(p.read_text(encoding="utf-8")) or {}
                if data:
                    return data, p
        except Exception:
            pass
    return {}, None


def resolve_gemini_config(
    provided_key: Optional[str] = None,
    provided_model: Optional[str] = None,
    workspace: Optional[Path] = None,
    video_path: Optional[Path] = None
) -> Tuple[str, str]:
    """Xác định Gemini API Key và Model theo thứ tự ưu tiên:
    1. CLI Argument / tham số trực tiếp.
    2. Biến môi trường GEMINI_API_KEY / GEMINI_MODEL.
    3. File config.yaml của project (quét ngược lên từ video_path hoặc workspace) hoặc root config.yaml.
       Ưu tiên đọc từ các khóa: movie_review: -> translator: -> translation: -> root.
    """
    api_key = (provided_key or "").strip()
    model = (provided_model or "").strip()

    if not api_key:
        api_key = os.environ.get("GEMINI_API_KEY", "").strip()

    if not model:
        model = os.environ.get("GEMINI_MODEL", "").strip()

    # Tìm config.yaml từ video_path hoặc workspace
    data, cfg_path = load_project_config(video_path=video_path, workspace=workspace)
    if data:
        # 1. Đọc API Key nếu chưa có
        if not api_key:
            mr = data.get("movie_review", {})
            trans = data.get("translator", {}) or data.get("translation", {})
            k = (
                mr.get("api_key") or mr.get("gemini_api_key") or
                trans.get("api_key") or trans.get("gemini_api_key") or
                data.get("gemini_api_key") or data.get("api_key")
            )
            if k and isinstance(k, str) and k.strip():
                api_key = k.strip()

        # 2. Đọc Model nếu chưa có
        if not model:
            mr = data.get("movie_review", {})
            trans = data.get("translator", {}) or data.get("translation", {})
            m = mr.get("model") or trans.get("model") or data.get("gemini_model")
            if m and isinstance(m, str) and m.strip():
                model = m.strip()

    # Fallback mặc định cho model
    if not model:
        model = "gemini-2.5-flash"

    return api_key, model


def resolve_gemini_api_key(
    provided_key: Optional[str] = None,
    workspace: Optional[Path] = None,
    video_path: Optional[Path] = None
) -> str:
    """Helper tương thích ngược chỉ lấy API Key."""
    key, _ = resolve_gemini_config(provided_key=provided_key, workspace=workspace, video_path=video_path)
    return key
