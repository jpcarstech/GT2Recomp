# Catch the scenery gaps IN MOTION. The still-frame capture came back clean,
# so if the artifact is temporal (LOD popping, wobble, seams that open only
# while moving) this is what will catch it.
#
# Start it, then DRIVE for ~20 seconds. It grabs the internal supersampled
# buffer once a second into diagnostics\gaps_motion\.
#
#   .\tools\diag_gaps_motion.ps1            (20 frames, ~20s)
#   .\tools\diag_gaps_motion.ps1 -Count 30  (longer)
param([int]$Count = 20, [int]$IntervalMs = 1000)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root 'diagnostics\gaps_motion'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Get-ChildItem $out -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

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

if ((Send-Cmd '{"id":1,"cmd":"frame"}') -like 'ERROR*') {
    Write-Host "Cannot reach the game on 127.0.0.1:4370 - is it running?" -ForegroundColor Red
    exit 1
}
Write-Host ""
Write-Host "START DRIVING NOW - capturing $Count frames." -ForegroundColor Yellow
Write-Host ""
for ($i = 1; $i -le $Count; $i++) {
    $p = Join-Path $out ("m{0:d2}.png" -f $i)
    [void](Send-Cmd ('{"id":2,"cmd":"screenshot_hires","path":"' + ($p -replace '\\','\\\\') + '"}'))
    Write-Host ("  {0,2}/{1}" -f $i, $Count) -NoNewline
    if ($i % 10 -eq 0) { Write-Host "" }
    Start-Sleep -Milliseconds $IntervalMs
}
Write-Host ""
Write-Host "Done -> $out" -ForegroundColor Green
Write-Host "Tell Claude it's ready." -ForegroundColor Green
