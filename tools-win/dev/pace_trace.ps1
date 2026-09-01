# pace_trace.ps1 - record WHEN each new game frame was presented (SwapWindow
# wall-clock ms + emulated vsync counter) while you race, so frame pacing /
# judder can be measured directly. The frame CONTENT already matches
# DuckStation frame-for-frame; this checks the timing of those frames on your
# machine, which screenshots cannot show.
#
#   .\tools\pace_trace.ps1 [seconds] [delay_seconds]
#
# Writes diagnostics\pace_trace.csv (seq,frame,t_ms,path) and prints a
# histogram of the interval between consecutive presented frames (ms) and of
# the emulated vsyncs per frame. Steady 30 fps on a 60/120 Hz display should
# be ~33 ms every time; alternating 25/41 (or 17/50) = judder.
param([int]$seconds=12,[int]$delay=5)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$out = Join-Path $outDir 'pace_trace.csv'
function Send-Cmd([string]$cmd, [int]$timeout = 10000) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $c.ReceiveTimeout = $timeout
        $s = $c.GetStream()
        $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s)
        $w.WriteLine($cmd); $line = $r.ReadLine(); $c.Close(); return $line
    } catch { return $null }
}
if (-not (Send-Cmd '{"id":1,"cmd":"frame"}')) { Write-Host "game not reachable on 127.0.0.1:4370 - is it running (ONE instance)?" -ForegroundColor Red; exit 1 }
Write-Host ("recording starts in {0} s - be racing/replaying in the chase camera, camera panning..." -f $delay) -ForegroundColor Yellow
for ($t=$delay; $t -gt 0; $t--) { Write-Host ("  {0}" -f $t); Start-Sleep -Seconds 1 }
$events = @{}
$sw = [Diagnostics.Stopwatch]::StartNew()
$perf0 = Send-Cmd '{"id":9,"cmd":"frame_perf"}'
$cad   = Send-Cmd '{"id":11,"cmd":"present_cadence"}'
if ($cad) { Write-Host ("present cadence: " + $cad) -ForegroundColor Cyan }
while ($sw.ElapsedMilliseconds -lt ($seconds * 1000)) {
    $j = Send-Cmd '{"id":2,"cmd":"gl_present_ring","n":600}'
    if ($j) {
        # events: [seq, frame, "path", t_ms, [..],[..],[..], glerr, [..]]
        $ms = [regex]::Matches($j, '\[(\d+),(\d+),"([a-z?]+)",(\d+),\[')
        foreach ($m in $ms) {
            $seq = [int64]$m.Groups[1].Value
            if (-not $events.ContainsKey($seq)) {
                $events[$seq] = "{0},{1},{2},{3}" -f $seq, $m.Groups[2].Value, $m.Groups[4].Value, $m.Groups[3].Value
            }
        }
    }
    Start-Sleep -Milliseconds 1000
}
$perf1 = Send-Cmd '{"id":9,"cmd":"frame_perf"}'
$pace  = Send-Cmd '{"id":10,"cmd":"pace_state"}'
$keys = $events.Keys | Sort-Object
$rows = @("seq,frame,t_ms,path")
foreach ($k in $keys) { $rows += $events[$k] }
$rows | Set-Content $out
Add-Content $out ("# frame_perf_start " + $perf0)
Add-Content $out ("# frame_perf_end " + $perf1)
Add-Content $out ("# pace_state " + $pace)
Add-Content $out ("# present_cadence " + $cad)
# --- summary ---
$prevT = $null; $prevF = $null
$dt = @{}; $dv = @{}
foreach ($k in $keys) {
    $p = $events[$k].Split(',')
    $f = [int64]$p[1]; $t = [int64]$p[2]
    if ($prevT -ne $null) {
        $d = $t - $prevT; $v = $f - $prevF
        if (-not $dt.ContainsKey($d)) { $dt[$d] = 0 }; $dt[$d]++
        if (-not $dv.ContainsKey($v)) { $dv[$v] = 0 }; $dv[$v]++
    }
    $prevT = $t; $prevF = $f
}
Write-Host ("done - {0} presented frames in diagnostics\pace_trace.csv" -f $keys.Count) -ForegroundColor Green
Write-Host "interval between presented frames (ms) : count"
foreach ($d in ($dt.Keys | Sort-Object)) { Write-Host ("  {0,4} ms : {1}" -f $d, $dt[$d]) }
Write-Host "emulated vsyncs per presented frame : count"
foreach ($v in ($dv.Keys | Sort-Object)) { Write-Host ("  {0,4}    : {1}" -f $v, $dv[$v]) }
