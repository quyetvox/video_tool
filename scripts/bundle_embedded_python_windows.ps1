# ==============================================================================
# Sub-Video AI: Windows Standalone Python Bundler (PowerShell)
# Tải và cấu hình môi trường Python 3.11 Standalone độc lập cho Windows x64
# ==============================================================================

param (
    [string]$TargetDir = "$PSScriptRoot\..\flutter_app\build\windows\x64\runner\Release\python"
)

$ErrorActionPreference = "Stop"

$PYTHON_VERSION = "3.11.8"
$RELEASE_TAG = "20240224"
$TAR_NAME = "cpython-${PYTHON_VERSION}+${RELEASE_TAG}-x86_64-pc-windows-msvc-install_only.tar.gz"
$DOWNLOAD_URL = "https://github.com/indygreg/python-build-standalone/releases/download/${RELEASE_TAG}/${TAR_NAME}"

$ROOT_DIR = (Resolve-Path "$PSScriptRoot\..").Path
$CACHE_DIR = "$ROOT_DIR\.cache_python_standalone_win"

Write-Host "🪟 [1/4] Bắt đầu chuẩn bị Standalone Python cho Windows x64..." -ForegroundColor Cyan

if (-not (Test-Path $CACHE_DIR)) {
    New-Item -ItemType Directory -Path $CACHE_DIR -Force | Out-Null
}

$TAR_PATH = "$CACHE_DIR\$TAR_NAME"
if (-not (Test-Path $TAR_PATH)) {
    Write-Host "⬇️ [2/4] Đang tải Python Standalone Windows ($TAR_NAME)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $TAR_PATH
}

Write-Host "📦 [3/4] Giải nén Python vào: $TargetDir" -ForegroundColor Yellow
if (Test-Path $TargetDir) {
    Remove-Item -Recurse -Force $TargetDir
}
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

tar -xzf $TAR_PATH -C $TargetDir --strip-components=1

$PYTHON_EXE = "$TargetDir\python.exe"
if (-not (Test-Path $PYTHON_EXE)) {
    Write-Error "❌ Không tìm thấy $PYTHON_EXE sau khi giải nén!"
}

Write-Host "📥 [4/4] Đang cài đặt thư viện vào Python Runtime Windows..." -ForegroundColor Yellow
& "$PYTHON_EXE" -m pip install --upgrade pip
& "$PYTHON_EXE" -m pip install -r "$ROOT_DIR\py_engine\requirements.txt"

Write-Host "🎉 HOÀN TẤT ĐÓNG GÓI STANDALONE PYTHON CHO WINDOWS!" -ForegroundColor Green
Write-Host "👉 Vị trí Python Runtime: $TargetDir" -ForegroundColor Green
