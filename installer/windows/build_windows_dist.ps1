# ==============================================================================
# Sub-Video AI: Complete Windows Distribution Builder (PowerShell)
# ==============================================================================

$ErrorActionPreference = "Stop"

$ROOT_DIR = (Resolve-Path "$PSScriptRoot\..\..").Path
$FLUTTER_APP_DIR = "$ROOT_DIR\flutter_app"
$RELEASE_DIR = "$FLUTTER_APP_DIR\build\windows\x64\runner\Release"
$RELEASES_WIN_DIR = "$ROOT_DIR\releases\win"
$DIST_DIR = "$ROOT_DIR\dist"

# Extract Version from pubspec.yaml
$APP_VERSION = "1.0.0"
$PUBSPEC_PATH = "$FLUTTER_APP_DIR\pubspec.yaml"
if (Test-Path $PUBSPEC_PATH) {
    $PUBSPEC_CONTENT = Get-Content $PUBSPEC_PATH -Raw
    if ($PUBSPEC_CONTENT -match 'version:\s*([0-9.]+)') {
        $APP_VERSION = $matches[1]
    }
}

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " [INFO] Starting Sub-Video AI Windows x64 Build (v$APP_VERSION)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 0. Kill existing running processes to prevent MSB3073 write-locking
Write-Host "`n[0/5] Checking and terminating running sub_video_desktop instances..." -ForegroundColor Yellow
Get-Process -Name "sub_video_desktop", "sub_video" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500

# 1. Build Flutter Desktop Windows Release
Write-Host "`n[1/5] Compiling Flutter Desktop Windows (Release)..." -ForegroundColor Yellow
Push-Location $FLUTTER_APP_DIR
try {
    flutter build windows --release
} finally {
    Pop-Location
}

$FOUND_EXE = (Test-Path "$RELEASE_DIR\sub_video_desktop.exe") -or (Test-Path "$RELEASE_DIR\sub_video.exe")
if (-not $FOUND_EXE) {
    Write-Error "[ERROR] sub_video_desktop.exe not found at $RELEASE_DIR after build."
}

# 2. Copy py_engine into Release\py_engine
Write-Host "`n[2/5] Copying py_engine to application folder..." -ForegroundColor Yellow
$DEST_PY_ENGINE = "$RELEASE_DIR\py_engine"
if (Test-Path $DEST_PY_ENGINE) {
    Remove-Item -Recurse -Force $DEST_PY_ENGINE
}
New-Item -ItemType Directory -Path $DEST_PY_ENGINE -Force | Out-Null

$COMPILED_ENGINE = "$ROOT_DIR\dist\engine_patch\py_engine"
if (Test-Path $COMPILED_ENGINE) {
    robocopy "$COMPILED_ENGINE" "$DEST_PY_ENGINE" /E | Out-Null
} else {
    $EXCLUDE_DIRS = @("__pycache__", ".pytest_cache", "tests", ".git")
    robocopy "$ROOT_DIR\py_engine" "$DEST_PY_ENGINE" /E /XD $EXCLUDE_DIRS /XF "*.DS_Store" | Out-Null
}

# 3. Prepare Standalone Python Runtime
Write-Host "`n[3/5] Setting up Embedded Python Runtime in Release\python..." -ForegroundColor Yellow
& "$PSScriptRoot\bundle_embedded_python_windows.ps1" -TargetDir "$RELEASE_DIR\python"

# Ensure bytecode compilation and strip .py sources
$PY_EXE = "$RELEASE_DIR\python\python.exe"
if (Test-Path $PY_EXE) {
    Write-Host "Compiling Python bytecode .pyc and concealing .py source..." -ForegroundColor Yellow
    & $PY_EXE -m compileall -b -q "$DEST_PY_ENGINE"
    Get-ChildItem -Path "$DEST_PY_ENGINE" -Recurse -Filter "*.py" | Remove-Item -Force -ErrorAction SilentlyContinue
}

# 4. Download and embed FFmpeg for Windows
Write-Host "`n[4/5] Preparing FFmpeg binaries for Windows..." -ForegroundColor Yellow
$DEST_BIN = "$RELEASE_DIR\bin"
if (-not (Test-Path $DEST_BIN)) {
    New-Item -ItemType Directory -Path $DEST_BIN -Force | Out-Null
}

$FFMPEG_EXE = "$DEST_BIN\ffmpeg.exe"
$FFPROBE_EXE = "$DEST_BIN\ffprobe.exe"

if (-not (Test-Path $FFMPEG_EXE) -or -not (Test-Path $FFPROBE_EXE)) {
    $CACHE_FFMPEG = "$ROOT_DIR\.cache_ffmpeg_win"
    if (-not (Test-Path $CACHE_FFMPEG)) {
        New-Item -ItemType Directory -Path $CACHE_FFMPEG -Force | Out-Null
    }
    $FFMPEG_ZIP = "$CACHE_FFMPEG\ffmpeg-release-essentials.zip"
    if (-not (Test-Path $FFMPEG_ZIP)) {
        Write-Host "Downloading FFmpeg Static Build for Windows..." -ForegroundColor Yellow
        $FFMPEG_URL = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
        Invoke-WebRequest -Uri $FFMPEG_URL -OutFile $FFMPEG_ZIP
    }
    Write-Host "Extracting ffmpeg.exe and ffprobe.exe..." -ForegroundColor Yellow
    Expand-Archive -Path $FFMPEG_ZIP -DestinationPath "$CACHE_FFMPEG\extracted" -Force
    $FOUND_FFMPEG = Get-ChildItem -Path "$CACHE_FFMPEG\extracted" -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
    $FOUND_FFPROBE = Get-ChildItem -Path "$CACHE_FFMPEG\extracted" -Recurse -Filter "ffprobe.exe" | Select-Object -First 1
    if ($FOUND_FFMPEG -and $FOUND_FFPROBE) {
        Copy-Item -Path $FOUND_FFMPEG.FullName -Destination $FFMPEG_EXE -Force
        Copy-Item -Path $FOUND_FFPROBE.FullName -Destination $FFPROBE_EXE -Force
    }
}

# 5. Compile Inno Setup Installer (.exe)
Write-Host "`n[5/5] Packaging Installer with Inno Setup (.exe)..." -ForegroundColor Yellow
if (-not (Test-Path $RELEASES_WIN_DIR)) {
    New-Item -ItemType Directory -Path $RELEASES_WIN_DIR -Force | Out-Null
}

$ISCC_PATHS = @(
    "ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles}\Inno Setup 6\ISCC.exe"
)

$ISCC_FOUND = $null
foreach ($p in $ISCC_PATHS) {
    if (Get-Command $p -ErrorAction SilentlyContinue) {
        $ISCC_FOUND = $p
        break
    } elseif (Test-Path $p) {
        $ISCC_FOUND = $p
        break
    }
}

if ($ISCC_FOUND) {
    Write-Host "Compiling installer with $ISCC_FOUND..." -ForegroundColor Yellow
    & "$ISCC_FOUND" "$PSScriptRoot\setup.iss"
    Write-Host "[SUCCESS] Installer executable created in releases/win/ folder." -ForegroundColor Green
} else {
    Write-Error "[ERROR] Inno Setup Compiler (ISCC.exe) not found. Required to build Windows .exe installer."
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host " [COMPLETED] Windows packaging finished successfully!" -ForegroundColor Green
Write-Host " Releases directory : $RELEASES_WIN_DIR" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
