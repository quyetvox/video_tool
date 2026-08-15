import re
import shutil
from pathlib import Path
from typing import Any, Dict
import yaml

from core.config_adapter import wrap_config, ConfigDict

ROOT_DIR = Path(__file__).parent.parent.parent.resolve()
DEFAULT_CONFIG_PATH = ROOT_DIR / "config.yaml"


class ProjectPaths:
    def __init__(
        self,
        project_name: str,
        project_dir: Path,
        src_dir: Path,
        workspace_dir: Path,
        output_dir: Path,
        config_path: Path
    ):
        self.project_name = project_name
        self.project_dir = project_dir
        self.src_dir = src_dir
        self.workspace_dir = workspace_dir
        self.output_dir = output_dir
        self.config_path = config_path

    def load_config(self) -> ConfigDict:
        """Loads project-specific config.yaml, deep-overlaying onto root default config."""
        config = ConfigDict()
        if DEFAULT_CONFIG_PATH.exists():
            with open(DEFAULT_CONFIG_PATH, "r", encoding="utf-8") as f:
                root_dict = yaml.safe_load(f) or {}
                config.deep_merge(root_dict)

        if self.config_path.exists():
            with open(self.config_path, "r", encoding="utf-8") as f:
                proj_dict = yaml.safe_load(f) or {}
                config.deep_merge(proj_dict)

        # Ensure project-specific workspace_dir and output_dir are set in config dict
        config["workspace_dir"] = str(self.workspace_dir)
        config["output_dir"] = str(self.output_dir)
        return config


class ProjectManager:
    @staticmethod
    def resolve_project_paths(target_path: Path | str) -> ProjectPaths:
        """
        Resolves project layout (src, workspace, output, config.yaml) for a given file or directory target.
        - Assets targets like 'assets/foods/src/v1.mp4' -> project 'foods' in 'assets/foods/'
        - Targets like 'input/foods/links.txt' -> project 'foods' in 'assets/foods/'
        - Independent targets -> project 'default' in 'assets/default/'
        """
        target_path = Path(target_path).resolve()
        assets_dir = ROOT_DIR / "assets"

        # Check if target is inside assets/<project_name>/...
        project_name = "default"
        try:
            rel_to_assets = target_path.relative_to(assets_dir)
            parts = rel_to_assets.parts
            if parts:
                project_name = parts[0]
        except ValueError:
            # Check legacy input/<project_name>/...
            try:
                legacy_input = ROOT_DIR / "input"
                rel_to_input = target_path.relative_to(legacy_input)
                parts = rel_to_input.parts
                if parts and parts[0] not in ("src", "downloaded"):
                    project_name = parts[0]
            except ValueError:
                # If target_path is a directory inside assets or named project
                if target_path.parent == assets_dir:
                    project_name = target_path.name

        project_dir = assets_dir / project_name
        src_dir = project_dir / "src"
        workspace_dir = project_dir / "workspace"
        output_dir = project_dir / "output"
        config_path = project_dir / "config.yaml"

        # Ensure project subdirectories exist
        src_dir.mkdir(parents=True, exist_ok=True)
        workspace_dir.mkdir(parents=True, exist_ok=True)
        output_dir.mkdir(parents=True, exist_ok=True)

        # Copy default root config.yaml if project config does not exist
        if not config_path.exists() and DEFAULT_CONFIG_PATH.exists():
            shutil.copy(str(DEFAULT_CONFIG_PATH), str(config_path))

        return ProjectPaths(
            project_name=project_name,
            project_dir=project_dir,
            src_dir=src_dir,
            workspace_dir=workspace_dir,
            output_dir=output_dir,
            config_path=config_path
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
