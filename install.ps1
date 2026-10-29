# Copies the six mod files into the game's Archives folder. Nothing in the game is modified.
# Also removes the files of the Season 2-only 1.x release if they are there.
# Usage:  .\install.ps1              (finds the game through Steam)
#         .\install.ps1 -GameDir "D:\Games\The Walking Dead The Telltale Definitive Series"
param([string]$GameDir)
$ErrorActionPreference = "Stop"
# tools\common.ps1 in a source checkout, next to this script in a release zip
$common = Join-Path $PSScriptRoot "tools\common.ps1"
if (-not (Test-Path $common)) { $common = Join-Path $PSScriptRoot "common.ps1" }
. $common

$game = Resolve-GameDir $GameDir
$archives = Join-Path $game "Archives"
# Release zips have the files next to this script; a source checkout has them in dist\
$from = if (Test-Path (Join-Path $PSScriptRoot $CoreArchive)) { $PSScriptRoot } else { Join-Path $PSScriptRoot "dist" }

foreach ($f in $ModFiles) {
    if (-not (Test-Path (Join-Path $from $f))) { throw "Missing $(Join-Path $from $f). Download a release zip or run build.ps1 first." }
}
foreach ($f in $LegacyFiles) {
    $p = Join-Path $archives $f
    if (Test-Path $p) { Remove-Item $p -Force; Write-Host "removed old $f" }
}
foreach ($f in $ModFiles) {
    Copy-Item (Join-Path $from $f) (Join-Path $archives $f) -Force
    Write-Host "copied $f"
}
Write-Host "Installed to $archives"
Write-Host "Season 2: pick an episode to see the chapter panels and REWIND."
Write-Host "Season 3: select an episode, open More Options, choose Rewind."
Write-Host "Season 4: select the episode and use Rewind (left face button) or Restart Episode."
