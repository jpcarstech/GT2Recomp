@echo off
rem GT2Recomp - double-click to build the game. Runs setup_and_build.ps1 beside
rem this file without needing to change the PowerShell execution policy.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_and_build.ps1"
