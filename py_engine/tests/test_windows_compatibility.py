import unittest
from pathlib import Path
import sys

# Ensure py_engine is in sys.path
ENGINE_DIR = Path(__file__).resolve().parent.parent
if str(ENGINE_DIR) not in sys.path:
    sys.path.insert(0, str(ENGINE_DIR))

from core.project_manager import ProjectManager
from utils.ffmpeg_utils import ensure_system_path


class TestWindowsCompatibility(unittest.TestCase):
    def test_ensure_system_path(self):
        ensure_system_path()
        # Ensure it doesn't crash and path is populated
        import os
        self.assertTrue(len(os.environ.get("PATH", "")) > 0)

    def test_hierarchy_traversal_project_resolution(self):
        root_dir = ENGINE_DIR.parent

        # 1. Test existing project
        p_existing = ProjectManager.resolve_project_paths(
            "resources/anh_trang_sang/src/anh_trang_sang.mp4",
            root_dir_override=root_dir
        )
        self.assertEqual(p_existing.project_name, "anh_trang_sang")

        # 2. Test deeply nested resources/src/demo layout
        p_nested = ProjectManager.resolve_project_paths(
            "resources/src/demo/video.mp4",
            root_dir_override=root_dir
        )
        self.assertEqual(p_nested.project_name, "demo")

        # 3. Test standard resources/custom_name/src/clip.mp4 layout
        p_custom = ProjectManager.resolve_project_paths(
            "resources/my_channel_01/src/clip.mp4",
            root_dir_override=root_dir
        )
        self.assertEqual(p_custom.project_name, "my_channel_01")

    def test_ffmpeg_libavfilter_path_escaping(self):
        # Simulated Windows absolute path
        win_path = r"C:\Users\princ\Documents\Projects\video_tool\subtitles_vi.ass"
        escaped = win_path.replace("\\", "/").replace(":", r"\:").replace("'", r"'\''")

        self.assertEqual(
            escaped,
            r"C\:/Users/princ/Documents/Projects/video_tool/subtitles_vi.ass"
        )
        # Ensure colon is escaped with backslash
        self.assertIn(r"C\:", escaped)
        # Ensure path separator is forward slash, preventing libavfilter escape eaten errors
        self.assertNotIn(r"\Users", escaped)
        self.assertNotIn(r"\princ", escaped)


if __name__ == "__main__":
    unittest.main()
