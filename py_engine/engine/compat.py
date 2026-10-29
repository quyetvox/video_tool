"""Backward-compat aliases: legacy top-level names (utils.x, steps.x, main, ...) resolve to the SAME
module objects as the new engine.* names, so imports and mock.patch on old names keep working."""
import importlib
import importlib.abc
import importlib.util
import sys

_PKG = {
    "core": "engine.core",
    "steps": "engine.pipeline.steps",
    "plugins": "engine.pipeline.plugins",
    "movie_review": "engine.features.movie_review",
    "lecture_illustrator": "engine.features.lecture_illustrator",
    "utils": "engine.shared",
    "tools": "engine.cli",
}
_MOD = {
    "analyze_video": "engine.media_tools.analyze_video",
    "batch_translate": "engine.cli.batch_translate",
    "blur_text_boxes": "engine.media_tools.blur_text_boxes",
    "composite_render": "engine.features.render.composite_render",
    "compress_video": "engine.media_tools.compress_video",
    "concat": "engine.media_tools.concat",
    "copyright_scan": "engine.media_tools.copyright_scan",
    "core.concurrency": "engine.core.concurrency",
    "core.config_adapter": "engine.core.config_adapter",
    "core.job_state": "engine.core.job_state",
    "core.pipeline_runner": "engine.core.pipeline_runner",
    "core.plugin_loader": "engine.core.plugin_loader",
    "core.project_manager": "engine.core.project_manager",
    "core.step_base": "engine.core.step_base",
    "detect_text_boxes": "engine.media_tools.detect_text_boxes",
    "download": "engine.features.downloader.download",
    "extract_frames": "engine.media_tools.extract_frames",
    "html_to_mp4": "engine.features.render.html_to_mp4",
    "lecture_illustrator.__init__": "engine.features.lecture_illustrator.__init__",
    "lecture_illustrator.common": "engine.features.lecture_illustrator.common",
    "lecture_illustrator.html_calibrator": "engine.features.lecture_illustrator.html_calibrator",
    "lecture_illustrator.knowledge_extractor": "engine.features.lecture_illustrator.knowledge_extractor",
    "lecture_illustrator.models": "engine.features.lecture_illustrator.models",
    "lecture_illustrator.scene_author": "engine.features.lecture_illustrator.scene_author",
    "lecture_illustrator.scene_planner": "engine.features.lecture_illustrator.scene_planner",
    "lecture_illustrator.scene_renderer": "engine.features.lecture_illustrator.scene_renderer",
    "lecture_illustrator.scene_validator": "engine.features.lecture_illustrator.scene_validator",
    "lecture_illustrator.subtitles": "engine.features.lecture_illustrator.subtitles",
    "lecture_illustrator.text_script_parser": "engine.features.lecture_illustrator.text_script_parser",
    "lecture_illustrator.visual_renderer": "engine.features.lecture_illustrator.visual_renderer",
    "lecture_illustrator_orchestrator": "engine.features.lecture_illustrator.orchestrator",
    "long_video_orchestrator": "engine.features.long_video.orchestrator",
    "main": "engine.cli.main",
    "media_link_tool": "engine.features.downloader.media_link_tool",
    "movie_review.__init__": "engine.features.movie_review.__init__",
    "movie_review.alignment": "engine.features.movie_review.alignment",
    "movie_review.assembler": "engine.features.movie_review.assembler",
    "movie_review.common": "engine.features.movie_review.common",
    "movie_review.detectors": "engine.features.movie_review.detectors",
    "movie_review.generators": "engine.features.movie_review.generators",
    "movie_review.subtitles": "engine.features.movie_review.subtitles",
    "movie_review_orchestrator": "engine.features.movie_review.orchestrator",
    "narrate": "engine.features.tts_studio.narrate",
    "narration_voice_generator": "engine.features.tts_studio.narration_voice_generator",
    "ocr_cli": "engine.cli.ocr_cli",
    "ocr_translator": "engine.cli.ocr_translator",
    "plugins.asr.mlx_whisper": "engine.pipeline.plugins.asr.mlx_whisper",
    "plugins.asr.whisper": "engine.pipeline.plugins.asr.whisper",
    "plugins.asr.whisper_fallback": "engine.pipeline.plugins.asr.whisper_fallback",
    "plugins.asr.whisper_mlx": "engine.pipeline.plugins.asr.whisper_mlx",
    "plugins.inpaint.apple_vision_inpaint": "engine.pipeline.plugins.inpaint.apple_vision_inpaint",
    "plugins.inpaint.ffmpeg_blur": "engine.pipeline.plugins.inpaint.ffmpeg_blur",
    "plugins.inpaint.opencv_inpaint": "engine.pipeline.plugins.inpaint.opencv_inpaint",
    "plugins.interfaces": "engine.pipeline.plugins.interfaces",
    "plugins.ocr.apple_vision": "engine.pipeline.plugins.ocr.apple_vision",
    "plugins.ocr.paddle_ocr": "engine.pipeline.plugins.ocr.paddle_ocr",
    "plugins.ocr.rapid_ocr": "engine.pipeline.plugins.ocr.rapid_ocr",
    "plugins.translation.ollama_qwen": "engine.pipeline.plugins.translation.ollama_qwen",
    "plugins.translation.openai": "engine.pipeline.plugins.translation.openai",
    "plugins.tts.preset_tts": "engine.pipeline.plugins.tts.preset_tts",
    "process_video_segment": "engine.media_tools.process_video_segment",
    "remove_text": "engine.media_tools.remove_text",
    "steps.s01_probe": "engine.pipeline.steps.s01_probe",
    "steps.s02_demux": "engine.pipeline.steps.s02_demux",
    "steps.s03_subtitle_detect": "engine.pipeline.steps.s03_subtitle_detect",
    "steps.s04_audio_separate": "engine.pipeline.steps.s04_audio_separate",
    "steps.s05_asr": "engine.pipeline.steps.s05_asr",
    "steps.s05b_gender_detect": "engine.pipeline.steps.s05b_gender_detect",
    "steps.s06_ocr": "engine.pipeline.steps.s06_ocr",
    "steps.s07_transcript_merge": "engine.pipeline.steps.s07_transcript_merge",
    "steps.s08_translation": "engine.pipeline.steps.s08_translation",
    "steps.s08b_metadata_gen": "engine.pipeline.steps.s08b_metadata_gen",
    "steps.s08c_timing": "engine.pipeline.steps.s08c_timing",
    "steps.s09_subtitle_gen": "engine.pipeline.steps.s09_subtitle_gen",
    "steps.s10_inpaint": "engine.pipeline.steps.s10_inpaint",
    "steps.s11_subtitle_render": "engine.pipeline.steps.s11_subtitle_render",
    "steps.s12_tts": "engine.pipeline.steps.s12_tts",
    "steps.s13_audio_mix": "engine.pipeline.steps.s13_audio_mix",
    "steps.s14_encode": "engine.pipeline.steps.s14_encode",
    "storage": "engine.features.cloud_storage.storage",
    "tools.media_link_tool": "engine.features.downloader.media_link_tool",
    "tools.ocr_cli": "engine.cli.ocr_cli",
    "trim": "engine.media_tools.trim",
    "tts_studio_tool": "engine.features.tts_studio.tts_studio_tool",
    "utils.audio_vad": "engine.shared.audio_vad",
    "utils.chunk_manifest": "engine.features.long_video.chunk_manifest",
    "utils.concat_utils": "engine.media_tools.concat_utils",
    "utils.ffmpeg_utils": "engine.shared.ffmpeg_utils",
    "utils.gender_detector": "engine.shared.gender_detector",
    "utils.movie_review_tts": "engine.shared.movie_review_tts",
    "utils.pkg_bootstrap": "engine.shared.pkg_bootstrap",
    "utils.process_guardian": "engine.shared.process_guardian",
    "utils.repetition_cleaner": "engine.shared.repetition_cleaner",
    "utils.resource_guard": "engine.shared.resource_guard",
    "utils.safe_cast": "engine.shared.safe_cast",
    "utils.smart_splitter": "engine.features.long_video.smart_splitter",
    "utils.storage_manager": "engine.features.cloud_storage.storage_manager",
    "utils.trimmer_utils": "engine.media_tools.trimmer_utils",
    "utils.tts_cache_manager": "engine.features.tts_studio.tts_cache_manager",
    "utils.vlog_story_prompts": "engine.features.vlog_story.vlog_story_prompts",
    "vlog_story_orchestrator": "engine.features.vlog_story.orchestrator",
}


def _target(name):
    if name.startswith("py_engine."):
        name = name[len("py_engine."):]
    if name in _MOD:
        return _MOD[name]
    head, _, rest = name.partition(".")
    if head in _PKG:
        return _PKG[head] + ("." + rest if rest else "")
    return None


class _Loader(importlib.abc.Loader):
    def __init__(self, target):
        self._target = target
        self._spec = None

    def create_module(self, spec):
        mod = importlib.import_module(self._target)
        self._spec = mod.__spec__
        return mod

    def exec_module(self, module):
        module.__spec__ = self._spec  # import machinery overwrote it with the alias spec


class _Finder(importlib.abc.MetaPathFinder):
    def find_spec(self, name, path=None, target=None):
        t = _target(name)
        if t is None:
            return None
        return importlib.util.spec_from_loader(name, _Loader(t))


def install():
    if not any(isinstance(f, _Finder) for f in sys.meta_path):
        sys.meta_path.insert(0, _Finder())
