-- Screenshot tour: a development add-on for the Chapter Rewind mod, NOT part of the released mod.
-- See tools/capture-tour/README.md. build.ps1 -CaptureTour packs this file (as TWDRewindAddon.lua,
-- which TWDRewind.lua loads at its end if it exists) and a generated TWDRewindTourConfig.lua into a
-- separately named capture build.
--
-- What it does: walks a Season 4 episode through every entry of Telltale's developer scene table
-- (TWDRewindScenes.lua), the same table the rewind uses. The episode starts in the first entry (the
-- rewind's own jump); each scene start is logged, then after F7 (or a timer) the next entry's setup
-- runs and the scene is ended into the next entry's script, the way the game moves between scenes
-- (Game_EndScene). Every scene load and start goes to the preferences as "TWDRewind - Tour Log" with
-- the time of day, which tools/capture-tour/capture_tour.ps1 reads to file its screenshots by scene.
--
-- Engine facts this depends on (found while building the mod; see the README):
-- - Starting an episode, and every Game_EndScene, is a fresh Lua state: nothing in Lua survives a
--   scene change, so the tour's position is kept in the preferences ("TWDRewind - Tour State") and
--   picked up again at the next scene start.
-- - Game_StartScene is called by its global name when a scene is open, so the mod's wrapper there
--   (R.BeforeSceneStart) is the place to see every scene start.
-- - The preferences (prefs.prop) are saved to disk right away by SavePrefs, so a program outside
--   the game can follow the log while the game runs.

local R = TWDRewind
if type(R) ~= "table" or R.tourAddon then
    return
end
R.tourAddon = true

pcall(require, "TWDRewindTourConfig.lua")
if type(TWDRewindTour) ~= "table" then
    return
end
local cfg = TWDRewindTour

local try, setPref, getPref, now = R.Try, R.SetPref, R.GetPref, R.Now

local kText = {
    tour = "Screenshot tour",
    tourBlocked = "Tour: needs a new save",
}

local kTourSlotKey = "TWDRewind - Tour Slot"
local kTourLogKey = "TWDRewind - Tour Log"
local kTourStateKey = "TWDRewind - Tour State"

-- Time of day as text (Lua numbers are 4-byte floats here, so os.time() is only exact to ~2 minutes).
local function wallClock()
    if type(os) == "table" and type(os.date) == "function" then
        local ok, t = pcall(os.date, "%Y%m%d%H%M%S")
        if ok then
            return tostring(t)
        end
    end
    return ""
end

-- Windows virtual-key codes, read with the engine's InputPCIsVKeyPressed (as Input.lua does, twice).
local kTourNextKey = 0x76    -- F7
local kTourPrevKey = 0x75    -- F6

local function keyDown(vk)
    pcall(InputPCIsVKeyPressed, vk)
    local ok, down = pcall(InputPCIsVKeyPressed, vk)
    return ok and down and true or false
end

local function tourLog(line)
    setPref(kTourLogKey, (getPref(kTourLogKey) or "") .. line .. "\n")
end

-- Only a new save (at most one episode started, a few saves) or the slot a tour already used
-- (remembered in the preferences): the tour plays scenes with developer setups and must never touch
-- a real playthrough.
local kTourMaxSaves = 20

local function tourEligible()
    local okSlot, slot = try("SaveLoad_GetSlot")
    if not okSlot or type(slot) ~= "string" then
        return false
    end
    if getPref(kTourSlotKey) == slot then
        return true
    end
    local file = R.LogFile()
    if not file then
        return false
    end
    local begins = R.QueryLog(file, { { tag = "Begin Episode" } })
    local saves = R.QueryLog(file, { { tag = "Save Serial" } })
    return #begins <= 1 and #saves <= kTourMaxSaves
end

-- The steps a tour visits in an episode: all of them, or only those in cfg.only[ep]
-- (build.ps1 -TourOnly, to take scenes again).
local function tourSteps(ep, count)
    local steps = {}
    if cfg.only then
        for _, s in ipairs(cfg.only[ep] or {}) do
            if s >= 1 and s <= count then
                steps[#steps + 1] = s
            end
        end
    else
        for s = 1, count do
            steps[s] = s
        end
    end
    return steps
end

-- The step dir (+1 / -1) places away from step in the visited steps; nil past the last one.
local function tourStepFrom(t, step, dir)
    local steps = tourSteps(t.ep, #t.entries)
    for i, s in ipairs(steps) do
        if s == step then
            return steps[math.max(1, i + dir)]
        end
    end
    return steps[1]
end

local tour                   -- { ep, entries, step, token, seconds } while a tour runs in this state

local function tourStart(ep, step)
    local tbl = TWDRewindScenes and TWDRewindScenes[4] and TWDRewindScenes[4][ep]
    if not tbl or #tbl == 0 then
        tourLog(string.format("error|tourstart|%d|no scene table", ep))
        return
    end
    step = math.max(1, math.min(step or tourSteps(ep, #tbl)[1] or 1, #tbl))
    tour = { ep = ep, entries = tbl, step = step, token = 0, seconds = cfg.seconds or 0 }
    setPref(kTourStateKey, ep .. "|" .. step)
end

-- A fresh state inside the episode a tour is running in: carry on from the saved position.
local function tourResume()
    local ep, step = string.match(getPref(kTourStateKey) or "", "^(%d+)|(%d+)$")
    ep, step = tonumber(ep), tonumber(step)
    local okCur, cur = try("SubProject_GetCurrent")
    if ep and step and okCur and type(cur) == "string" and string.lower(cur) == string.lower("WalkingDead40" .. ep) then
        tourLog(string.format("resume|%d|%d", ep, step))
        tourStart(ep, step)
    end
end

-- Each scene start notes the scene and waits for F7 / F6 (or the timer) in a thread that belongs to
-- that scene; then the chosen entry's setup runs and the scene is ended into its script. A scene start
-- the tour didn't cause (a scene that moves on by itself) keeps the current step.
local function tourOnStart()
    local t = tour
    t.token = t.token + 1
    local token, step = t.token, t.step
    local e = t.entries[step]
    local okScript, current = try("Game_GetCurrentScript")
    tourLog(string.format("start|%d|%d|%s|%s|%.1f|%s", t.ep, step, e.label,
        okScript and tostring(current) or "?", now(), wallClock()))
    ThreadStart(function()
        -- F7 next scene, F6 previous one (to take a shot again); with seconds > 0 also on a timer.
        local t0 = now()
        local held = true            -- ignore a key still down from the previous scene
        local target
        while tour == t and t.token == token do
            local nextDown, prevDown = keyDown(kTourNextKey), keyDown(kTourPrevKey)
            if not nextDown and not prevDown then
                held = false
            elseif not held then
                target = tourStepFrom(t, step, nextDown and 1 or -1) or 0
                break
            end
            if t.seconds > 0 and now() - t0 >= t.seconds then
                target = tourStepFrom(t, step, 1) or 0
                break
            end
            WaitForNextFrame()
        end
        if not target or tour ~= t or t.token ~= token then
            return
        end
        if target == 0 or target > #t.entries then
            tourLog(string.format("done|%d|%.1f|%s", t.ep, now(), wallClock()))
            tour = nil
            setPref(kTourStateKey, "")
            if cfg.auto then
                -- Back to the Season 4 menu, which starts the next episode's tour.
                pcall(SubProject_Switch, "MenuSeason4")
            end
            return
        end
        t.step = target
        setPref(kTourStateKey, t.ep .. "|" .. t.step)
        local nextEntry = t.entries[t.step]
        tourLog(string.format("load|%d|%d|%s|%.1f|%s", t.ep, t.step, nextEntry.script, now(), wallClock()))
        local okSetup, errSetup = pcall(DoString, nextEntry.command or "")
        if not okSetup then
            tourLog("error|setup|" .. tostring(errSetup))
        end
        local okEnd, errEnd
        if rawget(_G, "Game_EndScene") then
            okEnd, errEnd = pcall(Game_EndScene, nextEntry.script)
        else
            okEnd, errEnd = pcall(LoadScript, nextEntry.script .. ".lua")
        end
        if not okEnd then
            tourLog("error|load|" .. tostring(errEnd))
        end
    end)
end

-- Every scene start: the mod's own work first (it applies a pending jump's setup), then the tour.
local baseBeforeSceneStart = R.BeforeSceneStart
function R.BeforeSceneStart(...)
    if baseBeforeSceneStart then
        baseBeforeSceneStart(...)
    end
    if not tour then
        tourResume()
    end
    if tour then
        tourOnStart()
    end
end

-- The "Screenshot tour" row of the Season 4 list: start the episode in its first entry (with the
-- entry's full developer setup) and walk through the rest.
function TWDRewind_TourGo(ep)
    TWDRewind_Close()
    local tbl = TWDRewindScenes and TWDRewindScenes[4] and TWDRewindScenes[4][ep]
    local okProject, project = try("Menu_GetFullEpisodeName", ep)
    local okSlot, slot = try("SaveLoad_GetSlot")
    local firstStep = tbl and tourSteps(ep, #tbl)[1]
    local first = firstStep and tbl[firstStep]
    if not first or not okProject or type(project) ~= "string" or not okSlot or not tourEligible() then
        return
    end
    setPref(kTourSlotKey, slot)
    tourLog(string.format("begin|%d|%.1f|%s", ep, now(), wallClock()))
    ThreadStart(function()
        WaitForNextFrame()
        -- As the rewind does: without this, starting an episode that has a save loads that save
        -- instead of booting the episode (where the jump to the first entry happens).
        local ok, err = pcall(SaveLoad_RestartEpisode, ep, true)
        if not ok then
            tourLog("error|restart|" .. tostring(err))
            return
        end
        Yield()
        pcall(SaveLoad_SetEpisode, ep)
        -- The episode boots into the first entry through the mod's own jump; the tour position is
        -- picked up at that scene's start.
        setPref(kTourStateKey, ep .. "|" .. firstStep)
        R.SetPending({ project = project, script = first.script, command = first.command })
        R.LaunchEpisode(ep)
    end)
end

-- Adds the tour row to the Season 4 rewind list (on a new save only).
local baseExtraRows = R.ExtraRows
function R.ExtraRows(ep, items, image)
    if baseExtraRows then
        baseExtraRows(ep, items, image)
    end
    if R.Season() ~= 4 then
        return
    end
    if tourEligible() then
        table.insert(items, { label = kText.tour, action = "TWDRewind_TourGo(" .. ep .. ")", image = image })
    else
        table.insert(items, { label = kText.tourBlocked, action = "TWDRewind_Noop()", image = image })
    end
end

-- Auto-test (cfg.auto, build.ps1 -AutoTest): runs the tour without anyone at the menus. The hub menu
-- switches to Season 4; the Season 4 menu selects the slot a tour already used (never any other) and
-- starts the tour of the first episode without a "done" line in the log; the tour moves on by itself
-- and goes back to the Season 4 menu after an episode's last scene. A build only counts the "done"
-- lines after its own "run|" line (cfg.run, the build time), so a new build starts over.
local function nextTourEpisode()
    local log = getPref(kTourLogKey) or ""
    if cfg.run then
        local marker = "run|" .. cfg.run .. "\n"
        local at = string.find(log, marker, 1, true)
        if at then
            log = string.sub(log, at)
        else
            tourLog("run|" .. cfg.run)
            log = ""
        end
    end
    local ep = 1
    for done in string.gmatch(log, "done|(%d+)|") do
        ep = math.max(ep, tonumber(done) + 1)
    end
    while cfg.only and ep <= 4 and not cfg.only[ep] do
        ep = ep + 1
    end
    return ep
end

local function autoTest()
    local okCur, cur = try("SubProject_GetCurrent")
    cur = okCur and type(cur) == "string" and cur or ""
    if cur == "Menu" then
        tourLog("auto|hub")
        ThreadStart(function()
            local t0 = now()
            while now() - t0 < 4 do
                WaitForNextFrame()
            end
            tourLog("auto|switch to MenuSeason4")
            pcall(SubProject_Switch, "MenuSeason4")
        end)
    elseif cur == "MenuSeason4" then
        local slot = getPref(kTourSlotKey)
        local ep = nextTourEpisode()
        tourLog(string.format("auto|season4 menu|slot %s|next episode %d", tostring(slot), ep))
        local tbl = TWDRewindScenes and TWDRewindScenes[4]
        if not slot or slot == "" or not tbl or not tbl[ep] then
            return
        end
        ThreadStart(function()
            local t0 = now()
            while now() - t0 < 6 do
                WaitForNextFrame()
            end
            local okSet, errSet = pcall(SaveLoad_SetSlot, slot)
            tourLog("auto|set slot|" .. tostring(okSet) .. "|" .. tostring(errSet))
            TWDRewind_TourGo(ep)
        end)
    end
end

if cfg.auto then
    local ok, err = pcall(autoTest)
    if not ok then
        tourLog("error|auto|" .. tostring(err))
    end
end
