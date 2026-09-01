# Live PGXP tuner. Run WHILE THE GAME IS RUNNING (any screen; a race is the
# useful one). Adjust the depth buffer, its near band, tolerance, and the
# correction toggles instantly - no rebuild, no restart. Nothing here is
# saved: settings revert to the launcher's choices on next launch. When you
# find values you like, note them down and tell Claude to bake them in.
#
# Commands at the prompt:
# DuckStation-parity settings (same names/semantics as DuckStation's PGXP tab):
#   tol <x>                  Geometry Tolerance in px (-1 = unlimited, DS default)
#   tex on|off               Perspective Correct Textures (DS default on)
#   color on|off             Perspective Correct Colors (DS default off)
#   cull on|off              Culling Correction (DS default on)
#   cpu on|off               CPU Mode (DS default off)
#   d2d on|off               Disable on 2D Polygons (DS default off)
#   vcache on|off            Vertex Cache (DS default off)
#   depth on|off             PGXP Depth Buffer (DS default off)
#   dclear <n>               Depth Clear Threshold, SZ units (DS default 4096)
#   tdepth on|off            Depth Test Transparent Polygons (DS default off)
#   geom on|off              geometry correction master (DS: implied by PGXP on)
# GT2Recomp additions (not DuckStation options):
#   gap 0|1|2|3              crack fill at present: 0 off, 1 precise-coverage,
#                            2 coverage visualizer, 3 all-geometry (default)
#   gfthr <x>                crack detector: how much EARLIER a run must have
#                            been drawn to count as background (default 0.05,
#                            LOWER = more aggressive)
#   gfsim <x>                how alike the two flanking surfaces must be
#                            (default 0.55, HIGHER = more aggressive)
#   gfrad <n>                widest run it will bridge, hires px (0 = auto)
#   whole on|off             whole-primitive completion (recover scenery whose
#                            per-vertex tracking was lost entirely)
#   show                     print current state
#   q                        quit (game keeps the last values until exit)
$ErrorActionPreference = 'Continue'

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

function Get-State {
    $r = Send-Cmd '{"id":1,"cmd":"pgxp"}'
    if (-not $r) { return $null }
    try { return ($r | ConvertFrom-Json) } catch { return $null }
}

function Show-State {
    $s = Get-State
    if (-not $s) { Write-Host "  (game not reachable on port 4370 - is it running?)" -ForegroundColor Yellow; return }
    Write-Host ("  geometry correction : {0}" -f @('off','ON')[[int]$s.enabled])
    Write-Host ("  geometry tolerance  : {0}" -f $(if ($s.tolerance -lt 0) { "unlimited (DS default)" } else { "$($s.tolerance) px" }))
    Write-Host ("  persp. textures     : (launcher option)")
    Write-Host ("  persp. colors       : {0}" -f @('off','ON')[[int]$s.color])
    Write-Host ("  culling correction  : {0}" -f @('off','ON')[[int]$s.culling])
    Write-Host ("  CPU mode            : {0}" -f @('off','ON')[[int]$s.cpu_mode])
    Write-Host ("  disable on 2D       : {0}" -f @('off','ON')[[int]$s.disable_2d])
    Write-Host ("  vertex cache        : {0}" -f @('off','ON')[[int]$s.vertex_cache])
    Write-Host ("  depth buffer        : {0}" -f @('off','ON')[[int]$s.depth])
    Write-Host ("  depth clear thresh. : {0}" -f $s.depth_clear)
    Write-Host ("  transparent depth   : {0}" -f @('off','ON')[[int]$s.transparent_depth])
}

# Confirm the running build actually implements a knob. Three separate times
# a command was sent to an exe that predated it, ignored silently, and read as
# "the setting does nothing" - which sent the investigation the wrong way each
# time. If the field is missing from the reply, the build is older than the
# feature and the only fix is a rebuild.
function Assert-Field([string]$field, [string]$verb) {
    $st = Get-State
    if ($null -eq $st) { Write-Host "  (no reply from the game)" -ForegroundColor Red; return $false }
    if ($null -eq $st.$field) {
        Write-Host ""
        Write-Host ("  '{0}' is NOT supported by the running build." -f $verb) -ForegroundColor Red
        Write-Host "  Your exe predates this feature - it ignored the command silently." -ForegroundColor Red
        Write-Host "  Rebuild:  .\setup_and_build.ps1   then   .\tools\compile_cache.ps1" -ForegroundColor Yellow
        Write-Host ""
        return $false
    }
    return $true
}

function OnOff([string]$w) { if ($w -match '^(on|1|true)$') { 1 } elseif ($w -match '^(off|0|false)$') { 0 } else { -1 } }

Write-Host "PGXP live tuner - game must be running. Type 'show' for state, 'q' to quit."
Show-State
while ($true) {
    $inp = (Read-Host "tune").Trim()
    if ($inp -eq '') { continue }
    if ($inp -match '^(q|quit|exit)$') { break }
    $parts = $inp -split '\s+', 2
    $verb = $parts[0].ToLower()
    $arg = if ($parts.Count -gt 1) { $parts[1].Trim() } else { '' }
    switch ($verb) {
        'show' { Show-State; continue }
        'depth' {
            $v = OnOff $arg
            if ($v -lt 0) { Write-Host "  usage: depth on|off"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","depth":' + $v + '}'))
            Show-State
        }
        'tol' {
            if ($arg -notmatch '^-?\d+(\.\d+)?$') { Write-Host "  usage: tol 0.5  (or  tol -1  for unlimited)"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","tolerance":' + $arg + '}'))
            Show-State
        }
        'geom' {
            $v = OnOff $arg
            if ($v -lt 0) { Write-Host "  usage: geom on|off"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","geometry":' + $v + '}'))
            Show-State
        }
        'tex' {
            $v = OnOff $arg
            if ($v -lt 0) { Write-Host "  usage: tex on|off"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","texture":' + $v + '}'))
            Show-State
        }
        'cpu' {
            $v = OnOff $arg
            if ($v -lt 0) { Write-Host "  usage: cpu on|off"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","cpu_mode":' + $v + '}'))
            Show-State
        }
        'color' {
            $v = OnOff $arg
            if ($v -lt 0) { Write-Host "  usage: color on|off"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","color":' + $v + '}'))
            Show-State
        }
        'cull' {
            $v = OnOff $arg
            if ($v -lt 0) { Write-Host "  usage: cull on|off"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","culling":' + $v + '}'))
            Show-State
        }
        'd2d' {
            $v = OnOff $arg
            if ($v -lt 0) { Write-Host "  usage: d2d on|off"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","disable_2d":' + $v + '}'))
            Show-State
        }
        'vcache' {
            $v = OnOff $arg
            if ($v -lt 0) { Write-Host "  usage: vcache on|off"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","vertex_cache":' + $v + '}'))
            Show-State
        }
        'tdepth' {
            $v = OnOff $arg
            if ($v -lt 0) { Write-Host "  usage: tdepth on|off"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","transparent_depth":' + $v + '}'))
            Show-State
        }
        'gfthr' {
            if (-not (Assert-Field 'gfthr' 'gfthr')) { continue }
            if ($arg -notmatch '^\d*\.?\d+$') { Write-Host "  usage: gfthr 0.02   (how much EARLIER a run must have been drawn to count as background; lower = more aggressive)"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","gfthr":' + $arg + '}'))
            Write-Host ("  draw-order threshold -> {0}" -f $arg); continue
        }
        'gfsim' {
            if (-not (Assert-Field 'gfsim' 'gfsim')) { continue }
            if ($arg -notmatch '^\d*\.?\d+$') { Write-Host "  usage: gfsim 0.9    (how ALIKE the two flanks must be; higher = more aggressive)"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","gfsim":' + $arg + '}'))
            Write-Host ("  flank-similarity -> {0}" -f $arg); continue
        }
        'gfrad' {
            if (-not (Assert-Field 'gfrad' 'gfrad')) { continue }
            if ($arg -notmatch '^\d+$') { Write-Host "  usage: gfrad 24     (widest run it will bridge, hires px; 0 = auto)"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","gfrad":' + $arg + '}'))
            Write-Host ("  fill radius -> {0}" -f $arg); continue
        }
        'gap' {
            if ($arg -notmatch '^[0-3]$') { Write-Host "  usage: gap 0|1|2|3"; continue }
            if (-not (Assert-Field 'gapfill' 'gap')) { continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","gapfill":' + $arg + '}'))
            Write-Host ("  gapfill -> {0}" -f $arg)
            continue
        }
        'whole' {
            if (-not (Assert-Field 'whole' 'whole')) { continue }
            $v = OnOff $arg
            if ($v -lt 0) { Write-Host "  usage: whole on|off"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","whole":' + $v + '}'))
            Write-Host ("  whole-primitive completion -> {0}" -f @('off','ON')[$v])
            continue
        }
        'wipe' {
            [void](Send-Cmd '{"id":1,"cmd":"pgxp","invalidate":1}')
            Write-Host "  PGXP dataflow shadow invalidated (nothing else touched)"
            continue
        }
        'framewipe' {
            if (-not (Assert-Field 'framewipe' 'framewipe')) { continue }
            if ($arg -notmatch '^[0-2]$') {
                Write-Host "  usage: framewipe 0|1|2"
                Write-Host "     0 = never retire the shadow (old behaviour -> seams)"
                Write-Host "     1 = hard wipe every frame     (-> wobble)"
                Write-Host "     2 = one-frame grace window    (default, the fix)"
                continue
            }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","framewipe":' + $arg + '}'))
            Write-Host ("  shadow retirement -> {0}" -f @('0 never','1 hard wipe','2 one-frame window')[[int]$arg])
            continue
        }
        'dclear' {
            if ($arg -notmatch '^\d+$') { Write-Host "  usage: dclear 4096"; continue }
            [void](Send-Cmd ('{"id":1,"cmd":"pgxp","depth_clear":' + $arg + '}'))
            Show-State
        }
        default { Write-Host "  commands: tol <x>, tex/color/cull/cpu/d2d/vcache/depth/tdepth/whole on|off, dclear <n>, gap 0-3, gfthr/gfsim <x>, gfrad <n>, geom on|off, show, q" }
    }
}
