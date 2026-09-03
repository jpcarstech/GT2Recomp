@echo off
rem GT2Recomp - tidy the game folder: moves leftovers from older layouts, test
rem installs, disc-transfer chunks and freeze dumps into _old\ (nothing is
rem deleted), so "Gran Turismo 2 Recompiled.exe" is the one thing to launch.
if exist "%~dp0tools\tidy_game_folder.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\tidy_game_folder.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tidy_game_folder.ps1"
)
