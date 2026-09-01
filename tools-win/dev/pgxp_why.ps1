# pgxp_why.ps1 - is perspective-correct texturing actually firing, and where is
# PGXP losing vertices? Writes diagnostics\pgxp_why.txt so it can be read back.
# Usage:  .\tools\pgxp_why.ps1     (game running, ON TRACK and moving)
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outFile = Join-Path $outDir 'pgxp_why.txt'

$lines = New-Object System.Collections.Generic.List[string]
function Say([string]$s) { Write-Host $s; $lines.Add($s) }

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

$rawA = Send-Cmd '{"id":1,"cmd":"geom_correction"}'
if (-not $rawA) {
    Say "ERROR: no reply on 127.0.0.1:4370 - is the game running?"
    $lines -join "`r`n" | Set-Content -Path $outFile -Encoding UTF8
    exit 1
}
Start-Sleep -Seconds 2
$rawB = Send-Cmd '{"id":2,"cmd":"geom_correction"}'
$rawP = Send-Cmd '{"id":3,"cmd":"pgxp"}'

$a = $rawA | ConvertFrom-Json
$b = $rawB | ConvertFrom-Json

$dPersp = $b.perspective_triangles - $a.perspective_triangles
$dGeom  = $b.geometry_vertex_hits  - $a.geometry_vertex_hits
$dLook  = $b.pgxp.lookups          - $a.pgxp.lookups
$dFlow  = $b.pgxp.dataflow_hit     - $a.pgxp.dataflow_hit
$dFall  = $b.pgxp.fallback_hit     - $a.pgxp.fallback_hit
$dNat   = $b.pgxp.native           - $a.pgxp.native
$dMis   = $b.pgxp.value_mismatch   - $a.pgxp.value_mismatch
$dTrunc = $b.pgxp.trunc_reject     - $a.pgxp.trunc_reject
$dTol   = $b.pgxp.tolerance_reject - $a.pgxp.tolerance_reject
$dProd  = $b.pgxp.produced         - $a.pgxp.produced
$dSwc2  = $b.pgxp.swc2_stores      - $a.pgxp.swc2_stores
$dMissU = $b.miss_unrecorded       - $a.miss_unrecorded
$dMissA = $b.miss_ambiguous        - $a.miss_ambiguous

Say ("pgxp_why  {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say "--- deltas over 2 seconds of gameplay ---"
Say ("geometry_correction enabled : {0}" -f $b.geometry_correction)
Say ("pgxp enabled / cpu_mode     : {0} / {1}   tolerance {2}" -f $b.pgxp.enabled, $b.pgxp.cpu_mode, $b.pgxp.tolerance)
Say ""
Say ("PERSPECTIVE TRIANGLES       : {0}      <-- perspective-correct TEXTURES" -f $dPersp)
Say ("geometry vertex hits        : {0}" -f $dGeom)
Say ("  miss_unrecorded           : {0}" -f $dMissU)
Say ("  miss_ambiguous            : {0}" -f $dMissA)
Say ""
Say ("swc2_stores (projections)   : {0}" -f $dSwc2)
Say ("pgxp produced               : {0}" -f $dProd)
Say ("pgxp vertex lookups         : {0}" -f $dLook)
if ($dLook -gt 0) {
    Say ("  dataflow hit   : {0,10}  ({1,5:N1}%)" -f $dFlow, (100.0*$dFlow/$dLook))
    Say ("  fallback hit   : {0,10}  ({1,5:N1}%)" -f $dFall, (100.0*$dFall/$dLook))
    Say ("  native         : {0,10}  ({1,5:N1}%)" -f $dNat,  (100.0*$dNat /$dLook))
    Say ("  value_mismatch : {0,10}  ({1,5:N1}%)  <-- stale shadow = precision hole" -f $dMis, (100.0*$dMis/$dLook))
    Say ("  trunc_reject   : {0,10}" -f $dTrunc)
    Say ("  tol_reject     : {0,10}" -f $dTol)
    $unres = $dLook - $dFlow - $dFall - $dNat
    Say ("  UNRESOLVED     : {0,10}  ({1,5:N1}%)  <-- drawn at rounded integer position" -f $unres, (100.0*$unres/$dLook))
}
# why did the unresolved vertices fail?
if ($b.pgxp.why) {
    $wa=$a.pgxp.why; $wb=$b.pgxp.why
    $dn = $wb.noaddr-$wa.noaddr; $ds = $wb.stale-$wa.stale; $df = $wb.flagless-$wa.flagless
    $dm = $wb.mismatch-$wa.mismatch
    $tot = $dn+$ds+$df+$dm
    Say ""
    Say "WHY vertices fell back to the rounded integer position:"
    if ($tot -gt 0) {
        Say ("  noaddr   : {0,9}  ({1,5:N1}%)  no source address / no shadow slot" -f $dn,(100.0*$dn/$tot))
        Say ("  stale    : {0,9}  ({1,5:N1}%)  slot from a retired generation" -f $ds,(100.0*$ds/$tot))
        Say ("  flagless : {0,9}  ({1,5:N1}%)  slot LIVE but carries no X/Y  <-- provenance lost in transit" -f $df,(100.0*$df/$tot))
        Say ("  mismatch : {0,9}  ({1,5:N1}%)  live+flagged, describes another word" -f $dm,(100.0*$dm/$tot))
    } else { Say "  (none - every vertex resolved)" }
}

# THE seam metric: mixed triangles (1-2 of 3 corners precise) and SXY shadow health
$m1 = Send-Cmd '{"id":11,"cmd":"pgxp_mixed"}'
if ($m1) {
    try {
        $M1 = $m1 | ConvertFrom-Json
        if ($M1.ok) {
            Start-Sleep -Seconds 2
            $M2 = (Send-Cmd '{"id":12,"cmd":"pgxp_mixed"}') | ConvertFrom-Json
            $dm = $M2.tri_mixed - $M1.tri_mixed; $da = $M2.tri_all_precise - $M1.tri_all_precise
            Say ""
            Say ("SEAM MECHANISM - mixed triangles over 2s : {0}   (all-precise: {1})" -f $dm, $da)
            Say "   (before the SXYP FIFO fix this was ~1000+ per 2s; after it should be ~0)"
        }
    } catch {}
}
$sw = Send-Cmd '{"id":13,"cmd":"pgxp_swc2"}'
if ($sw) {
    try {
        $SW = $sw | ConvertFrom-Json
        if ($SW.ok) {
            $bad = @($SW.sites | Where-Object { $_.total -ge 20 -and $_.bad -gt 0 })
            Say ("SXY shadow health: {0} swc2 site(s) with stale shadows" -f $bad.Count)
            foreach ($b in ($bad | Sort-Object bad -Descending | Select-Object -First 6)) {
                Say ("   pc={0} reg{1} bad {2}/{3}" -f $b.pc,$b.reg,$b.bad,$b.total)
            }
        }
    } catch {}
}

Say ""
if ($dPersp -eq 0) {
    Say "VERDICT: perspective-correct texturing is NOT firing on any triangle."
} else {
    Say ("VERDICT: perspective-correct texturing IS firing ({0} tris / 2s)." -f $dPersp)
}
Say ""
Say "--- raw ---"
Say ("A: " + $rawA)
Say ("B: " + $rawB)
Say ("P: " + $rawP)

$lines -join "`r`n" | Set-Content -Path $outFile -Encoding UTF8
Write-Host ""
Write-Host ("wrote {0}" -f $outFile)
