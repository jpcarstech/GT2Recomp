# Capture the REAL SCREEN under each crack-fill mode, from one fixed spot.
#
# Park where the cyan cracks are visible, in FULLSCREEN, then run this. It
# cycles the fill modes and grabs the actual presented frame each time, so we
# can see which (if any) touches the cracks.
#
# Mode 2 is the coverage VISUALISER - it paints what the crack detector
# believes is covered. If the crack lines show up as covered there, the
# detector is blind to them by construction and no mode will ever fill them.
#
#   .\tools\diag_gaps_screen.ps1
param([int]$Delay = 6)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class W2 {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("shcore.dll")] public static extern int  SetProcessDpiAwareness(int v);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern IntPtr FindWindow(string c, string n);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    public struct RECT { public int L, T, R, B; }
    public struct POINT { public int X, Y; }
}
"@
try { [void][W2]::SetProcessDpiAwareness(2) } catch { try { [void][W2]::SetProcessDPIAware() } catch {} }
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root 'diagnostics\screen_ab'
New-Item -ItemType Directory -Force -Path $out | Out-Null
Get-ChildItem $out -Filter *.png -ErrorAction SilentlyContinue | Remove-Item -Force

function Send-Cmd([string]$cmd) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4370)
        $c.ReceiveTimeout = 15000
        $s = $c.GetStream()
        $w = New-Object System.IO.StreamWriter($s); $w.AutoFlush = $true
        $r = New-Object System.IO.StreamReader($s)
        $w.WriteLine($cmd); $l = $r.ReadLine(); $c.Close(); return $l
    } catch { return $null }
}
if (-not (Send-Cmd '{"id":1,"cmd":"frame"}')) { Write-Host "Game not reachable on :4370" -ForegroundColor Red; exit 1 }

$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$hwnd = [W2]::FindWindow($null, "Gran Turismo 2 Recompiled")
$cx=$b.X; $cy=$b.Y; $cw=$b.Width; $ch=$b.Height
if ($hwnd -ne [IntPtr]::Zero) {
    $r = New-Object W2+RECT
    if ([W2]::GetClientRect($hwnd, [ref]$r)) {
        $p = New-Object W2+POINT; $p.X=0; $p.Y=0
        [void][W2]::ClientToScreen($hwnd, [ref]$p)
        if (($r.R-$r.L) -gt 0) { $cx=$p.X; $cy=$p.Y; $cw=$r.R-$r.L; $ch=$r.B-$r.T }
    }
}
Write-Host ("  capturing {0}x{1} at {2},{3}" -f $cw,$ch,$cx,$cy) -ForegroundColor Cyan
Write-Host ""
Write-Host "Switch to the game (fullscreen), parked where the cracks show." -ForegroundColor Yellow
for ($i=$Delay; $i -gt 0; $i--) { Write-Host ("  starting in {0}..." -f $i); Start-Sleep -Seconds 1 }

function Grab($name) {
    $bmp = New-Object System.Drawing.Bitmap $cw, $ch
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($cx, $cy, 0, 0, $bmp.Size)
    $bmp.Save((Join-Path $out ($name + '.png')), [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}
foreach ($m in 0,1,2,3) {
    [void](Send-Cmd ('{"id":1,"cmd":"pgxp","gapfill":' + $m + '}'))
    Start-Sleep -Milliseconds 900
    Grab ("gap$m")
}
[void](Send-Cmd '{"id":1,"cmd":"pgxp","gapfill":3}')
Write-Host ""
Write-Host ("Done -> {0}   (gap0/gap1/gap2/gap3)" -f $out) -ForegroundColor Green
Write-Host "gap2 is the coverage visualiser - that's the decisive one." -ForegroundColor Green
