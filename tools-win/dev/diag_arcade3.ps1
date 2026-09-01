# Arcade unlock experiment #3. Run while in Arcade mode (anywhere in its
# menus). The course menus' item tables embed a per-track unlock TIER
# (starter tracks carry 5, later tracks 4..0). This sets every track's tier
# to 5 across the five course-menu descriptors, which should make the
# unlock filter pass everything. Then back out to course select and look.
# Writes gt2_arcade_probe3.txt
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_arcade_probe3.txt'
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
    $items = $d + 0x64
    $len = 18 * 0x20
    $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":{1}}}' -f $items, $len
    $resp = Send-Cmd $q
    if ($resp -notmatch '"hex":"([0-9a-fA-F]+)"') {
        $results.Add(("desc 0x{0:X6}: read failed: {1}" -f $d, $resp)); continue
    }
    $hex = $Matches[1]
    $before = @()
    for ($k = 0; $k -lt 18; $k++) {
        $rec = $k * 0x20
        $ptr = 0
        for ($b = 3; $b -ge 0; $b--) { $ptr = $ptr * 256 + [Convert]::ToInt32($hex.Substring(($rec+$b)*2, 2), 16) }
        if ($ptr -eq 0) { break }
        $tier = [Convert]::ToInt32($hex.Substring(($rec+0x10)*2, 2), 16)
        $before += ("{0:X2}" -f $tier)
        if ($tier -ne 5) {
            $pq = '{{"id":7,"cmd":"write_ram","addr":"0x{0:X8}","val":"0x05"}}' -f (0x80000000 + $items + $rec + 0x10)
            $pr = Send-Cmd $pq 4000
            if ($pr -match '"ok":true') { $poked++ }
            else { $results.Add(("poke item {0} of desc 0x{1:X6} failed: {2}" -f $k, $d, $pr)) }
        }
    }
    $results.Add(("desc 0x{0:X6}: tiers before = {1}" -f $d, ($before -join ' ')))
}
$results.Add("tier bytes poked: $poked")
[System.IO.File]::WriteAllLines($out, $results)
Write-Host "Wrote $out ($poked tier bytes set to 5)"
Write-Host ""
Write-Host "NOW: go back to (or re-enter) course select in 1P and check the track list."
Write-Host "Tell Claude whether all the road tracks are selectable."
Read-Host "Press Enter to exit"
