# GT2 full diagnostic - run this WHILE the game is running, ideally during a
# race. Queries the runtime's debug server and writes gt2_diag_full.txt.
# Each command uses its OWN connection and failures don't stop the rest, so a
# crashing handler still leaves the other answers in the file.
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_diag_full.txt'
$results = New-Object System.Collections.Generic.List[string]

$cmds = @(
    '{"id":1,"cmd":"frame"}',
    '{"id":2,"cmd":"geom_correction"}',
    '{"id":3,"cmd":"autocompile_status"}',
    '{"id":4,"cmd":"gpu_state"}',
    '{"id":5,"cmd":"frame_perf"}',
    '{"id":6,"cmd":"read_ram","addr":2149406260,"len":1}',
    '{"id":7,"cmd":"read_ram","addr":2147576428,"len":8}',
    '{"id":8,"cmd":"read_ram","addr":2147576008,"len":4}'
)
# id6: 0x801D5634 (60fps divider)  id7: 0x80016A6C (gt2_01 fingerprint)
# id8: 0x800168C8 (tire-smoke slti site)

foreach ($c in $cmds) {
    $results.Add($c)
    try {
        $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $client.ReceiveTimeout = 8000
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($c)
        $line = $reader.ReadLine()
        if ($null -eq $line) { $results.Add("(no response)") } else { $results.Add($line) }
        $client.Close()
    } catch {
        $results.Add("ERROR: $($_.Exception.Message)")
    }
    Start-Sleep -Milliseconds 200
}
$results | Set-Content $out
Write-Host "Wrote $out"
Get-Content $out
Read-Host "Press Enter to exit"
