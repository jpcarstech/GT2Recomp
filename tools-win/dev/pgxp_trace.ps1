# pgxp_trace.ps1 - record the PGXP per-triangle ring continuously for a few
# seconds while you drive, so every triangle's native + precise position, depth
# and resolve state on THIS machine can be analyzed offline (what the frame
# capture shows as pixels, this shows as numbers).
#
#   .\tools\pgxp_trace.ps1 [seconds] [delay_seconds]
#
#   seconds - how long to record (default 8)
#   delay   - countdown before recording starts (default 5)
#
# Writes diagnostics\pgxptrace\tris_NNN.csv (one ring dump every ~150 ms; the
# ring holds ~3-4 frames so consecutive dumps overlap and nothing is missed)
# plus pgxptrace_index.txt. ~1 MB per dump, ~50-60 MB per 8 s run.
param([int]$seconds=8,[int]$delay=5)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics\pgxptrace'
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
Write-Host ("recording starts in {0} s - get driving where the wobble is worst..." -f $delay) -ForegroundColor Yellow
for ($t=$delay; $t -gt 0; $t--) { Write-Host ("  {0}" -f $t); Start-Sleep -Seconds 1 }
$idx = @("CFG " + $probe)
$idx += ("TRI0 " + (Send-Cmd '{"id":5,"cmd":"pgxp_tri","reset":1}'))
$sw = [Diagnostics.Stopwatch]::StartNew()
$n = 0
while ($sw.ElapsedMilliseconds -lt ($seconds * 1000)) {
    $p = (Join-Path $outDir ("tris_{0:D3}.csv" -f $n)) -replace '\\','/'
    $r = Send-Cmd ('{"id":2,"cmd":"pgxp_tris","path":"' + $p + '"}')
    $f = Send-Cmd '{"id":3,"cmd":"frame"}'
    $idx += ("{0:D3} t={1}ms {2} {3}" -f $n, $sw.ElapsedMilliseconds, $f, $r)
    $n++
    Start-Sleep -Milliseconds 150
}
$idx += ("TRI1 " + (Send-Cmd '{"id":6,"cmd":"pgxp_tri"}'))
$idx += ("CFG1 " + (Send-Cmd '{"id":7,"cmd":"pgxp"}'))
$idx | Set-Content (Join-Path $outDir 'pgxptrace_index.txt')
$mb = [math]::Round(((Get-ChildItem $outDir -Filter 'tris_*.csv' | Measure-Object Length -Sum).Sum / 1MB), 0)
Write-Host ("done - {0} dumps, {1} MB in diagnostics\pgxptrace\" -f $n, $mb) -ForegroundColor Green
