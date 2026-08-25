#!/usr/bin/env bash
# ==============================================================================
# Sub-Video AI: One-Click Machine Setup Script
# Tự động thiết lập môi trường cho máy Mac mới
# ==============================================================================

set -e

echo "🚀 Bắt đầu thiết lập môi trường Sub-Video AI cho máy mới..."

# 1. Kiểm tra Homebrew & FFmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "📦 Đang cài đặt FFmpeg qua Homebrew..."
    if ! command -v brew &> /dev/null; then
        echo "⚠️ Máy chưa có Homebrew. Vui lòng cài đặt Homebrew tại https://brew.sh trước."
    else
        brew install ffmpeg
    fi
else
    echo "✅ Đã tìm thấy FFmpeg: $(which ffmpeg)"
fi

# 2. Tạo môi trường Python Virtualenv
if [ ! -d ".venv" ]; then
    echo "🐍 Đang khởi tạo môi trường Python virtualenv (.venv)..."
    python3 -m venv .venv
fi

echo "📥 Đang cài đặt các thư viện Python AI cần thiết..."
source .venv/bin/activate
pip install --upgrade pip
pip install -r py_engine/requirements.txt

# 3. Cài đặt App vào /Applications (Launchpad)
if [ -d "flutter_app/build/macos/Build/Products/Release/Sub-Video AI.app" ]; then
    echo "💻 Đang cài đặt Sub-Video AI vào Launchpad (/Applications)..."
    cp -R "flutter_app/build/macos/Build/Products/Release/Sub-Video AI.app" /Applications/
    xattr -cr "/Applications/Sub-Video AI.app" 2>/dev/null || true
fi

echo "=============================================================================="
echo "🎉 Thiết lập hoàn tất thành công 100%!"
echo "👉 Bạn có thể mở Sub-Video AI trực tiếp từ Launchpad hoặc Spotlight Search."
echo "=============================================================================="
