# Garbled-graphics triage: toggles NATIVE code execution on/off while the
# game runs (everything falls back to the always-correct interpreter - slow
# but authoritative). If garbling stops with native OFF, a miscompiled
# cache shard is the culprit and we can bisect it.
#   .\toggle_native.ps1 off   -> interpreter only
#   .\toggle_native.ps1 on    -> native shards again (default)
# After toggling, LEAVE and RE-ENTER the screen that garbles (text is
# composed once per screen entry).
param([string]$mode = 'on')
$cmd = if ($mode -eq 'off') { '{"id":1,"cmd":"overlay_native_off"}' } else { '{"id":1,"cmd":"overlay_native_on"}' }
try {
    $client = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
    $client.ReceiveTimeout = 5000
    $stream = $client.GetStream()
    $writer = New-Object System.IO.StreamWriter($stream)
    $reader = New-Object System.IO.StreamReader($stream)
    $writer.AutoFlush = $true
    $writer.WriteLine($cmd)
    Write-Host $reader.ReadLine()
    $client.Close()
} catch { Write-Host "ERR: $($_.Exception.Message) - is the game running?" }
