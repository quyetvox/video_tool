# ─────────────────────────────────────────────────────────────────────────────
# 🚀 SUB-VIDEO CLI CHEATSHEET & AUTOMATION SCRIPT
# ─────────────────────────────────────────────────────────────────────────────

# 1. DỊCH VIDEO ĐƠN LẺ (Translate Pipeline)
# Mặc định theo config.yaml của project (hoặc root config nếu chưa có riêng):
.venv/bin/python main.py translate assets/xujing/src/video_001.mp4

# Dịch ép kiểu Voice (ASR + Demucs + TTS):
.venv/bin/python main.py translate assets/xujing/src/video_001.mp4 --voice

# Dịch ép kiểu Sub Hardsub (OCR Only ~0s audio, giữ 100% âm thanh gốc):
.venv/bin/python main.py translate assets/xujing/src/video_001.mp4 --ocr-only

# Dịch giới hạn thời lượng test (Ví dụ: test 15s đầu):
.venv/bin/python main.py translate assets/xujing/src/video_001.mp4 --duration 15

# ─────────────────────────────────────────────────────────────────────────────
# 2. DỊCH HÀNG LOẠT (Batch Translation)
# Quét toàn bộ video trong folder src/ và dịch tuần tự:
.venv/bin/python batch_translate.py assets/xujing/src/
.venv/bin/python main.py batch assets/xujing/src/ --voice
.venv/bin/python main.py batch assets/xujing/src/ --ocr-only

# ─────────────────────────────────────────────────────────────────────────────
# 3. RESUME & TỰ ĐỘNG CẬP NHẬT KHI SỬA PHỤ ĐỀ TAY (Smart Invalidation)
# Sau khi sửa s08_translation.json trên GUI hoặc file text, gõ resume để áp dụng ngay (~2s):
# Cách A: Gõ trực tiếp project:job_id (Khuyến nghị)
.venv/bin/python main.py resume xujing:job_video_001
.venv/bin/python main.py resume foods:job_video_001

# Cách B: Truyền đường dẫn đầy đủ đến workspace hoặc file video
.venv/bin/python main.py resume assets/xujing/workspace/job_video_001
.venv/bin/python main.py resume assets/xujing/src/video_001.mp4

# Cách C: Gõ ID ngắn (Tự động nhận diện nếu không trùng tên)
.venv/bin/python main.py resume job_video_001

# ─────────────────────────────────────────────────────────────────────────────
# 4. QUẢN LÝ JOBS & XÓA CACHE STEP (Cascade Invalidation)
# Kiểm tra danh sách và tiến độ các job:
.venv/bin/python main.py jobs
.venv/bin/python main.py status xujing:job_video_001

# Xóa cache step bất kỳ (tự động xóa cascade các bước downstream):
.venv/bin/python main.py delete-step xujing:job_video_001 s10_inpaint
.venv/bin/python main.py delete-step xujing:job_video_001 s08_translation

# Xóa sạch toàn bộ workspace của một job:
.venv/bin/python main.py delete-job xujing:job_video_001

# ─────────────────────────────────────────────────────────────────────────────
# 5. KHỞI CHẠY GIAO DIỆN WEB GUI (Sub-Video Studio)
# Khởi chạy frontend Vite (port 5173) + backend Node.js (port 3001):
cd gui && npm run start
# Mở trình duyệt tại: http://localhost:5173

# ─────────────────────────────────────────────────────────────────────────────
# 6. CẮT VIDEO NHANH (Sub-Video Trimmer - trim.py)
# Cắt siêu tốc (<0.2s - Stream Copy mặc định không re-encode):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 --start 5 --end 25

# Cắt với định dạng phút:giây linh hoạt (Ví dụ: từ 01:15 đến 02:45):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 -s 01:15 -e 02:45

# Cắt từ đầu video đến 01:30 (Ghi đè file gốc hoặc xuất file mới):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 -e 01:30 -o assets/foods/src/video_cut.mp4 --overwrite

# Cắt re-encode chính xác từng frame (Apple Silicon VideoToolbox ~1s):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 -s 01:00 -e 02:00 --accurate

# ─────────────────────────────────────────────────────────────────────────────
# 7. GHÉP VIDEO & CẮT LOẠI BỎ ĐOẠN RÁC (Sub-Video Studio - concat.py)
# 1. Cắt loại bỏ các đoạn rác (<0.3s Siêu Tốc Stream Copy):
.venv/bin/python concat.py assets/foods/src/video_001.mp4 --remove 00:15-00:30 01:10-01:20 --overwrite

# Cắt loại bỏ đoạn rác chính xác từng frame (Frame-Accurate VideoToolbox ~1s):
.venv/bin/python concat.py assets/foods/src/video_001.mp4 --remove 00:15-00:30 --overwrite --accurate

# 2. Ghép nhiều video thành 1 file duy nhất (Tự động scale & letterbox pad nếu khác resolution):
.venv/bin/python concat.py assets/foods/src/part1.mp4 assets/foods/src/part2.mp4 assets/foods/src/part3.mp4 -o assets/foods/src/merged_final.mp4

# ─────────────────────────────────────────────────────────────────────────────
# 8. THUYẾT MINH AI TỰ ĐỘNG CHO VIDEO VISUAL (narrate.py)
# Dùng Vision AI + LLM phân tích hình ảnh và thuyết minh video không thoại:
.venv/bin/python narrate.py assets/default/src/video-test.mp4

# ─────────────────────────────────────────────────────────────────────────────
# 9. TẢI VIDEO DOUYIN HÀNG LOẠT (download.py & scripts/download-douyin.js)
# Tải video từ danh sách URL douyin-video-links.txt:
.venv/bin/python download.py assets/foods/src/douyin-video-links.txt --limit 5

# Tải phân trang tiếp theo (bắt đầu từ video #6):
.venv/bin/python download.py assets/foods/src/douyin-video-links.txt --start 6 --limit 5

# Trích xuất link Douyin bằng script Console trình duyệt (scripts/download-douyin.js):
# 1. Mở kênh Douyin trên Chrome/Edge -> Nhấn F12 (Console)
# 2. Dán mã nguồn từ scripts/download-douyin.js
# 3. Tùy chỉnh CONFIG: { START: 1, LIMIT: 20, FROM_END: false, REVERSE_ORDER: false }
# 4. Lưu tệp kết quả vào assets/<project>/src/douyin-video-links.txt

# ─────────────────────────────────────────────────────────────────────────────
# 10. QUẢN LÝ CLOUD STORAGE GCS DIRECT API (storage.py)
# Xem thông tin kết nối & bucket GCS:
.venv/bin/python storage.py info

# Kiểm tra trạng thái đồng bộ giữa Local SSD và Cloud Storage:
.venv/bin/python storage.py status foods

# Kéo video/dữ liệu từ Cloud về máy Mac để chuẩn bị Dịch AI:
.venv/bin/python storage.py sync-down foods
.venv/bin/python storage.py sync-down foods --files video_001.mp4 video_002.mp4

# Đẩy video hoàn thành và nguồn lên Cloud:
.venv/bin/python storage.py sync-up foods

# Giải phóng ổ cứng SSD (chỉ xóa local khi đã an toàn 100% trên Cloud):
.venv/bin/python storage.py offload foods
.venv/bin/python storage.py offload foods --files src/video_001.mp4 output/video_001_vi.mp4

# Làm mới danh mục Cloud:
.venv/bin/python storage.py refresh foods

