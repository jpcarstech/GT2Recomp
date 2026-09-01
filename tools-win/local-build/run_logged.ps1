# Launches the game with its (normally hidden) console output captured.
# Play normally - get into a race for a couple of minutes - then QUIT the game.
# Output lands in gt2_out.txt / gt2_err.txt next to the exe.
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
if (-not (Test-Path $exe)) { Write-Host "Game exe not found."; Read-Host "Enter to exit"; exit 1 }
$out = Join-Path $diag 'gt2_out.txt'
$err = Join-Path $diag 'gt2_err.txt'
Write-Host "Launching with logging. Play (menu + a race), then quit the game normally."
$p = Start-Process -FilePath $exe -WorkingDirectory $root `
        -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -Wait
Write-Host ("Game exited (code {0})." -f $p.ExitCode)
Write-Host "Wrote gt2_out.txt and gt2_err.txt"
Read-Host "Press Enter to exit"
