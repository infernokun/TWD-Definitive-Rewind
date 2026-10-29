local set = {}
set.name = "Mod_TWDRewind_S4Game"
set.setName = "Mod_TWDRewind_S4Game"
set.descriptionFilenameOverride = "_resdesc_50_Mod_TWDRewind_S4Game.lua"
set.logicalName = "<Mod_TWDRewind_S4Game>"
set.logicalDestination = "<ProjectSeason4>"
set.priority = 700
set.localDir = _currentDirectory
set.enableMode = "constant"
set.version = "patch"
set.descriptionPriority = 0
set.gameDataName = "Mod_TWDRewind_S4Game Game Data"
set.gameDataPriority = 0
set.gameDataEnableMode = "constant"
set.localDirIncludeBase = true
set.localDirRecurse = false
set.localDirIncludeOnly =
{
    "AllPlatforms/ProjectSeason4/",
    "HighEnd/ProjectSeason4/",
    "PC/ProjectSeason4/"
}
set.localDirExclude =
{
    "AllPlatforms/Builds/",
    "AllPlatforms/Languages/",
    "AllPlatforms/Platforms/"
}
set.gameDataArchives =
{
    _currentDirectory .. "WDC_pc_Mod_TWDRewind_S4Game_data.ttarch2"
}
RegisterSetDescription(set)
