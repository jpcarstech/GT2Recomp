# One-shot native-cache build: compiles the ENTIRE pending capture backlog in
# the foreground at full core count, then exits.
#
# WHY: the game spawns this same compiler in the background while you play,
# but it is killed the moment you quit — and the big hot-region compiles (the
# race engine code) take longer than a typical session, so they never finish
# and the game keeps interpreting its hottest code (~87% of dispatches in the
# last capture). Run THIS with the game CLOSED and let it run to completion;
# afterwards the next launch warm-loads the shards and races run native.
#
# Safe to re-run any time — already-built shards are skipped, and each play
# session that captures new code adds a little to the backlog.
param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
Set-Location $root
$tk = Join-Path $root 'overlay_toolchain'
$py = Join-Path $tk 'python\python.exe'
if (-not (Test-Path $py)) { Write-Host "Bundled python not found at $py"; Read-Host "Enter to exit"; exit 1 }
$caps = Join-Path $root 'overlay_captures.json'
if (-not (Test-Path $caps)) { Write-Host "No overlay_captures.json yet - play once first."; Read-Host "Enter to exit"; exit 1 }
if (Get-Process -Name 'Gran Turismo 2 Recompiled' -ErrorAction SilentlyContinue) {
    Write-Host "The game is running - close it first (it competes for the same captures file and CPU)."
    if (-not $NoPause) { Read-Host "Enter to exit" }; exit 1
}

# Mirror the runtime's spawn environment (autocompile.c pins these).
$env:PSX_OVERLAY_CACHE_DIR = Join-Path $root 'cache'
$env:PSX_OVERLAY_CAPTURES  = $caps
$env:PSX_OVERLAY_FLAVOR    = '6'   # PGXP hook build + 8MB RAM (flavor bits 2|4)
$env:PSX_OVERLAY_LIVE_AUTOCOMPILE = '1'

# gcc from the MSYS2 install setup_and_build.ps1 made (not on the global PATH).
$mingw = 'C:\msys64\mingw64\bin'
if ((Test-Path "$mingw\gcc.exe") -and ($env:Path -notlike "*$mingw*")) { $env:Path = "$mingw;$env:Path" }
$compiler = 'gcc'
if (-not (Get-Command gcc -ErrorAction SilentlyContinue)) {
    if (Test-Path (Join-Path $tk 'tcc\tcc.exe')) { $compiler = 'tcc' } else { Write-Host "No gcc on PATH and no bundled tcc - nothing can compile."; if (-not $NoPause) { Read-Host "Enter to exit" }; exit 1 }
}
$out = Join-Path $root 'compile_cache.txt'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host "Building the native-code cache (full backlog, all cores)."
Write-Host "This can take a while on the first run - leave it running to the end."
Write-Host ""
# Same command the game spawns (game.toml overlay_autocompile_cmd) except:
# no --jobs override, so the compiler's default (cores-2) applies - the game
# pins 8 to stay light while you play; offline we want the whole machine.
& $py (Join-Path $tk 'compile_overlays.py') `
    --captures $caps `
    --game-toml (Join-Path $root 'game.toml') `
    --recompiler (Join-Path $tk 'psxrecomp-game.exe') `
    --runtime-include (Join-Path $tk 'include') `
    --out-dir (Join-Path $root 'cache') `
    --compiler $compiler --tcc (Join-Path $tk 'tcc\tcc.exe') 2>&1 | Tee-Object -FilePath $out
$code = $LASTEXITCODE
$sw.Stop()
Write-Host ""
Write-Host ("Exit code {0} after {1:mm\:ss}. Full log: compile_cache.txt" -f $code, $sw.Elapsed)
$res = Select-String -Path $out -Pattern 'PSX_SHARD_RESULT' | Select-Object -Last 1
if ($res) { Write-Host $res.Line }
Write-Host "Launch the game normally - the new shards load at start."
if (-not $NoPause) { Read-Host "Press Enter to exit" } else { Start-Sleep -Seconds 3 }
