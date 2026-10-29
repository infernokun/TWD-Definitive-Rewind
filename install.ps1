# Copies the six mod files of a build (dist\) into the game's Archives folder, for testing a build
# from a source checkout. Nothing in the game is modified. Also removes the files of the Season 2-only
# 1.x release if they are there. (The release zip has no scripts: see readme.txt in it.)
# Usage:  .\install.ps1              (finds the game through Steam)
#         .\install.ps1 -GameDir "D:\Games\The Walking Dead The Telltale Definitive Series"
param([string]$GameDir)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "tools\common.ps1")

$game = Resolve-GameDir $GameDir
$archives = Join-Path $game "Archives"
$from = Join-Path $PSScriptRoot "dist"

foreach ($f in $ModFiles) {
    if (-not (Test-Path (Join-Path $from $f))) { throw "Missing $(Join-Path $from $f). Run build.ps1 first." }
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
