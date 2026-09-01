# dump_scene.ps1 - capture the SAME frame three ways so primitives can be
# matched to pixels: a native-resolution screenshot, the full GP0 command
# stream for that frame, and the whole VRAM as a PNG.
# Run parked on track with the teal lines clearly visible.
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

$shotPath = (Join-Path $outDir 'scene_native.png') -replace '\\','/'
$vramPath = (Join-Path $outDir 'scene_vram.png')  -replace '\\','/'

# 1. native-resolution screenshot (what the GP0 stream actually produced)
$r1 = Send-Cmd ('{"id":1,"cmd":"screenshot_file","path":"' + $shotPath + '"}')
Write-Host ("screenshot : " + $r1)

# 2. whole VRAM as an image - shows the texture pages the road samples from
$r2 = Send-Cmd ('{"id":2,"cmd":"screenshot_file","path":"' + $vramPath + '","vram":1}')
Write-Host ("vram       : " + $r2)

# 3. the GP0 stream for a frame still in the ring
$rs = Send-Cmd '{"id":3,"cmd":"gpu_ring_stats"}'
if ($rs) {
    $r = $rs | ConvertFrom-Json
    Write-Host ("ring holds frames {0}..{1}" -f $r.oldest_frame, $r.newest_frame)
    $best=$null; $bestN=0
    for ($f=[int]$r.newest_frame; $f -ge [int]$r.oldest_frame -and $f -gt [int]$r.newest_frame-6; $f--) {
        $d = Send-Cmd ('{"id":4,"cmd":"gpu_frame_dump","frame":' + $f + ',"count":65536}')
        if (-not $d) { continue }
        $n=0; try { $n=[int](($d|ConvertFrom-Json).count) } catch {}
        Write-Host ("  frame {0}: {1} entries" -f $f,$n)
        if ($n -gt $bestN) { $bestN=$n; $best=$d }
        if ($n -gt 500) { break }
    }
    if ($best) {
        [IO.File]::WriteAllText((Join-Path $outDir 'gp0_frame.json'), $best)
        Write-Host ("wrote gp0_frame.json ({0:N0} entries)" -f $bestN) -ForegroundColor Green
    }
}
Write-Host ""
Write-Host "done - scene_native.png, scene_vram.png, gp0_frame.json in diagnostics\"
