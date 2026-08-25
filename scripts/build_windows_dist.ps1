# ==============================================================================
# Sub-Video AI: Complete Windows Distribution Builder (PowerShell)
# ==============================================================================

$ErrorActionPreference = "Stop"

$ROOT_DIR = (Resolve-Path "$PSScriptRoot\..").Path
$FLUTTER_APP_DIR = "$ROOT_DIR\flutter_app"
$RELEASE_DIR = "$FLUTTER_APP_DIR\build\windows\x64\runner\Release"
$DIST_DIR = "$ROOT_DIR\dist"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " [INFO] Starting Sub-Video AI Windows x64 Build and Packaging" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Build Flutter Desktop Windows Release
Write-Host "`n[1/6] Compiling Flutter Desktop Windows (Release)..." -ForegroundColor Yellow
Push-Location $FLUTTER_APP_DIR
try {
    flutter build windows --release
} finally {
    Pop-Location
}

if (-not (Test-Path "$RELEASE_DIR\sub_video.exe")) {
    Write-Error "[ERROR] sub_video.exe not found at $RELEASE_DIR after build."
}

# 2. Copy py_engine into Release\py_engine
Write-Host "`n[2/6] Copying py_engine source to application folder..." -ForegroundColor Yellow
$DEST_PY_ENGINE = "$RELEASE_DIR\py_engine"
if (Test-Path $DEST_PY_ENGINE) {
    Remove-Item -Recurse -Force $DEST_PY_ENGINE
}
New-Item -ItemType Directory -Path $DEST_PY_ENGINE -Force | Out-Null

$EXCLUDE_DIRS = @("__pycache__", ".pytest_cache", "tests", ".git")
robocopy "$ROOT_DIR\py_engine" "$DEST_PY_ENGINE" /E /XD $EXCLUDE_DIRS /XF "*.pyc" "*.DS_Store" | Out-Null

# 3. Prepare Standalone Python Runtime
Write-Host "`n[3/6] Setting up Embedded Python Runtime in Release\python..." -ForegroundColor Yellow
& "$ROOT_DIR\scripts\bundle_embedded_python_windows.ps1" -TargetDir "$RELEASE_DIR\python"

# 4. Download and embed FFmpeg for Windows
Write-Host "`n[4/6] Preparing FFmpeg binaries for Windows..." -ForegroundColor Yellow
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

# 5. Create Portable zip archive
Write-Host "`n[5/6] Creating Portable archive (.zip)..." -ForegroundColor Yellow
if (-not (Test-Path $DIST_DIR)) {
    New-Item -ItemType Directory -Path $DIST_DIR -Force | Out-Null
}
$PORTABLE_ZIP = "$DIST_DIR\SubVideo_AI_Windows_Portable.zip"
if (Test-Path $PORTABLE_ZIP) {
    Remove-Item -Force $PORTABLE_ZIP
}
Compress-Archive -Path "$RELEASE_DIR\*" -DestinationPath $PORTABLE_ZIP -CompressionLevel Optimal
Write-Host "[SUCCESS] Created Portable Zip: $PORTABLE_ZIP" -ForegroundColor Green

# 6. Compile Inno Setup Installer (.exe)
Write-Host "`n[6/6] Packaging Installer with Inno Setup..." -ForegroundColor Yellow
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
    & "$ISCC_FOUND" "$ROOT_DIR\installer\windows\setup.iss"
    Write-Host "[SUCCESS] Installer executable created in dist/ folder." -ForegroundColor Green
} else {
    Write-Host "[INFO] Inno Setup Compiler (ISCC.exe) not found. You can use the Portable .zip package." -ForegroundColor Gray
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host " [COMPLETED] Windows packaging finished successfully!" -ForegroundColor Green
Write-Host " Output directory: $DIST_DIR" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
