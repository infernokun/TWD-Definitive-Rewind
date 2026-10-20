# Deletes the two mod files from the game's Archives folder, restoring stock behaviour.
param([string]$GameDir)
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "tools\common.ps1")

$archives = Join-Path (Resolve-GameDir $GameDir) "Archives"
foreach ($f in $ModArchive, $ModResdesc) {
    $p = Join-Path $archives $f
    if (Test-Path $p) { Remove-Item $p -Force; Write-Host "removed $f" } else { Write-Host "not present: $f" }
}
Write-Host "Uninstalled."
