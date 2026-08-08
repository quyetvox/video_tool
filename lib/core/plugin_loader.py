import importlib
import logging
from typing import Any, Dict

logger = logging.getLogger("sub_video")


class PluginLoader:
    @staticmethod
    def load_plugin(plugin_category: str, plugin_name: str, config: Dict[str, Any]) -> Any:
        aliases = {
            "paddleocr": "paddle_ocr",
            "edgetts": "edge_tts",
            "ffmpegblur": "ffmpeg_blur",
        }
        normalized_name = aliases.get(plugin_name.lower(), plugin_name)
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
