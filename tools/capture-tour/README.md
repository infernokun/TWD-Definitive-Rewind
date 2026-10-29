# Screenshot tour: how the Season 4 rewind pictures were made

This folder is a **development tool**. It is not part of the released mod and nothing in it ships in
the release zip. It is kept here to document how the Season 4 rewind pictures (`src/pictures/s4`) were
captured, and as a worked example of driving a Telltale game from Lua: hooking scene starts, moving
between scenes, keeping state across the engine's Lua resets, and talking to a program outside the game.

## The problem

Season 2's original rewind shows a screenshot of each chapter, so you can tell at a glance where you
are rewinding to. The mod adds rewind to Seasons 3 and 4 and wanted the same thing. But the game has no
per-scene pictures for those seasons.

The first version cut pictures out of textures the game already has: the "Previously On" recap art,
the episode-select key art and dioramas, and location matte paintings. That works for Season 3, which
keeps it. For Season 4 it was too vague: one painting per location, so the four
"Boarding School Ext. Night" points of Episode 1 all looked the same.

Real screenshots of 58 rewind points meant playing through all four episodes and stopping at each one.
That is hours of play, and has to be repeated whenever a picture needs redoing. So the game was made to
do it.

## How it works

```
 build.ps1 -CaptureTour [-AutoTest]
   packs the mod + lua/TWDRewindAddon.lua + a generated TWDRewindTourConfig.lua
   into a capture build (its own name in the mod launcher)

 in the game                                     outside the game
 -----------                                     ----------------
 Season 4 menu: "Screenshot tour" row            capture_tour.ps1
   (or -AutoTest: picks the slot and starts)       every second: copies prefs.prop,
 episode boots into scene table entry 1            reads the tour log,
 each scene start  -> log "start|ep|step|..."  ->  screenshots the game window into
 F7 / timer        -> log "load|ep|step|..."       captures\S4\E<ep>\<step> <scene>\HHmmss.jpg
                      run the next entry's setup   (skips frames while a scene loads)
                      Game_EndScene(next script)
 last entry        -> log "done|ep"
   (-AutoTest: back to the Season 4 menu, next episode)

 pick/*.py: shortlist -> candidates -> crops -> src/pictures/s4 + src/pictures.json
 build.ps1 (normal): tools/make_pictures.py turns them into the game's textures
```

**The scene list.** The tour walks Telltale's developer scene table for each episode
(`src/lua/TWDRewindScenes.lua`), the same table the rewind uses to find and enter scenes. Each entry has
a scene script and a setup command (act number, "entered" flags and, in some entries, test choices).

**The add-on.** `lua/TWDRewindAddon.lua` is loaded by the mod through a generic hook at the end of
`TWDRewind.lua`: if an archive mounts a file named `TWDRewindAddon.lua`, it is loaded after the mod,
with a few helpers (`R.Try`, `R.SetPref`, `R.GetPref`, `R.Now`, `R.LogFile`, `R.QueryLog`). The add-on
wraps two of the mod's functions:
- `R.BeforeSceneStart`, which the mod calls just before every scene's own start logic, to log the scene
  and start a per-scene thread that waits for F7 or the timer;
- `R.ExtraRows`, to add the "Screenshot tour" row to the Season 4 rewind list.

The released mod ships no add-on, so these hooks do nothing there.

**Starting an episode in a chosen scene** uses the rewind's own jump (`R.SetPending` and
`R.LaunchEpisode`): the menu answers the engine's question "which script does this episode start
with?" with the entry's script.

**Moving to the next scene** works the way the game's own scripts do it: run the entry's setup with
`DoString`, then `Game_EndScene(script)`.

**The tour log** is a string in the game's preferences ("TWDRewind - Tour Log"). `capture_tour.ps1`
copies `prefs.prop` once a second and reads the log out of the copy. It never writes to the file. Lines:

| line | when |
| --- | --- |
| `begin\|ep\|time\|clock` | the tour of an episode starts (from the menu) |
| `start\|ep\|step\|label\|script\|time\|clock` | a scene of the table has started: shots go to this step |
| `load\|ep\|step\|script\|time\|clock` | moving to the next scene: shots pause until the next `start` |
| `done\|ep\|time\|clock` | the episode's last entry is finished |
| `resume\|ep\|step`, `auto\|...`, `run\|...`, `error\|...` | diagnostics |

`clock` is the time of day as `YYYYMMDDhhmmss`, so shots can be matched to the log afterwards.

## What we had to find out about the engine

These are what made the tour work, and they apply to any mod that wants to run code inside a Season 4
episode. Each one says how we know it.

1. **Retail episodes never run the usual mod entry point.** The game's `ProjectInclude.lua` loads
   `WalkingDeadTools.lua` only `if IsToolBuild()`, and `DialogBlocker.lua` likewise. That is fine in the
   menus, which load `DebugLoader.lua` if it exists, but nothing of the mod ran inside an episode. Season
   4's `EpisodeInclude.lua` does load `GameOverrides.lua` (right after `Game.lua`) in every build, so
   the mod's third archive, mounted only into `<ProjectSeason4>`, replaces it with a wrapper. The
   wrapper runs the stock file (renamed `TWDRewind_S4_GameOverrides.lua`) and then the mod. *Read from
   the game's own scripts.* No loader like this has been found for Season 3 episodes yet, so the mod
   (and the tour) runs inside Season 4 episodes only.
2. **Every episode start and every scene change starts a fresh Lua state.** Starting an episode goes
   through `ResetGame`, and `Game_EndScene` ends the scene and loads the next script in a new state.
   Nothing kept in Lua survives a scene change: not tables, not threads, not hooks. So the tour keeps
   its position ("episode|step") in the preferences and picks it up at the next scene start.
   *Found because the first tour stopped after one scene. Confirmed in a Ghidra decompile of the
   DRM-free Epic Games Store build of the game (the same engine build as Steam's).*
3. **Scene start.** `Game_SceneOpen` opens the scene with `Game_OnSceneOpened` as its callback, which
   calls the global `Game_StartScene(bFadeIn)` by name. So a wrapper installed in `_G` sees every scene
   start, and that is where the mod and the add-on hook in. *Read from the game's scripts; confirmed by
   the tour logging every scene.*
4. **Booting an episode into a scene.** The menu's Lua state answers
   `SubProject_GetEpisodeFirstScript`, and the episode boots into the script it returns. Nothing in the
   episode asks again, so the episode's own state reads the jump back from the preferences. Before
   launching, `SaveLoad_RestartEpisode(ep, true)` must run: without it, an episode that has a save loads
   that save and never boots into the chosen script. *Found by testing: the first tour kept loading the
   old save.*
5. **Keys.** `InputPCIsVKeyPressed(vk)` with Windows virtual-key codes (F7 = 0x76, F6 = 0x75), called
   twice the way the game's `Input.lua` does. *Read from `Input.lua`; works.*
6. **Numbers are 4-byte floats.** This Lua 5.2 is built with a 32-bit float `lua_Number`, so
   `os.time()` is only exact to about two minutes. The log uses `os.date("%Y%m%d%H%M%S")` as text
   instead. *Read from the bytecode header (and seen in the timestamps of early logs).*
7. **The preferences are a usable channel.** `prefs.prop` keeps string values as plain text (the keys
   are hashed), and `SavePrefs` writes the file straight away. So a program outside the game can follow
   a log as it is written. *Seen: the capture script followed the tour live.*
8. **A fullscreen game minimizes itself when another window takes the focus.** Frames taken then are
   lost. In the first full run, six scenes got no shots this way; they were taken again with
   `-TourOnly`, and the capture script now brings the game back and logs why it skips frames. *Seen; the
   cause of those six gaps is the likeliest explanation, not proven.*

### Wrong turns

Before points 1, 2 and 4 were known, the tour "did nothing" in ways that looked like other problems.
Theories that turned out wrong: the scene-start callback not firing, threads dying, and the mod's code
running under a different `_ENV`. What helped was logging every step to the preferences and reading
them back from outside the game. The `auto|`, `resume|` and `error|` lines are left in the log for that
reason. Decompiling the engine settled point 2, which testing alone kept pointing away from.

### Research tools

- **Ghidra 12.2** with a Java 21 runtime (Eclipse Temurin), on the **Epic Games Store** copy of
  `WDC.exe`. The Steam `WDC.exe` is wrapped in Steam's DRM (SteamStub: an encrypted `.text` section and a
  `.bind` loader section), and we did not touch it. The Epic copy is not wrapped and is the same build,
  so it was used for reading only.
  - Ghidra 12.2 failed to start with "data file must be inside the data dir" until its settings, cache
    and temp folders were set explicitly: `-Dapplication.settingsdir=... -Dapplication.cachedir=...
    -Djava.io.tmpdir=...` in `support/launch.properties` (VMARGS).
- `research/ghidra/DumpLuaFuncs.java`: finds where the engine registers a Lua function by name and
  decompiles the C function behind it (args: output folder, names).
- `research/ghidra/DecompileAt.java` and `ListAt.java`: decompile or disassemble the code at given
  addresses, without a full auto-analysis.
- `research/find_riprefs.py`: finds code that loads a given string with a RIP-relative `lea`/`mov`. This
  is a quick way to find the users of a function-name string in an x64 exe.

Decompiled output is not kept in the repo: it is derived from the game's executable.

## Safety

The tour runs scene setups from Telltale's developer table. Some of them set test choices, so the tour
must never run on a real playthrough. The row only works on a **new save**: at most one episode
started and at most 20 saves in the slot's log. It also works on the slot a tour already used, which
the preferences remember ("TWDRewind - Tour Slot"). Otherwise the row reads "Tour: needs a new save".
The capture build is named "Chapter Rewind - SCREENSHOT TOUR (capture build)" in the mod launcher, so it
can't be mistaken for the real mod. Put the normal build back afterwards.

## Using it

Needs everything `build.ps1` needs, plus Windows PowerShell for `capture_tour.ps1` and Python 3 with
Pillow and numpy for `pick/`.

1. **Build and install the capture build** (from the repo root):

   ```
   .\build.ps1 -CaptureTour                      # F7 = next scene, F6 = previous
   .\build.ps1 -CaptureTour -AutoTest -TourSeconds 60
   .\build.ps1 -CaptureTour -AutoTest -TourSeconds 60 -TourOnly "2:5,6;3:9;4:2,3,4"
   .\install.ps1
   ```

   - With `-AutoTest`, the whole run is unattended. The hub menu switches to Season 4, the tour slot is
     selected, each episode's tour runs, and after its last scene the game goes back to the menu for
     the next episode.
   - `-TourOnly "episode:step,step;..."` visits only those scene table entries, to take scenes again.
   - Every build counts as a new run.

2. **Start the capture script, then the game:**

   ```
   .\tools\capture-tour\capture_tour.ps1 -Out D:\captures
   ```

   It waits for the game, takes a shot of the game window every second while a scene is on screen, and
   stops after Episode 4's `done`, when the game closes, or after `-MaxMinutes` (default 100). It only
   reads log lines written after it starts. Leave the game window in front.
   - The first time, make a new Season 4 save in a free slot (start Episode 1, then quit to the menu).
     Then open Episode 1's rewind points, press Tab for the list, and pick "Screenshot tour". `-AutoTest` builds reuse that slot by
     themselves after that.
   - The full run takes about an hour at 60 seconds a scene: 58 scenes plus loading.

3. **Pick the pictures** (`pick/`, each script documents its arguments):
   - `scene_sheet.py`: one sheet per episode, a few frames per scene, to check the folders match their
     labels.
   - `all_frames.py`: every frame of one scene, for scenes whose shortlist is poor.
   - `shortlist.py`: per scene, up to 12 varied, sharp and lit frames. Dark, flat and near-duplicate
     frames are dropped, with a lower bar for night scenes. Writes lettered review sheets and
     `shortlist.json`.
   - `make_candidates.py`: takes `picks.json` (scene -> five letters, or file names, in order of
     preference) and copies five ranked candidates per scene. Writes one sheet per episode, with a box
     showing the part the Season 4 picture view shows.
   - `grid.py` and `crop_preview.py`: choose and check crops. `cx`/`cy` are the centre of the crop
     (0..1); `zoom` crops tighter, which is how subtitles at the bottom are cropped out. The preview
     uses `tools/make_pictures.py`'s own crop code, so it matches the build.
   - `install_s4_pictures.py`: writes the chosen shots to `src/pictures/s4` (1920x1080 JPEG) and their
     crops to `src/pictures.json` (`seasons.4.steps`: episode -> scene table entry -> picture).

4. **Build the normal mod** (`.\build.ps1`) and install it again.

## Things to know

- **The tour plays scenes with nobody at the controls.** In some scenes the first minute is not what
  the scene is known for. Examples:
  - Episode 1 "Boarding School Dorm" opens with the credits.
  - In Episode 2 "BS Int. Night Fight", Clementine dies about 35 seconds in.
  - Episode 4 "Boarding School Gate" starts with a forest walk.

  The picks avoided those frames.
- **Episode 2 step 17 ("BS Ext. Damaged")** shows the fight inside the school for the whole first
  minute. The label likely belongs to a later part of the scene.
- **Two Episode 1 points**, "Forest Shack" and "Forest Shack - From Tile", open on the same moment.
- **The capture build was tested** with the tour code inside `TWDRewind.lua`; that is how the pictures
  were taken. Moving it into this add-on changed how the tour starts: it now writes its position before
  launching instead of riding on the jump. The add-on build compiles, but has not yet been run in the
  game.

## Files

| file | what |
| --- | --- |
| `lua/TWDRewindAddon.lua` | the tour, as an add-on to the mod (packed only by `build.ps1 -CaptureTour`) |
| `capture_tour.ps1` | screenshots the game window by scene, from the tour log |
| `pick/*.py` | shortlist, candidate, crop and install scripts for the pictures |
| `research/ghidra/*.java` | Ghidra scripts used to read the engine |
| `research/find_riprefs.py` | finds RIP-relative references to strings in an x64 exe |
