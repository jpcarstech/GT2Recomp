# Intro-FMV diagnosis v2. START THE GAME, then run this immediately - it
# samples the whole pipeline through the intro movie: frame pacing, audio,
# execution-phase attribution (interpreter vs native), and the overlay
# native-code pipeline (capture -> compile -> load). Writes
# diagnostics\gt2_fmv.txt for Claude.
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$diag = Join-Path $root 'diagnostics'
[void](New-Item -ItemType Directory -Force -Path $diag)
$out = Join-Path $diag 'gt2_fmv.txt'
function Send-Cmd([string]$cmd, [int]$timeout = 6000) {
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
    } catch { return $null }
}
$r = New-Object System.Collections.Generic.List[string]
$r.Add("diag_fmv v2")
# Build provenance: is the running exe actually the new build?
foreach ($exe in @('Gran Turismo 2 Recompiled.exe')) {
    $p = Join-Path $root $exe
    if (Test-Path $p) {
        $fi = Get-Item $p
        $r.Add(("exe={0} mtime={1} size={2}" -f $exe, $fi.LastWriteTime.ToString('s'), $fi.Length))
    }
}
$cacheDir = Join-Path $root 'cache\SCUS-94488'
if (Test-Path $cacheDir) {
    Get-ChildItem -Directory -Recurse $cacheDir | Where-Object { $_.Name -like 'cg*' } | ForEach-Object {
        $n = (Get-ChildItem -Filter *.dll $_.FullName).Count
        $r.Add(("cache tagdir={0} dlls={1}" -f $_.FullName.Substring($root.Length), $n))
    }
} else { $r.Add("cache dir: MISSING") }
$caps = Join-Path $root 'overlay_captures.json'
if (Test-Path $caps) { $fi = Get-Item $caps; $r.Add(("captures mtime={0} size={1}" -f $fi.LastWriteTime.ToString('s'), $fi.Length)) }
else { $r.Add("captures: MISSING") }

Write-Host "Waiting for the game (start it now if you haven't)..."
while (-not (Send-Cmd '{"id":1,"cmd":"frame"}' 2000)) { Start-Sleep -Seconds 2 }
Write-Host "Game up. Sampling through the intro - let the movie play with sound on..."
for ($i = 0; $i -lt 40; $i++) {
    $f  = Send-Cmd '{"id":1,"cmd":"frame"}'
    $a  = Send-Cmd '{"id":2,"cmd":"audio_stats"}'
    $p  = Send-Cmd '{"id":4,"cmd":"frame_perf"}'
    $ph = Send-Cmd '{"id":5,"cmd":"phase_profile","window":3}'
    $r.Add("t=$i frame=$f")
    $r.Add("  audio=$a")
    $r.Add("  perf=$p")
    $r.Add("  phase=$ph")
    Start-Sleep -Seconds 3
}
# One-shot pipeline state at the end of the window.
$r.Add("== overlay_loader_status ==")
$r.Add([string](Send-Cmd '{"id":6,"cmd":"overlay_loader_status"}'))
$r.Add("== autocompile_status ==")
$r.Add([string](Send-Cmd '{"id":7,"cmd":"autocompile_status"}'))
$r.Add("== dirty_ram_stats ==")
$r.Add([string](Send-Cmd '{"id":8,"cmd":"dirty_ram_stats"}' 12000))
$r.Add("== fmv_state ==")
$r.Add([string](Send-Cmd '{"id":9,"cmd":"fmv_state"}'))
# Give the background compiler a nudge so the backlog builds even if its
# trigger was gated during the run.
$r.Add("== autocompile_run ==")
$r.Add([string](Send-Cmd '{"id":10,"cmd":"autocompile_run"}'))
[System.IO.File]::WriteAllLines($out, $r)
Write-Host "Wrote $out - tell Claude it's ready."
Read-Host "Press Enter to exit"
