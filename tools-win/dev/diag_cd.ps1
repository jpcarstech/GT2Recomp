# CD-ROM delivery check for the garbled-text bug.
#   .\diag_cd.ps1 garbled   (at a garbled boot, e.g. the loading/save screen)
#   .\diag_cd.ps1 clean     (on a boot where text is fine)
# Captures the drive model's loss counters: int1_lost / ring_dropped count
# sectors whose data-ready notification was replaced before the game saw it -
# exactly the failure that would truncate the menu overlay load and zero the
# font. Writes gt2_cd_<label>.txt beside this script.
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
$out = Join-Path $root ("gt2_cd_{0}.txt" -f $label)

function Send-Cmd([string]$cmd, [int]$timeout = 20000) {
    # Reads EVERY line of the response: large histories arrive as multi-line
    # JSON, and a single ReadLine truncated them (first diag_cd version).
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
                if (-not $first) { $client.ReceiveTimeout = 2500 }
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

$sw = [System.IO.StreamWriter]::new($out)
$sw.WriteLine("=== diag_cd '$label' $(Get-Date -Format o) ===")
$sw.WriteLine("frame: "        + (Send-Cmd '{"id":1,"cmd":"frame"}'))
$sw.WriteLine("cdrom_state: "  + (Send-Cmd '{"id":2,"cmd":"cdrom_state"}'))
$sw.WriteLine("cd_read_log: "  + (Send-Cmd '{"id":3,"cmd":"cd_read_log"}'))
$sw.WriteLine("cdrom_bursts: " + (Send-Cmd '{"id":4,"cmd":"cdrom_bursts"}'))
$sw.WriteLine("cdrom_command_history: " + (Send-Cmd '{"id":5,"cmd":"cdrom_command_history","count":8192}' 60000))
$sw.WriteLine("dma_cdrom_history: "     + (Send-Cmd '{"id":6,"cmd":"dma_cdrom_history","count":8192}' 60000))
$sw.WriteLine("cdrom_sector_history: "  + (Send-Cmd '{"id":7,"cmd":"cdrom_sector_history","count":8192}' 60000))
$sw.Close()
Write-Host "Wrote $out"
Read-Host "Press Enter to exit"
