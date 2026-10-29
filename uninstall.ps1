# Deletes the mod files (and those of the Season 2-only 1.x release) from the game's Archives
# folder, restoring stock behaviour.
param([string]$GameDir)
$ErrorActionPreference = "Stop"
# tools\common.ps1 in a source checkout, next to this script in a release zip
$common = Join-Path $PSScriptRoot "tools\common.ps1"
if (-not (Test-Path $common)) { $common = Join-Path $PSScriptRoot "common.ps1" }
. $common

$archives = Join-Path (Resolve-GameDir $GameDir) "Archives"
foreach ($f in $ModFiles + $LegacyFiles + @($ModInfo)) {
    $p = Join-Path $archives $f
    if (Test-Path $p) { Remove-Item $p -Force; Write-Host "removed $f" }
}
Write-Host "Uninstalled."
