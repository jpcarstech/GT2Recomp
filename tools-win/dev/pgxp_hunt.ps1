# pgxp_hunt.ps1 - name the instruction that leaves a TRACK vertex without
# precision.
#
# v2: samples only the native corner of MIXED triangles (1-2 of 3 corners
# precise). A seam is one shared corner resolved precise in one triangle and
# integer in its neighbour, so it can only originate in a mixed triangle. The
# first version sampled every native vertex and landed on the tachometer HUD
# (a 2D rectangle builder at 0x8006B738) - correct behaviour, wrong target.
#
# Run on track and moving. Writes diagnostics\pgxp_hunt.txt
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outFile = Join-Path $outDir 'pgxp_hunt.txt'
$lines = New-Object System.Collections.Generic.List[string]
function Say([string]$s) { Write-Host $s; $lines.Add($s) }
function Flush { $lines -join "`r`n" | Set-Content -Path $outFile -Encoding UTF8 }

function Send-Cmd([string]$cmd, [int]$timeout = 20000) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $c.ReceiveTimeout = $timeout
        $s = $c.GetStream()
        $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s)
        $w.WriteLine($cmd); $line = $r.ReadLine(); $c.Close(); return $line
    } catch { return $null }
}

$a = Send-Cmd '{"id":1,"cmd":"pgxp_mixed"}'
if (-not $a) { Say "no reply on 127.0.0.1:4370 - is the game running?"; Flush; exit 1 }
Start-Sleep -Seconds 2
$b = Send-Cmd '{"id":2,"cmd":"pgxp_mixed"}'
Say "raw reply:"; Say ("  " + $(if ($b.Length -gt 600) { $b.Substring(0,600) + ' ...' } else { $b })); Say ""
$A=$null;$B=$null
try { $A = $a | ConvertFrom-Json; $B = $b | ConvertFrom-Json } catch { Say "reply is not JSON"; Flush; exit 1 }
if (-not $B.ok) { Say "command refused - this build lacks pgxp_mixed (rebuild + RESTART the game)"; Flush; exit 1 }

$dAll = $B.tri_all_precise - $A.tri_all_precise
$dMix = $B.tri_mixed       - $A.tri_mixed
$dNon = $B.tri_all_native  - $A.tri_all_native
$tot  = $dAll + $dMix + $dNon
Say "TRIANGLES over 2s, by resolve pattern:"
if ($tot -gt 0) {
  Say ("  all 3 corners precise : {0,9}  ({1,5:N1}%)" -f $dAll,(100.0*$dAll/$tot))
  Say ("  MIXED (1-2 precise)   : {0,9}  ({1,5:N1}%)   <-- the seam mechanism" -f $dMix,(100.0*$dMix/$tot))
  Say ("  all 3 native (2D)     : {0,9}  ({1,5:N1}%)" -f $dNon,(100.0*$dNon/$tot))
} else { Say "  no triangles resolved - are you on track and moving?" }
Say ""

$samples = @($B.samples)
Say ("mixed-triangle native corners sampled: {0}" -f $samples.Count)
if ($samples.Count -lt 1) {
    Say "  none recorded. If MIXED above is ~0, seams are NOT coming from mixed resolution."
    Flush; exit 0
}
$groups = $samples | Group-Object addr | Sort-Object Count -Descending
Say "  addr        x  word        state     n_precise  packet-src"
foreach ($g in $groups | Select-Object -First 10) {
    $s0 = $g.Group[0]
    Say ("  {0}  {1,2}  {2}  {3,-9} {4}          {5}" -f $g.Name,$g.Count,$s0.word,$s0.state,$s0.n_precise,$s0.src)
}
Say ""
$target = $groups[0].Name
Say ("arming writer trap on {0} ..." -f $target)
[void](Send-Cmd ('{"id":3,"cmd":"pgxp_trap","addr":"' + $target + '"}'))
Start-Sleep -Seconds 3
$tr = Send-Cmd '{"id":4,"cmd":"pgxp_trap"}'
if (-not $tr) { Say "trap read failed"; Flush; exit 1 }
$t = $tr | ConvertFrom-Json
Say ("stores that touched it in 3s: {0}" -f $t.total)
Say ""
if ($t.total -eq 0) {
    Say "NOBODY wrote it through a pgxp store hook (DMA, or a path with no hook)."
} else {
    Say "pc          instr       kind    value       src_live src_flags src_value"
    foreach ($h in $t.hits) {
        Say ("{0}  {1}  {2,-6}  {3}  {4,8} {5,9} {6}" -f $h.pc,$h.instr,$h.kind,$h.value,$h.src_live,$h.src_flags,$h.src_value)
    }
    Say ""
    Say "NOTE: pc is only reliable for statically-compiled code; overlay-shard stores"
    Say "leave it stale. The 'instr' word is always exact - it can be searched for in"
    Say "the EXE and overlays to locate the code."
}
Flush
Write-Host ""; Write-Host ("wrote {0}" -f $outFile)
