# AI Video Translator — Final Design Document (MVP v1)

> **Brainstorming completed**: 2026-07-26  
> **Status**: Validated & Approved  

---

## 1. Understanding Summary

| # | Điểm |
|---|------|
| 1 | **Sản phẩm**: AI Video Translator chạy 100% local, Python, open-source AI models |
| 2 | **Input**: Handle cả 3 loại — burn-in subtitle, embedded subtitle track, không có subtitle |
| 3 | **Hardware primary**: Apple Silicon (M1/M2/M3/M4) — tối ưu MPS; hỗ trợ thêm CUDA và CPU |
| 4 | **TTS MVP**: Giọng Việt preset cố định; Production sẽ clone giọng gốc + multi-speaker |
| 5 | **Pipeline resilience**: Cache từng bước ra disk, resume từ bước lỗi, auto-cleanup sau export |
| 6 | **UI**: CLI first — mở rộng Web UI / Desktop sau |
| 7 | **Transcript Merge**: Tiered Cascading (embedded → OCR+ASR → ASR only) |
| 8 | **Translation default**: Qwen2.5 qua Ollama (local) |

---

## 2. Assumptions

- Subtitle gốc chủ yếu: tiếng Trung, Anh, Nhật → dịch sang **tiếng Việt**
- MVP **không làm Lip Sync** — để production
- MVP **Subtitle Inpainting** dùng OpenCV — chấp nhận artifact nhẹ ở background phức tạp
- Pipeline chạy **tuần tự** (sequential) trong MVP — không parallel
- **Không dùng Redis/RQ** trong MVP — thêm sau khi làm Web UI
- Ollama đã được user cài sẵn trên máy
- Cache directory: `./workspace/{job_id}/` — cleanup sau export thành công

---

## 3. Decision Log

| # | Quyết định | Alternatives | Lý do chọn |
|---|---|---|---|
| D1 | ASR Mac: `mlx-whisper` | vanilla `whisper` | 2-3x nhanh hơn trên M-series, Metal backend |
| D2 | Bỏ Redis+RQ ở MVP | Redis+RQ, Celery | CLI single-user không cần queue, giảm operational complexity |
| D3 | Translation: Batch JSON | Per-segment call | ~10x ít Ollama calls, context tốt hơn |
| D4 | Burnin detect: OpenCV heuristic | AI detector | Đủ dùng, zero AI cost, sample 5 frames |
| D5 | Pipeline: Linear Step Registry | DAG, Event-driven | Đơn giản, dễ debug, extensible sau |
| D6 | Transcript: Tiered Cascading | ASR Primary, Parallel merge | Tối ưu compute theo từng case |
| D7 | Translation default: Qwen2.5 | Gemma3, DeepSeek | Tốt nhất cho Trung-Việt, Anh-Việt |
| D8 | Output naming: `{name}_vi.mp4` | User-defined only | Intuitive default, vẫn cho override |
| D9 | Config: 3-tier YAML+CLI flags | Single config | Standard pattern, flexible |
| D10 | Logging: `rich` + Python `logging` | loguru, custom | Đẹp, nhẹ, zero config |

---

## 4. Architecture

### 4.1 Project Structure

```
sub-video/
├── main.py                      # CLI entrypoint (argparse / typer)
├── config.yaml                  # Default config
├── docs/                        # Documentation
│   ├── AI Video Translator – Project Requirements Summary.pdf
│   └── AI Video Translator – Design Document.md
│
├── core/
│   ├── pipeline_runner.py       # Linear executor, skip cached steps
│   ├── job_state.py             # State machine, disk persistence (state.json)
│   ├── step_base.py             # Abstract base class cho mọi bước
│   └── plugin_loader.py         # Dynamic plugin loading theo config
│
├── steps/                       # Mỗi file = 1 bước pipeline
│   ├── s01_probe.py             # FFprobe — metadata, subtitle stream detection
│   ├── s02_demux.py             # FFmpeg — tách video/audio/subtitle stream
│   ├── s03_subtitle_detect.py   # Smart detection: embedded/burn-in/audio-only
│   ├── s04_audio_separate.py    # Demucs — voice / music / effect
│   ├── s05_asr.py               # mlx-whisper (Mac) / whisper (CUDA/CPU)
│   ├── s06_ocr.py               # PaddleOCR — chỉ chạy nếu mode=burnin
│   ├── s07_transcript_merge.py  # Merge theo mode được detect
│   ├── s08_translation.py       # Plugin — Qwen2.5/Ollama default
│   ├── s09_subtitle_gen.py      # Sinh SRT/ASS
│   ├── s10_inpaint.py           # Plugin — OpenCV MVP / LaMa production
│   ├── s11_subtitle_render.py   # FFmpeg/libass
│   ├── s12_tts.py               # Plugin — Fish Speech / CosyVoice
│   ├── s13_audio_mix.py         # Giữ music+effect, thay voice
│   └── s14_encode.py            # FFmpeg — ghép final MP4
│
├── plugins/
│   ├── asr/
│   │   ├── mlx_whisper.py       # Apple Silicon (PRIMARY)
│   │   ├── whisper.py           # CUDA / CPU fallback
│   │   └── sensevoice.py
│   ├── ocr/
│   │   ├── paddleocr.py         # Default
│   │   └── easyocr.py
│   ├── translation/
│   │   ├── ollama.py            # Default (Qwen2.5)
│   │   └── openai.py            # Optional cloud fallback
│   ├── tts/
│   │   ├── fish_speech.py       # Default MVP
│   │   └── cosyvoice.py
│   └── inpaint/
│       ├── opencv.py            # Default MVP
│       └── lama.py              # Production
│
└── workspace/                   # Job cache — auto-cleanup sau export
    └── {job_id}/
        ├── state.json
        ├── s01_probe.json
        ├── s02_demux/
        │   ├── video.mp4
        │   ├── audio.aac
        │   └── subtitle.srt (nếu có)
        ├── s04_audio/
        │   ├── voice.wav
        │   ├── music.wav
        │   └── effect.wav
        ├── s05_asr.json          # Transcript timeline
        ├── s08_translation.json  # Translated segments
        └── s14_output/
            └── output_vi.mp4
```

---

## 4.2 Core Abstractions

### StepBase

```python
# core/step_base.py
from abc import ABC, abstractmethod
from pathlib import Path

class StepBase(ABC):
    step_id: str           # e.g. "s05_asr"
    depends_on: list[str]  # e.g. ["s04_audio_separate"]

    @abstractmethod
    def run(self, workspace: Path, config: dict) -> dict:
        """Thực thi bước, trả về output dict"""
        ...

    def can_skip(self, workspace: Path) -> bool:
        """True nếu output đã tồn tại trên disk → skip khi resume"""
        return (workspace / f"{self.step_id}.done").exists()
```

### JobState — state.json schema

```json
{
  "job_id": "abc123",
  "input_video": "/path/to/movie.mp4",
  "config": {
    "target_lang": "vi",
    "translator": "ollama",
    "translator_model": "qwen2.5",
    "asr": "mlx-whisper",
    "asr_model": "large-v3"
  },
  "steps": {
    "s01_probe":          { "status": "done",    "output": { "fps": 24, "duration": 5400 } },
    "s03_subtitle_detect":{ "status": "done",    "output": { "mode": "burnin", "region": [0, 0.8, 1, 1] } },
    "s05_asr":            { "status": "done",    "output": { "transcript_path": "s05_asr.json" } },
    "s08_translation":    { "status": "failed",  "error": "Connection refused" },
    "s14_encode":         { "status": "pending"  }
  }
}
```

### PipelineRunner

```python
# core/pipeline_runner.py
class PipelineRunner:
    def __init__(self, steps: list[StepBase]):
        self.registry = steps  # Ordered list

    def run(self, job: JobState):
        for step in self.registry:
            if step.can_skip(job.workspace):
                log.info(f"[✓] {step.step_id} (cached)")
                continue

            job.set_status(step.step_id, "running")
            try:
                output = step.run(job.workspace, job.config)
                job.set_status(step.step_id, "done", output)
                log.info(f"[✓] {step.step_id}")
            except Exception as e:
                job.set_status(step.step_id, "failed", error=str(e))
                log.error(f"[✗] {step.step_id}: {e}")
                raise  # Dừng, giữ cache để resume

        job.cleanup()  # Xóa workspace sau export thành công
```

---

## 4.3 Transcript Merge — Tiered Cascading

```
VIDEO INPUT
    │
    ▼
[s01_probe — FFprobe, không cần AI]
Has embedded subtitle track?
    │
    ├── YES → s02_demux extract subtitle track
    │         → s07_transcript_merge mode="embedded"
    │         → KHÔNG chạy OCR, KHÔNG chạy ASR
    │         → Chất lượng tốt nhất, nhanh nhất ✅
    │
    └── NO → [s03 — Sample 5 frames tại 10/30/50/70/90%]
              [OpenCV threshold → detect bottom 20% region]
              Has burn-in subtitle region?
                  │
                  ├── YES → mode="burnin"
                  │         → Chạy OCR (s06) làm PRIMARY
                  │         → Chạy ASR (s05) làm SECONDARY
                  │         → s07 merge: ưu tiên OCR nếu confidence > 0.8
                  │                      fallback ASR nếu OCR thất bại
                  │
                  └── NO → mode="audio_only"
                            → Chỉ chạy ASR (s05)
                            → Không chạy OCR → tiết kiệm compute ✅
```

---

## 4.4 Translation — Batch JSON

```
Thay vì: N segments → N Ollama calls (chậm)

Dùng:    N segments → 1 Ollama call với batch JSON

Prompt template:
  "Translate the following Vietnamese subtitle segments.
   Return ONLY a JSON array with the same structure.
   Target language: Vietnamese.
   Input: [{"id":1,"text":"你好"},{"id":2,"text":"谢谢"}]"

Output: [{"id":1,"text":"Xin chào"},{"id":2,"text":"Cảm ơn"}]

Batch size: 50 segments per call (tránh context overflow)
```

---

## 4.5 Plugin Interface

```python
# Tất cả plugin đều implement interface tương ứng
# Chỉ cần đổi config.yaml — không sửa pipeline

class TranslatorBase(ABC):
    @abstractmethod
    def translate(self, segments: list[Segment], target_lang: str) -> list[Segment]: ...

class ASRBase(ABC):
    @abstractmethod
    def transcribe(self, audio_path: Path) -> list[Segment]: ...

class OCRBase(ABC):
    @abstractmethod
    def extract(self, video_path: Path, region: tuple) -> list[Segment]: ...

class TTSBase(ABC):
    @abstractmethod
    def synthesize(self, segments: list[Segment]) -> Path: ...

class InpaintBase(ABC):
    @abstractmethod
    def remove_subtitle(self, video_path: Path, mask_path: Path) -> Path: ...
```

---

## 4.6 Config System

```yaml
# config.yaml (defaults)

# Hardware
device: auto              # auto-detect: mps / cuda / cpu

# ASR
asr: mlx-whisper          # mlx-whisper | whisper | sensevoice
asr_model: large-v3

# Translation
translator: ollama
translator_model: qwen2.5
translator_batch_size: 50  # segments per call
ollama_host: http://localhost:11434

# TTS
tts: fish_speech
tts_voice: vi_preset_01   # MVP: giọng preset

# OCR
ocr: paddleocr

# Inpaint
inpaint: opencv            # opencv | lama

# Output
target_lang: vi
output_suffix: _vi         # movie.mp4 → movie_vi.mp4
```

**Priority**: `config.yaml` < `~/.sub-video/config.yaml` < CLI flags

---

## 4.7 CLI Interface

```bash
# Dịch video cơ bản
python main.py translate movie.mp4

# Override model
python main.py translate movie.mp4 --translator ollama --model qwen2.5

# Chỉ định output
python main.py translate movie.mp4 --output /path/to/output.mp4

# Resume job bị interrupted
python main.py resume {job_id}

# List jobs
python main.py jobs

# Xem trạng thái job
python main.py status {job_id}
```

---

## 4.8 Apple Silicon Optimizations

| Component | Tool | Optimization |
|---|---|---|
| ASR | `mlx-whisper` | Metal backend, 2-3x faster |
| Demucs | `demucs` | MPS backend (`--device mps`) |
| PaddleOCR | `paddleocr` | MPS support |
| Translation | Ollama | Native Apple Silicon binary |
| TTS | Fish Speech | MPS support |
| Inpaint | OpenCV | CPU (nhẹ, đủ dùng MVP) |

---

## 5. MVP Scope — Những gì có và không có

### ✅ Có trong MVP
- Upload video (mp4/mov/mkv)
- Smart subtitle detection (3 modes)
- Audio separation (Demucs)
- Speech recognition (mlx-whisper)
- OCR khi cần (PaddleOCR)
- Transcript merge
- Translation (Qwen2.5 / Ollama)
- Subtitle generation (SRT/ASS)
- Subtitle removal (OpenCV Inpaint)
- Subtitle rendering (FFmpeg)
- TTS preset voice (Fish Speech)
- Audio mixing (giữ music + effect)
- Step-level caching + resume
- CLI interface
- Plugin architecture

### ❌ Không có trong MVP
- Lip Sync
- Voice cloning
- Multi-speaker diarization
- Web UI / Desktop UI
- Redis queue
- Cloud API integration
- LaMa inpainting (production)
- Distributed processing

---

## 6. Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| OpenCV Inpaint chất lượng thấp với background phức tạp | Medium | Chấp nhận ở MVP, LaMa cho production |
| Demucs không tách được voice sạch (nhạc + voice overlap) | Medium | Expose `voice_separation_quality` metric, user có thể skip step |
| Ollama timeout với video dài (nhiều segments) | Low | Batch size limit 50, retry logic |
| OCR sai với font phức tạp/nhỏ | Low | Fallback sang ASR nếu OCR confidence thấp |
| mlx-whisper không có trên CUDA/CPU | Low | Auto-detect device, fallback sang vanilla whisper |

---

## 7. Verification Plan

### Testing chiến lược
- **Unit test** từng Step riêng lẻ với input/output fixture
- **Integration test** pipeline end-to-end với video mẫu ngắn (30s)
- **Smoke test** với 3 loại video: embedded track, burn-in, audio-only

### Sample test videos cần có
```
tests/fixtures/
├── sample_embedded_sub.mkv   # Video có embedded SRT track
├── sample_burnin.mp4          # Video có burn-in subtitle
└── sample_no_sub.mp4          # Video không có subtitle
```

---

*Document generated from brainstorming session — 2026-07-26*
