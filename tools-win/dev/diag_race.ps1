# Race-corruption capture - run this AFTER a race attempt, while the game
# window is still open (works even after a "halted" crash screen: the debug
# server stays alive post-mortem). Optional label: .\diag_race.ps1 try1
# Captures the GPU command ring for the current frame, RAM around the
# corrupt display-list region, and DMA state. Writes gt2_race_<label>.txt.
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
$out = Join-Path $diag ("gt2_race_{0}.txt" -f $label)
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
                if (-not $first) { $client.ReceiveTimeout = 1200 }
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
$frame = -1
if ($f -match '"frame":(\d+)') { $frame = [int]$Matches[1] }
if ($frame -lt 0) {
    Write-Host "Game/debug server not reachable - launch the game (or don't close the crash screen) and rerun."
    Read-Host "Enter"; exit 1
}

# Full GP0 command ring for the newest fully-recorded frames. The ring's
# frame stamps run behind the "frame" counter, so ask the ring itself.
$rs = Send-Cmd '{"id":8,"cmd":"gpu_ring_stats"}' 6000
$results.Add("ring_stats: $rs")
$newest = $frame - 1
if ($rs -match '"newest_frame":(\d+)') { $newest = [int]$Matches[1] }
foreach ($fr in @(($newest - 1), $newest)) {
    if ($fr -lt 0) { continue }
    $results.Add("--- gpu_frame_dump frame $fr ---")
    $results.Add((Send-Cmd ('{{"id":2,"cmd":"gpu_frame_dump","frame":{0},"count":6000}}' -f $fr) 30000))
}

$results.Add("--- gpu_state ---")
$results.Add((Send-Cmd '{"id":3,"cmd":"gpu_state"}' 6000))
$results.Add("--- gpu_ring_stats ---")
$results.Add((Send-Cmd '{"id":4,"cmd":"gpu_ring_stats"}' 6000))
$results.Add("--- dma_state ---")
$results.Add((Send-Cmd '{"id":5,"cmd":"dma_state"}' 6000))

# The ENTIRE relocated polygon/OT arena (0x200000..0x270000) plus the
# regions implicated so far. The arena dump is what lets the chain and the
# corrupt data block be decoded offline.
foreach ($r in @(
    @(0x00200000, 0x70000, 'full 8MB-patch polygon/OT arena'),
    @(0x000E5700, 0x38000, 'stock polygon arena (should be idle under the patch)'),
    @(0x00013000, 0x5000,  'sim overlay code around LOD/buffer-setup sites'),
    @(0x0007F000, 0x6000,  'libgpu-side code around 0x80080000..0x80085000'))) {
    $results.Add(("--- ram 0x{0:X8} len 0x{1:X} ({2}) ---" -f $r[0], $r[1], $r[2]))
    $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":{1}}}' -f $r[0], $r[1]
    $results.Add((Send-Cmd $q 15000))
}

# If gt2_err.txt names unknown-command source addresses, dump around the first.
$errf = Join-Path $diag 'gt2_err.txt'
if (Test-Path $errf) {
    $m = Select-String -Path $errf -Pattern 'unknown command .* src 0x([0-9A-Fa-f]{8})' | Select-Object -First 1
    if ($m) {
        $srcaddr = [Convert]::ToInt64($m.Matches[0].Groups[1].Value, 16)
        $base = [Math]::Max(0, $srcaddr - 0x800)
        $results.Add(("--- ram 0x{0:X8} len 0x1000 (around first unknown-cmd src) ---" -f $base))
        $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":4096}}' -f $base
        $results.Add((Send-Cmd $q 15000))
    }
}

[System.IO.File]::WriteAllLines($out, $results)
Write-Host ("Wrote {0}" -f $out)
Read-Host "Press Enter to exit"
