# Arcade unlock experiment #2. Run while sitting on the Arcade COURSE SELECT
# screen. The live arcade state block holds slot arrays of track IDs where
# some entries carry bit 7 (0x80|id) - suspected lock markers. This clears
# bit 7 on every such byte in both menu blocks (1P and 2P), then you back out
# and re-enter course select and report what changed.
# Writes gt2_arcade_probe2.txt
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_arcade_probe2.txt'
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
if ($f -notmatch '"frame"') {
    Write-Host "Game not reachable."; Read-Host "Enter"; exit 1
}

# The slot arrays inside the live arcade struct (1P block and 2P block).
$ranges = @(@(0x001C96BA, 0x2C), @(0x001C970C, 0x2C))
$poked = 0
foreach ($r in $ranges) {
    $addr = $r[0]; $len = $r[1]
    $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":{1}}}' -f $addr, $len
    $resp = Send-Cmd $q
    $results.Add(("BEFORE 0x{0:X6}: {1}" -f $addr, $resp))
    if ($resp -match '"hex":"([0-9a-fA-F]+)"') {
        $hex = $Matches[1]
        for ($i = 0; $i -lt $len; $i++) {
            $b = [Convert]::ToInt32($hex.Substring($i*2, 2), 16)
            if ($b -ge 0x80) {
                $nb = $b -band 0x7F
                $pq = '{{"id":7,"cmd":"write_ram","addr":"0x{0:X8}","val":"0x{1:X2}"}}' -f (0x80000000 + $addr + $i), $nb
                $pr = Send-Cmd $pq 4000
                if ($pr -match '"ok":true') { $poked++ }
                else { $results.Add(("poke 0x{0:X6} failed: {1}" -f ($addr+$i), $pr)) }
            }
        }
    }
    $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":{1}}}' -f $addr, $len
    $results.Add(("AFTER  0x{0:X6}: {1}" -f $addr, (Send-Cmd $q)))
}
$results.Add("bytes poked: $poked")
[System.IO.File]::WriteAllLines($out, $results)
Write-Host "Wrote $out ($poked bytes cleared)"
Write-Host ""
Write-Host "NOW: back out of course select and re-enter it."
Write-Host "Tell Claude what changed (new tracks? different layout? nothing?)."
Read-Host "Press Enter to exit"
