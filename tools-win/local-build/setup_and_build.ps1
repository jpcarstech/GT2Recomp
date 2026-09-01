# GT2Recomp - one-time setup + build (Windows 10/11 x64).
#
# What it does, in order:
#   1. finds your game folder (the one holding "Gran Turismo 2 Combined.bin")
#   2. extracts the boot EXE (SCUS_944.88) from the disc image if needed
#   3. installs MSYS2 + the MinGW64 toolchain if missing (winget)
#   4. runs local_build.sh: clones/updates the source, applies the framework
#      patches, recompiles the game and installs "Gran Turismo 2 Recompiled.exe"
#      into the game folder
#
# Run it from a source checkout at <game folder>\GT2Recomp-src\tools-win\local-build\
# (the layout the README describes), or from a copy in the game folder. Anywhere
# else, pass:  -GameDir "D:\Gran Turismo 2 Recompilation"
# First build: 30-60 min depending on CPU; needs ~6 GB free RAM and ~15 GB disk.
param([string]$GameDir = "")
$ErrorActionPreference = 'Stop'
$binName = 'Gran Turismo 2 Combined.bin'
$cueName = 'Gran Turismo 2 Combined.cue'
$knownMd5 = '70ecd6e788501eb69a220d2a96e624c4'   # GT2 Combined Disc (Silent), 1,033,459,392 bytes

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($GameDir -eq "") {
    $GameDir = $here
    if (-not (Test-Path (Join-Path $GameDir $binName))) {
        # <game>\GT2Recomp-src\tools-win\local-build -> three levels up
        $up = $here
        for ($i = 0; $i -lt 3; $i++) {
            $parent = Split-Path -Parent $up
            if ([string]::IsNullOrEmpty($parent)) { break }
            $up = $parent
        }
        if ($up -and (Test-Path (Join-Path $up $binName))) { $GameDir = $up }
    }
}
# Accept a differently named single large .bin and offer to rename it.
if (-not (Test-Path (Join-Path $GameDir $binName))) {
    $cands = @(Get-ChildItem -Path $GameDir -Filter *.bin -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 500MB })
    if ($cands.Count -eq 1) {
        Write-Host ("Found disc image '{0}' but the build expects '{1}'." -f $cands[0].Name, $binName)
        $a = Read-Host "Rename it (and its .cue) now? [Y/n]"
        if ($a -eq "" -or $a -match '^[Yy]') {
            $oldCue = [IO.Path]::ChangeExtension($cands[0].FullName, '.cue')
            Rename-Item -LiteralPath $cands[0].FullName -NewName $binName
            if (Test-Path -LiteralPath $oldCue) { Rename-Item -LiteralPath $oldCue -NewName $cueName }
        }
    }
}
if (-not (Test-Path (Join-Path $GameDir $binName))) {
    Write-Host "Could not find '$binName'."
    Write-Host "Put your GT2 Combined Disc image in the game folder as described in the README,"
    Write-Host "or run this script with -GameDir `"<that folder>`"."
    Read-Host "Enter to exit"; exit 1
}
Write-Host "Game folder: $GameDir"

# ---- disc image sanity -------------------------------------------------------
$binPath = Join-Path $GameDir $binName
$binLen = (Get-Item -LiteralPath $binPath).Length
if ($binLen -ne 1033459392) {
    Write-Host ("WARNING: disc image is {0:N0} bytes; the GT2 Combined Disc this port was built from is 1,033,459,392." -f $binLen) -ForegroundColor Yellow
    Write-Host "         A different base image (GT2 Plus, another region) has a different boot EXE and will not work with these seeds." -ForegroundColor Yellow
} else {
    Write-Host "Checking disc image (MD5, a few seconds)..."
    $md5 = (Get-FileHash -LiteralPath $binPath -Algorithm MD5).Hash.ToLower()
    if ($md5 -ne $knownMd5) {
        Write-Host "WARNING: MD5 $md5 differs from the known GT2 Combined Disc ($knownMd5). Continuing anyway." -ForegroundColor Yellow
    } else { Write-Host "  disc image OK" }
}
# The runtime reads the .cue; it must reference the .bin's real file name.
$cuePath = Join-Path $GameDir $cueName
$cueBody = "FILE `"$binName`" BINARY`r`n  TRACK 01 MODE2/2352`r`n    INDEX 01 00:00:00`r`n"
if (-not (Test-Path -LiteralPath $cuePath)) {
    Set-Content -LiteralPath $cuePath -Value $cueBody -NoNewline
    Write-Host "  wrote $cueName"
} elseif ((Get-Content -LiteralPath $cuePath -Raw) -notmatch [regex]::Escape($binName)) {
    Copy-Item -LiteralPath $cuePath "$cuePath.bak" -Force
    Set-Content -LiteralPath $cuePath -Value $cueBody -NoNewline
    Write-Host "  fixed $cueName to reference $binName (old copy: $cueName.bak)"
}

# ---- boot EXE ----------------------------------------------------------------
if (-not (Test-Path (Join-Path $GameDir 'extracted\SCUS_944.88'))) {
    $extract = Join-Path $here '..\extract_gt2_exe.ps1'                 # checkout: tools-win\
    if (-not (Test-Path $extract)) { $extract = Join-Path $GameDir 'tools\extract_gt2_exe.ps1' }
    if (-not (Test-Path $extract)) { $extract = Join-Path $GameDir 'extract_gt2_exe.ps1' }
    if (-not (Test-Path $extract)) { Write-Host "extract_gt2_exe.ps1 not found."; Read-Host "Enter to exit"; exit 1 }
    Write-Host "Extracting the boot EXE from the disc image..."
    & $extract -Root $GameDir -NoPause
    if (-not (Test-Path (Join-Path $GameDir 'extracted\SCUS_944.88'))) {
        Write-Host "Extraction did not produce extracted\SCUS_944.88 - is this the GT2 Combined Disc (Simulation-disc base)?"
        Read-Host "Enter to exit"; exit 1
    }
}

# ---- toolchain ---------------------------------------------------------------
$msys = 'C:\msys64'
if (-not (Test-Path "$msys\usr\bin\bash.exe")) {
    Write-Host "Installing MSYS2 (one-time, ~100 MB)..."
    winget install -e --id MSYS2.MSYS2 --accept-source-agreements --accept-package-agreements
}
if (-not (Test-Path "$msys\usr\bin\bash.exe")) { Write-Host "MSYS2 not found at C:\msys64 - install it from msys2.org and re-run."; Read-Host "Enter to exit"; exit 1 }
Write-Host "Installing build toolchain (one-time)..."
& "$msys\usr\bin\bash.exe" -lc "pacman -S --needed --noconfirm mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja mingw-w64-x86_64-ccache git python unzip curl"

# ---- build -------------------------------------------------------------------
function To-Unix([string]$p) { return '/' + $p.Substring(0,1).ToLower() + ($p.Substring(2) -replace '\\','/') }
$script = Join-Path $here 'local_build.sh'            # beside this script (checkout or game folder)
if (-not (Test-Path $script)) { $script = Join-Path $GameDir 'local_build.sh' }
if (-not (Test-Path $script)) { Write-Host "local_build.sh not found next to this script."; Read-Host "Enter"; exit 1 }
$srcArg = ""
if (Test-Path (Join-Path $here '..\..\.git')) { $srcArg = " '" + (To-Unix (Resolve-Path (Join-Path $here '..\..')).Path) + "'" }
Write-Host "Building (first run: 30-60 min depending on CPU)..."
$env:MSYSTEM = 'MINGW64'
& "$msys\usr\bin\bash.exe" -lc ("MSYSTEM=MINGW64 bash '" + (To-Unix $script) + "' '" + (To-Unix $GameDir) + "'" + $srcArg)
Write-Host ""
Write-Host "Start the game with 'Play GT2.cmd' in the game folder."
Read-Host "Press Enter to exit"
