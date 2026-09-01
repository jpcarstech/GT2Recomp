# PGXP coverage census. Run DURING A RACE where cracks are visible.
# Captures which triangles mix corrected and uncorrected corners (the crack
# signature) and the RAM addresses of the corners that missed correction.
# Writes diagnostics\gt2_coverage.txt
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_coverage.txt'
function Send-Cmd([string]$cmd, [int]$timeout = 8000) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $client.ReceiveTimeout = $timeout
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($cmd)
        $line = $reader.ReadLine()
        $client.Close()
        return $line
    } catch { return "ERR: $($_.Exception.Message)" }
}
$r = New-Object System.Collections.Generic.List[string]
$r.Add("t0 census: " + (Send-Cmd '{"id":1,"cmd":"pgxp_tri","reset":1}'))
$r.Add("geom_correction t0: " + (Send-Cmd '{"id":2,"cmd":"geom_correction"}'))
Write-Host "Sampling 12 seconds - keep racing where the cracks show..."
Start-Sleep -Seconds 12
$r.Add("t1 census+samples: " + (Send-Cmd '{"id":3,"cmd":"pgxp_tri"}'))
$r.Add("geom_correction t1: " + (Send-Cmd '{"id":4,"cmd":"geom_correction"}'))
$r.Add("pgxp: " + (Send-Cmd '{"id":5,"cmd":"pgxp"}'))
[System.IO.File]::WriteAllLines($out, $r)
Write-Host "Wrote $out"
Read-Host "Press Enter to exit"
