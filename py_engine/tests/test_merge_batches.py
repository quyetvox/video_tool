import argparse
import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pytest

from lecture_illustrator.models import LectureBatch, LectureProject, LectureProjectConfig
from lecture_illustrator_orchestrator import run_merge_batches_flow


@pytest.fixture
def temp_lecture_project():
    temp_dir = Path(tempfile.mkdtemp(prefix="test_merge_batches_"))
    scenes_dir = temp_dir / "scenes"
    scenes_dir.mkdir(parents=True, exist_ok=True)
    tts_dir = temp_dir / "tts"
    tts_dir.mkdir(parents=True, exist_ok=True)

    # Khởi tạo 3 batches: Batch 1 có câu dở dang dấu phẩy, Batch 2 bắt đầu bằng chữ thường
    b1 = LectureBatch(
        id="batch_001",
        start_sec=0.0,
        end_sec=10.0,
        transcript_original="First concept. Finally, since LMS can be used to generate answers,",
        transcript_translated="Khái niệm đầu tiên. Cuối cùng, vì LLM có thể dùng để tạo câu trả lời,",
        scene_duration=10.0,
        step_starts=[1.2, 5.0],
        sentences=[
            {
                "index": 0,
                "audio_file": "s_0000.mp3",
                "text_orig": "First concept.",
                "text": "Khái niệm đầu tiên.",
                "duration": 3.0,
                "start": 1.2,
                "end": 4.2,
            },
            {
                "index": 1,
                "audio_file": "s_0001.mp3",
                "text_orig": "Finally, since LMS can be used to generate answers,",
                "text": "Cuối cùng, vì LLM có thể dùng để tạo câu trả lời,",
                "duration": 4.0,
                "start": 5.0,
                "end": 9.0,
            },
        ],
        scene={"template": "bullet_list", "title": "Khái niệm đầu tiên", "steps": []},
    )

    b2 = LectureBatch(
        id="batch_002",
        start_sec=10.0,
        end_sec=18.0,
        transcript_original="you also learn how to plug in search results.",
        transcript_translated="bạn sẽ học cách đưa kết quả tìm kiếm vào LLM.",
        scene_duration=8.0,
        step_starts=[1.2],
        sentences=[
            {
                "index": 2,
                "audio_file": "s_0002.mp3",
                "text_orig": "you also learn how to plug in search results.",
                "text": "bạn sẽ học cách đưa kết quả tìm kiếm vào LLM.",
                "duration": 5.0,
                "start": 11.2,
                "end": 16.2,
            },
        ],
        scene={"template": "bullet_list", "title": "Tích hợp", "steps": []},
    )

    b3 = LectureBatch(
        id="batch_003",
        start_sec=18.0,
        end_sec=28.0,
        transcript_original="Third concept.",
        transcript_translated="Khái niệm thứ ba.",
        scene_duration=10.0,
        step_starts=[1.2],
        sentences=[
            {
                "index": 3,
                "audio_file": "s_0003.mp3",
                "text_orig": "Third concept.",
                "text": "Khái niệm thứ ba.",
                "duration": 6.0,
                "start": 19.2,
                "end": 25.2,
            },
        ],
        scene={"template": "bullet_list", "title": "Khái niệm ba", "steps": []},
    )

    project = LectureProject(
        project_name="test_merge",
        video_path=str(temp_dir / "dummy.mp4"),
        batches=[b1, b2, b3],
        config=LectureProjectConfig(
            aspect_ratio="16:9",
            tts_voice="ban_mai",
            burn_subtitles=False,
        ),
    )

    proj_file = temp_dir / "lecture_project.json"
    proj_file.write_text(json.dumps(project.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")

    yield proj_file

    shutil.rmtree(temp_dir, ignore_errors=True)


CLEAN_HTML = """<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <link rel="stylesheet" href="style_kit.css">
</head>
<body style="background:#f4efe3;margin:0;">
  <div id="stage"><svg id="svg" viewBox="0 0 1920 1080"></svg></div>
  <script src="style_kit.js"></script>
  <script>
    window.__load = function(scene) {
      document.getElementById('svg').innerHTML = '<text x="100" y="100">' + (scene.title || 'Bài giảng') + '</text>';
    };
    window.__renderAt = function(t, stepStarts) {
      const el = document.querySelector('text');
      if (el) el.setAttribute('opacity', Math.min(1, t));
    };
  </script>
</body>
</html>"""


def test_merge_batches_stitches_sentences_and_updates_timeline(temp_lecture_project, monkeypatch):
    proj_file = temp_lecture_project
    monkeypatch.setattr(
        "lecture_illustrator.scene_author.call_llm_api",
        lambda *args, **kwargs: f"```html\n{CLEAN_HTML}\n```",
    )
    # Giả lập render video preview để test chạy siêu tốc (dưới 1 giây)
    preview_mp4 = proj_file.parent / "scenes" / "batch_001_combined.mp4"
    preview_mp4.touch()
    monkeypatch.setattr(
        "lecture_illustrator.visual_renderer.render_single_batch_complete",
        lambda **kwargs: (preview_mp4, "test_fingerprint"),
    )

    args = argparse.Namespace(
        project_file=str(proj_file),
        workspace=str(proj_file.parent),
        batch_id="batch_001",
        merge_with_id="batch_002",
        feedback="Gộp cảnh 1 và 2",
        html_author_api_key=None,
        html_author_model=None,
        html_author_base_url=None,
        api_key=None,
        model=None,
        base_url=None,
    )

    ret = run_merge_batches_flow(args)
    assert ret == 0

    # Đọc lại project đã lưu
    updated_data = json.loads(proj_file.read_text(encoding="utf-8"))
    updated_project = LectureProject.from_dict(updated_data)

    # 1. Số lượng batch giảm từ 3 xuống 2
    assert len(updated_project.batches) == 2
    b1 = updated_project.batches[0]
    b3 = updated_project.batches[1]

    assert b1.id == "batch_001"
    assert b3.id == "batch_003"  # ID batch 3 được giữ nguyên

    # 2. Câu dở dang ở cuối batch 1 và đầu batch 2 được khâu thành 1 câu duy nhất
    # Ban đầu b1 có 2 câu, b2 có 1 câu -> tổng 3 câu nhưng câu 2 và 3 khâu lại -> còn đúng 2 câu
    assert len(b1.sentences) == 2
    assert b1.sentences[0]["text"] == "Khái niệm đầu tiên."
    assert "Cuối cùng, vì LLM có thể dùng để tạo câu trả lời," in b1.sentences[1]["text"]
    assert "bạn sẽ học cách đưa kết quả tìm kiếm vào LLM." in b1.sentences[1]["text"]

    # 3. Timeline được tính toán lại chính xác
    assert len(b1.step_starts) == 2
    assert b1.step_starts[0] == 1.2
    assert b1.scene_duration > 0
    assert b1.end_sec == round(b1.start_sec + b1.scene_duration, 3)

    # 4. Batch 3 được tịnh tiến mốc thời gian liền mạch
    assert b3.start_sec == b1.end_sec

    # 5. Trạng thái scene cho batch 1 được đặt về authored (Instant Merge)
    html_file = proj_file.parent / "scenes" / "batch_001.html"
    assert b1.scene.get("mode") == "authored"
    assert Path(b1.scene.get("html_path", "")).name == html_file.name
