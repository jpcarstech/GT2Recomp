# pgxp_framerec.ps1 - capture a burst of CONSECUTIVE PRESENTED FRAMES exactly as
# displayed (present-synchronized; every file is one complete game frame), so
# per-frame wobble/popping can be analyzed frame by frame.
#
#   .\tools\pgxp_framerec.ps1 [count] [div] [delay_seconds]
#
#   count  - frames to capture (default 240 = 8 s of 30 fps racing)
#   div    - downsample divisor of the WINDOW resolution (default 2:
#            a 3840x2160 fullscreen window -> 1920x1080 files, ~6 MB each,
#            ~1.5 GB for 240 frames; use 4 for ~370 MB)
#   delay  - seconds to wait before capture starts (default 5) so you can
#            alt-tab back and be driving at speed where the wobble is worst
#
# Writes diagnostics\framerec\frame_NNNNN.png + framerec_index.txt.
# The game slows down while it writes files - that's expected; the frames
# are still consecutive game frames. Drive through the section once, at speed,
# from the chase camera.
param([int]$count=240,[int]$div=2,[int]$delay=5)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics\framerec'
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
$probe = Send-Cmd '{"id":1,"cmd":"pgxp"}'
if (-not $probe) { Write-Host "game not reachable on 127.0.0.1:4370 - is it running (ONE instance)?" -ForegroundColor Red; exit 1 }
Write-Host ("capture starts in {0} s - get driving at speed, chase camera..." -f $delay) -ForegroundColor Yellow
for ($t=$delay; $t -gt 0; $t--) { Write-Host ("  {0}" -f $t); Start-Sleep -Seconds 1 }
$dir = $outDir -replace '\\','/'
$idx = @()
$idx += ("CFG " + $probe)
$sw = [Diagnostics.Stopwatch]::StartNew()
$arm = Send-Cmd ('{"id":2,"cmd":"framerec","dir":"' + $dir + '","count":' + $count + ',"div":' + $div + '}')
$idx += ("ARM t=0ms " + $arm)
Write-Host ("recording {0} frames (div {1}) -> diagnostics\framerec\ ..." -f $count, $div) -ForegroundColor Cyan
$last = -1
while ($true) {
    Start-Sleep -Milliseconds 500
    $st = Send-Cmd '{"id":3,"cmd":"framerec"}'
    if (-not $st) { break }
    $idx += ("ST t={0}ms {1}" -f $sw.ElapsedMilliseconds, $st)
    if ($st -match '"remaining":(\d+)') {
        $rem = [int]$Matches[1]
        if ($rem -ne $last) { Write-Host ("  remaining {0}" -f $rem); $last = $rem }
        if ($rem -eq 0) { break }
    }
    if ($sw.ElapsedMilliseconds -gt 600000) { Write-Host "timeout" -ForegroundColor Red; break }
}
$idx += ("END " + (Send-Cmd '{"id":4,"cmd":"frame"}'))
$idx | Set-Content (Join-Path $outDir 'framerec_index.txt')
$n = (Get-ChildItem $outDir -Filter 'frame_*.png').Count
$mb = [math]::Round(((Get-ChildItem $outDir -Filter 'frame_*.png' | Measure-Object Length -Sum).Sum / 1MB), 0)
Write-Host ("done - {0} frames, {1} MB in diagnostics\framerec\ ({2} ms)" -f $n, $mb, $sw.ElapsedMilliseconds) -ForegroundColor Green
Write-Host "Zip the folder (or just tell me it's there) and I'll analyze it." -ForegroundColor Green
