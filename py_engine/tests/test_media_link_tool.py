#!/usr/bin/env python3
"""
Unit tests for media_link_tool.py
"""

import unittest
from pathlib import Path
import sys
import os

# Add py_engine/tools to sys.path
engine_dir = Path(__file__).resolve().parent.parent
tools_dir = engine_dir / "tools"
sys.path.insert(0, str(tools_dir))

from media_link_tool import (
    sanitize_filename,
    format_bytes,
    format_speed,
    format_eta,
    is_direct_media_url,
    probe_url,
)


class TestMediaLinkTool(unittest.TestCase):
    def test_sanitize_filename(self):
        self.assertEqual(sanitize_filename('Naruto Shippuden: Episode 1/2?'), 'Naruto Shippuden_ Episode 1_2_')
        self.assertEqual(sanitize_filename('   Simple Movie   '), 'Simple Movie')
        self.assertTrue(sanitize_filename('').startswith('video_'))

    def test_format_helpers(self):
        self.assertEqual(format_bytes(1024 * 1024), '1.0 MB')
        self.assertEqual(format_speed(2.5 * 1024 * 1024), '2.5 MB/s')
        self.assertEqual(format_eta(65), '01:05')
        self.assertEqual(format_eta(3665), '01:01:05')

    def test_is_direct_media_url(self):
        self.assertTrue(is_direct_media_url('https://cdn.example.com/videos/movie.mp4?token=123'))
        self.assertTrue(is_direct_media_url('http://storage.com/clip.mkv'))
        self.assertFalse(is_direct_media_url('https://www.youtube.com/watch?v=dQw4w9WgXcQ'))
        self.assertFalse(is_direct_media_url('https://v.douyin.com/abcxyz/'))

    def test_probe_invalid_url(self):
        res = probe_url('not_a_valid_url')
        self.assertFalse(res['success'])
        self.assertIn('error', res)

    def test_probe_dash_stream_with_audio_and_headers(self):
        from unittest.mock import patch, MagicMock
        fake_info = {
            "title": "Bilibili Test Video",
            "duration": 120.0,
            "thumbnail": "https://example.com/thumb.jpg",
            "http_headers": {"Referer": "https://www.bilibili.com/video/BV12345"},
            "formats": [
                {"vcodec": "avc1.64001F", "acodec": "none", "height": 1080, "url": "https://cdn.example.com/video_1080p.m4s"},
                {"vcodec": "none", "acodec": "mp4a.40.2", "abr": 128, "url": "https://cdn.example.com/audio_128k.m4s"},
            ]
        }
        with patch('media_link_tool.yt_dlp.YoutubeDL') as mock_ydl:
            mock_inst = MagicMock()
            mock_inst.extract_info.return_value = fake_info
            mock_ydl.return_value.__enter__.return_value = mock_inst

            res = probe_url("https://www.bilibili.com/video/BV12345")
            self.assertTrue(res['success'])
            self.assertEqual(res['stream_url'], "https://cdn.example.com/video_1080p.m4s")
            self.assertEqual(res['audio_url'], "https://cdn.example.com/audio_128k.m4s")
    def test_find_ffmpeg(self):
        from media_link_tool import find_ffmpeg
        ffmpeg_bin = find_ffmpeg()
        if ffmpeg_bin:
            self.assertTrue(os.path.exists(ffmpeg_bin))
            self.assertIn(str(Path(ffmpeg_bin).parent), os.environ["PATH"])


if __name__ == '__main__':
    unittest.main()
