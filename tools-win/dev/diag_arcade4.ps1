# Arcade unlock experiment #4 - the decoded unlock model.
# Track selectable <=> all 10 ranking entries for that track are marked
# present (byte +1 of each 0xA4-byte entry in the 0x668-byte per-track block
# at 0x801C96B0+0x1418). Cars/extras gate on bits 1|2 of a flag array at
# 0x801C96B0+0xB8. This pokes both, then you re-enter course select / car
# select. Writes gt2_arcade_probe4.txt
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_arcade_probe4.txt'
$results = New-Object System.Collections.Generic.List[string]

function Send-Cmd([string]$cmd, [int]$timeout = 10000) {
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
function Poke([long]$addr, [int]$val) {
    $q = '{{"id":7,"cmd":"write_ram","addr":"0x{0:X8}","val":"0x{1:X2}"}}' -f $addr, $val
    return ((Send-Cmd $q 4000) -match '"ok":true')
}

$f = Send-Cmd '{"id":1,"cmd":"frame"}' 4000
$results.Add("frame: $f")
if ($f -notmatch '"frame"') { Write-Host "Game not reachable."; Read-Host "Enter"; exit 1 }

$base = 0x801C96B0
# Snapshot the presence bytes of track 0 and track 2 first (one known
# unlocked, one likely locked) for the record.
foreach ($tid in @(0, 2, 0x14)) {
    $a = ($base -band 0x1FFFFF) + 0x1418 + $tid * 0x668
    $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":16}}' -f $a
    $results.Add(("track {0} block head: {1}" -f $tid, (Send-Cmd $q)))
}

Write-Host "Marking all ranking entries present for track ids 0..0x14..."
$ok = 0; $fail = 0
for ($tid = 0; $tid -le 0x14; $tid++) {
    for ($k = 0; $k -lt 10; $k++) {
        $addr = $base + 0x1418 + $tid * 0x668 + $k * 0xA4 + 1
        if (Poke $addr 1) { $ok++ } else { $fail++ }
    }
    Write-Host ("  track {0}/20 done" -f $tid)
}
$results.Add("presence pokes ok=$ok fail=$fail")

Write-Host "Setting unlock bits in the flag array (0x80 bytes)..."
$ok2 = 0
for ($i = 0; $i -lt 0x80; $i++) {
    $addr = $base + 0xB8 + $i
    # set bits 1 and 2 on top of whatever is there: read-modify-write
    $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":1}}' -f (($base -band 0x1FFFFF) + 0xB8 + $i)
    $r = Send-Cmd $q 4000
    $cur = 0
    if ($r -match '"hex":"([0-9a-fA-F]{2})"') { $cur = [Convert]::ToInt32($Matches[1], 16) }
    if (Poke $addr ($cur -bor 0x06)) { $ok2++ }
}
$results.Add("flag-array pokes ok=$ok2")

[System.IO.File]::WriteAllLines($out, $results)
Write-Host "Wrote $out"
Write-Host ""
Write-Host "NOW: back out and re-enter course select (and car select)."
Write-Host "Tell Claude what unlocked."
Read-Host "Press Enter to exit"
