"""
Sub-Video AI Movie Review Package:
Modularized architecture for two-stage hierarchical review generation & audio-anchor video assembly.
"""

from .common import (
    emit_json,
    emit_log,
    emit_progress,
    calculate_optimal_review_duration,
    calculate_word_budget,
    clean_json_str,
    load_project_config,
    resolve_gemini_config,
    resolve_gemini_api_key,
)

from .subtitles import (
    split_long_segments_by_speed,
    wrap_subtitle_text,
    split_subtitle_into_rhythmic_cues,
    _color_to_ass,
    generate_review_ass_subtitles,
    build_inpaint_filter,
)

from .detectors import TargetedSceneDetector

from .alignment import VisualAlignmentEngine

from .generators import (
    NarrativeBlueprintGenerator,
    GoldenScriptGenerator,
)

from .assembler import (
    VoiceoverSynthesizer,
    MovieReviewAssembler,
)

__all__ = [
    # Common / IPC / Budget / Config
    "emit_json",
    "emit_log",
    "emit_progress",
    "calculate_optimal_review_duration",
    "calculate_word_budget",
    "clean_json_str",
    "load_project_config",
    "resolve_gemini_config",
    "resolve_gemini_api_key",
    # Subtitles & Inpaint
    "split_long_segments_by_speed",
    "wrap_subtitle_text",
    "split_subtitle_into_rhythmic_cues",
    "_color_to_ass",
    "generate_review_ass_subtitles",
    "build_inpaint_filter",
    # Detectors
    "TargetedSceneDetector",
    # Alignment
    "VisualAlignmentEngine",
    # Generators
    "NarrativeBlueprintGenerator",
    "GoldenScriptGenerator",
    # Assembler
    "VoiceoverSynthesizer",
    "MovieReviewAssembler",
]
