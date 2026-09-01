# Stuck-screen diagnosis - run this WHILE the game is sitting on the stuck
# screen (opponent roster / course select / wherever). Leave the game open.
# Optional label argument names the output: .\diag_hang.ps1 roster
# Writes gt2_hang_<label>.txt
param([string]$label = 'capture')
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $root ("gt2_hang_{0}.txt" -f $label)
$results = New-Object System.Collections.Generic.List[string]

function Send-Cmd([string]$cmd) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $client.ReceiveTimeout = 8000
        $stream = $client.GetStream()
        $writer = New-Object System.IO.StreamWriter($stream)
        $reader = New-Object System.IO.StreamReader($stream)
        $writer.AutoFlush = $true
        $writer.WriteLine($cmd)
        $line = $reader.ReadLine()
        $client.Close()
        if ($null -eq $line) { return "(no response)" }
        return $line
    } catch { return "ERR: $($_.Exception.Message)" }
}

function Read-Block([long]$addr, [int]$len) {
    $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":{1}}}' -f $addr, $len
    return (Send-Cmd $q)
}

# Is the emulated CPU advancing? Two frame samples 2s apart.
$results.Add("frame sample 1: " + (Send-Cmd '{"id":1,"cmd":"frame"}'))
Start-Sleep -Seconds 2
$results.Add("frame sample 2: " + (Send-Cmd '{"id":1,"cmd":"frame"}'))

foreach ($c in @(
    '{"id":2,"cmd":"gpu_state"}',
    '{"id":3,"cmd":"frame_perf"}',
    '{"id":4,"cmd":"overlay_loader_status"}',
    '{"id":5,"cmd":"autocompile_status"}'
)) {
    $results.Add($c)
    $results.Add((Send-Cmd $c))
}

# Mod patch state - shows which enhancements are applied RIGHT NOW.
$results.Add("--- 8MB buffer setup 0x80016A60..0x80016AA0 (patched if 3C058020 at +C) ---")
$results.Add((Read-Block 0x80016A60L 64))
$results.Add("--- full-LOD site 0x80014340..0x80014350 (patched if 08005112/24120001) ---")
$results.Add((Read-Block 0x80014340L 16))
$results.Add("--- draw distance 0x80020420 (patched if 0800810D) ---")
$results.Add((Read-Block 0x80020420L 4))
$results.Add("--- gt2_01 fingerprint words 0x8001F888 / 0x8003EC6C ---")
$results.Add((Read-Block 0x8001F888L 4))
$results.Add((Read-Block 0x8003EC6CL 4))
$results.Add("--- 60fps divider 0x801D5634 ---")
$results.Add((Read-Block 0x801D5634L 4))

# The wait loop the exit report showed: code around 0x8001F800 and its
# caller near 0x8002009C, plus the expanded-RAM buffer area itself.
$results.Add("--- code 0x8001F7F8..0x8001F878 ---")
$results.Add((Read-Block 0x8001F7F8L 128))
$results.Add("--- code 0x80020040..0x800200C0 ---")
$results.Add((Read-Block 0x80020040L 128))
$results.Add("--- expanded bank head 0x80200000 (first buffer bytes) ---")
$results.Add((Read-Block 0x80200000L 64))
$results.Add("--- stock buffer area 0x800E5700 head ---")
$results.Add((Read-Block 0x800E5700L 64))

$results | Set-Content $out
Write-Host "Wrote $out - you can leave the game as it is or quit."
Read-Host "Press Enter to exit"
