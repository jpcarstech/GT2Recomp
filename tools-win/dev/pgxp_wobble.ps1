# pgxp_wobble.ps1 - capture what the renderer is doing while you drive SLOWLY.
# Start driving first, then run this. Writes to diagnostics\:
#   wobble_tris.csv      every triangle of the last few frames (integer + sub-pixel corners)
#   wobble_ops.txt       GP0 opcode mix + PGXP counters over 2s
#   wobble_hires_N.png   4 back-to-back high-res frames (to see the wobble itself)
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
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
$log = @()
$log += "pgxp_wobble  " + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
$a  = Send-Cmd '{"id":1,"cmd":"gpu_opcodes"}'
$ga = Send-Cmd '{"id":2,"cmd":"geom_correction"}'
$ma = Send-Cmd '{"id":3,"cmd":"pgxp_mixed"}'
for ($i=0; $i -lt 4; $i++) {
    $p = (Join-Path $outDir ("wobble_hires_$i.png")) -replace '\\','/'
    $r = Send-Cmd ('{"id":4,"cmd":"screenshot_hires","path":"' + $p + '"}')
    $f = Send-Cmd '{"id":5,"cmd":"frame"}'
    $log += "shot $i : $r  $f"
}
Start-Sleep -Seconds 2
$b  = Send-Cmd '{"id":6,"cmd":"gpu_opcodes"}'
$gb = Send-Cmd '{"id":7,"cmd":"geom_correction"}'
$mb = Send-Cmd '{"id":8,"cmd":"pgxp_mixed"}'
$csv = (Join-Path $outDir 'wobble_tris.csv') -replace '\\','/'
$t = Send-Cmd ('{"id":9,"cmd":"pgxp_tris","path":"' + $csv + '"}')
$log += "tris   : $t"
$log += "A ops  : $a"
$log += "B ops  : $b"
$log += "A geom : $ga"
$log += "B geom : $gb"
$log += "A mixed: $ma"
$log += "B mixed: $mb"
$log += "P      : " + (Send-Cmd '{"id":10,"cmd":"pgxp"}')
$log | Set-Content (Join-Path $outDir 'wobble_ops.txt')
Write-Host "done - diagnostics\wobble_ops.txt, wobble_tris.csv, wobble_hires_0..3.png" -ForegroundColor Green
