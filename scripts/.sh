# ─────────────────────────────────────────────────────────────────────────────
# 🚀 CLI Command Cheatsheet (Asset Projects Architecture)
# ─────────────────────────────────────────────────────────────────────────────

# 1. Dịch 1 video đơn lẻ (Tự động nhận diện project 'xujing' & dùng assets/xujing/config.yaml):
.venv/bin/python main.py translate assets/xujing/src/video_001.mp4

# 2. Dịch hàng loạt toàn bộ video trong một dự án:
.venv/bin/python batch_translate.py assets/xujing/src/

# 3. Resume lại một job theo nhiều cách:
# Cách A: Gõ trực tiếp project:job_id
.venv/bin/python main.py resume xujing:job_video_001

# Cách B: Truyền đường dẫn đầy đủ đến workspace hoặc file video
.venv/bin/python main.py resume assets/xujing/workspace/job_video_001
.venv/bin/python main.py resume assets/xujing/src/video_001.mp4

# Cách C: Gõ ID ngắn (Tự động nhận diện)
.venv/bin/python main.py resume job_video_001

# 4. Kiểm tra danh sách tất cả các job trên các project:
.venv/bin/python main.py jobs
.venv/bin/python main.py status job_video_001

# 5. Tự động viết kịch bản thuyết minh & đọc TTS cho video:
.venv/bin/python narrate.py assets/default/src/video-test.mp4

# 6. Khởi chạy Giao Diện Đồ Họa Local (Sub-Video Desktop GUI Studio):
cd gui && npm run start
# Giao diện ứng dụng sẽ mở tại http://localhost:5173 (Tự động kết nối với backend server http://localhost:3001)

# ─────────────────────────────────────────────────────────────────────────────
# ✂️ Cắt Video Nhanh (Sub-Video Trimmer CLI - trim.py)
# ─────────────────────────────────────────────────────────────────────────────

# Cắt từ giây 5 đến giây 25 (Tự động sinh tên không trùng video_001_cut_1.mp4):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 --start 5 --end 25

# Cắt với định dạng phút:giây linh hoạt (Ví dụ: từ 01:15 đến 02:45):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 -s 01:15 -e 02:45

# Cắt từ đầu video đến 01:30 (Chỉ định file đầu ra hoặc ghi đè):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 -e 01:30 -o assets/foods/src/video_cut.mp4 --overwrite

# Cắt re-encode chính xác từng frame (nếu cần chuẩn từng miligiây):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 -s 01:00 -e 02:00 --accurate

# ─────────────────────────────────────────────────────────────────────────────
# 🎬 Ghép Video & Cắt Loại Bỏ Đoạn Rác (Sub-Video Studio CLI - concat.py)
# ─────────────────────────────────────────────────────────────────────────────

# 1. Ghép 3 video thành 1 file duy nhất (Tự động Scale & Letterbox Pad về cùng độ phân giải):
.venv/bin/python concat.py assets/foods/src/part1.mp4 assets/foods/src/part2.mp4 assets/foods/src/part3.mp4

# 2. Cắt loại bỏ 2 đoạn rác (00:15➔00:30 và 01:10➔01:20) trên 1 video:
.venv/bin/python concat.py assets/foods/src/video_001.mp4 --remove 00:15-00:30 01:10-01:20

# 3. Ghép video với tên file kết quả chỉ định:
.venv/bin/python concat.py assets/foods/src/part1.mp4 assets/foods/src/part2.mp4 -o assets/foods/src/merged_final.mp4

# ─────────────────────────────────────────────────────────────────────────────
# 🔍 Cấu hình Auto-Detect Vùng Sub Gốc (Frame Diff Accumulation)
# ─────────────────────────────────────────────────────────────────────────────
# Để tự động detect vị trí sub cũ (không cần gán cứng inpaint_region):
# 1. Trong assets/<project>/config.yaml, comment dòng inpaint_region:
#    # inpaint_region: [0.12, 0.05, 0.22, 0.95]
#
# 2. Hệ thống sẽ tự động quét 40 frame thưa (từ 5% -> 95% thời lượng video)
#    và tính toán heat map thay đổi pixel để xác định chính xác top/bottom.
#    Chiều rộng luôn căn đều 2 bên [left=0.05, right=0.95].
#
# 3. Nếu muốn override thủ công cho 1 project đặc thù, chỉ cần bỏ comment inpaint_region trong config.yaml của project đó.

# ─────────────────────────────────────────────────────────────────────────────
# 📥 Tải video hàng loạt từ Douyin (Tự động tải vào assets/<project>/src/)
# ─────────────────────────────────────────────────────────────────────────────

# Tải tất cả video trong project foods:
.venv/bin/python download.py assets/foods/src/douyin-video-links.txt

# Tải theo mốc giới hạn (Ví dụ: tải 5 video từ mốc #1):
.venv/bin/python download.py assets/foods/src/douyin-video-links.txt --limit 5

# Tải mốc tiếp theo (Bắt đầu từ video #6, tải 5 video):
.venv/bin/python download.py assets/foods/src/douyin-video-links.txt --start 6 --limit 5

# Sub video không thuyết minh Tùy chỉnh font:
.venv/bin/python process_video_segment.py assets/cooking/src/video_001.mp4 -t 10 --font-size 18

# ─────────────────────────────────────────────────────────────────────────────
# ☁️ Quản Lý Cloud Storage GCS (Sub-Video Storage CLI - storage.py)
# ─────────────────────────────────────────────────────────────────────────────

# 1. Xem thông tin cấu hình Cloud Storage & trạng thái kết nối Direct API:
.venv/bin/python storage.py info

# 2. Kiểm tra trạng thái đồng bộ giữa máy Mac và Cloud Storage (Quét siêu tốc 0-Byte):
.venv/bin/python storage.py status foods
.venv/bin/python storage.py status edamame

# 3. Kéo video/tệp từ Cloud về máy Mac để chuẩn bị Dịch AI:
# Kéo toàn bộ file của dự án:
.venv/bin/python storage.py sync-down foods

# Kéo đích danh 1 hoặc nhiều video cụ thể:
.venv/bin/python storage.py sync-down foods --files video_001.mp4 video_002.mp4

# 4. Đẩy video kết quả / dữ liệu từ máy Mac lên Cloud Storage:
# Đẩy toàn bộ src/ và output/ (bỏ qua cache workspace):
.venv/bin/python storage.py sync-up foods

# Đẩy đích danh 1 video kết quả:
.venv/bin/python storage.py sync-up foods --files output/video_001_vi.mp4

# 5. Giải phóng dung lượng ổ cứng SSD (Offload):
# (Chỉ xóa file ở máy Mac khi đã xác nhận an toàn 100% trên Cloud)
.venv/bin/python storage.py offload foods

# Giải phóng đích danh file cụ thể:
.venv/bin/python storage.py offload foods --files src/video_001.mp4 output/video_001_vi.mp4

# 6. Xóa vĩnh viễn tệp trên Cloud Storage:
.venv/bin/python storage.py delete-cloud foods --files src/video_001.mp4

# 7. Làm mới dữ liệu bảng kê Cloud (Direct API Refresh):
.venv/bin/python storage.py refresh foods
.venv/bin/python storage.py refresh all

