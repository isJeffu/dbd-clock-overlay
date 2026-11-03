@echo off
cd /d "%TEMP%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Uninstall.ps1"
