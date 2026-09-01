# dump_ab.ps1 - the decisive A/B: the SAME frame captured at NATIVE 320x240
# and at the full internal resolution. If the teal lines exist in one and not
# the other, the bug is in the high-resolution path, not in the draw stream.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

function Send-Cmd([string]$cmd, [int]$timeout = 120000) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $c.ReceiveTimeout = $timeout
        $s = $c.GetStream()
        $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s)
        $w.WriteLine($cmd); $line = $r.ReadLine(); $c.Close(); return $line
    } catch { Write-Host ("send failed: " + $_.Exception.Message) -ForegroundColor Red; return $null }
}

$nat = ((Join-Path $outDir 'ab_native.png') -replace '\\','/')
$hi  = ((Join-Path $outDir 'ab_hires.png')  -replace '\\','/')

Write-Host "capturing native..."
Write-Host ("  " + (Send-Cmd ('{"id":1,"cmd":"screenshot_file","path":"'   + $nat + '"}')))
Write-Host "capturing hires (may take a few seconds at 16x)..."
Write-Host ("  " + (Send-Cmd ('{"id":2,"cmd":"screenshot_hires","path":"' + $hi  + '"}')))
Write-Host ""
Write-Host "done - ab_native.png and ab_hires.png in diagnostics\"
