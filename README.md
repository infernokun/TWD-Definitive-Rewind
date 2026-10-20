# Season 2 Rewind for The Walking Dead: The Telltale Definitive Series

Brings back the chapter Rewind feature in Season 2. The Definitive Series shipped with it switched off, so you could only restart a whole episode. With this mod the episode menu once again lists every chapter you have reached, and picking one lets you rewind (or branch) from that point, exactly like the original Season Two release.

Works on the Steam PC version. Two files, no changes to any stock game file, removable in seconds.

## Why

In the original Season Two you could open an episode, pick any chapter you had already played, and either rewind your save to that point or branch a new save from it. That is how most people replayed choices.

The Definitive Series reuses the Season Two menu almost unchanged, but someone flipped a switch in the menu script so the chapter list is never built and the only option left is "Restart Episode". Seasons 1, 3, 4 and Michonne kept their rewind menus. Only Season 2 lost it, and nothing in the game files explains why.

I wanted it back, so I went through the scripts of both games, found the exact change, and reversed it.

## What was changed

The Season 2 episode menu lives in `Menu_chapters.lua` inside `WDC_pc_MenuSeason2_data.ttarch2`. Compared with the original Season Two script, the Definitive Series version differs in three places:

| | Original Season Two | Definitive Series | This mod |
|---|---|---|---|
| Chapter list | built for every autosave | gated behind a new `Menu_Chapters_RewindIsSupported()` that always returns `false` | returns `true` |
| Picking a chapter | "Rewind" popup, then choose a save slot to copy into | "Restart Episode" popup | original popup and flow restored |
| Button label | `navhelp_rewind` ("REWIND") | `navhelp_restart` | `navhelp_rewind` |

Everything the feature depends on (the save-slot rewind code, `SaveLoad_Revert`, the menu text, the chapter thumbnails) is still in the Definitive Series untouched. Only this one script needed patching, and the patch is three small edits to the compiled Lua bytecode.

## How it loads

The engine reads every `_resdesc_50_*.lua` file in the Archives folder at startup. Each one registers a resource set with a priority and a list of archives. When two sets contain a file with the same name, the higher priority wins. Telltale used this for their own PC patches (priority 400 over the stock 62). This mod registers a set at priority 700 that contains just the patched script.

So the game is never modified. It just finds a newer copy of one file first.

## Install

1. Download the zip from the [Releases](../../releases) page and extract it anywhere.
2. Run `install.ps1` (right-click, Run with PowerShell). It finds the game through Steam and copies the two files into the game's `Archives` folder.

If the script cannot find the game, pass the path:

```powershell
.\install.ps1 -GameDir "D:\SteamLibrary\steamapps\common\The Walking Dead The Telltale Definitive Series"
```

Or copy by hand. Put these two files into `...\The Walking Dead The Telltale Definitive Series\Archives\`:

```
WDC_pc_Mod_S2Rewind_data.ttarch2
_resdesc_50_Mod_S2Rewind.lua
```

The zip also works with [TelltaleModLauncher](https://github.com/Telltale-Modding-Group/TelltaleModLauncher): add it with the "+" button. The launcher copies the same two files.

## Uninstall

Run `uninstall.ps1`, or delete the two files from the Archives folder. Steam's "verify integrity" will not remove them on its own because they are additions, not replacements.

## Things to know

- Rewinding deletes the saves after the chapter you rewind to. That is how the original game worked too. If you want to keep a finished playthrough, use Branch, or copy your save slot first (`Documents\Telltale Games\The Walking Dead Definitive`, files named `wd2_saveslot1*`).
- If another mod also replaces `Menu_chapters.lua`, the one with the higher priority in its `_resdesc_50` file wins.
- Tested on the Steam build dated 2020.01.29 (Season 108-RC). Other storefronts use the same archives but have not been tried.

## Building from source

Requirements: Windows, Python 3, [ttarchext](https://aluigi.altervista.org/papers.htm#ttarchext) 0.3.2 or newer, and the game installed.

```powershell
.\build.ps1                      # put ttarchext.exe in tools\ or pass -Ttarchext <path>
```

The build extracts the stock `Menu_chapters.lua` from your game install (it is not in this repo), patches it, packs the archive, encrypts the descriptor, extracts both again to check they round-trip, and writes `dist\` with checksums.

Repository layout:

```
tools/luapatch52.py          Lua 5.2 bytecode parser and writer, exact round-trip, 4-byte floats as Telltale uses
tools/patch_menu_chapters.py the three edits
tools/luadis.py              disassembler used to review the diff
tools/common.ps1             Steam library lookup shared by the scripts
src/mod/_resdesc_50_Mod_S2Rewind.lua   resource descriptor, plain text (encrypted at build time)
src/mod/modinfo.json         TelltaleModLauncher manifest
```

`luapatch52.py` is generic. It round-trips any Definitive Series script byte for byte, so it can be reused for other script mods in this game.

## Credits

- ttarchext by Luigi Auriemma, which handles the archive and encryption formats.
- The Telltale Modding Group for documenting the `_resdesc_50` patch set approach and the mod launcher format.

## License

MIT for the scripts and tools here. The game and its files belong to their owners; the built archive is distributed only as a patch for people who own the game.
