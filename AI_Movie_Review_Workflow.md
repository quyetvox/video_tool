# TÀI LIỆU KỸ THUẬT: HỆ THỐNG AUTO-GENERATE MOVIE REVIEW VIDEO (FULL WORKFLOW & SCRIPT SOP)

**Mô tả:** Hệ thống tự động 100% biến một video phim dài (1-3 tiếng) thành video Review Phim ngắn có kịch bản chuẩn cấu trúc tâm lý học, tối ưu tốc độ, token và đồng bộ Hình - Tiếng 100%.  
**Core Logic:** Tách nhỏ dữ liệu (Audio + Keyframes) để LLM xử lý theo 2 giai đoạn (Two-Stage Hierarchical), dùng AI sinh kịch bản chuẩn tỷ lệ vàng 4 phần, tự động căn chỉnh số chữ theo tốc độ đọc TTS, sau đó lấy thời lượng thực tế của file Voiceover làm mốc mỏ neo để cắt/slow-mo video, chống triệt để hiện tượng lẹm cảnh (Scene Bleed).

---

## 🛠 TECH STACK ĐỀ XUẤT
* **Ngôn ngữ:** Python 3.10+
* **Giao diện:** Flutter Desktop (macOS & Windows)
* **Xử lý Video/Audio:** `ffmpeg-python`, `scenedetect` (PySceneDetect), `mutagen`
* **LLM (AI Core):** SDK `google-genai` (Model: **gemini-2.5-flash** hoặc **gemini-2.5-pro**)
* **Text-to-Speech (TTS):** EdgeTTS tích hợp sẵn (Hoài My, Nam Minh) + Hỗ trợ API ElevenLabs / FPT.AI / Viettel AI.

---

## 📜 QUY CHUẨN XÂY DỰNG KỊCH BẢN & CĂN CHỈNH THỜI LƯỢNG (SOP)

### 1. Phân Loại Phim & Khuyến Nghị Thời Lượng
* **Nhóm Tuyến tính / Hành động (Linear / Action):** Phim võ thuật, đua xe, kinh dị sinh tồn (*John Wick, Fast & Furious*). Cốt truyện đơn giản $\rightarrow$ **Khuyến nghị 5 - 8 phút**. Chiến lược: Bỏ qua tiểu tiết, tập trung khoe cảnh hành động, kỹ xảo mãn nhãn.
* **Nhóm Phức tạp / Tâm lý (Complex / Psychological):** Trinh thám, viễn tưởng, giật gân, đa tuyến (*Inception, Parasite*). Luật lệ riêng, nhiều ẩn dụ $\rightarrow$ **Khuyến nghị 10 - 15 phút**. Chiến lược: Giải thích luật chơi, diễn biến tâm lý, phân tích sâu các cú Twist.
* **Video Ngắn (Shorts / Reels / TikTok):** **Khuyến nghị 1 - 3 phút**. Chiến lược: Đi thẳng vào 1 tình huống éo le hoặc 1 cú twist đỉnh nhất.

### 2. Phân Bổ Thời Lượng Kịch Bản (Tỷ Lệ Vàng 4 Phần)
* **The Hook - Mở bài (5% ~ 20-30s):** Bắt đầu bằng 1 câu giật gân / éo le nhất để giữ chân khán giả trong 5 giây đầu.
* **Storytelling - Kể chuyện (70% ~ 4-5.5 phút):** Tóm tắt siêu tốc bối cảnh $\rightarrow$ Hành trình giải quyết biến cố. Lược bỏ nhân vật phụ thừa.
* **The Review - Đánh giá & Nhặt sạn (20% ~ 1-1.5 phút):** Khen/chê diễn xuất, âm thanh, góc máy; nhặt "sạn" logic hoặc Easter Eggs.
* **The Outro - Kết luận (5% ~ 20-30s):** Chấm điểm (VD: 8/10) và Call to Action bằng câu hỏi mở liên quan đến kết phim.

### 3. Công Thức Quy Đổi Số Chữ Động (Speed-Calibrated Word Count)
* Tốc độ đọc chuẩn TTS Tiếng Việt: `135 - 140 chữ / phút` (ở tốc độ $1.0\times$).
* **Công thức thích ứng:**  
  $$\text{Tổng số chữ} = \text{Thời lượng (phút)} \times (140 \times \text{TTS Speed})$$
* **Ví dụ Video 6 phút (TTS Speed 1.15x):**  
  Tốc độ đọc thực tế: $140 \times 1.15 \approx 161\text{ chữ/phút}$.  
  Tổng số chữ mục tiêu: $6 \times 161 \approx 966\text{ chữ}$.  
  * **Hook (5%):** $\sim 48\text{ chữ}$.  
  * **Storytelling (70%):** $\sim 676\text{ chữ}$.  
  * **Review (20%):** $\sim 193\text{ chữ}$.  
  * **Outro (5%):** $\sim 49\text{ chữ}$.

---

## ⚙️ QUY TRÌNH THỰC THI TOÀN DIỆN (FULL FLOW)

### PHASE 1: PRE-PROCESSING & STAGE 1 BLUEPRINTING (TỐI ƯU 90% TOKEN)
*Không upload toàn bộ video hay hàng nghìn ảnh lên API để tránh nghẽn băng thông và tốn Token.*

1. **Tách Audio Nén Siêu Nhẹ:**  
   Dùng FFmpeg bóc tách audio mono 16kHz siêu nhẹ (24kbps) trong 5 giây:  
   `ffmpeg -y -i input.mp4 -vn -ac 1 -ar 16000 -b:a 24k workspace/audio_low.mp3`
2. **AI Lập Dàn Ý & Chọn Mốc Thời Gian Cao Trào (Stage 1):**  
   Gửi audio nén (hoặc text transcript từ Whisper MLX cục bộ) lên Gemini 2.5 Flash:  
   * **Prompt:** Yêu cầu tóm tắt cốt truyện và chọn ra **15–20 mốc thời gian cao trào quan trọng nhất** (tổng khoảng 15–25 phút footage) phù hợp với thể loại và thời lượng mục tiêu.

---

### PHASE 2: QUÉT CẢNH MỤC TIÊU & SINH KỊCH BẢN MONTAGE
1. **Quét Chuyển Cảnh Mục Tiêu (PySceneDetect 360p):**  
   Chỉ quét trong các mốc thời gian đã chọn ở Phase 1 với proxy 360p (`scale=-2:360`, `ContentDetector(threshold=27.0)`).  
   Trích xuất **1 ảnh Middle Keyframe** mỗi cảnh. Giới hạn nghiêm ngặt ở mức **80–120 keyframes**.
2. **Gọi Gemini Sinh Kịch Bản Đầy Đủ (Stage 2):**  
   Upload batch ảnh lên Google Files API $\rightarrow$ Gửi prompt ép số chữ chi tiết cho 4 phần:
   > "Hãy viết kịch bản review phim bám sát cấu trúc 4 phần với tổng độ dài [X] chữ: Mở bài ([A] chữ) -> Kể chuyện ([B] chữ) -> Đánh giá ([C] chữ) -> Kết luận ([D] chữ). Với mỗi câu voiceover, hãy chỉ định 1 hoặc nhiều scene_id phù hợp nhất. Phần Đánh giá & Outro hãy tái sử dụng các cảnh cận cảnh / đại cảnh đắt giá nhất của kho ảnh để làm B-roll minh họa. Trả về đúng JSON."

**Cấu trúc JSON đầu ra từ Gemini:**
```json
{
  "title": "Tên video review",
  "genre": "action",
  "target_duration_sec": 360,
  "total_word_count": 960,
  "script": [
    {
      "id": 1,
      "section": "hook",
      "voiceover_text": "Bị dồn vào đường cùng, nam chính quyết định nhảy qua cửa sổ để tẩu thoát trong gang tấc.",
      "scenes_to_use": [
        {"scene_id": 45, "start_sec": 125.5, "end_sec": 128.0}, 
        {"scene_id": 46, "start_sec": 128.0, "end_sec": 132.5}
      ]
    },
    {
      "id": 2,
      "section": "storytelling",
      "voiceover_text": "Mọi chuyện bắt đầu khi anh vô tình phát hiện ra bí mật đen tối của tổ chức...",
      "scenes_to_use": [
        {"scene_id": 12, "start_sec": 45.0, "end_sec": 51.0}
      ]
    },
    {
      "id": 25,
      "section": "review",
      "voiceover_text": "Về mặt kỹ xảo, các pha cận chiến của phim được dàn dựng cực kỳ chân thực và mãn nhãn.",
      "scenes_to_use": [
        {"scene_id": 46, "start_sec": 128.0, "end_sec": 132.5}
      ]
    },
    {
      "id": 30,
      "section": "outro",
      "voiceover_text": "Tổng kết lại, phim xứng đáng nhận điểm 8.5/10. Bạn thấy kết phim như vậy đã hợp lý chưa?",
      "scenes_to_use": [
        {"scene_id": 1, "start_sec": 5.0, "end_sec": 10.0}
      ]
    }
  ]
}
```
3. **Dọn dẹp File Tạm Cloud Tức Thì:**  
   Gọi `client.files.delete(name=file.name)` ngay sau khi nhận được JSON.

---

### PHASE 3: GIAO DIỆN KIỂM DUYỆT STORYBOARD (FLUTTER GUI)
* Dữ liệu kịch bản được nạp lên giao diện **Storyboard Editor** trong Sub-Video:
  * Hiển thị 4 nhóm thẻ phân cảnh rõ ràng: **[Hook (5%)] | [Storytelling (70%)] | [Review (20%)] | [Outro (5%)]**.
  * Cho phép chỉnh sửa trực tiếp text câu thoại (không mất con trỏ soạn thảo).
  * Nút **🔊 Nghe thử** từng câu thoại qua EdgeTTS.
  * Nút **🔄 Đổi cảnh** để chọn cảnh B-roll khác trong kho keyframes.
  * Thống kê số chữ thời gian thực: `Số chữ: 955 / 966 (Ước tính: 5:58 / 6:00)`.

---

### PHASE 4: SINH GIỌNG ĐỌC (TTS) & ĐO THỜI LƯỢNG ĐỘNG
1. Gửi từng câu `voiceover_text` tới EdgeTTS với cấu hình Speed mong muốn ($1.0\times\text{--}1.3\times$).
2. Lưu file âm thanh `voice_01.mp3`, `voice_02.mp3`...
3. Dùng `mutagen` / `ffprobe` đo độ dài vật lý thực tế: `audio_duration` (ví dụ: `6.42s`).

---

### PHASE 5: CẮT GHÉP & CHỐNG LẸM CẢNH (DYNAMIC ASSEMBLY)
1. **Gom Phân Cảnh (Concatenate):**  
   Cắt các đoạn trong `scenes_to_use` từ video gốc và nối lại thành `Video_Thô`.
2. **Khớp Động Với Audio (Trimming / Slow-mo):**  
   * **Trường hợp 1 ($T_{video} \ge T_{audio}$):** Cắt bỏ phần thừa ở cuối `Video_Thô` bằng `-t {audio_duration}`.
   * **Trường hợp 2 ($T_{video} < T_{audio}$):** Áp dụng hiệu ứng `setpts=({audio_duration}/{video_duration})*PTS` làm chậm nhẹ chuyển động khớp chuẩn 100%.
3. **Định Dạng Tỷ Lệ (9:16 Dọc TikTok hoặc 16:9 Ngang YouTube):**  
   Tùy chọn 9:16: Video gốc ở giữa, lớp nền phía sau scale 1080x1920 làm mờ BoxBlur.
4. **Phụ Đề Động ASS & Lồng Nhạc Nền (BGM Ducking):**  
   Tự động sinh phụ đề phong cách SubBox Karaoke highlight; lồng BGM loop ở mức âm lượng 8–12%.
5. **Render Final Siêu Tốc:**  
   Nối tất cả các Segments bằng FFmpeg concat demuxer; xuất MP4 qua Hardware Acceleration (VideoToolbox / NVENC).
