"""
AI blueprint and script generators using Google Gemini for Movie Review engine:
- NarrativeBlueprintGenerator (Stage 1)
- GoldenScriptGenerator (Stage 2)
"""

import json
import subprocess
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

from .alignment import VisualAlignmentEngine
from .common import (
    calculate_word_budget,
    clean_json_str,
    emit_log,
    resolve_gemini_config,
)
from .subtitles import split_long_segments_by_speed


class NarrativeBlueprintGenerator:
    """Stage 1: Tóm tắt 5 hồi & chỉ định 15-20 mốc thời gian cao trào."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        model_name: Optional[str] = None,
        workspace: Optional[Path] = None,
        video_path: Optional[Path] = None
    ):
        resolved_key, resolved_model = resolve_gemini_config(
            provided_key=api_key,
            provided_model=model_name,
            workspace=workspace,
            video_path=video_path
        )
        self.api_key = resolved_key
        self.model_name = resolved_model

        if not self.api_key:
            raise ValueError(
                "Không tìm thấy Google Gemini API Key. "
                "Vui lòng cấu hình 'translator.api_key' trong config.yaml của project "
                "hoặc nhập trực tiếp API Key trên giao diện Review Phim."
            )

    def extract_audio_preview(self, video_path: Path, output_audio: Path) -> Path:
        """Bóc tách audio mono 16kHz nhẹ (24kbps) trong vài giây."""
        output_audio.parent.mkdir(parents=True, exist_ok=True)
        cmd = [
            "ffmpeg", "-y", "-i", str(video_path),
            "-vn", "-sn",
            "-ac", "1",
            "-ar", "16000",
            "-b:a", "24k",
            str(output_audio)
        ]
        emit_log("info", f"Trích xuất âm thanh nén siêu nhẹ: {output_audio.name}")
        subprocess.run(cmd, capture_output=True, check=True)
        return output_audio

    def generate_blueprint(
        self,
        audio_path: Path,
        genre: str,
        target_duration_sec: Optional[int],
        speed_factor: float,
        video_duration_sec: float,
        target_lang: str = "vi",
        review_style: str = "story_review",
        custom_prompt: Optional[str] = None
    ) -> Dict[str, Any]:
        from google import genai

        client = genai.Client(api_key=self.api_key)
        budget = calculate_word_budget(
            target_duration_sec=target_duration_sec,
            speed_factor=speed_factor,
            movie_duration_sec=video_duration_sec,
            review_style=review_style
        )
        effective_target_sec = budget["target_duration_sec"]
        num_chapters = budget.get("num_chapters", 6)

        emit_log("info", "Đang tải audio lên Google AI Cloud để phân tích...")
        audio_file = client.files.upload(file=str(audio_path))
        emit_log("info", f"Upload thành công (URI: {audio_file.name}). Chờ xử lý...")

        # Chờ file hoàn tất xử lý
        while audio_file.state.name == "PROCESSING":
            time.sleep(3)
            audio_file = client.files.get(name=audio_file.name)

        if audio_file.state.name == "FAILED":
            raise ValueError("Xử lý file audio trên Google AI thất bại.")

        genre_guidelines = {
            "linear_action": (
                "Thể loại Tuyến tính / Hành động: Cốt truyện đơn giản, hãy bỏ qua tiểu tiết, "
                "tập trung chọn các mốc thời gian có cảnh hành động gay cấn, truy đuổi, cận chiến, kỹ xảo mãn nhãn."
            ),
            "complex_psychological": (
                "Thể loại Phức tạp / Tâm lý / Trinh thám: Hãy chọn các mốc thời gian giải thích quy luật thế giới, "
                "diễn biến tâm lý bước ngoặt và các cú Twist quan trọng nhất."
            ),
            "shorts": (
                "Video Ngắn (Shorts/Reels): Hãy tập trung vào 1 biến cố éo le duy nhất và khoảnh khắc cao trào nhất."
            ),
        }.get(genre, "Chọn các mốc thời gian cao trào và nút thắt đắt giá nhất của phim.")

        min_total_footage = max(300, int(effective_target_sec * 1.5))
        min_beats = max(15, num_chapters * 2)
        max_beats = max(25, num_chapters * 3)

        user_prompt_instruction = ""
        if custom_prompt and custom_prompt.strip():
            user_prompt_instruction = f"\nĐẶC BIỆT - ĐỊNH HƯỚNG TỪ NGƯỜI DÙNG (USER PROMPT):\n\"{custom_prompt.strip()}\"\nHãy định hướng toàn bộ dàn ý, luận điểm trung tâm và lựa chọn phân cảnh theo sát yêu cầu trên.\n"

        prompt = f"""
Bạn là một đạo diễn và biên kịch review phim chuyên nghiệp (chuẩn bị nội dung chuyển hóa Transformative Content cho kênh triệu view).
Hãy nghe toàn bộ audio phim này và lập dàn ý kịch bản khai thác sâu toàn bộ cốt truyện theo mạch biến cố thực tế từ đầu đến cuối phim.
Tổng thời lượng phim gốc: {video_duration_sec:.1f} giây ({video_duration_sec/60.0:.1f} phút).
Thời lượng video review dự kiến: ~{effective_target_sec/60.0:.1f} phút (số chương cốt truyện: {num_chapters}).
Định hướng thể loại: {genre_guidelines}
{user_prompt_instruction}

YÊU CẦU QUAN TRỌNG VỀ ĐỘ DÀI MỐC THỜI GIAN & LUẬN ĐIỂM (BẮT BUỘC):
1. XÁC ĐỊNH LUẬN ĐIỂM TRUNG TÂM (CENTRAL THESIS):
   - Đưa ra 1 câu chủ đề sâu sắc bao quát ý nghĩa cốt lõi của bộ phim.
   - Đưa ra 3-5 luận cứ đắt giá (key arguments) để chứng minh cho luận điểm (về cốt truyện, tâm lý nhân vật, cú twist hoặc nghệ thuật điện ảnh).
   - Xác định sắc thái cảm xúc chủ đạo (emotional_tone: kịch tính, lắng đọng, châm biếm, hồi hộp).
2. CHỌN CÁC MỐC THỜI GIAN BIẾN CỐ (STORYLINE BEATS):
   - Hãy chọn ra từ {min_beats} đến {max_beats} khoảng thời gian (timestamp ranges) chứa các phân cảnh cao trào, bước ngoặt đắt giá nhất trải đều từ đầu đến cuối phim.
   - MỖI MỐC THỜI GIAN PHẢI ĐỦ DÀI: Tối thiểu từ 30 đến 90 giây mỗi mốc (ví dụ: start_sec: 60.0, end_sec: 120.0). TUYỆT ĐỐI KHÔNG chọn các mốc quá ngắn 5-10 giây vì sẽ không đủ chất liệu hình ảnh để dựng video.
3. Tổng thời lượng của tất cả các mốc chọn cộng lại phải đạt tối thiểu từ {min_total_footage} giây đến {int(video_duration_sec * 0.85)} giây.
4. Các mốc thời gian phải nằm hoàn toàn trong phạm vi từ 0 đến {video_duration_sec:.1f} giây.

Trả về DUY NHẤT một chuỗi JSON theo cấu trúc sau:
{{
  "movie_title": "Tên phim tiếng Việt hoặc quốc tế",
  "genre": "{genre}",
  "target_duration_sec": {effective_target_sec},
  "summary": "Tóm tắt ngắn gọn cốt truyện phim trong 2-3 câu",
  "central_thesis": "Luận điểm trung tâm sâu sắc bao quát ý nghĩa của bộ phim",
  "key_arguments": [
    "Luận cứ 1 về mâu thuẫn cốt lõi của nhân vật",
    "Luận cứ 2 về bước ngoặt hoặc quy luật thế giới trong phim",
    "Luận cứ 3 về cú twist và thông điệp đọng lại"
  ],
  "emotional_tone": "kịch tính, lắng đọng",
  "blueprint_ranges": [
    {{
      "id": 1,
      "act": "hook",
      "start_sec": 120.0,
      "end_sec": 160.0,
      "description": "Khoảnh khắc nhân vật gặp nguy hiểm tột cùng"
    }},
    {{
      "id": 2,
      "act": "storytelling",
      "start_sec": 300.0,
      "end_sec": 420.0,
      "description": "Bối cảnh xuất phát và mâu thuẫn mở đầu"
    }}
  ]
}}
"""
        emit_log("info", f"Đang gọi Gemini ({self.model_name}) lập dàn ý kịch bản...")
        try:
            response = client.models.generate_content(
                model=self.model_name,
                contents=[audio_file, prompt],
                config={"response_mime_type": "application/json"}
            )
            raw_text = response.text.strip()
            blueprint_data = json.loads(clean_json_str(raw_text))
            blueprint_data["word_budget"] = budget
            return blueprint_data
        finally:
            # Dọn dẹp tức thì trên Cloud
            try:
                client.files.delete(name=audio_file.name)
                emit_log("info", "Đã giải phóng file audio trên Cloud.")
            except Exception:
                pass


class GoldenScriptGenerator:
    """Stage 2: Viết kịch bản Thesis-Driven chuẩn tỷ lệ vàng 4 phần và tự động phối cảnh thông minh."""

    def __init__(
        self,
        api_key: Optional[str] = None,
        model_name: Optional[str] = None,
        workspace: Optional[Path] = None,
        video_path: Optional[Path] = None
    ):
        resolved_key, resolved_model = resolve_gemini_config(
            provided_key=api_key,
            provided_model=model_name,
            workspace=workspace,
            video_path=video_path
        )
        self.api_key = resolved_key
        self.model_name = resolved_model

        if not self.api_key:
            raise ValueError(
                "Không tìm thấy Google Gemini API Key. "
                "Vui lòng cấu hình 'translator.api_key' trong config.yaml của project "
                "hoặc nhập trực tiếp API Key trên giao diện Review Phim."
            )

    def generate_montage_script(
        self,
        scenes: List[Dict[str, Any]],
        blueprint: Dict[str, Any],
        keyframes_dir: Path,
        target_lang: str = "vi",
        audio_path: Optional[Path] = None,
        review_style: str = "story_review",
        acts_config: Optional[Dict[str, Any]] = None,
        custom_prompt: Optional[str] = None
    ) -> Dict[str, Any]:
        from google import genai

        client = genai.Client(api_key=self.api_key)
        speed = float(blueprint.get("speed_factor", 1.45))
        effective_acts_cfg = acts_config or blueprint.get("acts_config")
        budget = blueprint.get("word_budget", calculate_word_budget(360, speed, acts_config=effective_acts_cfg))
        target_dur = int(blueprint.get("target_duration_sec", 360))
        num_chapters = budget.get("num_chapters", 0)
        chapter_words = budget.get("chapter_words", budget.get("story_words", 500))

        # Lọc storyline beats theo chapters được chọn nếu có
        blueprint_ranges = blueprint.get("blueprint_ranges", [])
        if effective_acts_cfg and isinstance(effective_acts_cfg.get("story"), dict):
            selected_ch = effective_acts_cfg["story"].get("chapters")
            if isinstance(selected_ch, (list, tuple)) and len(selected_ch) > 0:
                blueprint_ranges = [r for r in blueprint_ranges if r.get("id") in selected_ch]

        story_outline = "\n".join([
            f"- Mốc {int(r.get('start_sec', 0)//60):02d}:{int(r.get('start_sec', 0)%60):02d} ({r.get('act', 'story')}): {r.get('description', '')}"
            for r in blueprint_ranges
        ])

        key_args = blueprint.get("key_arguments", [])
        args_text = "\n".join([f"- {a}" for a in key_args]) if key_args else "- Khám phá ý nghĩa ẩn sâu và diễn biến tâm lý nhân vật"

        user_prompt_instruction = ""
        if custom_prompt and custom_prompt.strip():
            user_prompt_instruction = f"\n- LƯU Ý ĐẶC BIỆT TỪ NGƯỜI DÙNG: \"{custom_prompt.strip()}\"\nHãy lồng ghép phong cách, góc nhìn và thông điệp này vào bài viết."

        if review_style == "critique":
            # --- OPTION 1: PHÊ BÌNH TÁC PHẨM (FILM CRITIQUE - THESIS-DRIVEN) ---
            emit_log("info", f"Đang yêu cầu Gemini viết kịch bản Phê Bình Tác Phẩm (ngân sách ~{budget['total_words']} từ, {num_chapters} chương, speed {speed:.2f}x)...")
            if num_chapters > 0:
                prompt = f"""
Bạn là Chuyên Gia Biên Kịch & Phê Bình Phim số 1 (phong cách cuốn hút, sắc bén, kịch tính như Phê Phim, Khen Phim, Xem Phim Làm Sao).
Nhiệm vụ của bạn là nghe toàn bộ audio của bộ phim "{blueprint.get('movie_title', 'Bộ phim')}" và viết một bài Review Phim hoàn chỉnh đạt chuẩn MONETIZATION YOUTUBE (Nội dung chuyển hóa - Transformative Content, lập luận sâu sắc, cuốn hút từ giây đầu tiên đến phút cuối cùng).

THÔNG TIN ĐỊNH HƯỚNG TỪ BẢN THIẾT KẾ:
- Tóm tắt cốt truyện: {blueprint.get('summary', '')}
- Luận điểm trung tâm (Central Thesis): {blueprint.get('central_thesis', 'Bộ phim là câu chuyện sâu sắc về số phận và lựa chọn của nhân vật')}
- Các luận cứ chính (Key Arguments):
{args_text}
- Dòng sự kiện chính (Storyline Beats):
{story_outline}{user_prompt_instruction}

QUY CHUẨN BÀI REVIEW ĐIỆN ẢNH CHUẨN MONETIZATION (BẮT BUỘC):
1. ĐÓNG VAI NGÔI THỨ BA CỦA NHÀ PHÊ BÌNH ĐIỆN ẢNH:
   - Bạn là người đánh giá, phân tích và bình phẩm tác phẩm.
   - TUYỆT ĐỐI KHÔNG làm người kể chuyện thiếu nhi hay đọc sách tranh.
   - NGHIÊM CẤM miêu tả cử chỉ vật lý vụn vặt từng khung hình (CẤM các câu: "Bàn tay ai đó...", "Đôi mắt to tròn...", "Một người đang đứng...", "Cô bé nâng niu bát cháo...", "Nghịch giỏ tre...", "Chạy về nhà...").
   - DỰA TRÊN LỜI THOẠI THỰC TẾ TRONG AUDIO: Trích dẫn đúng tên nhân vật, mâu thuẫn thật, câu thoại đắt giá thật nghe được từ audio.

2. BỐ CỤC PHÂN CHƯƠNG ĐA HỒI ({num_chapters + 3} PHẦN - TỔNG NGÂN SÁCH ~{budget['total_words']} TỪ):
   - Hồi "hook" (~{budget['hook_words']} từ): Mở bài giật gân, nêu ngay nghịch lý hoặc câu hỏi mở từ Luận Điểm Trung Tâm để giữ chân khán giả 15 giây đầu.
   - BẰNG CHỨNG CỐT TRUYỆN ĐƯỢC CHIA THÀNH {num_chapters} CHƯƠNG (MỖI CHƯƠNG TỐI THIỂU TỪ {max(180, chapter_words - 50)} TỪ TRỞ LÊN, KHÔNG GIỚI HẠN TRẦN TRÊN):
     Mỗi chương phân tích một biến cố cốt lõi theo mốc thời gian như một BẰNG CHỨNG ĐẮT GIÁ chứng minh cho luận điểm trung tâm, trích dẫn đúng lời thoại và xung đột thật từ audio. TUYỆT ĐỐI KHÔNG TÓM TẮT SƠ SÀI.
   - Hồi "review" (~{budget['review_words']} từ): Phân tích sâu cú twist, diễn xuất, ẩn ý hình ảnh, thủ pháp đạo diễn, điểm khen/chê thuyết phục.
   - Hồi "outro" (~{budget['outro_words']} từ): Đúc kết thông điệp đọng lại sâu sắc nhất, chấm điểm phim trên thang 10 và kêu gọi khán giả like, đăng ký, thảo luận (CTA).

3. ĐỊNH DẠNG ĐẦU RA (JSON BẮT BUỘC):
Trả về DUY NHẤT một chuỗi JSON theo cấu trúc sau:
{{
  "title": "Tên video review hấp dẫn, giật gân chuẩn YouTube",
  "central_thesis": "{blueprint.get('central_thesis', '')}",
  "target_duration_sec": {target_dur},
  "total_word_count": {budget['total_words']},
  "hook": {{
    "text": "Nội dung văn xuôi hoàn chỉnh của phần mở đầu...",
    "visual_intent": "symbolic"
  }},
  "chapters": [
    {{
      "chapter_id": 1,
      "title": "Tên chương 1 theo diễn biến phim",
      "time_range": [0, 600],
      "text": "Nội dung phân tích chương 1 (ít nhất {chapter_words} từ)...",
      "visual_intent": "direct"
    }}
  ],
  "review": {{
    "text": "Nội dung văn xuôi bình luận chuyên sâu, cú twist...",
    "visual_intent": "symbolic"
  }},
  "outro": {{
    "text": "Nội dung văn xuôi tổng kết, chấm điểm và kêu gọi CTA...",
    "visual_intent": "direct"
  }}
}}
"""
            else:
                prompt = f"""
Bạn là Chuyên Gia Biên Kịch & Phê Bình Phim số 1 (phong cách cuốn hút, sắc bén, kịch tính như Phê Phim, Khen Phim, Xem Phim Làm Sao).
Nhiệm vụ của bạn là nghe toàn bộ audio của bộ phim "{blueprint.get('movie_title', 'Bộ phim')}" và viết một bài Review Phim hoàn chỉnh đạt chuẩn MONETIZATION YOUTUBE (Nội dung chuyển hóa - Transformative Content, lập luận sâu sắc, cuốn hút từ giây đầu tiên đến phút cuối cùng).

THÔNG TIN ĐỊNH HƯỚNG TỪ BẢN THIẾT KẾ:
- Tóm tắt cốt truyện: {blueprint.get('summary', '')}
- Luận điểm trung tâm (Central Thesis): {blueprint.get('central_thesis', 'Bộ phim là câu chuyện sâu sắc về số phận và lựa chọn của nhân vật')}
- Các luận cứ chính (Key Arguments):
{args_text}
- Dòng sự kiện chính (Storyline Beats):
{story_outline}{user_prompt_instruction}

QUY CHUẨN BÀI REVIEW ĐIỆN ẢNH CHUẨN MONETIZATION (BẮT BUỘC):
1. ĐÓNG VAI NGÔI THỨ BA CỦA NHÀ PHÊ BÌNH ĐIỆN ẢNH:
   - Bạn là người đánh giá, phân tích và bình phẩm tác phẩm.
   - TUYỆT ĐỐI KHÔNG làm người kể chuyện thiếu nhi hay đọc sách tranh.
   - NGHIÊM CẤM miêu tả cử chỉ vật lý vụn vặt từng khung hình (CẤM các câu: "Bàn tay ai đó...", "Đôi mắt to tròn...", "Một người đang đứng...", "Cô bé nâng niu bát cháo...", "Nghịch giỏ tre...", "Chạy về nhà...").
   - DỰA TRÊN LỜI THOẠI THỰC TẾ TRONG AUDIO: Trích dẫn đúng tên nhân vật, mâu thuẫn thật, câu thoại đắt giá thật nghe được từ audio.

2. BỐ CỤC 4 HỒI REVIEW VĂN XUÔI HOÀN CHỈNH (TỔNG NGÂN SÁCH ~{budget['total_words']} TỪ):
   - Hồi "hook" (~{budget['hook_words']} từ, 2-3 đoạn văn): Mở bài giật gân, nêu ngay nghịch lý hoặc câu hỏi mở từ Luận Điểm Trung Tâm để giữ chân khán giả 15 giây đầu.
   - Hồi "story" (~{budget['story_words']} từ, 4-6 đoạn văn): Kể lại diễn biến cốt lõi của phim theo trình tự thời gian, nhưng mỗi diễn biến được phân tích như một BẰNG CHỨNG ĐẮT GIÁ chứng minh cho luận điểm trung tâm.
   - Hồi "review" (~{budget['review_words']} từ, 3-4 đoạn văn): Phân tích sâu cú twist, diễn xuất, ẩn ý hình ảnh, thủ pháp đạo diễn, điểm khen/chê thuyết phục.
   - Hồi "outro" (~{budget['outro_words']} từ, 1-2 đoạn văn): Đúc kết thông điệp đọng lại sâu sắc nhất, chấm điểm phim trên thang 10 và kêu gọi khán giả like, đăng ký, thảo luận (CTA).

3. ĐỊNH DẠNG ĐẦU RA (JSON):
Trả về DUY NHẤT một chuỗi JSON theo cấu trúc sau:
{{
  "title": "Tên video review hấp dẫn, giật gân chuẩn YouTube",
  "central_thesis": "{blueprint.get('central_thesis', '')}",
  "target_duration_sec": {target_dur},
  "total_word_count": {budget['total_words']},
  "sections": [
    {{
      "section": "hook",
      "text": "Nội dung văn xuôi hoàn chỉnh của phần mở đầu...",
      "visual_intent": "symbolic"
    }},
    {{
      "section": "story",
      "text": "Nội dung văn xuôi phân tích diễn biến cốt truyện...",
      "visual_intent": "direct"
    }},
    {{
      "section": "review",
      "text": "Nội dung văn xuôi bình luận chuyên sâu, cú twist...",
      "visual_intent": "symbolic"
    }},
    {{
      "section": "outro",
      "text": "Nội dung văn xuôi tổng kết, chấm điểm và kêu gọi CTA...",
      "visual_intent": "direct"
    }}
  ]
}}
"""
        else:
            # --- OPTION 2: KỂ CHUYỆN KỊCH TÍNH (STORY-DRIVEN REVIEW / SPOIL PHIM TRIỆU VIEW) ---
            hook_words = int(budget["total_words"] * 0.10)
            story_words = int(budget["total_words"] * 0.75)
            review_words = int(budget["total_words"] * 0.10)
            outro_words = budget["total_words"] - hook_words - story_words - review_words

            emit_log("info", f"Đang yêu cầu Gemini viết kịch bản Review Kể Chuyện Kịch Tính (ngân sách ~{budget['total_words']} từ, {num_chapters} chương, speed {speed:.2f}x)...")
            if num_chapters > 0:
                prompt = f"""
Bạn là Vua Biên Kịch Review Phim Triệu View trên YouTube & TikTok (phong cách dẫn chuyện kịch tính, lôi cuốn, gay cấn, nhịp nhanh, cuốn hút từng giây như Spoil Phim, Tóm Tắt Phim Cực Cuốn, Phim Hay Mỗi Ngày).
Nhiệm vụ của bạn là nghe toàn bộ audio của bộ phim "{blueprint.get('movie_title', 'Bộ phim')}" và viết một kịch bản Review Phim Kể Chuyện Kịch Tính (Story-Driven Review) chuẩn Monetization YouTube.

THÔNG TIN ĐỊNH HƯỚNG TỪ BẢN THIẾT KẾ:
- Tóm tắt cốt truyện: {blueprint.get('summary', '')}
- Dòng sự kiện chính (Storyline Beats):
{story_outline}{user_prompt_instruction}

QUY CHUẨN KỂ CHUYỆN KỊCH TÍNH TRIỆU VIEW (BẮT BUỘC):
1. PHONG CÁCH KỂ CHUYỆN DẪN DẮT (STORYTELLING):
   - Kể lại toàn bộ diễn biến câu chuyện một cách hồi hộp, gay cấn, dẫn dắt người xem đi từ bất ngờ này đến bất ngờ khác.
   - TUYỆT ĐỐI KHÔNG viết như bài văn phân tích học thuật (CẤM các câu: "Đạo diễn đã khéo léo...", "Thủ pháp nghệ thuật...", "Bộ phim là lớp vỏ...", "Bối cảnh là nhân vật có tiếng nói riêng...").
   - TUYỆT ĐỐI KHÔNG miêu tả vụn vặt từng hành động thể xác (CẤM: "Bàn tay ai đó chạm đầu...", "Cô bé bưng bát cháo...", "Nghịch giỏ tre...").
   - DÙNG VĂN PHONG REVIEW TRIỆU VIEW CUỐN HÚT: "Mọi chuyện bắt đầu khi...", "Cứ ngỡ vớ được món hời, nào ngờ...", "Chính quyết định sai lầm này đã đẩy họ vào...", "Cú quay xe bất ngờ ở phút chót khiến ai nấy đều phải ngã ngửa...", "Tình thế ngày càng ngàn cân treo sợi tóc khi...".
   - DỰA TRÊN LỜI THOẠI & SỰ KIỆN THỰC TẾ TRONG AUDIO: Kể đúng tên nhân vật, tình huống kịch tính thật, mâu thuẫn thật nghe được từ audio.

2. BỐ CỤC PHÂN CHƯƠNG ĐA HỒI ({num_chapters + 3} PHẦN - TỔNG NGÂN SÁCH ~{budget['total_words']} TỪ):
   - Hồi "hook" (~{hook_words} từ, 1-2 đoạn văn): Mở đầu giật gân, cảnh báo hiểm họa hoặc nghịch cảnh trớ trêu để giữ chân khán giả 10 giây đầu.
   - CỐT TRUYỆN ĐƯỢC CHIA THÀNH {num_chapters} CHƯƠNG (MỖI CHƯƠNG TỐI THIỂU TỪ {max(180, chapter_words - 50)} TỪ TRỞ LÊN, KHÔNG GIỚI HẠN TRẦN TRÊN):
     Kể chi tiết toàn bộ diễn biến câu chuyện bám sát các mốc thời gian (Storyline Beats) từ đầu đến cuối phim. Mỗi chương phải đào sâu vào lời thoại thật, tên nhân vật thật, hành động đối đầu và biến cố thật nghe được từ audio. TUYỆT ĐỐI KHÔNG TÓM TẮT SƠ SÀI.
   - Hồi "review" (~{review_words} từ, 1-2 đoạn văn): Nhận xét cảm xúc tự nhiên của người xem về sự éo le, khen chê các pha xử lý của nhân vật và cú lật mặt của phim.
   - Hồi "outro" (~{outro_words} từ, 1 đoạn văn): Đúc kết ngắn gọn, đặt câu hỏi cho khán giả thảo luận và kêu gọi Subscribe.

3. ĐỊNH DẠNG ĐẦU RA (JSON BẮT BUỘC):
Trả về DUY NHẤT một chuỗi JSON theo cấu trúc sau:
{{
  "title": "Tên video review giật gân, siêu cuốn hút chuẩn YouTube",
  "central_thesis": "{blueprint.get('central_thesis', '')}",
  "target_duration_sec": {target_dur},
  "total_word_count": {budget['total_words']},
  "hook": {{
    "text": "Nội dung mở đầu giật gân, lôi cuốn khán giả...",
    "visual_intent": "symbolic"
  }},
  "chapters": [
    {{
      "chapter_id": 1,
      "title": "Tên chương 1 theo mạch phim",
      "time_range": [0, 600],
      "text": "Nội dung kể chi tiết diễn biến, lời thoại thật của chương 1 (ít nhất {chapter_words} từ)...",
      "visual_intent": "direct"
    }}
  ],
  "review": {{
    "text": "Nội dung nhận xét cảm xúc, cú quay xe bất ngờ...",
    "visual_intent": "symbolic"
  }},
  "outro": {{
    "text": "Nội dung tổng kết ngắn gọn và CTA subscribe...",
    "visual_intent": "direct"
  }}
}}
"""
            else:
                prompt = f"""
Bạn là Vua Biên Kịch Review Phim Triệu View trên YouTube & TikTok (phong cách dẫn chuyện kịch tính, lôi cuốn, gay cấn, nhịp nhanh, cuốn hút từng giây như Spoil Phim, Tóm Tắt Phim Cực Cuốn, Phim Hay Mỗi Ngày).
Nhiệm vụ của bạn là nghe toàn bộ audio của bộ phim "{blueprint.get('movie_title', 'Bộ phim')}" và viết một kịch bản Review Phim Kể Chuyện Kịch Tính (Story-Driven Review) chuẩn Monetization YouTube.

THÔNG TIN ĐỊNH HƯỚNG TỪ BẢN THIẾT KẾ:
- Tóm tắt cốt truyện: {blueprint.get('summary', '')}
- Dòng sự kiện chính (Storyline Beats):
{story_outline}{user_prompt_instruction}

QUY CHUẨN KỂ CHUYỆN KỊCH TÍNH TRIỆU VIEW (BẮT BUỘC):
1. PHONG CÁCH KỂ CHUYỆN DẪN DẮT (STORYTELLING):
   - Kể lại toàn bộ diễn biến câu chuyện một cách hồi hộp, gay cấn, dẫn dắt người xem đi từ bất ngờ này đến bất ngờ khác.
   - TUYỆT ĐỐI KHÔNG viết như bài văn phân tích học thuật (CẤM các câu: "Đạo diễn đã khéo léo...", "Thủ pháp nghệ thuật...", "Bộ phim là lớp vỏ...", "Bối cảnh là nhân vật có tiếng nói riêng...").
   - TUYỆT ĐỐI KHÔNG miêu tả vụn vặt từng hành động thể xác (CẤM: "Bàn tay ai đó chạm đầu...", "Cô bé bưng bát cháo...", "Nghịch giỏ tre...").
   - DÙNG VĂN PHONG REVIEW TRIỆU VIEW CUỐN HÚT: "Mọi chuyện bắt đầu khi...", "Cứ ngỡ vớ được món hời, nào ngờ...", "Chính quyết định sai lầm này đã đẩy họ vào...", "Cú quay xe bất ngờ ở phút chót khiến ai nấy đều phải ngã ngửa...", "Tình thế ngày càng ngàn cân treo sợi tóc khi...".
   - DỰA TRÊN LỜI THOẠI & SỰ KIỆN THỰC TẾ TRONG AUDIO: Kể đúng tên nhân vật, tình huống kịch tính thật, mâu thuẫn thật nghe được từ audio.

2. BỐ CỤC 4 PHẦN KỂ CHUYỆN KỊCH TÍNH (TỔNG NGÂN SÁCH ~{budget['total_words']} TỪ):
   - Hồi "hook" (~{hook_words} từ, 1-2 đoạn văn): Mở đầu giật gân, cảnh báo hiểm họa hoặc nghịch cảnh trớ trêu để giữ chân khán giả 10 giây đầu.
   - Hồi "story" (~{story_words} từ, 6-8 đoạn văn): Kể lại toàn bộ mạch phim theo diễn biến kịch tính dồn dập (mở đầu -> biến cố -> cao trào -> nút thắt -> cú twist -> kết cục).
   - Hồi "review" (~{review_words} từ, 1-2 đoạn văn): Nhận xét cảm xúc tự nhiên của người xem về sự éo le, khen chê các pha xử lý của nhân vật và cú lật mặt của phim.
   - Hồi "outro" (~{outro_words} từ, 1 đoạn văn): Đúc kết ngắn gọn, đặt câu hỏi cho khán giả thảo luận và kêu gọi Subscribe.

3. ĐỊNH DẠNG ĐẦU RA (JSON):
Trả về DUY NHẤT một chuỗi JSON theo cấu trúc sau:
{{
  "title": "Tên video review giật gân, siêu cuốn hút chuẩn YouTube",
  "central_thesis": "{blueprint.get('central_thesis', '')}",
  "target_duration_sec": {target_dur},
  "total_word_count": {budget['total_words']},
  "sections": [
    {{
      "section": "hook",
      "text": "Nội dung mở đầu giật gân, lôi cuốn khán giả...",
      "visual_intent": "symbolic"
    }},
    {{
      "section": "story",
      "text": "Nội dung kể lại cốt truyện kịch tính, dồn dập...",
      "visual_intent": "direct"
    }},
    {{
      "section": "review",
      "text": "Nội dung nhận xét cảm xúc, cú quay xe bất ngờ...",
      "visual_intent": "symbolic"
    }},
    {{
      "section": "outro",
      "text": "Nội dung tổng kết ngắn gọn và CTA subscribe...",
      "visual_intent": "direct"
    }}
  ]
}}
"""
        audio_file = None
        contents = [prompt]
        if audio_path and Path(audio_path).is_file():
            try:
                emit_log("info", f"Đang tải audio gốc ({Path(audio_path).name}) lên Gemini để nghe lời thoại và phân tích kịch bản...")
                audio_file = client.files.upload(file=str(audio_path))
                while audio_file.state.name == "PROCESSING":
                    time.sleep(2)
                    audio_file = client.files.get(name=audio_file.name)
                contents = [audio_file, prompt]
                emit_log("info", "Upload audio thành công. Đang gọi Gemini nghe audio & sinh bài luận Review...")
            except Exception as e:
                emit_log("warning", f"Không thể tải audio lên Gemini ({e}), chuyển sang sinh kịch bản từ text blueprint...")
                contents = [prompt]

        try:
            response = client.models.generate_content(
                model=self.model_name,
                contents=contents,
                config={"response_mime_type": "application/json"}
            )
            raw_text = response.text.strip()
            result = json.loads(clean_json_str(raw_text))
        finally:
            if audio_file:
                try:
                    client.files.delete(name=audio_file.name)
                    emit_log("info", "Đã dọn dẹp file audio kịch bản trên Cloud.")
                except Exception:
                    pass

        # Chuyển đổi sections/chapters thành các cues thoại ngắn bằng split_long_segments_by_speed
        raw_items = []
        if "chapters" in result and isinstance(result["chapters"], list):
            # 1. Hook
            if "hook" in result and isinstance(result["hook"], dict):
                h_text = result["hook"].get("text", "").strip()
                if h_text:
                    raw_items.append({
                        "section": "hook",
                        "voiceover_text": h_text,
                        "visual_intent": result["hook"].get("visual_intent", "symbolic"),
                    })
            elif "sections" in result and isinstance(result["sections"], list):
                for sec in result["sections"]:
                    if sec.get("section") == "hook":
                        raw_items.append({
                            "section": "hook",
                            "voiceover_text": sec.get("text", "").strip(),
                            "visual_intent": sec.get("visual_intent", "symbolic"),
                        })
            # 2. Chapters
            for ch in result["chapters"]:
                c_text = ch.get("text", "").strip()
                if c_text:
                    raw_items.append({
                        "section": "story",
                        "voiceover_text": c_text,
                        "visual_intent": ch.get("visual_intent", "direct"),
                        "chapter_title": ch.get("title", ""),
                        "time_range": ch.get("time_range"),
                    })
            # 3. Review
            if "review" in result and isinstance(result["review"], dict):
                r_text = result["review"].get("text", "").strip()
                if r_text:
                    raw_items.append({
                        "section": "review",
                        "voiceover_text": r_text,
                        "visual_intent": result["review"].get("visual_intent", "symbolic"),
                    })
            elif "sections" in result and isinstance(result["sections"], list):
                for sec in result["sections"]:
                    if sec.get("section") in ["review", "critique"]:
                        raw_items.append({
                            "section": "review",
                            "voiceover_text": sec.get("text", "").strip(),
                            "visual_intent": sec.get("visual_intent", "symbolic"),
                        })
            # 4. Outro
            if "outro" in result and isinstance(result["outro"], dict):
                o_text = result["outro"].get("text", "").strip()
                if o_text:
                    raw_items.append({
                        "section": "outro",
                        "voiceover_text": o_text,
                        "visual_intent": result["outro"].get("visual_intent", "direct"),
                    })
            elif "sections" in result and isinstance(result["sections"], list):
                for sec in result["sections"]:
                    if sec.get("section") == "outro":
                        raw_items.append({
                            "section": "outro",
                            "voiceover_text": sec.get("text", "").strip(),
                            "visual_intent": sec.get("visual_intent", "direct"),
                        })
        elif "sections" in result and isinstance(result["sections"], list):
            for sec in result["sections"]:
                s_name = sec.get("section", "story")
                s_text = sec.get("text", "").strip()
                s_intent = sec.get("visual_intent", "direct")
                if s_text:
                    raw_items.append({
                        "section": s_name,
                        "voiceover_text": s_text,
                        "visual_intent": s_intent
                    })
        elif "script" in result and isinstance(result["script"], list):
            for item in result["script"]:
                raw_items.append({
                    "section": item.get("section", "story"),
                    "voiceover_text": item.get("text") or item.get("voiceover_text", ""),
                    "visual_intent": item.get("visual_intent", "direct")
                })

        # Phân đoạn thành các cues 3.5s - 7.5s (10-22 từ) theo tốc độ đọc
        split_items = split_long_segments_by_speed(raw_items, speed_factor=speed, target_shot_sec_range=(3.5, 7.5))

        # So khớp Visual Alignment In-Memory thông minh
        aligned_items = VisualAlignmentEngine.align_script_with_scenes(
            split_items,
            scenes=scenes,
            video_duration_sec=float(target_dur)
        )

        # Đánh số ID tuần tự 1, 2, 3...
        for idx, item in enumerate(aligned_items):
            item["id"] = idx + 1

        result["script"] = aligned_items
        return result
