# Arcade unlock experiment #6 - BOTH halves in one session.
# Pokes the unlock source data (ranking-presence bytes + unlock-bit array)
# AND the cached per-item visibility bytes together. Then:
#   step 1: re-enter course select               (tests the cache path)
#   step 2: exit Arcade mode fully to the game's main menu, re-enter
#           Arcade, and check course select again (tests the recompute path)
# Report what each step shows. Writes gt2_arcade_probe6.txt
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_arcade_probe6.txt'
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

Write-Host "1/3 marking all ranking entries present (tiers 0..5, plus spares to 20)..."
$ok = 0
for ($tid = 0; $tid -le 0x14; $tid++) {
    for ($k = 0; $k -lt 10; $k++) {
        if (Poke ($base + 0x1418 + $tid * 0x668 + $k * 0xA4 + 1) 1) { $ok++ }
    }
}
$results.Add("presence pokes ok=$ok/210")

Write-Host "2/3 setting unlock bits in the flag array..."
$ok2 = 0
for ($i = 0; $i -lt 0x80; $i++) {
    $a = ($base -band 0x1FFFFF) + 0xB8 + $i
    $r = Send-Cmd ('{{"id":9,"cmd":"read_ram","addr":{0},"len":1}}' -f $a) 4000
    $cur = 0
    if ($r -match '"hex":"([0-9a-fA-F]{2})"') { $cur = [Convert]::ToInt32($Matches[1], 16) }
    if (Poke ($base + 0xB8 + $i) ($cur -bor 0x06)) { $ok2++ }
}
$results.Add("flag-array pokes ok=$ok2/128")

Write-Host "3/3 setting cached visibility bytes..."
$descs = @(0x0005098C, 0x00050C4C, 0x00050F0C, 0x0005120C, 0x0005150C)
$ok3 = 0
foreach ($d in $descs) {
    $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":{1}}}' -f $d, (30*0x20)
    $resp = Send-Cmd $q
    if ($resp -notmatch '"hex":"([0-9a-fA-F]+)"') { continue }
    $hex = $Matches[1]
    for ($k = 0; $k -lt 30; $k++) {
        $rec = $k * 0x20
        $pB = 0
        for ($b = 7; $b -ge 4; $b--) { $pB = $pB * 256 + [Convert]::ToInt32($hex.Substring(($rec+$b)*2, 2), 16) }
        if ($pB -eq 0) { break }
        if (Poke (0x80000000 + $d + $rec + 0x1C) 1) { $ok3++ }
    }
}
$results.Add("vis pokes ok=$ok3")

[System.IO.File]::WriteAllLines($out, $results)
Write-Host "Wrote $out"
Write-Host ""
Write-Host "STEP 1: re-enter course select. All tracks there? Note it."
Write-Host "STEP 2: exit Arcade mode completely (back to the game's main menu),"
Write-Host "        re-enter Arcade, open course select again. Note it."
Write-Host "Tell Claude BOTH results."
Read-Host "Press Enter to exit"
