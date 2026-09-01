# Exports the game disc as 3 chunk files so Claude's cloud lab can receive the
# complete image (transfer caps prevent sending the ~1GB bin in one piece).
# Run from anywhere; finds the game folder like the other tools. No rebuild
# needed. Creates disc_chunk_0.bin .. disc_chunk_2.bin in the game folder;
# they are safe to delete once Claude confirms receipt.
$ErrorActionPreference = 'Stop'
$sdir = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = $sdir
if (-not (Test-Path (Join-Path $root 'Gran Turismo 2 Recompiled.exe'))) {
    $up = Split-Path -Parent $root
    if ($up -and (Test-Path (Join-Path $up 'Gran Turismo 2 Recompiled.exe'))) { $root = $up }
}
$bin = Get-ChildItem -Path $root -Filter '*.bin' -File | Where-Object { $_.Length -gt 500MB } | Select-Object -First 1
if (-not $bin) {
    # disc may live in a subfolder
    $bin = Get-ChildItem -Path $root -Recurse -Filter '*.bin' -File -ErrorAction SilentlyContinue |
           Where-Object { $_.Length -gt 500MB } | Select-Object -First 1
}
if (-not $bin) { Write-Host "No disc .bin (>500MB) found under $root"; Read-Host "Enter"; exit 1 }
Write-Host ("Disc: {0} ({1:N0} bytes)" -f $bin.FullName, $bin.Length)
$chunkSize = [int64][Math]::Ceiling($bin.Length / 3.0)
$in = [System.IO.File]::OpenRead($bin.FullName)
$buf = New-Object byte[] (8MB)
for ($i = 0; $i -lt 3; $i++) {
    $outPath = Join-Path $root ("disc_chunk_{0}.bin" -f $i)
    $out = [System.IO.File]::Create($outPath)
    $remaining = [Math]::Min($chunkSize, $bin.Length - $in.Position)
    while ($remaining -gt 0) {
        $n = $in.Read($buf, 0, [Math]::Min($buf.Length, $remaining))
        if ($n -le 0) { break }
        $out.Write($buf, 0, $n)
        $remaining -= $n
    }
    $out.Close()
    Write-Host ("Wrote {0} ({1:N0} bytes)" -f $outPath, (Get-Item $outPath).Length)
}
$in.Close()
Write-Host "Done. Tell Claude the chunks are ready."
Read-Host "Press Enter to exit"
