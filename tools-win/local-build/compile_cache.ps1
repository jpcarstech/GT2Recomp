# One-shot native-cache build: compiles the ENTIRE pending capture backlog in
# the foreground at full core count, then exits.
#
# WHY: the game spawns this same compiler in the background while you play,
# and finishes the backlog after you quit — but the biggest hot-region
# compiles (the race engine code) can outlive both, so this runs everything
# to completion in one sitting. Run it with the game CLOSED; afterwards the
# next launch warm-loads the shards and races run native.
#
# Multi-disc installs: every installed disc under titles\<name>\ keeps its
# own capture backlog and cache; this compiles each one that has captures.
# Safe to re-run any time — already-built shards are skipped.
param([switch]$NoPause)
$ErrorActionPreference = 'Stop'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$tk = Join-Path $root 'overlay_toolchain'
$py = Join-Path $tk 'python\python.exe'
if (-not (Test-Path $py)) { Write-Host "Bundled python not found at $py"; Read-Host "Enter to exit"; exit 1 }
$running = Get-Process -ErrorAction SilentlyContinue |
           Where-Object { $_.ProcessName -like 'GT2 *' -or $_.ProcessName -eq 'Gran Turismo 2 Recompiled' }
if ($running) {
    Write-Host "The game is running - close it first (it competes for the same captures file and CPU)."
    if (-not $NoPause) { Read-Host "Enter to exit" }; exit 1
}

# The disc builds to compile for: titles\<name>\ (multi-disc layout), or the
# game root itself (pre-0.2 single-build layout).
$dirs = @()
$titles = Join-Path $root 'titles'
if (Test-Path $titles) {
    $dirs = @(Get-ChildItem -Path $titles -Directory | ForEach-Object { $_.FullName })
}
if ($dirs.Count -eq 0) { $dirs = @($root) }

# gcc from the MSYS2 install setup_and_build.ps1 made (not on the global PATH).
$mingw = 'C:\msys64\mingw64\bin'
if ((Test-Path "$mingw\gcc.exe") -and ($env:Path -notlike "*$mingw*")) { $env:Path = "$mingw;$env:Path" }
$compiler = 'gcc'
if (-not (Get-Command gcc -ErrorAction SilentlyContinue)) {
    if (Test-Path (Join-Path $tk 'tcc\tcc.exe')) { $compiler = 'tcc' } else { Write-Host "No gcc on PATH and no bundled tcc - nothing can compile."; if (-not $NoPause) { Read-Host "Enter to exit" }; exit 1 }
}

$did = 0
foreach ($d in $dirs) {
    $caps = Join-Path $d 'overlay_captures.json'
    if (-not (Test-Path $caps)) { continue }
    $did++
    $label = Split-Path -Leaf $d
    Write-Host ("== {0}: building the native-code cache (full backlog, all cores) ==" -f $label)
    Set-Location $d
    # Mirror the runtime's spawn environment (autocompile.c pins these).
    $env:PSX_OVERLAY_CACHE_DIR = Join-Path $d 'cache'
    $env:PSX_OVERLAY_CAPTURES  = $caps
    $env:PSX_OVERLAY_FLAVOR    = '6'   # PGXP hook build + 8MB RAM (flavor bits 2|4)
    $env:PSX_OVERLAY_LIVE_AUTOCOMPILE = '1'
    $out = Join-Path $d 'compile_cache.txt'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    # Same command the game spawns (game.toml overlay_autocompile_cmd) except:
    # no --jobs override, so the compiler's default (cores-2) applies - the
    # game pins 8 to stay light while you play; offline we want the machine.
    & $py (Join-Path $tk 'compile_overlays.py') `
        --captures $caps `
        --game-toml (Join-Path $d 'game.toml') `
        --recompiler (Join-Path $tk 'psxrecomp-game.exe') `
        --runtime-include (Join-Path $tk 'include') `
        --out-dir (Join-Path $d 'cache') `
        --compiler $compiler --tcc (Join-Path $tk 'tcc\tcc.exe') 2>&1 | Tee-Object -FilePath $out
    $code = $LASTEXITCODE
    $sw.Stop()
    Write-Host ("   exit code {0} after {1:mm\:ss}. Full log: {2}" -f $code, $sw.Elapsed, $out)
    $res = Select-String -Path $out -Pattern 'PSX_SHARD_RESULT' | Select-Object -Last 1
    if ($res) { Write-Host ("   " + $res.Line) }
    Write-Host ""
}
if ($did -eq 0) {
    Write-Host "No capture backlog found yet - play each disc once first."
} else {
    Write-Host "Launch the game normally - the new shards load at start."
}
if (-not $NoPause) { Read-Host "Press Enter to exit" } else { Start-Sleep -Seconds 3 }
