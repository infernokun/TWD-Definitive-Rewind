# Season 2 Rewind for The Walking Dead: The Telltale Definitive Series

[![Latest release](https://img.shields.io/github/v/release/infernokun/TWD-Definitive-Season2-Rewind)](https://github.com/infernokun/TWD-Definitive-Season2-Rewind/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/infernokun/TWD-Definitive-Season2-Rewind/total)](https://github.com/infernokun/TWD-Definitive-Season2-Rewind/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

![Season 2 Chapter Rewind](docs/cover.webp)

Brings back chapter Rewind in Season 2. The Definitive Series shipped with it switched off, so the only option was to restart a whole episode. With this mod the episode menu lists every chapter you have reached again, and picking one lets you rewind or branch from that point, just like the original Season Two release.

- Two files, added next to the game's own archives.
- No stock game file is modified, and removing it takes seconds.
- Works on the Steam PC version.

**[Download the latest release](https://github.com/infernokun/TWD-Definitive-Season2-Rewind/releases/latest)**

## Install

### With the Telltale Mod Launcher (recommended)

Use [my fork of the Telltale Mod Launcher](https://github.com/infernokun/TelltaleModLauncher), version [0.7.0](https://github.com/infernokun/TelltaleModLauncher/releases/tag/v0.7.0) or newer. It runs on Windows and Linux and needs nothing else installed.

1. Download the mod's zip from [Releases](https://github.com/infernokun/TWD-Definitive-Season2-Rewind/releases/latest). Don't extract it.
2. Open the launcher, pick The Walking Dead: The Telltale Definitive Series, and drop the zip onto the window (or use Add mod).
3. Play.

The launcher installs only the two mod files, shows the mod's load priority, and lets you drag it above or below other mods. The original 0.6.5 launcher can also add the zip, but it copies every file in the zip into the game folder and has bugs that can lose installed mods, so the fork is the better choice.

### With the install script

1. Download the zip from [Releases](https://github.com/infernokun/TWD-Definitive-Season2-Rewind/releases/latest) and extract it anywhere.
2. Right-click `install.ps1` and choose Run with PowerShell. It finds the game through Steam and copies the two files into the game's `Archives` folder.

If the script can't find the game, pass the path:

```powershell
.\install.ps1 -GameDir "D:\SteamLibrary\steamapps\common\The Walking Dead The Telltale Definitive Series"
```

### By hand

Copy these two files into `...\The Walking Dead The Telltale Definitive Series\Archives\`:

```
WDC_pc_Mod_S2Rewind_data.ttarch2
_resdesc_50_Mod_S2Rewind.lua
```

## Uninstall

Remove it in the launcher, run `uninstall.ps1`, or delete the two files from the Archives folder. Steam's "verify integrity" won't remove them on its own because they are additions, not replacements.

## Things to know

- Rewinding deletes the saves after the chapter you rewind to. The original game worked the same way. To keep a finished playthrough, use Branch, or copy your save slot first (`Documents\Telltale Games\The Walking Dead Definitive`, files named `wd2_saveslot1*`).
- If another mod also replaces `Menu_chapters.lua`, the one with the higher priority wins. In the launcher, that's whichever is higher in the list.
- Tested on the Steam build dated 2020.01.29 (Season 108-RC). Other storefronts use the same archives but haven't been tried.

## Why

In the original Season Two you could open an episode, pick any chapter you had already played, and either rewind your save to that point or branch a new save from it. That is how most people replayed choices.

The Definitive Series reuses the Season Two menu almost unchanged, but a switch in the menu script stops the chapter list from being built, leaving only "Restart Episode". Seasons 1, 3, 4 and Michonne kept their rewind menus. Only Season 2 lost it, and nothing in the game files explains why.

I wanted it back, so I went through the scripts of both games, found the exact change, and reversed it. The full story is on [my site](https://infernokun.github.io/projects/twd-season-2-rewind/).

## What was changed

The Season 2 episode menu lives in `Menu_chapters.lua` inside `WDC_pc_MenuSeason2_data.ttarch2`. Compared with the original Season Two script, the Definitive Series version differs in three places:

| | Original Season Two | Definitive Series | This mod |
|---|---|---|---|
| Chapter list | built for every autosave | gated behind a new `Menu_Chapters_RewindIsSupported()` that always returns `false` | returns `true` |
| Picking a chapter | "Rewind" popup, then choose a save slot to copy into | "Restart Episode" popup | original popup and flow restored |
| Button label | `navhelp_rewind` ("REWIND") | `navhelp_restart` | `navhelp_rewind` |

Everything the feature depends on (the save-slot rewind code, `SaveLoad_Revert`, the menu text, the chapter thumbnails) is still in the Definitive Series, untouched. Only this one script needed patching, and the patch is three small edits to the compiled Lua bytecode.

## How it loads

At startup the engine reads every `_resdesc_50_*.lua` file in the Archives folder. Each one registers a resource set with a priority and a list of archives. When two sets contain a file with the same name, the higher priority wins. Telltale used this for their own PC patches (priority 400 over the stock 62). This mod registers a set at priority 700 that contains just the patched script.

So the game is never modified. It just finds a newer copy of one file first.

## Building from source

Requirements: Windows, Python 3, [ttarchext](https://aluigi.altervista.org/papers.htm#ttarchext) 0.3.2 or newer, and the game installed.

```powershell
.\build.ps1                      # put ttarchext.exe in tools\ or pass -Ttarchext <path>
```

The build extracts the stock `Menu_chapters.lua` from your game install (it is not in this repo), patches it, packs the archive, encrypts the descriptor, extracts both again to check they round-trip, and writes `dist\` with checksums.

Repository layout:

```
tools/luapatch52.py                    Lua 5.2 bytecode parser and writer, exact round-trip, 4-byte floats as Telltale uses
tools/patch_menu_chapters.py           the three edits
tools/luadis.py                        disassembler used to review the diff
tools/common.ps1                       Steam library lookup shared by the scripts
src/mod/_resdesc_50_Mod_S2Rewind.lua   resource descriptor, plain text (encrypted at build time)
src/mod/modinfo_season2_rewind.json    Telltale Mod Launcher manifest
```

`luapatch52.py` is generic. It round-trips any Definitive Series script byte for byte, so it can be reused for other script mods in this game.

## Credits

- ttarchext by Luigi Auriemma, which handles the archive and encryption formats.
- The Telltale Modding Group for the original [Telltale Mod Launcher](https://github.com/Telltale-Modding-Group/TelltaleModLauncher) and for documenting the `_resdesc_50` patch set approach.

## License

MIT for the scripts and tools here. The game and its files belong to their owners; the built archive is distributed only as a patch for people who own the game.
