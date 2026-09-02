@echo off
rem GT2Recomp - capture why the game exits immediately.
rem Runs each installed disc build with its output captured, then shows it.
setlocal enabledelayedexpansion
cd /d "%~dp0"
set LOG=%~dp0gt2_diag.txt
echo GT2Recomp diagnostic  %DATE% %TIME% > "%LOG%"
echo folder: %~dp0 >> "%LOG%"
echo. >> "%LOG%"
for /d %%T in ("titles\*") do (
    for %%E in ("%%~fT\*.exe") do (
        echo ================================================ >> "%LOG%"
        echo RUN: %%~nxE   in %%~fT >> "%LOG%"
        echo ================================================ >> "%LOG%"
        pushd "%%~fT"
        "%%~fE" >> "%LOG%" 2>&1
        echo [exit code: !ERRORLEVEL!] >> "%LOG%"
        popd
        echo. >> "%LOG%"
    )
)
echo ================================================ >> "%LOG%"
echo done. >> "%LOG%"
echo.
echo Wrote gt2_diag.txt - opening it now.
notepad "%LOG%"
