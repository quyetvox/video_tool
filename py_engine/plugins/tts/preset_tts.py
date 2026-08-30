import asyncio
import hashlib
import os
import re
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from plugins.interfaces import TTSBase


def normalize_vietnamese_text(text: str) -> str:
    """Normalize symbols, currencies, percentages, and clean filler characters."""
    t = text.strip()
    if not t:
        return ""

    # Currency
    t = re.sub(r'(\d+)\s*\$', r'\1 đô la', t)
    t = re.sub(r'\$\s*(\d+)', r'\1 đô la', t)
    t = re.sub(r'(\d+)\s*k(?=\s|$|[.,!?])', r'\1 nghìn', t, flags=re.IGNORECASE)
    t = re.sub(r'(\d+)\s*tr(?=\s|$|[.,!?])', r'\1 triệu', t, flags=re.IGNORECASE)

    # Symbols & Units
    t = re.sub(r'(\d+)\s*%', r'\1 phần trăm', t)
    t = re.sub(r'(\d+)\s*km/h', r'\1 ki lô mét trên giờ', t, flags=re.IGNORECASE)
    t = re.sub(r'(\d+)\s*kg', r'\1 ki lô gam', t, flags=re.IGNORECASE)
    t = re.sub(r'(\d+)\s*m(?=\s|$|[.,!?])', r'\1 mét', t)

    # Common tech acronyms
    t = re.sub(r'\bAI\b', 'Ây Ai', t)
    t = re.sub(r'\bCEO\b', 'Si I Ô', t)

    # Clean multiple punctuation
    t = re.sub(r'[\~\|\^\*]', '', t)
    t = re.sub(r'\s+', ' ', t).strip()
    return t


class Plugin(TTSBase):
    def __init__(self, config: Dict[str, Any] = None):
        super().__init__(config)
        self.cache_dir = Path.home() / ".subvideo" / "tts_cache"
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def _get_cache_path(self, text: str, voice: str, rate: str) -> Path:
        key = f"{text}_{voice}_{rate}".encode("utf-8")
        h = hashlib.md5(key).hexdigest()
        return self.cache_dir / f"{h}.mp3"

    def _synth_gtts_single(self, text: str, output_path: Path, lang: str = "vi") -> bool:
        norm_text = normalize_vietnamese_text(text)
        if not norm_text:
            return False

        cache_file = self._get_cache_path(norm_text, f"gtts_{lang}", "+0%")
        if cache_file.exists() and cache_file.stat().st_size > 500:
            try:
                import shutil
                shutil.copy2(cache_file, output_path)
                return True
            except Exception:
                pass

        try:
            from gtts import gTTS
            tts = gTTS(text=norm_text, lang=lang)
            tts.save(str(output_path))
            if output_path.exists() and output_path.stat().st_size > 500:
                try:
                    import shutil
                    shutil.copy2(output_path, cache_file)
                except Exception:
                    pass
                return True
        except Exception:
            pass
        return False

    def _resolve_voice(self, voice: Optional[str]) -> str:
        v = (voice or "vi-VN-BanMai").strip().lower()
        # 1. Nhóm Ban Mai (Google TTS)
        if v in ("vi-vn-banmai", "vi-banmai", "banmai", "gtts", "google", "vi_gtts", "vi", "default", "preset"):
            return "gtts_vi"
        # 2. Nhóm EdgeTTS Nam Minh
        if v in ("vi-vn-namminhneural", "namminh", "male", "nam"):
            return "vi-VN-NamMinhNeural"
        # 3. Nhóm EdgeTTS Hoài My
        if v in ("vi-vn-hoaimyneural", "hoaimy", "female", "nu"):
            return "vi-VN-HoaiMyNeural"
        return voice or "gtts_vi"

    async def _async_synth_edge_single(
        self,
        sem: asyncio.Semaphore,
        text: str,
        output_path: Path,
        voice: str,
        rate: str = "+0%"
    ) -> bool:
        norm_text = normalize_vietnamese_text(text)
        if not norm_text or len(norm_text) < 1:
            return False

        resolved_voice = self._resolve_voice(voice)
        cache_file = self._get_cache_path(norm_text, resolved_voice, rate)
        if cache_file.exists() and cache_file.stat().st_size > 500:
            try:
                import shutil
                shutil.copy2(cache_file, output_path)
                return True
            except Exception:
                pass

        async with sem:
            for attempt in range(5):
                try:
                    import edge_tts
                    communicate = edge_tts.Communicate(norm_text, resolved_voice, rate=rate)
                    await communicate.save(str(output_path))
                    if output_path.exists() and output_path.stat().st_size > 500:
                        try:
                            import shutil
                            shutil.copy2(output_path, cache_file)
                        except Exception:
                            pass
                        return True
                    if output_path.exists() and output_path.stat().st_size <= 500:
                        output_path.unlink(missing_ok=True)
                except Exception:
                    if output_path.exists() and output_path.stat().st_size <= 500:
                        output_path.unlink(missing_ok=True)
                    await asyncio.sleep(0.4 * (attempt + 1))

        return False

    def synthesize_batch(
        self,
        items: List[Dict[str, Any]],
        default_voice: str = "vi",
        speed_factor: float = 1.0
    ) -> List[Tuple[int, Path, bool]]:
        """
        Synthesize multiple segments concurrently:
        - gTTS (Ban Mai): concurrent ThreadPoolExecutor
        - EdgeTTS (Hoài My / Nam Minh): concurrent asyncio Semaphore(4)
        """
        edge_items = []
        gtts_items = []

        for item in items:
            raw_v = item.get("voice") or default_voice
            resolved_v = self._resolve_voice(raw_v)
            if resolved_v == "gtts_vi":
                item["voice"] = "gtts_vi"
                gtts_items.append(item)
            else:
                item["voice"] = resolved_v
                edge_items.append(item)

        results = {}

        # 1. Synthesize gTTS items in thread pool (only when explicitly requested)
        if gtts_items:
            from concurrent.futures import ThreadPoolExecutor
            with ThreadPoolExecutor(max_workers=4) as pool:
                futures = {
                    pool.submit(self._synth_gtts_single, itm["text"], itm["output_path"], "vi"): (itm["id"], itm["output_path"])
                    for itm in gtts_items
                }
                for fut, (idx, out_p) in futures.items():
                    try:
                        ok = fut.result()
                        results[idx] = (idx, out_p, bool(ok and out_p.exists() and out_p.stat().st_size > 500))
                    except Exception:
                        results[idx] = (idx, out_p, False)

        # 2. Synthesize EdgeTTS items via asyncio with Semaphore(4)
        if edge_items:
            async def _run_edge():
                sem = asyncio.Semaphore(4)
                tasks = []
                for item in edge_items:
                    idx = item["id"]
                    text = item["text"]
                    out_p = item["output_path"]
                    voice = item.get("voice") or "vi-VN-HoaiMyNeural"
                    item_speed = float(item.get("speed_factor", speed_factor))
                    item_rate_percent = int(round((item_speed - 1.0) * 100))
                    item_rate_str = f"+{item_rate_percent}%" if item_rate_percent >= 0 else f"{item_rate_percent}%"
                    tasks.append((idx, out_p, self._async_synth_edge_single(sem, text, out_p, voice, rate=item_rate_str)))

                gathered = await asyncio.gather(*[t[2] for t in tasks], return_exceptions=True)
                for (idx, out_p, _), success in zip(tasks, gathered):
                    is_ok = bool(success is True and out_p.exists() and out_p.stat().st_size > 500)
                    results[idx] = (idx, out_p, is_ok)

            try:
                loop = asyncio.get_event_loop()
                if loop.is_running():
                    import nest_asyncio
                    nest_asyncio.apply()
                    loop.run_until_complete(_run_edge())
                else:
                    loop.run_until_complete(_run_edge())
            except Exception:
                asyncio.run(_run_edge())

        return [results[item["id"]] for item in items if item["id"] in results]

    def synthesize_segment(self, text: str, output_path: Path, voice: Optional[str] = None) -> Path:
        selected_voice = voice or self.config.get("tts_voice", "vi")
        res = self.synthesize_batch([{"id": 0, "text": text, "output_path": output_path, "voice": selected_voice}])
        if res and res[0][2]:
            return output_path
        raise RuntimeError(f"TTS synthesis failed for text: '{text[:30]}...'")
