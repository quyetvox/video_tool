# ==============================================================================
# Sub-Video AI: Windows AI Runtime Packager (PowerShell)
# Packages Torch CPU, Demucs, Whisper, etc. into SubVideo-AI-Runtime-Win64.zip
# ==============================================================================

param (
    [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"

$ROOT_DIR = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $OutputDir) {
    $OutputDir = "$ROOT_DIR\releases\ai"
}
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$CACHE_DIR = "$ROOT_DIR\.cache_python_standalone_win"
$PYTHON_EXE = "$CACHE_DIR\python\python.exe"

# If standalone python is not cached in .cache_python_standalone_win\python, extract it
if (-not (Test-Path $PYTHON_EXE)) {
    $RELEASE_DIR_PY = "$ROOT_DIR\flutter_app\build\windows\x64\runner\Release\python\python.exe"
    if (Test-Path $RELEASE_DIR_PY) {
        $PYTHON_EXE = $RELEASE_DIR_PY
    } else {
        Write-Host "Preparing Standalone Python for staging..." -ForegroundColor Cyan
        & "$PSScriptRoot\bundle_embedded_python_windows.ps1" -TargetDir "$CACHE_DIR\python"
        $PYTHON_EXE = "$CACHE_DIR\python\python.exe"
    }
}

Write-Host "Using Python engine: $PYTHON_EXE" -ForegroundColor Cyan

$STAGING_DIR = "$ROOT_DIR\dist\ai_runtime_win_staging"
$SITE_PACKAGES = "$STAGING_DIR\site-packages"

if (Test-Path $STAGING_DIR) {
    Remove-Item -Recurse -Force $STAGING_DIR
}
New-Item -ItemType Directory -Path $SITE_PACKAGES -Force | Out-Null

$REQ_AI = "$ROOT_DIR\py_engine\requirements-ai-windows.txt"
Write-Host "Installing AI runtime packages into staging ($SITE_PACKAGES)..." -ForegroundColor Yellow
& "$PYTHON_EXE" -m pip install --no-cache-dir --target "$SITE_PACKAGES" -r "$REQ_AI"

# Write metadata
$MANIFEST = @{
    "version" = "1.0.0"
    "platform" = "windows-x64"
    "type" = "ai_runtime"
    "packages" = @("torch", "torchaudio", "demucs", "openai-whisper", "scipy", "opencv-python", "soundfile", "rapidocr-onnxruntime")
} | ConvertTo-Json -Depth 3

Set-Content -Path "$STAGING_DIR\runtime_info.json" -Value $MANIFEST -Encoding UTF8

# Compress to Zip
$ZIP_OUTPUT = "$OutputDir\SubVideo-AI-Runtime-Win64.zip"
if (Test-Path $ZIP_OUTPUT) {
    Remove-Item -Force $ZIP_OUTPUT
}

Write-Host "Compressing AI Runtime to: $ZIP_OUTPUT..." -ForegroundColor Yellow
Compress-Archive -Path "$STAGING_DIR\*" -DestinationPath $ZIP_OUTPUT -CompressionLevel Optimal

$FILE_INFO = Get-Item $ZIP_OUTPUT
$HASH = (Get-FileHash -Path $ZIP_OUTPUT -Algorithm SHA256).Hash.ToLower()

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host " [SUCCESS] Windows AI Runtime Package created!" -ForegroundColor Green
Write-Host " Path: $ZIP_OUTPUT" -ForegroundColor Green
Write-Host " Size: $([math]::Round($FILE_INFO.Length / 1MB, 2)) MB" -ForegroundColor Green
Write-Host " SHA256: $HASH" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
