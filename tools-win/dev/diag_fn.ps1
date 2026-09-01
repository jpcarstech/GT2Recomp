# Function-level trace of GT2's streaming manager across boot.
# START THE GAME, then run this IMMEDIATELY. It arms the runtime's function
# tracer on the manager's address range and records every call (with caller
# and arguments) through the boot window, then stops once the intro stream
# starts or frame 1700 passes. Writes gt2_fn_boot.jsonl.
# Tell Claude whether THIS boot was garbled or clean.
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_fn_boot.jsonl'

function Send-Cmd([string]$cmd, [int]$timeout = 4000) {
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
    } catch { return $null }
}

Write-Host "Waiting for the game..."
$armed = $false
for ($i = 0; $i -lt 240; $i++) {
    $r = Send-Cmd '{"id":1,"cmd":"fn_filter","lo":"0x8007C300","hi":"0x8007D100"}' 1000
    if ($r -match '"active":1') { $armed = $true; break }
    Start-Sleep -Milliseconds 500
}
if (-not $armed) { Write-Host "Game never came up."; Read-Host "Enter"; exit 1 }
Write-Host "Tracer armed - recording through boot..."

$seen = @{}
$sw = [System.IO.StreamWriter]::new($out)
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    $d = Send-Cmd '{"id":3,"cmd":"fn_entry_tail","count":256}' 4000
    if ($d) {
        foreach ($m in [regex]::Matches($d, '\{"seq":\d+[^}]*\}')) {
            $mm = [regex]::Match($m.Value, '"seq":(\d+)')
            $s = $mm.Groups[1].Value
            if (-not $seen.ContainsKey($s)) {
                $seen[$s] = $true
                $sw.WriteLine($m.Value)
            }
        }
    }
    $f = Send-Cmd '{"id":1,"cmd":"frame"}' 1500
    $st = Send-Cmd '{"id":2,"cmd":"cdrom_state"}' 1500
    if ($st -match '"mode":"0xE8"' -and $st -match '"reading":1') {
        $sw.WriteLine('{"note":"stream-started"}')
        Write-Host "Intro stream started - boot is CLEAN. Recording tail..."
        Start-Sleep -Seconds 2
        break
    }
    if ($f -match '"frame":(\d+)' -and [int]$Matches[1] -gt 1700) {
        $sw.WriteLine('{"note":"no-stream-by-1700 (WEDGED)"}')
        Write-Host "No intro stream by frame 1700 - boot looks WEDGED (good capture!)."
        break
    }
    Start-Sleep -Milliseconds 120
}
$sw.Close()
Write-Host ("Wrote {0} ({1} entries)" -f $out, $seen.Count)
Read-Host "Press Enter to exit"
