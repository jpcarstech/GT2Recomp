# Performance deep-dive - START A RACE FIRST, then run this and LEAVE THE
# GAME RUNNING until it finishes (about 10 seconds). Writes gt2_perf.txt.
# Captures: compiler status, overlay loader status, per-candidate dump
# (which code regions keep invalidating), frame timings, and two passes over
# every mod patch site to catch the game rewriting one.
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_perf.txt'
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

foreach ($c in @(
    '{"id":1,"cmd":"frame"}',
    '{"id":2,"cmd":"autocompile_status"}',
    '{"id":3,"cmd":"overlay_loader_status"}',
    '{"id":4,"cmd":"frame_perf"}',
    '{"id":5,"cmd":"overlay_candidates"}'
)) {
    $results.Add($c)
    $results.Add((Send-Cmd $c))
}

# Hot-function native coverage: the exit-report ring showed these as the most
# dispatched addresses (the 0x80022Dxx block loop alone was ~39M dispatches).
# For each, dump the candidate table filtered to that PC - no candidates, or
# candidates with match=0, means that function still runs interpreted.
$results.Add("--- hot-function candidates ---")
foreach ($pc in @('0x80022DFC','0x800209E4','0x8001F9A4','0x80020074',
                  '0x8007B6D8','0x8007B858','0x80082490','0x8008211C',
                  '0x8007D1CC')) {
    $q = '{{"id":6,"cmd":"overlay_candidates","pc":"{0}"}}' -f $pc
    $results.Add("pc $pc")
    $results.Add((Send-Cmd $q))
}

# Cache inventory: shard dlls per region (first 8 hex chars of the file name),
# so coverage gaps are visible next to the hot list above.
$results.Add("--- cache dll inventory (gcc tier) ---")
$cacheRoot = Join-Path $root 'cache\SCUS-94488\gcc'
if (Test-Path $cacheRoot) {
    Get-ChildItem $cacheRoot -Recurse -Filter *.dll |
        Group-Object { $_.Name.Substring(0, 8) } |
        Sort-Object Name |
        ForEach-Object { $results.Add(("region {0}: {1} dll(s)" -f $_.Name, $_.Count)) }
} else { $results.Add("no gcc cache dir at $cacheRoot") }

# Patch-site churn: two passes, 3s apart. Long-typed literals (the previous
# script's Int32 hex literals went negative and broke the reads).
$sites = @(
    0x800100D0L, 0x800100D4L, 0x800295E4L, 0x800295E8L,
    0x80049736L, 0x80049EB4L, 0x80049EBCL,
    0x8004C100L, 0x8004C108L,
    0x8004DFE8L, 0x8004DFF4L, 0x8004DFD0L,
    0x80050B80L, 0x80050B88L,
    0x8005802CL, 0x80058034L,
    0x800588E0L, 0x800588E8L, 0x800599C4L,
    0x8001E55CL, 0x8001E564L, 0x800201A8L, 0x800201B0L, 0x80015350L,
    0x800168C8L, 0x80019644L, 0x80029548L,
    0x8001F888L, 0x80057010L, 0x8005D598L, 0x8003EC6CL, 0x80020A74L
)
function Read-Sites {
    $vals = @{}
    foreach ($a in $sites) {
        $wa = $a -band 0xFFFFFFFCL
        $line = Send-Cmd ('{{"id":9,"cmd":"read_ram","addr":{0},"len":4}}' -f $wa)
        if ($line -match '"hex":"([0-9a-fA-F]+)"') { $vals[$a] = $Matches[1] }
        else { $vals[$a] = "ERR " + $line.Substring(0, [Math]::Min(60, $line.Length)) }
    }
    return $vals
}
$results.Add("sites pass 1: " + (Get-Date -Format o))
$p1 = Read-Sites
Start-Sleep -Seconds 3
$results.Add("sites pass 2: " + (Get-Date -Format o))
$p2 = Read-Sites
foreach ($a in $sites) {
    $flag = if ($p1[$a] -ne $p2[$a]) { "  <== CHANGED" } else { "" }
    $results.Add(("0x{0:X8}: {1} -> {2}{3}" -f $a, $p1[$a], $p2[$a], $flag))
}
$results | Set-Content $out
Write-Host "Wrote $out"
Write-Host "Done - you can quit the game now."
Read-Host "Press Enter to exit"
