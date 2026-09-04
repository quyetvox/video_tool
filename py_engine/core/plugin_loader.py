import importlib
import logging
import sys
from typing import Any, Dict

logger = logging.getLogger("sub_video")


class PluginLoader:
    @staticmethod
    def load_plugin(plugin_category: str, plugin_name: str, config: Dict[str, Any]) -> Any:
        is_windows = sys.platform == "win32"
        whisper_default = "whisper" if is_windows else "whisper_mlx"

        aliases = {
            "paddleocr": "paddle_ocr",
            "applevision": "apple_vision",
            "edgetts": "edge_tts",
            "ffmpegblur": "ffmpeg_blur",
            "mlx_whisper": "whisper_mlx",
            "mlx": whisper_default,
            "whisper": whisper_default,
            "openai_whisper": "whisper",
        }
        clean_name = plugin_name.lower().replace("-", "_")
        normalized_name = aliases.get(clean_name, clean_name)
        module_path = f"plugins.{plugin_category}.{normalized_name}"

        try:
            module = importlib.import_module(module_path)
            if hasattr(module, "Plugin"):
                return module.Plugin(config)
            else:
                raise AttributeError(f"Module '{module_path}' does not define a 'Plugin' class.")
        except Exception as e:
            logger.error(f"Failed to load plugin '{plugin_name}' from '{plugin_category}': {e}")
            raise
