# pgxp_burst.ps1 - grab a burst of consecutive frames of ONE screen region at
# full internal resolution, so frame-to-frame wobble can be measured.
#   .\tools\pgxp_burst.ps1 [cx cy cw ch] [count]
# cx,cy,cw,ch are NATIVE (320x240) display pixels; default = a 120x80 window
# in the upper middle of the screen (trackside objects ahead); count default 16.
# Writes diagnostics\burst\burst_NN.png plus burst_index.txt (frame numbers).
param([int]$cx=100,[int]$cy=60,[int]$cw=120,[int]$ch=80,[int]$count=16)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics\burst'
if (Test-Path $outDir) { Remove-Item (Join-Path $outDir '*') -Force }
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
function Send-Cmd([string]$cmd, [int]$timeout = 60000) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $c.ReceiveTimeout = $timeout
        $s = $c.GetStream()
        $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s)
        $w.WriteLine($cmd); $line = $r.ReadLine(); $c.Close(); return $line
    } catch { Write-Host ("send failed: " + $_.Exception.Message) -ForegroundColor Red; return $null }
}
$idx = @()
$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i=0; $i -lt $count; $i++) {
    $p = (Join-Path $outDir ("burst_{0:D2}.png" -f $i)) -replace '\\','/'
    $r = Send-Cmd ('{"id":4,"cmd":"screenshot_hires","path":"' + $p + '","cx":' + $cx + ',"cy":' + $cy + ',"cw":' + $cw + ',"ch":' + $ch + '}')
    $idx += ("{0:D2} t={1}ms {2}" -f $i, $sw.ElapsedMilliseconds, $r)
}
$idx += ("P " + (Send-Cmd '{"id":10,"cmd":"pgxp"}'))
$idx | Set-Content (Join-Path $outDir 'burst_index.txt')
Write-Host ("done - {0} frames in diagnostics\burst\ ({1} ms)" -f $count, $sw.ElapsedMilliseconds) -ForegroundColor Green
