# win_burst.ps1 - grab what is ACTUALLY ON SCREEN: a burst of window captures
# of the running game, as fast as the desktop allows (~60/s), so 60 Hz
# presentation problems (frame alternation, judder) can be seen frame by frame.
#   .\tools\win_burst.ps1 [count] [x y w h]
# x,y,w,h = optional crop inside the game's client area (window pixels).
# Writes diagnostics\winburst\win_NN.png and win_index.txt (timestamps).
param([int]$count=40,[int]$x=-1,[int]$y=-1,[int]$w=0,[int]$h=0)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
$diag = Join-Path $root 'diagnostics'
if (-not (Test-Path $diag)) { New-Item -ItemType Directory -Path $diag -Force | Out-Null }
$logPath = Join-Path $diag 'win_burst_log.txt'
Start-Transcript -Path $logPath -Force | Out-Null
try {
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System; using System.Runtime.InteropServices;
public struct RECT { public int Left, Top, Right, Bottom; }
public struct PT { public int X, Y; }
public static class W32 {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string cls, string title);
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref PT p);
}
"@
$outDir = Join-Path $root 'diagnostics\winburst'
if (Test-Path $outDir) { Remove-Item (Join-Path $outDir '*') -Force }
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
[void][W32]::SetProcessDPIAware()   # physical pixels, not DPI-virtualized ones
$hwnd = [W32]::FindWindow($null, 'Gran Turismo 2 Recompiled')
if ($hwnd -eq [IntPtr]::Zero) {
    $proc = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and ($_.MainWindowTitle -like '*Gran Turismo*' -or $_.ProcessName -like '*Gran Turismo*' -or $_.ProcessName -like '*Recompiled*') } | Select-Object -First 1
    if ($proc) { $hwnd = $proc.MainWindowHandle; Write-Host ("found window via process {0}: '{1}'" -f $proc.ProcessName, $proc.MainWindowTitle) }
}
if ($hwnd -eq [IntPtr]::Zero) {
    Write-Host "game window not found. Windows with titles:" -ForegroundColor Red
    Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object { Write-Host ("  {0}: {1}" -f $_.ProcessName, $_.MainWindowTitle) }
    throw "no game window"
}
$rc = New-Object RECT; [void][W32]::GetClientRect($hwnd, [ref]$rc)
$pt = New-Object PT; $pt.X = 0; $pt.Y = 0; [void][W32]::ClientToScreen($hwnd, [ref]$pt)
$cw = $rc.Right - $rc.Left; $ch = $rc.Bottom - $rc.Top
if ($x -lt 0) { $x = 0; $y = 0; $w = $cw; $h = $ch }
if ($w -le 0 -or $h -le 0) { $w = $cw - $x; $h = $ch - $y }
Write-Host ("client {0}x{1} at screen {2},{3}; capturing {4}x{5} @ {6},{7} x{8}; screen {9}x{10}" -f $cw,$ch,$pt.X,$pt.Y,$w,$h,$x,$y,$count,[System.Windows.Forms.SystemInformation]::VirtualScreen.Width,[System.Windows.Forms.SystemInformation]::VirtualScreen.Height)
$frames = New-Object System.Collections.ArrayList
$times  = New-Object System.Collections.ArrayList
$sw = [Diagnostics.Stopwatch]::StartNew()
for ($i=0; $i -lt $count; $i++) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($pt.X + $x, $pt.Y + $y, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $g.Dispose()
    [void]$frames.Add($bmp); [void]$times.Add($sw.ElapsedMilliseconds)
}
$idx = @()
for ($i=0; $i -lt $frames.Count; $i++) {
    $frames[$i].Save((Join-Path $outDir ("win_{0:D2}.png" -f $i)), [System.Drawing.Imaging.ImageFormat]::Png)
    $frames[$i].Dispose()
    $idx += ("{0:D2} t={1}ms" -f $i, $times[$i])
}
$idx | Set-Content (Join-Path $outDir 'win_index.txt')
Write-Host ("done - {0} frames over {1} ms in diagnostics\winburst\" -f $count, $times[$times.Count-1]) -ForegroundColor Green
} catch { Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red; Write-Host $_.ScriptStackTrace }
finally { Stop-Transcript | Out-Null }
