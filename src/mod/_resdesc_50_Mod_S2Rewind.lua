local set = {}
set.name = "Mod_S2Rewind"
set.setName = "Mod_S2Rewind"
set.descriptionFilenameOverride = "_resdesc_50_Mod_S2Rewind.lua"
set.logicalName = "<Mod_S2Rewind>"
set.logicalDestination = "<MenuSeason2>"
set.priority = 700
set.localDir = _currentDirectory
set.enableMode = "constant"
set.version = "patch"
set.descriptionPriority = 0
set.gameDataName = "Mod_S2Rewind Game Data"
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
    _currentDirectory .. "WDC_pc_Mod_S2Rewind_data.ttarch2"
}
RegisterSetDescription(set)
