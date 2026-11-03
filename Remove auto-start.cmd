@echo off
if not exist "%~dp0scripts\AutoStart.ps1" (
  echo.
  echo  This was started from INSIDE the zip, so the other files aren't next to it.
  echo.
  echo  Close this, right-click "DbD Clock Overlay.zip" and choose "Extract All...",
  echo  then open the extracted folder and run this file from there.
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\AutoStart.ps1" -Off
pause
