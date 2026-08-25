@echo off
setlocal enabledelayedexpansion

echo =====================================================================
echo  SUB-VIDEO AI: 1-CLICK WINDOWS BUILD ^& PACKAGING SUITE
echo =====================================================================

set ROOT_DIR=%~dp0..
cd /d "%ROOT_DIR%"

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_DIR%\scripts\build_windows_dist.ps1"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo [SUCCESS] Windows Build ^& Packaging completed successfully!
) else (
    echo.
    echo [ERROR] Build failed with error code %ERRORLEVEL%.
)

pause
