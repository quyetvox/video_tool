from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from lecture_illustrator.models import LectureProjectConfig, LectureBatch
from lecture_illustrator.visual_renderer import compute_batch_fingerprint


class TestSmartResumeAIAuthored(unittest.TestCase):
    def test_config_ai_authored_fields(self):
        cfg = LectureProjectConfig(
            aspect_ratio="9:16",
            ai_authored=True,
            html_author_model="gemma4:31b-cloud",
            html_author_base_url="http://localhost:11434",
            html_author_api_key="secret",
        )
        d = cfg.to_dict()
        self.assertTrue(d["ai_authored"])
        self.assertEqual(d["aspect_ratio"], "9:16")
        self.assertEqual(d["html_author_model"], "gemma4:31b-cloud")
        self.assertEqual(d["html_author_base_url"], "http://localhost:11434")
        self.assertEqual(d["html_author_api_key"], "secret")

        restored = LectureProjectConfig.from_dict(d)
        self.assertTrue(restored.ai_authored)
        self.assertEqual(restored.aspect_ratio, "9:16")
        self.assertEqual(restored.html_author_model, "gemma4:31b-cloud")
        self.assertEqual(restored.html_author_base_url, "http://localhost:11434")
        self.assertEqual(restored.html_author_api_key, "secret")

    def test_fingerprint_changes_with_html_content(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            html_file = Path(tmpdir) / "scene_001.html"
            html_file.write_text("<html><body>v1</body></html>", encoding="utf-8")

            batch = LectureBatch(
                id="batch_001",
                start_sec=0.0,
                end_sec=5.0,
                transcript_original="Test",
                sentences=[{"text": "Câu 1", "audio_file": "s_0000.mp3"}],
                scene={"mode": "authored", "html_path": str(html_file), "title": "Test"},
                step_starts=[0.0],
                scene_duration=5.0,
            )
            cfg_16_9 = LectureProjectConfig(aspect_ratio="16:9")
            cfg_9_16 = LectureProjectConfig(aspect_ratio="9:16")

            h1 = compute_batch_fingerprint(batch, cfg_16_9)
            h_portrait = compute_batch_fingerprint(batch, cfg_9_16)
            self.assertNotEqual(h1, h_portrait, "Đổi aspect_ratio phải thay đổi fingerprint")

            # Cập nhật nội dung HTML
            html_file.write_text("<html><body>v2 with changes</body></html>", encoding="utf-8")
            h2 = compute_batch_fingerprint(batch, cfg_16_9)
            self.assertNotEqual(h1, h2, "Đổi nội dung HTML authored phải thay đổi fingerprint")


if __name__ == "__main__":
    unittest.main()
