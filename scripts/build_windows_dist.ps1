# ==============================================================================
# Sub-Video AI: Complete Windows Distribution Builder (PowerShell)
# ==============================================================================

$ErrorActionPreference = "Stop"

$ROOT_DIR = (Resolve-Path "$PSScriptRoot\..").Path
$FLUTTER_APP_DIR = "$ROOT_DIR\flutter_app"
$RELEASE_DIR = "$FLUTTER_APP_DIR\build\windows\x64\runner\Release"
$DIST_DIR = "$ROOT_DIR\dist"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " 🚀 BẮT ĐẦU ĐÓNG GÓI SUB-VIDEO AI CHO WINDOWS X64" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

# 1. Build Flutter Desktop Windows Release
Write-Host "`n🔨 [1/6] Biên dịch Flutter Desktop Windows (Release)..." -ForegroundColor Yellow
Push-Location $FLUTTER_APP_DIR
try {
    flutter build windows --release
} finally {
    Pop-Location
}

if (-not (Test-Path "$RELEASE_DIR\sub_video.exe")) {
    Write-Error "❌ Không tìm thấy $RELEASE_DIR\sub_video.exe sau khi build Flutter!"
}

# 2. Nhúng py_engine vào thư mục Release\py_engine
Write-Host "`n🐍 [2/6] Sao chép py_engine vào thư mục ứng dụng..." -ForegroundColor Yellow
$DEST_PY_ENGINE = "$RELEASE_DIR\py_engine"
if (Test-Path $DEST_PY_ENGINE) {
    Remove-Item -Recurse -Force $DEST_PY_ENGINE
}
New-Item -ItemType Directory -Path $DEST_PY_ENGINE -Force | Out-Null

$EXCLUDE_DIRS = @("__pycache__", ".pytest_cache", "tests", ".git")
robocopy "$ROOT_DIR\py_engine" "$DEST_PY_ENGINE" /E /XD $EXCLUDE_DIRS /XF "*.pyc" "*.DS_Store" | Out-Null

# 3. Chuẩn bị Standalone Python Runtime
Write-Host "`n📦 [3/6] Chuẩn bị Embedded Python Runtime trong Release\python..." -ForegroundColor Yellow
& "$ROOT_DIR\scripts\bundle_embedded_python_windows.ps1" -TargetDir "$RELEASE_DIR\python"

# 4. Tải & Nhúng FFmpeg cho Windows
Write-Host "`n🎬 [4/6] Chuẩn bị FFmpeg binary cho Windows..." -ForegroundColor Yellow
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
        Write-Host "⬇️ Đang tải FFmpeg Static Build cho Windows..." -ForegroundColor Yellow
        $FFMPEG_URL = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
        Invoke-WebRequest -Uri $FFMPEG_URL -OutFile $FFMPEG_ZIP
    }
    Write-Host "📦 Giải nén ffmpeg.exe & ffprobe.exe..." -ForegroundColor Yellow
    Expand-Archive -Path $FFMPEG_ZIP -DestinationPath "$CACHE_FFMPEG\extracted" -Force
    $FOUND_FFMPEG = Get-ChildItem -Path "$CACHE_FFMPEG\extracted" -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1
    $FOUND_FFPROBE = Get-ChildItem -Path "$CACHE_FFMPEG\extracted" -Recurse -Filter "ffprobe.exe" | Select-Object -First 1
    if ($FOUND_FFMPEG -and $FOUND_FFPROBE) {
        Copy-Item -Path $FOUND_FFMPEG.FullName -Destination $FFMPEG_EXE -Force
        Copy-Item -Path $FOUND_FFPROBE.FullName -Destination $FFPROBE_EXE -Force
    }
}

# 5. Tạo bản nén Portable .zip
Write-Host "`n📁 [5/6] Tạo bản nén Portable (.zip)..." -ForegroundColor Yellow
if (-not (Test-Path $DIST_DIR)) {
    New-Item -ItemType Directory -Path $DIST_DIR -Force | Out-Null
}
$PORTABLE_ZIP = "$DIST_DIR\SubVideo_AI_Windows_Portable.zip"
if (Test-Path $PORTABLE_ZIP) {
    Remove-Item -Force $PORTABLE_ZIP
}
Compress-Archive -Path "$RELEASE_DIR\*" -DestinationPath $PORTABLE_ZIP -CompressionLevel Optimal
Write-Host "✅ Đã tạo Portable Zip: $PORTABLE_ZIP" -ForegroundColor Green

# 6. Biên dịch Inno Setup Installer (.exe) nếu có ISCC
Write-Host "`n💿 [6/6] Đóng gói bộ cài đặt Installer (Inno Setup)..." -ForegroundColor Yellow
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
    Write-Host "⚡ Đang biên dịch installer với $ISCC_FOUND..." -ForegroundColor Yellow
    & "$ISCC_FOUND" "$ROOT_DIR\installer\windows\setup.iss"
    Write-Host "✅ Đã tạo Installer Setup .exe trong thư mục dist/" -ForegroundColor Green
} else {
    Write-Host "ℹ️ Không tìm thấy Inno Setup Compiler (ISCC.exe). Bạn có thể tải Inno Setup để tạo file Setup.exe, hoặc sử dụng file Portable .zip vừa tạo." -ForegroundColor Gray
}

Write-Host "`n================================================================" -ForegroundColor Green
Write-Host " 🎉 HOÀN TẤT ĐÓNG GÓI SUB-VIDEO AI CHO WINDOWS!" -ForegroundColor Green
Write-Host " 📂 Xem kết quả tại thư mục: $DIST_DIR" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
