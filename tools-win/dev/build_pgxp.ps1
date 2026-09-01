# Builds the PGXP hook variant from the already-configured build tree and
# installs it as THE game exe ('Gran Turismo 2 Recompiled.exe'). The builtin
# "PGXP Precision" mod (Mods menu, default off) toggles the correction at
# runtime, so no separate non-PGXP exe is needed.
# Run this AFTER setup_and_build.ps1 / clean_rebuild.ps1 has completed a build.
$ErrorActionPreference = 'Stop'
$gameDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path (Join-Path $gameDir 'Gran Turismo 2 Combined.bin'))) {
    $up = Split-Path -Parent $gameDir
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Combined.bin'))) { $gameDir = $up }
}
$build = Join-Path $gameDir 'GT2Recomp-src\build'
if (-not (Test-Path (Join-Path $build 'build.ninja'))) {
    Write-Host "No configured build tree at $build - run setup_and_build.ps1 first."
    Read-Host "Enter to exit"; exit 1
}
$msys = 'C:\msys64'
if (-not (Test-Path "$msys\usr\bin\bash.exe")) {
    Write-Host "MSYS2 not found at C:\msys64 - run setup_and_build.ps1 first."
    Read-Host "Enter to exit"; exit 1
}
# Unix-style path (D:\Foo -> /d/Foo)
$ubuild = '/' + $build.Substring(0,1).ToLower() + ($build.Substring(2) -replace '\\','/')
Write-Host "Building PGXP variant (incremental)..."
$env:MSYSTEM = 'MINGW64'
& "$msys\usr\bin\bash.exe" -lc "MSYSTEM=MINGW64 cmake --build '$ubuild' --target psx-runtime-pgxp -j"
if ($LASTEXITCODE -ne 0) { Write-Host "Build failed - see output above."; Read-Host "Enter to exit"; exit 1 }
$src = Join-Path $build 'Gran_Turismo_2_Recompiled_pgxp.exe'
if (-not (Test-Path $src)) { Write-Host "Build finished but the PGXP exe was not found at $src"; Read-Host "Enter to exit"; exit 1 }
Copy-Item $src (Join-Path $gameDir 'Gran Turismo 2 Recompiled.exe') -Force
Write-Host ""
Write-Host "Done. 'Gran Turismo 2 Recompiled.exe' is now the PGXP hook build."
Write-Host "Toggle 'PGXP Precision' in the in-game Mods menu (default off)."
Write-Host "If a 'Gran Turismo 2 Recompiled (PGXP).exe' is still in this folder,"
Write-Host "it is an older duplicate - safe to delete."
Read-Host "Press Enter to exit"
