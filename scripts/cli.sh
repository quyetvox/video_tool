# ─────────────────────────────────────────────────────────────────────────────
# 🚀 SUB-VIDEO CLI CHEATSHEET & AUTOMATION SCRIPT
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# 1. DỊCH VIDEO ĐƠN LẺ & TỰ ĐỘNG PHÂN ĐOẠN (Translate Pipeline)
# Mặc định theo config.yaml của project (Tự động chuyển translate-long nếu >10 phút hoặc >1GB):
.venv/bin/python py_engine/main.py translate resources/xujing/src/video_001.mp4

# Dịch ép kiểu Voice (ASR + Demucs + TTS):
.venv/bin/python py_engine/main.py translate resources/xujing/src/video_001.mp4 --voice

# Dịch ép kiểu Sub Hardsub (OCR Only ~0s audio, giữ 100% âm thanh gốc):
.venv/bin/python py_engine/main.py translate resources/xujing/src/video_001.mp4 --ocr-only

# Dịch giới hạn thời lượng test (Ví dụ: test 15s đầu):
.venv/bin/python py_engine/main.py translate resources/xujing/src/video_001.mp4 --duration 15

# ─────────────────────────────────────────────────────────────────────────────
# 2. DỊCH VIDEO DÀI & NẶNG CHUYÊN SÂU (Smart Chunking & Resumable Engine)
# Dịch video dài/nặng với cơ chế Triple-Lock Split (Silence + I-Frame không re-encode):
.venv/bin/python py_engine/main.py translate-long resources/xujing/src/long_video.mp4

# Tùy chỉnh độ dài mỗi đoạn (ví dụ 8 phút/đoạn) và số worker an toàn:
.venv/bin/python py_engine/main.py translate-long resources/xujing/src/long_video.mp4 --chunk-mins 8 --workers 2

# Dịch video dài chế độ Hardsub (OCR Only):
.venv/bin/python py_engine/main.py translate-long resources/xujing/src/long_video.mp4 --ocr-only

# Ép buộc phân đoạn cho video bất kể thời lượng:
.venv/bin/python py_engine/main.py translate-long resources/xujing/src/video_001.mp4 --force-chunk

# ─────────────────────────────────────────────────────────────────────────────
# 3. DỊCH HÀNG LOẠT (Batch Translation)
# Quét toàn bộ video trong folder src/ và dịch tuần tự:
.venv/bin/python py_engine/batch_translate.py resources/xujing/src/
.venv/bin/python py_engine/main.py batch resources/xujing/src/ --voice
.venv/bin/python py_engine/main.py batch resources/xujing/src/ --ocr-only

# ─────────────────────────────────────────────────────────────────────────────
# 4. RESUME & TỰ ĐỘNG CẬP NHẬT KHI SỬA PHỤ ĐỀ TAY (Smart Invalidation)
# Sau khi sửa s08_translation.json trên GUI hoặc file text, gõ resume để áp dụng ngay (~2s):
# Cách A: Gõ trực tiếp project:job_id (Khuyến nghị)
.venv/bin/python py_engine/main.py resume xujing:job_video_001
.venv/bin/python py_engine/main.py resume foods:job_video_001

# Cách B: Truyền đường dẫn đầy đủ đến workspace hoặc file video
.venv/bin/python py_engine/main.py resume resources/xujing/workspace/job_video_001
.venv/bin/python py_engine/main.py resume resources/xujing/src/video_001.mp4

# Cách C: Gõ ID ngắn (Tự động nhận diện nếu không trùng tên)
.venv/bin/python py_engine/main.py resume job_video_001

# ─────────────────────────────────────────────────────────────────────────────
# 5. QUẢN LÝ TIẾN TRÌNH & DỌN DẸP TIẾN TRÌNH MỒ CÔI (Process Guardian)
# Quét và dọn sạch các tiến trình Python/Demucs/FFmpeg chạy ngầm mồ côi để giải phóng RAM:
.venv/bin/python py_engine/main.py cleanup-orphans

# Kiểm tra trạng thái job cụ thể:
.venv/bin/python py_engine/main.py status xujing:job_video_001

# Xóa cache step bất kỳ (tự động xóa cascade các bước downstream):
.venv/bin/python py_engine/main.py delete-step xujing:job_video_001 s10_inpaint
.venv/bin/python py_engine/main.py delete-step xujing:job_video_001 s08_translation

# Xóa sạch toàn bộ workspace của một job:
.venv/bin/python py_engine/main.py delete-job xujing:job_video_001

# ─────────────────────────────────────────────────────────────────────────────
# 6. KHỞI CHẠY GIAO DIỆN FLUTTER DESKTOP APP
# Khởi chạy Flutter Desktop Native trên macOS:
cd flutter_app && flutter run -d macos

# ─────────────────────────────────────────────────────────────────────────────
# 7. CẮT VIDEO NHANH (Sub-Video Trimmer - trim.py)
# Cắt siêu tốc (<0.2s - Stream Copy mặc định không re-encode):
.venv/bin/python py_engine/trim.py resources/foods/src/video_001.mp4 --start 5 --end 25

# Cắt với định dạng phút:giây linh hoạt (Ví dụ: từ 01:15 đến 02:45):
.venv/bin/python py_engine/trim.py resources/foods/src/video_001.mp4 -s 01:15 -e 02:45

# Cắt từ đầu video đến 01:30 (Ghi đè file gốc hoặc xuất file mới):
.venv/bin/python py_engine/trim.py resources/foods/src/video_001.mp4 -e 01:30 -o resources/foods/src/video_cut.mp4 --overwrite

# Cắt re-encode chính xác từng frame (Apple Silicon VideoToolbox ~1s):
.venv/bin/python py_engine/trim.py resources/foods/src/video_001.mp4 -s 01:00 -e 02:00 --accurate

# ─────────────────────────────────────────────────────────────────────────────
# 8. GHÉP VIDEO & CẮT LOẠI BỎ ĐOẠN RÁC (Sub-Video Studio - concat.py)
# 1. Cắt loại bỏ các đoạn rác (<0.3s Siêu Tốc Stream Copy):
.venv/bin/python py_engine/concat.py resources/foods/src/video_001.mp4 --remove 00:15-00:30 01:10-01:20 --overwrite

# Cắt loại bỏ đoạn rác chính xác từng frame (Frame-Accurate VideoToolbox ~1s):
.venv/bin/python py_engine/concat.py resources/foods/src/video_001.mp4 --remove 00:15-00:30 --overwrite --accurate

# 2. Ghép nhiều video thành 1 file duy nhất (Tự động scale & letterbox pad nếu khác resolution):
.venv/bin/python py_engine/concat.py resources/foods/src/part1.mp4 resources/foods/src/part2.mp4 resources/foods/src/part3.mp4 -o resources/foods/src/merged_final.mp4

# ─────────────────────────────────────────────────────────────────────────────
# 9. THUYẾT MINH AI TỰ ĐỘNG CHO VIDEO VISUAL (narrate.py)
# Dùng Vision AI + LLM phân tích hình ảnh và thuyết minh video không thoại:
.venv/bin/python py_engine/narrate.py resources/default/src/video-test.mp4

# ─────────────────────────────────────────────────────────────────────────────
# 10. TẢI VIDEO DOUYIN HÀNG LOẠT (download.py & scripts/download-douyin.js)
# Tải video từ danh sách URL douyin-video-links.txt:
.venv/bin/python py_engine/download.py resources/foods/src/douyin-video-links.txt --limit 5

# Tải phân trang tiếp theo (bắt đầu từ video #6):
.venv/bin/python py_engine/download.py resources/foods/src/douyin-video-links.txt --start 6 --limit 5

# ─────────────────────────────────────────────────────────────────────────────
# 11. QUẢN LÝ CLOUD STORAGE GCS DIRECT API (storage.py)
# Xem thông tin kết nối & bucket GCS:
.venv/bin/python py_engine/storage.py info

# Kiểm tra trạng thái đồng bộ giữa Local SSD và Cloud Storage:
.venv/bin/python py_engine/storage.py status foods

# Kéo video/dữ liệu từ Cloud về máy Mac để chuẩn bị Dịch AI:
.venv/bin/python py_engine/storage.py sync-down foods
.venv/bin/python py_engine/storage.py sync-down foods --files video_001.mp4 video_002.mp4

# Đẩy video hoàn thành và nguồn lên Cloud:
.venv/bin/python py_engine/storage.py sync-up foods

# Giải phóng ổ cứng SSD (chỉ xóa local khi đã an toàn 100% trên Cloud):
.venv/bin/python py_engine/storage.py offload foods
.venv/bin/python py_engine/storage.py offload foods --files src/video_001.mp4 output/video_001_vi.mp4

# Làm mới danh mục Cloud:
.venv/bin/python py_engine/storage.py refresh foods

# ─────────────────────────────────────────────────────────────────────────────
# 12. ĐÓNG GÓI BẢN VÁ PYTHON CORE ENGINE (.pyc Bytecode & releases/core/)
# Tự động tăng version patch (1.1.47 -> 1.1.48), biên dịch .pyc và xóa mã nguồn thô:
./scripts/package_engine_patch.sh

# Hoặc chỉ định phiên bản và ghi chú cập nhật cụ thể:
./scripts/package_engine_patch.sh 1.1.48 "Bản vá tối ưu hóa ASR timing và Ducking"

# ─────────────────────────────────────────────────────────────────────────────
# 13. BIÊN DỊCH BẢN CÀI ĐẶT ĐA NỀN TẢNG CỤC BỘ (Local Desktop Builders)
# 1. Đóng gói macOS DMG (Apple Silicon arm64 -> releases/macos/):
bash installer/macos/build_dmg.sh

# 2. Đóng gói Windows x64 (Inno Setup .exe + Portable .zip -> releases/win/):
# Chạy trong PowerShell trên Windows:
powershell -ExecutionPolicy Bypass -File .\installer\windows\build_windows_dist.ps1

# ─────────────────────────────────────────────────────────────────────────────
# 14. KÍCH HOẠT CI/CD GITHUB ACTIONS PHÁT HÀNH TỰ ĐỘNG (Smart Matrix Release)
#
# ── MODE 1: CHỈ PHÁT HÀNH BẢN VÁ PYTHON CORE (~30 GIÂY, ~400KB .PYC) ──
# (Dùng khi chỉ sửa code Python py_engine, chỉnh prompt hay thuật toán)
git add .
git commit -m "fix(core): cập nhật thuật toán nhận diện subtitle"
git push origin v-flutter
git tag core-v1.1.48
git push origin core-v1.1.48
# -> GitHub Actions chỉ chạy job package-core (~30s), skip macOS/Windows, đẩy file zip lên Release!

# ── MODE 2: PHÁT HÀNH DESKTOP APP ĐẦY ĐỦ (CẢ WIN .EXE, MAC .DMG, CORE .ZIP) ──
# (Dùng khi cập nhật Flutter GUI, phát hành bản cài đặt mới toàn diện)
git add .
git commit -m "release: v1.0.1 phát hành bản cài đa nền tảng"
git push origin v-flutter
git tag v1.0.1
git push origin v1.0.1
# -> GitHub Actions chạy đầy đủ 3 máy ảo Win/Mac/Ubuntu, gom và đính kèm đủ 4-5 file lên Release!

# ── MODE 3: CHỈ BUILD BẢN CÀI ĐẶT WINDOWS X64 (.EXE SETUP & .ZIP PORTABLE) ──
# (Dùng khi chỉ cần xuất file cài đặt cho máy Windows)
git add .
git commit -m "release: cập nhật bản cài đặt Windows"
git push origin v-flutter
git tag win-v1.0.1
git push origin win-v1.0.1
# -> GitHub Actions chỉ chạy job build-windows (skip macOS), xuất file .exe & .zip lên Release!

# ── MODE 4: CHỈ BUILD BẢN CÀI ĐẶT MACOS (APPLE SILICON ARM64 .DMG) ──
# (Dùng khi chỉ cần xuất file DMG cho máy Mac)
git add .
git commit -m "release: cập nhật bản cài đặt macOS"
git push origin v-flutter
git tag mac-v1.0.1
git push origin mac-v1.0.1
# -> GitHub Actions chỉ chạy job build-macos (skip Windows), xuất file .dmg lên Release!

# ── MODE 5: KÍCH HOẠT THỦ CÔNG TRÊN WEB GITHUB (TÙY CHỌN TARGET) ──
# Vào tab Actions -> Chọn "Build & Publish Multi-Platform Release" -> Run workflow:
# Chọn target: core-only | windows-only | macos-only | all

# ── MẸO QUẢN LÝ TAG GIT ──
# Xem danh sách các tag hiện có:
git tag -l
# Xóa tag nếu lỡ tạo nhầm:
# git tag -d core-v1.1.48               # Xóa local
# git push origin --delete core-v1.1.48 # Xóa trên GitHub remote

