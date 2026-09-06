# 🎬 Sub-Video — AI Video Translator & Studio System

**Sub-Video** là hệ thống dịch thuật, thuyết minh và biên tập video tự động (AI Video Translator & Studio) được xây dựng theo kiến trúc phân tách 2 module cốt lõi:
- 📱 **`flutter_app/`**: Giao diện người dùng Desktop (macOS Apple Silicon & Windows x64) với Timeline đa kênh, Canvas Studio trực quan, Douyin Downloader, và Quản lý bản quyền Office/Google-style.
- 🐍 **`py_engine/`**: Lõi xử lý AI đa luồng 15 bước mô-đun hóa (Tách giọng Demucs, Whisper MLX / CPU VAD Snapping, Apple Vision OCR & Inpaint, Dịch song ngữ Ollama/Qwen, EdgeTTS Ban Mai / Hoài My, ASS Render, VideoToolbox H.264/AAC).
- 🌐 **Web Portal & Cloud**: [https://subvideo.site](https://subvideo.site) (Cổng quản lý bản quyền, Slot thiết bị và Đồng bộ Cloud Storage).

---

## 🏗️ Kiến trúc Dự án (Architecture)

```
Sub-Video/
├── flutter_app/            # Frontend GUI Flutter Desktop (macOS & Windows)
│   ├── lib/core/           # AppConstants, LicenseService, Storage, Providers
│   ├── lib/screens/        # Video Studio, Douyin Downloader, Dashboard, Setup
│   └── lib/widgets/        # Timeline, Canvas Studio, Paywall, License Dialog
├── py_engine/              # Lõi AI Python Engine (Local-first)
│   ├── main.py             # CLI điều khiển chính (translate, batch, resume, jobs)
│   ├── download.py         # Lõi tải Douyin CDN & trích xuất metadata
│   ├── steps/              # 15 bước xử lý pipeline (s01 -> s14)
│   ├── plugins/            # ASR, OCR, Translation, TTS, Inpaint plugins
│   └── utils/              # FFmpeg, Gender Detector, Repetition Cleaner, VAD
├── resources/              # Thư mục tài nguyên dự án cục bộ
│   └── <project_name>/
│       ├── src/            # Video gốc & douyin-video-links.txt
│       ├── workspace/      # Cache xử lý từng bước (job_<video_stem>)
│       ├── output/         # Video hoàn thành đã dịch và render phụ đề
│       └── config.yaml     # Cấu hình tham số riêng của project
└── installer/              # Bộ công cụ đóng gói cài đặt
    ├── macos/build_dmg.sh  # Đóng gói DMG nhúng trọn vẹn Lõi AI (Rule 4)
    └── windows/            # Đóng gói Windows x64 Inno Setup Installer
```

---

## 🔄 Danh Sách 15 Bước trong Pipeline (`py_engine/steps/`)

1. **`s01_probe` — Probe Video**: Phân tích kích thước, fps, duration bằng FFmpeg/ffprobe.
2. **`s02_demux` — Demux Video & Audio**: Tách riêng video không tiếng (`video_stream.mp4`) và âm thanh gốc (`audio_stream.wav`).
3. **`s03_subtitle_detect` — Subtitle Detect**: Phát hiện vị trí sub nhúng hoặc vùng sub cứng `[ymin, xmin, ymax, xmax]`.
4. **`s04_audio_separate` — Audio Separate**: Tách giọng nói (`vocals.wav`) & nhạc nền (`no_vocals.wav`) bằng Demucs AI.
5. **`s05_asr` — Speech to Text**: Nhận diện giọng nói thành văn bản bằng Whisper MLX + VAD Peak Energy Snapping.
6. **`s05b_gender_detect` — Gender Detect**: Phân tích tần số F0 Pitch gán nhãn Nam/Nữ (`male`/`female`).
7. **`s06_ocr` — OCR Subtitle**: Nhận diện chữ sub cứng bằng Apple Vision Native OCR (macOS) hoặc PaddleOCR.
8. **`s07_transcript_merge` — Transcript Merge**: Gộp ASR + OCR thành bản ghi mốc thời gian thống nhất + Lọc rác lặp.
9. **`s08_translation` — Translation**: Dịch thoại sang tiếng Việt bằng LLM (Ollama/Qwen) Batch 20 câu.
10. **`s08c_timing` — Subtitle Timing**: Tối ưu thời lượng đọc & Gap-Fill $\le 0.8s$ ($End > Start$).
11. **`s09_subtitle_gen` — Subtitle Gen**: Sinh file phụ đề `.srt`/`.ass` mới kèm SubBox nền và viền chữ.
12. **`s10_inpaint` — Subtitle Inpaint**: Làm mờ/xóa sub cũ bằng BoxBlur hoặc Apple Vision Inpainting.
13. **`s11_subtitle_render` — Subtitle Render**: Ghép sub tiếng Việt `.ass` mới vào video sạch.
14. **`s12_tts` — Text to Speech**: Sinh giọng đọc tiếng Việt Studio (Ban Mai, Hoài My, Nam Minh).
15. **`s13_audio_mix` — Audio Mix**: Trộn nhạc nền + giọng đọc TTS + giọng gốc nhỏ bên dưới.
16. **`s14_encode` — Final Encode**: Encode VideoToolbox H.264/AAC, xuất file sang `resources/<project>/output/`.

---

## 🚀 Hướng Dẫn Sử Dụng (Quick Start)

### 1. Khởi chạy Ứng Dụng Desktop (GUI)
```bash
cd flutter_app
flutter run -d macos      # Chạy trên macOS Apple Silicon
# hoặc: flutter run -d windows  # Chạy trên Windows x64 PC
```

### 2. Sử Dụng CLI Engine Trực Tiếp
```bash
# Dịch 1 video đơn lẻ:
.venv/bin/python py_engine/main.py translate resources/foods/src/video_001.mp4

# Dịch hàng loạt tất cả video trong dự án:
.venv/bin/python py_engine/batch_translate.py resources/foods/src/

# Resume lại một job bị gián đoạn:
.venv/bin/python py_engine/main.py resume foods:job_video_001

# Tải video hàng loạt từ Douyin:
.venv/bin/python py_engine/download.py resources/foods/src/douyin-video-links.txt -o resources/foods/src/
```

### 3. Đóng Gói Bộ Cài Đặt Release
```bash
# Đóng gói macOS DMG (tự động nhúng Lõi AI Core theo Rule 4):
bash installer/macos/build_dmg.sh
```

---

## 🔑 Bản Quyền & Kích Hoạt (License System)
- **Cổng Quản Lý**: [https://subvideo.site](https://subvideo.site)
- **Tự động cấp Dùng thử 7 ngày**: Khi đăng ký tài khoản mới (Email hoặc Google).
- **Phân cấp gói**:
  - **Gói Creator**: 1 máy tính, xuất video không giới hạn, hỗ trợ GCS Cloud Storage.
  - **Gói Pro Studio**: 2 máy tính, mở toàn bộ tính năng cao cấp (Resume thông minh, Phân đoạn video siêu dài, Tải tuần tự hàng loạt).
- **Cơ chế thu hồi linh hoạt (Device Slots Pool)**: Tự do giải phóng slot máy tính cũ để chuyển sang máy mới bất kỳ lúc nào trên Web Portal.

