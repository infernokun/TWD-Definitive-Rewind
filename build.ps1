# Builds the mod from scratch:
#   1. Season 2: extracts the stock Menu_chapters.lua from your game install (it is not kept in
#      this repo) and patches it
#   2. Seasons 3/4: cuts the rewind pictures out of the game's own textures (src\pictures.json) and
#      compiles src\lua\*.lua plus the generated picture table with luac (Lua 5.2, the game's bytecode format)
#   3. packs both ttarch2 archives and encrypts both resource descriptors
#   4. verifies everything by extracting / decrypting it again
#   5. writes dist\ and the release zip (the six mod files, the launcher's info file and readme.txt)
#
# Needs: Python 3 with Pillow and numpy; ttarchext.exe 0.3.2 or newer (https://aluigi.altervista.org/papers.htm#ttarchext);
#        luac.exe from the Telltale Modding Group's Script Editor
#        (https://github.com/Telltale-Modding-Group/Telltale-Script-Editor, resources/luac.exe);
#        and the game installed through Steam (or pass -GameDir).
#
# Development tool, not part of the released mod: -CaptureTour adds the screenshot tour from
# tools\capture-tour (see its README) and builds a separately named variant (dist\...-capture.zip).
# On a new save, the Season 4 list's "Screenshot tour" row walks through all the episode's scenes
# (F7 next, F6 previous).
# -AutoTest (with -CaptureTour) runs that tour unattended: from the hub menu into Season 4, the tour
# slot, every episode in turn, a scene every -TourSeconds (default 8) seconds (dist\...-autotest.zip).
# -TourOnly "2:5,6;4:2,3" limits the tour to those episode:steps (to take scenes again).
param(
    [string]$GameDir,
    [switch]$CaptureTour,
    [switch]$AutoTest,
    [int]$TourSeconds = 8,
    [string]$TourOnly,
    [string]$Ttarchext = "$PSScriptRoot\tools\ttarchext.exe",
    [string]$Luac = "$PSScriptRoot\tools\luac.exe"
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
. (Join-Path $PSScriptRoot "tools\common.ps1")

if (-not (Test-Path $Ttarchext)) {
    $alt = "$env:USERPROFILE\Desktop\Programming\RE\ttarchext\ttarchext.exe"
    if (Test-Path $alt) { $Ttarchext = $alt } else { throw "ttarchext.exe not found. Put it in tools\ or pass -Ttarchext <path>." }
}
if (-not (Test-Path $Luac)) { throw "luac.exe not found. Put it in tools\ or pass -Luac <path>." }
$game = Resolve-GameDir $GameDir
$stock = Join-Path $game "Archives\WDC_pc_MenuSeason2_data.ttarch2"
if (-not (Test-Path $stock)) { throw "Stock archive not found: $stock" }

# Header of every script the game ships: Lua 5.2, little endian, 4-byte int/size_t/instruction,
# 4-byte float lua_Number. luac output that doesn't match would not load.
$LuaHeader = [byte[]](0x1B, 0x4C, 0x75, 0x61, 0x52, 0x00, 0x01, 0x04, 0x04, 0x04, 0x04, 0x00, 0x19, 0x93, 0x0D, 0x0A, 0x1A, 0x0A)
function Assert-LuaHeader([string]$path) {
    $b = [System.IO.File]::ReadAllBytes($path)
    for ($i = 0; $i -lt $LuaHeader.Length; $i++) {
        if ($b[$i] -ne $LuaHeader[$i]) { throw "$path does not have the game's Lua 5.2 bytecode header" }
    }
}

foreach ($d in "build\s2", "build\core", "build\s4game", "build\gen", "build\resdesc_in", "build\resdesc_out", "build\verify", "dist") {
    # Empty it rather than delete it: an Explorer window open on dist\ would otherwise stop the build.
    New-Item -ItemType Directory -Force $d | Out-Null
    Get-ChildItem $d -Force | Remove-Item -Recurse -Force
}
New-Item -ItemType Directory -Force "build\s2\original", "build\s2\archive", "build\core\archive", "build\s4game\archive",
    "build\verify\s2", "build\verify\core", "build\verify\s4game" | Out-Null

Write-Host "== 1. Season 2: extract and patch Menu_chapters.lua from $stock"
& $Ttarchext -o -f "Menu_chapters.lua" 67 $stock "$PSScriptRoot\build\s2\original" | Out-Null
if (-not (Test-Path "build\s2\original\Menu_chapters.lua")) { throw "extraction failed" }
python -I tools\patch_menu_chapters.py build\s2\original\Menu_chapters.lua build\s2\archive\Menu_chapters.lua
if ($LASTEXITCODE -ne 0) { throw "patch failed" }

Write-Host "== 2a. Seasons 3/4: rewind pictures"
python -I tools\make_pictures.py src\pictures.json src\lua\TWDRewindScenes.lua $Ttarchext (Join-Path $game "Archives") `
    build\gen\extracted build\core\archive build\gen\TWDRewindPictures.lua
if ($LASTEXITCODE -ne 0) { throw "make_pictures failed" }
if ($CaptureTour) {
    Write-Host "   capture build: adding the Season 4 screenshot tour (tools\capture-tour)"
    $fields = if ($AutoTest) { "seconds = $TourSeconds, auto = true" } else { "seconds = 0" }
    # Each build is its own run: the auto-test starts over instead of carrying on after the last one.
    $fields += ', run = "' + (Get-Date).ToString("yyyyMMddHHmmss") + '"'
    if ($TourOnly) {
        $eps = foreach ($part in $TourOnly -split ';') {
            if ($part -notmatch '^\s*(\d+)\s*:\s*(\d+(\s*,\s*\d+)*)\s*$') { throw "-TourOnly: can't read '$part' (expected episode:step,step;...)" }
            "[{0}] = {{ {1} }}" -f $Matches[1], (($Matches[2] -split ',' | ForEach-Object { [int]$_ }) -join ", ")
        }
        $fields += ", only = { " + ($eps -join ", ") + " }"
        Write-Host "   tour limited to $TourOnly"
    }
    Set-Content -Path build\gen\TWDRewindTourConfig.lua -Encoding ascii -Value @(
        "-- Generated by build.ps1 -CaptureTour: settings of the screenshot tour (tools\capture-tour).",
        "-- seconds = 0: F7 moves to the next scene, F6 back to the previous one (no timer).",
        "-- auto: the tour runs unattended (build.ps1 -AutoTest). only: the episode steps it visits (-TourOnly).",
        "TWDRewindTour = { $fields }")
}

Write-Host "== 2b. Seasons 3/4: compile src\lua and the picture table"
# Compile from inside each folder so the bytecode records "TWDRewind.lua", not a full local path.
$luaDirs = @("$PSScriptRoot\src\lua", "$PSScriptRoot\build\gen")
if ($CaptureTour) { $luaDirs += "$PSScriptRoot\tools\capture-tour\lua" }
foreach ($dir in $luaDirs) {
    Push-Location $dir
    try {
        foreach ($f in Get-ChildItem -Filter *.lua) {
            & $Luac -o "$PSScriptRoot\build\core\archive\$($f.Name)" $f.Name
            if ($LASTEXITCODE -ne 0) { throw "luac failed on $($f.Name)" }
            Assert-LuaHeader "$PSScriptRoot\build\core\archive\$($f.Name)"
            Write-Host "   compiled $($f.Name)"
        }
    } finally { Pop-Location }
}

Write-Host "== 2c. Season 4 episodes: GameOverrides.lua wrapper and the stock one it runs"
# The stock file is not kept in this repo: extracted from the game, shipped under another name.
$s4project = Join-Path $game "Archives\WDC_pc_ProjectSeason4_data.ttarch2"
& $Ttarchext -o -f "GameOverrides.lua" 67 $s4project "$PSScriptRoot\build\s4game" | Out-Null
if (-not (Test-Path "build\s4game\GameOverrides.lua")) { throw "extraction of the Season 4 GameOverrides.lua failed" }
Assert-LuaHeader "$PSScriptRoot\build\s4game\GameOverrides.lua"
Move-Item "build\s4game\GameOverrides.lua" "build\s4game\archive\TWDRewind_S4_GameOverrides.lua" -Force
Push-Location "$PSScriptRoot\src\lua_s4game"
try {
    & $Luac -o "$PSScriptRoot\build\s4game\archive\GameOverrides.lua" GameOverrides.lua
    if ($LASTEXITCODE -ne 0) { throw "luac failed on the GameOverrides.lua wrapper" }
    Assert-LuaHeader "$PSScriptRoot\build\s4game\archive\GameOverrides.lua"
} finally { Pop-Location }
Write-Host "   GameOverrides.lua wrapper + TWDRewind_S4_GameOverrides.lua"

Write-Host "== 3a. pack ttarch2 archives"
& $Ttarchext -b 67 "$PSScriptRoot\dist\$S2Archive" "$PSScriptRoot\build\s2\archive" | Out-Null
& $Ttarchext -b 67 "$PSScriptRoot\dist\$CoreArchive" "$PSScriptRoot\build\core\archive" | Out-Null
& $Ttarchext -b 67 "$PSScriptRoot\dist\$S4GameArchive" "$PSScriptRoot\build\s4game\archive" | Out-Null
foreach ($a in $S2Archive, $CoreArchive, $S4GameArchive) { if (-not (Test-Path "dist\$a")) { throw "ttarch2 build failed: $a" } }

Write-Host "== 3b. encrypt resource descriptors"
$hdr = [byte[]](0x1B, 0x4C, 0x45, 0x6F)   # "\x1bLEo" marker the engine expects on encrypted scripts
foreach ($r in $S2Resdesc, $CoreResdesc, $S4GameResdesc) {
    $body = [System.IO.File]::ReadAllBytes("$PSScriptRoot\src\resdesc\$r")
    [System.IO.File]::WriteAllBytes("$PSScriptRoot\build\resdesc_in\$r", $hdr + $body)
    & $Ttarchext -o -V 7 -e 4 67 "$PSScriptRoot\build\resdesc_in\$r" "$PSScriptRoot\build\resdesc_out" | Out-Null
    Copy-Item "build\resdesc_out\$r" "dist\$r" -Force
}

Write-Host "== 4. verify"
& $Ttarchext -o 67 "$PSScriptRoot\dist\$S2Archive" "$PSScriptRoot\build\verify\s2" | Out-Null
& $Ttarchext -o 67 "$PSScriptRoot\dist\$CoreArchive" "$PSScriptRoot\build\verify\core" | Out-Null
& $Ttarchext -o 67 "$PSScriptRoot\dist\$S4GameArchive" "$PSScriptRoot\build\verify\s4game" | Out-Null
foreach ($pair in @(@("build\s2\archive", "build\verify\s2"), @("build\core\archive", "build\verify\core"), @("build\s4game\archive", "build\verify\s4game"))) {
    foreach ($f in Get-ChildItem $pair[0]) {
        $v = Join-Path $pair[1] $f.Name
        if (-not (Test-Path $v)) { throw "missing from archive: $($f.Name)" }
        if ((Get-FileHash $v).Hash -ne (Get-FileHash $f.FullName).Hash) { throw "archive round-trip mismatch: $($f.Name)" }
    }
}
foreach ($r in $S2Resdesc, $CoreResdesc, $S4GameResdesc) {
    & $Ttarchext -o -V 7 67 "$PSScriptRoot\dist\$r" "$PSScriptRoot\build\verify" | Out-Null
    if ((Get-FileHash "build\verify\$r").Hash -ne (Get-FileHash "src\resdesc\$r").Hash) { throw "resdesc round-trip mismatch: $r" }
}
Write-Host "   archives and descriptors round-trip OK"

Write-Host "== 5. package"
$ver = (Get-Content "src\$ModInfo" | ConvertFrom-Json).ModVersion
$zip = if ($AutoTest) { "dist\TWD-Definitive-Rewind-v$ver-autotest.zip" }
       elseif ($CaptureTour) { "dist\TWD-Definitive-Rewind-v$ver-capture.zip" }
       else { "dist\TWD-Definitive-Rewind-v$ver.zip" }
$modInfoPath = "src\$ModInfo"
if ($CaptureTour) {
    # Its own name in the launcher, so it can't be mistaken for the normal build.
    $info = Get-Content "src\$ModInfo" -Raw | ConvertFrom-Json
    $info.ModDisplayName = "Chapter Rewind - SCREENSHOT TOUR (capture build)"
    New-Item -ItemType Directory -Force build\capture | Out-Null
    $modInfoPath = "build\capture\$ModInfo"
    $info | ConvertTo-Json | Set-Content -Path $modInfoPath -Encoding utf8
}
# The release holds the mod files, the launcher's info file and readme.txt (install steps), nothing else.
New-Item -ItemType Directory -Force build\package | Out-Null
(Get-Content src\readme.txt -Raw).Replace("@VERSION@", $ver) | Set-Content -Path build\package\readme.txt -Encoding ascii -NoNewline
$files = @($ModFiles | ForEach-Object { "dist\$_" }) + @($modInfoPath, "build\package\readme.txt")
Compress-Archive -Path $files -DestinationPath $zip
Get-ChildItem dist -File | ForEach-Object { "{0,-50} {1,10}  {2}" -f $_.Name, $_.Length, (Get-FileHash $_.FullName).Hash } | Tee-Object -FilePath dist\SHA256SUMS.txt
