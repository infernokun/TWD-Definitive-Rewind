local set = {}
set.name = "Mod_TWDRewind_S2"
set.setName = "Mod_TWDRewind_S2"
set.descriptionFilenameOverride = "_resdesc_50_Mod_TWDRewind_S2.lua"
set.logicalName = "<Mod_TWDRewind_S2>"
set.logicalDestination = "<MenuSeason2>"
set.priority = 700
set.localDir = _currentDirectory
set.enableMode = "constant"
set.version = "patch"
set.descriptionPriority = 0
set.gameDataName = "Mod_TWDRewind_S2 Game Data"
set.gameDataPriority = 0
set.gameDataEnableMode = "constant"
set.localDirIncludeBase = true
set.localDirRecurse = false
set.localDirIncludeOnly =
{
    "AllPlatforms/MenuSeason2/",
    "HighEnd/MenuSeason2/",
    "PC/MenuSeason2/"
}
set.localDirExclude =
{
    "AllPlatforms/Builds/",
    "AllPlatforms/Languages/",
    "AllPlatforms/Platforms/"
}
set.gameDataArchives =
{
    _currentDirectory .. "WDC_pc_Mod_TWDRewind_S2_data.ttarch2"
}
RegisterSetDescription(set)
