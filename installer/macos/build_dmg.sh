#!/usr/bin/env bash
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_SRC="$PROJECT_ROOT/flutter_app/build/macos/Build/Products/Release/Sub-Video AI.app"
RELEASES_MAC_DIR="$PROJECT_ROOT/releases/macos"
DIST_DIR="$PROJECT_ROOT/dist"
STAGING_DIR="/tmp/sub_video_dmg_staging"

# Extract Version from pubspec.yaml (e.g. 1.0.0)
PUBSPEC_FILE="$PROJECT_ROOT/flutter_app/pubspec.yaml"
RAW_VERSION=$(grep '^version:' "$PUBSPEC_FILE" | head -n 1 | awk '{print $2}' | tr -d '[:space:]')
APP_VERSION=$(echo "$RAW_VERSION" | cut -d'+' -f1)
BUILD_NUM=$(echo "$RAW_VERSION" | cut -d'+' -f2)
if [ -z "$APP_VERSION" ]; then
  APP_VERSION="1.0.0"
fi
if [ -z "$BUILD_NUM" ] || [ "$BUILD_NUM" = "$APP_VERSION" ]; then
  BUILD_NUM="1"
fi

# Auto-sync AppConstants.appVersion in flutter_app/lib/core/app_constants.dart
CONSTANTS_FILE="$PROJECT_ROOT/flutter_app/lib/core/app_constants.dart"
if [ -f "$CONSTANTS_FILE" ]; then
  sed -i '' -E "s/appVersion = 'v?[0-9.]+'/appVersion = 'v${APP_VERSION}'/" "$CONSTANTS_FILE" || true
  sed -i '' -E "s/buildNumber = '[0-9]+'/buildNumber = '${BUILD_NUM}'/" "$CONSTANTS_FILE" || true
  echo "🔄 [SYNC] Synchronized AppConstants: v${APP_VERSION} (Build ${BUILD_NUM})"
fi

VERSIONED_DMG="$RELEASES_MAC_DIR/SubVideo-AI-macOS-arm64-v${APP_VERSION}.dmg"
LATEST_DMG="$RELEASES_MAC_DIR/SubVideo-AI-macOS-arm64.dmg"
LEGACY_DMG="$DIST_DIR/Sub-Video-AI.dmg"

echo "📦 [0/4] Tự động cập nhật và đóng gói Lõi Core mới nhất..."
bash "$PROJECT_ROOT/scripts/package_engine_patch.sh" "$(cat "$PROJECT_ROOT/py_engine/VERSION" | tr -d '[:space:]')"

echo "🔨 [1/4] Biên dịch Flutter Desktop App (Release)..."
(cd "$PROJECT_ROOT/flutter_app" && flutter build macos --release)

echo "🐍 [2/4] Nhúng py_engine (.pyc), engine_manifest.json & Native Binaries vào Contents/Resources/..."
RESOURCES_DIR="$APP_SRC/Contents/Resources"
mkdir -p "$RESOURCES_DIR/py_engine"
rsync -av --delete "$PROJECT_ROOT/dist/engine_patch/py_engine/" "$RESOURCES_DIR/py_engine/"

if [ -f "$PROJECT_ROOT/releases/core/engine_manifest.json" ]; then
  cp "$PROJECT_ROOT/releases/core/engine_manifest.json" "$RESOURCES_DIR/engine_manifest.json"
elif [ -f "$PROJECT_ROOT/dist/engine_patch/engine_manifest.json" ]; then
  cp "$PROJECT_ROOT/dist/engine_patch/engine_manifest.json" "$RESOURCES_DIR/engine_manifest.json"
fi

if [ -f "$PROJECT_ROOT/rust_native/target/release/sub_video_vision_ocr" ]; then
  cp "$PROJECT_ROOT/rust_native/target/release/sub_video_vision_ocr" "$RESOURCES_DIR/"
  chmod +x "$RESOURCES_DIR/sub_video_vision_ocr"
elif [ -f "$PROJECT_ROOT/flutter_app/macos/Runner/sub_video_vision_ocr" ]; then
  cp "$PROJECT_ROOT/flutter_app/macos/Runner/sub_video_vision_ocr" "$RESOURCES_DIR/"
  chmod +x "$RESOURCES_DIR/sub_video_vision_ocr"
fi

if [ -f "$PROJECT_ROOT/rust_native/target/release/sub_video_inpaint" ]; then
  cp "$PROJECT_ROOT/rust_native/target/release/sub_video_inpaint" "$RESOURCES_DIR/"
  chmod +x "$RESOURCES_DIR/sub_video_inpaint"
fi

if [ -f "$PROJECT_ROOT/rust_native/target/release/libsub_video_audio_dsp.dylib" ]; then
  cp "$PROJECT_ROOT/rust_native/target/release/libsub_video_audio_dsp.dylib" "$RESOURCES_DIR/"
elif [ -f "$PROJECT_ROOT/flutter_app/macos/Runner/libsub_video_audio_dsp.dylib" ]; then
  cp "$PROJECT_ROOT/flutter_app/macos/Runner/libsub_video_audio_dsp.dylib" "$RESOURCES_DIR/"
fi

echo "📂 [3/4] Sao chép Sub-Video AI.app và tạo liên kết /Applications..."
mkdir -p "$RELEASES_MAC_DIR"
mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_SRC" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 [4/4] Tạo file DMG nén UDZO bằng hdiutil..."
rm -f "$VERSIONED_DMG" "$LATEST_DMG" "$LEGACY_DMG"
hdiutil create -volname "Sub-Video AI" \
  -srcfolder "$STAGING_DIR" \
  -ov -format UDZO \
  "$VERSIONED_DMG"

cp "$VERSIONED_DMG" "$LATEST_DMG"
cp "$VERSIONED_DMG" "$LEGACY_DMG"

rm -rf "$STAGING_DIR"

echo ""
echo "=============================================================================="
echo "🎉 TẠO FILE CÀI ĐẶT DMG THÀNH CÔNG!"
echo "📁 Thư mục phát hành Mac : $RELEASES_MAC_DIR"
echo "📦 DMG theo phiên bản    : $VERSIONED_DMG ($(ls -lh "$VERSIONED_DMG" | awk '{print $5}'))"
echo "📦 DMG mới nhất          : $LATEST_DMG"
echo "=============================================================================="
