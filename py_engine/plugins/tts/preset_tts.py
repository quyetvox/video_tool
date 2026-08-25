import asyncio
import time
import subprocess
from pathlib import Path
from typing import Any, Dict, Optional

from plugins.interfaces import TTSBase


class Plugin(TTSBase):
    def synthesize_segment(self, text: str, output_path: Path, voice: Optional[str] = None) -> Path:
        target_lang = self.config.get("target_lang", "vi")
        enable_gender = self.config.get("enable_gender_tts", False)
        selected_voice = voice or self.config.get("tts_voice", "vi")

        def _is_valid(p: Path) -> bool:
            return p.exists() and p.stat().st_size > 500

        def _clean_invalid(p: Path):
            if p.exists() and p.stat().st_size <= 500:
                try:
                    p.unlink()
                except Exception:
                    pass

        # 1. Fast gTTS Mode (Ban Mai voice) for "vi", "default", "preset", or when gender TTS is disabled
        if not enable_gender or selected_voice in ("vi", "default", "preset"):
            try:
                from gtts import gTTS
                tts = gTTS(text=text, lang=target_lang)
                tts.save(str(output_path))
                if _is_valid(output_path):
                    return output_path
                _clean_invalid(output_path)
            except Exception:
                _clean_invalid(output_path)

        # 2. EdgeTTS Mode (for Neural Voices like vi-VN-NamMinhNeural / vi-VN-HoaiMyNeural)
        if selected_voice.startswith("vi-VN-"):
            for attempt in range(3):
                try:
                    import edge_tts

                    async def _edge_synth():
                        communicate = edge_tts.Communicate(text, selected_voice)
                        await communicate.save(str(output_path))

                    asyncio.run(_edge_synth())
                    if _is_valid(output_path):
                        return output_path
                    _clean_invalid(output_path)
                except Exception:
                    _clean_invalid(output_path)
                    time.sleep(0.5)

        # 3. Fallback: gTTS
        try:
            from gtts import gTTS
            tts = gTTS(text=text, lang=target_lang)
            tts.save(str(output_path))
            if _is_valid(output_path):
                return output_path
            _clean_invalid(output_path)
        except Exception:
            _clean_invalid(output_path)

        # 4. Fallback: macOS say command
        try:
            cmd = ["say", "-v", "Linh", text, "-o", str(output_path)]
            subprocess.run(cmd, check=True)
            if _is_valid(output_path):
                return output_path
            _clean_invalid(output_path)
        except Exception:
            _clean_invalid(output_path)

        raise RuntimeError(f"TTS synthesis failed for text: '{text[:30]}...'")
