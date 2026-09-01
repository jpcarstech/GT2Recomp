# Garbled-text evidence capture. Run WHILE the save-load or options screen is
# showing - once when the text is GARBLED, once when it is CLEAN:
#   .\diag_text.ps1 garbled
#   .\diag_text.ps1 clean
# Works against whichever build is running (main or retail-test; both carry
# the debug server). Captures the GPU upload/readback histories with caller
# provenance (which game function sent each CPU->VRAM rect and from what
# source address), the full GP0 stream of the current frame, and a screenshot.
# Output: gt2_text_<label>.txt + gt2_text_<label>.png beside this script.
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
$out = Join-Path $root ("gt2_text_{0}.txt" -f $label)
$png = (($root -replace '\\','/') + ("/gt2_text_{0}.png" -f $label))

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

$sw = [System.IO.StreamWriter]::new($out)
$sw.WriteLine("=== diag_text '$label' $(Get-Date -Format o) ===")

$frameLine = Send-Cmd '{"id":1,"cmd":"frame"}'
$sw.WriteLine("frame: $frameLine")
$frame = -1
if ($frameLine -match '"frame":(\d+)') { $frame = [int]$Matches[1] }

$sw.WriteLine("gpu_state: "      + (Send-Cmd '{"id":2,"cmd":"gpu_state"}'))
$sw.WriteLine("gpu_opcodes: "    + (Send-Cmd '{"id":3,"cmd":"gpu_opcodes"}'))
$sw.WriteLine("gpu_ring_stats: " + (Send-Cmd '{"id":4,"cmd":"gpu_ring_stats"}'))
$sw.WriteLine("a0_history: "     + (Send-Cmd '{"id":5,"cmd":"a0_history"}'))
$sw.WriteLine("c0_history: "     + (Send-Cmd '{"id":6,"cmd":"c0_history"}'))
if ($frame -ge 0) {
    # the current frame may still be filling; dump the previous one too
    $q1 = '{{"id":7,"cmd":"gpu_frame_dump","frame":{0},"count":16384}}' -f ($frame - 1)
    $q2 = '{{"id":8,"cmd":"gpu_frame_dump","frame":{0},"count":16384}}' -f $frame
    $sw.WriteLine("gpu_frame_dump(prev): " + (Send-Cmd $q1 30000))
    $sw.WriteLine("gpu_frame_dump(cur): "  + (Send-Cmd $q2 30000))
}
$sw.WriteLine("screenshot: " + (Send-Cmd ('{{"id":9,"cmd":"screenshot_file","path":"{0}"}}' -f $png)))

# Targeted VRAM peeks: the loading-screen text is drawn as 4bpp sprites from
# the texture page at (896,256) with CLUT at (928,256); the game also streams
# a 32x480 strip to (352,0) and a 16-entry CLUT to (352,481) every frame.
# Capture all of them so garbled vs clean shows WHICH ingredient goes bad.
$peeks = @(
    @(896,256,128,128), @(896,384,128,128),   # font texture page (and CLUT row at its top)
    @(352,0,32,128), @(352,128,32,128), @(352,256,32,128), @(352,384,32,128),
    @(352,481,128,1),                          # per-frame 16-color CLUT
    @(768,511,128,1),                          # boot-time 256-color CLUT row
    @(0,24,128,128), @(600,24,128,64)          # where the boot strips landed
)
$pid2 = 10
foreach ($p in $peeks) {
    $q = '{{"id":{0},"cmd":"vram_peek","x":{1},"y":{2},"w":{3},"h":{4}}}' -f $pid2, $p[0], $p[1], $p[2], $p[3]
    $sw.WriteLine(("vram({0},{1},{2}x{3}): " -f $p[0], $p[1], $p[2], $p[3]) + (Send-Cmd $q 30000))
    $pid2++
}
$sw.Close()
Write-Host "Wrote $out"
Read-Host "Press Enter to exit"
