from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any, Dict, List


class ASRBase(ABC):
    def __init__(self, config: Dict[str, Any]):
        self.config = config

    @abstractmethod
    def transcribe(self, audio_path: Path) -> List[Dict[str, Any]]:
        """Transcribe audio file and return list of segments: [{start, end, text}]."""
        pass


class OCRBase(ABC):
    def __init__(self, config: Dict[str, Any]):
        self.config = config

    @abstractmethod
    def extract_text(self, video_path: Path, region: List[float]) -> List[Dict[str, Any]]:
        """Extract text from video region: [{start, end, text}]."""
        pass


class TranslatorBase(ABC):
    def __init__(self, config: Dict[str, Any]):
        self.config = config

    @abstractmethod
    def translate_segments(self, segments: List[Dict[str, Any]], target_lang: str) -> List[Dict[str, Any]]:
        """Translate segments list to target_lang."""
        pass


class TTSBase(ABC):
    def __init__(self, config: Dict[str, Any]):
        self.config = config

    @abstractmethod
    def synthesize_segment(self, text: str, output_path: Path) -> Path:
        """Synthesize single text segment into audio file."""
        pass


class InpaintBase(ABC):
    def __init__(self, config: Dict[str, Any]):
        self.config = config

    @abstractmethod
    def remove_subtitles(self, video_path: Path, region: List[float], output_video: Path) -> Path:
        """Remove subtitle region from video frames."""
        pass
