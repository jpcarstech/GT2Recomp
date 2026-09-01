# Arcade unlock experiment #5 - poke the CACHED visibility bytes.
# The menu computes per-item visibility ONCE at arcade-mode init and caches
# it at item+0x1C; course select just reads the cache. This sets vis=1 on
# every item across the five course-menu tables so the change shows up
# immediately. Writes gt2_arcade_probe5.txt
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_arcade_probe5.txt'
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

$f = Send-Cmd '{"id":1,"cmd":"frame"}' 4000
$results.Add("frame: $f")
if ($f -notmatch '"frame"') { Write-Host "Game not reachable."; Read-Host "Enter"; exit 1 }

$descs = @(0x0005098C, 0x00050C4C, 0x00050F0C, 0x0005120C, 0x0005150C)
$poked = 0
foreach ($d in $descs) {
    # walk records (stride 0x20) until the +0x04 "exists" pointer is zero
    $len = 30 * 0x20
    $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":{1}}}' -f $d, $len
    $resp = Send-Cmd $q
    if ($resp -notmatch '"hex":"([0-9a-fA-F]+)"') { $results.Add("desc read fail: $resp"); continue }
    $hex = $Matches[1]
    $vis = @()
    for ($k = 0; $k -lt 30; $k++) {
        $rec = $k * 0x20
        $pB = 0
        for ($b = 7; $b -ge 4; $b--) { $pB = $pB * 256 + [Convert]::ToInt32($hex.Substring(($rec+$b)*2, 2), 16) }
        if ($pB -eq 0) { break }
        $v = [Convert]::ToInt32($hex.Substring(($rec+0x1C)*2, 2), 16)
        $vis += ("{0:X2}" -f $v)
        if ($v -ne 1) {
            $addr = 0x80000000 + $d + $rec + 0x1C
            $pq = '{{"id":7,"cmd":"write_ram","addr":"0x{0:X8}","val":"0x01"}}' -f $addr
            if ((Send-Cmd $pq 4000) -match '"ok":true') { $poked++ }
        }
    }
    $results.Add(("desc 0x{0:X6}: vis before = {1}" -f $d, ($vis -join ' ')))
}
$results.Add("vis bytes poked: $poked")
[System.IO.File]::WriteAllLines($out, $results)
Write-Host "Wrote $out ($poked vis bytes set)"
Write-Host ""
Write-Host "NOW: re-enter course select. Are all the tracks there?"
Read-Host "Press Enter to exit"
