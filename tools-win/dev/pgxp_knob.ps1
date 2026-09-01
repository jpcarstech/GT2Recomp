# pgxp_knob.ps1 - flip a PGXP setting LIVE in the running game (no rebuild, no restart).
#   .\tools\pgxp_knob.ps1                 -> show current PGXP state
#   .\tools\pgxp_knob.ps1 completion 0    -> set one knob
#   .\tools\pgxp_knob.ps1 disable_2d 1
# Knobs: geometry texture culling preserve completion whole disable_2d vertex_cache cpu_mode
#        tolerance (float; -1 = unlimited)
param([string]$knob = "", [string]$value = "")
function Send-Cmd([string]$cmd) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370); $c.ReceiveTimeout = 5000
        $s = $c.GetStream(); $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s); $w.WriteLine($cmd); $line = $r.ReadLine(); $c.Close(); return $line
    } catch { return $null }
}
if ($knob -ne "") {
    if ($value -eq "") { Write-Host "usage: pgxp_knob.ps1 <knob> <value>" -ForegroundColor Red; exit 1 }
    $j = Send-Cmd ('{"id":1,"cmd":"pgxp","' + $knob + '":' + $value + '}')
} else {
    $j = Send-Cmd '{"id":1,"cmd":"pgxp"}'
}
if (-not $j) { Write-Host "game not reachable on 127.0.0.1:4370 (is it running? ONE instance)" -ForegroundColor Red; exit 1 }
Write-Host $j
