# Builds the retail-geometry TEST exe (garbled-text discriminator).
# Same tree, same patches, but PSX_EXPANDED_RAM=OFF - the retail 2MB memory
# map WITH mirrors. Installs a self-contained retail-test\ subfolder with its
# own exe, mods, and a COPY of your saves; the main install is untouched.
# Run it, boot to the save-load screen:
#   text clean   -> the expanded 8MB memory map causes the garbling
#   text garbled -> expanded RAM is exonerated, we look elsewhere
# Uses the toolchain setup_and_build.ps1 already installed.
$ErrorActionPreference = 'Stop'
$gameDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path (Join-Path $gameDir 'Gran Turismo 2 Combined.bin'))) {
    $up = Split-Path -Parent $gameDir
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Combined.bin'))) { $gameDir = $up }
}
if (-not (Test-Path (Join-Path $gameDir 'Gran Turismo 2 Combined.bin'))) {
    Write-Host "Run this from the game folder (no 'Gran Turismo 2 Combined.bin' here)."
    Read-Host "Enter to exit"; exit 1
}
$msys = 'C:\msys64'
if (-not (Test-Path "$msys\usr\bin\bash.exe")) {
    Write-Host "MSYS2 not found - run setup_and_build.ps1 first."
    Read-Host "Enter to exit"; exit 1
}
$unix = '/' + $gameDir.Substring(0,1).ToLower() + ($gameDir.Substring(2) -replace '\\','/')
$script = Join-Path $gameDir 'local_build.sh'
$uscript = '/' + $script.Substring(0,1).ToLower() + ($script.Substring(2) -replace '\\','/')
Write-Host "Building main + retail test (the retail pass recompiles most of the runtime)..."
$env:MSYSTEM = 'MINGW64'
& "$msys\usr\bin\bash.exe" -lc "GT2_RETAIL_TEST=1 MSYSTEM=MINGW64 bash '$uscript' '$unix'"
Write-Host ""
Write-Host "If the build succeeded: run 'retail-test\GT2 Retail Test.exe',"
Write-Host "let it auto-load your save, and check the save-load screen text."
Write-Host "(No shard cache for this exe - menus run interpreted; that's fine.)"
Read-Host "Press Enter to exit"
