"""
Data models and schemas for AI Lecture Illustrator.
"""

from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional


@dataclass
class BatchActiveAsset:
    file_path: str = ""
    type: str = "image"  # "image", "video", "diagram"
    source: str = "none"  # "none", "user_import", "ai_generated"
    layout: str = "pip"  # "pip", "full", "split", "custom"
    locked: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "BatchActiveAsset":
        if not data:
            return cls()
        return cls(
            file_path=str(data.get("file_path", "")),
            type=str(data.get("type", "image")),
            source=str(data.get("source", "none")),
            layout=str(data.get("layout", "pip")),
            locked=bool(data.get("locked", False)),
        )


@dataclass
class BatchPrompts:
    image_prompt: str = ""
    diagram_mermaid: str = ""
    animation_concept: str = ""
    code_animation: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "BatchPrompts":
        if not data:
            return cls()
        return cls(
            image_prompt=str(data.get("image_prompt", "")),
            diagram_mermaid=str(data.get("diagram_mermaid", "")),
            animation_concept=str(data.get("animation_concept", "")),
            code_animation=str(data.get("code_animation", "")),
        )


@dataclass
class LectureBatch:
    id: str
    start_sec: float
    end_sec: float
    transcript_original: str
    transcript_translated: str = ""
    educational_intent: str = "CONCEPT"  # PROCESS, DEFINITION, COMPARISON, STRUCTURE, etc.
    visual_priority: str = "HIGH"  # HIGH, MEDIUM, LOW, KEEP_ORIGINAL
    prompts: BatchPrompts = field(default_factory=BatchPrompts)
    active_asset: Optional[BatchActiveAsset] = None
    sentences: List[Dict[str, Any]] = field(default_factory=list)  # {text_orig,text,start,end,duration} theo timeline TTS
    scene: Dict[str, Any] = field(default_factory=dict)  # scene JSON (template, title, steps, photo)
    step_starts: List[float] = field(default_factory=list)  # giây bắt đầu mỗi câu, tính từ đầu cảnh
    scene_duration: float = 0.0
    scene_video: str = ""  # mp4 cảnh đã render (cache)

    def to_dict(self) -> Dict[str, Any]:
        res = {
            "id": self.id,
            "start_sec": round(self.start_sec, 3),
            "end_sec": round(self.end_sec, 3),
            "transcript_original": self.transcript_original,
            "transcript_translated": self.transcript_translated,
            "educational_intent": self.educational_intent,
            "visual_priority": self.visual_priority,
            "prompts": self.prompts.to_dict() if self.prompts else {},
            "sentences": self.sentences,
            "scene": self.scene,
            "step_starts": self.step_starts,
            "scene_duration": round(self.scene_duration, 3),
            "scene_video": self.scene_video,
        }
        if self.active_asset:
            res["active_asset"] = self.active_asset.to_dict()
        else:
            res["active_asset"] = None
        return res

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "LectureBatch":
        prompts_raw = data.get("prompts") or {}
        asset_raw = data.get("active_asset")
        return cls(
            id=str(data.get("id", "")),
            start_sec=float(data.get("start_sec", 0.0)),
            end_sec=float(data.get("end_sec", 0.0)),
            transcript_original=str(data.get("transcript_original", "")),
            transcript_translated=str(data.get("transcript_translated", "")),
            educational_intent=str(data.get("educational_intent", "CONCEPT")),
            visual_priority=str(data.get("visual_priority", "HIGH")),
            prompts=BatchPrompts.from_dict(prompts_raw),
            active_asset=BatchActiveAsset.from_dict(asset_raw) if asset_raw else None,
            sentences=list(data.get("sentences") or []),
            scene=dict(data.get("scene") or {}),
            step_starts=[float(v) for v in (data.get("step_starts") or [])],
            scene_duration=float(data.get("scene_duration", 0.0)),
            scene_video=str(data.get("scene_video", "")),
        )


@dataclass
class LectureProjectConfig:
    source_lang: str = "auto"
    target_lang: str = "vi"
    secondary_lang: str = "en"
    pronoun_mode: str = "formal"
    voice_mode: str = "tts_dub"  # "original" | "tts_dub"
    tts_voice: str = "ban_mai"
    tts_speed: float = 1.15
    bgm_volume: float = 0.10
    voice_volume: float = 1.0
    burn_subtitles: bool = True
    subtitle_mode: str = "bilingual"  # "single" | "bilingual"
    subtitle_secondary_show: bool = True
    subtitle_order: str = "primary_top"  # "primary_top" | "primary_bottom"
    font_name: str = "Be Vietnam Pro"
    secondary_font_name: Optional[str] = None
    font_size: str = "26"
    font_color: str = "&H00FFFFFF"
    outline_color: str = "&H00000000"
    secondary_font_color: str = "&H00E7E1DC"
    secondary_scale: float = 0.70
    video_bitrate: str = "6000k"
    watermark_enabled: bool = False
    watermark_path: str = ""
    enable_inpaint: bool = False
    inpaint_engine: str = "ffmpeg_blur"  # "ffmpeg_blur", "box_color", "apple_vision_inpaint", "opencv"
    inpaint_blur_radius: int = 20
    box_bg_color: str = "#000000"
    box_opacity: float = 0.85
    inpaint_method: str = "vertical_gradient"  # "vertical_gradient", "navier_stokes", "telea"
    inpaint_region: List[float] = field(default_factory=lambda: [0.82, 0.10, 0.92, 0.90])
    visual_layout_preset: str = "pip"  # "pip", "full", "split"

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "LectureProjectConfig":
        if not data:
            return cls()
        reg = data.get("inpaint_region")
        if not (isinstance(reg, list) and len(reg) == 4):
            reg = [0.82, 0.10, 0.92, 0.90]
        else:
            reg = [float(v) for v in reg]
        sec_font = data.get("secondary_font_name")
        return cls(
            source_lang=str(data.get("source_lang", "auto")),
            target_lang=str(data.get("target_lang", "vi")),
            secondary_lang=str(data.get("secondary_lang", "en")),
            pronoun_mode=str(data.get("pronoun_mode", "formal")),
            voice_mode=str(data.get("voice_mode", "tts_dub")),
            tts_voice=str(data.get("tts_voice", "ban_mai")),
            tts_speed=float(data.get("tts_speed", 1.15)),
            bgm_volume=float(data.get("bgm_volume", 0.10)),
            voice_volume=float(data.get("voice_volume", 1.0)),
            burn_subtitles=bool(data.get("burn_subtitles", True)),
            subtitle_mode=str(data.get("subtitle_mode", "bilingual")),
            subtitle_secondary_show=bool(data.get("subtitle_secondary_show", True)),
            subtitle_order=str(data.get("subtitle_order", "primary_top")),
            font_name=str(data.get("font_name", "Be Vietnam Pro")),
            secondary_font_name=str(sec_font) if sec_font else None,
            font_size=str(data.get("font_size", "26")),
            font_color=str(data.get("font_color", "&H00FFFFFF")),
            outline_color=str(data.get("outline_color", "&H00000000")),
            secondary_font_color=str(data.get("secondary_font_color", "&H00E7E1DC")),
            secondary_scale=float(data.get("secondary_scale", 0.70)),
            video_bitrate=str(data.get("video_bitrate", "6000k")),
            watermark_enabled=bool(data.get("watermark_enabled", False)),
            watermark_path=str(data.get("watermark_path", "")),
            enable_inpaint=bool(data.get("enable_inpaint", False)),
            inpaint_engine=str(data.get("inpaint_engine", "ffmpeg_blur")),
            inpaint_blur_radius=int(data.get("inpaint_blur_radius", 20)),
            box_bg_color=str(data.get("box_bg_color", "#000000")),
            box_opacity=float(data.get("box_opacity", 0.85)),
            inpaint_method=str(data.get("inpaint_method", "vertical_gradient")),
            inpaint_region=reg,
            visual_layout_preset=str(data.get("visual_layout_preset", "pip")),
        )


@dataclass
class LectureProject:
    project_name: str
    video_path: str
    video_duration: float = 0.0
    video_width: int = 1920
    video_height: int = 1080
    config: LectureProjectConfig = field(default_factory=LectureProjectConfig)
    batches: List[LectureBatch] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "project_name": self.project_name,
            "video_path": self.video_path,
            "video_duration": round(self.video_duration, 3),
            "video_width": self.video_width,
            "video_height": self.video_height,
            "config": self.config.to_dict(),
            "batches": [b.to_dict() for b in self.batches],
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> "LectureProject":
        batches_raw = data.get("batches") or []
        cfg_raw = data.get("config") or {}
        return cls(
            project_name=str(data.get("project_name", "default")),
            video_path=str(data.get("video_path", "")),
            video_duration=float(data.get("video_duration", 0.0)),
            video_width=int(data.get("video_width", 1920)),
            video_height=int(data.get("video_height", 1080)),
            config=LectureProjectConfig.from_dict(cfg_raw),
            batches=[LectureBatch.from_dict(b) for b in batches_raw],
        )
