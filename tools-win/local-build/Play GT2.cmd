@echo off
rem Double-clickable launcher: play, then auto-build the native-code cache.
if exist "%~dp0tools\play_gt2.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\play_gt2.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0play_gt2.ps1"
)
