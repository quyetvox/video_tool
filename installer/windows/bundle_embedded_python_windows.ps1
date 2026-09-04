# ==============================================================================
# Sub-Video AI: Windows Standalone Python Bundler (PowerShell)
# Sets up standalone Python 3.11 environment for Windows x64
# ==============================================================================

param (
    [string]$TargetDir = ""
)

$ErrorActionPreference = "Stop"

$ROOT_DIR = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $TargetDir) {
    $TargetDir = "$ROOT_DIR\flutter_app\build\windows\x64\runner\Release\python"
}

$PYTHON_VERSION = "3.11.8"
$RELEASE_TAG = "20240224"
$TAR_NAME = "cpython-${PYTHON_VERSION}+${RELEASE_TAG}-x86_64-pc-windows-msvc-shared-install_only.tar.gz"
$DOWNLOAD_URL = "https://github.com/astral-sh/python-build-standalone/releases/download/${RELEASE_TAG}/${TAR_NAME}"

$CACHE_DIR = "$ROOT_DIR\.cache_python_standalone_win"

Write-Host "[1/4] Preparing Standalone Python for Windows x64..." -ForegroundColor Cyan

if (-not (Test-Path $CACHE_DIR)) {
    New-Item -ItemType Directory -Path $CACHE_DIR -Force | Out-Null
}

$TAR_PATH = "$CACHE_DIR\$TAR_NAME"
if (-not (Test-Path $TAR_PATH)) {
    Write-Host "[2/4] Downloading Python Standalone Windows package ($TAR_NAME)..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $TAR_PATH
}

Write-Host "[3/4] Extracting Python to: $TargetDir" -ForegroundColor Yellow
if (Test-Path $TargetDir) {
    Remove-Item -Recurse -Force $TargetDir
}
New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null

tar -xzf $TAR_PATH -C $TargetDir --strip-components=1

$PYTHON_EXE = "$TargetDir\python.exe"
if (-not (Test-Path $PYTHON_EXE)) {
    Write-Error "[ERROR] python.exe not found in $TargetDir after extraction."
}

Write-Host "[4/4] Installing Python requirements into runtime..." -ForegroundColor Yellow
$REQ_FILE = "$ROOT_DIR\py_engine\requirements-windows.txt"
if (-not (Test-Path $REQ_FILE)) {
    $REQ_FILE = "$ROOT_DIR\py_engine\requirements.txt"
}
Write-Host "Using requirements file: $REQ_FILE" -ForegroundColor Cyan
& "$PYTHON_EXE" -m pip install --no-cache-dir --upgrade pip
& "$PYTHON_EXE" -m pip install --no-cache-dir -r "$REQ_FILE"
& "$PYTHON_EXE" -m pip cache purge -q -ErrorAction SilentlyContinue

Write-Host "[SUCCESS] Standalone Python bundle ready at: $TargetDir" -ForegroundColor Green
