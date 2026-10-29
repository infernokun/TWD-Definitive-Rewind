# Changelog

## 2.0.0 (2026-10-28)

- Now covers Seasons 3 and 4 as well as Season 2, so the mod is renamed "Chapter Rewind (Seasons 2, 3 and 4)".
- Seasons 3 and 4: the rewind list shows every scene you reached in the episode, rebuilt from the season's choice log, so it works on saves made before the mod (and finished games). Rewinding cuts the log after the last save before that scene and starts the episode there; earlier choices are kept.
- Seasons 3 and 4 also keep an exact save at the start of each scene while you play (they normally only ever overwrite one autosave), by giving the first checkpoint of each scene a chapter ID as Michonne does.
- Season 3: the episode's More Options popup has a Rewind entry that lists the episode's rewind points.
- Season 4: Restart Episode, and the button of any episode you've played, open the rewind list: the stock restart from the beginning first, then the episode's rewind points. Controllers also get a Rewind legend entry.
- Seasons 3 and 4: the rewind list shows four buttons at a time and pages with More... / Back...; every rewind point has a picture.
  - Season 4: Rewind opens straight onto the latest point in the game's own picture popup, with Previous / Next / Rewind here. Left / Right arrow keys and LB / RB also browse, Tab (Y) shows the numbered list of all points, and Esc (B) closes. Each of the 58 rewind points has its own screenshot from the start of its scene (`src/pictures/s4`, picked per point and cropped in `src/pictures.json`), so two visits to one location look different. From the beginning shows the episode's first scene, and a Saved entry shows the scene it was saved in.
  - A save made at the start of a scene that is already a scene point is no longer listed twice.
  - Season 3: a picture strip in its More Options window follows the highlighted row (location matte paintings).
- Seasons 3 and 4: after a rewind, the list again shows every point from earlier in that episode. A rewind logs a new Begin Episode, and back-to-back Begin Episode events of one episode now count as one playthrough.
- The Season 4 pictures were taken with a development tool kept in the repo, `tools/capture-tour` (not in the release). `TWDRewind.lua` loads an optional `TWDRewindAddon.lua` if an archive provides one; the release ships none.
- Seasons 3 and 4 add two new scripts (`DebugLoader.lua`, `TWDRewind.lua`); the menus load the mod through `DebugLoader.lua`.
- Season 4 episodes load the mod through a third set, `Mod_TWDRewind_S4Game` (`WDC_pc_Mod_TWDRewind_S4Game_data.ttarch2` / `_resdesc_50_Mod_TWDRewind_S4Game.lua`, mounted into `<ProjectSeason4>` only). Its `GameOverrides.lua` runs the stock one (extracted from the game at build time) and then loads the mod. Retail episodes never load an optional file such as `WalkingDeadTools.lua`: `ProjectInclude.lua` requires it in tool builds only. Season 3 episodes still don't load the mod.
- Season 4: a scene point's act number and "entered" flags are now applied in the episode, at the scene's start (`Game_StartScene`), and the jump is used up only then.
- Season 2 is unchanged: the same patched `Menu_chapters.lua`, now in `WDC_pc_Mod_TWDRewind_S2_data.ttarch2` / `_resdesc_50_Mod_TWDRewind_S2.lua`.
- The launcher info file is now `modinfo_twd_rewind.json`. If 1.x is installed, remove it first (or delete `WDC_pc_Mod_S2Rewind_data.ttarch2` and `_resdesc_50_Mod_S2Rewind.lua`).
- The release zip holds only the six mod files, the launcher info file and `readme.txt` with the install steps. The install scripts, README and license stay in the repo.
- Building now also needs `luac.exe` (Lua 5.2) from the Telltale Modding Group's Script Editor.

## 1.0.1 (2026-10-20)

- The TelltaleModLauncher info file is now `modinfo_season2_rewind.json` instead of `modinfo.json`, so it is clear which mod it belongs to and it doesn't share a generic name with other mods in the Archives folder.
- The mod itself is unchanged. If you installed 1.0.0 by hand, there is nothing to update.

## 1.0.0 (2026-10-19)

First release.

- Restores the per-chapter Rewind option in Season 2 of The Walking Dead: The Telltale Definitive Series.
- Ships as two files for the Archives folder. No stock game file is changed.
- Tested on the Steam build dated 2020.01.29 (Season 108-RC).
