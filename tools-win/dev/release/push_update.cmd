@echo off
rem GT2Recomp - push the latest release branch from gt2recomp.bundle to GitHub main.
rem Lives in <game folder>\release; the bundle sits one level up at the game root
rem (where Setup GT2.cmd builds from), the GitHub checkout beside this script.
rem Safe with edits made directly on GitHub: it fetches origin first and rebases
rem the bundle's commits on top, so nothing on GitHub is ever overwritten.
setlocal
set BUNDLE=%~dp0..\gt2recomp.bundle
set OUT=%~dp0GT2Recomp-public
set REMOTE=https://github.com/jpcarstech/GT2Recomp.git
set GIT=
where git >nul 2>nul && set GIT=git
if not defined GIT if exist "%ProgramFiles%\Git\cmd\git.exe" set GIT=%ProgramFiles%\Git\cmd\git.exe
if not defined GIT if exist C:\msys64\usr\bin\git.exe set GIT=C:\msys64\usr\bin\git.exe
if not defined GIT ( echo git not found - install Git for Windows from git-scm.com. & pause & exit /b 1 )
if not exist "%BUNDLE%" ( echo gt2recomp.bundle not found in the game folder above this one. & pause & exit /b 1 )
if not exist "%OUT%\.git" (
    echo == creating checkout from the bundle ==
    "%GIT%" clone -q -b release "%BUNDLE%" "%OUT%" || ( pause & exit /b 1 )
    cd /d "%OUT%"
    "%GIT%" remote set-url origin "%REMOTE%"
) else (
    cd /d "%OUT%"
)
"%GIT%" -c core.editor=true config user.name "John Accumanno"
"%GIT%" config user.email "jpaccumanno@gmail.com"
rem "+": the bundle's release history is rewritten to GitHub's after every push
rem (fix_release_tag.cmd), so the tracking ref here is never a fast-forward of it.
"%GIT%" fetch "%BUNDLE%" +release:refs/remotes/bundle/release || ( pause & exit /b 1 )
"%GIT%" fetch "%BUNDLE%" "refs/tags/*:refs/tags/*" 2>nul
"%GIT%" fetch origin main || ( echo could not reach GitHub - are you online / signed in? & pause & exit /b 1 )
"%GIT%" rebase --abort 2>nul
"%GIT%" checkout -q -B release bundle/release
echo == integrating anything committed on GitHub since the last push ==
"%GIT%" rebase origin/main || (
    echo.
    echo A file was changed BOTH on GitHub and in the bundle and git cannot merge
    echo them by itself. Nothing was pushed. Ask Claude to reconcile, or resolve
    echo the conflict in %OUT% and run: git rebase --continue, then this script.
    "%GIT%" rebase --abort 2>nul
    pause & exit /b 1
)
"%GIT%" log --format="%%h %%an - %%s" -4
echo.
echo == pushing to GitHub main ==
"%GIT%" push origin HEAD:main || ( echo push failed. & pause & exit /b 1 )
"%GIT%" push origin --tags
echo DONE.
pause
