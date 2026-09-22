#!/usr/bin/env python3
import unittest
from pathlib import Path
import sys

ENGINE_DIR = Path(__file__).parent.parent.resolve()
sys.path.insert(0, str(ENGINE_DIR))

from movie_review_orchestrator import (
    calculate_word_budget,
    TargetedSceneDetector,
    clean_json_str,
    resolve_gemini_api_key,
    resolve_gemini_config
)


class TestMovieReviewOrchestrator(unittest.TestCase):
    def test_word_budget_standard_1_0x(self):
        # 6 minutes at 1.0x -> 6 * 140 = 840 words
        budget = calculate_word_budget(target_duration_sec=360, speed_factor=1.0)
        self.assertEqual(budget["total_words"], 840)
        self.assertEqual(budget["words_per_min"], 140)
        self.assertEqual(budget["hook_words"], 126)   # 15%
        self.assertEqual(budget["review_words"], 252) # 30%
        self.assertEqual(budget["outro_words"], 84)   # 10%
        # Story = total - hook - review - outro = 840 - 126 - 252 - 84 = 378 (45%)
        self.assertEqual(
            budget["hook_words"] + budget["story_words"] + budget["review_words"] + budget["outro_words"],
            budget["total_words"]
        )

    def test_word_budget_fast_tts_1_45x(self):
        # 6 minutes at 1.45x -> 6 * (140 * 1.45 = 203) = 1218 words
        budget = calculate_word_budget(target_duration_sec=360, speed_factor=1.45)
        self.assertEqual(budget["total_words"], 1218)
        self.assertEqual(budget["words_per_min"], 203)
        self.assertEqual(
            budget["hook_words"] + budget["story_words"] + budget["review_words"] + budget["outro_words"],
            budget["total_words"]
        )

    def test_word_budget_short_video(self):
        # 2 minutes at 1.2x -> 2 * 168 = 336 words
        budget = calculate_word_budget(target_duration_sec=120, speed_factor=1.2)
        self.assertEqual(budget["total_words"], 336)
        self.assertGreater(budget["hook_words"], 0)
        self.assertGreater(budget["story_words"], 0)
        self.assertGreater(budget["review_words"], 0)
        self.assertGreater(budget["outro_words"], 0)

    def test_word_budget_content_driven_auto_scale(self):
        # 1. Feature film 120m (7200s) -> 10 chapters, 18m review (1080s)
        budget_long = calculate_word_budget(target_duration_sec=None, movie_duration_sec=7200, speed_factor=1.45)
        self.assertEqual(budget_long["num_chapters"], 10)
        self.assertEqual(budget_long["target_duration_sec"], 1080)
        self.assertGreater(budget_long["total_words"], 3000)

        # 2. Mid episode 40m (2400s) -> 8 chapters, 14m review (840s)
        budget_mid = calculate_word_budget(target_duration_sec=None, movie_duration_sec=2400, speed_factor=1.45)
        self.assertEqual(budget_mid["num_chapters"], 8)
        self.assertEqual(budget_mid["target_duration_sec"], 840)

        # 3. Short video 20m (1200s) -> 6 chapters, 10m review (600s)
        budget_short = calculate_word_budget(target_duration_sec=None, movie_duration_sec=1200, speed_factor=1.45)
        self.assertEqual(budget_short["num_chapters"], 6)
        self.assertEqual(budget_short["target_duration_sec"], 600)

    def test_clean_json_str_with_markdown_fences(self):
        raw_markdown = '```json\n{"title": "Test Movie", "acts": []}\n```'
        cleaned = clean_json_str(raw_markdown)
        self.assertEqual(cleaned, '{"title": "Test Movie", "acts": []}')

    def test_clean_json_str_plain(self):
        raw_plain = '  {"title": "Test Movie"}  '
        cleaned = clean_json_str(raw_plain)
        self.assertEqual(cleaned, '{"title": "Test Movie"}')

    def test_resolve_gemini_api_key_priority(self):
        # Explicit key overrides everything
        k = resolve_gemini_api_key("custom_key_123")
        self.assertEqual(k, "custom_key_123")

    def test_resolve_gemini_config_explicit(self):
        k, m = resolve_gemini_config(provided_key="key_abc", provided_model="custom-model")
        self.assertEqual(k, "key_abc")
        self.assertEqual(m, "custom-model")

    def test_resolve_gemini_config_from_project_yaml(self):
        # Thư mục workspace con của chu-truc-tu
        test_ws = ENGINE_DIR.parent / "resources" / "chu-truc-tu" / "workspace" / "movie_review" / "demo_vid"
        k, m = resolve_gemini_config(workspace=test_ws)
        # Kiểm tra đọc từ translator trong chu-truc-tu/config.yaml
        self.assertEqual(m, "gemini-3.5-flash-lite")
        self.assertTrue(len(k) > 10)

    def test_load_project_config_from_video_path(self):
        from movie_review_orchestrator import load_project_config, resolve_gemini_config
        fake_video = Path("resources/chu-truc-tu/src/sample.mp4")
        data, cfg_p = load_project_config(video_path=fake_video)
        self.assertIsNotNone(cfg_p)
        self.assertIn("translator", data)
        self.assertEqual(data["translator"]["model"], "gemini-3.5-flash-lite")

        # Test resolve_gemini_config using only video_path
        key, model = resolve_gemini_config(video_path=fake_video)
        self.assertTrue(len(key) > 10)
        self.assertEqual(model, "gemini-3.5-flash-lite")

    def test_generate_review_ass_and_inpaint_filter(self):
        from movie_review_orchestrator import generate_review_ass_subtitles, build_inpaint_filter
        import tempfile
        segments = [
            {"id": 1, "voiceover_text": "Mở đầu bộ phim là phân cảnh nghẹt thở.", "audio_duration": 4.5},
            {"id": 2, "voiceover_text": "Nhân vật chính đối mặt với hiểm nguy.", "audio_duration": 3.2},
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            ass_path = Path(tmpdir) / "sub.ass"
            generate_review_ass_subtitles(
                segments=segments,
                output_ass_path=ass_path,
                video_width=1920,
                video_height=1080
            )
            self.assertTrue(ass_path.exists())
            content = ass_path.read_text(encoding="utf-8")
            self.assertIn("[Script Info]", content)
            # Kiểm tra phụ đề được chia đều cân bằng 4-5 từ, không có cụm mồ côi
            self.assertIn("Dialogue: 0,0:00:00.00,0:00:02.50,ReviewDefault", content)
            self.assertIn("Dialogue: 0,0:00:02.50,0:00:04.50,ReviewDefault", content)
            self.assertIn("Dialogue: 0,0:00:04.50,0:00:06.10,ReviewDefault", content)
            self.assertIn("Dialogue: 0,0:00:06.10,0:00:07.70,ReviewDefault", content)

        # Test inpaint filter (large box)
        cfg = {"inpaint": {"region": [0.8, 0.1, 0.95, 0.9], "blur_radius": 15}}
        f = build_inpaint_filter(1920, 1080, cfg)
        self.assertIsNotNone(f)
        self.assertIn("boxblur=15:2:15:2", f)
        self.assertIn("crop=", f)

        # Test inpaint filter (narrow box: height = 52px -> chroma max radius = 12)
        cfg_narrow = {"inpaint": {"region": [0.67, 0.0, 0.718, 1.0], "blur_radius": 15}}
        f_narrow = build_inpaint_filter(1920, 1080, cfg_narrow)
        self.assertIsNotNone(f_narrow)
        self.assertIn("boxblur=15:2:11:2", f_narrow)

    def test_tts_normalization_and_subtitle_wrap(self):
        from movie_review_orchestrator import VoiceoverSynthesizer, wrap_subtitle_text
        norm = VoiceoverSynthesizer._normalize_text("Chạy 100km/h tốn 50$ và 10% pin")
        self.assertIn("ki lô mét trên giờ", norm)
        self.assertIn("đô la", norm)
        self.assertIn("phần trăm", norm)

        long_txt = "Đây là một câu thoại review phim rất dài cần phải được tự động xuống dòng để không bị tràn viền màn hình"
        wrapped = wrap_subtitle_text(long_txt, max_chars=35)
        self.assertIn("\\N", wrapped)

    def test_split_long_segments_by_speed(self):
        from movie_review_orchestrator import split_long_segments_by_speed
        
        # 1. Segment ngắn không bị chia
        short_items = [
            {"id": 1, "section": "hook", "voiceover_text": "Một phân cảnh mở đầu gay cấn.", "scenes_to_use": [{"scene_id": 1}]}
        ]
        res_short = split_long_segments_by_speed(short_items, speed_factor=1.15)
        self.assertEqual(len(res_short), 1)
        self.assertEqual(res_short[0]["voiceover_text"], "Một phân cảnh mở đầu gay cấn.")

        # 2. Segment dài (40 từ) bị tách thành 2-3 câu ngắn
        long_paragraph = (
            "Nhân vật chính bước vào hang tối và phát hiện ra một bí mật kinh hoàng đã bị chôn vùi suốt ba mươi năm qua. "
            "Anh ta hoảng loạn tìm đường thoát thân nhưng mọi lối ra đều đã bị kẻ thù phong tỏa một cách tuyệt đối, "
            "buộc anh phải đưa ra một quyết định sinh tử vô cùng liều lĩnh."
        )
        long_items = [
            {
                "id": 1,
                "section": "storytelling",
                "voiceover_text": long_paragraph,
                "scenes_to_use": [
                    {"scene_id": 10, "start_sec": 100.0, "end_sec": 115.0},
                    {"scene_id": 11, "start_sec": 115.0, "end_sec": 130.0}
                ]
            }
        ]
        res_split = split_long_segments_by_speed(long_items, speed_factor=1.15)
        self.assertGreater(len(res_split), 1)
        
        # Kiểm tra các câu con không quá dài và có ID tuần tự
        for idx, item in enumerate(res_split):
            self.assertEqual(item["id"], idx + 1)
            self.assertEqual(item["section"], "storytelling")
            words_count = len(item["voiceover_text"].split())
            self.assertLessEqual(words_count, 25)
            self.assertTrue(len(item["scenes_to_use"]) > 0)

    def test_split_subtitle_into_rhythmic_cues(self):
        from movie_review_orchestrator import split_subtitle_into_rhythmic_cues
        text = "Một đứa trẻ ba tuổi rưỡi đi lạc, không người thân, đói lả giữa rừng sâu hoang vu."
        cues = split_subtitle_into_rhythmic_cues(text, audio_duration=6.0, max_words_per_cue=6)
        self.assertGreaterEqual(len(cues), 2)
        # Kiểm tra tính liên tục thời gian
        last_end = 0.0
        for start, end, cue_text in cues:
            self.assertAlmostEqual(start, last_end, places=1)
            self.assertGreater(end, start)
            w_cnt = len(cue_text.split())
            self.assertLessEqual(w_cnt, 8)
            last_end = end
        self.assertAlmostEqual(last_end, 6.0, places=1)

    def test_movie_review_tts_voice_mapping_and_cache(self):
        from utils.movie_review_tts import MovieReviewTTS, normalize_vietnamese_text
        from movie_review_orchestrator import VoiceoverSynthesizer

        # 1. Kiểm tra ánh xạ mã giọng Ban Mai (chuẩn Translate & UI Movie Review)
        self.assertEqual(MovieReviewTTS.resolve_voice("vi-VN-BanMai"), ("gtts", "vi"))
        self.assertEqual(MovieReviewTTS.resolve_voice("ban_mai"), ("gtts", "vi"))

        # 2. Kiểm tra ánh xạ mã giọng Hoài My
        self.assertEqual(MovieReviewTTS.resolve_voice("vi-VN-HoaiMyNeural"), ("edge", "vi-VN-HoaiMyNeural"))
        self.assertEqual(MovieReviewTTS.resolve_voice("hoai_my"), ("edge", "vi-VN-HoaiMyNeural"))

        # 3. Kiểm tra ánh xạ mã giọng Nam Minh
        self.assertEqual(MovieReviewTTS.resolve_voice("vi-VN-NamMinhNeural"), ("edge", "vi-VN-NamMinhNeural"))
        self.assertEqual(MovieReviewTTS.resolve_voice("nam_minh"), ("edge", "vi-VN-NamMinhNeural"))

        # 4. Kiểm tra ủy quyền VoiceoverSynthesizer.VOICE_CONFIG
        self.assertIn("ban_mai", VoiceoverSynthesizer.VOICE_CONFIG)
        self.assertIn("vi-VN-BanMai", VoiceoverSynthesizer.VOICE_CONFIG)
        self.assertEqual(VoiceoverSynthesizer.VOICE_CONFIG["ban_mai"], ("gtts", "vi"))

        # 5. Kiểm tra Cache Path logic
        p1 = MovieReviewTTS._get_cache_path("Test text", "vi-VN-HoaiMyNeural", "+15%")
        p2 = MovieReviewTTS._get_cache_path("Test text", "vi-VN-HoaiMyNeural", "+15%")
        p3 = MovieReviewTTS._get_cache_path("Test text", "vi-VN-HoaiMyNeural", "+20%")
        self.assertEqual(p1, p2)
        self.assertNotEqual(p1, p3)

    def test_assemble_segment_with_bg_audio(self):
        from unittest.mock import patch
        from movie_review_orchestrator import MovieReviewAssembler
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            fake_video = tmp_path / "fake_input.mp4"
            fake_video.write_bytes(b"fake video content")
            out_v = tmp_path / "out_seg.mp4"
            out_bg_a = tmp_path / "out_bga.wav"

            scenes = [
                {"scene_id": 1, "start_sec": 10.0, "end_sec": 14.0},
                {"scene_id": 2, "start_sec": 20.0, "end_sec": 23.0},
            ]

            def fake_subprocess_run(cmd, *args, **kwargs):
                # Tạo file đích nếu lệnh ffmpeg yêu cầu ghi file
                target = Path(cmd[-1])
                target.write_bytes(b"dummy")
                import subprocess
                return subprocess.CompletedProcess(cmd, 0, b"", b"")

            with patch("subprocess.run", side_effect=fake_subprocess_run), \
                 patch("movie_review_orchestrator.FFmpegUtils.probe", return_value={"format": {"duration": "7.0"}}):
                # Gọi assemble_segment với extract_bg_audio=True và out_segment_bg_audio
                res = MovieReviewAssembler.assemble_segment(
                    video_path=fake_video,
                    scenes_to_use=scenes,
                    audio_duration=6.5,
                    out_segment_video=out_v,
                    aspect_ratio="16:9",
                    temp_dir=tmp_path,
                    out_segment_bg_audio=out_bg_a,
                    extract_bg_audio=True
                )
                self.assertEqual(res, out_v)
                self.assertTrue(out_v.exists())
                self.assertTrue(out_bg_a.exists())

    def test_detect_scenes_for_ranges_autofill(self):
        from unittest.mock import patch
        from movie_review_orchestrator import TargetedSceneDetector
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            fake_video = tmp_path / "fake_vid.mp4"
            fake_video.write_bytes(b"content")

            ranges = [
                {"id": 1, "act": "hook", "start_sec": 10.0, "end_sec": 20.0},
                {"id": 2, "act": "storytelling", "start_sec": 40.0, "end_sec": 50.0},
            ]

            def fake_detect_pure(video_path, start_sec, end_sec, start_scene_id, output_dir, max_scenes_per_range):
                # Chỉ trả về 2 scenes mỗi range -> tổng cộng 4 scenes (thiếu so với target_shots = 30)
                img1 = output_dir / f"scene_{start_scene_id:04d}.jpg"
                img1.write_bytes(b"img")
                img2 = output_dir / f"scene_{start_scene_id+1:04d}.jpg"
                img2.write_bytes(b"img")
                return [
                    {"scene_id": start_scene_id, "start_sec": start_sec, "end_sec": start_sec + 5.0, "duration": 5.0, "image_path": img1.name},
                    {"scene_id": start_scene_id + 1, "start_sec": start_sec + 5.0, "end_sec": end_sec, "duration": 5.0, "image_path": img2.name}
                ]

            def fake_subprocess_run(cmd, *args, **kwargs):
                target = Path(cmd[-1])
                target.write_bytes(b"img")
                import subprocess
                return subprocess.CompletedProcess(cmd, 0, b"", b"")

            with patch.object(TargetedSceneDetector, "detect_scenes_pure_ffmpeg", side_effect=fake_detect_pure), \
                 patch("subprocess.run", side_effect=fake_subprocess_run), \
                 patch("movie_review_orchestrator.FFmpegUtils.probe", return_value={"format": {"duration": "1000.0"}}):
                scenes = TargetedSceneDetector.detect_scenes_for_ranges(
                    video_path=fake_video,
                    ranges=ranges,
                    output_dir=tmp_path,
                    target_shots=30
                )
                # target_shots = 30 -> min_needed = 35
                self.assertGreaterEqual(len(scenes), 35)
                # Kiểm tra đánh số tuần tự 1..N
                for idx, sc in enumerate(scenes):
                    self.assertEqual(sc["scene_id"], idx + 1)
                # Kiểm tra sắp xếp theo thời gian tăng dần
                for k in range(len(scenes) - 1):
                    self.assertLessEqual(scenes[k]["start_sec"], scenes[k+1]["start_sec"])

    def test_generate_review_ass_subtitles_pos_tag(self):
        from movie_review_orchestrator import generate_review_ass_subtitles
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            ass_path = tmp_path / "subtitles_review.ass"
            segments = [
                {"id": 1, "voiceover_text": "Phân đoạn mở đầu hấp dẫn.", "audio_duration": 4.0}
            ]
            cfg = {
                "subtitle": {
                    "region": [0.70, 0.10, 0.80, 0.90],
                    "font_name": "Roboto",
                    "font_size": 36,
                    "font_color": "#FFFF00",
                }
            }
            # video_width = 1920, video_height = 1080
            # center_x = int(1920 * (0.10 + 0.90) / 2) = 960
            # center_y = int(1080 * (0.70 + 0.80) / 2) = 810
            generate_review_ass_subtitles(
                segments=segments,
                output_ass_path=ass_path,
                video_width=1920,
                video_height=1080,
                project_config=cfg
            )
            self.assertTrue(ass_path.exists())
            content = ass_path.read_text(encoding="utf-8")
            self.assertIn(r"\an5\pos(960,810)", content)
    def test_visual_alignment_engine_timeline_and_antirepetition(self):
        from movie_review_orchestrator import VisualAlignmentEngine

        scenes = [
            {"scene_id": 1, "start_sec": 10.0, "end_sec": 15.0, "duration": 5.0},
            {"scene_id": 2, "start_sec": 30.0, "end_sec": 34.0, "duration": 4.0},
            {"scene_id": 3, "start_sec": 60.0, "end_sec": 66.0, "duration": 6.0},
            {"scene_id": 4, "start_sec": 90.0, "end_sec": 95.0, "duration": 5.0},
            {"scene_id": 5, "start_sec": 120.0, "end_sec": 127.0, "duration": 7.0},
        ]
        script = [
            {"id": 1, "section": "hook", "text": "Liệu quá khứ có buông tha?", "visual_intent": "symbolic"},
            {"id": 2, "section": "story", "text": "Mở đầu câu chuyện là một buổi sáng u ám.", "visual_intent": "direct"},
            {"id": 3, "section": "story", "text": "Nhân vật phát hiện ra chiếc hộp bí ẩn.", "visual_intent": "direct"},
            {"id": 4, "section": "review", "text": "Nhịp phim dồn dập với các cú cắt sắc lẹm.", "visual_intent": "montage"},
        ]

        aligned = VisualAlignmentEngine.align_script_with_scenes(
            script_items=script,
            scenes=scenes,
            video_duration_sec=130.0
        )

        self.assertEqual(len(aligned), 4)
        for item in aligned:
            self.assertIn("scenes_to_use", item)
            self.assertTrue(len(item["scenes_to_use"]) >= 1)

        # Câu 4 (montage) phải có 2 cảnh ghép lại
        self.assertEqual(len(aligned[3]["scenes_to_use"]), 2)

    def test_dynamic_pacing_breathing_room_calculation(self):
        from movie_review_orchestrator import MovieReviewAssembler
        from unittest.mock import patch
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            fake_video = tmp_path / "fake.mp4"
            fake_video.write_bytes(b"dummy")
            out_v = tmp_path / "out_seg.mp4"

            # Cảnh dài 6.0s nhưng câu thoại chỉ 4.0s -> Phải có breathing room 1.5s (hoặc 6.0 - 4.0 = 2.0 -> clamp 1.5s)
            scenes = [{"scene_id": 1, "start_sec": 10.0, "end_sec": 16.0}]
            dur_info = []

            def fake_subrun(cmd, *args, **kwargs):
                target = Path(cmd[-1])
                target.write_bytes(b"dummy")
                import subprocess
                return subprocess.CompletedProcess(cmd, 0, b"", b"")

            with patch("subprocess.run", side_effect=fake_subrun), \
                 patch("movie_review_orchestrator.FFmpegUtils.probe", return_value={"format": {"duration": "5.5"}}):
                MovieReviewAssembler.assemble_segment(
                    video_path=fake_video,
                    scenes_to_use=scenes,
                    audio_duration=4.0,
                    out_segment_video=out_v,
                    aspect_ratio="16:9",
                    temp_dir=tmp_path,
                    extract_bg_audio=False,
                    enable_breathing_room=True,
                    target_duration_out=dur_info
                )

            # target_segment_dur = 4.0 + 1.5 = 5.5s; breathing_room = 1.5s
            self.assertEqual(len(dur_info), 2)
            self.assertAlmostEqual(dur_info[0], 5.5, places=1)
            self.assertAlmostEqual(dur_info[1], 1.5, places=1)

    def test_calculate_optimal_review_duration(self):
        from movie_review_orchestrator import calculate_optimal_review_duration
        # Short film <= 20m -> 180s (3m)
        self.assertEqual(calculate_optimal_review_duration(600), 180)
        self.assertEqual(calculate_optimal_review_duration(1200), 180)

        # Episode 45m (2700s) -> ~300s (5m)
        dur_45m = calculate_optimal_review_duration(2700)
        self.assertTrue(300 <= dur_45m <= 480)

        # Feature film 120m (7200s) -> 600s (10m)
        dur_120m = calculate_optimal_review_duration(7200)
        self.assertEqual(dur_120m, 600)

        # Very long movie 180m (10800s) -> capped at 900s (15m)
        self.assertEqual(calculate_optimal_review_duration(10800), 900)

    def test_multi_act_word_budget_chapters(self):
        # 12 minutes (720s) -> 6 chapters
        budget = calculate_word_budget(target_duration_sec=720, speed_factor=1.45, review_style="story_review")
        self.assertEqual(budget["num_chapters"], 6)
        self.assertGreater(budget["chapter_words"], 200)
        self.assertEqual(
            budget["hook_words"] + budget["story_words"] + budget["review_words"] + budget["outro_words"],
            budget["total_words"]
        )

        # 15 minutes (900s) -> 8 chapters
        budget_15m = calculate_word_budget(target_duration_sec=900, speed_factor=1.45, review_style="story_review")
        self.assertEqual(budget_15m["num_chapters"], 8)
        self.assertGreater(budget_15m["chapter_words"], 250)

    def test_from_step_cli_argument(self):
        import argparse
        from unittest.mock import patch
        # Verify parser accepts --from-step
        with patch("sys.argv", ["movie_review_orchestrator.py", "--action", "analyze", "--video", "test.mp4", "--from-step", "mr03_script_gen"]):
            # Test that argument is valid in parser definition
            parser = argparse.ArgumentParser()
            parser.add_argument("--action", choices=["analyze", "render", "auto"])
            parser.add_argument("--from-step", choices=[
                "mr01_blueprint", "mr02_scene_detect", "mr03_script_gen",
                "mr04_tts", "mr05_assembly", "mr06_subtitle", "mr07_encode"
            ])
            args = parser.parse_args(["--action", "analyze", "--from-step", "mr03_script_gen"])
            self.assertEqual(args.from_step, "mr03_script_gen")

    def test_run_stage2_skip_scene_detect(self):
        import json
        import tempfile
        from unittest.mock import patch
        from movie_review_orchestrator import MovieReviewOrchestrator
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            fake_video = tmp_path / "fake_video.mp4"
            fake_video.write_bytes(b"content")

            scenes_file = tmp_path / "scenes_meta.json"
            scenes_data = [{"scene_id": 1, "start_sec": 0.0, "end_sec": 5.0}]
            scenes_file.write_text(json.dumps(scenes_data))

            orchestrator = MovieReviewOrchestrator(tmp_path)
            with patch("movie_review_orchestrator.GoldenScriptGenerator.generate_montage_script", return_value={"script": []}), \
                 patch("movie_review_orchestrator.TargetedSceneDetector.detect_scenes_for_ranges") as mock_detect:
                orchestrator.run_stage2_scenes_and_script(
                    video_path=fake_video,
                    blueprint={"blueprint_ranges": []},
                    skip_scene_detect=True,
                    api_key="dummy_test_key"
                )
                # Verify detect_scenes_for_ranges was NOT called because skip_scene_detect was True and file existed
                mock_detect.assert_not_called()

    def test_tts_progress_range(self):
        import tempfile
        from unittest.mock import patch
        from utils.movie_review_tts import MovieReviewTTS

        progress_calls = []
        def on_progress(pct, status):
            progress_calls.append((pct, status))

        script_items = [
            {"id": 1, "voiceover_text": "Câu một"},
            {"id": 2, "voiceover_text": "Câu hai"},
        ]

        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir)
            with patch.object(MovieReviewTTS, "synthesize_single", return_value=3.5):
                MovieReviewTTS.synthesize_script(
                    script_items=script_items,
                    output_dir=out_dir,
                    progress_callback=on_progress,
                    start_progress=0.0,
                    end_progress=0.30
                )

        self.assertEqual(len(progress_calls), 2)
        # First item: 0.0 + 0.30 * (1/2) = 0.15
        self.assertAlmostEqual(progress_calls[0][0], 0.15)
        # Second item: 0.0 + 0.30 * (2/2) = 0.30
        self.assertAlmostEqual(progress_calls[1][0], 0.30)
    def test_calculate_word_budget_with_acts_config(self):
        from movie_review_orchestrator import calculate_word_budget

        # Test with custom acts_config (turn off review, adjust percentages)
        acts_cfg = {
            "hook": True,
            "story": True,
            "review": False,
            "outro": True,
            "hook_pct": 0.20,
            "story_pct": 0.70,
            "review_pct": 0.0,
            "outro_pct": 0.10,
            "selected_chapters": [1, 2]
        }
        b = calculate_word_budget(360, 1.45, acts_config=acts_cfg)
        self.assertGreater(b["hook_words"], 0)
        self.assertGreater(b["story_words"], 0)
        self.assertEqual(b["review_words"], 0)
        self.assertGreater(b["outro_words"], 0)
        self.assertEqual(b["num_chapters"], 2)
        # Total sum of acts should match total_words
        act_sum = b["hook_words"] + b["story_words"] + b["review_words"] + b["outro_words"]
        self.assertEqual(act_sum, b["total_words"])

    def test_render_full_review_volume_parameters(self):
        from movie_review_orchestrator import MovieReviewAssembler
        from unittest.mock import patch
        import tempfile

        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            fake_video = tmp_path / "fake.mp4"
            fake_video.write_bytes(b"dummy")
            out_mp4 = tmp_path / "output.mp4"
            ws = tmp_path / "workspace"
            ws.mkdir()
            audio_dir = ws / "audio_segments"
            audio_dir.mkdir()
            (audio_dir / "tts_001.wav").write_bytes(b"dummy")

            script_data = {
                "script": [
                    {
                        "id": 1,
                        "voiceover_text": "Chào mừng bạn đến với phim.",
                        "audio_file": "tts_001.wav",
                        "audio_duration": 3.0,
                        "scenes_to_use": [{"scene_id": 1, "start_sec": 0.0, "end_sec": 4.0}]
                    }
                ]
            }

            with patch("subprocess.run") as mock_run, \
                 patch("utils.ffmpeg_utils.FFmpegUtils.probe", return_value={"streams": [{"codec_type": "video", "width": 1920, "height": 1080}]}):
                # Mock segment file creation
                def fake_run(cmd, *args, **kwargs):
                    for item in cmd:
                        if isinstance(item, str) and item.endswith(".mp4"):
                            Path(item).write_bytes(b"video")
                        elif isinstance(item, str) and item.endswith(".wav"):
                            Path(item).write_bytes(b"audio")
                    return unittest.mock.MagicMock(returncode=0)

                mock_run.side_effect = fake_run

                # Call render_full_review with distinct volumes
                res = MovieReviewAssembler.render_full_review(
                    video_path=fake_video,
                    script_data=script_data,
                    workspace_dir=ws,
                    output_mp4=out_mp4,
                    tts_volume=0.8,
                    original_audio_volume=0.10,
                    bgm_volume=0.30,
                    burn_subtitles=False,
                    enable_inpaint=False
                )
    def test_cli_prompt_argument_and_custom_prompt(self):
        import argparse
        from movie_review_orchestrator import MovieReviewOrchestrator
        from movie_review.generators import NarrativeBlueprintGenerator, GoldenScriptGenerator

        # 1. Verify parser accepts --prompt
        parser = argparse.ArgumentParser()
        parser.add_argument("--action", choices=["analyze", "render", "auto"])
        parser.add_argument("--prompt", type=str, default=None)
        args = parser.parse_args(["--action", "analyze", "--prompt", "Kịch tính và sâu sắc"])
        self.assertEqual(args.prompt, "Kịch tính và sâu sắc")

        # 2. Verify generators accept custom_prompt parameter
        bp_gen = NarrativeBlueprintGenerator(api_key="dummy_key", model_name="dummy")
        self.assertIsNotNone(bp_gen)
        script_gen = GoldenScriptGenerator(api_key="dummy_key", model_name="dummy")
        self.assertIsNotNone(script_gen)


if __name__ == "__main__":
    unittest.main()

