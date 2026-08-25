import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict

import numpy as np
import soundfile as sf

from core.step_base import StepBase


def _apply_spectral_gate(input_path: Path, output_path: Path, prop_decrease: float = 0.9) -> bool:
    """Apply noisereduce Spectral Gate to remove vocal ghost residue from a WAV file.
    
    Args:
        input_path: Source WAV file path
        output_path: Destination cleaned WAV file path
        prop_decrease: Aggressiveness of noise suppression (0.0 to 1.0).
                       0.8 = soft, 0.9 = recommended, 1.0 = maximum
    Returns:
        True if successful, False on error.
    """
    try:
        import noisereduce as nr
        audio_data, sample_rate = sf.read(str(input_path))

        # Estimate noise profile from first 0.5s of audio (usually contains ambient noise)
        noise_sample_frames = min(int(sample_rate * 0.5), len(audio_data))
        if audio_data.ndim == 2:
            # Stereo: process each channel independently then merge
            reduced_channels = []
            for ch in range(audio_data.shape[1]):
                noise_clip = audio_data[:noise_sample_frames, ch]
                reduced = nr.reduce_noise(
                    y=audio_data[:, ch],
                    y_noise=noise_clip,
                    sr=sample_rate,
                    prop_decrease=prop_decrease,
                    stationary=False
                )
                reduced_channels.append(reduced)
            cleaned = np.stack(reduced_channels, axis=-1)
        else:
            # Mono
            noise_clip = audio_data[:noise_sample_frames]
            cleaned = nr.reduce_noise(
                y=audio_data,
                y_noise=noise_clip,
                sr=sample_rate,
                prop_decrease=prop_decrease,
                stationary=False
            )

        sf.write(str(output_path), cleaned, sample_rate)
        return True
    except Exception as e:
        print(f"[AudioSeparate] Spectral gate failed ({e}), keeping original.")
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

        orig_voice_file = audio_dir / "orig_voice.wav"
        shutil.copy(str(audio_stream), str(orig_voice_file))

        # Separate vocals & background music using Demucs AI
        try:
            from core.concurrency import ConcurrencyManager
            workers = ConcurrencyManager.get_num_workers(config)
            device = config.get("device", "auto")
            device_flag = ["-d", "mps"] if device in ["auto", "mps"] else []
            cmd = [sys.executable, "-m", "demucs.separate", "--two-stems", "vocals", "-j", str(workers)] + device_flag + ["-o", str(audio_dir), str(audio_stream)]
            print(f"[AudioSeparate] Running AI Demucs audio separation with {workers} CPU workers...")
            subprocess.run(cmd, capture_output=True, check=True)

            # Demucs creates demucs/htdemucs/{track_name}/vocals.wav and no_vocals.wav
            track_name = audio_stream.stem
            separated_base = audio_dir / "htdemucs" / track_name
            if (separated_base / "vocals.wav").exists():
                shutil.move(str(separated_base / "vocals.wav"), str(voice_file))
                shutil.move(str(separated_base / "no_vocals.wav"), str(music_file))
                effect_file.touch()
        except Exception as e:
            print(f"[AudioSeparate] Demucs separation failed ({e}). Falling back to FFmpeg filter.")
            shutil.copy(str(audio_stream), str(voice_file))
            cmd_no_vocal = [
                "ffmpeg", "-y", "-i", str(audio_stream),
                "-af", "pan=stereo|c0=0.5*c0-0.5*c1|c1=0.5*c1-0.5*c0",
                "-c:a", "pcm_s16le", str(music_file)
            ]
            res = subprocess.run(cmd_no_vocal, capture_output=True, check=False)
            if res.returncode != 0 or not music_file.exists() or music_file.stat().st_size == 0:
                music_file.touch()
            effect_file.touch()

        # Apply Spectral Gate noise reduction to remove vocal ghost/residue from background track
        noise_prop_decrease = float(config.get("noise_reduction_strength", 0.9))

        if music_file.exists() and music_file.stat().st_size > 0:
            print(f"[AudioSeparate] Applying Spectral Gate noise reduction (strength={noise_prop_decrease})...")
            cleaned_music = audio_dir / "music_cleaned.wav"
            if _apply_spectral_gate(music_file, cleaned_music, prop_decrease=noise_prop_decrease):
                shutil.move(str(cleaned_music), str(music_file))
                print(f"[AudioSeparate] Spectral gate applied successfully.")

        return {
            "voice": str(voice_file),
            "music": str(music_file),
            "effect": str(effect_file),
            "orig_voice": str(orig_voice_file)
        }

