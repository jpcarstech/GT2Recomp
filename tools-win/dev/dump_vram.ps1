# Garbled-graphics capture: run WHILE a garbled screen is showing.
# Saves gt2_screen.png (what is rendered) and gt2_vram.hex (the emulated
# CPU-side VRAM, all 1024x512 pixels) so we can tell whether the garbage
# already exists in VRAM (game/memory side) or only appears in rendering.
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

function Send-Cmd([string]$cmd, [int]$timeout = 15000) {
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
        if ($null -eq $line) { return "(no response)" }
        return $line
    } catch { return "ERR: $($_.Exception.Message)" }
}

$png = ($root -replace '\\','/') + '/gt2_screen.png'
Write-Host ("screenshot: " + (Send-Cmd ('{{"id":1,"cmd":"screenshot_file","path":"{0}"}}' -f $png)))

$out = Join-Path $dumps 'gt2_vram.hex'
$sw = [System.IO.StreamWriter]::new($out)
for ($ty = 0; $ty -lt 4; $ty++) {
    for ($tx = 0; $tx -lt 8; $tx++) {
        $q = '{{"id":2,"cmd":"vram_peek","x":{0},"y":{1},"w":128,"h":128}}' -f ($tx*128), ($ty*128)
        $sw.WriteLine((Send-Cmd $q))
    }
}
$sw.Close()
Write-Host "Wrote gt2_screen.png and gt2_vram.hex"
Read-Host "Press Enter to exit"
