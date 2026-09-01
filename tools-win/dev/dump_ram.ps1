# Dumps the emulated console's ENTIRE 2MB main RAM through the debug server.
#   .\dump_ram.ps1 clean     (while text looks right)
#   .\dump_ram.ps1 garbled   (while text is garbled)
# Writes gt2_ram_<label>.hex beside this script (~4 MB text). Used to locate
# the font atlas in RAM and compare its bytes between good and bad boots -
# this splits the bug between the CD/asset-loading side (RAM already bad)
# and the GPU upload side (RAM good, VRAM bad).
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
$dumps = Join-Path $root 'dumps'
[void](New-Item -ItemType Directory -Force -Path $dumps)
$out = Join-Path $dumps ("gt2_ram_{0}.hex" -f $label)
try {
    $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
    $client.ReceiveTimeout = 120000
    $stream = $client.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream)
    $reader = New-Object System.IO.StreamReader($stream)
    $writer.AutoFlush = $true
    Write-Host "Reading 2MB of console RAM (takes a few seconds)..."
    $writer.WriteLine('{"id":1,"cmd":"read_ram","addr":"0x80000000","len":2097152}')
    $line = $reader.ReadLine()
    $client.Close()
    if ($null -eq $line) { Write-Host "No response - is the game running?"; Read-Host "Enter"; exit 1 }
    if ($line -match '"hex":"([0-9a-f]+)"') {
        [System.IO.File]::WriteAllText($out, $Matches[1])
        Write-Host ("Wrote {0} ({1:N0} bytes of RAM)" -f $out, ($Matches[1].Length / 2))
    } else {
        Write-Host ("Unexpected response: " + $line.Substring(0, [Math]::Min(120, $line.Length)))
    }
} catch { Write-Host "ERR: $($_.Exception.Message) - is the game running?" }
Read-Host "Press Enter to exit"
