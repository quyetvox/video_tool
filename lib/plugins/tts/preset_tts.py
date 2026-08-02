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

        # 1. Fast gTTS Mode (Ban Mai voice) for "vi", "default", "preset", or when gender TTS is disabled
        if not enable_gender or selected_voice in ("vi", "default", "preset"):
            try:
                from gtts import gTTS
                tts = gTTS(text=text, lang=target_lang)
                tts.save(str(output_path))
                if output_path.exists() and output_path.stat().st_size > 0:
                    return output_path
            except Exception:
                pass

        # 2. EdgeTTS Mode (for Neural Voices like vi-VN-NamMinhNeural / vi-VN-HoaiMyNeural)
        if selected_voice.startswith("vi-VN-"):
            for attempt in range(3):
                try:
                    import edge_tts

                    async def _edge_synth():
                        communicate = edge_tts.Communicate(text, selected_voice)
                        await communicate.save(str(output_path))

                    asyncio.run(_edge_synth())
                    if output_path.exists() and output_path.stat().st_size > 0:
                        return output_path
                except Exception:
                    time.sleep(0.5)

        # 3. Fallback: gTTS
        try:
            from gtts import gTTS
            tts = gTTS(text=text, lang=target_lang)
            tts.save(str(output_path))
            if output_path.exists() and output_path.stat().st_size > 0:
                return output_path
        except Exception:
            pass

        # 4. Fallback: macOS say command
        try:
            cmd = ["say", "-v", "Linh", text, "-o", str(output_path)]
            subprocess.run(cmd, check=True)
            return output_path
        except Exception:
            output_path.touch(exist_ok=True)
            return output_path
