# Deletes the mod files (and those of the Season 2-only 1.x release) from the game's Archives
# folder, restoring stock behaviour.
param([string]$GameDir)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "tools\common.ps1")

$archives = Join-Path (Resolve-GameDir $GameDir) "Archives"
foreach ($f in $ModFiles + $LegacyFiles + @($ModInfo)) {
    $p = Join-Path $archives $f
    if (Test-Path $p) { Remove-Item $p -Force; Write-Host "removed $f" }
}
Write-Host "Uninstalled."
