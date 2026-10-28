import json
import tempfile
from pathlib import Path
import sys

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.scene_author import (  # noqa: E402
    build_scene_author_prompt,
    extract_html_code,
    author_scene_with_retry,
)


CLEAN_HTML = """<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <link rel="stylesheet" href="style_kit.css">
</head>
<body style="background:#f4efe3;margin:0;">
  <div id="stage">
    <svg id="svg" viewBox="0 0 1920 1080">
      <g id="header-group" transform="translate(960, 80)">
        <text text-anchor="middle" font-size="44px" font-weight="bold">KIẾN TRÚC HỆ THỐNG</text>
      </g>
      <rect x="200" y="250" width="360" height="200" fill="#fff" />
    </svg>
  </div>
  <script src="style_kit.js"></script>
  <script>
    window.__load = function(scene) {};
    window.__renderAt = function(t, stepStarts) {
      const el = document.querySelector('text');
      if (el) el.setAttribute('opacity', Math.min(1, t));
    };
  </script>
</body>
</html>"""


BROKEN_HTML_WITH_TIMER = """<!DOCTYPE html>
<html>
<body>
  <h1>Đang tải...</h1>
  <script>
    window.__load = function(s) {};
    window.__renderAt = function(t, s) {};
    setTimeout(() => { console.log('bad timer'); }, 1000);
  </script>
</body>
</html>"""


BROKEN_HTML_NO_RENDER = """<!DOCTYPE html>
<html>
<body>
  <script>
    window.__load = function(s) {};
  </script>
</body>
</html>"""


def test_build_scene_author_prompt():
    """Kiểm tra cấu trúc prompt đầy đủ các thành phần hợp đồng và chỉ dẫn bố cục."""
    prompt = build_scene_author_prompt(
        sentences=["Khái niệm mạng nơ-ron", "Hàm kích hoạt phi tuyến"],
        step_starts=[0.0, 2.5],
        duration=6.0,
        aspect_ratio="9:16",
        title="Trí tuệ nhân tạo",
    )
    assert "9:16" in prompt
    assert "1080 x 1920" in prompt
    assert "window.__load" in prompt
    assert "window.__renderAt" in prompt
    assert "ZERO-TRUNCATION" in prompt
    assert "PatrickHand" in prompt
    assert "setTimeout" in prompt  # Trong phần cấm


def test_extract_html_code():
    """Kiểm tra trích xuất code HTML từ markdown codeblock."""
    raw = f"Dưới đây là mã của bạn:\n```html\n{CLEAN_HTML}\n```\nChúc bạn thành công!"
    extracted = extract_html_code(raw)
    assert "<!DOCTYPE html>" in extracted
    assert "window.__load" in extracted


def test_author_scene_passes_on_first_try():
    """Khi LLM trả về mã sạch ngay từ đầu, đạt chuẩn tại vòng 0."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        out_html = Path(tmp_dir) / "scene_001.html"

        def mock_llm(p: str) -> str:
            return f"```html\n{CLEAN_HTML}\n```"

        success, scene, meta = author_scene_with_retry(
            batch_id="batch_001",
            sentences=["Câu 1", "Câu 2"],
            step_starts=[0.0, 2.0],
            duration=5.0,
            aspect_ratio="16:9",
            out_html_path=out_html,
            llm_caller=mock_llm,
            max_retries=2,
        )

        assert success is True
        assert scene["mode"] == "authored"
        assert scene["html_path"] == str(out_html.resolve())
        assert meta["rounds_needed"] == 0
        assert meta["passed"] is True
        assert out_html.exists()


def test_author_scene_self_corrects_on_second_try():
    """Khi LLM trả về mã lỗi ở vòng 0, nhưng sửa thành công ở vòng 1 qua Reflection loop."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        out_html = Path(tmp_dir) / "scene_002.html"
        calls = []

        def mock_llm_healing(p: str) -> str:
            calls.append(p)
            if len(calls) == 1:
                # Vòng 0: trả về mã dính timer và dấu ba chấm
                return f"```html\n{BROKEN_HTML_WITH_TIMER}\n```"
            # Vòng 1: sửa thành mã sạch
            return f"```html\n{CLEAN_HTML}\n```"

        success, scene, meta = author_scene_with_retry(
            batch_id="batch_002",
            sentences=["Bước 1", "Bước 2"],
            step_starts=[0.0, 1.5],
            duration=4.0,
            aspect_ratio="16:9",
            out_html_path=out_html,
            llm_caller=mock_llm_healing,
            max_retries=2,
        )

        assert success is True
        assert scene["mode"] == "authored"
        assert meta["rounds_needed"] == 1
        assert len(calls) == 2
        # Kiểm tra nội dung reflection prompt có chứa lỗi cảnh báo
        assert "tiêu chí an toàn" in calls[1] or "chưa đạt" in calls[1]


def test_author_scene_falls_back_after_two_failed_retries():
    """Khi LLM tiếp tục trả về mã lỗi qua 2 vòng sửa, hệ thống tự động sinh mã Native SVG fallback an toàn tự chứa."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        out_html = Path(tmp_dir) / "scene_003.html"
        call_count = 0

        def mock_llm_always_broken(p: str) -> str:
            nonlocal call_count
            call_count += 1
            return f"```html\n{BROKEN_HTML_NO_RENDER}\n```"

        success, scene, meta = author_scene_with_retry(
            batch_id="batch_003",
            sentences=["Câu A", "Câu B"],
            step_starts=[0.0, 1.0],
            duration=3.0,
            aspect_ratio="9:16",
            out_html_path=out_html,
            llm_caller=mock_llm_always_broken,
            max_retries=2,
        )

        # Kết quả fallback bằng Native SVG tự chứa
        assert success is False
        assert scene["mode"] == "authored"
        assert meta["fallback"] is True
        assert meta["passed"] is False
        assert meta["rounds_attempted"] == 2
        assert len(meta["errors"]) > 0
        assert call_count == 3  # 1 lần gọi đầu + 2 lần sửa
        assert out_html.exists()
        fallback_content = out_html.read_text(encoding="utf-8")
        assert "<svg" in fallback_content
        assert "window.__renderAt" in fallback_content
        assert "Câu A" in fallback_content


def test_master_prompt_few_shots_and_assets():
    """Kiểm tra Master Prompt chứa đầy đủ 16 section, few-shot và đường dẫn font assets/fonts/."""
    from lecture_illustrator.scene_author import load_master_prompt_template, PATRICK_HAND_FONT_PATH
    prompt = load_master_prompt_template()
    assert "CANONICAL FEW-SHOT DEMONSTRATIONS" in prompt
    assert "assets/fonts/PatrickHand.ttf" in prompt
    assert PATRICK_HAND_FONT_PATH.exists()


def test_monolithic_prompt_for_high_visual_fidelity():
    """Kiểm tra author_scene_with_retry gửi prompt nguyên khối (Master + User info) trực tiếp không tách caching."""
    from unittest.mock import MagicMock, patch
    from lecture_illustrator.knowledge_extractor import call_llm_api

    # 1. Kiểm tra author_scene_with_retry gọi llm_caller với prompt nguyên khối
    received_prompts = []

    def mock_monolithic_llm(p: str):
        received_prompts.append(p)
        return f"```html\n{CLEAN_HTML}\n```"

    with tempfile.TemporaryDirectory() as tmp_dir:
        out_html = Path(tmp_dir) / "scene_monolithic.html"
        ok, _, meta = author_scene_with_retry(
            batch_id="batch_001",
            sentences=["Khái niệm Kiến trúc Hệ thống", "Lát cắt đa tầng"],
            step_starts=[0.0, 2.0],
            duration=5.0,
            aspect_ratio="16:9",
            out_html_path=out_html,
            llm_caller=mock_monolithic_llm,
        )
        assert ok is True
        assert len(received_prompts) == 1
        # Prompt nguyên khối phải chứa cả yêu cầu Blueprint / Master Template và thông tin cảnh cụ thể
        assert (
            "YÊU CẦU TRẢ VỀ TỐI THƯỢNG" in received_prompts[0]
            or "STRICT OUTPUT CONTRACT" in received_prompts[0]
            or "STYLE: BLUEPRINT" in received_prompts[0]
            or "ROLE:" in received_prompts[0]
        )
        assert "THÔNG TIN ĐẦU VÀO CHO CẢNH MINH HỌA NÀY" in received_prompts[0]
        assert "Lát cắt đa tầng" in received_prompts[0]

    # 2. Kiểm tra call_llm_api đẩy system_instruction vào Gemini payload
    with patch("urllib.request.urlopen") as mock_url:
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "candidates": [{"content": {"parts": [{"text": "Gemini HTML"}]}}]
        }).encode("utf-8")
        mock_resp.__enter__.return_value = mock_resp
        mock_url.return_value = mock_resp

        res = call_llm_api(
            prompt="User question",
            api_key="AIzaSy_fake_test_key",
            model_name="gemini-2.5-flash",
            system_prompt="System static prompt instructions",
        )
        assert res == "Gemini HTML"
        req_called = mock_url.call_args[0][0]
        body = json.loads(req_called.data.decode("utf-8"))
        assert "system_instruction" in body
        assert body["system_instruction"]["parts"][0]["text"] == "System static prompt instructions"
        assert body["contents"][0]["parts"][0]["text"] == "User question"
        assert body["generationConfig"]["maxOutputTokens"] == 8192
        assert body["generationConfig"]["topP"] == 0.8

    # 3. Kiểm tra call_llm_api đẩy role: system vào Ollama / OpenAI payload và kèm options tối ưu
    with patch("urllib.request.urlopen") as mock_url:
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "choices": [{"message": {"content": "Ollama HTML"}}]
        }).encode("utf-8")
        mock_resp.__enter__.return_value = mock_resp
        mock_url.return_value = mock_resp

        res = call_llm_api(
            prompt="User question",
            base_url="http://localhost:11434",
            model_name="gemma4:31b-cloud",
            system_prompt="System static prompt for ollama",
        )
        assert res == "Ollama HTML"
        req_called = mock_url.call_args[0][0]
        body = json.loads(req_called.data.decode("utf-8"))
        assert len(body["messages"]) == 2
        assert body["messages"][0]["role"] == "system"
        assert body["messages"][0]["content"] == "System static prompt for ollama"
        assert body["messages"][1]["role"] == "user"
        assert body["messages"][1]["content"] == "User question"
        assert "options" in body
        assert body["options"]["num_ctx"] == 16384
        assert body["options"]["temperature"] == 0.0
        assert body["options"]["top_p"] == 0.5
        assert body["options"]["num_predict"] == 4096

    # 4. Kiểm tra tự động tách marker thành system_instruction khi không có system_prompt tường minh
    with patch("urllib.request.urlopen") as mock_url:
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "candidates": [{"content": {"parts": [{"text": "Auto Split HTML"}]}}]
        }).encode("utf-8")
        mock_resp.__enter__.return_value = mock_resp
        mock_url.return_value = mock_resp

        composite_prompt = "Đây là Master Blueprint Prompt\n\nTHÔNG TIN ĐẦU VÀO CHO CẢNH MINH HỌA NÀY:\nCảnh số 1: Giới thiệu Redis"
        res = call_llm_api(
            prompt=composite_prompt,
            api_key="AIzaSy_fake_test_key",
            model_name="gemini-2.5-flash",
        )
        assert res == "Auto Split HTML"
        req_called = mock_url.call_args[0][0]
        body = json.loads(req_called.data.decode("utf-8"))
        assert "system_instruction" in body
        assert body["system_instruction"]["parts"][0]["text"] == "Đây là Master Blueprint Prompt"
        assert "Cảnh số 1: Giới thiệu Redis" in body["contents"][0]["parts"][0]["text"]


def test_author_scene_with_retry_respects_title_and_concept():
    """Kiểm tra author_scene_with_retry nhận diện đúng title, concept và diagram_type từ semantic planner."""
    with tempfile.TemporaryDirectory() as tmp_dir:
        out_html = Path(tmp_dir) / "test_batch.html"
        captured_prompts = []

        def mock_llm(prompt):
            captured_prompts.append(prompt)
            return f"```html\n{CLEAN_HTML}\n```"

        ok, sc_data, meta = author_scene_with_retry(
            batch_id="batch_001",
            sentences=["Câu 1", "Câu 2"],
            step_starts=[0.0, 2.0],
            duration=5.0,
            aspect_ratio="16:9",
            out_html_path=out_html,
            llm_caller=mock_llm,
            title="GIẢI THUẬT BUBBLE SORT",
            concept="Mô phỏng đổi chỗ cặp phần tử kề nhau",
            diagram_type="flowchart",
        )

        assert ok is True
        assert sc_data["title"] == "GIẢI THUẬT BUBBLE SORT"
        assert sc_data["visual_concept"] == "Mô phỏng đổi chỗ cặp phần tử kề nhau"
        assert sc_data["diagram_type"] == "flowchart"
        assert len(captured_prompts) == 1
        assert "TITLE: GIẢI THUẬT BUBBLE SORT" in captured_prompts[0]
        assert "VISUAL CONCEPT DIRECTION: Mô phỏng đổi chỗ cặp phần tử kề nhau" in captured_prompts[0]
        assert "Archetype: flowchart" in captured_prompts[0]


def test_scene_author_session_lifecycle_and_reset():
    """Kiểm tra SceneAuthorSession tích lũy ngữ cảnh đến window_size và tự động reset ở lượt kế tiếp."""
    from lecture_illustrator.scene_author import SceneAuthorSession

    captured_prompts = []

    def mock_caller(prompt):
        captured_prompts.append(prompt)
        return f"```html\n{CLEAN_HTML}\n```"

    session = SceneAuthorSession(
        window_size=2,
        system_prompt="MASTER SYSTEM BLUEPRINT RULES",
        llm_caller=mock_caller,
    )

    with tempfile.TemporaryDirectory() as tmp_dir:
        # Lượt 1: Bắt đầu window
        p1 = Path(tmp_dir) / "b1.html"
        ok1, _, _ = author_scene_with_retry(
            batch_id="batch_001",
            sentences=["Câu 1"],
            step_starts=[0.0],
            duration=3.0,
            aspect_ratio="16:9",
            out_html_path=p1,
            session=session,
        )
        assert ok1 is True
        assert session.turns_in_window == 1
        assert len(session.history) == 2  # user + assistant

        # Lượt 2: Trong window
        p2 = Path(tmp_dir) / "b2.html"
        ok2, _, _ = author_scene_with_retry(
            batch_id="batch_002",
            sentences=["Câu 2"],
            step_starts=[0.0],
            duration=3.0,
            aspect_ratio="16:9",
            out_html_path=p2,
            session=session,
        )
        assert ok2 is True
        assert session.turns_in_window == 2
        assert len(session.history) == 4

        # Lượt 3: Vượt quá window_size=2 -> Tự động reset và bắt đầu cửa sổ mới
        p3 = Path(tmp_dir) / "b3.html"
        ok3, _, _ = author_scene_with_retry(
            batch_id="batch_003",
            sentences=["Câu 3"],
            step_starts=[0.0],
            duration=3.0,
            aspect_ratio="16:9",
            out_html_path=p3,
            session=session,
        )
        assert ok3 is True
        assert session.turns_in_window == 1
        assert len(session.history) == 2


def test_retry_preserves_system_prompt_and_session():
    """Kiểm tra vòng Retry/Reflection bảo toàn System Prompt và lịch sử trong Session."""
    from lecture_illustrator.scene_author import SceneAuthorSession

    call_count = 0
    received_prompts = []

    def mock_retry_caller(prompt):
        nonlocal call_count
        call_count += 1
        received_prompts.append(prompt)
        if call_count == 1:
            # Lần 1: trả về HTML thiếu viewBox chuẩn để kích hoạt retry
            return "```html\n<div>invalid</div>\n```"
        # Lần 2 (Retry): trả về HTML sạch chuẩn
        return f"```html\n{CLEAN_HTML}\n```"

    session = SceneAuthorSession(
        window_size=3,
        system_prompt="MASTER SYSTEM BLUEPRINT RULES",
        llm_caller=mock_retry_caller,
    )

    with tempfile.TemporaryDirectory() as tmp_dir:
        out_html = Path(tmp_dir) / "retry_batch.html"
        ok, _, meta = author_scene_with_retry(
            batch_id="batch_retry",
            sentences=["Câu thoại thử nghiệm retry"],
            step_starts=[0.0],
            duration=4.0,
            aspect_ratio="16:9",
            out_html_path=out_html,
            session=session,
            max_retries=1,
        )
        assert ok is True
        assert meta["rounds_needed"] == 1
        assert call_count == 2
        # Lần 1 gửi prompt ban đầu chứa thông tin batch
        assert "Câu thoại thử nghiệm retry" in received_prompts[0]
        # Lần 2 gửi reflection prompt chỉ rõ lỗi
        assert "HÃY SỬA LẠI TRÊN CẤU TRÚC VỪA TẠO" in received_prompts[1]
        assert session.turns_in_window == 1


def test_gemini_multiturn_alternating_contract_and_smart_routing():
    """Kiểm tra xử lý riêng cho Gemini: Smart Routing bỏ qua Ollama, system_instruction riêng và gộp part nếu trùng role."""
    from unittest.mock import MagicMock, patch
    from lecture_illustrator.knowledge_extractor import call_llm_api

    with patch("urllib.request.urlopen") as mock_url:
        mock_resp = MagicMock()
        mock_resp.read.return_value = json.dumps({
            "candidates": [{"content": {"parts": [{"text": "```html\n<!DOCTYPE html><html><body>Gemini OK</body></html>\n```"}]}}]
        }).encode("utf-8")
        mock_resp.__enter__.return_value = mock_resp
        mock_url.return_value = mock_resp

        # Truyền cả base_url Ollama và Gemini API key + model Gemini -> phải gọi thẳng Google Gemini REST
        res = call_llm_api(
            api_key="AIzaSy_fake_test_gemini_key",
            model_name="gemini-3.8-flash",
            base_url="http://localhost:11434",
            system_prompt="MASTER SYSTEM RULES FOR GEMINI",
            messages=[
                {"role": "user", "content": "Tạo cảnh 1"},
                {"role": "assistant", "content": "<html>Cảnh 1 lỗi</html>"},
                {"role": "user", "content": "Hãy sửa lại cảnh 1"},
            ],
        )
        assert "Gemini OK" in res
        req_called = mock_url.call_args[0][0]
        # Kiểm tra URL gọi đến Google generativelanguage, không gọi localhost:11434
        assert "generativelanguage.googleapis.com" in req_called.full_url
        assert "AIzaSy_fake_test_gemini_key" in req_called.full_url

        body = json.loads(req_called.data.decode("utf-8"))
        # 1. System prompt đưa vào system_instruction
        assert "system_instruction" in body
        assert body["system_instruction"]["parts"][0]["text"] == "MASTER SYSTEM RULES FOR GEMINI"

        # 2. Contents luân phiên user -> model -> user
        contents = body["contents"]
        assert len(contents) == 3
        assert contents[0]["role"] == "user"
        assert contents[0]["parts"][0]["text"] == "Tạo cảnh 1"
        assert contents[1]["role"] == "model"
        assert contents[1]["parts"][0]["text"] == "<html>Cảnh 1 lỗi</html>"
        assert contents[2]["role"] == "user"
        assert contents[2]["parts"][0]["text"] == "Hãy sửa lại cảnh 1"



