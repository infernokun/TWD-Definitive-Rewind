# Builds the mod from scratch:
#   1. extracts the stock Menu_chapters.lua from your game install (it is not kept in this repo)
#   2. patches it
#   3. packs it into a ttarch2 and encrypts the resource descriptor
#   4. verifies both by extracting / decrypting them again
#   5. writes dist\ and the release zip
#
# Needs: Python 3, ttarchext.exe 0.3.2 or newer (https://aluigi.altervista.org/papers.htm#ttarchext),
#        and the game installed through Steam (or pass -GameDir).
param(
    [string]$GameDir,
    [string]$Ttarchext = "$PSScriptRoot\tools\ttarchext.exe"
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
. (Join-Path $PSScriptRoot "tools\common.ps1")

if (-not (Test-Path $Ttarchext)) {
    $alt = "$env:USERPROFILE\Desktop\Programming\RE\ttarchext\ttarchext.exe"
    if (Test-Path $alt) { $Ttarchext = $alt } else { throw "ttarchext.exe not found. Put it in tools\ or pass -Ttarchext <path>." }
}
$game = Resolve-GameDir $GameDir
$stock = Join-Path $game "Archives\WDC_pc_MenuSeason2_data.ttarch2"
if (-not (Test-Path $stock)) { throw "Stock archive not found: $stock" }

foreach ($d in "build\original", "build\patched", "build\resdesc_in", "build\resdesc_out", "build\verify", "dist") {
    if (Test-Path $d) { Remove-Item $d -Recurse -Force }
    New-Item -ItemType Directory -Force $d | Out-Null
}

Write-Host "== 1. extract stock Menu_chapters.lua from $stock"
& $Ttarchext -o -f "Menu_chapters.lua" 67 $stock "$PSScriptRoot\build\original" | Out-Null
if (-not (Test-Path "build\original\Menu_chapters.lua")) { throw "extraction failed" }

Write-Host "== 2. patch"
python -I tools\patch_menu_chapters.py build\original\Menu_chapters.lua build\patched\Menu_chapters.lua
if ($LASTEXITCODE -ne 0) { throw "patch failed" }

Write-Host "== 3a. pack ttarch2"
& $Ttarchext -b 67 "$PSScriptRoot\dist\$ModArchive" "$PSScriptRoot\build\patched" | Out-Null
if (-not (Test-Path "dist\$ModArchive")) { throw "ttarch2 build failed" }

Write-Host "== 3b. encrypt resource descriptor"
$hdr = [byte[]](0x1B, 0x4C, 0x45, 0x6F)   # "\x1bLEo" marker the engine expects on encrypted scripts
$body = [System.IO.File]::ReadAllBytes("$PSScriptRoot\src\mod\$ModResdesc")
[System.IO.File]::WriteAllBytes("$PSScriptRoot\build\resdesc_in\$ModResdesc", $hdr + $body)
& $Ttarchext -o -V 7 -e 4 67 "$PSScriptRoot\build\resdesc_in\$ModResdesc" "$PSScriptRoot\build\resdesc_out" | Out-Null
Copy-Item "build\resdesc_out\$ModResdesc" "dist\$ModResdesc" -Force

Write-Host "== 4. verify"
& $Ttarchext -o 67 "$PSScriptRoot\dist\$ModArchive" "$PSScriptRoot\build\verify" | Out-Null
if ((Get-FileHash "build\verify\Menu_chapters.lua").Hash -ne (Get-FileHash "build\patched\Menu_chapters.lua").Hash) { throw "archive round-trip mismatch" }
& $Ttarchext -o -V 7 67 "$PSScriptRoot\dist\$ModResdesc" "$PSScriptRoot\build\verify" | Out-Null
if ((Get-FileHash "build\verify\$ModResdesc").Hash -ne (Get-FileHash "src\mod\$ModResdesc").Hash) { throw "resdesc round-trip mismatch" }
Write-Host "   archive and descriptor round-trip OK"

Write-Host "== 5. package"
$ver = (Get-Content "src\mod\$ModInfo" | ConvertFrom-Json).ModVersion
$zip = "dist\TWD-Definitive-Season2-Rewind-v$ver.zip"
Compress-Archive -Path "dist\$ModArchive", "dist\$ModResdesc", "src\mod\$ModInfo", "install.ps1", "uninstall.ps1", "tools\common.ps1", "README.md", "LICENSE" -DestinationPath $zip
Get-ChildItem dist | ForEach-Object { "{0,-50} {1,10}  {2}" -f $_.Name, $_.Length, (Get-FileHash $_.FullName).Hash } | Tee-Object -FilePath dist\SHA256SUMS.txt
