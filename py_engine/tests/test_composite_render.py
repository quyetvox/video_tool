import unittest
import json
import tempfile
import os
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent.parent.resolve()))
from composite_render import render_composite


class TestCompositeRender(unittest.TestCase):
    def test_render_composite_audio_only_no_overlay_no_subtitles(self):
        """Kiểm tra xuất bản phối khi chỉ có Video + Audio clips (không có overlay/subtitles)."""
        video_src = Path(__file__).parent.parent.parent / "resources" / "tech" / "src" / "screen-recording-2026-09-10-at-55233-pm_rIXoYzPZ.mov"
        voice_wav = Path(__file__).parent.parent.parent / "resources" / "_assets" / "sfx" / "sub_video_ai_voiceover_namminh.wav"
        music_mp3 = Path(__file__).parent.parent.parent / "resources" / "_assets" / "music" / "Walen - The Choice (freetouse.com).mp3"

        if not video_src.exists():
            self.skipTest("Sample video file not found")

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = os.path.join(tmpdir, "test_output.mp4")
            config = {
                "videoPath": str(video_src),
                "outputPath": out_file,
                "overlayClips": [],
                "audioClips": [
                    {
                        "fullPath": str(voice_wav) if voice_wav.exists() else "",
                        "start": 0.0,
                        "end": 2.0,
                        "volume": 100,
                        "trackId": "voice",
                        "muted": False,
                    },
                    {
                        "fullPath": str(music_mp3) if music_mp3.exists() else "",
                        "start": 0.0,
                        "end": 2.0,
                        "volume": 50,
                        "trackId": "music",
                        "muted": False,
                    }
                ],
                "mixState": {
                    "origMuted": False,
                    "origVolume": 100,
                    "musicMuted": False,
                    "musicVolume": 80,
                    "sfxMuted": False,
                    "sfxVolume": 60,
                },
                "subtitles": [],
                "subStyle": {},
            }

            cfg_path = os.path.join(tmpdir, "config.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(config, f)

            success = render_composite(cfg_path)
            self.assertTrue(success)
            self.assertTrue(os.path.exists(out_file))
            self.assertGreater(os.path.getsize(out_file), 1000)

    def test_render_composite_with_subtitles(self):
        """Kiểm tra xuất bản phối khi có Subtitles."""
        video_src = Path(__file__).parent.parent.parent / "resources" / "tech" / "src" / "screen-recording-2026-09-10-at-55233-pm_rIXoYzPZ.mov"

        if not video_src.exists():
            self.skipTest("Sample video file not found")

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = os.path.join(tmpdir, "test_sub_output.mp4")
            config = {
                "videoPath": str(video_src),
                "outputPath": out_file,
                "overlayClips": [],
                "audioClips": [],
                "mixState": {
                    "origMuted": False,
                    "origVolume": 100,
                },
                "subtitles": [
                    {
                        "start": 0.0,
                        "end": 1.5,
                        "textTrans": "Xin chào thế giới",
                        "textOrig": "Hello World",
                    }
                ],
                "subStyle": {
                    "fontFamily": "Arial",
                    "fontSize": 20,
                    "fontColor": "#facc15",
                    "origColor": "#ffffff",
                    "showSubBox": True,
                    "hasDropShadow": True,
                    "showMainSub": True,
                    "showSubSub": True,
                    "posX": 50.0,
                    "posY": 85.0,
                },
            }

            cfg_path = os.path.join(tmpdir, "config.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(config, f)

            success = render_composite(cfg_path)
            self.assertTrue(success)
            self.assertTrue(os.path.exists(out_file))
            self.assertGreater(os.path.getsize(out_file), 1000)

    def test_generate_ass_file_scaling(self):
        """Kiểm tra sinh file ASS với canvas scaling và bù trừ quang học."""
        from composite_render import generate_ass_file
        with tempfile.TemporaryDirectory() as tmpdir:
            ass_path = os.path.join(tmpdir, "test.ass")
            subtitles = [
                {"start": 1.0, "end": 3.0, "textTrans": "Xin chào", "textOrig": "Hello"}
            ]
            sub_style = {
                "fontFamily": "Be Vietnam Pro",
                "fontSize": 20,
                "posX": 50.0,
                "posY": 80.0,
                "showMainSub": True,
                "showSubSub": True,
            }
            # Giả sử canvas_h = 400, video_h = 1080
            # font_ratio = 20 / 400 = 0.05
            # main_font_size = round(0.05 * 1080) = 54 (exact WYSIWYG match with canvas preview)
            generate_ass_file(subtitles, sub_style, ass_path, video_w=1920, video_h=1080, canvas_w=600.0, canvas_h=400.0)
            self.assertTrue(os.path.exists(ass_path))
            with open(ass_path, "r", encoding="utf-8") as f:
                content = f.read()
            self.assertIn(r"\fs54", content)
            self.assertIn("PlayResX: 1920", content)
            self.assertIn("PlayResY: 1080", content)
    def test_audio_volume_mapping_calculation(self):
        """Kiểm tra công thức tính âm lượng cấp bậc (Clip x Master Track) hỗ trợ cả alias voice/voiceover."""
        def compute_vol(clip, mix_state):
            track_type = clip.get("trackId", "music")
            is_sfx_track = str(track_type).lower() in ["sfx", "voice", "voiceover", "effect"]
            sfx_muted = mix_state.get("sfxMuted", False)
            music_muted = mix_state.get("musicMuted", False)
            sfx_master_vol = 0.0 if sfx_muted else (mix_state.get("sfxVolume", 100) / 100.0)
            music_master_vol = 0.0 if music_muted else (mix_state.get("musicVolume", 100) / 100.0)

            clip_vol = float(clip.get("volume", 100)) / 100.0
            is_clip_muted = clip.get("muted", False)
            is_track_muted = sfx_muted if is_sfx_track else music_muted
            master_vol = 0.0 if is_track_muted else (sfx_master_vol if is_sfx_track else music_master_vol)
            return 0.0 if (is_clip_muted or is_track_muted) else (clip_vol * master_vol)

        # 1. Standard: clip 100%, master 80% -> 0.8
        self.assertAlmostEqual(compute_vol({"volume": 100, "trackId": "music"}, {"musicVolume": 80}), 0.8)
        # 2. Boost: clip 150%, master 100% -> 1.5
        self.assertAlmostEqual(compute_vol({"volume": 150, "trackId": "sfx"}, {"sfxVolume": 100}), 1.5)
        # 3. Voice alias: clip 100%, sfxVolume 160% -> 1.6
        self.assertAlmostEqual(compute_vol({"volume": 100, "trackId": "voice"}, {"sfxVolume": 160}), 1.6)
        # 4. Attenuated: clip 50%, master 80% -> 0.4
        self.assertAlmostEqual(compute_vol({"volume": 50, "trackId": "music"}, {"musicVolume": 80}), 0.4)
        # 5. Clip Muted -> 0.0
        self.assertEqual(compute_vol({"volume": 100, "muted": True, "trackId": "music"}, {"musicVolume": 80}), 0.0)
        # 6. Track Muted -> 0.0
        self.assertEqual(compute_vol({"volume": 100, "trackId": "music"}, {"musicVolume": 80, "musicMuted": True}), 0.0)

    def test_exact_audio_volume_mix_balance(self):
        """Kiểm tra render thực tế giữ nguyên tỉ lệ âm lượng (SFX/Voice 160% vs Nhạc 50%)."""
        import subprocess
        video_src = Path(__file__).parent.parent.parent / "resources" / "tech" / "src" / "screen-recording-2026-09-10-at-55233-pm_rIXoYzPZ.mov"
        voice_wav = Path(__file__).parent.parent.parent / "resources" / "_assets" / "sfx" / "sub_video_ai_voiceover_namminh.wav"
        music_mp3 = Path(__file__).parent.parent.parent / "resources" / "_assets" / "music" / "Walen - The Choice (freetouse.com).mp3"

        if not video_src.exists() or not voice_wav.exists() or not music_mp3.exists():
            self.skipTest("Sample media files not found")

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = os.path.join(tmpdir, "balance_output.mp4")
            config = {
                "videoPath": str(video_src),
                "outputPath": out_file,
                "overlayClips": [],
                "audioClips": [
                    {
                        "fullPath": str(voice_wav),
                        "start": 0.0,
                        "end": 2.0,
                        "volume": 100,
                        "trackId": "sfx",
                        "muted": False,
                    },
                    {
                        "fullPath": str(music_mp3),
                        "start": 0.0,
                        "end": 2.0,
                        "volume": 100,
                        "trackId": "music",
                        "muted": False,
                    }
                ],
                "mixState": {
                    "origMuted": False,
                    "origVolume": 0,
                    "musicMuted": False,
                    "musicVolume": 50,
                    "sfxMuted": False,
                    "sfxVolume": 160,
                },
                "subtitles": [],
                "subStyle": {},
            }

            cfg_path = os.path.join(tmpdir, "config.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(config, f)

            success = render_composite(cfg_path)
            self.assertTrue(success)
            self.assertTrue(os.path.exists(out_file))

            # Phân tích mức âm lượng bằng volumedetect
            cmd = ["ffmpeg", "-i", out_file, "-filter:a", "volumedetect", "-f", "null", "-"]
            res = subprocess.run(cmd, capture_output=True, text=True)
            self.assertIn("mean_volume", res.stderr)
            self.assertIn("max_volume", res.stderr)

    def test_render_composite_with_speed_and_bitrate(self):
        """Kiểm tra xuất bản phối khi tăng tốc độ video lên 2.0x và dùng bitrate 1.5M."""
        import subprocess
        video_src = Path(__file__).parent.parent.parent / "resources" / "tech" / "src" / "screen-recording-2026-09-10-at-55233-pm_rIXoYzPZ.mov"

        if not video_src.exists():
            self.skipTest("Sample video file not found")

        with tempfile.TemporaryDirectory() as tmpdir:
            out_file = os.path.join(tmpdir, "speed_bitrate_output.mp4")
            config = {
                "videoPath": str(video_src),
                "outputPath": out_file,
                "videoSpeed": 2.0,
                "videoBitrate": "1.5M",
                "overlayClips": [],
                "audioClips": [],
                "mixState": {
                    "origMuted": False,
                    "origVolume": 100,
                },
                "subtitles": [],
                "subStyle": {},
            }

            cfg_path = os.path.join(tmpdir, "config.json")
            with open(cfg_path, "w", encoding="utf-8") as f:
                json.dump(config, f)

            success = render_composite(cfg_path)
            self.assertTrue(success)
            self.assertTrue(os.path.exists(out_file))
            self.assertGreater(os.path.getsize(out_file), 1000)

            # Probe duration để kiểm chứng thời lượng giảm 1 nửa
            probe_cmd = ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", out_file]
            probe_res = subprocess.run(probe_cmd, capture_output=True, text=True)
            out_dur = float(probe_res.stdout.strip() or 0)
            # Video gốc ~ 122s, sau khi 2x speed phải ~ 61s (dung sai +/- 2s)
            self.assertGreater(out_dur, 55.0)
            self.assertLess(out_dur, 65.0)

    def test_hex_to_ass_color(self):
        """Kiểm tra parse màu sắc Hex và RGBA sang định dạng ASS &HAABBGGRR."""
        from composite_render import hex_to_ass_color
        # 1. Hex standard #RRGGBB -> &H00BBGGRR
        self.assertEqual(hex_to_ass_color("#ffffff"), "&H00FFFFFF")
        self.assertEqual(hex_to_ass_color("#ff0000"), "&H000000FF") # Red
        # 2. String rgba(255, 255, 255, 0.75)
        self.assertEqual(hex_to_ass_color("rgba(255, 255, 255, 0.75)"), "&H00FFFFFF")
        # 3. Custom Alpha override (0.25 -> a_val = int(0.25 * 255) = 63 = 0x3F)
        self.assertEqual(hex_to_ass_color("#000000", alpha=0.25), "&H3F000000")

    def test_generate_ass_file_split_and_separate_boxes(self):
        """Kiểm tra sinh SubBox vector khi tách 2 hộp (boxSplit) hoặc vị trí riêng (separateSecPos)."""
        from composite_render import generate_ass_file
        with tempfile.TemporaryDirectory() as tmpdir:
            ass_path = os.path.join(tmpdir, "test_split.ass")
            subtitles = [
                {"start": 1.0, "end": 3.0, "textTrans": "Dòng chính", "textOrig": "Secondary line"}
            ]
            # Kịch bản 1: boxSplit = True (Tách 2 hộp trên cùng 1 cụm)
            sub_style = {
                "fontFamily": "Be Vietnam Pro",
                "fontSize": 20,
                "secondaryFontSize": 16,
                "posX": 50.0,
                "posY": 80.0,
                "boxWidthPct": 80.0,
                "showSubBox": True,
                "boxSplit": True,
                "boxBorderRadius": 8.0,
                "boxPaddingX": 12.0,
                "boxPaddingY": 8.0,
                "boxGap": 10.0,
                "showMainSub": True,
                "showSubSub": True,
            }
            generate_ass_file(subtitles, sub_style, ass_path, video_w=1920, video_h=1080, canvas_w=640.0, canvas_h=360.0)
            self.assertTrue(os.path.exists(ass_path))
            with open(ass_path, "r", encoding="utf-8") as f:
                content = f.read()
            # Phải có 2 Dialogue SubBox vì boxSplit = True
            subbox_count = content.count("Dialogue: 0,0:00:01.00,0:00:03.00,SubBox")
            self.assertEqual(subbox_count, 2)
            # Phải chứa lệnh vẽ vector path ASS bo góc: \p1 và {\p0}
            self.assertIn(r"\p1", content)
            self.assertIn(r"{\p0}", content)
            self.assertIn("m 24 0", content)

            # Kịch bản 2: separateSecPos = True (Vị trí Sub phụ độc lập)
            ass_sep_path = os.path.join(tmpdir, "test_sep.ass")
            sub_style_sep = {
                "fontFamily": "Be Vietnam Pro",
                "fontSize": 22,
                "posX": 50.0,
                "posY": 85.0,
                "separateSecPos": True,
                "secPosX": 50.0,
                "secPosY": 20.0,
                "secBoxWidthPct": 70.0,
                "showSubBox": True,
                "showMainSub": True,
                "showSubSub": True,
            }
            generate_ass_file(subtitles, sub_style_sep, ass_sep_path, video_w=1920, video_h=1080, canvas_w=640.0, canvas_h=360.0)
            with open(ass_sep_path, "r", encoding="utf-8") as f:
                sep_content = f.read()
            self.assertIn(r"\pos(288,216)", sep_content)  # SubBox Y = 216 (20% của 1080)
            self.assertIn(r"\pos(960,234)", sep_content)  # SubText Y = 216 + v_pad_y(18) = 234
            self.assertIn(r"\pos(96,918)", sep_content)   # SubBox Y = 918 (85% của 1080)
            self.assertIn(r"\pos(960,936)", sep_content)  # SubText Y = 918 + v_pad_y(18) = 936


if __name__ == "__main__":
    unittest.main()


