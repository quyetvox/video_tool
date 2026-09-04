#!/bin/bash
set -e

# ==============================================================================
# Sub-Video AI: Python Engine Patch Packager & Builder
# Packages py_engine/ + Native Inpainter/OCR into lightweight .zip patch (~1MB)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RELEASES_DIR="$ROOT_DIR/releases/core"
DIST_DIR="$ROOT_DIR/dist/engine_patch"
VERSION_FILE="$ROOT_DIR/py_engine/VERSION"
if [ ! -f "$VERSION_FILE" ]; then
  echo "1.1.2" > "$VERSION_FILE"
fi

CURRENT_VER=$(cat "$VERSION_FILE" | tr -d '[:space:]')

if [ -n "$1" ]; then
  VERSION="$1"
else
  # Auto increment patch number (e.g. 1.1.2 -> 1.1.3)
  BASE_VER=$(echo "$CURRENT_VER" | awk -F. '{print $1"."$2}')
  PATCH_VER=$(echo "$CURRENT_VER" | awk -F. '{print $3}')
  if [ -z "$PATCH_VER" ]; then
    PATCH_VER=0
  fi
  NEW_PATCH=$((PATCH_VER + 1))
  VERSION="${BASE_VER}.${NEW_PATCH}"
fi

echo "$VERSION" > "$VERSION_FILE"
RELEASE_NOTES="${2:-Bản vá v$VERSION: Nâng cấp Multi-Track Timeline Overlay, Auto Silence Trimming, và Smart Cross-Ducking cho luồng thuyết minh AI.}"

echo "🚀 Chuẩn bị đóng gói bản vá Engine Version: v$VERSION (từ v$CURRENT_VER)..."

echo "🐍 [1/3] Đồng bộ thư mục py_engine..."
mkdir -p "$RELEASES_DIR"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/py_engine"
rsync -av --exclude '__pycache__' --exclude '*.pyc' --exclude '.DS_Store' --exclude 'tests' --exclude '.pytest_cache' "$ROOT_DIR/py_engine/" "$DIST_DIR/py_engine/"

echo "🔒 [1.5/3] Biên dịch toàn bộ mã nguồn sang bytecode .pyc và ẩn mã nguồn .py..."
python3 -m compileall -b -q "$DIST_DIR/py_engine"
find "$DIST_DIR/py_engine" -type f -name "*.py" -delete
find "$DIST_DIR/py_engine" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

echo "📝 [2/3] Tạo engine_manifest.json (v$VERSION)..."
cat <<EOF > "$DIST_DIR/engine_manifest.json"
{
  "version": "$VERSION",
  "engine_type": "python_core",
  "release_notes": "$RELEASE_NOTES",
  "download_url": "releases/core/engine_patch_v$VERSION.zip",
  "published_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "size_bytes": 0
}
EOF

# Copy manifest to releases/core/
cp "$DIST_DIR/engine_manifest.json" "$RELEASES_DIR/engine_manifest.json"

echo "📦 [3/3] Đóng gói engine_patch.zip..."
cd "$DIST_DIR"
VERSIONED_ZIP="$RELEASES_DIR/engine_patch_v${VERSION}.zip"
LATEST_ZIP="$RELEASES_DIR/engine_patch.zip"
LEGACY_ZIP="$ROOT_DIR/dist/engine_patch.zip"

rm -f "$VERSIONED_ZIP" "$LATEST_ZIP" "$LEGACY_ZIP"
mkdir -p "$ROOT_DIR/dist"
zip -r "$VERSIONED_ZIP" ./*
cp "$VERSIONED_ZIP" "$LATEST_ZIP"
cp "$VERSIONED_ZIP" "$LEGACY_ZIP"

ZIP_SIZE=$(ls -lh "$VERSIONED_ZIP" | awk '{print $5}')
BYTES_SIZE=$(wc -c < "$VERSIONED_ZIP" | tr -d ' ')

# Update size_bytes in manifests
if command -v sed >/dev/null 2>&1; then
  sed -i '' "s/\"size_bytes\": 0/\"size_bytes\": $BYTES_SIZE/" "$RELEASES_DIR/engine_manifest.json" 2>/dev/null || \
  sed -i "s/\"size_bytes\": 0/\"size_bytes\": $BYTES_SIZE/" "$RELEASES_DIR/engine_manifest.json" 2>/dev/null || true
  cp "$RELEASES_DIR/engine_manifest.json" "$DIST_DIR/engine_manifest.json"
fi

echo ""
echo "=============================================================================="
echo "🎉 ĐÃ ĐÓNG GÓI BẢN VÁ PYTHON CORE ENGINE THÀNH CÔNG!"
echo "📁 Thư mục phát hành Core : $RELEASES_DIR"
echo "📦 Bản vá theo phiên bản  : $VERSIONED_ZIP ($ZIP_SIZE)"
echo "📦 Bản vá mới nhất        : $LATEST_ZIP ($ZIP_SIZE)"
echo "📄 Chỉ mục manifest       : $RELEASES_DIR/engine_manifest.json"
echo "=============================================================================="

