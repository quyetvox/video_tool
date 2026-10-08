"""
AI Lecture Illustrator Package.
Module thứ 4 của Sub-Video: Tự động minh họa video bài giảng giáo dục.
"""

from .models import (
    BatchActiveAsset,
    BatchPrompts,
    LectureBatch,
    LectureProjectConfig,
    LectureProject,
)
from .common import (
    emit_json,
    emit_log,
    emit_progress,
    safe_ensure_dir,
    clean_json_str,
)
from .knowledge_extractor import (
    group_transcript_into_semantic_batches,
    extract_lecture_knowledge,
)
from .subtitles import (
    generate_lecture_srt,
    generate_lecture_ass,
)
from .visual_renderer import (
    render_lecture_video,
)

__all__ = [
    "BatchActiveAsset",
    "BatchPrompts",
    "LectureBatch",
    "LectureProjectConfig",
    "LectureProject",
    "emit_json",
    "emit_log",
    "emit_progress",
    "safe_ensure_dir",
    "clean_json_str",
    "group_transcript_into_semantic_batches",
    "extract_lecture_knowledge",
    "generate_lecture_srt",
    "generate_lecture_ass",
    "render_lecture_video",
]
