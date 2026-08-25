import copy
from typing import Any, Dict, Optional


# Mapping from legacy flat config keys to nested dot-paths
FLAT_TO_NESTED_MAP = {
    # App
    "device": "app.device",
    "num_workers": "app.num_workers",
    "target_lang": "app.target_lang",
    "secondary_lang": "app.secondary_lang",
    "ocr_only": "app.ocr_only",
    "video_bitrate": "app.video_bitrate",
    "output_suffix": "app.output_suffix",
    "workspace_dir": "app.workspace_dir",
    "output_dir": "app.output_dir",
    "duration": "app.duration",

    # ASR
    "asr": "asr.engine",
    "asr_model": "asr.model",

    # OCR
    "ocr": "ocr.engine",
    "ocr_num_workers": "ocr.num_workers",
    "ocr_mode": "ocr.mode",
    "ocr_diff_threshold": "ocr.diff_threshold",
    "ocr_diff_step": "ocr.diff_step",
    "subtitle_detect_start_sec": "ocr.detect_start_sec",
    "subtitle_detect_duration_sec": "ocr.detect_duration_sec",

    # Inpaint
    "inpaint": "inpaint.engine",
    "inpaint_show_box": "inpaint.show_box",
    "inpaint_method": "inpaint.method",
    "inpaint_color": "inpaint.color",
    "inpaint_region": "inpaint.region",
    "blur_radius": "inpaint.blur_radius",
    "blur_box_padding_y": "inpaint.padding_y",
    "inpaint_box_bg_color": "inpaint.box.bg_color",
    "inpaint_box_bg_opacity": "inpaint.box.bg_opacity",
    "inpaint_box_border_color": "inpaint.box.border_color",
    "inpaint_box_border_width": "inpaint.box.border_width",
    "inpaint_box_border_radius": "inpaint.box.border_radius",

    # Subtitle
    "show_subtitle": "subtitle.show",
    "subtitle_show_primary": "subtitle.show_primary",
    "subtitle_region": "subtitle.region",
    "subtitle_primary_region": "subtitle.region",
    "subtitle_order": "subtitle.order",
    "subtitle_box_split": "subtitle.box_split",
    "subtitle_box_gap": "subtitle.box_gap",
    "subtitle_font_name": "subtitle.font_name",
    "subtitle_font_color": "subtitle.font_color",
    "subtitle_outline_color": "subtitle.outline_color",
    "subtitle_font_size": "subtitle.font_size",
    "subtitle_char_rate": "subtitle.char_rate",
    "subtitle_safety_margin": "subtitle.safety_margin",
    "subtitle_fill_gap": "subtitle.fill_gap",
    "subtitle_max_gap_fill": "subtitle.max_gap_fill",
    "subtitle_secondary_show": "subtitle.secondary.show",
    "subtitle_secondary_region": "subtitle.secondary.region",
    "subtitle_secondary_font_name": "subtitle.secondary.font_name",
    "subtitle_secondary_font_size_scale": "subtitle.secondary.font_size_scale",
    "subtitle_secondary_font_color": "subtitle.secondary.font_color",
    "subtitle_secondary_outline_color": "subtitle.secondary.outline_color",
    # Legacy fallbacks
    "subtitle_style": "inpaint.engine",
    "subtitle_box_enabled": "inpaint.box",
    "subtitle_box_bg_opacity": "inpaint.box.bg_opacity",
    "subtitle_box_border_color": "inpaint.box.border_color",
    "subtitle_box_border_width": "inpaint.box.border_width",

    # Watermark
    "watermark_enable": "watermark.enabled",
    "watermark_region": "watermark.region",
    "watermark_image": "watermark.image",
    "watermark_text": "watermark.text",
    "watermark_font_name": "watermark.font_name",
    "watermark_font_color": "watermark.font_color",
    "watermark_opacity": "watermark.opacity",
    "watermark_blur_bg": "watermark.blur_bg",

    # TTS
    "tts": "tts.engine",
    "tts_voice": "tts.voice",
    "tts_num_workers": "tts.num_workers",
    "tts_speed_factor": "tts.speed_factor",
    "enable_gender_tts": "tts.enable_gender",
    "tts_voice_male": "tts.voice_male",
    "tts_voice_female": "tts.voice_female",

    # Audio
    "tts_voice_volume": "audio.volumes.tts_voice",
    "original_voice_volume": "audio.volumes.original_voice",
    "music_volume": "audio.volumes.music",
    "background_music_volume": "audio.volumes.music",
    "ambient_volume": "audio.volumes.ambient",
    "noise_reduction_strength": "audio.filters.noise_reduction_strength",
    "ambient_split_threshold": "audio.filters.ambient_split_threshold",

    # Translator
    "translator_model": "translator.model",
    "translator_api_key": "translator.api_key",
    "translator_base_url": "translator.base_url",
    "translator_batch_size": "translator.batch_size",
}


class ConfigDict(dict):
    """
    Smart Hierarchical Configuration Dictionary.
    Seamlessly supports both nested access (e.g. config['audio']['volumes']['music'])
    and flat legacy access (e.g. config.get('music_volume') or dot-notation config.get('audio.volumes.music')).
    """

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._wrap_nested()

    def _wrap_nested(self):
        for k, v in list(self.items()):
            if isinstance(v, dict) and not isinstance(v, ConfigDict):
                self[k] = ConfigDict(v)

    def copy(self) -> "ConfigDict":
        return ConfigDict(copy.deepcopy(dict(self)))

    def __deepcopy__(self, memo):
        return ConfigDict(copy.deepcopy(dict(self), memo))

    def _get_by_dot_path(self, dot_path: str) -> Any:
        parts = dot_path.split(".")
        curr = self
        for part in parts:
            if not isinstance(curr, dict) or not dict.__contains__(curr, part):
                return None
            curr = dict.__getitem__(curr, part)
        return curr

    def get(self, key: str, default: Any = None) -> Any:
        # Special: Inpaint Region Smart Lookup (supports inpaint: [...], inpaint.region, inpaint_region)
        if key in ("inpaint_region", "inpaint.region"):
            # 1. inpaint.region
            val = self._get_by_dot_path("inpaint.region")
            if val is not None and isinstance(val, (list, tuple)) and len(val) == 4:
                return list(val)
            # 2. inpaint.inpaint_region
            val = self._get_by_dot_path("inpaint.inpaint_region")
            if val is not None and isinstance(val, (list, tuple)) and len(val) == 4:
                return list(val)
            # 3. Direct inpaint_region key
            if dict.__contains__(self, "inpaint_region"):
                val = dict.__getitem__(self, "inpaint_region")
                if val is not None and isinstance(val, (list, tuple)) and len(val) == 4:
                    return list(val)
            # 4. inpaint key directly contains a 4-element list/tuple
            if dict.__contains__(self, "inpaint"):
                val = dict.__getitem__(self, "inpaint")
                if isinstance(val, (list, tuple)) and len(val) == 4:
                    return list(val)
            return default

        # Special: Inpaint Engine Smart Lookup
        if key in ("inpaint", "inpaint.engine"):
            val = self._get_by_dot_path("inpaint.engine")
            if isinstance(val, str) and val.strip():
                return val.strip()
            if dict.__contains__(self, "inpaint"):
                inpaint_val = dict.__getitem__(self, "inpaint")
                if isinstance(inpaint_val, str) and inpaint_val.strip():
                    return inpaint_val.strip()
            return default if default is not None else "box_color"

        # 1. Known flat alias to nested dot-path (e.g. 'ocr' -> 'ocr.engine', 'music_volume' -> 'audio.volumes.music')
        if key in FLAT_TO_NESTED_MAP:
            val = self._get_by_dot_path(FLAT_TO_NESTED_MAP[key])
            if val is not None:
                return val

        # 2. Dot-notation path (e.g., 'audio.volumes.music')
        if "." in key:
            val = self._get_by_dot_path(key)
            if val is not None:
                return val

        # 3. Direct key in dictionary
        if dict.__contains__(self, key):
            val = dict.__getitem__(self, key)
            return val if val is not None else default

        return default

    def __contains__(self, key: object) -> bool:
        if not isinstance(key, str):
            return dict.__contains__(self, key)
        if dict.__contains__(self, key):
            return True
        if "." in key:
            return self._get_by_dot_path(key) is not None
        if key in FLAT_TO_NESTED_MAP:
            return self._get_by_dot_path(FLAT_TO_NESTED_MAP[key]) is not None
        return False

    def __getitem__(self, key: str) -> Any:
        # 1. Direct key in dictionary (e.g. config['ocr'] returns the ocr block dict)
        if dict.__contains__(self, key):
            val = dict.__getitem__(self, key)
            if val is not None:
                return val

        # 2. Dot-notation path (e.g., config['audio.volumes.music'])
        if "." in key:
            val = self._get_by_dot_path(key)
            if val is not None:
                return val

        # 3. Known flat alias
        if key in FLAT_TO_NESTED_MAP:
            val = self._get_by_dot_path(FLAT_TO_NESTED_MAP[key])
            if val is not None:
                return val

        raise KeyError(key)

    def deep_merge(self, other: Dict[str, Any]):
        """Recursively merges another dictionary into self."""
        for k, v in other.items():
            if k in self and isinstance(self[k], dict) and isinstance(v, dict):
                if not isinstance(self[k], ConfigDict):
                    self[k] = ConfigDict(self[k])
                self[k].deep_merge(v)
            else:
                self[k] = ConfigDict(v) if isinstance(v, dict) else v


def wrap_config(raw_dict: Optional[Dict[str, Any]]) -> ConfigDict:
    """Wraps a regular Python dictionary in a Smart ConfigDict."""
    return ConfigDict(raw_dict or {})
