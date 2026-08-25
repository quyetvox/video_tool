import os
import re
import shutil
from pathlib import Path
from typing import Any, Dict, Optional
import yaml

from core.config_adapter import wrap_config, ConfigDict


class ProjectPaths:
    def __init__(
        self,
        project_name: str,
        project_dir: Path,
        src_dir: Path,
        cut_dir: Path,
        merge_dir: Path,
        workspace_dir: Path,
        output_dir: Path,
        config_path: Path,
        root_config_path: Optional[Path] = None
    ):
        self.project_name = project_name
        self.project_dir = project_dir
        self.src_dir = src_dir
        self.cut_dir = cut_dir
        self.merge_dir = merge_dir
        self.workspace_dir = workspace_dir
        self.output_dir = output_dir
        self.config_path = config_path
        self.root_config_path = root_config_path

    def load_config(self) -> ConfigDict:
        """Loads project-specific config.yaml, deep-overlaying onto root default config."""
        config = ConfigDict()
        if self.root_config_path and self.root_config_path.exists():
            try:
                with open(self.root_config_path, "r", encoding="utf-8") as f:
                    root_dict = yaml.safe_load(f) or {}
                    config.deep_merge(root_dict)
            except Exception:
                pass

        if self.config_path.exists():
            try:
                with open(self.config_path, "r", encoding="utf-8") as f:
                    proj_dict = yaml.safe_load(f) or {}
                    config.deep_merge(proj_dict)
            except Exception:
                pass

        # Ensure project-specific workspace_dir and output_dir are set in config dict
        config["workspace_dir"] = str(self.workspace_dir)
        config["output_dir"] = str(self.output_dir)
        config["cut_dir"] = str(self.cut_dir)
        config["merge_dir"] = str(self.merge_dir)
        return config


class ProjectManager:
    @staticmethod
    def find_root_dir(start_path: Optional[Path | str] = None) -> Path:
        """
        Robust root directory finder that works in macOS GUI sandboxes, DMG, CLI, and dev environments.
        """
        if start_path:
            p = Path(start_path).resolve()
            curr = p.parent if p.is_file() else p
        else:
            env_root = os.environ.get("SUB_VIDEO_ROOT")
            if env_root and Path(env_root).exists():
                return Path(env_root).resolve()
            curr = Path.cwd().resolve()

        # 1. Walk upwards looking for repository / workspace markers
        check_dir = curr
        for _ in range(10):
            has_resources = (check_dir / "resources").exists() or (check_dir / "assets").exists()
            has_config = (check_dir / "config.yaml").exists()
            has_engine = (check_dir / "py_engine").exists() or (check_dir / "video_engine").exists()

            if has_resources and (has_config or has_engine):
                return check_dir

            parent = check_dir.parent
            if parent == check_dir:
                break
            check_dir = parent

        # 2. Standard Sub-Video workspace location fallback
        home = os.environ.get("HOME")
        if home:
            std_ws = Path(home) / "Documents" / "projects" / "video" / "Sub-Video"
            if std_ws.exists():
                return std_ws

        return curr

    @staticmethod
    def resolve_project_paths(target_path: Path | str, root_dir_override: Optional[Path] = None) -> ProjectPaths:
        """
        Resolves project layout (src, cut, merge, workspace, output, config.yaml) for a given file or directory target.
        Correctly detects project directory on user's writable disk.
        """
        target = Path(target_path).resolve()
        root_dir = root_dir_override or ProjectManager.find_root_dir(target)
        target_dir = target.parent if target.is_file() else target

        target_str = str(target.as_posix())
        project_name = "default"
        project_dir = target_dir

        if "/resources/" in target_str:
            parts = target.parts
            try:
                res_idx = [i for i, part in enumerate(parts) if part == "resources"][-1]
                if res_idx + 1 < len(parts):
                    project_name = parts[res_idx + 1]
                    # Walk up until we are at the project folder level
                    project_dir = Path(*parts[: res_idx + 2])
            except (ValueError, IndexError):
                project_name = target_dir.name
                project_dir = target_dir
        elif "/assets/" in target_str:
            parts = target.parts
            try:
                assets_idx = [i for i, part in enumerate(parts) if part == "assets"][-1]
                if assets_idx + 1 < len(parts):
                    project_name = parts[assets_idx + 1]
                    project_dir = Path(*parts[: assets_idx + 2])
            except (ValueError, IndexError):
                project_name = target_dir.name
                project_dir = target_dir
        elif (target_dir / "src").exists() or (target_dir / "workspace").exists() or (target_dir / "config.yaml").exists():
            project_name = target_dir.name
            project_dir = target_dir
        else:
            project_name = target_dir.name
            res_cand = root_dir / "resources" / project_name
            asset_cand = root_dir / "assets" / project_name
            if res_cand.exists():
                project_dir = res_cand
            elif asset_cand.exists():
                project_dir = asset_cand
            else:
                project_dir = target_dir

        src_dir = project_dir / "src"
        cut_dir = project_dir / "cut"
        merge_dir = project_dir / "merge"
        workspace_dir = project_dir / "workspace"
        output_dir = project_dir / "output"
        config_path = project_dir / "config.yaml"
        default_root_config = root_dir / "config.yaml"

        # Ensure project subdirectories exist in user's writable project_dir
        src_dir.mkdir(parents=True, exist_ok=True)
        cut_dir.mkdir(parents=True, exist_ok=True)
        merge_dir.mkdir(parents=True, exist_ok=True)
        workspace_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)

        # Copy default root config if project config does not exist
        if not config_path.exists() and default_root_config.exists():
            try:
                shutil.copy(str(default_root_config), str(config_path))
            except Exception:
                pass

        return ProjectPaths(
            project_name=project_name,
            project_dir=project_dir,
            src_dir=src_dir,
            cut_dir=cut_dir,
            merge_dir=merge_dir,
            workspace_dir=workspace_dir,
            output_dir=output_dir,
            config_path=config_path,
            root_config_path=default_root_config if default_root_config.exists() else None
        )

    @staticmethod
    def get_job_id(video_path: Path | str) -> str:
        """
        Generates a clean, deterministic job ID based on the video filename.
        Example: 'video_001.mp4' -> 'job_video_001'
        """
        stem = Path(video_path).stem
        sanitized = re.sub(r"[^a-zA-Z0-9_\-]", "_", stem)
        return f"job_{sanitized}"
