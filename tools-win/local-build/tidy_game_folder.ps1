# GT2Recomp - tidy the game folder so there is ONE thing to launch.
#
# After a few releases a game folder collects the single-build layout from
# before 0.2 (game.toml, cache\, overlay_captures.json ... at the root, now
# dead: every disc build lives under titles\<name>\), test installs made in
# a subfolder, disc-transfer chunks, freeze dumps, and developer files. None
# of it is used by the game any more, and a second "Gran Turismo 2
# Recompiled.exe" in a subfolder makes it easy to launch the wrong build.
#
# This moves (never deletes):
#   _old\pre-0.2 install\   the root-level single-build leftovers
#   _old\<subfolder>\        any subfolder that is itself a whole GT2 install
#   _old\lab transfer\       disc chunk files made for the cloud lab
#   _old\freeze dumps\       titles\*\dumps\psx_freeze_dump_*.json (all of them)
#   release\                 GitHub release tooling (push_update.cmd & co.)
# and leaves at the root: "Gran Turismo 2 Recompiled.exe" (the one exe to
# start), Setup / Play / Diagnose / Benchmark GT2.cmd, README.txt, your discs,
# settings, saves\, mods\, titles\, tools\, overlay_toolchain\, and
# gt2recomp.bundle + GT2Recomp-src\ (what "Setup GT2.cmd" builds from).
# Everything under _old\ can be deleted once you are happy.
#
# Safe to re-run any time. Run it with the game closed.
param([switch]$NoPause, [switch]$NoRebuildPrompt)
$ErrorActionPreference = 'Continue'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
$frontDoor = 'Gran Turismo 2 Recompiled.exe'
if (-not (Test-Path -LiteralPath (Join-Path $root $frontDoor))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path -LiteralPath (Join-Path $up $frontDoor))) { $root = $up }
}
if (-not (Test-Path -LiteralPath (Join-Path $root $frontDoor))) {
    Write-Host "Game folder not found (no '$frontDoor' here or one level up)."
    if (-not $NoPause) { Read-Host "Enter to exit" }; exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $root 'titles'))) {
    Write-Host "This folder has no titles\ - it is a pre-0.2 single-build install."
    Write-Host "Run 'Setup GT2.cmd' first; it converts the install, then run this."
    if (-not $NoPause) { Read-Host "Enter to exit" }; exit 1
}
$running = Get-Process -ErrorAction SilentlyContinue |
           Where-Object { $_.ProcessName -like 'GT2 *' -or $_.ProcessName -eq 'Gran Turismo 2 Recompiled' }
if ($running) {
    Write-Host "The game is running - close it first."
    if (-not $NoPause) { Read-Host "Enter to exit" }; exit 1
}

$old     = Join-Path $root '_old'
$release = Join-Path $root 'release'
$script:moved = 0
$script:log = @()

function Ensure-Dir([string]$p) { if (-not (Test-Path -LiteralPath $p)) { [void](New-Item -ItemType Directory -Force -Path $p) } }
function Free-Name([string]$dest) {
    # never overwrite: if <dest> exists, use <dest> (2), (3) ...
    if (-not (Test-Path -LiteralPath $dest)) { return $dest }
    $dir = Split-Path -Parent $dest; $leaf = Split-Path -Leaf $dest
    $base = [IO.Path]::GetFileNameWithoutExtension($leaf); $ext = [IO.Path]::GetExtension($leaf)
    $i = 2
    while ($true) {
        $cand = Join-Path $dir ("{0} ({1}){2}" -f $base, $i, $ext)
        if (-not (Test-Path -LiteralPath $cand)) { return $cand }
        $i++
    }
}
function Move-Into([string]$path, [string]$destDir, [string]$why) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    Ensure-Dir $destDir
    $dest = Free-Name (Join-Path $destDir (Split-Path -Leaf $path))
    try {
        Move-Item -LiteralPath $path -Destination $dest -Force
        $script:moved++
        $script:log += ("  {0}  ->  {1}   ({2})" -f (Resolve-RelPath $path), (Resolve-RelPath $dest), $why)
    } catch {
        $script:log += ("  !! could not move {0}: {1}" -f $path, $_.Exception.Message)
    }
}
function Resolve-RelPath([string]$p) {
    if ($p.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $p.Substring($root.Length).TrimStart('\', '/') }
    return $p
}

Write-Host "Tidying: $root"
Write-Host ""

# 1. Root-level leftovers of the pre-0.2 single-build layout. Each disc build
#    keeps its own copy of all of these under titles\<name>\ now.
$pre02 = Join-Path $old 'pre-0.2 install'
$biosDir = Join-Path $root 'bios'
if (Test-Path -LiteralPath $biosDir) {
    # A retail BIOS dump is an input to setup - keep it at the root.
    Get-ChildItem -LiteralPath $biosDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^scph\d+\.bin$' } |
        ForEach-Object {
            $target = Join-Path $root $_.Name
            if (-not (Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $_.FullName -Destination $target }
        }
}
foreach ($leaf in @('game.toml', 'cache', 'compile_cache.txt', 'cache_finisher.lock',
                    'overlay_captures.json', 'overlay_captures.json.d', 'extracted', 'seeds',
                    'dumps', 'assets', 'bios', 'bios.cfg', 'disc.cfg', 'diagnostics',
                    'extract_gt2_exe.ps1', 'patches', 'patches.pre-shared')) {
    Move-Into (Join-Path $root $leaf) $pre02 'pre-0.2 layout, unused'
}
# Loose runtime output at the root from that layout.
foreach ($pat in @('psx_freeze_dump_*.json', 'psx_freeze_heartbeat.json', 'psx_last_run_report.json',
                   'gt2_out.txt', 'gt2_err.txt', 'gt2_ram_*.hex', 'gt2_vram*.hex', 'gt2_vram*.png')) {
    Get-ChildItem -LiteralPath $root -Filter $pat -File -ErrorAction SilentlyContinue |
        ForEach-Object { Move-Into $_.FullName $pre02 'old diagnostic output' }
}

# 2. Whole second installs in subfolders (a test build, an older copy): any
#    subfolder that has its own front-door exe. Those are the ones that get
#    launched by mistake.
Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notin @('_old', 'release', 'titles', 'tools', 'mods', 'saves', 'overlay_toolchain', 'GT2Recomp-src') } |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $frontDoor) } |
    ForEach-Object { Move-Into $_.FullName $old 'a second complete install' }

# 3. Disc chunks made for the cloud lab (send_discs_to_lab.ps1) - done their job.
$lab = Join-Path $old 'lab transfer'
Move-Into (Join-Path $root 'lab_transfer') $lab 'disc chunks for the lab'
Move-Into (Join-Path $root 'send_discs_to_lab.ps1') $lab 'disc chunks for the lab'
Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'gt2_slice_*.bin' -or $_.Name -like 'disc_chunk*' } |
    ForEach-Object { Move-Into $_.FullName $lab 'disc chunks for the lab' }

# 4. Freeze dumps under every disc build (40-110 MB each, written when the
#    runtime's watchdog trips; only useful while that freeze is being debugged).
$titlesDir = Join-Path $root 'titles'
Get-ChildItem -LiteralPath $titlesDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $t = $_.Name
    $dd = Join-Path $_.FullName 'dumps'
    if (Test-Path -LiteralPath $dd) {
        Get-ChildItem -LiteralPath $dd -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like 'psx_freeze_dump_*.json' -or $_.Name -like 'gt2_ram_*.hex' -or $_.Name -like 'gt2_vram*' } |
            ForEach-Object { Move-Into $_.FullName (Join-Path (Join-Path $old 'freeze dumps') $t) 'freeze dump' }
    }
}

# 5. Developer / release files -> release\ (the scripts there expect
#    gt2recomp.bundle one level up, at the game root, where Setup also reads it).
foreach ($leaf in @('GT2Recomp-public', 'github_main.bundle', 'GT2Recomp-setup.zip')) {
    Move-Into (Join-Path $root $leaf) $release 'release tooling'
}
Get-ChildItem -LiteralPath $root -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like 'RELEASE_NOTES*' } |
    ForEach-Object { Move-Into $_.FullName $release 'release tooling' }
foreach ($leaf in @('push_update.cmd', 'fix_release_tag.cmd')) {
    $p = Join-Path $root $leaf
    if (Test-Path -LiteralPath $p) {
        if (Test-Path -LiteralPath (Join-Path $release $leaf)) {
            # release\ already carries the version that knows the new layout
            Move-Into $p (Join-Path $old 'superseded scripts') ("replaced by release\{0}" -f $leaf)
        } else {
            Move-Into $p $release 'release tooling'
        }
    }
}

# 6. Helper scripts that belong in tools\ (older setups left copies at the root).
$tools = Join-Path $root 'tools'
foreach ($leaf in @('play_gt2.ps1', 'compile_cache.ps1', 'run_logged.ps1', 'organize_game_folder.ps1',
                    'play_software.ps1', 'capture_screen.ps1', 'tidy_game_folder.ps1')) {
    $p = Join-Path $root $leaf
    if ((Test-Path -LiteralPath $p) -and ($p -ne $MyInvocation.MyCommand.Path)) {
        if (Test-Path -LiteralPath (Join-Path $tools $leaf)) { Move-Into $p (Join-Path $old 'superseded scripts') 'tools\ has it' }
        else { Move-Into $p $tools 'helper script' }
    }
}

if (Test-Path -LiteralPath $old) {
    @(
        'Everything in this folder was moved here by "Tidy GT2 folder.cmd" and is',
        'not used by the game any more. Delete the whole folder whenever you like.',
        '',
        '  pre-0.2 install\   the single-build layout from before 0.2 (each disc',
        '                     build now lives under titles\<name>\ in the game folder)',
        '  <subfolder>\       a complete second install that had its own',
        '                     "Gran Turismo 2 Recompiled.exe" - the game folder',
        '                     itself is the one to keep and rebuild',
        '  lab transfer\      disc chunk files made for the cloud lab',
        '  freeze dumps\      watchdog dumps from earlier sessions',
        '  superseded scripts\ older copies of helper scripts'
    ) | Set-Content -LiteralPath (Join-Path $old 'README.txt') -Encoding ASCII
}

Write-Host ("Moved {0} item(s):" -f $script:moved)
$script:log | ForEach-Object { Write-Host $_ }
Write-Host ""
Write-Host "The game folder now has ONE thing to start:"
Write-Host "    $frontDoor"
Write-Host "(it opens whichever disc you used last; 'Play GT2.cmd' does the same and"
Write-Host " tops up the native-code cache after you quit). The per-disc exes under"
Write-Host "titles\ are what it starts - no need to open those yourself."
Write-Host ""
$src = Join-Path $root 'GT2Recomp-src'
$bundle = Join-Path $root 'gt2recomp.bundle'
$exes = Get-ChildItem -LiteralPath $titlesDir -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Filter '*.exe' -File -ErrorAction SilentlyContinue }
if ($exes) {
    $newestExe = ($exes | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    Write-Host ("Installed build: {0}  (built {1:yyyy-MM-dd HH:mm})" -f $newestExe.Name, $newestExe.LastWriteTime)
    if ((Test-Path -LiteralPath $bundle) -and ((Get-Item -LiteralPath $bundle).LastWriteTime -gt $newestExe.LastWriteTime)) {
        Write-Host ("gt2recomp.bundle is NEWER ({0:yyyy-MM-dd HH:mm}) - the installed build is behind it." -f (Get-Item -LiteralPath $bundle).LastWriteTime)
        if (-not $NoRebuildPrompt) {
            $a = Read-Host "Rebuild now with 'Setup GT2.cmd'? (only the changed parts; a few minutes) [Y/n]"
            if ($a -eq '' -or $a -match '^[Yy]') {
                $setup = Join-Path $root 'Setup GT2.cmd'
                if (Test-Path -LiteralPath $setup) { Start-Process -FilePath $setup -WorkingDirectory $root; exit 0 }
                Write-Host "Setup GT2.cmd not found."
            }
        }
    }
}
if (-not $NoPause) { Read-Host "Enter to exit" }
