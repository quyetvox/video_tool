"""
AI-Authored Scene Generation Engine (Lecture Illustrator - Lean Direct AI Engine).

Quy trình tự động thiết kế cảnh minh họa bài giảng do AI trực tiếp viết mã HTML tự chứa:
1. Dựng Prompt trực tiếp từ master_handdrawn_animation_prompt.md kết hợp nội dung bài giảng
   (Title, Aspect Ratio, Duration, Sentences & Timestamps, User Requirements/Feedback).
2. Gọi AI (Gemini / OpenAI / Ollama qua call_llm_api) sinh mã HTML tự chứa 100% (SVG + CSS + JS thuần).
3. Kiểm tra cú pháp tối thiểu (Sanity check nhẹ, tức thì, không phụ thuộc Playwright/Harness cồng kềnh).
4. Ghi trực tiếp ra file HTML cảnh độc lập và metadata.
"""

import json
from pathlib import Path
import re
from typing import Any, Callable, Dict, List, Optional, Tuple

from .common import emit_log
from .html_calibrator import evaluate_and_calibrate_scene_html
from .knowledge_extractor import call_llm_api, get_last_llm_error


# Tương thích ngược cho các mẫu cũ nếu có tham chiếu ngoài
FEW_SHOT_TEMPLATE_16_9 = ""
FEW_SHOT_TEMPLATE_GRID_16_9 = ""
FEW_SHOT_TEMPLATE_COMPARE_16_9 = ""
FEW_SHOT_TEMPLATE_HERO_16_9 = ""
FEW_SHOT_TEMPLATE_RADIAL_16_9 = ""


def get_core_design_constraints(width: int = 1920, height: int = 1080) -> str:
    """Tạo bộ ràng buộc kỹ thuật & sư phạm thống nhất (Backward compatible)."""
    sub_limit = height - (250 if height > width else 140)
    return f"""GIAO KÈO KỸ THUẬT & QUY TẮC BẮT BUỘC (STRICT CONTRACT & CONSTRAINTS):
1. 100% ĐỒ HỌA PHẢI NẰM TRONG SVG VẼ TAY THUẦN (NATIVE SVG):
   - Thẻ gốc: `<svg id="svg" viewBox="0 0 {width} {height}">`.
   - TUYỆT ĐỐI CẤM tạo thẻ <div> HTML, flexbox hay CSS box-shadow bên ngoài SVG. Mọi phần tử đều vẽ bằng SVG.
2. ĐA DẠNG HÓA BỐ CỤC SƯ PHẠM THEO NGỮ NGHĨA (MANDATORY AUTO-LAYOUT & CONTEXTUAL ARCHETYPES):
   - Phân tích ngữ nghĩa để chọn bố cục trực quan phù hợp: So sánh (layoutCompare), Cây tư duy (layoutRadial), Điểm nhấn (layoutHeroFocus), Xếp tầng (layoutStack), Luồng tiến trình (layoutRow / layoutGrid).
3. THAM SỐ SỐ HỌC HỢP LỆ (NO NAN / NO NEGATIVE NUMBERS):
   - Mọi kích thước width, height, x, y phải là số dương hữu hạn hợp lệ.
4. CHỐNG CHỒNG CHÉO HÌNH HỌC & QUY TẮC ĐƯỜNG NỐI (STRICT SHAPE ANTI-OVERLAP & SEAMLESS CONNECTORS):
   - Không giới hạn chiều dài đường line: đường nối/mũi tên có thể dài tùy ý theo bố cục, không bị gò bó khoảng cách.
   - Nối dính từ A đến B: nếu dùng line thì bắt buộc phải nối dính liền mạch từ mép ngoài đối tượng A đến mép ngoài đối tượng B, không để đường nối lơ lửng.
   - Tuyệt đối cấm chạy xuyên: đường line không được chạy xuyên qua bất kỳ hình khối đối tượng hay đoạn text nào trên đường đi; không đâm thủng vào giữa bụng hộp.
5. TỐI GIẢN VĂN BẢN - ƯU TIÊN BIỂU ĐỒ & ĐỐI TƯỢNG MÔ PHỎNG (CONCEPT KEYWORDS & VISUAL SIMULATION OVER TEXT):
   - VÌ ĐÃ CÓ GIỌNG ĐỌC VÀ PHỤ ĐỀ GIẢI THÍCH CHI TIẾT: Tuyệt đối CẤM viết các đoạn văn dài, lời khuyên, hay danh sách gạch đầu dòng giải thích tính năng trong các thẻ.
   - Mỗi thẻ/khối chỉ hiển thị TỐI GIẢN: Tên khối (1-3 từ, ví dụ: Load Balancer, Primary DB) + Trạng thái/chỉ số (1-2 từ hoặc icon, ví dụ: ● Active, ✕ Error).
   - DÙNG ĐỐI TƯỢNG & BIỂU ĐỒ ĐỂ MÔ PHỎNG: Dùng các icon phác họa (máy chủ, database, người dùng), mũi tên chỉ hướng, luồng hạt chạy (flow dots), nét đứt báo lỗi để người xem THẤY được cơ chế vận hành, thay vì bắt người xem phải đọc chữ.
6. VÙNG CẤM PHỤ ĐỀ ĐÁY (NO-DRAW SUBTITLE ZONE):
   - Toàn bộ đồ họa phải kết thúc trước y = {sub_limit}px để chừa chỗ cho phụ đề video.
7. PHONG CÁCH VẼ TAY TRÊN GIẤY KEM & PHÔNG CHỮ SƯ PHẠM:
   - Giữ nguyên màu giấy kem #f4efe3, viền mực #26323d, đỏ gạch #b5533c, font Patrick Hand (PatrickHand, cấm cursive).
8. GIAO KÈO HOẠT ẢNH & ĐIỀU KHIỂN KHUNG HÌNH (ANIMATION CONTRACT):
   - Có hàm window.__load(scene) và window.__renderAt(t, stepStarts) điều khiển chuyển động theo mốc giây.
   - TUYỆT ĐỐI CẤM setTimeout và setInterval.
9. QUY TẮC ZERO-TRUNCATION:
   - TUYỆT ĐỐI KHÔNG sử dụng dấu ba chấm "..." hoặc "…" trong văn bản hiển thị."""


PROMPTS_DIR = (Path(__file__).parent / "prompts").resolve()
MASTER_PROMPT_PATH = PROMPTS_DIR / "master_handdrawn_animation_prompt.md"


def load_master_prompt_template() -> str:
    """Nạp nội dung Master Prompt chuẩn Sub-Video."""
    if MASTER_PROMPT_PATH.exists():
        try:
            return MASTER_PROMPT_PATH.read_text(encoding="utf-8")
        except Exception:
            pass
    p1 = PROMPTS_DIR / "paper-1.md"
    if p1.exists():
        try:
            return p1.read_text(encoding="utf-8")
        except Exception:
            pass
    return ""


def build_scene_author_system_prompt() -> str:
    """Tạo System Prompt tĩnh đọc trực tiếp từ Master Prompt (Single Source of Truth) tối ưu cho Prompt Caching."""
    master_template = load_master_prompt_template()
    if master_template:
        return master_template.strip()

    return """Bạn là Kỹ Sư Đồ Họa Bài Giảng Tương Tác Sư Phạm.
YÊU CẦU TRẢ VỀ TỐI THƯỢNG (STRICT OUTPUT CONTRACT):
- Phân tích nội dung đầu vào được cung cấp ở lượt hỏi của người dùng và tạo ra DUY NHẤT một file index.html tự chứa 100% (thuần native HTML, CSS, SVG và JavaScript).
- Nền giấy kem #f4efe3, viền mực #26323d, điểm nhấn đỏ #b5533c, font Patrick Hand (PatrickHand, cấm cursive).
- Toàn bộ đồ họa phải kết thúc trước vạch cấm phụ đề đáy (No-draw subtitle zone) để chừa chỗ cho phụ đề video hiển thị.
- Bắt buộc có hàm window.__load(scene) và window.__renderAt(t, stepStarts) điều khiển chuyển động khớp từng mốc câu thoại. stepStarts là mảng số thực [t1, t2...] theo thứ tự các Ý; hãy truy xuất dạng stepStarts[0], stepStarts[1]... Bắt buộc hủy cancelAnimationFrame ngay đầu hàm window.__renderAt để dừng vòng lặp tự chạy. Cấm setTimeout và setInterval.
- Tuân thủ ZERO-TRUNCATION (tuyệt đối không dùng dấu ba chấm '...' trong các nhãn hiển thị).
- Trả về DUY NHẤT một khối mã HTML hoàn chỉnh nằm trong thẻ ```html ... ```. Không kèm lời giải thích rườm rà."""



def build_scene_author_user_prompt(
    sentences: List[str],
    step_starts: List[float],
    duration: float,
    aspect_ratio: str = "16:9",
    title: str = "Bài giảng",
    user_feedback: Optional[str] = None,
    subtitle_region: Optional[List[float]] = None,
    concept: Optional[str] = None,
    diagram_type: Optional[str] = None,
) -> str:
    """Dựng User Prompt động chứa thông tin riêng biệt của phân cảnh hiện tại."""
    is_portrait = aspect_ratio == "9:16"
    width = 1080 if is_portrait else 1920
    height = 1920 if is_portrait else 1080
    sub_limit = height - (250 if is_portrait else 140)
    if subtitle_region and len(subtitle_region) == 4:
        try:
            top = float(subtitle_region[0])
            if top >= 0.5:
                custom_limit = int(top * height) - 20
                sub_limit = min(sub_limit, custom_limit)
        except (ValueError, TypeError):
            pass

    steps_formatted = []
    for idx, s in enumerate(sentences):
        st = step_starts[idx] if idx < len(step_starts) else idx * 2.0
        steps_formatted.append(f'  - Ý {idx + 1} (bắt đầu tại giây t={st:.2f}s): "{s}"')
    steps_txt = "\n".join(steps_formatted)

    concept_section = ""
    if concept and concept.strip():
        concept_section = f"VISUAL CONCEPT DIRECTION: {concept.strip()} (Archetype: {diagram_type or 'diagram'})\n"

    feedback_section = ""
    if user_feedback and user_feedback.strip():
        feedback_section = f"""
YÊU CẦU ĐẶC BIỆT / CHỈNH SỬA TỪ NGƯỜI DÙNG:
{user_feedback.strip()}
(LƯU Ý QUAN TRỌNG: Đây là chỉ đạo trực tiếp từ người dùng. Bạn PHẢI ưu tiên đáp ứng chính xác yêu cầu này trong bố cục và nội dung vẽ tay!)
"""

    return f"""TITLE: {title}
ASPECT RATIO: {aspect_ratio} ({'9:16 Portrait' if is_portrait else '16:9 Landscape'} - {width}x{height} px)
SCENE DURATION: {duration:.2f}s
NO-DRAW SUBTITLE ZONE: y <= {sub_limit}px
{concept_section}SENTENCES & TIMESTAMPS:
{steps_txt}
{feedback_section.strip()}""".strip()


def build_scene_refine_user_prompt(
    existing_html: str,
    user_feedback: str,
    sentences: List[str],
    step_starts: List[float],
    duration: float,
    aspect_ratio: str = "16:9",
    title: str = "Bài giảng",
    subtitle_region: Optional[List[float]] = None,
    concept: Optional[str] = None,
    diagram_type: Optional[str] = None,
) -> str:
    """Dựng User Prompt tinh chỉnh phẫu thuật từ mã HTML đã sinh hiện có với phân cấp thông tin đảo chiều (Inverted Hierarchy)."""
    is_portrait = aspect_ratio == "9:16"
    width = 1080 if is_portrait else 1920
    height = 1920 if is_portrait else 1080
    sub_limit = height - (250 if is_portrait else 140)
    if subtitle_region and len(subtitle_region) == 4:
        try:
            top = float(subtitle_region[0])
            if top >= 0.5:
                custom_limit = int(top * height) - 20
                sub_limit = min(sub_limit, custom_limit)
        except (ValueError, TypeError):
            pass

    steps_formatted = []
    for idx, s in enumerate(sentences):
        st = step_starts[idx] if idx < len(step_starts) else idx * 2.0
        steps_formatted.append(f'  - Ý {idx + 1} (bắt đầu tại giây t={st:.2f}s): "{s}"')
    steps_txt = "\n".join(steps_formatted)

    concept_line = f"VISUAL CONCEPT DIRECTION: {concept.strip()} (Archetype: {diagram_type or 'diagram'})\n" if concept and concept.strip() else ""
    feedback_clean = (user_feedback or "").strip()

    return f"""BỐI CẢNH PHÂN CẢNH BÀI GIẢNG:
TITLE: {title}
ASPECT RATIO: {aspect_ratio} ({'9:16 Portrait' if is_portrait else '16:9 Landscape'} - {width}x{height} px)
SCENE DURATION: {duration:.2f}s
NO-DRAW SUBTITLE ZONE: y <= {sub_limit}px
{concept_line}SENTENCES & TIMESTAMPS:
{steps_txt}

MÃ NGUỒN HTML HIỆN TẠI ĐANG SỬ DỤNG CHO PHÂN CẢNH (EXISTING HTML CODE):
```html
{existing_html.strip()}
```

CHỈ ĐẠO TINH CHỈNH PHẪU THUẬT (SURGICAL REFINEMENT DIRECTIVE):
YÊU CẦU ĐẶC BIỆT / CHỈNH SỬA TỪ NGƯỜI DÙNG:
"{feedback_clean}"

QUY TẮC BẮT BUỘC:
1. Bạn BẮT BUỘC phải tạo ra sự thay đổi rõ rệt và chính xác theo 'YÊU CẦU ĐẶC BIỆT / CHỈNH SỬA TỪ NGƯỜI DÙNG' ở trên. TUYỆT ĐỐI CẤM chép lại y nguyên mã cũ mà không thay đổi gì!
2. Bảo toàn bộ khung SVG: giữ nguyên #stage, viewBox, font PatrickHand và hàm window.__renderAt(t, stepStarts).
3. ĐỊNH DẠNG ĐẦU RA BẮT BUỘC (2 GIAI ĐOẠN):
   - Trước tiên, hãy viết ngắn gọn 2-3 gạch đầu dòng KẾ HOẠCH TINH CHỈNH (ACTION PLAN):
     * Kế hoạch 1: [chi tiết sửa đổi]
     * Kế hoạch 2: [chi tiết sửa đổi]
   - Sau đó, xuất DUY NHẤT một khối mã HTML hoàn chỉnh sau khi đã áp dụng kế hoạch trên nằm trong thẻ ```html ... ```."""


def extract_refinement_plan(raw_response: str) -> str:
    """Trích xuất kế hoạch tinh chỉnh (Refinement Plan) trước khối HTML."""
    if not raw_response or not raw_response.strip():
        return ""
    idx = raw_response.lower().find("```html")
    if idx == -1:
        idx = raw_response.lower().find("```")
    if idx > 0:
        pre_code = raw_response[:idx].strip()
        lines = [line.strip() for line in pre_code.splitlines() if line.strip()]
        if lines:
            return "\n".join(lines[:6])
    return ""


def build_scene_author_prompt(
    sentences: List[str],
    step_starts: List[float],
    duration: float,
    aspect_ratio: str = "16:9",
    title: str = "Bài giảng",
    suggested_template: Optional[str] = None,
    user_feedback: Optional[str] = None,
    subtitle_region: Optional[List[float]] = None,
    refine_existing_html: Optional[str] = None,
    concept: Optional[str] = None,
    diagram_type: Optional[str] = None,
) -> str:
    """Dựng prompt hoàn chỉnh (ghép System Prompt và User Prompt) tương thích ngược 100%."""
    sys_prompt = build_scene_author_system_prompt()
    if refine_existing_html and refine_existing_html.strip():
        user_prompt = build_scene_refine_user_prompt(
            existing_html=refine_existing_html,
            user_feedback=user_feedback or "",
            sentences=sentences,
            step_starts=step_starts,
            duration=duration,
            aspect_ratio=aspect_ratio,
            title=title,
            subtitle_region=subtitle_region,
            concept=concept,
            diagram_type=diagram_type,
        )
    else:
        user_prompt = build_scene_author_user_prompt(
            sentences=sentences,
            step_starts=step_starts,
            duration=duration,
            aspect_ratio=aspect_ratio,
            title=title,
            user_feedback=user_feedback,
            subtitle_region=subtitle_region,
            concept=concept,
            diagram_type=diagram_type,
        )
    return f"{sys_prompt}\n\nTHÔNG TIN ĐẦU VÀO CHO CẢNH MINH HỌA NÀY:\n{user_prompt}"


def extract_html_code(raw_response: str) -> str:
    """Trích xuất khối mã HTML từ phản hồi của LLM."""
    if not raw_response or not raw_response.strip():
        return ""

    # 1. Tìm trong khối code ```html ... ```
    match = re.search(r"```(?:html)?\s*([\s\S]*?)\s*```", raw_response, re.IGNORECASE)
    if match:
        extracted = match.group(1).strip()
        if "<html" in extracted.lower() or "<!doctype" in extracted.lower() or "<svg" in extracted.lower():
            return extracted

    # 2. Tìm khối từ <!DOCTYPE html> hoặc <html> đến </html>
    match_html = re.search(r"(<!DOCTYPE html[\s\S]*?</html>|<html[\s\S]*?</html>)", raw_response, re.IGNORECASE)
    if match_html:
        return match_html.group(1).strip()

    return raw_response.strip()


ASSETS_DIR = (Path(__file__).parent / "assets").resolve()
FONTS_DIR = (ASSETS_DIR / "fonts").resolve()
PATRICK_HAND_FONT_PATH = FONTS_DIR / "PatrickHand.ttf"


def generate_minimal_native_svg_fallback(
    scene_or_title: Any = None,
    sentences: Optional[List[str]] = None,
    duration: float = 5.0,
    step_starts: Optional[List[float]] = None,
    aspect_ratio: str = "16:9",
    width: Optional[int] = None,
    height: Optional[int] = None,
    title: Optional[str] = None,
    **kwargs: Any,
) -> str:
    """Tạo mã HTML/SVG Native tự chứa tối thiểu làm fallback dự phòng an toàn tuyệt đối khi AI gặp sự cố."""
    target = scene_or_title if scene_or_title is not None else kwargs.get("scene")
    if isinstance(target, dict):
        scene = target
        title = str(title or scene.get("title") or "Minh Họa Bài Giảng")
        if sentences is None:
            raw_steps = scene.get("steps") if isinstance(scene.get("steps"), list) else []
            sentences = [
                str(st.get("label") or st.get("keyword") or "")
                for st in raw_steps
                if isinstance(st, dict)
            ]
            if not sentences:
                sentences = [title]
        duration = float(scene.get("duration") or duration or 5.0)
        if step_starts is None:
            step_starts = scene.get("step_starts") or [0.0]
    else:
        title = str(title or target or "Minh Họa Bài Giảng")
        if sentences is None:
            sentences = [title]
        if step_starts is None:
            step_starts = [0.0]

    if width is not None and height is not None:
        is_portrait = height > width
    else:
        is_portrait = aspect_ratio == "9:16"
        width = 1080 if is_portrait else 1920
        height = 1920 if is_portrait else 1080

    step_starts_json = json.dumps(step_starts if step_starts else [0.0])

    nodes_svg = []
    card_w = 760 if is_portrait else 420
    card_h = 130
    count = max(1, len(sentences))

    for i, s in enumerate(sentences[:4]):
        clean_label = s.strip()
        if len(clean_label) > 30:
            clean_label = clean_label[:28] + "…"
        if is_portrait:
            cx = width // 2
            cy = 380 + i * 220
        else:
            spacing = width // (count + 1)
            cx = spacing * (i + 1)
            cy = 480

        nodes_svg.append(f"""
        <g id="fallback-node-{i}" class="sync-entity" transform="translate({cx}, {cy})">
          <rect x="-{card_w // 2}" y="-{card_h // 2}" width="{card_w}" height="{card_h}" rx="14"
                fill="var(--card-bg)" stroke="var(--ink)" stroke-width="3.5" class="sketch-stroke"/>
          <text x="0" y="8" class="handwritten" text-anchor="middle" font-size="28" font-weight="bold">{clean_label}</text>
        </g>
        """)

    nodes_str = "\n".join(nodes_svg)

    return f"""<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <title>{title}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Patrick+Hand&display=swap" rel="stylesheet">
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Patrick+Hand&display=swap');
    @font-face {{
      font-family: 'PatrickHand';
      src: local('Patrick Hand'), local('PatrickHand'),
           url('https://fonts.gstatic.com/s/patrickhand/v22/LDI1apSQOAYtSuYWp8ZhfImpWrVk.woff2') format('woff2'),
           url('assets/fonts/PatrickHand.ttf') format('truetype'),
           url('fonts/PatrickHand.ttf') format('truetype');
    }}
    :root {{
      --paper: #f6f3eb; /* legacy: #f4efe3 */
      --card-bg: #ffffff;
      --ink: #0f172a; /* legacy: #26323d */
      --ink-muted: #334155; /* legacy: #8a8372 */
      --accent-red: #991b1b; /* legacy: #b5533c */
      --accent: #991b1b;
      --accent-green: #14532d;
      --accent-blue: #1e3a8a;
    }}
    * {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body, html {{
      width: 100%; height: 100%; overflow: hidden;
      background-color: var(--paper);
      font-family: 'Patrick Hand', 'PatrickHand', cursive, sans-serif;
    }}
    #stage {{
      position: relative; width: 100vw; height: 100vh;
      display: flex; align-items: center; justify-content: center;
    }}
    #grain {{
      position: absolute; inset: 0; pointer-events: none;
      background-image: radial-gradient(rgba(60, 50, 30, 0.08) 1px, transparent 1.2px);
      background-size: 7px 7px; opacity: 0.45; z-index: 1;
    }}
    .notebook-lines {{
      position: absolute; inset: 0; pointer-events: none;
      background-image: linear-gradient(rgba(38, 50, 61, 0.04) 1px, transparent 1px);
      background-size: 100% 36px; z-index: 2;
    }}
    svg {{
      position: relative; z-index: 3;
      width: 100%; height: 100%;
      max-width: {width}px; max-height: {height}px;
    }}
    .handwritten {{
      font-family: 'Patrick Hand', 'PatrickHand', cursive, sans-serif;
      user-select: none;
    }}
    svg text {{
      fill: var(--ink);
    }}
    .text-white {{ fill: #ffffff !important; color: #ffffff !important; }}
    .text-ink {{ fill: var(--ink) !important; color: var(--ink) !important; }}
    .text-muted {{ fill: var(--ink-muted) !important; color: var(--ink-muted) !important; }}
    .text-red {{ fill: var(--accent-red) !important; color: var(--accent-red) !important; }}
    .text-green {{ fill: var(--accent-green) !important; color: var(--accent-green) !important; }}
    .text-blue {{ fill: var(--accent-blue) !important; color: var(--accent-blue) !important; }}
    .sketch-stroke {{
      stroke-linecap: round; stroke-linejoin: round;
    }}
    .sync-entity {{
      visibility: hidden; opacity: 0;
    }}
  </style>
</head>
<body>
  <div id="stage">
    <div id="grain"></div>
    <div class="notebook-lines"></div>

    <svg id="svg" viewBox="0 0 {width} {height}" preserveAspectRatio="xMidYMid meet">
      <!-- HEADER -->
      <g id="header-group" transform="translate({width // 2}, 90)">
        <text id="title-text" class="handwritten sync-entity" text-anchor="middle" font-size="44" font-weight="bold">{title}</text>
        <path id="title-underline" class="sketch-stroke sync-entity" d="M -260 22 Q 0 30 260 20" fill="none" stroke="var(--accent)" stroke-width="3.5"/>
      </g>

      <g id="main-canvas">
        {nodes_str}
      </g>
    </svg>
  </div>

  <script>
    const SCENE_DURATION = {duration:.2f};
    const STEP_STARTS = {step_starts_json};
    let autoPlayLoopId = null;
    let isExternalVirt = false;

    function easeOutCubic(x) {{
      return 1 - Math.pow(1 - Math.max(0, Math.min(1, x)), 3);
    }}

    function getStepProgress(t, startT, dur = 0.7) {{
      if (t < startT) return 0;
      return easeOutCubic((t - startT) / dur);
    }}

    function setEntityOpacity(el, p) {{
      if (!el) return;
      if (p <= 0) {{
        el.style.visibility = 'hidden';
        el.style.opacity = '0';
      }} else {{
        el.style.visibility = 'visible';
        el.style.opacity = String(p);
      }}
    }}

    function renderScene(t, stepStarts) {{
      const starts = Array.isArray(stepStarts) && stepStarts.length ? stepStarts : STEP_STARTS;
      const pTitle = getStepProgress(t, starts[0] ?? 0.0, 0.5);
      setEntityOpacity(document.getElementById("title-text"), pTitle);
      setEntityOpacity(document.getElementById("title-underline"), pTitle);

      for (let i = 0; i < {len(sentences[:4])}; i++) {{
        const node = document.getElementById("fallback-node-" + i);
        const st = starts[i] ?? (i * 2.0);
        const p = getStepProgress(t, st, 0.7);
        setEntityOpacity(node, p);
      }}
    }}

    window.__load = function(scene) {{
      renderScene(0, STEP_STARTS);
    }};

    window.__renderAt = function(t, stepStarts) {{
      if (autoPlayLoopId) {{
        cancelAnimationFrame(autoPlayLoopId);
        autoPlayLoopId = null;
      }}
      isExternalVirt = true;
      renderScene(t, stepStarts);
    }};

    let startTime = null;
    function autoLoop(now) {{
      if (isExternalVirt) return;
      if (!startTime) startTime = now;
      const elapsed = ((now - startTime) / 1000) % (SCENE_DURATION + 1.5);
      const t = Math.min(elapsed, SCENE_DURATION);
      renderScene(t, STEP_STARTS);
      autoPlayLoopId = requestAnimationFrame(autoLoop);
    }}
    autoPlayLoopId = requestAnimationFrame(autoLoop);
  </script>
</body>
</html>"""


def ensure_templates_base_tag(html_str: str) -> str:
    """Tương thích ngược: Đảm bảo font assets được nạp đúng."""
    return html_str


def ensure_templates_dependencies(html_str: str) -> str:
    """Đảm bảo font Patrick Hand được nạp trong HTML (hỗ trợ cả Google Fonts CDN lẫn file cục bộ tương đối)."""
    if not html_str:
        return html_str

    if "fonts.googleapis.com" not in html_str:
        google_fonts_link = """  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Patrick+Hand&display=swap" rel="stylesheet">"""
        if "</head>" in html_str:
            html_str = html_str.replace("</head>", f"{google_fonts_link}\n</head>", 1)
        elif "<head>" in html_str:
            html_str = html_str.replace("<head>", f"<head>\n{google_fonts_link}", 1)

    if "PatrickHand" not in html_str and "@font-face" not in html_str:
        font_style = """<style>
@import url('https://fonts.googleapis.com/css2?family=Patrick+Hand&display=swap');
@font-face {
  font-family: 'PatrickHand';
  src: local('Patrick Hand'), local('PatrickHand'),
       url('https://fonts.gstatic.com/s/patrickhand/v22/LDI1apSQOAYtSuYWp8ZhfImpWrVk.woff2') format('woff2'),
       url('assets/fonts/PatrickHand.ttf') format('truetype'),
       url('fonts/PatrickHand.ttf') format('truetype');
}
</style>"""
        if "</head>" in html_str:
            html_str = html_str.replace("</head>", f"  {font_style}\n</head>", 1)
        elif "<head>" in html_str:
            html_str = html_str.replace("<head>", f"<head>\n{font_style}", 1)
    return html_str


def validate_html_sanity(html_str: str, aspect_ratio: str = "16:9") -> List[str]:
    """Kiểm tra cú pháp tối thiểu (siêu nhẹ, tức thì, không cần Playwright browser)."""
    errors = []
    if not html_str or not html_str.strip():
        return ["Mã HTML trống hoặc không tồn tại."]
    low = html_str.lower()
    if "<html" not in low and "<svg" not in low:
        errors.append("Thiếu thẻ gốc <html> hoặc <svg>.")
    if "window.__renderat" not in low and "__renderat" not in low:
        errors.append("Thiếu hàm window.__renderAt(t, stepStarts) để điều khiển tua chuyển động.")
    if "settimeout(" in low or "setinterval(" in low:
        errors.append("Chứa hàm hẹn giờ cấm (setTimeout / setInterval). Hãy dùng window.__renderAt.")

    # Kiểm tra viewBox bắt buộc chuẩn 1080p
    expected_vb = "1080 1920" if aspect_ratio == "9:16" else "1920 1080"
    vb_match = re.search(r'viewbox=["\']([^"\']+)["\']', html_str, re.IGNORECASE)
    if vb_match:
        vb_val = vb_match.group(1).strip()
        if expected_vb not in vb_val:
            errors.append(f"ViewBox sai kích thước: '{vb_val}'. Bắt buộc 'viewBox=\"0 0 {expected_vb}\"'. Tuyệt đối cấm thu nhỏ thành 960x540 hay 920x420.")
    else:
        errors.append(f"Thiếu thuộc tính viewBox trên thẻ SVG. Bắt buộc: viewBox=\"0 0 {expected_vb}\".")

    # Kiểm tra cấm bọc trong container / .stage có width cố định
    if re.search(r'\.(?:container|canvas-container|stage|card)\s*\{[^}]*width\s*:\s*(?:9\d\d|8\d\d|[1-7]\d\d)px', html_str, re.IGNORECASE) or '<div class="container">' in html_str:
        errors.append("Phát hiện thẻ bọc thu nhỏ (như .stage / .container { width: 960px; height: 540px; }). Bắt buộc #stage chiếm 100vw x 100vh và thẻ SVG id='svg' chiếm toàn bộ #stage.")

    # Kiểm tra cấm player controls
    if re.search(r'<(?:input|button)\b|\b(?:scrubber|footer-bar)\b', html_str, re.IGNORECASE):
        errors.append("Phát hiện thẻ <input> hoặc player scrubber cấm. Video được render tự động qua Playwright.")

    # Kiểm tra tiêu đề phân cảnh ở đỉnh khung hình
    has_header = bool(
        re.search(r'<g[^>]*id=["\'](?:header-group|header|title-group)["\']', html_str, re.IGNORECASE)
        or re.search(r'<text[^>]*(?:font-size[:=]["\']?(?:3[6-9]|[4-6][0-9])|y=["\'](?:[0-9]|[1-9][0-9]|1[0-5][0-9])["\'])', html_str, re.IGNORECASE)
    )
    if not has_header:
        errors.append("Thiếu tiêu đề phân cảnh ở đỉnh khung hình. Bắt buộc có <g id='header-group' transform='translate(960, 80)'> chứa <text> tiêu đề chữ in hoa cỡ 40-44px.")

    return errors


def author_scene_with_retry(
    batch_id: str,
    sentences: List[str],
    step_starts: List[float],
    duration: float,
    aspect_ratio: str,
    out_html_path: Path,
    api_key: Optional[str] = None,
    model: Optional[str] = None,
    base_url: Optional[str] = None,
    llm_caller: Optional[Callable[..., str]] = None,
    max_retries: int = 2,
    fallback_template: str = "bullet_list",
    user_feedback: Optional[str] = None,
    subtitle_region: Optional[List[float]] = None,
    refine_existing_html: Optional[str] = None,
    title: Optional[str] = None,
    concept: Optional[str] = None,
    diagram_type: Optional[str] = None,
) -> Tuple[bool, Dict[str, Any], Dict[str, Any]]:
    """
    Sinh cảnh HTML tự chứa 100% qua AI (dựa trên Master Prompt) tinh gọn trực tiếp:
    - Dựng prompt trực tiếp từ master_handdrawn_animation_prompt.md + nội dung phân cảnh.
    - Gọi AI (Gemini / OpenAI / Ollama) lấy mã HTML tự chứa thuần SVG/CSS/JS.
    - Kiểm tra tính hợp lệ cơ bản siêu nhẹ (không browser, không linter chậm).
    - Lưu trực tiếp mã HTML tự chứa thuần SVG ra đĩa mà không chèn cưỡng ép các thư viện ngoài.
    - Nếu AI không trả về sau max_retries: Fallback an toàn về template kinh điển.
    
    Trả về: (thành_công_authored: bool, scene_dict: Dict, meta_dict: Dict)
    """
    out_html_path = Path(out_html_path).resolve()
    out_html_path.parent.mkdir(parents=True, exist_ok=True)
    meta_path = out_html_path.parent / f"{out_html_path.stem}.meta.json"

    width = 1080 if aspect_ratio == "9:16" else 1920
    height = 1920 if aspect_ratio == "9:16" else 1080

    scene_title = (title or "").strip() or (sentences[0] if sentences else "Bài giảng")
    scene_data = {
        "mode": "authored",
        "title": scene_title,
        "visual_concept": concept or "",
        "diagram_type": diagram_type or "",
        "steps": [{"label": s, "icon": "bulb", "role": "VISUAL"} for s in sentences],
    }

    effective_temp = 0.45 if (refine_existing_html and refine_existing_html.strip()) else 0.2

    # Hàm gọi LLM thống nhất (tiêm mock được khi test)
    def _call(p: str) -> str:
        if llm_caller:
            try:
                return llm_caller(p)
            except TypeError:
                return llm_caller(p, system_prompt=None)
        return call_llm_api(
            prompt=p,
            api_key=api_key,
            model_name=model or "gemini-3.6-flash",
            base_url=base_url,
            response_mime_type="text/plain",
            temperature=effective_temp,
        ) or ""

    # 1. Dựng Prompt nguyên khối (kết hợp Master Blueprint Prompt và thông tin phân cảnh)
    full_prompt = build_scene_author_prompt(
        sentences=sentences,
        step_starts=step_starts,
        duration=duration,
        aspect_ratio=aspect_ratio,
        title=scene_title,
        user_feedback=user_feedback,
        subtitle_region=subtitle_region,
        refine_existing_html=refine_existing_html,
        concept=concept,
        diagram_type=diagram_type,
    )

    emit_log("info", f"[SceneAuthor] Gửi Master Prompt lên AI tạo cảnh minh họa SVG cho {batch_id} ({aspect_ratio})...")
    raw_resp = _call(full_prompt)
    if refine_existing_html and refine_existing_html.strip():
        plan_text = extract_refinement_plan(raw_resp)
        if plan_text:
            emit_log("info", f"[SceneAuthor] Kế hoạch tinh chỉnh ({batch_id}):\n{plan_text}")
    html_code = extract_html_code(raw_resp)

    current_round = 0
    last_errors: List[str] = []

    while current_round <= max_retries:
        if not html_code:
            api_err = get_last_llm_error()
            if api_err:
                last_errors = [f"Lỗi kết nối AI ({api_err})"]
                emit_log("error", f"[SceneAuthor] Không thể sinh HTML cho {batch_id} do lỗi API ({model or 'default'}): {api_err}")
                break
        last_errors = validate_html_sanity(html_code, aspect_ratio=aspect_ratio)
        if not last_errors and refine_existing_html and refine_existing_html.strip():
            # Chốt chặn chống trùng lặp (Identical Code Guard)
            norm_new = re.sub(r"\s+", " ", html_code).strip()
            norm_old = re.sub(r"\s+", " ", refine_existing_html).strip()
            if norm_new == norm_old:
                last_errors = [f"Mã HTML trả về trùng lặp 100% với mã cũ (chưa áp dụng thay đổi theo yêu cầu: '{user_feedback}')"]

        if not last_errors:
            # Tự động nắn chỉnh vi mô (Auto-Calibrate) và chấm điểm chất lượng (Quality Gate)
            calibrated_html, quality_report = evaluate_and_calibrate_scene_html(
                html_str=html_code,
                duration=duration,
                step_starts=step_starts,
                aspect_ratio=aspect_ratio,
            )
            passed = bool(quality_report.get("passed", True))
            if passed or current_round >= max_retries:
                out_html_path.write_text(calibrated_html, encoding="utf-8")
                q_score = quality_report.get("quality_score", 100)
                calibs = quality_report.get("calibrations", [])
                calibs_msg = f" (Đã tự cân chỉnh: {', '.join(calibs)})" if calibs else ""
                emit_log("info", f"[SceneAuthor] Cảnh {batch_id} đạt chất lượng {q_score}đ{calibs_msg} tại vòng {current_round}!")
                scene_data["html_path"] = str(out_html_path)
                scene_data["quality_score"] = q_score
                meta = {
                    "mode": "authored",
                    "batch_id": batch_id,
                    "html_path": str(out_html_path),
                    "aspect_ratio": aspect_ratio,
                    "model": model or "default",
                    "rounds_needed": current_round,
                    "passed": passed,
                    "quality_score": q_score,
                    "calibrations": calibs,
                    "eval_details": quality_report.get("eval_details", {}),
                    "inferred": False,
                    "warnings": [],
                }
                meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
                return True, scene_data, meta

            # Nếu chưa đạt Quality Gate và còn lượt retry
            q_errs = []
            for k, v in quality_report.get("eval_details", {}).items():
                if isinstance(v, dict) and not v.get("passed", True) and v.get("warning"):
                    q_errs.append(v["warning"])
            last_errors = q_errs or ["Chưa đạt tiêu chuẩn chất lượng (Quality Gate)"]

        if current_round >= max_retries:
            break

        current_round += 1
        emit_log("warn", f"[SceneAuthor] Mã HTML cảnh {batch_id} cần điều chỉnh (vòng {current_round}): {'; '.join(last_errors)}")
        err_list_str = "\n".join(f"- {err}" for err in last_errors)
        expected_vb = "1080 1920" if aspect_ratio == "9:16" else "1920 1080"
        if refine_existing_html and refine_existing_html.strip():
            reflection_prompt = f"""Mã HTML bạn vừa tinh chỉnh cho cảnh '{scene_title}' ({aspect_ratio}) chưa đạt các tiêu chuẩn bắt buộc sau:
{err_list_str}

LƯU Ý ĐẶC BIỆT KHI SỬA LỖI (REFINEMENT MANDATE):
- Đây là phiên tinh chỉnh theo yêu cầu của người dùng:
  "{user_feedback.strip() if user_feedback else ''}"
- Bạn PHẢI vừa khắc phục các lỗi kỹ thuật ở trên, VỪA BẮT BUỘC tạo ra biến đổi chính xác theo yêu cầu của người dùng (TUYỆT ĐỐI CẤM chép lại y nguyên mã cũ)!
- Hãy viết ngắn gọn 2-3 gạch đầu dòng KẾ HOẠCH TINH CHỈNH trước, sau đó trả về DUY NHẤT khối mã HTML hoàn chỉnh trong ```html ... ```."""
        else:
            reflection_prompt = f"""Mã HTML bạn vừa thiết kế cho cảnh '{title}' ({aspect_ratio}) chưa đạt các tiêu chí an toàn bắt buộc sau:
{err_list_str}

HÃY SỬA LẠI VÀ TRẢ VỀ DUY NHẤT KHỐI MÃ HTML HOÀN CHỈNH TRONG ```html ... ```:
- Thẻ gốc: <div id="stage"><svg id="svg" viewBox="0 0 {expected_vb}"> chiếm trọn toàn màn hình.
- CHUẨN VÀNG BATCH 4 BẢN LỚN:
  + Bắt buộc phông chữ: font-family: 'Patrick Hand', cursive, sans-serif; (tuyệt đối không dùng Segoe UI/Arial).
  + Nền giấy kem #f4efe3 kèm lưới ô vuông <pattern id="handGrid">.
  + Cụm tiêu đề đỉnh: Tiêu đề chính font-size 58px bold tại y=0, nét gạch chân đỏ ôm sát y=18px (M -260 18 Q 0 24 260 18), text phụ dẫn nhập font-size 22px-25px (CHUẨN 24px) đặt tại y=65px. TUYỆT ĐỐI CẤM gạch chân đè lên chữ text phụ!
  + Hộp thẻ to bản: Tự do hóa số lượng hộp theo sơ đồ (không giới hạn số hộp). Linh hoạt bố trí kích thước (2-3 khối: 420x270px; 4-5 khối: 360x240px; >=6 khối: bố trí dạng Grid hoặc Compact Node).
  + 3 tầng tinh gọn CHỐNG CHỒNG CHÉO (ANTI-OVERLAP):
    * Tầng 1 (đỉnh): Icon vector nét than chì to bản 5px (r=36..40px). Khi sự cố (crash/500): đặt tia sét đỏ ở góc trên ngoài thẻ hoặc thay thế icon tầng 1. TUYỆT ĐỐI CẤM vẽ tia sét hoặc icon đè lên chữ tiêu đề!
    * Tầng 2 (giữa, y=140): Tiêu đề IN HOA 32px - 36px bold than chì #26323d. Khu vực chữ là bất khả xâm phạm.
    * Tầng 3 (đáy, y = H - 44 - 20): Pill badge to 220x44px rx=14 (Active #e7f4eb chữ xanh 24-26px bold, Standby #f0ede6 chữ xám, Error #fbeae5 chữ đỏ). ĐỆM ĐÁY NỘI BỘ >= 20px: Box nhỏ trạng thái PHẢI NẰM LỌT HOÀN TOÀN TRONG HỘP, đáy pill cách viền đáy hộp lớn >= 20px, TUYỆT ĐỐI CẤM pill đè lên hoặc chẹt ngang qua đường viền stroke đáy của hộp lớn!
  + Dây dẫn & Flow Dots (Tùy chọn): Tuyến chính stroke xanh #2e7d52 dày 7-8px, marker-end="url(#arrow-green)". Có thể thêm hạt tròn to <circle r="10" fill="#2e7d52"/> chạy bám sát đường cong qua updateFlowDots() khi cần mô phỏng dữ liệu di chuyển (không bắt buộc).
- BỐ CỤC DÀN TRẢI KHÔNG GIAN (FLUID CANVAS):
  + Dàn đều các khối từ gần lề trái (X ≈ 140..200) sang gần lề phải (X ≈ 1400..1700), độ phủ ngang deltaX = X_max - X_min >= 1100px. TUYỆT ĐỐI CẤM dồn cục các khối thành một dải hẹp giữa màn hình (< 900px)!
  + Tận dụng chiều cao Y (tầng trên Y ≈ 250..300, tầng dưới Y ≈ 580..640) nếu kịch bản có rẽ nhánh, đối sánh 2 bên hoặc phân cấp. Không xếp một hàng dẹp đơn điệu ở giữa khi có quan hệ đa chiều!
- ĐỒNG BỘ DÒNG THỜI GIAN: Dùng opacity: 0 -> 1 hoặc renderScene theo stepStarts. TUYỆT ĐỐI CẤM dùng CSS transform: scale trên thẻ SVG <g> vì sẽ xóa sạch tọa độ XML translate làm dồn khối về góc trên trái!
- CẤM TẠO FOOTER NOTE: TUYỆT ĐỐI CẤM thẻ <g id="footer-note"> hay hộp chữ ở đáy (kết thúc toàn bộ đồ họa trước y = 840px để chừa chỗ cho phụ đề).
- SÀN FONT TỐI THIỂU: Tiêu đề khối 32px - 36px bold, tiêu đề đỉnh 56px - 62px bold, phụ đề dưới tiêu đề 22px - 25px (chuẩn 24px), nhãn trạng thái 24px - 26px bold.
- Tiêu đề chính bắt buộc nằm ở đỉnh SVG: <g id="header-group" transform="translate({int(width/2)}, 75)">.
- Có hàm window.__renderAt(t, stepStarts) điều khiển chuyển động theo các mốc giây. Tuyệt đối cấm setTimeout hoặc setInterval."""
        raw_resp = _call(reflection_prompt)
        html_code = extract_html_code(raw_resp)

    # Nếu đang ở chế độ tinh chỉnh (refine) mà thất bại: Bảo toàn mã cũ thay vì ghi đè template fallback
    if refine_existing_html and refine_existing_html.strip():
        emit_log("error", f"[SceneAuthor] Tinh chỉnh AI không thành công sau {max_retries} lượt. Bảo toàn mã HTML cũ cho {batch_id}.")
        meta_err = {
            "mode": "authored",
            "batch_id": batch_id,
            "html_path": str(out_html_path),
            "aspect_ratio": aspect_ratio,
            "model": model or "default",
            "rounds_needed": current_round,
            "passed": False,
            "errors": last_errors,
        }
        meta_path.write_text(json.dumps(meta_err, indent=2, ensure_ascii=False), encoding="utf-8")
        return False, scene_data, meta_err

    # Nếu sinh mới từ đầu mà sau retries vẫn không có mã hợp lệ -> Fallback nhẹ nhàng bằng mã Native SVG chuẩn tự chứa
    emit_log("warn", f"[SceneAuthor] Cảnh {batch_id} không nhận được HTML hợp lệ từ AI. Sinh mã Native SVG fallback dự phòng an toàn.")
    fallback_html = generate_minimal_native_svg_fallback(
        title=title,
        sentences=sentences,
        duration=duration,
        step_starts=step_starts,
        aspect_ratio=aspect_ratio,
    )
    out_html_path.write_text(fallback_html, encoding="utf-8")
    fallback_scene = {
        "mode": "authored",
        "html_path": str(out_html_path),
        "title": title,
        "steps": [{"label": s, "icon": "bulb", "role": "VISUAL"} for s in sentences],
    }
    meta_fallback = {
        "mode": "authored",
        "batch_id": batch_id,
        "html_path": str(out_html_path),
        "aspect_ratio": aspect_ratio,
        "fallback": True,
        "rounds_attempted": max_retries,
        "passed": False,
        "errors": last_errors,
    }
    meta_path.write_text(json.dumps(meta_fallback, indent=2, ensure_ascii=False), encoding="utf-8")
    return False, fallback_scene, meta_fallback
