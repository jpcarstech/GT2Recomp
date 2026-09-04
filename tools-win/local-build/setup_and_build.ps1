# GT2Recomp - one-time setup + build (Windows 10/11 x64).
#
# What it does, in order:
#   1. finds your game folder - the one holding your GT2 disc image(s). If
#      this script is not already in it, a folder picker asks for it, and the
#      setup files copy themselves there so future updates run from the game
#      folder itself. Extract the zip anywhere; it does not matter where.
#   2. shows the discs it found and asks before starting the long step
#   3. installs MSYS2 + the MinGW64 toolchain if missing (winget)
#   4. runs local_build.sh: clones/updates the source, applies the framework
#      patches, works out which GT2 disc each image is (Arcade, Simulation,
#      or the optional Combined Disc - any file names), recompiles every disc
#      it finds into titles\<name>\, and installs the "Gran Turismo 2
#      Recompiled.exe" front door into the game folder
#
# Also runs from a source checkout at <game folder>\GT2Recomp-src\tools-win\local-build\
# (the layout docs/BUILDING.md describes). Anywhere else, pass:
#   -GameDir "D:\Gran Turismo 2 Recompilation"
# First build: 30-60 min PER DISC depending on CPU; ~6 GB free RAM, ~15 GB disk.
param([string]$GameDir = "")
$ErrorActionPreference = 'Stop'

function Get-DiscImages([string]$dir) {
    return @(Get-ChildItem -LiteralPath $dir -Filter *.bin -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Length -gt 400MB })
}
function Has-DiscImage([string]$dir) { return (Get-DiscImages $dir).Count -gt 0 }

# A quick, size-based label so the confirmation reads like a sentence. The
# build itself identifies discs by content (boot serial + track size); this is
# only for the message, so an unrecognised size is not an error.
function Disc-Label($f) {
    switch ($f.Length) {
        729606864  { return "Arcade disc (v1.1)" }
        680856960  { return "Simulation disc (v1.1)" }
        1033459392 { return "Combined Disc (fan-made, optional)" }
        default    { return "disc image (identified during the build)" }
    }
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$setupFiles = @('Setup GT2.cmd', 'setup_and_build.ps1', 'local_build.sh', 'Diagnose GT2.cmd')

# ---- 1. find the game folder -------------------------------------------------
if ($GameDir -eq "") {
    $GameDir = $here
    if (-not (Has-DiscImage $GameDir)) {
        # <game>\GT2Recomp-src\tools-win\local-build -> three levels up
        $up = $here
        for ($i = 0; $i -lt 3; $i++) {
            $parent = Split-Path -Parent $up
            if ([string]::IsNullOrEmpty($parent)) { break }
            $up = $parent
        }
        if ($up -and (Has-DiscImage $up)) { $GameDir = $up }
    }
    if (-not (Has-DiscImage $GameDir)) {
        # Not beside the discs (the zip was extracted to Downloads, say): ask.
        # This is the normal first-run path, not an error.
        Write-Host ""
        Write-Host "No GT2 disc image is in this folder, so let's find them." -ForegroundColor Cyan
        Write-Host "In the window that opens, pick the folder that holds your GT2 disc"
        Write-Host "dump(s) as .bin files - Arcade, Simulation, or both. That folder"
        Write-Host "becomes the game folder: the game is built and installed there."
        Write-Host ""
        Add-Type -AssemblyName System.Windows.Forms
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Pick the folder that holds your Gran Turismo 2 disc image(s) (.bin)"
        $dlg.ShowNewFolderButton = $false
        $dlg.RootFolder = [System.Environment+SpecialFolder]::MyComputer
        $picked = $null
        for (;;) {
            $r = $dlg.ShowDialog((New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }))
            if ($r -ne [System.Windows.Forms.DialogResult]::OK) {
                Write-Host "No folder chosen - nothing to build."
                Write-Host "Put your GT2 .bin disc image(s) in a folder and run this again."
                Read-Host "Enter to exit"; exit 1
            }
            if (Has-DiscImage $dlg.SelectedPath) { $picked = $dlg.SelectedPath; break }
            Write-Host ("No .bin disc image found in {0} - try again." -f $dlg.SelectedPath) -ForegroundColor Yellow
            [void][System.Windows.Forms.MessageBox]::Show(
                "No GT2 disc image (.bin, larger than 400 MB) was found in:`n`n$($dlg.SelectedPath)`n`nPick the folder that holds your disc dump(s).",
                "GT2Recomp setup", 'OK', 'Information')
        }
        $GameDir = $picked
    }
}
if (-not (Has-DiscImage $GameDir)) {
    Write-Host "No disc image found in $GameDir."
    Write-Host "Put your Gran Turismo 2 disc dump(s) (.bin files - Arcade disc,"
    Write-Host "Simulation disc, or both; any file names) in the game folder, or run"
    Write-Host "this script with -GameDir `"<that folder>`"."
    Read-Host "Enter to exit"; exit 1
}
$GameDir = (Resolve-Path -LiteralPath $GameDir).Path

# The setup files live in the game folder from now on, so an update is
# "re-run Setup GT2.cmd there" - and so the build below runs from one place
# whatever folder the zip was extracted to. Never overwrite a newer copy.
if ($GameDir -ne $here) {
    foreach ($f in $setupFiles) {
        $src = Join-Path $here $f
        $dst = Join-Path $GameDir $f
        if (-not (Test-Path -LiteralPath $src)) { continue }
        if ((Test-Path -LiteralPath $dst) -and
            ((Get-Item -LiteralPath $dst).LastWriteTimeUtc -gt (Get-Item -LiteralPath $src).LastWriteTimeUtc)) { continue }
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }
    Write-Host ("Setup files copied to the game folder - next time, run 'Setup GT2.cmd' from there.")
}

# ---- 2. say what is about to happen, and ask ------------------------------
$discs = Get-DiscImages $GameDir
Write-Host ""
Write-Host "Game folder: $GameDir" -ForegroundColor Cyan
Write-Host "Disc images found:"
foreach ($d in $discs) { Write-Host ("   {0,-46} {1}" -f $d.Name, (Disc-Label $d)) }
$n = $discs.Count
function Format-Span([int]$m) {
    if ($m -ge 60) { $h = [math]::Floor($m / 60); $r = $m % 60
        if ($r -eq 0) { return "$h hr" } else { return "$h hr $r min" } }
    return "$m min"
}
Write-Host ""
Write-Host ("Each disc becomes its own build; expect roughly {0} to {1} in total and" -f (Format-Span ($n*30)), (Format-Span ($n*60)))
Write-Host ("about {0} GB of disk. Don't want one of them? Move it out of the folder first." -f ($n*4))
Write-Host "(Already built discs are only updated, which takes minutes.)"
$a = Read-Host ("Build {0} disc{1}? [Y/n]" -f $n, $(if ($n -eq 1) {""} else {"s"}))
if ($a -match '^[Nn]') { Write-Host "Stopped - nothing was changed."; Read-Host "Enter to exit"; exit 0 }

# ---- 3. toolchain --------------------------------------------------------------
$msys = 'C:\msys64'
if (-not (Test-Path "$msys\usr\bin\bash.exe")) {
    Write-Host "Installing MSYS2 (one-time, ~100 MB)..."
    winget install -e --id MSYS2.MSYS2 --accept-source-agreements --accept-package-agreements
}
if (-not (Test-Path "$msys\usr\bin\bash.exe")) { Write-Host "MSYS2 not found at C:\msys64 - install it from msys2.org and re-run."; Read-Host "Enter to exit"; exit 1 }
Write-Host "Installing build toolchain (one-time)..."
& "$msys\usr\bin\bash.exe" -lc "pacman -S --needed --noconfirm mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja mingw-w64-x86_64-ccache mingw-w64-x86_64-vulkan-headers mingw-w64-x86_64-shaderc git python unzip curl"

# ---- 4. build ------------------------------------------------------------------
function To-Unix([string]$p) { return '/' + $p.Substring(0,1).ToLower() + ($p.Substring(2) -replace '\\','/') }
$script = Join-Path $GameDir 'local_build.sh'           # the game-folder copy, always
if (-not (Test-Path $script)) { $script = Join-Path $here 'local_build.sh' }
if (-not (Test-Path $script)) { Write-Host "local_build.sh not found next to this script."; Read-Host "Enter"; exit 1 }
$srcArg = ""
if (Test-Path (Join-Path $here '..\..\.git')) { $srcArg = " '" + (To-Unix (Resolve-Path (Join-Path $here '..\..')).Path) + "'" }
Write-Host ""
Write-Host "Building. This window keeps you posted - one live line per disc with a" -ForegroundColor Cyan
Write-Host "percentage and a time estimate. Leave it alone until it prints DONE."
$env:MSYSTEM = 'MINGW64'
& "$msys\usr\bin\bash.exe" -lc ("MSYSTEM=MINGW64 bash '" + (To-Unix $script) + "' '" + (To-Unix $GameDir) + "'" + $srcArg)
Write-Host ""
Write-Host "Double-click 'Gran Turismo 2 Recompiled.exe' in the game folder to play:"
Write-Host "   $GameDir"
Read-Host "Press Enter to exit"
