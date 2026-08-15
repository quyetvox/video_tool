import os
import shutil
import time
from pathlib import Path
from typing import Any, Dict, List, Optional
import yaml

ROOT_DIR = Path(__file__).parent.parent.parent.resolve()
DEFAULT_CONFIG_PATH = ROOT_DIR / "config.yaml"


class StorageManager:
    """
    Native Google Cloud Storage Manager using google-cloud-storage Python SDK
    and Service Account Key (gcs-key.json).
    Operates 100% independently without Rclone or OS mounts.
    """

    def __init__(self, project_name: Optional[str] = None):
        self.project_name = project_name or "default"
        self.assets_dir = ROOT_DIR / "assets"
        self.local_proj_dir = self.assets_dir / self.project_name
        self.config = self._load_storage_config()
        self.bucket_name = self.config.get("bucket_name", "service-qa-beta")
        self.base_prefix = self.config.get("base_prefix", "video-tiktok-volumn").strip("/")
        self.key_file = self._resolve_key_file(self.config.get("key_file", "gcs-key.json"))
        self._client = None
        self._bucket = None

    def _load_storage_config(self) -> Dict[str, Any]:
        """Loads storage configuration from project or root config.yaml."""
        if self.project_name:
            proj_config = ROOT_DIR / "assets" / self.project_name / "config.yaml"
            if proj_config.exists():
                try:
                    with open(proj_config, "r", encoding="utf-8") as f:
                        cfg = yaml.safe_load(f) or {}
                        if "storage" in cfg and isinstance(cfg["storage"], dict):
                            return cfg["storage"]
                except Exception:
                    pass

        if DEFAULT_CONFIG_PATH.exists():
            try:
                with open(DEFAULT_CONFIG_PATH, "r", encoding="utf-8") as f:
                    cfg = yaml.safe_load(f) or {}
                    if "storage" in cfg and isinstance(cfg["storage"], dict):
                        return cfg["storage"]
            except Exception:
                pass

        return {
            "enabled": True,
            "provider": "gcs",
            "key_file": "gcs-key.json",
            "bucket_name": "service-qa-beta",
            "base_prefix": "video-tiktok-volumn"
        }

    def _resolve_key_file(self, key_file_name: str) -> Optional[Path]:
        """Resolves absolute path to service account key json."""
        env_key = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
        if env_key and Path(env_key).exists():
            return Path(env_key).resolve()

        candidates = [
            ROOT_DIR / key_file_name,
            ROOT_DIR / "gcs-key.json",
            ROOT_DIR / "key.json",
            ROOT_DIR / "service_account.json",
            Path.home() / ".config" / "gcloud" / "gcs-key.json"
        ]
        for p in candidates:
            if p.exists() and p.is_file():
                return p.resolve()
        return ROOT_DIR / key_file_name

    def _get_client(self):
        """Initializes and returns google.cloud.storage.Client."""
        if self._client is None:
            try:
                from google.cloud import storage as gcs
                from google.oauth2 import service_account

                if self.key_file and self.key_file.exists():
                    credentials = service_account.Credentials.from_service_account_file(str(self.key_file))
                    self._client = gcs.Client(credentials=credentials, project=credentials.project_id)
                else:
                    self._client = gcs.Client()
            except Exception as e:
                raise RuntimeError(f"Failed to initialize Google Cloud Storage client: {e}")
        return self._client

    def _get_bucket(self):
        """Returns the target GCS bucket object."""
        if self._bucket is None:
            client = self._get_client()
            self._bucket = client.bucket(self.bucket_name)
        return self._bucket

    def is_connected(self) -> bool:
        """Checks if Google Cloud Storage is reachable and key is valid."""
        try:
            client = self._get_client()
            # Fast & safe check: list 1 item (requires only Storage Object permissions, works with all Service Accounts)
            iterator = client.list_blobs(self.bucket_name, prefix=self.base_prefix, max_results=1)
            next(iterator.pages, None)
            return True
        except Exception:
            return False

    def is_mounted(self) -> bool:
        """Backward compatibility alias for is_connected."""
        return self.is_connected()

    def ensure_local_project_structure(self) -> bool:
        """Ensures local project directory structure exists."""
        try:
            (self.local_proj_dir / "src").mkdir(parents=True, exist_ok=True)
            (self.local_proj_dir / "output").mkdir(parents=True, exist_ok=True)
            (self.local_proj_dir / "workspace").mkdir(parents=True, exist_ok=True)
            return True
        except Exception:
            return False

    def _scan_cloud_files(self) -> Dict[str, Dict[str, Any]]:
        """Scans cloud files via GCS API list_blobs (real-time metadata, 0-byte video download)."""
        result = {}
        try:
            client = self._get_client()
            prefix = f"{self.base_prefix}/{self.project_name}/"
            blobs = client.list_blobs(self.bucket_name, prefix=prefix)

            for blob in blobs:
                full_name = blob.name
                if not full_name.startswith(prefix):
                    continue
                rel_path = full_name[len(prefix):].lstrip("/")
                if not rel_path or rel_path.endswith("/") or rel_path.startswith("workspace/") or rel_path.startswith("."):
                    continue

                ext = Path(rel_path).suffix.lower()
                mtime_ms = int(blob.updated.timestamp() * 1000) if blob.updated else 0
                result[rel_path] = {
                    "name": Path(rel_path).name,
                    "relPath": rel_path,
                    "fullPath": f"gs://{self.bucket_name}/{blob.name}",
                    "sizeBytes": blob.size or 0,
                    "mtime": mtime_ms,
                    "isMedia": ext in [".mp4", ".mkv", ".mov", ".webm", ".avi", ".mp3", ".wav"]
                }
        except Exception:
            pass
        return result

    def _scan_directory(self, base_dir: Path, exclude_workspace: bool = True) -> Dict[str, Dict[str, Any]]:
        """Helper to scan local directory recursively."""
        result = {}
        if not base_dir.exists() or not base_dir.is_dir():
            return result

        try:
            for root, dirs, files in os.walk(base_dir):
                root_path = Path(root)
                rel_root = root_path.relative_to(base_dir)

                if exclude_workspace:
                    dirs[:] = [d for d in dirs if d != "workspace" and not d.startswith(".")]
                else:
                    dirs[:] = [d for d in dirs if not d.startswith(".")]

                for f in files:
                    if f.startswith("."):
                        continue
                    file_path = root_path / f
                    try:
                        stat = file_path.stat()
                        rel_file = str(rel_root / f) if str(rel_root) != "." else f
                        ext = file_path.suffix.lower()
                        result[rel_file] = {
                            "name": f,
                            "relPath": rel_file,
                            "fullPath": str(file_path),
                            "sizeBytes": stat.st_size,
                            "mtime": stat.st_mtime * 1000,
                            "isMedia": ext in [".mp4", ".mkv", ".mov", ".webm", ".avi", ".mp3", ".wav"]
                        }
                    except (PermissionError, OSError):
                        pass
        except Exception:
            pass

        return result

    def get_status(self) -> Dict[str, Any]:
        """
        Scans both local assets/<project>/ and Cloud Storage via Google Cloud SDK.
        Returns a comprehensive comparison with categorized files.
        """
        connected = self.is_connected()
        local_exists = self.local_proj_dir.exists()

        local_files = self._scan_directory(self.local_proj_dir, exclude_workspace=True) if local_exists else {}
        cloud_files = self._scan_cloud_files() if connected else {}

        all_rel_paths = sorted(set(list(local_files.keys()) + list(cloud_files.keys())))

        files_detail = []
        synced_count = 0
        local_only_count = 0
        cloud_only_count = 0
        modified_count = 0

        total_local_bytes = 0
        total_cloud_bytes = 0

        for rel in all_rel_paths:
            loc = local_files.get(rel)
            cld = cloud_files.get(rel)

            if loc:
                total_local_bytes += loc["sizeBytes"]
            if cld:
                total_cloud_bytes += cld["sizeBytes"]

            if loc and cld:
                if loc["sizeBytes"] == cld["sizeBytes"]:
                    status = "synced"
                    synced_count += 1
                else:
                    status = "modified"
                    modified_count += 1
            elif loc and not cld:
                status = "local_only"
                local_only_count += 1
            elif cld and not loc:
                status = "cloud_only"
                cloud_only_count += 1
            else:
                status = "unknown"

            entry = {
                "relPath": rel,
                "name": Path(rel).name,
                "folder": str(Path(rel).parent) if str(Path(rel).parent) != "." else "",
                "status": status,
                "local": loc,
                "cloud": cld,
                "sizeBytes": (loc or cld)["sizeBytes"],
                "isMedia": (loc or cld)["isMedia"]
            }
            files_detail.append(entry)

        return {
            "project": self.project_name,
            "mounted": connected,  # Backward compatibility flag
            "connected": connected,
            "mode": "native_gcs_key",
            "keyFile": str(self.key_file) if self.key_file else "",
            "keyExists": self.key_file.exists() if self.key_file else False,
            "bucket": self.bucket_name,
            "prefix": f"{self.base_prefix}/{self.project_name}",
            "localPath": str(self.local_proj_dir),
            "counts": {
                "total": len(files_detail),
                "synced": synced_count,
                "localOnly": local_only_count,
                "cloudOnly": cloud_only_count,
                "modified": modified_count
            },
            "bytes": {
                "local": total_local_bytes,
                "cloud": total_cloud_bytes
            },
            "files": files_detail
        }

    def sync_down(self, files: Optional[List[str]] = None) -> Dict[str, Any]:
        """
        Downloads files from Google Cloud Storage directly to Local assets directory.
        """
        bucket = self._get_bucket()
        self.ensure_local_project_structure()

        cloud_files = self._scan_cloud_files()
        targets = []

        if files:
            for f in files:
                clean_f = f.strip().lstrip("/")
                matched = False
                for c_rel in cloud_files:
                    if c_rel == clean_f or Path(c_rel).name == clean_f:
                        targets.append(c_rel)
                        matched = True
                if not matched:
                    targets.append(clean_f)
        else:
            targets = list(cloud_files.keys())

        transferred = []
        skipped = []
        failed = []
        total_bytes = 0

        for rel in targets:
            dest_file = self.local_proj_dir / rel
            try:
                dest_file.parent.mkdir(parents=True, exist_ok=True)

                cld_info = cloud_files.get(rel)
                if dest_file.exists() and cld_info and dest_file.stat().st_size == cld_info["sizeBytes"]:
                    skipped.append({"file": rel, "reason": "Already up to date locally"})
                    continue

                blob_name = f"{self.base_prefix}/{self.project_name}/{rel}"
                blob = bucket.blob(blob_name)
                blob.download_to_filename(str(dest_file))

                trans_size = dest_file.stat().st_size if dest_file.exists() else 0
                transferred.append({"file": rel, "sizeBytes": trans_size})
                total_bytes += trans_size
            except Exception as e:
                failed.append({"file": rel, "error": str(e)})

        return {
            "action": "sync_down",
            "project": self.project_name,
            "transferredCount": len(transferred),
            "skippedCount": len(skipped),
            "failedCount": len(failed),
            "totalBytes": total_bytes,
            "transferred": transferred,
            "skipped": skipped,
            "failed": failed
        }

    def sync_up(self, files: Optional[List[str]] = None) -> Dict[str, Any]:
        """
        Uploads files from Local assets directory directly to Google Cloud Storage.
        """
        bucket = self._get_bucket()
        if not self.local_proj_dir.exists():
            raise RuntimeError(f"Local project folder does not exist: {self.local_proj_dir}")

        local_files = self._scan_directory(self.local_proj_dir, exclude_workspace=True)
        cloud_files = self._scan_cloud_files()
        targets = []

        if files:
            for f in files:
                clean_f = f.strip().lstrip("/")
                matched = False
                for l_rel in local_files:
                    if l_rel == clean_f or Path(l_rel).name == clean_f:
                        targets.append(l_rel)
                        matched = True
                if not matched:
                    targets.append(clean_f)
        else:
            targets = list(local_files.keys())

        transferred = []
        skipped = []
        failed = []
        total_bytes = 0

        for rel in targets:
            src_file = self.local_proj_dir / rel
            if not src_file.exists():
                failed.append({"file": rel, "error": "Local source file not found"})
                continue

            try:
                src_stat = src_file.stat()
                cld_info = cloud_files.get(rel)

                if cld_info and cld_info["sizeBytes"] == src_stat.st_size:
                    skipped.append({"file": rel, "reason": "Already up to date on cloud"})
                    continue

                blob_name = f"{self.base_prefix}/{self.project_name}/{rel}"
                blob = bucket.blob(blob_name)
                blob.upload_from_filename(str(src_file))

                transferred.append({"file": rel, "sizeBytes": src_stat.st_size})
                total_bytes += src_stat.st_size
            except Exception as e:
                failed.append({"file": rel, "error": str(e)})

        return {
            "action": "sync_up",
            "project": self.project_name,
            "transferredCount": len(transferred),
            "skippedCount": len(skipped),
            "failedCount": len(failed),
            "totalBytes": total_bytes,
            "transferred": transferred,
            "skipped": skipped,
            "failed": failed
        }

    def offload_local(self, files: Optional[List[str]] = None) -> Dict[str, Any]:
        """
        Safely deletes local files ONLY IF they are verified to exist on GCS with matching size.
        """
        if not self.local_proj_dir.exists():
            return {"action": "offload", "freedCount": 0, "freedBytes": 0, "freed": []}

        bucket = self._get_bucket()
        local_files = self._scan_directory(self.local_proj_dir, exclude_workspace=True)

        targets = []
        if files:
            for f in files:
                clean_f = f.strip().lstrip("/")
                for l_rel in local_files:
                    if l_rel == clean_f or Path(l_rel).name == clean_f:
                        targets.append(l_rel)
        else:
            targets = [rel for rel, info in local_files.items() if info["isMedia"] and (rel.startswith("src/") or rel.startswith("output/"))]

        freed = []
        rejected = []
        failed = []
        total_freed_bytes = 0

        for rel in set(targets):
            loc_file = self.local_proj_dir / rel
            if not loc_file.exists():
                continue

            loc_size = loc_file.stat().st_size
            blob_name = f"{self.base_prefix}/{self.project_name}/{rel}"
            blob = bucket.get_blob(blob_name)

            if not blob or not blob.exists():
                rejected.append({"file": rel, "reason": "Not found on cloud storage (Upload first)"})
                continue

            if loc_size != (blob.size or 0):
                rejected.append({"file": rel, "reason": f"Size mismatch: Local={loc_size}B vs Cloud={blob.size}B"})
                continue

            try:
                loc_file.unlink()
                freed.append({"file": rel, "freedBytes": loc_size})
                total_freed_bytes += loc_size
            except Exception as e:
                failed.append({"file": rel, "error": str(e)})

        return {
            "action": "offload",
            "project": self.project_name,
            "freedCount": len(freed),
            "rejectedCount": len(rejected),
            "failedCount": len(failed),
            "totalFreedBytes": total_freed_bytes,
            "freed": freed,
            "rejected": rejected,
            "failed": failed
        }

    def delete_cloud(self, files: List[str]) -> Dict[str, Any]:
        """Deletes specified files directly from Google Cloud Storage."""
        bucket = self._get_bucket()
        deleted = []
        failed = []

        for f in files:
            clean_f = f.strip().lstrip("/")
            try:
                blob_name = f"{self.base_prefix}/{self.project_name}/{clean_f}"
                blob = bucket.blob(blob_name)
                blob.delete()
                deleted.append(clean_f)
            except Exception as e:
                failed.append({"file": clean_f, "error": str(e)})

        return {
            "action": "delete_cloud",
            "project": self.project_name,
            "deletedCount": len(deleted),
            "failedCount": len(failed),
            "deleted": deleted,
            "failed": failed
        }

    def refresh_mount(self, target_dir: Optional[str] = None) -> Dict[str, Any]:
        """Backward compatibility alias for refreshing status."""
        return {
            "success": True,
            "mode": "native_gcs_key",
            "message": "Cloud metadata re-synced via Native GCS SDK"
        }
