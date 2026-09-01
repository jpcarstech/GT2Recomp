# play_software.ps1 - launch with the SOFTWARE rasterizer instead of OpenGL.
# The software path is the faithful reference: it is the same GP0/GTE stream,
# rasterized by our own DDA rather than by GL. If the seam lines are absent
# here and present in OpenGL, the bug is in the GL backend. If they are
# present in BOTH, the bug is upstream of the backend (GP0/GTE/PGXP feed)
# and no amount of renderer tuning will touch it.
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$exe = Join-Path $root 'Gran Turismo 2 Recompiled.exe'
if (-not (Test-Path $exe)) { Write-Host "no exe at $exe" -ForegroundColor Red; exit 1 }

$e = (Get-Item $exe).LastWriteTime
$b = Join-Path $root 'gt2recomp.bundle'
if ((Test-Path $b) -and ((Get-Item $b).LastWriteTime -gt $e)) {
    Write-Host "STALE: the bundle is newer than the exe - rebuild first." -ForegroundColor Red
    exit 1
}

Write-Host "launching with --renderer software ..." -ForegroundColor Cyan
Write-Host "(expect it to be SLOW - that is fine, we only need one look at the track)"
& $exe --renderer software
