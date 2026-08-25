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
# 12. ĐÓNG GÓI BẢN VÁ ENGINE (Hot-Patch Packager)
# Đóng gói toàn bộ py_engine/ và dylibs thành bản vá dist/engine_patch.zip:
./scripts/package_engine_patch.sh
