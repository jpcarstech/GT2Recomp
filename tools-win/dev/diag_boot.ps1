# Boot-stall profiler for the garbled-text bug.
# START THE GAME, then run this IMMEDIATELY (it waits for the debug server).
# It samples the emulated CPU's program counter ~10x per second for 45
# seconds - through the boot screens and into the menu - then captures the
# pad/memory-card port state. The PC histogram shows exactly which wait
# loop the boot sequencer is stuck in during the silent window.
# Writes gt2_boot_profile.txt. Tell Claude whether THIS boot came up garbled.
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_boot_profile.txt'

function Send-Cmd([string]$cmd, [int]$timeout = 5000) {
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
                if (-not $first) { $client.ReceiveTimeout = 1500 }
                $line = $reader.ReadLine()
            } catch { break }
            if ($null -eq $line) { break }
            [void]$sb.AppendLine($line)
            $first = $false
        }
        $client.Close()
        if ($sb.Length -eq 0) { return "(no response)" }
        return $sb.ToString().TrimEnd()
    } catch { return "ERR: $($_.Exception.Message)" }
}

Write-Host "Waiting for the game's debug server..."
$up = $false
for ($i = 0; $i -lt 120; $i++) {
    $r = Send-Cmd '{"id":1,"cmd":"frame"}' 1000
    if ($r -match '"ok":true') { $up = $true; break }
    Start-Sleep -Milliseconds 500
}
if (-not $up) { Write-Host "Game never came up - start the game first."; Read-Host "Enter"; exit 1 }

$sw = [System.IO.StreamWriter]::new($out)
$sw.WriteLine("=== diag_boot $(Get-Date -Format o) ===")
Write-Host "Sampling PC for 45 seconds (let the game boot to the menu)..."
$deadline = (Get-Date).AddSeconds(45)
$n = 0
while ((Get-Date) -lt $deadline) {
    $f = Send-Cmd '{"id":2,"cmd":"frame"}' 1500
    $r = Send-Cmd '{"id":3,"cmd":"get_registers"}' 1500
    # GT2's CD-streaming manager struct: state byte at +0x166 (0x801F0436),
    # queue pointers at +0x7c..+0x90. The boot stall spins on state==0.
    $m = Send-Cmd '{"id":9,"cmd":"read_ram","addr":"0x801F02D0","len":432}' 1500
    # DMA controller: if MDEC ch0/ch1 sits active with remaining_words > 0
    # across the wedge, the decode pipeline is the stalled completion.
    $d = Send-Cmd '{"id":10,"cmd":"dma_state"}' 1500
    # Current stream-op descriptors (queue nodes live at 0x800901C4..0x2CC).
    $q = Send-Cmd '{"id":11,"cmd":"read_ram","addr":"0x80090180","len":416}' 1500
    $frame = if ($f -match '"frame":(\d+)') { $Matches[1] } else { '?' }
    $sw.WriteLine("sample f$frame : $r")
    $sw.WriteLine("mgr f$frame : $m")
    $sw.WriteLine("dma f$frame : $d")
    $sw.WriteLine("queue f$frame : $q")
    $n++
    Start-Sleep -Milliseconds 40
}
Write-Host "Captured $n samples; grabbing port state..."
$sw.WriteLine("sio_state: "       + (Send-Cmd '{"id":4,"cmd":"sio_state"}' 8000))
$sw.WriteLine("mc_status: "       + (Send-Cmd '{"id":5,"cmd":"mc_status"}' 8000))
$sw.WriteLine("sio_burst_stats: " + (Send-Cmd '{"id":6,"cmd":"sio_burst_stats"}' 8000))
$sw.WriteLine("card_mgr_trace: "  + (Send-Cmd '{"id":7,"cmd":"card_mgr_trace"}' 8000))
$sw.WriteLine("irq_state: "       + (Send-Cmd '{"id":8,"cmd":"irq_state"}' 8000))
$sw.Close()
Write-Host "Wrote $out - note whether THIS boot was garbled or clean."
Read-Host "Press Enter to exit"
