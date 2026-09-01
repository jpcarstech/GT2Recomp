# Play Gran Turismo 2, then top up the native-code cache on exit.
# Launches the game, waits until you quit, and runs compile_cache.ps1 so
# every session's newly captured code is compiled while you're away from
# the game - the next launch loads it and runs faster. When nothing new
# was captured, the compile step finishes in seconds.
$ErrorActionPreference = 'Stop'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$exe = Join-Path $root 'Gran Turismo 2 Recompiled.exe'
if (-not (Test-Path $exe)) { Write-Host "Game exe not found next to this script."; Read-Host "Enter to exit"; exit 1 }

# The game's background code compiler prefers a real gcc when one is on PATH
# (faster shards than the bundled TinyCC). setup_and_build.ps1 installs one
# with MSYS2; make it visible to the game process without touching the user's
# global PATH.
$mingw = 'C:\msys64\mingw64\bin'
if ((Test-Path "$mingw\gcc.exe") -and ($env:Path -notlike "*$mingw*")) { $env:Path = "$mingw;$env:Path" }

Write-Host "Starting Gran Turismo 2..."
$p = Start-Process -FilePath $exe -WorkingDirectory $root -PassThru
$p.WaitForExit()

Write-Host ""
Write-Host "Game closed - topping up the native-code cache (safe to minimize this window)."
& (Join-Path $sdir 'compile_cache.ps1') -NoPause
