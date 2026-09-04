#!/usr/bin/env bash
# ==============================================================================
# Sub-Video AI: macOS ARM64 AI Runtime Packager
# Packages Demucs, MLX-Whisper, PyTorch into SubVideo-AI-Runtime-macOS-arm64.zip
# ==============================================================================
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT_DIR="${1:-$PROJECT_ROOT/releases/ai}"
mkdir -p "$OUTPUT_DIR"

STAGING_DIR="$PROJECT_ROOT/dist/ai_runtime_macos_staging"
SITE_PACKAGES="$STAGING_DIR/site-packages"

rm -rf "$STAGING_DIR"
mkdir -p "$SITE_PACKAGES"

PYTHON_BIN="python3"
if [ -f "$PROJECT_ROOT/venv/bin/python3" ]; then
  PYTHON_BIN="$PROJECT_ROOT/venv/bin/python3"
fi

echo "Using Python: $PYTHON_BIN"

REQ_FILE="$PROJECT_ROOT/py_engine/requirements-ai-macos.txt"
echo "📦 Installing macOS AI packages to staging ($SITE_PACKAGES)..."
"$PYTHON_BIN" -m pip install --no-cache-dir --target "$SITE_PACKAGES" -r "$REQ_FILE"

cat <<EOF > "$STAGING_DIR/runtime_info.json"
{
  "version": "1.0.0",
  "platform": "macos-arm64",
  "type": "ai_runtime",
  "packages": ["torch", "torchaudio", "demucs", "mlx-whisper", "soundfile", "scipy", "opencv-python"]
}
EOF

ZIP_OUTPUT="$OUTPUT_DIR/SubVideo-AI-Runtime-macOS-arm64.zip"
rm -f "$ZIP_OUTPUT"

echo "🗜️ Compressing to $ZIP_OUTPUT..."
(cd "$STAGING_DIR" && zip -r -q -9 "$ZIP_OUTPUT" .)

FILE_SIZE=$(du -sh "$ZIP_OUTPUT" | awk '{print $1}')
SHA256=$(shasum -a 256 "$ZIP_OUTPUT" | awk '{print $1}')

echo "================================================================"
echo "🎉 macOS AI Runtime Package created successfully!"
echo "📍 Output: $ZIP_OUTPUT"
echo "📊 Size  : $FILE_SIZE"
echo "🔑 SHA256: $SHA256"
echo "================================================================"
