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
VERSION="1.1.1"

echo "🐍 [1/4] Đồng bộ và dọn dẹp thư mục py_engine..."
mkdir -p "$DIST_DIR/py_engine"
rsync -av --exclude '__pycache__' --exclude '*.pyc' --exclude '.DS_Store' --exclude 'tests' --exclude '.pytest_cache' "$ROOT_DIR/py_engine/" "$DIST_DIR/py_engine/"

echo "🍏 [2/4] Kiểm tra & Sao chép Swift Native OCR & Inpainter (nếu có)..."
if [ -f "$ROOT_DIR/rust_native/target/release/sub_video_vision_ocr" ]; then
  cp "$ROOT_DIR/rust_native/target/release/sub_video_vision_ocr" "$DIST_DIR/"
  chmod +x "$DIST_DIR/sub_video_vision_ocr"
fi

if [ -f "$ROOT_DIR/rust_native/target/release/sub_video_inpaint" ]; then
  cp "$ROOT_DIR/rust_native/target/release/sub_video_inpaint" "$DIST_DIR/"
  chmod +x "$DIST_DIR/sub_video_inpaint"
fi

if [ -f "$ROOT_DIR/rust_native/target/release/libsub_video_audio_dsp.dylib" ]; then
  cp "$ROOT_DIR/rust_native/target/release/libsub_video_audio_dsp.dylib" "$DIST_DIR/"
fi

echo "📝 [3/4] Tạo engine_manifest.json..."
cat <<EOF > "$DIST_DIR/engine_manifest.json"
{
  "version": "$VERSION",
  "engine_type": "python_core",
  "release_notes": "Bản vá v$VERSION: Nâng cấp chuyển đổi toàn diện Core Engine sang Python Engine (Whisper MLX / Demucs / EdgeTTS) hỗ trợ luồng log JSON thời gian thực, tối ưu tốc độ và độ chính xác dịch thuật.",
  "download_url": "dist/engine_patch",
  "published_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "size_bytes": 0
}
EOF

echo "📦 [4/4] Đóng gói engine_patch.zip..."
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
