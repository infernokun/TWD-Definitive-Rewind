# Copies the two mod files into the game's Archives folder. Nothing in the game is modified.
# Usage:  .\install.ps1              (finds the game through Steam)
#         .\install.ps1 -GameDir "D:\Games\The Walking Dead The Telltale Definitive Series"
param([string]$GameDir)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "tools\common.ps1")

$game = Resolve-GameDir $GameDir
$archives = Join-Path $game "Archives"
# Release zips have the files next to this script; a source checkout has them in dist\
$from = if (Test-Path (Join-Path $PSScriptRoot $ModArchive)) { $PSScriptRoot } else { Join-Path $PSScriptRoot "dist" }

foreach ($f in $ModArchive, $ModResdesc) {
    $src = Join-Path $from $f
    if (-not (Test-Path $src)) { throw "Missing $src. Download a release zip or run build.ps1 first." }
    Copy-Item $src (Join-Path $archives $f) -Force
    Write-Host "copied $f"
}
Write-Host "Installed to $archives"
Write-Host "Start the game, open Season 2 and pick an episode. The chapter panels and the REWIND option are back."
