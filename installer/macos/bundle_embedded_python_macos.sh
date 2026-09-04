#!/bin/bash
set -e

# ==============================================================================
# Sub-Video AI: Embedded Standalone Python Bundler for macOS App (.app)
# Bundles a relocatable python runtime + pip dependencies into Contents/Frameworks/python/
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ -d "$ROOT_DIR/flutter_app/build/macos/Build/Products/Release/Sub-Video AI.app" ]; then
  APP_DIR="$ROOT_DIR/flutter_app/build/macos/Build/Products/Release/Sub-Video AI.app"
else
  APP_DIR="$ROOT_DIR/flutter_app/build/macos/Build/Products/Release/SubVideo.app"
fi

FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

# Python Standalone Release details (astral-sh / indygreg python-build-standalone)
PYTHON_VERSION="3.11.8"
RELEASE_TAG="20240224"
TAR_NAME="cpython-${PYTHON_VERSION}+${RELEASE_TAG}-aarch64-apple-darwin-install_only.tar.gz"
DOWNLOAD_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${RELEASE_TAG}/${TAR_NAME}"

echo "🍏 Bắt đầu đóng gói Embedded Standalone Python vào $APP_DIR..."

if [ ! -d "$APP_DIR" ]; then
  echo "⚠️ Không tìm thấy $APP_DIR. Hãy build release Flutter Desktop trước (flutter build macos --release)."
  exit 1
fi

mkdir -p "$FRAMEWORKS_DIR"
mkdir -p "$RESOURCES_DIR"

# 1. Download & Extract Standalone Python if not present
TEMP_CACHE="$ROOT_DIR/.cache_python_standalone"
mkdir -p "$TEMP_CACHE"

if [ ! -f "$TEMP_CACHE/$TAR_NAME" ]; then
  echo "⬇️ Đang tải Python Standalone cho macOS Apple Silicon (aarch64)..."
  curl -L "$DOWNLOAD_URL" -o "$TEMP_CACHE/$TAR_NAME"
fi

echo "📦 Đang giải nén Python Standalone vào Contents/Frameworks/python/..."
rm -rf "$FRAMEWORKS_DIR/python"
mkdir -p "$FRAMEWORKS_DIR/python"
tar -xzf "$TEMP_CACHE/$TAR_NAME" -C "$FRAMEWORKS_DIR/python" --strip-components=1

# 2. Copy py_engine source into Contents/Resources/py_engine/
echo "📁 Đang sao chép py_engine vào Contents/Resources/py_engine/..."
rm -rf "$RESOURCES_DIR/py_engine"
mkdir -p "$RESOURCES_DIR/py_engine"
rsync -av --exclude '__pycache__' --exclude '*.pyc' --exclude '.DS_Store' --exclude 'tests' --exclude '.pytest_cache' "$ROOT_DIR/py_engine/" "$RESOURCES_DIR/py_engine/"

# 3. Install requirements into Embedded Python environment
EMBEDDED_PY="$FRAMEWORKS_DIR/python/bin/python3"
chmod +x "$EMBEDDED_PY"

echo "📥 Đang cài đặt thư viện vào Embedded Python runtime..."
"$EMBEDDED_PY" -m pip install --upgrade pip
"$EMBEDDED_PY" -m pip install -r "$ROOT_DIR/py_engine/requirements.txt"

echo "🎉 HOÀN TẤT ĐÓNG GÓI EMBEDDED PYTHON VÀO App!"
echo "👉 App đã sẵn sàng chạy độc lập 100% không cần người dùng cài môi trường."
