#!/usr/bin/env bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SRC="$PROJECT_ROOT/flutter_app/build/macos/Build/Products/Release/Sub-Video AI.app"
DIST_DIR="$PROJECT_ROOT/dist"
STAGING_DIR="/tmp/sub_video_dmg_staging"
OUTPUT_DMG="$DIST_DIR/Sub-Video-AI.dmg"

echo "🔨 [1/4] Biên dịch Flutter Desktop App (Release)..."
(cd "$PROJECT_ROOT/flutter_app" && flutter build macos --release)

echo "🐍 [2/4] Nhúng py_engine & Native Binaries vào Contents/Resources/..."
RESOURCES_DIR="$APP_SRC/Contents/Resources"
mkdir -p "$RESOURCES_DIR/py_engine"
rsync -av --exclude '__pycache__' --exclude '*.pyc' --exclude '.DS_Store' --exclude 'tests' --exclude '.pytest_cache' "$PROJECT_ROOT/py_engine/" "$RESOURCES_DIR/py_engine/"

if [ -f "$PROJECT_ROOT/rust_native/target/release/sub_video_vision_ocr" ]; then
  cp "$PROJECT_ROOT/rust_native/target/release/sub_video_vision_ocr" "$RESOURCES_DIR/"
  chmod +x "$RESOURCES_DIR/sub_video_vision_ocr"
fi

if [ -f "$PROJECT_ROOT/rust_native/target/release/sub_video_inpaint" ]; then
  cp "$PROJECT_ROOT/rust_native/target/release/sub_video_inpaint" "$RESOURCES_DIR/"
  chmod +x "$RESOURCES_DIR/sub_video_inpaint"
fi

if [ -f "$PROJECT_ROOT/rust_native/target/release/libsub_video_audio_dsp.dylib" ]; then
  cp "$PROJECT_ROOT/rust_native/target/release/libsub_video_audio_dsp.dylib" "$RESOURCES_DIR/"
fi

cat <<EOF > "$RESOURCES_DIR/engine_manifest.json"
{
  "version": "1.1.1",
  "engine_type": "python_core",
  "release_notes": "Bản v1.1.1: Tối ưu hoá toàn diện Pipeline (In-Memory Demucs, Adaptive Whisper MLX, Pure Async EdgeTTS, Fast Hardware Render).",
  "published_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF

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

echo ""
echo "=============================================================================="
echo "🎉 TẠO FILE CÀI ĐẶT DMG THÀNH CÔNG!"
echo "📁 File DMG : $OUTPUT_DMG"
echo "📦 Kích thước: $(ls -lh "$OUTPUT_DMG" | awk '{print $5}')"
echo "=============================================================================="
