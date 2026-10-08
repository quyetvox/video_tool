"""Kiểm tra/chuẩn hóa scene JSON do LLM trả về trước khi render."""
from typing import Any, Dict, List

KNOWN_TEMPLATES = {
    "bullet_list",
    "title_point",
    "process_flow",
    "compare_two",
    "definition",
    "number_stat",
    "code_block",
    "network_route",
    "algo_array",
    "neural_net",
    "system_tree",
    "agent_workflow",
    "rag_pipeline",
    "transformer_attention",
}
FALLBACK_TEMPLATE = "bullet_list"
MAX_LABEL_CHARS = 24
MAX_TITLE_CHARS = 26


def _shorten(text: str, limit: int) -> str:
    text = " ".join(str(text or "").split())
    if len(text) <= limit:
        return text
    cut = text[: limit - 1].rsplit(" ", 1)[0] or text[: limit - 1]
    return cut + "…"


def validate_scene(scene: Any, sentences: List[str]) -> Dict[str, Any]:
    """Luôn trả scene hợp lệ: số bước = số câu, chữ đã rút gọn, template tồn tại.

    Khi scene lỗi/thiếu, fallback về bullet_list dựng trực tiếp từ các câu đã dịch.
    """
    if not isinstance(scene, dict):
        scene = {}
    raw_steps = scene.get("steps") if isinstance(scene.get("steps"), list) else []

    steps = []
    for i, sentence in enumerate(sentences):
        src = raw_steps[i] if i < len(raw_steps) and isinstance(raw_steps[i], dict) else {}
        steps.append({
            "sentence_idx": i,
            "label": _shorten(src.get("label") or sentence, MAX_LABEL_CHARS),
            "icon": src.get("icon"),
        })

    template = scene.get("template")
    return {
        "template": template if template in KNOWN_TEMPLATES else FALLBACK_TEMPLATE,
        "title": _shorten(scene.get("title") or (sentences[0] if sentences else ""), MAX_TITLE_CHARS),
        "steps": steps,
        "photo": scene.get("photo"),
    }
