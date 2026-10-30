-- TWDRewind_S2.lua
-- Season 2: rewind into any save file, each keeping its own choice history.
--
-- Loaded by the patched Menu_chapters.lua (pcall(require, "TWDRewind_S2.lua") at its top). Season 2's
-- Menu_Main.lua does not load DebugLoader.lua, so TWDRewind.lua never runs in this menu.
--
-- Season 2's slot copy on PC (SaveLoad_Copy / SaveLoad_Branch) copies a slot's choice log file as is.
-- The log names itself and its pages inside the file, so the copy keeps reading and writing the
-- original's pages: the two save files share one history, and a rewind in either trims the other's.
-- The game can't fix that from a script, so copies are made here instead: the saves and slot data are
-- copied without the log, the target gets a fresh log of its own (the game creates one, named after
-- the slot, the first time a slot is used), and the source log's entries are replayed into it, as
-- Season 4's SaveLoad_CopyGeneratedSave does. Season 2's log keeps only two kinds of entry,
-- "Executing Dialog Node" (the choice stats and the choice randomizer read these) and "Save Serial"
-- (loading and rewinding cut the log back to one), so the copy's history matches the original's.
-- The rewind then runs in place in the copy.
--
-- The rewind's save-file picker (Menu_SaveSlots.lua) is where copies start: picking another file runs
-- that copy, then the stock overwrite in the copy. Every other way into the stock copy is refused.
-- The picker names files "wd2_saveslotN" while the game creates "wd2_saveSlotN" and compares names
-- exactly, so names are compared without case here.
--
-- Menu_Main.lua requires Menu_chapters.lua before Menu_SaveSlots.lua, so this file wraps require and
-- re-checks its hooks after every later require, as TWDRewind.lua does. Each copy leaves a short
-- report in the preferences ("TWDRewindS2 report").

TWDRewindS2 = TWDRewindS2 or {}
local R = TWDRewindS2
R.version = "2.1.0"
R.originals = R.originals or {}
R.wrappers = R.wrappers or {}

local kTags = { "Executing Dialog Node", "Save Serial" }
local kHeader = "Rewind"
local kRefused = "This save file can't be copied this way. Use Rewind and pick a save file in the list instead."
local kFailed = "Couldn't copy the save file, so nothing was rewound. Your current save file is unchanged."

local function G(name)
    return rawget(_G, name)
end

local function try(name, ...)
    local f = G(name)
    if type(f) ~= "function" then
        return false
    end
    return pcall(f, ...)
end

local function upvalue(f, wanted)
    if type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
        return nil
    end
    for i = 1, 64 do
        local name, value = debug.getupvalue(f, i)
        if name == nil then
            return nil
        end
        if name == wanted then
            return value
        end
    end
    return nil
end

local function setPref(key, value)
    local ok, prefs = try("GetPreferences")
    if ok and prefs then
        local okExists, exists = pcall(PropertyExists, prefs, key)
        if okExists and exists then
            pcall(PropertySet, prefs, key, value)
        elseif not pcall(PropertyCreate, prefs, key, "String", value) then
            pcall(PropertySet, prefs, key, value)
        end
        try("SavePrefs")
    end
end

local function report(text)
    setPref("TWDRewindS2 report", "TWDRewindS2 " .. R.version .. ": " .. text)
end

local function notify(message)
    pcall(UIZ_Notify, message, kHeader)
end

local function currentSlot()
    local ok, slot = try("SaveLoad_GetSlot")
    if ok and type(slot) == "string" then
        return slot
    end
    return nil
end

local function isSeason2()
    local slot = currentSlot()
    return slot ~= nil and string.find(string.lower(slot), "wd2_", 1, true) == 1
end

local function isCurrentSlot(name)
    local slot = currentSlot()
    return type(name) == "string" and slot ~= nil and string.lower(name) == string.lower(slot)
end

-- "wd2_saveSlot1.bundle" -> "wd2_saveslot1"
local function stem(slot)
    local s = string.lower(slot)
    if string.sub(s, -7) == ".bundle" then
        s = string.sub(s, 1, -8)
    end
    return s
end

-- A save of one slot under another slot's name: "_wd2_saveslot1_checkpoint4.bundle" -> "_wd2_saveslot2_...".
local function renamed(name, fromStem, toStem)
    local lower = string.lower(name)
    local prefix = "_" .. fromStem .. "_"
    if string.sub(lower, 1, string.len(prefix)) == prefix then
        return "_" .. toStem .. "_" .. string.sub(lower, string.len(prefix) + 1)
    end
    return name
end

local function yield()
    try("Yield")
end

-- Copies fromSlot to toSlot (replacing it) with its own log, then makes toSlot the current slot.
function R.CopyWithHistory(fromSlot, toSlot)
    local split = false
    local okPrefs, prefs = try("GetPreferences")
    if okPrefs and prefs then
        split = prefs["Save - Split Files"] and true or false
    end
    if not split then
        error("saves are not split into files")
    end
    local fromStem, toStem = stem(fromSlot), stem(toSlot)

    -- The source history, read before anything changes, oldest first.
    local events = QueryEventLog(FileSetExtension("_" .. fromStem .. "_id", "estore"), { { tag = kTags[1] }, { tag = kTags[2] } })
    if type(events) ~= "table" then
        error("could not read the history of " .. fromStem)
    end
    table.sort(events, function(a, b)
        return a.id < b.id
    end)

    -- The target cleared, then the slot data and saves copied under its name, without the log.
    R.copying = true
    SaveLoad_DeleteSlot(toSlot)
    yield()
    -- The stock delete stops early when the slot file is missing, which can leave old saves and an
    -- old (possibly shared) log behind; a log left there would be loaded as the target's.
    for _, name in ipairs(SaveLoad_GetSaveNames(toSlot) or {}) do
        pcall(Unload, name)
        pcall(ResourceDelete, name)
    end
    local toLog = "_" .. toStem .. "_id"
    local toLogPath = "logical:<User>/" .. toLog .. ".estore"
    local okActive, active = try("EventLogActive", toLog)
    if okActive and active then
        pcall(EventLogRemove, toLog)
    end
    pcall(ResourceSetNonPurgable, toLogPath, false)
    pcall(Unload, toLog .. ".estore")
    pcall(ResourceDelete, toLogPath)
    yield()
    ResourceCopy(fromSlot, "logical:<User>/" .. toStem .. ".bundle")
    local saves = SaveLoad_GetSaveNames(fromSlot) or {}
    for _, name in ipairs(saves) do
        ResourceCopy(name, "logical:<User>/" .. renamed(name, fromStem, toStem))
        yield()
    end

    -- Switching to the target creates its log, empty and named after it. The entries are replayed
    -- into it with the session log paused, as SaveLoad_CopyGeneratedSave does.
    SaveLoad_SetSlot(toStem .. ".bundle")
    yield()
    local okSession, sessionLog = try("GetSessionEventLogName", "session")
    local paused = true
    if okSession and sessionLog then
        local okPaused, isPaused = pcall(EventLogIsPaused, sessionLog)
        paused = okPaused and isPaused
        if not paused then
            pcall(EventLogSetPaused, sessionLog, true)
        end
    end
    -- A queried entry's tag comes back as a symbol, which the log's tag filter doesn't match, so the
    -- tag is written as its name (as SaveLoad_CopyGeneratedSave does); the data goes back as it came.
    local counts = { [kTags[1]] = 0, [kTags[2]] = 0 }
    local ok, err = pcall(function()
        for i, e in ipairs(events) do
            local tag = nil
            if e.tag == kTags[1] then
                tag = kTags[1]
            elseif e.tag == kTags[2] then
                tag = kTags[2]
            end
            if tag then
                CreateEventLogEvent(tag, e.data, true)
                counts[tag] = counts[tag] + 1
            end
            if i % 200 == 0 then
                yield()
            end
        end
    end)
    if okSession and sessionLog and not paused then
        pcall(EventLogSetPaused, sessionLog, false)
    end
    local toLogName = "_" .. toStem .. "_id"
    pcall(ForceEventLogFlushPage, toLogName)
    try("SaveLoad_SaveEventLog")
    try("ChoiceStats_Init", toLogName)
    R.copying = false
    if not ok then
        error("replaying the history failed after " .. (counts[kTags[1]] + counts[kTags[2]]) .. " entries: " .. tostring(err))
    end
    local okCheck, check = pcall(QueryEventLog, FileSetExtension(toLogName, "estore"), { { tag = kTags[1] }, { tag = kTags[2] } })
    local inLog = okCheck and type(check) == "table" and #check or -1
    return string.format("copied %s -> %s: %d saves; replayed %d dialog nodes and %d save serials; the new log now holds %d",
        fromStem, toStem, #saves, counts[kTags[1]], counts[kTags[2]], inLog)
end

function R.Wrap(name, makeWrapper)
    local current = G(name)
    if type(current) ~= "function" then
        return false
    end
    if R.wrappers[name] == current then
        return true
    end
    R.originals[name] = current
    local w = makeWrapper(current)
    R.wrappers[name] = w
    _G[name] = w
    return true
end

local function refuseOutsideCopy(name)
    return R.Wrap(name, function(orig)
        return function(...)
            if isSeason2() and not R.copying then
                notify(kRefused)
                return
            end
            return orig(...)
        end
    end)
end

function R.Install()
    -- The picker: another file runs the copy. An empty one has nothing to overwrite, so it skips the
    -- stock confirmation and goes straight to the overwrite (which copies first, below).
    R.Wrap("SaveSlot_Choose", function(orig)
        return function(filename, ...)
            if isSeason2() and upvalue(orig, "mbReplay") then
                local okPanel, panel = try("CoverFlow_GetCenterPanel")
                if okPanel and type(panel) == "table" and type(panel.slotname) == "string"
                    and not isCurrentSlot(panel.slotname .. ".bundle") then
                    local okEmpty, empty = false, false
                    if type(panel.isEmpty) == "function" then
                        okEmpty, empty = pcall(panel.isEmpty)
                    end
                    if okEmpty and empty then
                        return SaveSlot_Overwrite(panel.slotname .. ".bundle")
                    end
                end
            end
            return orig(filename, ...)
        end
    end)
    -- The overwrite: into another file, copy first and then overwrite in place in the copy.
    R.Wrap("SaveSlot_Overwrite", function(orig)
        return function(slot, ...)
            if isSeason2() and type(slot) == "string" and not isCurrentSlot(slot) and not R.copying then
                local from = currentSlot()
                local ok, result = pcall(R.CopyWithHistory, from, slot)
                R.copying = false
                if not ok then
                    report("copy failed: " .. tostring(result))
                    notify(kFailed)
                    return
                end
                report(result)
                R.saveMap = { from = stem(from), to = stem(slot) }
                return orig(currentSlot(), ...)
            end
            return orig(slot, ...)
        end
    end)
    -- Revert and restart run in the current file; a picked save of the source file is the copy's.
    R.Wrap("SaveLoad_Revert", function(orig)
        return function(save, newSlot, bDontSave, ...)
            if isSeason2() and not R.copying then
                if newSlot ~= nil then
                    if not isCurrentSlot(newSlot) then
                        notify(kRefused)
                        return currentSlot()
                    end
                    newSlot = nil
                end
                if R.saveMap and type(save) == "string" then
                    save = renamed(save, R.saveMap.from, R.saveMap.to)
                    R.saveMap = nil
                end
            end
            return orig(save, newSlot, bDontSave, ...)
        end
    end)
    R.Wrap("SaveLoad_RestartEpisode", function(orig)
        return function(episode, additionalEpisodes, bDontSave, newSlot, ...)
            if newSlot ~= nil and isSeason2() and not R.copying then
                if not isCurrentSlot(newSlot) then
                    notify(kRefused)
                    return
                end
                newSlot = nil
            end
            R.saveMap = nil
            return orig(episode, additionalEpisodes, bDontSave, newSlot, ...)
        end
    end)
    -- The stock copies share the log, so they only run inside the copy above (which uses none of them).
    refuseOutsideCopy("SaveLoad_Copy")
    refuseOutsideCopy("SaveLoad_Branch")
    refuseOutsideCopy("SaveLoad_BranchAndRestartEpisode")
end

if type(require) == "function" and require ~= R.requireWrapper then
    local baseRequire = require
    R.requireWrapper = function(...)
        local result = baseRequire(...)
        pcall(R.Install)
        return result
    end
    require = R.requireWrapper
end

pcall(R.Install)
