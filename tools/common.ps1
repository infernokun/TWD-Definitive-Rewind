# Shared helpers for build.ps1 / install.ps1 / uninstall.ps1

# Season 2: patched stock Menu_chapters.lua, mounted into <MenuSeason2>
$S2Archive = "WDC_pc_Mod_TWDRewind_S2_data.ttarch2"
$S2Resdesc = "_resdesc_50_Mod_TWDRewind_S2.lua"
# Seasons 3 and 4: the scripts and the rewind pictures, mounted into <Project>
$CoreArchive = "WDC_pc_Mod_TWDRewind_data.ttarch2"
$CoreResdesc = "_resdesc_50_Mod_TWDRewind.lua"
# Season 4 episodes: GameOverrides.lua that runs the stock one and loads the mod, mounted into <ProjectSeason4>
$S4GameArchive = "WDC_pc_Mod_TWDRewind_S4Game_data.ttarch2"
$S4GameResdesc = "_resdesc_50_Mod_TWDRewind_S4Game.lua"
$ModInfo = "modinfo_twd_rewind.json"
$ModFiles = @($S2Archive, $S2Resdesc, $CoreArchive, $CoreResdesc, $S4GameArchive, $S4GameResdesc)
# Files of earlier releases, removed on install so they don't linger: the Season 2-only 1.x set, and
# the Season 4 menu set of 2.0 test builds (Season 3's More Options window for Season 4)
$LegacyFiles = @("WDC_pc_Mod_S2Rewind_data.ttarch2", "_resdesc_50_Mod_S2Rewind.lua", "modinfo_season2_rewind.json",
    "WDC_pc_Mod_TWDRewind_S4_data.ttarch2", "_resdesc_50_Mod_TWDRewind_S4.lua")
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
            foreach ($x in $m.Matches) { $libs += ($x.Groups[1].Value -replace '\\\\', '\') }
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
