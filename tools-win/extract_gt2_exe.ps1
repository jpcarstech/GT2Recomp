# GT2 Recomp - boot EXE extractor
# Parses the ISO9660 filesystem inside a raw MODE2/2352 PS1 .bin image and
# extracts SYSTEM.CNF + the boot executable into an "extracted" subfolder.
# Usage: right-click -> "Run with PowerShell" (or: powershell -ExecutionPolicy Bypass -File .\extract_gt2_exe.ps1)
#        setup_and_build.ps1 calls it as: extract_gt2_exe.ps1 -Root <game folder> -NoPause
param([string]$Root = "", [switch]$NoPause)

$ErrorActionPreference = 'Stop'
$root = if ($Root -ne "") { $Root } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not (Get-ChildItem -Path $root -Filter *.bin -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 100MB })) {
    # running from the game folder's tools\ subfolder
    $up = Split-Path -Parent $root
    if ($up -and (Get-ChildItem -Path $up -Filter *.bin -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 100MB })) { $root = $up }
}
Set-Location $root

$bin = Get-ChildItem -Path $root -Filter *.bin | Where-Object { $_.Length -gt 100MB } | Select-Object -First 1
if (-not $bin) { Write-Host "ERROR: no large .bin disc image found in $root"; if (-not $NoPause) { Read-Host "Press Enter to exit" }; exit 1 }
Write-Host "Disc image: $($bin.Name) ($([math]::Round($bin.Length/1MB,1)) MB)"

$outDir = Join-Path $root "extracted"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$fs = [System.IO.File]::OpenRead($bin.FullName)
try {
    $SECTOR_RAW = 2352

    function Read-UserData([long]$lba) {
        # Returns the 2048-byte user-data payload of one raw sector.
        $raw = New-Object byte[] $SECTOR_RAW
        $null = $fs.Seek($lba * $SECTOR_RAW, 'Begin')
        $n = $fs.Read($raw, 0, $SECTOR_RAW)
        if ($n -lt $SECTOR_RAW) { throw "Short read at LBA $lba" }
        # Mode 2 (XA) Form 1: 12 sync + 4 header + 8 subheader -> data at 24
        # Mode 1: 12 sync + 4 header -> data at 16
        $mode = $raw[15]
        $off = if ($mode -eq 2) { 24 } else { 16 }
        $out = New-Object byte[] 2048
        [Array]::Copy($raw, $off, $out, 0, 2048)
        return ,$out
    }

    function Read-Extent([long]$lba, [long]$size) {
        $buf = New-Object byte[] $size
        $pos = 0
        $cur = $lba
        while ($pos -lt $size) {
            $chunk = Read-UserData $cur
            $take = [Math]::Min(2048, $size - $pos)
            [Array]::Copy($chunk, 0, $buf, $pos, $take)
            $pos += $take
            $cur += 1
        }
        return ,$buf
    }

    function Parse-Dir([long]$lba, [long]$size) {
        # Returns array of records: @{Name; Lba; Size; IsDir}
        $records = @()
        $data = Read-Extent $lba $size
        $i = 0
        while ($i -lt $data.Length) {
            $len = $data[$i]
            if ($len -eq 0) {
                # advance to next 2048-byte boundary
                $i = ([math]::Floor($i / 2048) + 1) * 2048
                continue
            }
            $nameLen = $data[$i + 32]
            $nameBytes = New-Object byte[] $nameLen
            [Array]::Copy($data, $i + 33, $nameBytes, 0, $nameLen)
            $name = [System.Text.Encoding]::ASCII.GetString($nameBytes)
            $extLba = [BitConverter]::ToUInt32($data, $i + 2)
            $extSize = [BitConverter]::ToUInt32($data, $i + 10)
            $flags = $data[$i + 25]
            if ($nameLen -gt 1 -or ($nameBytes.Length -ge 1 -and $nameBytes[0] -gt 1)) {
                $records += [pscustomobject]@{ Name = $name; Lba = $extLba; Size = $extSize; IsDir = (($flags -band 2) -ne 0) }
            }
            $i += $len
        }
        return ,$records
    }

    # --- Primary Volume Descriptor at LBA 16 ---
    $pvd = Read-UserData 16
    $id = [System.Text.Encoding]::ASCII.GetString($pvd, 1, 5)
    if ($id -ne 'CD001') { throw "PVD not found (got '$id') - is this a raw 2352-byte/sector image?" }
    $volId = ([System.Text.Encoding]::ASCII.GetString($pvd, 40, 32)).Trim()
    Write-Host "Volume ID: $volId"

    # Root directory record at offset 156 of PVD
    $rootLba = [BitConverter]::ToUInt32($pvd, 156 + 2)
    $rootSize = [BitConverter]::ToUInt32($pvd, 156 + 10)
    $rootEntries = Parse-Dir $rootLba $rootSize

    # Dump full root listing (recurse one level) for reference
    $listing = New-Object System.Collections.Generic.List[string]
    $listing.Add("Volume: $volId")
    $listing.Add("Image:  $($bin.Name)  size=$($bin.Length)")
    $listing.Add("")
    foreach ($e in $rootEntries) {
        $kind = if ($e.IsDir) { 'DIR ' } else { 'FILE' }
        $line = "{0} {1,-32} lba={2,-8} size={3}" -f $kind, $e.Name, $e.Lba, $e.Size
        $listing.Add($line)
        if ($e.IsDir -and $e.Name -notin @('.', '..')) {
            try {
                foreach ($s in (Parse-Dir $e.Lba $e.Size)) {
                    $kind2 = if ($s.IsDir) { 'DIR ' } else { 'FILE' }
                    $line2 = "    {0} {1,-28} lba={2,-8} size={3}" -f $kind2, $s.Name, $s.Lba, $s.Size
                    $listing.Add($line2)
                }
            } catch { $listing.Add("    (failed to read subdir: $_)") }
        }
    }
    $listing | Set-Content (Join-Path $outDir 'disc_listing.txt')

    # --- SYSTEM.CNF ---
    $cnfEntry = $rootEntries | Where-Object { $_.Name -match '^SYSTEM\.CNF' } | Select-Object -First 1
    if (-not $cnfEntry) { throw "SYSTEM.CNF not found in root directory - see extracted\disc_listing.txt" }
    $cnfBytes = Read-Extent $cnfEntry.Lba $cnfEntry.Size
    [System.IO.File]::WriteAllBytes((Join-Path $outDir 'SYSTEM.CNF'), $cnfBytes)
    $cnfText = [System.Text.Encoding]::ASCII.GetString($cnfBytes)
    Write-Host "SYSTEM.CNF:`n$cnfText"

    # BOOT = cdrom:\SCUS_944.55;1  (also handle cdrom0:, no leading slash, subdirs)
    if ($cnfText -match 'BOOT\s*=\s*cdrom0?:\\?([^;\r\n]+)') {
        $bootPath = $Matches[1].Trim()
    } else { throw "Could not parse BOOT line from SYSTEM.CNF" }
    Write-Host "Boot executable: $bootPath"

    # Resolve path (may contain backslash-separated subdirectory)
    $parts = $bootPath -split '\\'
    $entries = $rootEntries
    $target = $null
    for ($p = 0; $p -lt $parts.Count; $p++) {
        $seek = $parts[$p]
        $hit = $entries | Where-Object { ($_.Name -replace ';\d+$', '') -ieq $seek } | Select-Object -First 1
        if (-not $hit) { throw "Path component '$seek' not found on disc" }
        if ($p -eq $parts.Count - 1) { $target = $hit }
        elseif ($hit.IsDir) { $entries = Parse-Dir $hit.Lba $hit.Size }
        else { throw "'$seek' is not a directory" }
    }

    $exeName = ($target.Name -replace ';\d+$', '')
    $exeBytes = Read-Extent $target.Lba $target.Size
    $exeOut = Join-Path $outDir $exeName
    [System.IO.File]::WriteAllBytes($exeOut, $exeBytes)
    $magic = [System.Text.Encoding]::ASCII.GetString($exeBytes, 0, 8)
    Write-Host "Extracted $exeName ($($target.Size) bytes) magic='$magic'"
    if ($magic -ne 'PS-X EXE') { Write-Host "WARNING: expected 'PS-X EXE' magic; got '$magic'" }

    # Also copy the cue and hash the bin for identification
    Get-ChildItem -Path $root -Filter *.cue | ForEach-Object { Copy-Item $_.FullName $outDir -Force }
    Write-Host "Hashing disc image (this takes a moment)..."
    $md5 = (Get-FileHash -Algorithm MD5 -Path $bin.FullName).Hash
    "MD5($($bin.Name)) = $md5" | Set-Content (Join-Path $outDir 'disc_md5.txt')
    Write-Host "MD5: $md5"

    Write-Host ""
    Write-Host "DONE. Files written to: $outDir"
} finally {
    $fs.Close()
}
if (-not $NoPause) { Read-Host "Press Enter to exit" }
