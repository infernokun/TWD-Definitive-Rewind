# Shared helpers for build.ps1 / install.ps1 / uninstall.ps1

$ModArchive = "WDC_pc_Mod_S2Rewind_data.ttarch2"
$ModResdesc = "_resdesc_50_Mod_S2Rewind.lua"
$ModInfo = "modinfo_season2_rewind.json"
$GameFolderName = "The Walking Dead The Telltale Definitive Series"

function Find-GameDir {
    # Look through every Steam library for the game folder. Returns $null if not found.
    $roots = @()
    $hkcu = Get-ItemProperty "HKCU:\Software\Valve\Steam" -ErrorAction SilentlyContinue
    if ($hkcu -and $hkcu.SteamPath) { $roots += $hkcu.SteamPath }
    $hklm = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam" -ErrorAction SilentlyContinue
    if ($hklm -and $hklm.InstallPath) { $roots += $hklm.InstallPath }
    $libs = @()
    foreach ($r in $roots) {
        $libs += $r
        $vdf = Join-Path $r "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            $m = Select-String -Path $vdf -Pattern '"path"\s+"([^"]+)"' -AllMatches
            foreach ($x in $m.Matches) { $libs += ($x.Groups[1].Value -replace '\\', '\') }
        }
    }
    foreach ($l in ($libs | Select-Object -Unique)) {
        $g = Join-Path $l "steamapps\common\$GameFolderName"
        if (Test-Path (Join-Path $g "WDC.exe")) { return $g }
    }
    return $null
}

function Resolve-GameDir([string]$GameDir) {
    if ($GameDir) {
        if (-not (Test-Path (Join-Path $GameDir "WDC.exe"))) { throw "WDC.exe not found in '$GameDir'" }
        return $GameDir
    }
    $g = Find-GameDir
    if (-not $g) { throw "Could not find '$GameFolderName' in any Steam library. Pass -GameDir <path to the game folder>." }
    return $g
}
