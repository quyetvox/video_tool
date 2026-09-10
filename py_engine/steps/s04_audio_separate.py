import os
import logging
import warnings
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

import numpy as np
import soundfile as sf
import torch

from core.step_base import StepBase

# Suppress Hugging Face warnings & HTTP logs
os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
os.environ["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
warnings.filterwarnings("ignore", category=UserWarning, module="huggingface_hub")
warnings.filterwarnings("ignore", message=".*unauthenticated requests.*")
logging.getLogger("huggingface_hub").setLevel(logging.ERROR)
logging.getLogger("httpx").setLevel(logging.ERROR)
try:
    from huggingface_hub.utils import logging as hf_logging
    hf_logging.set_verbosity_error()
    import huggingface_hub.utils._http as _hf_http
    _hf_http._WARNED_TOPICS.add("")
    _hf_http._WARNED_TOPICS.add("unauthenticated")
except Exception:
    pass

_DEMUCS_MODEL_CACHE: Dict[str, Tuple[Any, str]] = {}


def get_cached_demucs_model(model_name: str = "htdemucs", preferred_device: str = "auto") -> Tuple[Any, str]:
    """Retrieve or load cached Demucs model in memory for ultra-fast repeat inference."""
    global _DEMUCS_MODEL_CACHE
    if model_name in _DEMUCS_MODEL_CACHE:
        return _DEMUCS_MODEL_CACHE[model_name]

    if preferred_device == "auto":
        if torch.cuda.is_available():
            device = "cuda"
        elif hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
            device = "mps"
        else:
            device = "cpu"
    else:
        device = preferred_device

    print(f"[AudioSeparate] Loading Demucs model '{model_name}' on device: {device}...")
    
    from demucs.pretrained import get_model
    model = get_model(model_name)

    model.to(device)
    model.eval()
    _DEMUCS_MODEL_CACHE[model_name] = (model, device)
    return model, device


def _apply_spectral_gate(input_path: Path, output_path: Path, prop_decrease: float = 0.9) -> bool:
    """Apply noisereduce Spectral Gate to remove vocal ghost residue from a WAV file."""
    if prop_decrease <= 0.0:
        return False
    try:
        import noisereduce as nr
        audio_data, sample_rate = sf.read(str(input_path))

        noise_sample_frames = min(int(sample_rate * 0.5), len(audio_data))
        if audio_data.ndim == 2:
            noise_clip = audio_data[:noise_sample_frames]
            cleaned = nr.reduce_noise(
                y=audio_data.T,
                y_noise=noise_clip.T,
                sr=sample_rate,
                prop_decrease=prop_decrease,
                stationary=True
            ).T
        else:
            noise_clip = audio_data[:noise_sample_frames]
            cleaned = nr.reduce_noise(
                y=audio_data,
                y_noise=noise_clip,
                sr=sample_rate,
                prop_decrease=prop_decrease,
                stationary=True
            )

        sf.write(str(output_path), cleaned, sample_rate)
        return True
    except Exception as e:
        print(f"[AudioSeparate] Spectral gate skipped/failed ({e}), keeping original.")
        return False


class StepAudioSeparate(StepBase):
    step_id = "s04_audio_separate"
    depends_on = ["s02_demux"]

    def run(self, workspace: Path, config: Dict[str, Any], job_state: Any) -> Dict[str, Any]:
        demux_info = job_state.get_step_output("s02_demux") or {}
        audio_stream = Path(demux_info["audio_stream"])

        if config.get("ocr_only", False):
            print("[AudioSeparate] ocr_only mode enabled: Bypassing Demucs audio separation (~0s).")
            return {
                "skipped": True,
                "voice": str(audio_stream),
                "music": str(audio_stream),
                "effect": str(audio_stream),
                "orig_voice": str(audio_stream)
            }

        audio_dir = workspace / "audio_separated"
        audio_dir.mkdir(parents=True, exist_ok=True)

        voice_file = audio_dir / "voice.wav"
        music_file = audio_dir / "music.wav"
        effect_file = audio_dir / "effect.wav"

        # 1. Direct In-Memory Demucs Separation (35% faster + Zero subprocess overhead)
        separated_success = False
        try:
            from demucs.apply import apply_model

            device_setting = str(config.get("device", "auto")).lower()
            model, device = get_cached_demucs_model("htdemucs", preferred_device=device_setting)

            # Configure CPU threads on Windows / non-GPU environments
            if device == "cpu":
                try:
                    from core.concurrency import ConcurrencyManager
                    num_threads = ConcurrencyManager.get_num_workers(config)
                    torch.set_num_threads(max(1, num_threads))
                except Exception:
                    pass

            print(f"[AudioSeparate] Running Direct In-Memory Demucs on {device.upper()} (shifts=0, overlap=0.1)...")
            data, sr = sf.read(str(audio_stream))
            if data.ndim == 1:
                data = np.stack([data, data], axis=-1)
            elif data.shape[1] > 2:
                data = data[:, :2]

            wav_tensor = torch.from_numpy(data.T).float()

            with torch.inference_mode():
                sources = apply_model(
                    model,
                    wav_tensor[None].to(device),
                    device=device,
                    shifts=0,
                    split=True,
                    overlap=0.1
                )[0]

            vocal_idx = model.sources.index("vocals")
            vocal_wav = sources[vocal_idx].cpu().numpy().T
            other_indices = [i for i in range(len(model.sources)) if i != vocal_idx]
            no_vocal_wav = sources[other_indices].sum(dim=0).cpu().numpy().T

            sf.write(str(voice_file), vocal_wav, sr)
            sf.write(str(music_file), no_vocal_wav, sr)
            effect_file.touch()
            separated_success = True
            print(f"[AudioSeparate] In-Memory Demucs separation completed successfully.")
        except Exception as e:
            print(f"[AudioSeparate] In-memory Demucs failed ({e}). Falling back to CLI subprocess mode...")

        # Fallback to CLI Demucs if in-memory fails
        if not separated_success:
            try:
                from core.concurrency import ConcurrencyManager
                workers = ConcurrencyManager.get_num_workers(config)
                device = config.get("device", "auto")
                device_flag = ["-d", "mps"] if device in ["auto", "mps"] else []
                cmd = [sys.executable, "-m", "demucs.separate", "--two-stems", "vocals", "-j", str(workers)] + device_flag + ["-o", str(audio_dir), str(audio_stream)]
                subprocess.run(cmd, capture_output=True, check=True)

                track_name = audio_stream.stem
                separated_base = audio_dir / "htdemucs" / track_name
                if (separated_base / "vocals.wav").exists():
                    shutil.move(str(separated_base / "vocals.wav"), str(voice_file))
                    shutil.move(str(separated_base / "no_vocals.wav"), str(music_file))
                    effect_file.touch()
                    separated_success = True
            except Exception as cli_err:
                print(f"[AudioSeparate] Demucs CLI fallback also failed ({cli_err}). Using pan stereo fallback.")
                shutil.copy(str(audio_stream), str(voice_file))
                cmd_no_vocal = [
                    "ffmpeg", "-y", "-i", str(audio_stream),
                    "-af", "pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0",
                    "-c:a", "pcm_s16le", str(music_file)
                ]
                subprocess.run(cmd_no_vocal, capture_output=True, check=False)
                if not music_file.exists() or music_file.stat().st_size == 0:
                    music_file.touch()
                effect_file.touch()

        # 2. Spectral Gate noise reduction (optional)
        noise_prop_decrease = float(config.get("noise_reduction_strength", 0.0))
        if noise_prop_decrease > 0.0 and music_file.exists() and music_file.stat().st_size > 0:
            print(f"[AudioSeparate] Applying Spectral Gate noise reduction (strength={noise_prop_decrease})...")
            cleaned_music = audio_dir / "music_cleaned.wav"
            if _apply_spectral_gate(music_file, cleaned_music, prop_decrease=noise_prop_decrease):
                shutil.move(str(cleaned_music), str(music_file))

        return {
            "voice": str(voice_file),
            "music": str(music_file),
            "effect": str(effect_file),
            "orig_voice": str(voice_file)
        }
