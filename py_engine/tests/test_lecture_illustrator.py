"""
Unit tests for AI Lecture Illustrator module using standard library unittest.
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

# Add py_engine to sys.path
ENGINE_DIR = Path(__file__).parent.parent.resolve()
if str(ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(ENGINE_DIR))

from lecture_illustrator.models import (
    LectureProject,
    LectureProjectConfig,
    LectureBatch,
    BatchPrompts,
    BatchActiveAsset,
)
from lecture_illustrator.knowledge_extractor import (
    group_transcript_into_semantic_batches,
    generate_fallback_prompts_for_batch,
    build_educational_analysis_prompt,
    sanitize_english_prompt,
)
from lecture_illustrator.subtitles import (
    generate_lecture_srt,
    generate_lecture_ass,
    format_ass_time,
    format_srt_time,
)
from lecture_illustrator.visual_renderer import (
    get_hardware_video_encoder,
    create_batch_audio,
    render_batch_visual,
)


class TestLectureIllustrator(unittest.TestCase):

    def test_models_serialization(self):
        cfg = LectureProjectConfig(
            source_lang="en",
            target_lang="vi",
            voice_mode="tts_dub",
            subtitle_mode="bilingual",
            enable_inpaint=True,
        )
        batch = LectureBatch(
            id="batch_001",
            start_sec=10.0,
            end_sec=25.0,
            transcript_original="Hello world",
            transcript_translated="Xin chào thế giới",
            educational_intent="DEFINITION",
            prompts=BatchPrompts(
                image_prompt="A globe in space",
                diagram_mermaid="graph TD; A-->B;",
                animation_concept="Rotating globe",
            ),
            active_asset=BatchActiveAsset(
                file_path="assets/globe.png",
                type="image",
                source="user_import",
                layout="pip",
                locked=True,
            ),
        )
        proj = LectureProject(
            project_name="test_proj",
            video_path="test.mp4",
            video_duration=120.0,
            config=cfg,
            batches=[batch],
        )

        data = proj.to_dict()
        self.assertEqual(data["project_name"], "test_proj")
        self.assertEqual(data["config"]["voice_mode"], "tts_dub")
        self.assertEqual(len(data["batches"]), 1)
        self.assertTrue(data["batches"][0]["active_asset"]["locked"])

        # Roundtrip from_dict
        restored = LectureProject.from_dict(data)
        self.assertEqual(restored.project_name, "test_proj")
        self.assertEqual(restored.batches[0].prompts.image_prompt, "A globe in space")
        self.assertEqual(restored.batches[0].active_asset.file_path, "assets/globe.png")

    def test_semantic_batch_grouping(self):
        raw_segments = [
            {"start": 0.0, "end": 4.0, "text": "Hôm nay chúng ta sẽ tìm hiểu về quang hợp."},
            {"start": 4.2, "end": 8.0, "text": "Quang hợp là một quá trình sinh học kỳ diệu."},
            {"start": 8.2, "end": 14.0, "text": "Cây xanh hấp thụ ánh sáng mặt trời để tạo ra năng lượng."},
            {"start": 14.5, "end": 22.0, "text": "Tiếp theo là giai đoạn pha sáng diễn ra ở màng thylakoid."},
        ]

        batches = group_transcript_into_semantic_batches(raw_segments, min_duration=10.0, max_duration=25.0)
        self.assertGreaterEqual(len(batches), 2)
        self.assertEqual(batches[0]["id"], "batch_001")
        self.assertEqual(batches[0]["start_sec"], 0.0)
        self.assertGreaterEqual(batches[0]["end_sec"], 10.0)

    def test_subtitle_generators(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            cfg = LectureProjectConfig(
                subtitle_mode="bilingual",
                font_name="Arial",
                font_size="24",
            )
            batches = [
                LectureBatch(
                    id="batch_001",
                    start_sec=1.5,
                    end_sec=5.8,
                    transcript_original="Photosynthesis is essential for life.",
                    transcript_translated="Quang hợp là điều thiết yếu cho sự sống.",
                )
            ]

            srt_path = tmp_path / "test.srt"
            generate_lecture_srt(batches, srt_path, cfg)
            self.assertTrue(srt_path.exists())
            srt_content = srt_path.read_text(encoding="utf-8")
            self.assertIn("00:00:01,500 --> 00:00:05,800", srt_content)
            self.assertIn("Quang hợp là điều thiết yếu", srt_content)

            ass_path = tmp_path / "test.ass"
            generate_lecture_ass(batches, ass_path, cfg)
            self.assertTrue(ass_path.exists())
            ass_content = ass_path.read_text(encoding="utf-8")
            self.assertIn("Dialogue: 0,0:00:01.50,0:00:05.80", ass_content)
            self.assertIn("\\rSecondary", ass_content)

    def test_batch_audio_and_visual_generation(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            cfg = LectureProjectConfig(
                tts_voice="ban_mai",
                tts_speed=1.15,
            )
            batch = LectureBatch(
                id="batch_001",
                start_sec=0.0,
                end_sec=5.0,
                transcript_original="Sentence one. Sentence two.",
                transcript_translated="Câu một về thực vật. Câu hai về ánh sáng.",
                scene_duration=5.0,
                step_starts=[1.0, 3.0],
                sentences=[
                    {"text": "Câu một về thực vật.", "text_orig": "Sentence one.", "duration": 1.5, "start": 1.0, "end": 2.5},
                    {"text": "Câu hai về ánh sáng.", "text_orig": "Sentence two.", "duration": 1.8, "start": 3.0, "end": 4.8},
                ],
                scene={"template": "bullet_list", "title": "Cơ chế quang hợp", "steps": [{"label": "Cây xanh"}, {"label": "Ánh sáng"}]},
            )
            out_wav = tmp_path / "test_audio.wav"
            ok = create_batch_audio(batch, tmp_path, cfg, out_wav)
            self.assertTrue(ok)
            self.assertTrue(out_wav.exists())
            self.assertGreater(out_wav.stat().st_size, 1000)

    def test_fallback_prompt_generation(self):
        raw_b = {
            "id": "batch_001",
            "transcript_original": "Giải thích quy trình hô hấp tế bào và chu trình Krebs.",
        }
        fb = generate_fallback_prompts_for_batch(raw_b)
        self.assertEqual(fb["educational_intent"], "CONCEPT")
        self.assertIn("image_prompt", fb["prompts"])
        self.assertIn("no text", fb["prompts"]["image_prompt"])
        self.assertIn("graph TD", fb["prompts"]["diagram_mermaid"])
        self.assertEqual(fb["prompts"]["code_animation"], "")  # Không có từ khóa lập trình

        # Test khi bài giảng là về lập trình
        raw_code = {
            "id": "batch_002",
            "transcript_original": "Đoạn code này sử dụng function đệ quy để giải bài toán Fibonacci.",
        }
        fb_code = generate_fallback_prompts_for_batch(raw_code)
        self.assertNotEqual(fb_code["prompts"]["code_animation"], "")
        self.assertIn("function", fb_code["prompts"]["code_animation"])
        self.assertIn("Animation Execution Cues", fb_code["prompts"]["code_animation"])

    def test_chinese_transcript_multilingual_and_clean_prompt(self):
        """Kiểm chứng transcript tiếng Trung được dịch sang Tiếng Việt và Prompt ảnh là Tiếng Anh sạch không có chữ Hán."""
        import re
        raw_chinese = {
            "id": "batch_001",
            "transcript_original": "当大多数人提及神经网络时,通常会想到以下三种情况之一 A他们是对人类大脑的人工模拟 B他们的效果好的有些出人意料",
        }
        fb = generate_fallback_prompts_for_batch(raw_chinese, target_lang="vi")
        
        # 1. Bản dịch kịch bản không được là tiếng Trung gốc, phải là tiếng Việt
        self.assertNotEqual(fb["transcript_translated"], raw_chinese["transcript_original"])
        self.assertTrue(any(word in fb["transcript_translated"].lower() for word in ["mạng", "thần kinh", "não", "người"]))

        # 2. Image prompt BẮT BUỘC là tiếng Anh và KHÔNG ĐƯỢC CHỨA bất kỳ ký tự tiếng Trung nào
        img_prompt = fb["prompts"]["image_prompt"]
        self.assertIn("Educational scientific illustration", img_prompt)
        self.assertIn("no text", img_prompt)
        has_cjk = bool(re.search(r'[\u4e00-\u9fff]', img_prompt))
        self.assertFalse(has_cjk, f"Image prompt vẫn còn chứa chữ Hán: {img_prompt}")

        # 3. Mermaid diagram nhãn phải hiển thị tiếng Việt, không chứa chữ Hán
        mermaid_code = fb["prompts"]["diagram_mermaid"]
        self.assertIn("graph TD", mermaid_code)
        self.assertFalse(bool(re.search(r'[\u4e00-\u9fff]', mermaid_code)), f"Mermaid code vẫn còn chứa chữ Hán: {mermaid_code}")

        # 4. Kiểm thử hàm sanitize_english_prompt độc lập
        dirty_prompt = "A diagram of 神经网络 and deep learning"
        clean = sanitize_english_prompt(dirty_prompt)
        self.assertEqual(clean, "A diagram of and deep learning")

    def test_all_21_config_fields_full_parity(self):
        """Đảm bảo tất cả 21 trường cấu hình được lưu và nạp nguyên vẹn."""
        custom_cfg = LectureProjectConfig(
            source_lang="en",
            target_lang="vi",
            pronoun_mode="teacher_student",
            voice_mode="tts_dub",
            tts_voice="hoai_my",
            tts_speed=1.25,
            bgm_volume=0.15,
            burn_subtitles=True,
            subtitle_mode="single",
            font_name="Montserrat",
            secondary_font_name="Arial Unicode MS",
            font_size="30",
            font_color="&H0000FFFF",
            outline_color="&H00333333",
            enable_inpaint=True,
            inpaint_engine="box_color",
            inpaint_blur_radius=35,
            box_bg_color="#1e1e1e",
            box_opacity=0.92,
            inpaint_method="telea",
            inpaint_region=[0.80, 0.05, 0.95, 0.95],
            visual_layout_preset="split",
            secondary_lang="ja",
            voice_volume=0.9,
            subtitle_secondary_show=False,
            subtitle_order="secondary_top",
            secondary_font_color="&H00FFCC00",
            secondary_scale=0.85,
            video_bitrate="4000k",
            watermark_enabled=True,
            watermark_path="/path/to/logo.png",
        )

        d = custom_cfg.to_dict()
        self.assertEqual(len(d), 31, "LectureProjectConfig phải có chính xác 31 fields!")
        
        restored = LectureProjectConfig.from_dict(d)
        self.assertEqual(restored.source_lang, "en")
        self.assertEqual(restored.target_lang, "vi")
        self.assertEqual(restored.secondary_lang, "ja")
        self.assertEqual(restored.pronoun_mode, "teacher_student")
        self.assertEqual(restored.voice_mode, "tts_dub")
        self.assertEqual(restored.tts_voice, "hoai_my")
        self.assertEqual(restored.tts_speed, 1.25)
        self.assertEqual(restored.bgm_volume, 0.15)
        self.assertEqual(restored.voice_volume, 0.9)
        self.assertEqual(restored.burn_subtitles, True)
        self.assertEqual(restored.subtitle_mode, "single")
        self.assertEqual(restored.subtitle_secondary_show, False)
        self.assertEqual(restored.subtitle_order, "secondary_top")
        self.assertEqual(restored.font_name, "Montserrat")
        self.assertEqual(restored.secondary_font_name, "Arial Unicode MS")
        self.assertEqual(restored.font_size, "30")
        self.assertEqual(restored.font_color, "&H0000FFFF")
        self.assertEqual(restored.outline_color, "&H00333333")
        self.assertEqual(restored.secondary_font_color, "&H00FFCC00")
        self.assertEqual(restored.secondary_scale, 0.85)
        self.assertEqual(restored.video_bitrate, "4000k")
        self.assertEqual(restored.watermark_enabled, True)
        self.assertEqual(restored.watermark_path, "/path/to/logo.png")
        self.assertEqual(restored.enable_inpaint, True)
        self.assertEqual(restored.inpaint_engine, "box_color")
        self.assertEqual(restored.inpaint_blur_radius, 35)
        self.assertEqual(restored.box_bg_color, "#1e1e1e")
        self.assertEqual(restored.box_opacity, 0.92)
        self.assertEqual(restored.inpaint_method, "telea")
        self.assertEqual(restored.inpaint_region, [0.80, 0.05, 0.95, 0.95])
        self.assertEqual(restored.visual_layout_preset, "split")

    def test_cjk_secondary_font_auto_resolution(self):
        """Kiểm chứng phụ đề song ngữ tự động chọn font CJK chuẩn khi có ký tự tiếng Trung/Nhật/Hàn."""
        from lecture_illustrator.subtitles import resolve_secondary_font_name, has_cjk_characters, get_default_cjk_font
        self.assertTrue(has_cjk_characters("神经网络"))
        self.assertFalse(has_cjk_characters("Neural Network"))

        cfg = LectureProjectConfig(font_name="Be Vietnam Pro", subtitle_mode="bilingual")
        cjk_batches = [
            LectureBatch(
                id="batch_001",
                start_sec=0.0,
                end_sec=5.0,
                transcript_original="神经网络训练",
                transcript_translated="Huấn luyện mạng thần kinh",
            )
        ]
        resolved_font = resolve_secondary_font_name(cfg, cjk_batches)
        self.assertEqual(resolved_font, get_default_cjk_font())

        # Test sinh file ASS có style Secondary dùng font CJK
        with tempfile.TemporaryDirectory() as tmp_dir:
            ass_path = Path(tmp_dir) / "test.ass"
            generate_lecture_ass(cjk_batches, ass_path, cfg)
            content = ass_path.read_text(encoding="utf-8")
            self.assertIn("Style: Primary,Be Vietnam Pro", content)
            self.assertIn(f"Style: Secondary,{get_default_cjk_font()}", content)

    def test_reanalysis_config_inheritance(self):
        """Đảm bảo khi phân tích lại, các config tùy biến inpaint/font của người dùng không bị xóa mất."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            proj_file = tmp_path / "lecture_project.json"

            # Giả lập project đã có cấu hình tùy biến của người dùng
            custom_cfg = LectureProjectConfig(
                enable_inpaint=True,
                inpaint_engine="ffmpeg_blur",
                inpaint_blur_radius=42,
                font_name="Roboto",
                font_size="28",
                box_bg_color="#121212",
            )
            initial_proj = LectureProject(
                project_name="demo",
                video_path="demo.mp4",
                config=custom_cfg,
                batches=[],
            )
            proj_file.write_text(json.dumps(initial_proj.to_dict(), ensure_ascii=False), encoding="utf-8")

            # Đọc lại và kế thừa
            data = json.loads(proj_file.read_text(encoding="utf-8"))
            inherited_cfg = LectureProjectConfig.from_dict(data["config"])
            self.assertTrue(inherited_cfg.enable_inpaint)
            self.assertEqual(inherited_cfg.inpaint_blur_radius, 42)
            self.assertEqual(inherited_cfg.font_name, "Roboto")
            self.assertEqual(inherited_cfg.font_size, "28")
            self.assertEqual(inherited_cfg.box_bg_color, "#121212")

    def test_resolve_hardware_config_and_workers(self):
        """Kiểm tra đọc num_workers và device chính xác từ config.yaml."""
        from lecture_illustrator.common import resolve_hardware_config

        # 1. Config với num_workers = 6 và device = auto
        cfg_6 = {"app": {"num_workers": 6, "device": "auto"}}
        w, enc, args = resolve_hardware_config(cfg_6)
        self.assertEqual(w, 6)
        if sys.platform == "darwin":
            self.assertEqual(enc, "h264_videotoolbox")
            self.assertIn("-b:v", args)

        # 2. Config với device = cpu (tối ưu cho animation vector)
        cfg_cpu = {"app": {"num_workers": 8, "device": "cpu"}}
        w_cpu, enc_cpu, args_cpu = resolve_hardware_config(cfg_cpu)
        self.assertEqual(w_cpu, 8)
        self.assertEqual(enc_cpu, "libx264")
        self.assertIn("animation", args_cpu)
        self.assertIn("23", args_cpu)

        # 3. Config với device = cuda
        cfg_cuda = {"app": {"num_workers": 4, "device": "cuda"}}
        w_cuda, enc_cuda, args_cuda = resolve_hardware_config(cfg_cuda)
        self.assertEqual(w_cuda, 4)
        self.assertEqual(enc_cuda, "h264_nvenc")
        self.assertIn("1800k", args_cuda)

    def test_smart_resume_fingerprint_and_11_templates(self):
        """Kiểm chứng 11 template vẽ tay và tính toán mã băm Smart Resume."""
        from lecture_illustrator.scene_validator import KNOWN_TEMPLATES, validate_scene
        from lecture_illustrator.visual_renderer import compute_batch_fingerprint

        # 1. Đảm bảo toàn bộ 14 template đều có trong whitelist
        expected_templates = {
            "bullet_list", "title_point", "process_flow", "compare_two",
            "definition", "number_stat", "code_block",
            "network_route", "algo_array", "neural_net", "system_tree",
            "agent_workflow", "rag_pipeline", "transformer_attention",
        }
        self.assertEqual(KNOWN_TEMPLATES, expected_templates)

        # 2. Kiểm tra các file template HTML thực tế tồn tại trên đĩa
        tmpl_dir = ENGINE_DIR / "lecture_illustrator" / "templates"
        for tmpl_name in expected_templates:
            tmpl_file = tmpl_dir / f"{tmpl_name}.html"
            self.assertTrue(tmpl_file.exists(), f"Thiếu file template: {tmpl_file}")

        # 3. Kiểm thử validate_scene chấp nhận các template AI mới
        for tmpl in ["agent_workflow", "rag_pipeline", "transformer_attention", "network_route", "algo_array", "neural_net", "system_tree"]:
            validated = validate_scene({"template": tmpl, "title": "Test Title"}, ["Câu 1", "Câu 2"])
            self.assertEqual(validated["template"], tmpl)

        # 4. Kiểm thử tính ổn định của mã băm compute_batch_fingerprint
        b1 = LectureBatch(
            id="batch_001",
            start_sec=0.0,
            end_sec=5.0,
            transcript_original="Câu A Câu B",
            scene={"template": "agent_workflow", "title": "Route A to B", "steps": [{"label": "A"}, {"label": "B"}]},
            sentences=[{"text": "Câu A", "audio_file": "s_0001.mp3"}, {"text": "Câu B", "audio_file": "s_0002.mp3"}],
            step_starts=[0.0, 2.5],
            scene_duration=5.0,
        )
        hash1 = compute_batch_fingerprint(b1)
        self.assertIsInstance(hash1, str)
        self.assertEqual(len(hash1), 32)
        # Băm lại cùng dữ liệu phải ra mã hash giống nhau
        self.assertEqual(compute_batch_fingerprint(b1), hash1)

        # Thay đổi template -> hash phải đổi ngay lập tức
        b2 = LectureBatch(
            id="batch_001",
            start_sec=0.0,
            end_sec=5.0,
            transcript_original="Câu A Câu B",
            scene={"template": "rag_pipeline", "title": "Route A to B", "steps": [{"label": "A"}, {"label": "B"}]},
            sentences=[{"text": "Câu A", "audio_file": "s_0001.mp3"}, {"text": "Câu B", "audio_file": "s_0002.mp3"}],
            step_starts=[0.0, 2.5],
            scene_duration=5.0,
        )
        self.assertNotEqual(compute_batch_fingerprint(b2), hash1)

    def test_semantic_classifier_and_anti_repetition_guard(self):
        """Kiểm chứng bộ phân loại từ khóa Semantic và bộ chống lặp Anti-Repetition Guard."""
        from lecture_illustrator.scene_planner import classify_template_by_keywords, apply_anti_repetition_guard

        # 1. Phân loại từ khóa Tier 1
        self.assertEqual(classify_template_by_keywords("Vòng lặp ReAct của AI Agent tự trị"), "agent_workflow")
        self.assertEqual(classify_template_by_keywords("Kiến trúc RAG truy vấn vector database"), "rag_pipeline")
        self.assertEqual(classify_template_by_keywords("Cơ chế Self-Attention tính tích QKV softmax"), "transformer_attention")
        self.assertEqual(classify_template_by_keywords("Duyệt mảng bằng hai con trỏ two pointers"), "algo_array")
        self.assertEqual(classify_template_by_keywords("So sánh đối chiếu ưu nhược điểm"), "compare_two")

        # 2. Bộ chống lặp Anti-Repetition Guard Tier 3
        scenes = [
            {"template": "agent_workflow"},
            {"template": "agent_workflow"},
            {"template": "agent_workflow"}, # Lặp lần 3 -> phải luân chuyển
        ]
        guarded = apply_anti_repetition_guard(scenes)
        self.assertNotEqual(guarded[2]["template"], "agent_workflow")
        self.assertIn(guarded[2]["template"], ["rag_pipeline", "transformer_attention", "neural_net"])

    def test_create_batch_audio_uses_global_sentence_indices(self):
        """Đảm bảo batch 2 không nạp lại âm thanh s_0000.mp3 của batch 1."""
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as td:
            ws = Path(td)
            tts_dir = ws / "tts"
            tts_dir.mkdir(parents=True, exist_ok=True)
            # Tạo các file mp3 giả lập cho batch 1 (0..2) và batch 2 (3..5)
            for i in range(6):
                (tts_dir / f"s_{i:04d}.mp3").write_bytes(b"dummy_mp3_content" * 50)

            batch_2 = LectureBatch(
                id="batch_002",
                start_sec=10.0,
                end_sec=20.0,
                transcript_original="Orig text batch 2",
                transcript_translated="Trans text batch 2",
                sentences=[
                    {"text": "Câu 4 của video", "start": 10.0, "end": 13.0},
                    {"text": "Câu 5 của video", "start": 13.0, "end": 16.0},
                    {"text": "Câu 6 của video", "start": 16.0, "end": 20.0},
                ],
                step_starts=[0.0, 3.0, 6.0],
                scene_duration=10.0,
            )

            out_wav = ws / "b2.wav"
            cfg = LectureProjectConfig()

            # Mock subprocess.run để kiểm tra arguments truyền vào ffmpeg
            with patch("subprocess.run") as mock_run:
                mock_run.return_value.returncode = 0
                out_wav.touch()  # giả lập ffmpeg sinh file thành công
                # Gọi với sentence_offset = 3 (vì batch 1 có 3 câu)
                create_batch_audio(batch_2, ws, cfg, out_wav, sentence_offset=3)

                self.assertTrue(mock_run.called)
                called_cmd = mock_run.call_args[0][0]
                # Kiểm tra ffmpeg input phải là s_0003, s_0004, s_0005 chứ KHÔNG ĐƯỢC là s_0000, s_0001, s_0002!
                cmd_str = " ".join(called_cmd)
                self.assertIn("s_0003.mp3", cmd_str)
                self.assertIn("s_0004.mp3", cmd_str)
                self.assertIn("s_0005.mp3", cmd_str)
                self.assertNotIn("s_0000.mp3", cmd_str)

    def test_call_llm_api_filters_ssh_key_and_resolves_ollama(self):
        """Kiểm tra call_llm_api lọc sạch SSH key và tự động tạo endpoint /v1/chat/completions cho Ollama."""
        from unittest.mock import patch, MagicMock
        from lecture_illustrator.knowledge_extractor import call_llm_api

        # 1. Test lọc SSH key và không crash control characters
        with patch("urllib.request.urlopen") as mock_url:
            mock_resp = MagicMock()
            mock_resp.read.return_value = json.dumps({
                "choices": [{"message": {"content": "Dịch thành công"}}]
            }).encode("utf-8")
            mock_resp.__enter__.return_value = mock_resp
            mock_url.return_value = mock_resp

            ssh_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDQfgnMBVvSBiZ1cq6/Rgjv/UciaE4yd3CzoLl4yCGSE"
            res = call_llm_api(
                prompt="test prompt",
                api_key=ssh_key,
                model_name="gemma4:31b-cloud",
                base_url="http://localhost:11434",
            )
            self.assertEqual(res, "Dịch thành công")

            # Kiểm tra URL được gọi là http://localhost:11434/v1/chat/completions
            req_called = mock_url.call_args[0][0]
            self.assertEqual(req_called.full_url, "http://localhost:11434/v1/chat/completions")
            # Headers không được truyền Bearer chứa khoảng trắng SSH key
            self.assertNotIn("Authorization", req_called.headers)

    def test_call_llm_api_supports_ollama_without_api_key(self):
        """Kiểm tra call_llm_api hoạt động với Ollama local khi không có API key."""
        from unittest.mock import patch, MagicMock
        from lecture_illustrator.knowledge_extractor import call_llm_api

        with patch("urllib.request.urlopen") as mock_url:
            mock_resp = MagicMock()
            mock_resp.read.return_value = json.dumps({
                "choices": [{"message": {"content": "Ollama response"}}]
            }).encode("utf-8")
            mock_resp.__enter__.return_value = mock_resp
            mock_url.return_value = mock_resp

            res = call_llm_api(
                prompt="test prompt",
                api_key="",
                model_name="gemma4:31b-cloud",
                base_url="http://localhost:11434",
            )
            self.assertEqual(res, "Ollama response")
            req_called = mock_url.call_args[0][0]
            self.assertEqual(req_called.full_url, "http://localhost:11434/v1/chat/completions")


if __name__ == "__main__":
    unittest.main()
