#!/bin/bash
set -e

# ==============================================================================
# Sub-Video AI: Python Engine Patch Packager & Builder
# Packages py_engine/ + Native Inpainter/OCR into lightweight .zip patch (~1MB)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/engine_patch"
ZIP_OUT="$ROOT_DIR/dist/engine_patch.zip"
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

echo "🐍 [1/3] Đồng bộ và dọn dẹp thư mục py_engine..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/py_engine"
rsync -av --exclude '__pycache__' --exclude '*.pyc' --exclude '.DS_Store' --exclude 'tests' --exclude '.pytest_cache' "$ROOT_DIR/py_engine/" "$DIST_DIR/py_engine/"

echo "📝 [2/3] Tạo engine_manifest.json (v$VERSION)..."
cat <<EOF > "$DIST_DIR/engine_manifest.json"
{
  "version": "$VERSION",
  "engine_type": "python_core",
  "release_notes": "$RELEASE_NOTES",
  "download_url": "dist/engine_patch",
  "published_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "size_bytes": 0
}
EOF

echo "📦 [3/3] Đóng gói engine_patch.zip..."
cd "$DIST_DIR"
rm -f "$ZIP_OUT"
zip -r "$ZIP_OUT" ./*

echo ""
echo "=============================================================================="
echo "🎉 ĐÃ ĐÓNG GÓI BẢN VÁ PYTHON CORE ENGINE THÀNH CÔNG!"
echo "📁 Thư mục bản vá cục bộ : $DIST_DIR"
echo "📦 File nén bản vá (.zip): $ZIP_OUT ($(ls -lh "$ZIP_OUT" | awk '{print $5}'))"
echo "=============================================================================="
echo "👉 Bạn có thể nạp trực tiếp thư mục '$DIST_DIR' hoặc file '$ZIP_OUT' trên GUI!"
