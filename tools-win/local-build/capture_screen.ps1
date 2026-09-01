# Capture what is ACTUALLY ON YOUR SCREEN, at true display resolution.
#
# v2: the first version was DPI-UNAWARE, so on a scaled display Windows handed
# it a virtualised desktop (1536x864 instead of 3840x2160) and the saved image
# was a blurry downscale - the blur was the capture's, not the game's. This
# declares per-monitor DPI awareness first, and also measures the game
# window's true pixel size, which decides whether the internal supersampling
# is reaching your panel or being thrown away at the last step.
#
#   .\tools\capture_screen.ps1 -Delay 5
#   .\tools\capture_screen.ps1 -Delay 5 -Count 4     (burst, for motion)
param([int]$Delay = 3, [int]$Count = 1)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Win {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("shcore.dll")] public static extern int  SetProcessDpiAwareness(int v);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string c, string n);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    public struct RECT { public int L, T, R, B; }
    public struct POINT { public int X, Y; }
}
"@
# Per-monitor-v2 if available, else the legacy system-DPI call.
try { [void][Win]::SetProcessDpiAwareness(2) } catch { try { [void][Win]::SetProcessDPIAware() } catch {} }

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root 'diagnostics\screen'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Get-ChildItem $out -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

# Measure the game's client area in REAL pixels.
$hwnd = [Win]::FindWindow($null, "Gran Turismo 2 Recompiled")
$gw = 0; $gh = 0; $gx = 0; $gy = 0
if ($hwnd -ne [IntPtr]::Zero) {
    $r = New-Object Win+RECT
    if ([Win]::GetClientRect($hwnd, [ref]$r)) {
        $p = New-Object Win+POINT; $p.X = 0; $p.Y = 0
        [void][Win]::ClientToScreen($hwnd, [ref]$p)
        $gx = $p.X; $gy = $p.Y; $gw = $r.R - $r.L; $gh = $r.B - $r.T
    }
}

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
Write-Host ""
Write-Host ("  display (true pixels)   : {0}x{1}" -f $b.Width, $b.Height) -ForegroundColor Cyan
if ($gw -gt 0) {
    Write-Host ("  game window (true px)   : {0}x{1}  at {2},{3}" -f $gw, $gh, $gx, $gy) -ForegroundColor Cyan
    $frac = [math]::Round(100.0 * $gw / $b.Width)
    Write-Host ("  window covers           : {0}% of screen width" -f $frac)
    if ($gw -lt $b.Width * 0.9) {
        Write-Host "  -> The game is NOT filling your display. Internal supersampling is" -ForegroundColor Yellow
        Write-Host ("     being downsampled into only {0} pixels across." -f $gw) -ForegroundColor Yellow
    }
} else {
    Write-Host "  game window: not found by title (is it running?)" -ForegroundColor Yellow
}

if ($Delay -gt 0) {
    Write-Host ""
    Write-Host "Bring the game to the front with the problem visible." -ForegroundColor Yellow
    for ($i = $Delay; $i -gt 0; $i--) { Write-Host ("  capturing in {0}..." -f $i); Start-Sleep -Seconds 1 }
}

for ($n = 1; $n -le $Count; $n++) {
    # Prefer the game's client area; fall back to the whole screen.
    if ($gw -gt 0) { $cx = $gx; $cy = $gy; $cw = $gw; $ch = $gh }
    else           { $cx = $b.X; $cy = $b.Y; $cw = $b.Width; $ch = $b.Height }
    $bmp = New-Object System.Drawing.Bitmap $cw, $ch
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($cx, $cy, 0, 0, $bmp.Size)
    $p = Join-Path $out ("screen{0:d2}.png" -f $n)
    $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    Write-Host ("  wrote {0}  ({1}x{2})" -f (Split-Path $p -Leaf), $cw, $ch) -ForegroundColor Green
    if ($n -lt $Count) { Start-Sleep -Milliseconds 900 }
}
Write-Host ""
Write-Host ("Done -> {0}" -f $out) -ForegroundColor Green
