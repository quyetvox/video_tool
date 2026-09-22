#!/usr/bin/env python3
"""
Vlog Story Prompts — Các mẫu Prompt chuyên biệt cho AI Storyteller & Vlog Narration
Tối ưu hóa cho Google Gemini Multimodal Video (1-Pass) & Ollama Vision Fallback.
"""

from typing import Optional


PRESET_INSTRUCTIONS = {
    "daily_chill": (
        "Phong cách: Vlog đời thường, ấm áp, thư thái, nhẹ nhàng (Chill Lifestyle). "
        "Ngôi xưng: Ngôi thứ nhất ('mình' hoặc 'tôi'). "
        "Giọng điệu: Thân mật như đang tâm sự, trò chuyện cùng bạn bè thân thiết, "
        "chia sẻ những cảm xúc chân thật, quan sát những chi tiết nhỏ thú vị trong cuộc sống thường nhật."
    ),
    "cinematic": (
        "Phong cách: Thuyết minh điện ảnh, sâu sắc, giàu hình ảnh và triết lý (Cinematic Documentary). "
        "Ngôi xưng: Ngôi thứ ba hoặc người dẫn chuyện giấu mặt. "
        "Giọng điệu: Trầm ấm, sâu lắng, văn phong trau chuốt, gợi mở không gian, thời gian "
        "và ý nghĩa biểu tượng của từng hành động, khung cảnh."
    ),
    "humorous": (
        "Phong cách: Hài hước, dí dỏm, bắt trend, duyên dáng và tràn đầy năng lượng (Catchy Viral). "
        "Ngôi xưng: Ngôi thứ nhất hoặc người bình luận dí dỏm. "
        "Giọng điệu: Hóm hỉnh, chơi chữ tinh tế, tạo bất ngờ thú vị cho người xem, "
        "rất hợp với định dạng video ngắn TikTok/Reels."
    ),
    "auto": (
        "Phong cách: Tự động thích ứng linh hoạt. Hãy quan sát bối cảnh, nhịp điệu chuyển động, "
        "màu sắc ánh sáng và hành động trong video để tự chọn phong cách phù hợp nhất "
        "(nếu video cảnh thiên nhiên/nấu ăn yên bình -> phong cách chill; "
        "nếu video có hành động hài hước/thú cưng -> phong cách vui nhộn; "
        "nếu video phong cảnh hùng vĩ/nghệ thuật -> phong cách điện ảnh sâu lắng)."
    )
}


def build_gemini_vlog_prompt(
    duration: float,
    style: str = "daily_chill",
    custom_prompt: Optional[str] = None,
    words_per_sec: float = 2.2,
    tts_speed: float = 1.0,
) -> str:
    """Xây dựng prompt 1-pass cho Gemini xem video và xuất phân đoạn kịch bản JSON."""
    preset_guide = PRESET_INSTRUCTIONS.get(style, PRESET_INSTRUCTIONS["daily_chill"])
    effective_wps = words_per_sec * tts_speed

    custom_block = ""
    if custom_prompt and custom_prompt.strip():
        custom_block = f"""
GỢI Ý Ý TƯỞNG / CHỦ ĐỀ TỪ TÁC GIẢ:
"{custom_prompt.strip()}"
(Hãy lồng ghép khéo léo thông điệp hoặc câu chuyện này vào lời dẫn sao cho khớp với hình ảnh thực tế).
"""

    return f"""Bạn là một đạo diễn và biên kịch video tài năng, chuyên sáng tạo kịch bản lồng tiếng (voiceover/narration) cho các video ngắn, vlog đời sống, du lịch và ẩm thực.

THÔNG TIN VIDEO:
- Tổng thời lượng video: chính xác {duration:.1f} giây.
- Đặc điểm: Video không có lời thoại sẵn (chỉ có hình ảnh hoặc âm thanh môi trường/nhạc nền). Video sẽ được GIỮ NGUYÊN 100% dòng thời gian (không cắt ghép hay xáo trộn thứ tự cảnh).

ĐỊNH HƯỚNG PHONG CÁCH KỂ CHUYỆN:
{preset_guide}
{custom_block}

NHIỆM VỤ CỦA BẠN:
1. Xem toàn bộ video từ 0.0s đến {duration:.1f}s.
2. Chia video thành các phân đoạn cảnh (scenes/beats) tự nhiên theo hành động hoặc góc máy. Mỗi phân đoạn thường kéo dài từ 3.0s đến 8.0s.
3. Với MỖI phân đoạn:
   - Xác định chính xác mốc thời gian bắt đầu `start` và kết thúc `end` (tính bằng giây).
   - Mô tả ngắn gọn nội dung hình ảnh thực tế `visual_desc` (1 câu ngắn).
   - Viết 1 câu lồng tiếng tiếng Việt hoàn chỉnh `text` tương ứng.
   - BẮT BUỘC KHỐNG CHẾ SỐ TỪ: Số từ của `text` KHÔNG ĐƯỢC VƯỢT QUÁ ngân sách từ tối đa: max_words = int((end - start) * {effective_wps:.2f}).
   - Nếu phân đoạn quá ngắn (< 2.5s) hoặc cần khoảng lặng nghệ thuật để người xem ngắm cảnh, hãy để `text`: "" (đoạn này sẽ là khoảng thở âm nhạc).
4. Các phân đoạn phải liên tục, sắp xếp tăng dần theo thời gian, không được chồng lấn nhau và phân đoạn cuối cùng kết thúc đúng tại hoặc trước {duration:.1f}s.

YÊU CẦU ĐỊNH DẠNG ĐẦU RA:
Chỉ trả về DUY NHẤT một khối JSON hợp lệ dạng danh sách (JSON Array), KHÔNG kèm bất kỳ lời giải thích nào ngoài khối mã:
```json
[
  {{
    "start": 0.0,
    "end": 4.5,
    "visual_desc": "Góc quay từ trên cao nhìn xuống con phố lúc sớm mai.",
    "text": "Một buổi sáng bình yên bắt đầu khi thành phố còn ngái ngủ.",
    "max_words": 10
  }},
  {{
    "start": 4.5,
    "end": 9.2,
    "visual_desc": "Đang rót nước sôi pha một ly cà phê phin đậm đà.",
    "text": "Hương cà phê phin tí tách làm bừng tỉnh mọi giác quan.",
    "max_words": 11
  }}
]
```
"""
