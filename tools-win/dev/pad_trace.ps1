# pad_trace.ps1 - log what the GAME sees from your controller, ~60 times a
# second, so per-frame jitter in the steering input can be measured.
#   .\tools\pad_trace.ps1 [seconds] [delay_seconds]
# Writes diagnostics\pad_trace.csv : t_ms, frame, buttons, analog, lx, ly, rx, ry
param([int]$seconds=8,[int]$delay=5)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$out = Join-Path $outDir 'pad_trace.csv'
function Send-Cmd([string]$cmd, [int]$timeout = 5000) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $c.ReceiveTimeout = $timeout
        $s = $c.GetStream()
        $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s)
        $w.WriteLine($cmd); $line = $r.ReadLine(); $c.Close(); return $line
    } catch { return $null }
}
if (-not (Send-Cmd '{"id":1,"cmd":"pad_status"}')) { Write-Host "game not reachable on 127.0.0.1:4370" -ForegroundColor Red; exit 1 }
Write-Host ("logging starts in {0} s - drive and steer through the wobble section..." -f $delay) -ForegroundColor Yellow
for ($t=$delay; $t -gt 0; $t--) { Write-Host ("  {0}" -f $t); Start-Sleep -Seconds 1 }
$rows = @("t_ms,frame,buttons,analog,lx,ly,rx,ry")
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.ElapsedMilliseconds -lt ($seconds * 1000)) {
    $p = Send-Cmd '{"id":2,"cmd":"pad_status"}'
    $f = Send-Cmd '{"id":3,"cmd":"frame"}'
    $fr = ''; if ($f -match '"frame":(\d+)') { $fr = $Matches[1] }
    $b = ''; $an = ''; $st = ''
    if ($p -match '"slot0":\{"buttons":"(0x[0-9A-Fa-f]+)","connected":(true|false),"analog":(true|false),"sticks":\[(\d+),(\d+),(\d+),(\d+)\]') {
        $b = $Matches[1]; $an = $Matches[3]; $st = "{0},{1},{2},{3}" -f $Matches[4],$Matches[5],$Matches[6],$Matches[7]
    }
    $rows += ("{0},{1},{2},{3},{4}" -f $sw.ElapsedMilliseconds, $fr, $b, $an, $st)
    Start-Sleep -Milliseconds 8
}
$rows | Set-Content $out
Write-Host ("done - {0} samples in diagnostics\pad_trace.csv" -f ($rows.Count-1)) -ForegroundColor Green
