@echo off
if not exist "%~dp0scripts\Update.ps1" (
  echo.
  echo  This was started from INSIDE the zip - extract it first ^(right-click ^> Extract All^).
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Update.ps1"
