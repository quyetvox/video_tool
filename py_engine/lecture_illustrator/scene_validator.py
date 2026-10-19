"""Kiểm tra/chuẩn hóa scene JSON do LLM trả về trước khi render."""
from typing import Any, Dict, List

KNOWN_TEMPLATES = {
    "authored",
    # 1. Họ AI & Autonomous Agent
    "agent_workflow",
    "rag_pipeline",
    "transformer_attention",
    "neural_net",
    # 2. Họ Lập trình & Hệ thống
    "code_block",
    "algo_array",
    "system_tree",
    "network_route",
    "architecture_stack",
    "dialogue_flow",
    # 3. Họ Phân tích & Hình thái Đa năng (Meta-Templates)
    "process_flow",
    "compare_two",
    "number_stat",
    "cycle_loop",
    "timeline_horizontal",
    "quadrant_matrix",
    "pyramid_hierarchy",
    "dynamic_diagram",
    # 4. Họ Khái niệm & Thuyết minh
    "definition",
    "title_point",
    "bullet_list",
    # 5. Họ Ví dụ & Tình huống Thực tế
    "example_simulation",
}
FALLBACK_TEMPLATE = "authored"


def _clean_text(text: str) -> str:
    """Làm sạch khoảng trắng thừa mà không cắt cụt hay thêm dấu ba chấm."""
    return " ".join(str(text or "").strip().split())


def validate_scene(scene: Any, sentences: List[str]) -> Dict[str, Any]:
    """Luôn trả scene hợp lệ: số bước = số câu, text nguyên vẹn (Zero-Truncation), template tồn tại.

    Khi scene lỗi/thiếu, fallback về bullet_list dựng trực tiếp từ các câu đã dịch.
    """
    if not isinstance(scene, dict):
        scene = {}
    raw_steps = scene.get("steps") if isinstance(scene.get("steps"), list) else []

    steps = []
    for i, sentence in enumerate(sentences):
        src = raw_steps[i] if i < len(raw_steps) and isinstance(raw_steps[i], dict) else {}
        # Zero-Truncation: Giữ nguyên vẹn toàn bộ nhãn, không bao giờ dùng dấu "..."
        label = _clean_text(src.get("label") or sentence)
        role = str(src.get("role", "VISUAL")).upper()
        if role not in ("VISUAL", "SUPPORTING", "NON_VISUAL"):
            role = "VISUAL"

        step_data = {
            "sentence_idx": i,
            "label": label,
            "icon": src.get("icon"),
            "role": role,
        }
        if "from" in src:
            step_data["from"] = _clean_text(src["from"])
        if "to" in src:
            step_data["to"] = _clean_text(src["to"])
        if "state_text" in src:
            step_data["state_text"] = _clean_text(src["state_text"])
        if "keyword" in src:
            step_data["keyword"] = _clean_text(src["keyword"])
        if "summary" in src:
            step_data["summary"] = _clean_text(src["summary"])
        steps.append(step_data)

    template = scene.get("template")
    valid_template = template if template in KNOWN_TEMPLATES else FALLBACK_TEMPLATE
    validated = {
        "template": valid_template,
        "title": _clean_text(scene.get("title") or (sentences[0] if sentences else "")),
        "steps": steps,
        "photo": scene.get("photo"),
    }

    mode = str(scene.get("mode") or "").lower()
    if mode == "authored" or not mode:
        validated["mode"] = "authored"
        if "html_path" in scene:
            validated["html_path"] = str(scene["html_path"])
        if "inferred" in scene:
            validated["inferred"] = bool(scene["inferred"])
        if "quality_score" in scene:
            validated["quality_score"] = scene["quality_score"]
        if "calibrations" in scene:
            validated["calibrations"] = scene["calibrations"]
        if "eval_details" in scene:
            validated["eval_details"] = scene["eval_details"]

    # Bổ sung & chuẩn hóa cho template number_stat
    if valid_template == "number_stat":
        stat_val = str(scene.get("stat") or "").strip()
        if not stat_val:
            import re
            # Trích xuất số liệu đầu tiên tìm thấy trong title hoặc các câu thoại
            full_txt = " ".join([validated["title"]] + sentences)
            match = re.search(r"(\d+([.,]\d+)?\s*(%|triệu|tỷ|nghìn tỷ|k|USD|\$))", full_txt, re.IGNORECASE)
            stat_val = match.group(1).strip() if match else "100%"
        validated["stat"] = stat_val

    # Bổ sung & chuẩn hóa cho template compare_two
    elif valid_template == "compare_two":
        if scene.get("left_title"):
            validated["left_title"] = _clean_text(scene["left_title"])
        if scene.get("right_title"):
            validated["right_title"] = _clean_text(scene["right_title"])

    # Bổ sung & chuẩn hóa cho template example_simulation
    if valid_template == "example_simulation":
        raw_actors = scene.get("actors") if isinstance(scene.get("actors"), list) else []
        actors = []
        for a in raw_actors[:4]:
            if isinstance(a, dict) and (a.get("name") or a.get("label")):
                actors.append({
                    "name": _clean_text(a.get("name") or a.get("label")),
                    "icon": str(a.get("icon") or "person"),
                })
        if not actors:
            actors = [
                {"name": "Chủ thể A", "icon": "person"},
                {"name": "Đối tượng B", "icon": "server"},
            ]
        validated["actors"] = actors

        # Đảm bảo mỗi step có from, to, state_text
        for i, st in enumerate(steps):
            if not st.get("from"):
                st["from"] = actors[0]["name"]
            if not st.get("to"):
                st["to"] = actors[min(1, len(actors) - 1)]["name"]
            if not st.get("state_text"):
                st["state_text"] = st["label"]

    elif valid_template == "bullet_list":
        # Chuẩn hóa semantic icon & keyword chống lệch ngữ cảnh
        for st in steps:
            txt = (st.get("label") or "").lower()
            if not st.get("icon") or st.get("icon") in ("sun", "leaf", "bulb", "gear", "check", "arrow", "star"):
                if any(w in txt for w in ("ml", "machine learning", "ai", "học máy", "trí tuệ nhân tạo", "nơ-ron")):
                    st["icon"] = "ai_brain"
                    st["keyword"] = st.get("keyword") or "Học Máy & AI"
                elif any(w in txt for w in ("thành công", "chinh phục", "kỹ năng", "cốt lõi", "thành tựu")):
                    st["icon"] = "trophy_master"
                    st["keyword"] = st.get("keyword") or "Làm Chủ Kỹ Năng"
                elif any(w in txt for w in ("code", "lập trình", "thuật toán", "chương trình", "viết mã")):
                    st["icon"] = "code"
                    st["keyword"] = st.get("keyword") or "Kỹ Năng Lập Trình"
                elif any(w in txt for w in ("kinh nghiệm", "thực tế", "thực hành", "thử nghiệm", "ứng dụng")):
                    st["icon"] = "target_goal"
                    st["keyword"] = st.get("keyword") or "Thực Tiễn Ứng Dụng"
                elif any(w in txt for w in ("dữ liệu", "data", "số liệu", "thống kê", "phân tích")):
                    st["icon"] = "data_chart"
                    st["keyword"] = st.get("keyword") or "Phân Tích Dữ Liệu"
                elif any(w in txt for w in ("công nghệ", "kỹ thuật", "hệ thống", "tối ưu")):
                    st["icon"] = "gear_tech"
                    st["keyword"] = st.get("keyword") or "Hệ Thống Kỹ Thuật"
                elif any(w in txt for w in ("tiềm năng", "bứt phá", "đa dạng", "tương lai")):
                    st["icon"] = "rocket"
                    st["keyword"] = st.get("keyword") or "Tiềm Năng Bứt Phá"
                else:
                    st["icon"] = "lightbulb"
                    st["keyword"] = st.get("keyword") or "Trọng Tâm Ý"

    return validated

