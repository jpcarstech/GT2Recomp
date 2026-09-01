# pgxp_ab.ps1 - automatic A/B sweep. Applies each PGXP config, measures how many
# vertices fall back to the rounded integer position ("native"), restores.
# Run ON TRACK AND MOVING (a replay is ideal - continuous motion, no input).
# Writes diagnostics\pgxp_ab.txt
$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$outDir = Join-Path $root 'diagnostics'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outFile = Join-Path $outDir 'pgxp_ab.txt'

$lines = New-Object System.Collections.Generic.List[string]
function Say([string]$s) { Write-Host $s; $lines.Add($s) }

function Send-Cmd([string]$cmd, [int]$timeout = 6000) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $c.ReceiveTimeout = $timeout
        $s = $c.GetStream()
        $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s)
        $w.WriteLine($cmd); $line = $r.ReadLine(); $c.Close(); return $line
    } catch { return $null }
}

function Sample([int]$seconds = 3) {
    $a = Send-Cmd '{"id":1,"cmd":"geom_correction"}'
    if (-not $a) { return $null }
    Start-Sleep -Seconds $seconds
    $b = Send-Cmd '{"id":2,"cmd":"geom_correction"}'
    if (-not $b) { return $null }
    $A = $a | ConvertFrom-Json; $B = $b | ConvertFrom-Json
    return [pscustomobject]@{
        lookups  = $B.pgxp.lookups        - $A.pgxp.lookups
        dataflow = $B.pgxp.dataflow_hit   - $A.pgxp.dataflow_hit
        fallback = $B.pgxp.fallback_hit   - $A.pgxp.fallback_hit
        native   = $B.pgxp.native         - $A.pgxp.native
        mismatch = $B.pgxp.value_mismatch - $A.pgxp.value_mismatch
        trunc    = $B.pgxp.trunc_reject   - $A.pgxp.trunc_reject
        persp    = $B.perspective_triangles - $A.perspective_triangles
        ambig    = $B.miss_ambiguous      - $A.miss_ambiguous
        ghits    = $B.geometry_vertex_hits- $A.geometry_vertex_hits
    }
}

# remember what to restore
$st = Send-Cmd '{"id":9,"cmd":"pgxp"}' | ConvertFrom-Json
if (-not $st) { Say "ERROR: game not answering on 127.0.0.1:4370"; $lines -join "`r`n" | Set-Content $outFile -Encoding UTF8; exit 1 }
$origCpu = $st.cpu_mode; $origVc = $st.vertex_cache

$configs = @(
  @{ name = 'baseline (cpu off, vcache off)'; cpu = 0; vc = 0 },
  @{ name = 'cpu ON                        '; cpu = 1; vc = 0 },
  @{ name = 'vcache ON                     '; cpu = 0; vc = 1 },
  @{ name = 'cpu ON + vcache ON            '; cpu = 1; vc = 1 }
)

Say ("pgxp_ab  {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Say "Each row = 3s of gameplay. 'native' = vertices drawn SNAPPED to the pixel grid."
Say ""
Say "config                            lookups   native   native%  dataflow%  fallback  mismatch   persp"
Say "--------------------------------------------------------------------------------------------------"

$rows = @()
foreach ($c in $configs) {
    [void](Send-Cmd ('{"id":1,"cmd":"pgxp","cpu_mode":' + $c.cpu + ',"vertex_cache":' + $c.vc + '}'))
    Start-Sleep -Milliseconds 1200          # let it settle
    $s = Sample 3
    if (-not $s) { Say ("{0}  <no reply>" -f $c.name); continue }
    $np = if ($s.lookups -gt 0) { 100.0*$s.native/$s.lookups } else { 0 }
    $dp = if ($s.lookups -gt 0) { 100.0*$s.dataflow/$s.lookups } else { 0 }
    Say ("{0}  {1,9} {2,8} {3,8:N2}% {4,9:N2}% {5,9} {6,9} {7,7}" -f `
         $c.name, $s.lookups, $s.native, $np, $dp, $s.fallback, $s.mismatch, $s.persp)
    $rows += [pscustomobject]@{ name=$c.name.Trim(); nativePct=$np }
}

[void](Send-Cmd ('{"id":1,"cmd":"pgxp","cpu_mode":' + $origCpu + ',"vertex_cache":' + $origVc + '}'))
Say ""
Say ("restored: cpu_mode={0} vertex_cache={1}" -f $origCpu, $origVc)

if ($rows.Count -gt 1) {
    $best = $rows | Sort-Object nativePct | Select-Object -First 1
    $base = $rows | Where-Object { $_.name -like 'baseline*' } | Select-Object -First 1
    Say ""
    Say ("lowest snap rate: {0}  ({1:N2}%)" -f $best.name, $best.nativePct)
    if ($base) { Say ("baseline was    : {0:N2}%" -f $base.nativePct) }
}

$lines -join "`r`n" | Set-Content -Path $outFile -Encoding UTF8
Write-Host ""
Write-Host ("wrote {0}" -f $outFile)
