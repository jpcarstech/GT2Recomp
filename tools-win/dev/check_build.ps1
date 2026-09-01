# check_build.ps1 - is the exe you are about to test actually built from the
# bundle that is sitting on disk? Run this BEFORE judging any change.
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$exe    = Join-Path $root 'Gran Turismo 2 Recompiled.exe'
$bundle = Join-Path $root 'gt2recomp.bundle'

if (-not (Test-Path $exe))    { Write-Host "no exe found at $exe" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $bundle)) { Write-Host "no bundle found at $bundle" -ForegroundColor Yellow; exit 1 }

$e = (Get-Item $exe).LastWriteTime
$b = (Get-Item $bundle).LastWriteTime
Write-Host ""
Write-Host ("bundle : {0}" -f $b)
Write-Host ("exe    : {0}" -f $e)
Write-Host ""
if ($e -gt $b) {
    $age = [int]($e - $b).TotalSeconds
    Write-Host ("OK - exe is {0}s NEWER than the bundle. You are testing the current code." -f $age) -ForegroundColor Green
} else {
    $age = [int]($b - $e).TotalSeconds
    Write-Host ("STALE - the bundle is {0}s NEWER than the exe." -f $age) -ForegroundColor Red
    Write-Host "You have NOT rebuilt. Anything you observe right now is the OLD binary." -ForegroundColor Red
    Write-Host ""
    Write-Host "  .\setup_and_build.ps1"
    Write-Host "  .\tools\compile_cache.ps1"
}
Write-Host ""
