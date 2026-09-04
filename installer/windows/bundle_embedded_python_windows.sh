#!/usr/bin/env bash
set -e

# ==============================================================================
# Sub-Video AI: Windows Standalone Python Bundler (Bash)
# Tải và cấu hình môi trường Python 3.11 Standalone cho Windows x64
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET_DIR="${1:-$ROOT_DIR/flutter_app/build/windows/x64/runner/Release/python}"

PYTHON_VERSION="3.11.8"
RELEASE_TAG="20240224"
TAR_NAME="cpython-${PYTHON_VERSION}+${RELEASE_TAG}-x86_64-pc-windows-msvc-shared-install_only.tar.gz"
DOWNLOAD_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${RELEASE_TAG}/${TAR_NAME}"

CACHE_DIR="$ROOT_DIR/.cache_python_standalone_win"
mkdir -p "$CACHE_DIR"

echo "🪟 [1/3] Chuẩn bị Standalone Python cho Windows x64..."

if [ ! -f "$CACHE_DIR/$TAR_NAME" ]; then
  echo "⬇️ [2/3] Đang tải Python Standalone Windows ($TAR_NAME)..."
  curl -L "$DOWNLOAD_URL" -o "$CACHE_DIR/$TAR_NAME"
fi

echo "📦 [3/3] Giải nén Python vào: $TARGET_DIR..."
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"
tar -xzf "$CACHE_DIR/$TAR_NAME" -C "$TARGET_DIR" --strip-components=1

echo "🎉 Hoàn tất chuẩn bị runtime Windows Python tại: $TARGET_DIR"
