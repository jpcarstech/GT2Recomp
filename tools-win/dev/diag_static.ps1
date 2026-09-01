# Static-dispatch blockage capture. Run DURING A RACE. Grabs the dirty-RAM /
# text-guard bitmaps that decide whether the statically recompiled EXE code
# (libgpu, engine) may run native, plus dispatch counters before and after a
# 10-second window. Writes gt2_static.txt
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_static.txt'
$results = New-Object System.Collections.Generic.List[string]

function Send-Cmd([string]$cmd, [int]$timeout = 15000) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $client.ReceiveTimeout = $timeout
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($cmd)
        $sb = New-Object System.Text.StringBuilder
        $first = $true
        while ($true) {
            $line = $null
            try {
                if (-not $first) { $client.ReceiveTimeout = 800 }
                $line = $reader.ReadLine()
            } catch { break }
            if ($null -eq $line) { break }
            [void]$sb.AppendLine($line)
            $first = $false
        }
        $client.Close()
        return $sb.ToString().TrimEnd()
    } catch { return "ERR: $($_.Exception.Message)" }
}

$f = Send-Cmd '{"id":1,"cmd":"frame"}' 4000
$results.Add("frame: $f")
if ($f -notmatch '"frame"') { Write-Host "Game not reachable."; Read-Host "Enter"; exit 1 }

$results.Add("--- dirty_ram_stats (t0) ---")
$results.Add((Send-Cmd '{"id":2,"cmd":"dirty_ram_stats"}' 15000))
$results.Add("--- overlay_loader_status (t0) ---")
$results.Add((Send-Cmd '{"id":3,"cmd":"overlay_loader_status"}' 8000))
Write-Host "Sampling a 10-second window - keep racing..."
Start-Sleep -Seconds 10
$results.Add("--- dirty_ram_stats (t1, +10s) ---")
$results.Add((Send-Cmd '{"id":4,"cmd":"dirty_ram_stats"}' 15000))
$results.Add("--- overlay_loader_status (t1) ---")
$results.Add((Send-Cmd '{"id":5,"cmd":"overlay_loader_status"}' 8000))
$results.Add("--- frame_perf ---")
$results.Add((Send-Cmd '{"id":6,"cmd":"frame_perf"}' 8000))

[System.IO.File]::WriteAllLines($out, $results)
Write-Host "Wrote $out"
Read-Host "Press Enter to exit"
