# One-time game-folder cleanup: sorts the accumulated files into
#   tools\        - all helper / diagnostic scripts
#   diagnostics\  - text captures and logs
#   dumps\        - large binary captures (RAM/VRAM dumps, freeze dumps)
#   _attic\transfer\ - the one-off disc-slice/exe-transfer files (done their job)
# Root keeps: the exe, Play GT2.cmd, setup_and_build.ps1, the disc, configs,
# saves, patches, cache, and the folders the game itself uses.
# Safe to re-run any time; also run after a rebuild to sweep new logs.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    Write-Host "Game folder not found."; Read-Host "Enter"; exit 1
}

$tools = Join-Path $root 'tools'
$diag  = Join-Path $root 'diagnostics'
$attic = Join-Path $root '_attic\transfer'
$dumps = Join-Path $root 'dumps'
foreach ($d in @($tools, $diag, $dumps, $attic)) { [void](New-Item -ItemType Directory -Force -Path $d) }

$moved = 0
function Move-Into([string]$pattern, [string]$dest) {
    $script:n = 0
    Get-ChildItem -Path $root -Filter $pattern -File -ErrorAction SilentlyContinue | ForEach-Object {
        Move-Item -Force -Path $_.FullName -Destination $dest
        $script:n++
    }
    $script:n
}

# 1. Tool scripts -> tools\  (launchers stay at root)
$toolScripts = @(
    'play_gt2.ps1','compile_cache.ps1','build_pgxp.ps1','pgxp_tune.ps1',
    'toggle_native.ps1','retail_test_build.ps1','run_logged.ps1',
    'dump_vram.ps1','dump_ram.ps1','scan_xbank.ps1','organize_game_folder.ps1',
    'tidy_game_folder.ps1',
    'diag_full.ps1','diag_perf.ps1','diag_hang.ps1','diag_race.ps1',
    'diag_text.ps1','diag_cd.ps1','diag_boot.ps1','diag_fn.ps1',
    'diag_arcade.ps1','diag_arcade2.ps1','diag_arcade3.ps1','diag_arcade4.ps1',
    'diag_arcade5.ps1','diag_arcade6.ps1','diag_coverage.ps1','export_disc_chunks.ps1','diag_fmv.ps1'
)
foreach ($s in $toolScripts) {
    $p = Join-Path $root $s
    if ((Test-Path $p) -and ($p -ne $MyInvocation.MyCommand.Path)) {
        Move-Item -Force -Path $p -Destination $tools
        $moved++
    }
}

# 2. Diagnostic outputs -> diagnostics\
foreach ($pat in @('gt2_text_*.txt','gt2_text_*.png','gt2_cd_*.txt',
                   'gt2_boot_profile*.txt','gt2_fn_boot.jsonl','gt2_hang_*.txt',
                   'gt2_race_*.txt','gt2_arcade_probe*.txt','gt2_out.txt','gt2_err.txt',
                   'gt2_scan*.txt','psx_last_run_report.json',
                   'psx_freeze_heartbeat.json')) {
    $moved += (Move-Into $pat $diag)
}

# 2b. Large binary captures -> dumps\  (also sweeps any already filed under
#     diagnostics\ by earlier layouts)
foreach ($pat in @('gt2_ram_*.hex','gt2_vram*.hex','gt2_vram*.png','psx_freeze_dump_*.json')) {
    $moved += (Move-Into $pat $dumps)
    Get-ChildItem -Path $diag -Filter $pat -File -ErrorAction SilentlyContinue | ForEach-Object {
        Move-Item -Force -Path $_.FullName -Destination $dumps; $moved++
    }
}

# 3. One-off transfer files -> _attic\transfer\
foreach ($pat in @('gt2_slice_*.bin','gt2exe.zip','extract_slices*.ps1','pack_exe.ps1',
                   'retail_run_logged.ps1')) {
    $moved += (Move-Into $pat $attic)
}

Write-Host ("Organized: {0} files moved." -f $moved)
Write-Host "  tools\        - helper and diagnostic scripts"
Write-Host "  diagnostics\  - text captures and logs"
Write-Host "  dumps\        - RAM/VRAM dumps and freeze dumps"
Write-Host "  _attic\transfer\ - one-off transfer files (safe to delete)"
Write-Host ""
Write-Host "Root keeps the exe, 'Play GT2.cmd', setup_and_build.ps1, disc, and configs."
Write-Host "Note: with the diagnostics-dirs framework patch (2026-08-28) and the"
Write-Host "game.toml settings, new crash reports/heartbeats/freeze dumps go to"
Write-Host "diagnostics\ and dumps\ directly - this sweep is for older files."
Read-Host "Press Enter to exit"
