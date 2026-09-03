@echo off
rem GT2Recomp - performance measurement run (docs/PERFORMANCE.md).
rem Starts a disc build with the runtime's own performance counters switched
rem on: every 5 seconds it logs the frame rate it achieved, how much of each
rem second went into emulation vs. waiting, what the GPU side cost, and how
rem much ran interpreted vs. from the native cache. Play a race for about a
rem minute (60 FPS on; then Original 30 fps for comparison if you like),
rem quit the game normally, and send gt2_benchmark.txt.
rem   Benchmark GT2.cmd            -> the Arcade disc build
rem   Benchmark GT2.cmd simulation -> that disc's build
setlocal
cd /d "%~dp0"
set LOG=%~dp0gt2_benchmark.txt
set TITLE=arcade
if not "%~1"=="" set TITLE=%~1
set PSX_RUNTIME_PERF_DIAG=1
set PSX_RUNTIME_PERF_DIAG_MS=5000
echo GT2Recomp benchmark  %DATE% %TIME%  title=%TITLE% > "%LOG%"
echo. >> "%LOG%"
set EXE=
for %%E in ("%~dp0titles\%TITLE%\*.exe") do set EXE=%%~fE
if "%EXE%"=="" (
    echo No build found under titles\%TITLE%.
    pause
    exit /b 1
)
echo Running %EXE%
echo Play a race for about a minute, then quit the game normally.
pushd "%~dp0titles\%TITLE%"
"%EXE%" >> "%LOG%" 2>&1
echo [exit code: %ERRORLEVEL%] >> "%LOG%"
popd
echo.
echo Wrote gt2_benchmark.txt - opening it now.
notepad "%LOG%"
