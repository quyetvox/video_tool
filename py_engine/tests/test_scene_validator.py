import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.scene_validator import validate_scene  # noqa: E402

SENTENCES = ["Ánh sáng chiếu vào lá", "Diệp lục hấp thụ năng lượng", "Tạo ra glucose và oxy"]


def test_steps_count_equals_sentence_count_when_too_few():
    scene = {"template": "bullet_list", "title": "T", "steps": [{"label": "A"}]}
    out = validate_scene(scene, SENTENCES)
    assert len(out["steps"]) == 3
    assert out["steps"][1]["label"] == SENTENCES[1]


def test_steps_trimmed_when_too_many():
    scene = {"template": "bullet_list", "steps": [{"label": str(i)} for i in range(10)]}
    assert len(validate_scene(scene, SENTENCES)["steps"]) == 3


def test_invalid_scene_falls_back_to_bullet_list_from_sentences():
    for bad in (None, "x", [], {"template": "unknown", "steps": "oops"}):
        out = validate_scene(bad, SENTENCES)
        assert out["template"] == "bullet_list"
        assert [s["label"] for s in out["steps"]] == SENTENCES


def test_long_text_is_shortened():
    out = validate_scene({"title": "x " * 100, "steps": [{"label": "y" * 200}]}, SENTENCES)
    assert len(out["title"]) <= 36
    assert all(len(s["label"]) <= 30 for s in out["steps"])
