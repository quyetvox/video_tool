# 🎬 Sub-Video — AI Video Translator System

**Sub-Video** là hệ thống dịch thuật và thuyết minh video tự động (AI Video Translator) được xây dựng theo kiến trúc Pipeline 15 bước mô-đun hóa. Hệ thống hỗ trợ tách giọng gốc, làm sạch tiếng ù, xóa/làm mờ sub cũ, dịch thuật LLM, nhận diện giới tính giọng nói, đọc TTS tiếng Việt chuẩn nhịp, ghép sub mới và xuất video chuẩn H.264/AAC.

---

## 🏗️ Kiến trúc Dự án (Architecture)

- **Root CLI Tools**:
  - `main.py`: CLI điều khiển chính (`translate`, `batch`, `resume`, `status`, `jobs`).
  - `batch_translate.py`: Dịch thuật hàng loạt video trong một project.
  - `narrate.py`: Thuyết minh tự động cho video visual/không thoại bằng Vision AI + LLM.
  - `download.py`: Tải video hàng loạt từ Douyin trực tiếp vào `assets/<project>/src/`.

- **Core Codebase (`lib/`)**:
  - `lib/core/`: Quản lý runner, state, plugin loader và project manager.
  - `lib/steps/`: 15 bước xử lý pipeline. Xem chi tiết tại [`lib/steps/README.md`](lib/steps/README.md).
  - `lib/plugins/`: Plugins linh hoạt cho ASR, OCR, Translation, TTS, Inpaint.
  - `lib/utils/`: Utilities phụ trợ (FFmpeg, Gender Detector, Repetition Cleaner).

- **Cấu trúc Tài nguyên (`assets/<project_name>/`)**:
  - `assets/<project>/src/`: Video gốc & file link `douyin-video-links.txt`.
  - `assets/<project>/workspace/`: Cache không gian làm việc (`job_<video_stem>`).
  - `assets/<project>/output/`: Video hoàn thành đã dịch.
  - `assets/<project>/config.yaml`: File cấu hình riêng cho project.

---

## 🔄 Danh Sách 15 Bước trong Pipeline

1. **`s01_probe` — Probe Video**: Phân tích kích thước, fps, duration bằng FFmpeg/ffprobe.
2. **`s02_demux` — Demux Video & Audio**: Tách riêng video không tiếng (`video_stream.mp4`) và âm thanh gốc (`audio_stream.wav`).
3. **`s03_subtitle_detect` — Subtitle Detect**: Phát hiện vị trí sub nhúng hoặc vùng sub cứng `[ymin, xmin, ymax, xmax]`.
4. **`s04_audio_separate` — Audio Separate**: Tách giọng nói (`vocals.wav`) & nhạc nền (`no_vocals.wav`) bằng Demucs AI + Lọc tiếng ù.
5. **`s05_asr` — Speech to Text**: Nhận diện giọng nói thành văn bản bằng Whisper MLX + Lọc ảo giác lặp từ.
6. **`s05b_gender_detect` — Gender Detect**: Phân tích tần số F0 Pitch gán nhãn Nam/Nữ (`male`/`female`) khi `enable_gender_tts: true`.
7. **`s06_ocr` — OCR Subtitle**: Nhận diện chữ sub cứng bằng PaddleOCR (Mặc định `region` mode skip 0s).
8. **`s07_transcript_merge` — Transcript Merge**: Gộp ASR + OCR thành bản ghi mốc thời gian thống nhất + Lọc rác lặp.
9. **`s08_translation` — Translation**: Dịch thoại sang tiếng Việt bằng LLM/Ollama + Thu gọn lặp từ tiếng Việt.
10. **`s09_subtitle_gen` — Subtitle Gen**: Sinh file phụ đề `.srt` mới, tính font size tự động.
11. **`s10_inpaint` — Subtitle Inpaint**: Làm mờ/xóa sub cũ bằng FFmpeg BoxBlur siêu nhanh (~1s) hoặc OpenCV Telea.
12. **`s11_subtitle_render` — Subtitle Render**: Ghép sub tiếng Việt `.srt` mới vào video sạch.
13. **`s12_tts` — Text to Speech**: Sinh giọng đọc tiếng Việt (EdgeTTS/gTTS Ban Mai), chuyển giọng Nam/Nữ tự động.
14. **`s13_audio_mix` — Audio Mix**: Trộn nhạc nền + giọng đọc TTS + giọng gốc nhỏ bên dưới.
15. **`s14_encode` — Final Encode**: Encode video H.264/AAC tương thích macOS QuickTime/iOS, xuất file sang `output/`.

👉 *Xem hướng dẫn và ví dụ chi tiết cho từng bước tại: [`lib/steps/README.md`](lib/steps/README.md)*

---

## 🚀 Hướng dẫn Sử dụng (Quick Start)

```bash
# 1. Dịch 1 video đơn lẻ trong dự án 'foods':
.venv/bin/python main.py translate assets/foods/src/video_001.mp4

# 2. Dịch hàng loạt tất cả video trong dự án 'foods':
.venv/bin/python batch_translate.py assets/foods/src/

# 3. Resume lại một job (hỗ trợ project:job_id hoặc đường dẫn):
.venv/bin/python main.py resume foods:job_video_001
.venv/bin/python main.py resume assets/foods/workspace/job_video_001

# 4. Kiểm tra danh sách công việc trên tất cả dự án:
.venv/bin/python main.py jobs

# 5. Tải video hàng loạt từ Douyin vào dự án:
.venv/bin/python download.py assets/foods/src/douyin-video-links.txt --limit 5
```
