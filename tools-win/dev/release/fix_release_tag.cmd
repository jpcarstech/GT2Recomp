@echo off
rem GT2Recomp - point a release tag at the commit that is actually on GitHub main.
rem Lives in <game folder>\release\ beside GT2Recomp-public; run after push_update.cmd.
rem   fix_release_tag.cmd v0.3.0   (the tag is required - it is never guessed)
rem push_update.cmd rebases the bundle's release commit onto GitHub's history, which
rem gives it a new id; the tag was pushed pointing at the pre-rebase id. Same content,
rem but GitHub then shows "N commits since this release" and the tag is off main.
setlocal
if "%~1"=="" ( echo usage: fix_release_tag.cmd vX.Y.Z   - the tag of the release you just pushed & pause & exit /b 1 )
set TAG=%~1
set OUT=%~dp0GT2Recomp-public
set GIT=
where git >nul 2>nul && set GIT=git
if not defined GIT if exist "%ProgramFiles%\Git\cmd\git.exe" set GIT=%ProgramFiles%\Git\cmd\git.exe
if not defined GIT if exist C:\msys64\usr\bin\git.exe set GIT=C:\msys64\usr\bin\git.exe
if not defined GIT ( echo git not found. & pause & exit /b 1 )
cd /d "%OUT%" || ( echo GT2Recomp-public not found - run push_update.cmd first. & pause & exit /b 1 )
"%GIT%" fetch origin main || ( pause & exit /b 1 )
echo == GitHub main is now:
"%GIT%" log --format="%%h %%s" -1 origin/main
"%GIT%" tag -f %TAG% origin/main
"%GIT%" push -f origin refs/tags/%TAG% || ( echo tag push failed. & pause & exit /b 1 )
rem Hand GitHub's exact history back so the next release builds on it directly.
"%GIT%" bundle create "%~dp0github_main.bundle" origin/main
echo DONE - %TAG% now points at GitHub main; github_main.bundle written for Claude.
pause
