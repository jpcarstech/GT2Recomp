# dump_gp0.ps1 - capture ONE frame of the GP0 draw-command stream while the
# artifact is on screen. Picks a frame that is actually still in the ring.
# Writes diagnostics\gp0_frame.json and diagnostics\gp0_opcodes.json.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

function Send-Cmd([string]$cmd, [int]$timeout = 40000) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $c.ReceiveTimeout = $timeout
        $s = $c.GetStream()
        $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s)
        $w.WriteLine($cmd)
        $line = $r.ReadLine(); $c.Close(); return $line
    } catch { Write-Host ("send failed: " + $_.Exception.Message) -ForegroundColor Red; return $null }
}

$rs = Send-Cmd '{"id":1,"cmd":"gpu_ring_stats"}'
if (-not $rs) { Write-Host "game not answering on 127.0.0.1:4370" -ForegroundColor Red; exit 1 }
$r = $rs | ConvertFrom-Json
Write-Host ("ring holds frames {0}..{1}  (capacity {2})" -f $r.oldest_frame, $r.newest_frame, $r.capacity)

$best = $null; $bestN = 0
# walk back from the newest frame in the ring until we find one with entries
for ($f = [int]$r.newest_frame; $f -ge [int]$r.oldest_frame -and $f -gt [int]$r.newest_frame - 6; $f--) {
    $d = Send-Cmd ('{"id":2,"cmd":"gpu_frame_dump","frame":' + $f + ',"count":65536}')
    if (-not $d) { continue }
    $n = 0
    try { $n = ([int](($d | ConvertFrom-Json).count)) } catch { $n = 0 }
    Write-Host ("  frame {0}: {1} entries" -f $f, $n)
    if ($n -gt $bestN) { $bestN = $n; $best = $d }
    if ($n -gt 500) { break }
}

if ($best) {
    $p = Join-Path $outDir 'gp0_frame.json'
    [IO.File]::WriteAllText($p, $best)
    Write-Host ("wrote {0}  ({1:N0} bytes, {2:N0} entries)" -f $p, $best.Length, $bestN) -ForegroundColor Green
} else {
    Write-Host "no frame in the ring had any entries" -ForegroundColor Red
}

$ops = Send-Cmd '{"id":3,"cmd":"gpu_opcodes"}'
if ($ops) { [IO.File]::WriteAllText((Join-Path $outDir 'gp0_opcodes.json'), $ops) }
Write-Host ""
Write-Host "done - files in diagnostics\"
