# Arcade-cheat probe. Run this while sitting INSIDE Arcade mode (ideally on
# the track-select screen). It records the current unlock-flag candidates,
# pokes the GameShark unlock values directly into RAM (bypassing the mod),
# re-reads them 2 seconds later, and saves a full 2MB RAM dump for offline
# analysis. After it finishes: back out of the track list and re-enter it,
# and note whether anything unlocked.
# Writes gt2_arcade_probe.txt + gt2_ram_arcade.hex
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$dumps = Join-Path $root 'dumps'
[void](New-Item -ItemType Directory -Force -Path $dumps)
$out = Join-Path $diag 'gt2_arcade_probe.txt'
$ramout = Join-Path $dumps 'gt2_ram_arcade.hex'
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

function Read-Region([long]$addr, [int]$len) {
    $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":{1}}}' -f $addr, $len
    return (Send-Cmd $q)
}
function Poke([long]$addr, [int]$val) {
    $q = '{{"id":7,"cmd":"write_ram","addr":"0x{0:X8}","val":"0x{1:X2}"}}' -f $addr, $val
    $r = Send-Cmd $q 4000
    if ($r -notmatch '"ok":true') { $results.Add(("poke 0x{0:X8} FAILED: {1}" -f $addr, $r)) }
}

$f = Send-Cmd '{"id":1,"cmd":"frame"}' 4000
$results.Add("frame: $f")
if ($f -notmatch '"frame"') {
    Write-Host "Game not reachable - start the game first."; Read-Host "Enter"; exit 1
}

$results.Add("--- BEFORE: 0x0F3600 region (track unlock candidates) ---")
$results.Add((Read-Region 0x000F3600 0x100))
$results.Add("--- BEFORE: 0x1C93C0 region (road completion candidates) ---")
$results.Add((Read-Region 0x001C93C0 0x100))

Write-Host "Poking GameShark unlock values..."
# All tracks (1P road/rally, 2P road/rally, time trial)
Poke 0x800F364E 0x83; Poke 0x800F364F 0x00
Poke 0x800F3652 0x17; Poke 0x800F3653 0x00
Poke 0x800F3656 0x27; Poke 0x800F3657 0x00
Poke 0x800F3658 0x15; Poke 0x800F3659 0x00
Poke 0x800F365A 0x06; Poke 0x800F365B 0x00
# Road-track completion array (unlocks extra cars) + all-difficulties byte
for ($a = 0x801C93F8; $a -lt 0x801C940C; $a++) { Poke $a 0x05 }
Poke 0x801C940C 0x05

Start-Sleep -Seconds 2
$results.Add("--- AFTER 2s: 0x0F3600 region ---")
$results.Add((Read-Region 0x000F3600 0x100))
$results.Add("--- AFTER 2s: 0x1C93C0 region ---")
$results.Add((Read-Region 0x001C93C0 0x100))

Write-Host "Dumping 2MB RAM (takes a moment)..."
$ram = Read-Region 0 0x200000
if ($ram -match '"hex":"([0-9a-fA-F]+)"') {
    [System.IO.File]::WriteAllText($ramout, $Matches[1])
    $results.Add("ram dump: wrote gt2_ram_arcade.hex")
} else {
    $results.Add("ram dump FAILED")
}

[System.IO.File]::WriteAllLines($out, $results)
Write-Host "Wrote $out"
Write-Host ""
Write-Host "NOW: back out of the track list and re-enter it."
Write-Host "Did any tracks/cars unlock? Tell Claude either way."
Read-Host "Press Enter to exit"
