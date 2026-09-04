@echo off
rem GT2Recomp - one-off repair after the 0.3.0 release. fix_release_tag.cmd was run
rem without a tag name and its old default moved v0.2.0 onto the 0.3.0 commit,
rem while v0.3.0 (created by the GitHub release form) still sat on the 0.2.0 one.
rem This puts both back:
rem   v0.2.0 -> 49e7523 (the 0.2.0 release commit on GitHub main)
rem   v0.3.0 -> GitHub main (the 0.3.0 release commit)
rem and rewrites github_main.bundle. Safe to run more than once.
setlocal
set OUT=%~dp0GT2Recomp-public
set GIT=
where git >nul 2>nul && set GIT=git
if not defined GIT if exist "%ProgramFiles%\Git\cmd\git.exe" set GIT=%ProgramFiles%\Git\cmd\git.exe
if not defined GIT if exist C:\msys64\usr\bin\git.exe set GIT=C:\msys64\usr\bin\git.exe
if not defined GIT ( echo git not found. & pause & exit /b 1 )
cd /d "%OUT%" || ( echo GT2Recomp-public not found. & pause & exit /b 1 )
"%GIT%" fetch origin main || ( pause & exit /b 1 )
echo == GitHub main is:
"%GIT%" log --format="%%h %%s" -1 origin/main
"%GIT%" tag -f v0.2.0 49e7523088c20bd2f1a5a7c16bdd1cf82491e7f6
"%GIT%" tag -f v0.3.0 origin/main
"%GIT%" push -f origin refs/tags/v0.2.0 refs/tags/v0.3.0 || ( echo tag push failed. & pause & exit /b 1 )
"%GIT%" bundle create "%~dp0github_main.bundle" origin/main
echo.
echo DONE: v0.2.0 on 49e7523, v0.3.0 on GitHub main. Reload the releases page.
pause
