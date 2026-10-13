@echo off
setlocal EnableExtensions
cd /d "%~dp0"

REM Self-elevate via UAC when not already running as Administrator.
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo.
  echo Requesting Administrator privileges via UAC...
  echo If a consent prompt appears, choose Yes.
  echo.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -LiteralPath '%~f0' -Verb RunAs"
  if errorlevel 1 (
    echo.
    echo Could not elevate this installer.
    echo UAC may have been cancelled, or elevation is blocked by organization policy.
    echo That is an OS restriction — setup.cmd cannot bypass it.
    echo.
    pause
    exit /b 1
  )
  exit /b 0
)

set "RESUME_SETUP_VIA_CMD=1"

echo.
echo Reactive Resume — Offline Desktop Setup
echo Working directory: %CD%
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
set "SETUP_EXIT=%ERRORLEVEL%"

echo.
if not "%SETUP_EXIT%"=="0" (
  echo =====================================================
  echo  Setup failed ^(exit code %SETUP_EXIT%^)
  echo =====================================================
  echo Review the error messages above, fix the issue, then run setup.cmd again.
  echo.
  pause
  exit /b %SETUP_EXIT%
)

echo =====================================================
echo  Done — use the Desktop shortcut "Reactive Resume"
echo =====================================================
echo.
echo Next: double-click the Desktop shortcut and accept UAC when prompted.
echo.
pause
exit /b 0
