local set = {}
set.name = "Mod_TWDRewind"
set.setName = "Mod_TWDRewind"
set.descriptionFilenameOverride = "_resdesc_50_Mod_TWDRewind.lua"
set.logicalName = "<Mod_TWDRewind>"
set.logicalDestination = "<Project>"
set.priority = 700
set.localDir = _currentDirectory
set.enableMode = "constant"
set.version = "patch"
set.descriptionPriority = 0
set.gameDataName = "Mod_TWDRewind Game Data"
set.gameDataPriority = 0
set.gameDataEnableMode = "constant"
set.localDirIncludeBase = true
set.localDirRecurse = false
set.localDirIncludeOnly =
{
    "AllPlatforms/Project/",
    "AllPlatforms/_Project/",
    "HighEnd/Project/",
    "HighEnd/_Project/",
    "PC/Project/",
    "PC/_Project/"
}
set.localDirExclude =
{
    "AllPlatforms/Builds/",
    "AllPlatforms/Languages/",
    "AllPlatforms/Platforms/"
}
set.gameDataArchives =
{
    _currentDirectory .. "WDC_pc_Mod_TWDRewind_data.ttarch2"
}
RegisterSetDescription(set)
