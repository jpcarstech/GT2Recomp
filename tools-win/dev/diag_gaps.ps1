# Capture the scenery-gap artifact + live PGXP state FROM THE RUNNING GAME.
#
# Run this WHILE PARKED AT A SPOT WHERE YOU CAN SEE THE GAPS (stationary is
# best - a moving car makes the A/B frames non-comparable). It writes
# everything to diagnostics\gaps\ for Claude to read directly off this disk.
#
#   .\tools\diag_gaps.ps1
#
# It captures the INTERNAL supersampled buffer (what your display magnifies),
# not the downscaled window, so a 1-pixel crack is actually visible.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root 'diagnostics\gaps'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$log  = Join-Path $out 'report.txt'
"" | Set-Content $log

function Send-Cmd([string]$cmd, [int]$timeout = 15000) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $c.ReceiveTimeout = $timeout
        $s = $c.GetStream()
        $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s)
        $w.WriteLine($cmd); $line = $r.ReadLine(); $c.Close(); return $line
    } catch { return "ERROR: $($_.Exception.Message)" }
}
function Log([string]$m) { Write-Host $m; Add-Content $log $m }

$probe = Send-Cmd '{"id":1,"cmd":"frame"}'
if (-not $probe -or $probe -like 'ERROR*') {
    Write-Host "Cannot reach the game on 127.0.0.1:4370 - is it running?" -ForegroundColor Red
    exit 1
}
Log "=== GT2 scenery-gap diagnostic  $(Get-Date -Format o) ==="
Log "frame        : $probe"
Log "pgxp state   : $(Send-Cmd '{"id":1,"cmd":"pgxp"}')"
Log "gpu_state    : $(Send-Cmd '{"id":1,"cmd":"gpu_state"}')"

# Triangle census over a short window: how much geometry is actually being
# corrected, and how much falls back to uncorrected integer positions.
[void](Send-Cmd '{"id":1,"cmd":"pgxp_tri","reset":1}')
Start-Sleep -Milliseconds 1500
Log "tri census   : $(Send-Cmd '{"id":1,"cmd":"pgxp_tri"}')"

# Capture the internal buffer under each fill mode. Same scene, so these are
# directly comparable IF the car is stationary.
foreach ($m in 0,1,3) {
    [void](Send-Cmd ('{"id":1,"cmd":"pgxp","gapfill":' + $m + '}'))
    Start-Sleep -Milliseconds 700
    $p = Join-Path $out ("shot_gapfill$m.png")
    $j = Send-Cmd ('{"id":2,"cmd":"screenshot_hires","path":"' + ($p -replace '\\','\\\\') + '"}')
    Log "gapfill=$m    : $j"
}
# And with geometry correction fully OFF, as the reference for what the
# uncorrected pipeline looks like at this exact spot.
[void](Send-Cmd '{"id":1,"cmd":"pgxp","geometry":0}')
Start-Sleep -Milliseconds 700
$p = Join-Path $out 'shot_pgxp_off.png'
Log "pgxp off     : $(Send-Cmd ('{"id":2,"cmd":"screenshot_hires","path":"' + ($p -replace '\\','\\\\') + '"}'))"
[void](Send-Cmd '{"id":1,"cmd":"pgxp","geometry":1}')
[void](Send-Cmd '{"id":1,"cmd":"pgxp","gapfill":3}')

Log ""
Log "Wrote $out"
Log "Shots: shot_gapfill0/1/3.png (fill off / precise-only / all-geometry) + shot_pgxp_off.png"
Write-Host ""
Write-Host "Done. Tell Claude it's ready - the files are on disk." -ForegroundColor Green
