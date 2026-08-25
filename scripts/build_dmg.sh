#!/usr/bin/env bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SRC="$PROJECT_ROOT/flutter_app/build/macos/Build/Products/Release/Sub-Video AI.app"
DIST_DIR="$PROJECT_ROOT/dist"
STAGING_DIR="/tmp/sub_video_dmg_staging"
OUTPUT_DMG="$DIST_DIR/Sub-Video-AI.dmg"

echo "🔨 [1/4] Biên dịch Flutter Desktop App (Release)..."
(cd "$PROJECT_ROOT/flutter_app" && flutter build macos --release)

echo "🐍 [2/4] Nhúng py_engine vào Contents/Resources/py_engine/..."
RESOURCES_DIR="$APP_SRC/Contents/Resources/py_engine"
mkdir -p "$RESOURCES_DIR"
rsync -av --exclude '__pycache__' --exclude '*.pyc' --exclude '.DS_Store' --exclude 'tests' --exclude '.pytest_cache' "$PROJECT_ROOT/py_engine/" "$RESOURCES_DIR/"

echo "📂 [3/4] Sao chép Sub-Video AI.app và tạo liên kết /Applications..."
mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_SRC" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 [4/4] Tạo file DMG nén UDZO bằng hdiutil..."
rm -f "$OUTPUT_DMG"
hdiutil create -volname "Sub-Video AI" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$OUTPUT_DMG"

rm -rf "$STAGING_DIR"

echo "🎉 Tạo DMG thành công tại: $OUTPUT_DMG"
ls -lh "$OUTPUT_DMG"
