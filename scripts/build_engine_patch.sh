#!/bin/bash
set -e

# ==============================================================================
# Sub-Video AI: Fast Sidecar Engine Patch Builder (~2 seconds)
# Builds standalone native binaries for instant hot-update without Flutter rebuild
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/engine_patch"
PATCH_DIR="$HOME/Library/Application Support/SubVideo/engine"

echo "⚡ [1/3] Biên dịch Standalone Dart Engine Binary..."
mkdir -p "$DIST_DIR"
cd "$ROOT_DIR/video_engine"
dart compile exe bin/engine_cli.dart -o "$DIST_DIR/sub_video_engine"
chmod +x "$DIST_DIR/sub_video_engine"

echo "🦀 [2/3] Gom Rust Audio DSP & Apple Vision OCR..."
if [ -f "$ROOT_DIR/rust_native/target/release/libsub_video_audio_dsp.dylib" ]; then
  cp "$ROOT_DIR/rust_native/target/release/libsub_video_audio_dsp.dylib" "$DIST_DIR/"
fi

if [ -f "$ROOT_DIR/rust_native/target/release/sub_video_vision_ocr" ]; then
  cp "$ROOT_DIR/rust_native/target/release/sub_video_vision_ocr" "$DIST_DIR/"
  chmod +x "$DIST_DIR/sub_video_vision_ocr"
fi

if [ -f "$ROOT_DIR/rust_native/target/release/sub_video_inpaint" ]; then
  cp "$ROOT_DIR/rust_native/target/release/sub_video_inpaint" "$DIST_DIR/"
  chmod +x "$DIST_DIR/sub_video_inpaint"
fi

echo "✅ Đã tạo gói bản vá tại: $DIST_DIR"
ls -lh "$DIST_DIR"

if [ "$1" == "--install" ] || [ "$1" == "-i" ]; then
  echo "🚀 [3/3] Tự động cài đặt bản vá vào Application Support..."
  mkdir -p "$PATCH_DIR"
  cp -r "$DIST_DIR/"* "$PATCH_DIR/"
  chmod +x "$PATCH_DIR/sub_video_engine" 2>/dev/null || true
  chmod +x "$PATCH_DIR/sub_video_vision_ocr" 2>/dev/null || true
  xattr -d com.apple.quarantine "$PATCH_DIR"/* 2>/dev/null || true
  echo "🎉 Bản vá đã được cài đặt thành công tại: $PATCH_DIR"
  echo "👉 Flutter App sẽ tự động chạy bản vá mới nhất này ngay tức thì!"
fi
