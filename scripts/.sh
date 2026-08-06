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

# Cắt từ giây 5 đến giây 25 (Ultra-fast stream copy <1s, tự lưu video_001_trimmed.mp4):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 --start 5 --end 25

# Cắt từ giây 10 đến hết video (không cắt đoạn sau, chỉ định file đầu ra):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 -s 10 -o assets/foods/src/video_cut.mp4

# Cắt từ đầu video đến giây 30 (không cắt đoạn đầu, chỉ định ghi đè):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 -e 30 --overwrite

# Cắt re-encode chính xác từng frame (nếu cần chuẩn từng miligiây):
.venv/bin/python trim.py assets/foods/src/video_001.mp4 -s 5 -e 20 --accurate --overwrite

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
