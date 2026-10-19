import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.scene_planner import (  # noqa: E402
    LEAD_IN, SENTENCE_GAP, TAIL, MAX_SENTENCES, build_timeline, group_sentences, stitch_sentence_boundaries,
)


def _s(start, end, text="Nội dung bài giảng."):
    return {"start": start, "end": end, "text_orig": text, "text": text}


def test_group_splits_on_long_pause():
    # Nhóm >= 3 câu gặp khoảng lặng >= 2.5s sẽ tách cụm tri thức hài hòa (3 - 7 câu), tránh cảnh cụt
    groups = group_sentences([_s(0, 2), _s(2.1, 4), _s(4.1, 6), _s(10, 12), _s(12.1, 14), _s(14.1, 16)])
    assert [len(g) for g in groups] == [3, 3]


def test_group_caps_sentences_per_group():
    # Ngưỡng sức chứa thị giác tối đa 2-4 câu trên màn hình chống nhồi nhét (MAX_SENTENCES = 4)
    groups = group_sentences([_s(i, i + 0.9) for i in range(10)])
    assert [len(g) for g in groups] == [4, 4, 2]


def test_timeline_total_equals_tts_plus_gaps():
    groups = [[_s(0, 1), _s(1, 2)], [_s(9, 10)]]
    durations = [3.0, 2.0, 4.0]
    tl = build_timeline(groups, durations)
    expected = (LEAD_IN + 3.0 + SENTENCE_GAP + 2.0 + TAIL) + (LEAD_IN + 4.0 + TAIL)
    assert abs(tl[-1]["end"] - expected) < 0.01
    assert abs(sum(g["scene_duration"] for g in tl) - expected) < 0.01


def test_step_start_matches_sentence_absolute_start():
    tl = build_timeline([[_s(0, 1), _s(1, 2)], [_s(9, 10)]], [3.0, 2.0, 4.0])
    for g in tl:
        for k, sent in enumerate(g["sentences"]):
            assert abs(g["start"] + g["step_starts"][k] - sent["start"]) < 0.01
    assert tl[1]["start"] == tl[0]["end"]
    assert len(tl[0]["step_starts"]) == len(tl[0]["sentences"]) == 2


def test_repetition_cleaner_collapses_whisper_hallucination_loop():
    from utils.repetition_cleaner import RepetitionCleaner
    raw_segs = [
        {"start": 100.0, "end": 105.0, "text": "Khái niệm mở đầu bài giảng."},
        {"start": 107.0, "end": 110.0, "text": "We've been working with the developers and we've been working with the developers and"},
        {"start": 110.0, "end": 113.0, "text": "we've been working with the developers and we've been working with the developers and"},
        {"start": 113.0, "end": 115.0, "text": "we've been working with the developers and we've been working with the developers and"},
        {"start": 120.0, "end": 125.0, "text": "Tiếp tục bài giảng phần tiếp theo."},
    ]
    cleaned = RepetitionCleaner.clean_segments(raw_segs)
    # Lặp 3 câu liên tiếp phải được gộp thành 1 câu duy nhất
    assert len(cleaned) == 3
    # Câu lặp nội bộ trong câu đơn lẻ phải được rút gọn sạch
    assert cleaned[1]["text"] == "We've been working with the developers and"


def test_stitch_sentence_boundaries_merges_dangling_commas_and_conjunctions():
    # Câu 37 kết thúc bằng dấu phẩy và câu 38 bắt đầu bằng chữ thường
    raw = [
        {"start": 180.0, "end": 183.0, "duration": 3.0, "text": "Cuối cùng, vì LLM có thể dùng để tạo câu trả lời,", "text_orig": "Finally, since LMS can be used to generate answers,"},
        {"start": 183.5, "end": 187.0, "duration": 3.5, "text": "bạn sẽ học cách đưa kết quả tìm kiếm vào LLM.", "text_orig": "you also learn how to plug in the search results into an LLM."},
    ]
    stitched = stitch_sentence_boundaries(raw)
    assert len(stitched) == 1
    assert stitched[0]["text"] == "Cuối cùng, vì LLM có thể dùng để tạo câu trả lời, bạn sẽ học cách đưa kết quả tìm kiếm vào LLM."
    assert stitched[0]["text_orig"] == "Finally, since LMS can be used to generate answers, you also learn how to plug in the search results into an LLM."
    assert stitched[0]["duration"] == 6.5
    assert stitched[0]["end"] == 187.0


def test_stitch_sentence_boundaries_handles_orphan_fragment_and_split_word():
    """Kiểm tra khâu triệt để mảnh mồ côi 1 từ và câu trước không có dấu chấm dù text_orig có dấu chấm."""
    raw = [
        {
            "start": 69.522,
            "end": 74.248,
            "duration": 4.476,
            "text": "nó tìm phần tử nhỏ nhất trong phần chưa được sắp xếp rồi đưa phần tử đó về đầu đoạn chưa sắp",
            "text_orig": "it finds the smallest element in the unsorted portion and moves it to the front.",
        },
        {
            "start": 74.248,
            "end": 75.052,
            "duration": 0.554,
            "text": "xếp.",
            "text_orig": "The unsorted portion shrinks accordingly.",
        },
    ]
    stitched = stitch_sentence_boundaries(raw)
    assert len(stitched) == 1
    assert stitched[0]["text"] == "nó tìm phần tử nhỏ nhất trong phần chưa được sắp xếp rồi đưa phần tử đó về đầu đoạn chưa sắp xếp."
    assert stitched[0]["duration"] == round(4.476 + 0.554, 3)
    assert stitched[0]["end"] == 75.052


def test_group_sentences_prevents_split_on_dangling_comma():
    # Danh sách 8 câu, trong đó câu thứ 7 kết thúc bằng dấu phẩy
    sentences = [_s(i, i + 0.9, f"Ý niệm số {i + 1}.") for i in range(6)]
    sentences.append({"start": 6.0, "end": 6.9, "duration": 0.9, "text": "Đặc biệt là khi triển khai mô hình,", "text_orig": "Especially when deploying models,"})
    sentences.append({"start": 7.0, "end": 7.9, "duration": 0.9, "text": "bạn cần theo dõi sát sao độ trễ.", "text_orig": "you must closely monitor latency."})

    groups = group_sentences(sentences)
    # Với MAX_SENTENCES = 4: Cụm 1 có 4 câu, cụm 2 chứa 2 câu + 2 câu dở dang (tổng 4 câu)
    assert len(groups) == 2
    assert len(groups[0]) == 4
    assert len(groups[1]) == 4
    assert groups[1][2]["text"] == "Đặc biệt là khi triển khai mô hình,"
    assert groups[1][3]["text"] == "bạn cần theo dõi sát sao độ trễ."


def test_plan_scenes_returns_ai_native_authored_mode():
    """Kiểm tra plan_scenes luôn tạo các scene ở mode 'authored' trực tiếp không qua router tĩnh."""
    from lecture_illustrator.scene_planner import plan_scenes
    groups = [[_s(0, 1, "Giới thiệu AI Agent"), _s(1, 2, "ReAct reasoning loop")]]
    scenes = plan_scenes(groups)
    assert len(scenes) == 1
    assert scenes[0]["mode"] == "authored"
    assert "title" in scenes[0]
    assert len(scenes[0]["steps"]) == 2


def test_plan_semantic_knowledge_units_with_llm():
    """Kiểm tra LLM semantic chunking nhóm câu trọn vẹn ngữ cảnh (không bị gò bó 4 câu)."""
    import json
    from lecture_illustrator.scene_planner import plan_semantic_knowledge_units, group_sentences, plan_scenes

    # Giả lập 9 câu: 2 câu mở đầu, 7 câu giải thuật Bubble Sort
    sentences = [
        {"start": float(i), "end": float(i + 1), "text": f"Câu thứ {i + 1}", "text_orig": f"Sent {i + 1}"}
        for i in range(9)
    ]

    llm_payload = json.dumps([
        {
            "sentence_indices": [0, 1],
            "title": "TỔNG QUAN BÀI GIẢNG",
            "visual_concept": "Giới thiệu bài toán sắp xếp dữ liệu",
            "diagram_type": "concept_map"
        },
        {
            "sentence_indices": [2, 3, 4, 5, 6, 7, 8],
            "title": "GIẢI THUẬT BUBBLE SORT",
            "visual_concept": "Mô phỏng đổi chỗ các cặp kề nhau và nổi lên",
            "diagram_type": "flowchart"
        }
    ])

    groups, metas = plan_semantic_knowledge_units(
        sentences=sentences,
        llm_caller=lambda p: llm_payload
    )

    assert len(groups) == 2
    assert len(groups[0]) == 2
    assert len(groups[1]) == 7  # 7 câu vẫn nằm trọn trong 1 batch, không bị cắt vụn thành 4 câu!
    assert metas[0]["title"] == "TỔNG QUAN BÀI GIẢNG"
    assert metas[1]["title"] == "GIẢI THUẬT BUBBLE SORT"
    assert metas[1]["visual_concept"] == "Mô phỏng đổi chỗ các cặp kề nhau và nổi lên"
    assert metas[1]["diagram_type"] == "flowchart"

    # Kiểm tra group_sentences và plan_scenes thừa kế đầy đủ
    g_res = group_sentences(sentences, llm_caller=lambda p: llm_payload)
    scenes = plan_scenes(g_res)
    assert len(scenes) == 2
    assert scenes[0]["title"] == "TỔNG QUAN BÀI GIẢNG"
    assert scenes[1]["title"] == "GIẢI THUẬT BUBBLE SORT"
    assert scenes[1]["visual_concept"] == "Mô phỏng đổi chỗ các cặp kề nhau và nổi lên"
    assert scenes[1]["diagram_type"] == "flowchart"
    assert len(scenes[1]["steps"]) == 7


def test_plan_semantic_knowledge_units_gap_healing():
    """Kiểm tra Continuity Guard tự động lấp đầy khoảng trống khi LLM vô tình bỏ sót index."""
    import json
    from lecture_illustrator.scene_planner import plan_semantic_knowledge_units

    sentences = [{"start": float(i), "end": float(i + 1), "text": f"Câu {i}", "text_orig": f"S {i}"} for i in range(6)]

    # LLM bỏ sót index 2 và index 5
    llm_payload = json.dumps([
        {"sentence_indices": [0, 1], "title": "BẮT ĐẦU", "visual_concept": "Mở đầu", "diagram_type": "process_steps"},
        {"sentence_indices": [3, 4], "title": "TRUNG TÂM", "visual_concept": "Nội dung", "diagram_type": "architecture"},
    ])

    groups, metas = plan_semantic_knowledge_units(
        sentences=sentences,
        llm_caller=lambda p: llm_payload
    )

    # Toàn bộ 6 câu (0..5) đều phải được phủ kín, không câu nào bị rơi rụng
    total_assigned = sum(len(g) for g in groups)
    assert total_assigned == 6
    all_texts = [s["text"] for g in groups for s in g]
    assert all_texts == [f"Câu {i}" for i in range(6)]


def test_group_sentences_by_paragraphs_fallback():
    """Kiểm tra Fallback gom theo đoạn văn (para_idx) khi không có LLM."""
    from lecture_illustrator.scene_planner import group_sentences

    sentences = [
        {"start": 0.0, "end": 1.0, "text": "Câu 1 đoạn 1", "text_orig": "S1", "para_idx": 0},
        {"start": 1.0, "end": 2.0, "text": "Câu 2 đoạn 1", "text_orig": "S2", "para_idx": 0},
        {"start": 2.0, "end": 3.0, "text": "Câu 1 đoạn 2", "text_orig": "S3", "para_idx": 1},
        {"start": 3.0, "end": 4.0, "text": "Câu 2 đoạn 2", "text_orig": "S4", "para_idx": 1},
        {"start": 4.0, "end": 5.0, "text": "Câu 3 đoạn 2", "text_orig": "S5", "para_idx": 1},
        {"start": 5.0, "end": 6.0, "text": "Câu 4 đoạn 2", "text_orig": "S6", "para_idx": 1},
        {"start": 6.0, "end": 7.0, "text": "Câu 5 đoạn 2", "text_orig": "S7", "para_idx": 1},
    ]

    # Không truyền api_key/base_url -> Tự động gom theo para_idx
    groups = group_sentences(sentences)
    assert len(groups) == 2
    assert len(groups[0]) == 2
    assert len(groups[1]) == 5  # Đoạn 2 có 5 câu giữ nguyên vẹn cùng nhau!



