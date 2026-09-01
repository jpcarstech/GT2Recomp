# Full PGXP + video state of the RUNNING game, in one shot.
#
# Everything here used to be invisible at runtime - which is how a silently
# clamped internal scale survived four rounds of investigation. If a value
# differs from what you configured, this is where you find out.
#
#   .\tools\show_video.ps1
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot

function Send-Cmd([string]$cmd, [int]$timeout = 15000) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $c.ReceiveTimeout = $timeout
        $s = $c.GetStream()
        $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s)
        $w.WriteLine($cmd); $line = $r.ReadLine(); $c.Close(); return $line
    } catch { return $null }
}

$j = Send-Cmd '{"id":1,"cmd":"pgxp"}'
if (-not $j) { Write-Host "Cannot reach the game on 127.0.0.1:4370 - is it running?" -ForegroundColor Red; exit 1 }
$s = $j | ConvertFrom-Json

function OnOff($v) { if ($v) { 'ON' } else { 'off' } }
$want = $null
$sf = Join-Path $root 'settings.toml'
if (Test-Path $sf) {
    $m = (Select-String -Path $sf -Pattern '^\s*supersampling\s*=\s*(\d+)').Matches
    if ($m.Count) { $want = [int]$m[0].Groups[1].Value }
}

Write-Host ""
Write-Host "  RESOLUTION" -ForegroundColor Cyan
Write-Host ("    internal scale rendering now : {0}x  ({1}x{2} buffer)" -f $s.scale, (320*$s.scale), (240*$s.scale))
if ($want) {
    if ($want -ne $s.scale) {
        Write-Host ("    settings.toml asked for      : {0}x   <-- MISMATCH" -f $want) -ForegroundColor Yellow
        Write-Host "    Your GPU likely caps texture/renderbuffer size below what that" -ForegroundColor Yellow
        Write-Host "    scale needs, so the renderer fit it down instead of failing." -ForegroundColor Yellow
    } else {
        Write-Host ("    settings.toml asked for      : {0}x   (matches)" -f $want) -ForegroundColor Green
    }
}
Write-Host ""
Write-Host "  PGXP - these should all read as shown for GT2" -ForegroundColor Cyan
Write-Host ("    geometry correction   : {0}   (want ON)"  -f (OnOff $s.enabled))
Write-Host ("    perspective textures  : {0}   (want ON)"  -f (OnOff $s.texture))
Write-Host ("    culling correction    : {0}   (want ON)"  -f (OnOff $s.culling))
Write-Host ("    preserve projection   : {0}   (want ON)"  -f (OnOff $s.preserve))
Write-Host ("    geometry tolerance    : {0}" -f $(if ($s.tolerance -lt 0) { 'unlimited' } else { "$($s.tolerance) px" }))
Write-Host ("    depth buffer          : {0}   (want off - it amplifies seams on GT2)" -f (OnOff $s.depth))
Write-Host ("    CPU mode              : {0}   (want off)" -f (OnOff $s.cpu_mode))
Write-Host ("    vertex cache          : {0}   (want off - corrupts 2D tiles)" -f (OnOff $s.vertex_cache))
Write-Host ("    perspective colors    : {0}   (want off)" -f (OnOff $s.color))
Write-Host ("    disable on 2D         : {0}   (want off)" -f (OnOff $s.disable_2d))
Write-Host ""
Write-Host "  CRACK HANDLING (this port's additions)" -ForegroundColor Cyan
Write-Host ("    gap fill mode         : {0}   (3 = all-geometry, the default)" -f $s.gapfill)
Write-Host ("    whole-prim completion : {0}   (want ON)" -f (OnOff $s.whole))

if ($null -ne $s.gf_why) {
    $w = [int]$s.gf_why
    Write-Host ("    fill actually running : {0}" -f $(if ($s.gf_active) { "YES (mode $($s.gf_active))" } else { "NO" })) -ForegroundColor $(if ($s.gf_active) { 'Green' } else { 'Yellow' })
    if (-not $s.gf_active) {
        Write-Host "      why not:" -ForegroundColor Yellow
        if (-not ($w -band 1)) { Write-Host "        - coverage texture was never allocated (too large for this GPU at this scale?)" -ForegroundColor Yellow }
        if (-not ($w -band 2)) { Write-Host "        - the presented surface has no coverage buffer paired with it" -ForegroundColor Yellow }
        if (-not ($w -band 4)) { Write-Host "        - internal scale is 1 (fill needs supersampling > 1)" -ForegroundColor Yellow }
        if (-not ($w -band 8)) { Write-Host "        - fill mode is set to 0 (off)" -ForegroundColor Yellow }
    }
}

# How much geometry is actually getting corrected right now.
[void](Send-Cmd '{"id":2,"cmd":"pgxp_tri","reset":1}')
Start-Sleep -Milliseconds 1200
$t = Send-Cmd '{"id":3,"cmd":"pgxp_tri"}'
Write-Host ""
Write-Host "  COVERAGE over the last ~1s" -ForegroundColor Cyan
if (-not $t) {
    Write-Host "    no reply from pgxp_tri." -ForegroundColor Yellow
} else {
    $tj = $t | ConvertFrom-Json
    $tot = ($tj.census | Measure-Object -Sum).Sum
    if ($tot -le 0) {
        Write-Host "    no triangles drawn in that window - run this DURING A RACE," -ForegroundColor Yellow
        Write-Host "    not at a menu, or there is no 3D geometry to measure." -ForegroundColor Yellow
    } else {
        $pct = [math]::Round(100.0 * $tj.census[3] / $tot, 2)
        Write-Host ("    triangles fully corrected : {0} of {1}  ({2}%)" -f $tj.census[3], $tot, $pct)
        Write-Host ("    uncorrected 3D / real 2D  : {0} / {1}" -f $tj.native3d, $tj.native2d)
        if ($pct -lt 95) {
            Write-Host "    <-- below 95%: real geometry is missing correction." -ForegroundColor Yellow
        } else {
            Write-Host "    -> full coverage." -ForegroundColor Green
        }
    }
}
Write-Host ""
