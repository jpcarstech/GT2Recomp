# Expanded-bank evidence scan - run at the garbled screen (mods can be off).
# On a retail PS1, game pointers that stray past 2MB fold back onto real
# memory (mirrors). On the 8MB build they land in the expanded bank
# [0x200000..0x800000) and STAY there. With the 8MB mods disabled nothing
# legitimate writes up there, so any nonzero page is a mirror-dependent
# game write - and its address says which real address it was meant for.
# Writes gt2_xbank.txt (nonzero pages + first bytes of each).
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_xbank.txt'
$results = New-Object System.Collections.Generic.List[string]

function Send-Cmd([string]$cmd) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $client.ReceiveTimeout = 8000
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

Write-Host "Scanning expanded RAM bank (1536 pages, ~30s)..."
$nonzero = 0
for ($page = 0; $page -lt 1536; $page++) {
    $addr = 2097152 + $page * 4096   # 0x200000 + page*0x1000
    # sample 4 spots per page: offsets 0, 1024, 2048, 3072 (64 bytes each)
    $hit = $false
    foreach ($off in @(0, 1024, 2048, 3072)) {
        $q = '{{"id":9,"cmd":"read_ram","addr":{0},"len":64}}' -f ($addr + $off)
        $line = Send-Cmd $q
        if ($line -match '"hex":"(0+)"') { continue }        # all zeros
        if ($line -match '"hex":"([0-9a-fA-F]+)"') {
            if (-not $hit) {
                $results.Add(("page 0x{0:X8}:" -f $addr)); $hit = $true; $nonzero++
            }
            $results.Add(("  +0x{0:X4}: {1}" -f $off, $Matches[1]))
        } else {
            $results.Add(("  read err at 0x{0:X8}: {1}" -f ($addr+$off), $line.Substring(0,[Math]::Min(80,$line.Length))))
            break
        }
    }
    if (($page % 256) -eq 0) { Write-Host ("  ... 0x{0:X8}" -f $addr) }
}
$results.Insert(0, ("nonzero pages found: {0} of 1536 sampled" -f $nonzero))
$results | Set-Content $out
Write-Host "Wrote $out ($nonzero nonzero pages)"
Read-Host "Press Enter to exit"
