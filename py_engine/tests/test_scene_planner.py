import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.scene_planner import (  # noqa: E402
    LEAD_IN, SENTENCE_GAP, TAIL, MAX_SENTENCES, build_timeline, group_sentences,
)


def _s(start, end, text="x"):
    return {"start": start, "end": end, "text_orig": text, "text": text}


def test_group_splits_on_long_pause():
    groups = group_sentences([_s(0, 2), _s(2.1, 4), _s(10, 12)])
    assert [len(g) for g in groups] == [2, 1]


def test_group_caps_sentences_per_group():
    groups = group_sentences([_s(i, i + 0.9) for i in range(MAX_SENTENCES + 2)])
    assert [len(g) for g in groups] == [MAX_SENTENCES, 2]


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
