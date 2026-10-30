-- TWDRewind.lua
-- Chapter rewind for Season 3 (A New Frontier) and Season 4 (The Final Season) of
-- The Walking Dead: The Telltale Definitive Series.
--
-- Loaded by:
--   DebugLoader.lua       required by every season's Menu_Main.lua and by BootTitle.lua (a file the
--                         retail game does not ship)
--   GameOverrides.lua     the mod's wrapper of Season 4's own file, required by every Season 4 episode
-- Because require() runs a file only once, this file wraps require itself and re-checks its hooks
-- after every later require, so it installs them as soon as SaveLoad.lua / Menu_Episodes.lua
-- exist. No stock script is replaced; a few global functions are wrapped.
--
-- Two parts:
--
--   Rewind points. Seasons 3 and 4 call Checkpoint("node") without a chapter ID, so their
--   SaveLoad_Checkpoint only ever overwrites the autosave; the standalone games and the
--   Definitive Series never had anything to rewind to. Michonne passes a chapter ID, which makes
--   the same SaveLoad_Checkpoint write a numbered save (_wdm_saveSlot1_checkpointN.bundle). This
--   mod passes the scene's dialog name as the chapter ID for the first checkpoint of each scene,
--   so Seasons 3 and 4 write one numbered save per scene; every other checkpoint stays an autosave.
--
--   Menu. Season 3: the episode's "More Options" popup gets a "Rewind" entry that opens the
--   rewind list, drawn in the stock ui_popupMoreOptions scene. Season 4: the episode list gets a
--   "Rewind" legend entry (left face button), and "Restart Episode" opens the rewind points too,
--   straight into a picture view of the latest one (Previous / Next, and the list on Tab / Y); the
--   first point is the stock restart. Picking a save runs SaveLoad_Revert, which deletes every later save
--   like the original games' rewind, then the season's own Continue, which loads the newest save:
--   the one that was picked.
--
-- Everything is guarded so that a missing function makes the mod do nothing rather than break the
-- game. Seasons 1, 2 and Michonne are left alone (Season 2 is handled by the patched
-- Menu_chapters.lua in the other archive).

TWDRewind = TWDRewind or {}
local R = TWDRewind
R.version = "2.1.0"

local kMaxButtons = 4               -- buttons that fit inside the popup window (Back/More included)
local kButtonPadding = 0.04         -- gap between buttons (the stock popup uses 0.1)
local kInterceptRestartS4 = true    -- Season 4: "Restart Episode" opens the rewind list first

-- The popup's buttons fit about 28 characters on one line; longer text wraps and the second line
-- is cut off, so every label is kept to kMaxLabel.
local kMaxLabel = 28
local kText = {
    rewind = "Rewind",
    saved = "Saved: %s",
    nextPage = "More...",
    prevPage = "Back...",
    restart = "From the beginning",
    none = "No rewind points yet",
    confirm = "Yes, rewind here",
    cancel = "Cancel",
    -- Season 4 picture view
    viewMessage = "%s\n\nRewind point %d of %d\n\nLeft / Right arrows: browse. Tab: all points.",
    previous = "Previous",
    rewindHere = "Rewind here",
    next = "Next",
    allPoints = "All points",
}

local function fit(s)
    if string.len(s) > kMaxLabel then
        return string.sub(s, 1, kMaxLabel - 3) .. "..."
    end
    return s
end

local function log(msg)
    pcall(print, "[TWDRewind] " .. tostring(msg))
end

local function G(name)
    return rawget(_G, name)
end

-- Calls a global function if it exists. Returns ok, results...
local function try(name, ...)
    local f = G(name)
    if type(f) ~= "function" then
        return false
    end
    return pcall(f, ...)
end

---------------------------------------------------------------------------------------------
-- Season detection: the save slot name is "wd3_saveslotN.bundle" / "wd4_saveslotN.bundle".
---------------------------------------------------------------------------------------------

function R.Season()
    local ok, slot = try("SaveLoad_GetSlot")
    if ok and type(slot) == "string" then
        local s = string.lower(slot)
        if string.find(s, "wd3_", 1, true) == 1 then
            return 3
        elseif string.find(s, "wd4_", 1, true) == 1 then
            return 4
        end
    end
    return nil
end

local function seasonSupported()
    local season = R.Season()
    return season == 3 or season == 4
end

---------------------------------------------------------------------------------------------
-- Rewind points
---------------------------------------------------------------------------------------------

-- Every save of the slot except the autosave, oldest first; with ep, only that episode's.
-- (Same filter as Michonne's Menu_Rewind.lua.)
function R.GetCheckpoints(ep)
    local list = {}
    local ok, saves = try("SaveLoad_GetSaves", nil, ep, true)
    if not ok or type(saves) ~= "table" then
        return list
    end
    for _, save in ipairs(saves) do
        if save then
            local okAuto, isAuto = try("SaveLoad_IsAutoSave", save)
            if okAuto and not isAuto then
                table.insert(list, save)
            end
        end
    end
    return list
end

function R.CanRewind(ep)
    if type(ep) ~= "number" or ep < 1 or not seasonSupported() then
        return false
    end
    if G("SaveLoad_Revert") == nil or G("Menu_Episodes_Continue") == nil then
        return false
    end
    if #R.GetCheckpoints(ep) > 0 then
        return true
    end
    local ok, points = pcall(R.ScenePoints, ep)
    return ok and #points > 0
end

---------------------------------------------------------------------------------------------
-- Scene points rebuilt from the event log
--
-- Seasons 3 and 4 log every playthrough to "_wd3/4_saveslotN_id.estore": Begin Episode, Start Scene
-- (data: the scene name), Executing Dialog Node, Dialog Choice, Checkpoint, Save Serial (one per save,
-- unique number) and so on. Choices from earlier episodes and the dialog nodes already seen are read
-- back from that log, which is how the stock game restarts an episode without a save.
--
-- So any scene the player reached can be rewound to: cut the log at the last save before that scene
-- (EventLog_TruncateAtSave, the call the game makes when loading a save), then start the episode in
-- that scene. The scenes and how to enter them come from Telltale's developer scene table for each
-- episode (TWDRewindScenes.lua); only its act number and "entered" flags are applied, never the
-- test choices some developer entries set.
---------------------------------------------------------------------------------------------

pcall(require, "TWDRewindScenes.lua")

local function logFile()
    local ok, name = try("EventLog_GetLogName")
    if not ok or type(name) ~= "string" then
        return nil
    end
    local okExt, file = try("FileSetExtension", name, "estore")
    return okExt and file or nil
end

local function queryLog(file, query)
    local ok, result = try("QueryEventLog", file, query)
    if ok and type(result) == "table" then
        return result
    end
    return {}
end

local function byId(a, b)
    return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
end

local function sceneKey(name)
    if type(name) ~= "string" then
        return nil
    end
    return (string.gsub(string.lower(name), "%.scene$", ""))
end

-- Scene points of an episode, in play order: { label, name (scene table label), script, command, act, serial }.
function R.ScenePoints(ep)
    local season = R.Season()
    local tbl = TWDRewindScenes and TWDRewindScenes[season] and TWDRewindScenes[season][ep]
    local file = logFile()
    if not tbl or not file then
        return {}
    end
    -- This playthrough of the episode: from its Begin Episode to the next episode's. A rewind starts
    -- the episode again, which logs another Begin Episode after the part of the log it kept, so a run
    -- of Begin Episode events for this episode with nothing else between them is one playthrough and
    -- it starts at the first of them. (The stock restart cuts the log at the episode start instead.)
    local begins = queryLog(file, { { tag = "Begin Episode" } })
    table.sort(begins, byId)
    local first, stop, latest
    for i, e in ipairs(begins) do
        if tonumber(e.data) == ep then
            latest = i
        end
    end
    if latest == nil then
        return {}
    end
    first = begins[latest].id
    for i = latest - 1, 1, -1 do
        if tonumber(begins[i].data) ~= ep then
            break
        end
        first = begins[i].id
    end
    for _, e in ipairs(begins) do
        if tonumber(e.data) == ep + 1 and e.id > first and (stop == nil or e.id < stop) then
            stop = e.id
        end
    end
    -- "Start Scene" stores the scene as a symbol (a hash of "adv_x.scene"), so ask for each scene of
    -- the table by name rather than reading names back.
    local scenes, asked = {}, {}
    for _, entry in ipairs(tbl) do
        local key = string.lower(entry.scene)
        if not asked[key] then
            asked[key] = true
            for _, e in ipairs(queryLog(file, { { tag = "Start Scene", data = entry.scene .. ".scene" } })) do
                if e.id > first and (stop == nil or e.id < stop) then
                    table.insert(scenes, { id = e.id, data = key })
                end
            end
        end
    end
    table.sort(scenes, byId)
    local serials = queryLog(file, { { tag = "Save Serial" } })
    table.sort(serials, byId)

    -- Match each scene visit to the next unused developer entry for that scene, acts in order.
    local used, act, points, labelCount = {}, 1, {}, {}
    for _, ev in ipairs(scenes) do
        local key, pick = sceneKey(ev.data), nil
        for i, entry in ipairs(tbl) do
            if not used[i] and string.lower(entry.scene) == key and entry.act >= act
                and (pick == nil or entry.act < tbl[pick].act) then
                pick = i
            end
        end
        if pick then
            used[pick] = true
            act = tbl[pick].act
            local serial
            for _, s in ipairs(serials) do
                if s.id >= ev.id then
                    break
                end
                if s.id > first then
                    serial = s.data
                end
            end
            -- No save between the episode start and this scene: that's "From the beginning".
            if serial then
                local entry = tbl[pick]
                -- "Bell Tower - Violet" / "- Louis" are developer test variants of one scene; which one
                -- the player had isn't known, so drop the suffix when the scene has several in this act.
                local label = entry.label
                for i, other in ipairs(tbl) do
                    if i ~= pick and other.act == entry.act and string.lower(other.scene) == string.lower(entry.scene) then
                        label = string.match(label, "^(.-)%s+%-%s+") or label
                        break
                    end
                end
                table.insert(points, { label = label, name = entry.label, step = pick, script = entry.script,
                                       command = entry.command, act = entry.act, serial = serial })
                labelCount[label] = (labelCount[label] or 0) + 1
            end
        end
    end
    for _, p in ipairs(points) do
        if labelCount[p.label] > 1 then
            p.label = p.label .. " (act " .. p.act .. ")"
        end
    end
    return points
end

-- Keep only the act and "entered" flags of a developer entry's setup; drop its test choices.
local function safeCommand(command)
    local out = {}
    for stmt in string.gmatch(command or "", "[^;]+") do
        local key = string.match(stmt, "^%s*LogicSet%(%s*([^,]-)%s*,")
        if key and (key == "kAct" or string.find(string.lower(key), "entered", 1, true)) then
            table.insert(out, (string.gsub(stmt, "^%s+", "")) .. ";")
        end
    end
    return table.concat(out, " ")
end

-- String values kept in the preferences (prefs.prop), which survive switching between menu and episode.
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

local function getPref(key)
    local ok, prefs = try("GetPreferences")
    if ok and prefs then
        local okGet, value = pcall(PropertyGet, prefs, key)
        if okGet and type(value) == "string" then
            return value
        end
    end
    return nil
end

-- The scene to start in survives the switch from the menu into the episode in the preferences.
local kPendingKey = "TWDRewind - Pending Scene"

function R.SetPending(p)
    R.pending = p
    local value = ""
    if p then
        value = p.project .. "\n" .. p.script .. "\n" .. (p.command or "")
    end
    setPref(kPendingKey, value)
end

function R.GetPending()
    if R.pending then
        return R.pending
    end
    local value = getPref(kPendingKey)
    if value and value ~= "" then
        local project, script, command = string.match(value, "^([^\n]*)\n([^\n]*)\n([^\n]*)")
        if project and project ~= "" then
            R.pending = { project = project, script = script, command = command }
            return R.pending
        end
    end
    return nil
end

local function now()
    local ok, t = try("GetTotalTime")
    return ok and tonumber(t) or 0
end

-- Starting an episode is a full Lua state reset (ResetGame boots the episode's start script in a new
-- state). The menu's state answers the first-script lookup (hookEpisodeStart), which is what makes
-- the episode boot straight into the chosen scene; the episode's own state picks the jump up again
-- from the preferences when it loads this file (see the end of the file) and arms it here. The
-- entry's act / entered flags are applied when its scene starts: Game_StartScene (hooked below)
-- runs them just before the scene's own start logic, and only then is the jump used up.
function R.ArmPending(p)
    if R.armed then
        return
    end
    R.armed = true
    local done = false
    local function apply()
        if done then
            return
        end
        done = true
        R.applyPending = nil
        if p.command and p.command ~= "" then
            local ok, err = pcall(DoString, p.command)
            if not ok then
                log("scene setup failed: " .. tostring(err))
            end
        end
        R.pending = nil
        R.armed = false
        setPref(kPendingKey, "")
    end
    R.applyPending = apply
end

-- The jump pending for the episode this state runs, if any (the menu answered its first-script lookup).
function R.ArmIfPending()
    local p = R.GetPending()
    local okCur, cur = try("SubProject_GetCurrent")
    if p and okCur and type(cur) == "string" and string.lower(cur) == string.lower(p.project) then
        R.ArmPending(p)
    end
end

-- Called by the Game_StartScene hook just before a scene's start logic runs.
function R.BeforeSceneStart()
    -- In case loading this file was too early to see the jump (preferences / project not set up yet).
    if not R.applyPending and not R.checkedAtSceneStart then
        R.checkedAtSceneStart = true
        R.ArmIfPending()
    end
    if R.applyPending then
        R.applyPending()
    end
end

-- Game_SceneOpen queues "<entry function>()" to run once the scene is open, and Game_OnSceneOpened
-- calls Game_StartScene by its global name, so a wrapper in _G is used.
local function hookSceneStart()
    return R.Wrap("Game_StartScene", function(orig)
        return function(...)
            local ok, err = pcall(R.BeforeSceneStart)
            if not ok then
                log("scene start hook failed: " .. tostring(err))
            end
            return orig(...)
        end
    end)
end

-- Menu side: SubProject_StartEpisode asks for the episode's first script before switching to it;
-- answer with the chosen scene's script while a jump is pending for that episode. The jump stays in
-- the preferences for the episode's own state.
local function hookEpisodeStart()
    return R.Wrap("SubProject_GetEpisodeFirstScript", function(orig)
        return function(projectName, ...)
            local p = R.GetPending()
            if p then
                local current = projectName
                if current == nil then
                    local okCur, cur = try("SubProject_GetCurrent")
                    current = okCur and cur or nil
                end
                if type(current) == "string" and string.lower(current) == string.lower(p.project) then
                    return p.script
                end
            end
            return orig(projectName, ...)
        end
    end)
end

-- Same menu-side steps as the stock restart (Menu_Episodes_Restart), without its log cut at the
-- episode start: SaveLoad_RestartEpisode(ep, bDontSave = true) only deletes this and later episodes'
-- saves; the log is cut at the chosen save instead, then the slot metadata is rebuilt from it.
function TWDRewind_JumpDo(index)
    local st = R.state
    TWDRewind_Close()
    local point = st and st.points and st.points[index]
    if not point then
        return
    end
    local ep = st.ep
    ThreadStart(function()
        WaitForNextFrame()
        log("rewinding episode " .. tostring(ep) .. " to scene " .. point.script .. " (save serial " .. tostring(point.serial) .. ")")
        local okProject, project = try("Menu_GetFullEpisodeName", ep)
        if not okProject or type(project) ~= "string" then
            log("no project name for episode " .. tostring(ep))
            return
        end
        local slot = SaveLoad_GetSlot()
        local ok, err = pcall(SaveLoad_RestartEpisode, ep, true)
        if not ok then
            log("deleting saves failed: " .. tostring(err))
            return
        end
        Yield()
        ok, err = pcall(EventLog_TruncateAtSave, point.serial)
        if not ok then
            log("cutting the event log failed: " .. tostring(err))
            return
        end
        Yield()
        pcall(updateMetadataAfterDelete, slot, "", nil)
        Yield()
        pcall(SaveLoad_SetEpisode, ep)
        R.SetPending({ project = project, script = point.script, command = safeCommand(point.command) })
        R.LaunchEpisode(ep)
    end)
end

-- Leave the menu the way the stock Restart does, then start the episode (in a thread).
function R.LaunchEpisode(ep)
    R.WaitForCloudSync()
    pcall(WidgetInputHandler_EnableInput, false)
    if G("ResourceExists") and ResourceExists("ui_menuMain_hide.chore") then
        pcall(ChorePlayAndWait, "ui_menuMain_hide.chore")
    end
    local okScenes, scenes = try("SceneGetActiveSceneNames", true)
    if okScenes and type(scenes) == "table" then
        for _, s in ipairs(scenes) do
            pcall(SceneHide, s, true)
        end
    end
    Menu_StartEpisode(ep, true)
end

-- "env_boardingSchoolBasement_act3" -> "Boarding School Basement (act 3)"
local function prettyScene(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    local s = string.gsub(id, "%.dlog$", "")
    s = string.gsub(s, "^env_", "")
    s = string.gsub(s, "^adv_", "")
    local act = string.match(s, "_act(%d+)$")
    s = string.gsub(s, "_act%d+$", "")
    s = string.gsub(s, "_", " ")
    s = string.gsub(s, "(%l)(%u)", "%1 %2")
    s = string.gsub(s, "^%l", string.upper)
    if act then
        s = s .. " (act " .. act .. ")"
    end
    return s
end

local function pointName(save)
    local ok, id = try("SaveLoad_GetChapterID", save)
    if ok then
        return prettyScene(id)
    end
    return nil
end

-- The scene table entry (its index in the episode's table) a save was made in, from its chapter ID:
-- the dialog name "env_riverShorelineNight_act1" belongs to scene "adv_riverShorelineNight", act 1.
-- nil if no entry matches.
local function stepOfSave(ep, save)
    local season = R.Season()
    local tbl = TWDRewindScenes and TWDRewindScenes[season] and TWDRewindScenes[season][ep]
    local ok, id = try("SaveLoad_GetChapterID", save)
    if not tbl or not ok or type(id) ~= "string" then
        return nil
    end
    local s = string.lower(id)
    s = string.gsub(s, "%.dlog$", "")
    s = string.gsub(s, "^env_", "")
    s = string.gsub(s, "^adv_", "")
    local act = tonumber(string.match(s, "_act(%d+)$"))
    s = string.gsub(s, "_act%d+$", "")
    local first
    for i, entry in ipairs(tbl) do
        local scene = string.gsub(string.lower(entry.scene), "^adv_", "")
        if scene == s then
            if act == nil or entry.act == act then
                return i
            end
            first = first or i
        end
    end
    return first
end

local function sceneOf(dialogFile)
    local name = dialogFile
    if type(name) ~= "string" then
        local ok, n = try("ResourceGetName", dialogFile)
        name = ok and n or nil
    end
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return name
end

-- Chapter ID of the newest numbered save in the slot (nil if there is none).
local function lastPointScene()
    local points = R.GetCheckpoints(nil)
    local last = points[#points]
    if last then
        local ok, id = try("SaveLoad_GetChapterID", last)
        if ok and type(id) == "string" then
            return id
        end
    end
    return nil
end

-- SaveLoad_Checkpoint(dialogFile, dialogNode, chapterID): give the first checkpoint of each scene
-- a chapter ID so the stock code saves it as a numbered checkpoint instead of the autosave.
local function hookCheckpoints()
    return R.Wrap("SaveLoad_Checkpoint", function(orig)
        return function(dialogFile, dialogNode, chapterID, ...)
            if (chapterID == nil or chapterID == "") and dialogFile and dialogFile ~= ""
                and dialogNode and dialogNode ~= "" and seasonSupported() then
                local ok, scene = pcall(sceneOf, dialogFile)
                if ok and scene then
                    local okLast, last = pcall(lastPointScene)
                    if okLast and (last == nil or string.lower(last) ~= string.lower(scene)) then
                        chapterID = scene
                    end
                end
            end
            return orig(dialogFile, dialogNode, chapterID, ...)
        end
    end)
end

---------------------------------------------------------------------------------------------
-- Popup: a copy of the stock "More Options" popup (Menu_Rewind_Context / Populate in the
-- shared Menu_Rewind.lua) that takes its option list as an argument.
---------------------------------------------------------------------------------------------

local function contextScene()
    local ok, small = try("IsPlatformSmallScreen")
    if ok and small then
        return "ui_popupMoreOptionsBig.scene"
    end
    return "ui_popupMoreOptions.scene"
end

R.ctx = nil
R.ctxButtons = {}

-- Pictures, generated from src/pictures.json: TWDRewindPictures[season] = { kind, steps[ep][scene table
-- entry], labels[scene table label], episodes[ep] }, most specific first. Season 3 ("strip"): the picture strip of its own More Options window, which
-- follows the highlighted row. Season 4 ("background"): picking a row opens the scene in the stock
-- picture popup (Menu_PopupWindow, as used for the Crowd Play intro); see R.View.
pcall(require, "TWDRewindPictures.lua")

local function pictures()
    return TWDRewindPictures and TWDRewindPictures[R.Season()]
end

function R.Picture(ep, label, step)
    local t = pictures()
    if not t then
        return nil
    end
    return (step and t.steps and t.steps[ep] and t.steps[ep][step])
        or (label and t.labels and t.labels[label]) or (t.episodes and t.episodes[ep])
end

local function pictureKind()
    local t = pictures()
    return t and t.kind
end

local function agentName(agent)
    if type(agent) == "string" then
        return string.lower(agent)
    end
    local ok, name = try("AgentGetName", agent)
    return ok and type(name) == "string" and string.lower(name) or nil
end

local function showPicture(texture)
    if texture and texture ~= R.ctxPicture and pictureKind() == "strip" then
        R.ctxPicture = texture
        pcall(ShaderOverrideTexture, "ui_popupMoreOptions_window", "ui_popupMoreOptions_imageHolder.d3dtx", texture)
    end
end

local function isOpen()
    if R.ctx == nil then
        return false
    end
    local ok, current = try("Menu_GetCurrentMenu")
    if ok and current ~= R.ctx then
        -- Closed by something else (e.g. the menu stack was cleared).
        R.ctx = nil
        return false
    end
    return true
end

local function anchorBelowWindow(self)
    if R.ctx and R.ctx.agent then
        self:AnchorToAgent(R.ctx.agent, "center", "bottom")
    end
end

-- data = { title = <ui_menu.dlog node>, image = <texture or nil>, { label = <text>, action = <lua> }, ... }
function R.ShowPopup(data)
    if isOpen() then
        return
    end
    local scene = contextScene()
    if not AgentExists(scene) then
        MenuUtils_AddScene(scene)
    end
    local ctx = Menu_Create(Menu, "ui_popupMoreOptions_reference")
    R.ctx = ctx
    ctx.modal = true

    ctx.Show = function(self)
        Widget.Show(self)
        if not Input_UseCursor() then
            local btn = self:GetDefaultButton()
            if btn then
                pcall(function() btn:Select(true) end)
            end
        end
    end

    ctx.Hide = function(self)
        if R.ctxSceneObj then
            try("Buttons_SetSelectedCallback", R.ctxSceneObj, nil)
            R.ctxSceneObj = nil
        end
        Menu.Hide(self, true, true)
        PropertyRemove(AgentGetRuntimeProperties(scene), "Scene Render Priority")
    end

    ctx.GetDefaultButton = function(self)
        return AgentFind("ui_popupMoreOptions_list_optbtn1_button")
    end

    ctx.OnWidgetInputChange = function(self, bUseCursor)
        if bUseCursor then
            ChorePlay("ui_popupMoreOptions_closeButtonOn.chore")
        else
            ChorePlay("ui_popupMoreOptions_closeButtonOff.chore")
        end
        local prop
        if IsPlatformSmallScreen() then
            prop = "material_ui_popupMoreOptionsBig_window_popupLegendBackground_M - Visible"
        else
            prop = "material_ui_popupMoreOptionsWindow_ui_popupLegendBackground_M - Visible"
        end
        if AgentHasProperty("ui_popupMoreOptions_window", prop) then
            AgentSetProperty("ui_popupMoreOptions_window", prop, not bUseCursor)
        end
    end

    ctx.Populate = function(self)
        if data.title then
            AgentSetProperty("ui_popupMoreOptions_labelEpisode", "Text Dialog 2.0 Node Name", data.title)
        end
        R.ctxPicture = nil
        showPicture(data.image)
        if #data == 0 then
            return
        end

        local listMenu = Menu_Add(SparseMenu, "list", kButtonPadding, nil, "top")
        listMenu.isVertical = true
        listMenu.widgets = {}
        R.ctxButtons = {}
        local pictureOf = {}
        for i, opt in ipairs(data) do
            local label = opt.label or ""
            local action = opt.action or "TWDRewind_Noop()"
            local btn = Menu_Insert(listMenu, PopupSplashButton, "optbtn" .. i, label, action)
            local clickAgent = Clone_Find(btn.agent, "_button")
            AgentSetProperty(clickAgent, "Button - Command", action)
            local clickLabel = Clone_Find(btn.agent, "_label")
            AgentSetProperty(clickLabel, "Text String", label)
            R.ctxButtons[i] = btn
            local key = agentName(clickAgent)
            if key and opt.image then
                pictureOf[key] = opt.image
            end
        end
        -- Season 3: the strip follows the highlighted row (mouse or controller); Back/More keep the
        -- current picture. The callback is stored on the scene object (what Widget:GetScene() returns).
        if pictureKind() == "strip" then
            local okScene, sceneObj = try("AgentGetScene", Clone_Find(R.ctxButtons[1].agent, "_button"))
            if okScene and sceneObj then
                local okCb = try("Buttons_SetSelectedCallback", sceneObj, function(buttonAgent, bSelect)
                    if bSelect then
                        local key = agentName(buttonAgent)
                        if key and pictureOf[key] then
                            showPicture(pictureOf[key])
                        end
                    end
                end)
                R.ctxSceneObj = okCb and sceneObj or nil
            end
        end

        local legendMenu = Menu_Add(SparseMenu, "legendMenu", 0.25)
        legendMenu.isVertical = false
        legendMenu.Place = anchorBelowWindow
        if AgentFind("ui_popupMoreOptions_closeButton") then
            AgentSetProperty("ui_popupMoreOptions_closeButton", "Button - Command", "TWDRewind_Close()")
        else
            Menu_Insert(legendMenu, LegendButtonBack, "legendButton_back", "TWDRewind_Close()", "legend_close")
        end

        local legendWidget = Menu_Add(Legend)
        legendWidget.Place = anchorBelowWindow
        Legend_Add("faceButtonDown", "legend_select")
        Legend_Add("faceButtonRight", "legend_close", "TWDRewind_Close()")
    end

    Menu_Push(ctx)
end

function R.ClosePopup()
    if R.ctx ~= nil then
        local ok, current = try("Menu_GetCurrentMenu")
        if ok and current == R.ctx then
            Menu_Pop()
        end
        R.ctx = nil
    end
end

-- Replace whatever popup is open with a new one on the next frame (a button's command runs
-- inside the popup that is being closed).
local function reopen(data)
    R.ClosePopup()
    ThreadStart(function()
        WaitForNextFrame()
        local ok, err = pcall(R.ShowPopup, data)
        if not ok then
            log("ShowPopup failed: " .. tostring(err))
        end
    end)
end

---------------------------------------------------------------------------------------------
-- Screens
---------------------------------------------------------------------------------------------

local function popupTitle(ep)
    local ok, small = try("IsPlatformSmallScreen")
    if ok and small then
        return "label_episode" .. ep
    end
    return "episodes_panelTitleEpisode" .. ep
end

-- R.state = { ep, image, items, points, saves, names, savedBase }
--   items: the list rows in order; points: scene points rebuilt from the event log;
--   saves/names: numbered saves kept while playing with the mod; savedBase: item index before them.
R.state = nil

-- Splits the items into pages of at most kMaxButtons buttons, counting the Back and More buttons
-- a page needs. The list has no Cancel button: the window's X (or Back/Esc) closes it.
local function paginate(count)
    local pages, first = {}, 1
    while first <= count do
        local room = kMaxButtons - (first > 1 and 1 or 0)
        local last
        if count - first + 1 <= room then
            last = count
        else
            last = first + room - 2     -- leave room for More
        end
        table.insert(pages, { first = first, last = last })
        first = last + 1
    end
    return pages
end

local function pageOf(itemIndex)
    for page, range in ipairs(R.state.pages) do
        if itemIndex <= range.last then
            return page
        end
    end
    return 1
end

local function buildList(page)
    local st = R.state
    local range = st.pages[page] or st.pages[1]
    local data = { title = popupTitle(st.ep), image = st.items[range.first].image or st.image }
    if page > 1 then
        table.insert(data, { label = kText.prevPage, action = "TWDRewind_Page(" .. (page - 1) .. ")" })
    end
    for i = range.first, range.last do
        table.insert(data, st.items[i])
    end
    if st.pages[page + 1] then
        table.insert(data, { label = kText.nextPage, action = "TWDRewind_Page(" .. (page + 1) .. ")" })
    end
    return data
end

-- The picture of one scene table entry (Season 4's screenshots), or nil.
local function stepPicture(ep, step)
    local t = pictures()
    return step and t and t.steps and t.steps[ep] and t.steps[ep][step] or nil
end

-- Opens an episode's rewind points. image: the episode's picture (Season 3 passes the one the stock
-- More Options popup uses). withRestart: add the stock restart as the first point.
-- Season 3 shows the list; Season 4 opens the picture view at the latest point, the list being one
-- key away. Every point carries a picture: its scene's, or the episode's.
function R.Open(ep, image, withRestart)
    local allSaves = R.GetCheckpoints(ep)
    local okPoints, points = pcall(R.ScenePoints, ep)
    if not okPoints then
        log("ScenePoints failed: " .. tostring(points))
        points = {}
    end
    if #allSaves == 0 and #points == 0 and not withRestart then
        return
    end
    image = image or R.Picture(ep)
    -- The mod saves at the start of each scene, so most scenes would be listed twice: as a scene
    -- point and as that save. Keep the scene point; keep the saves no scene point stands for.
    local pointSteps = {}
    for _, p in ipairs(points) do
        pointSteps[p.step] = true
    end
    local saves, saveSteps = {}, {}
    for _, save in ipairs(allSaves) do
        local okStep, step = pcall(stepOfSave, ep, save)
        step = okStep and step or nil
        if not (step and pointSteps[step]) then
            table.insert(saves, save)
            saveSteps[#saves] = step
        end
    end
    -- items: label (list row), action (row command), image, and for rewind points: text (full name) and
    -- go (the rewind itself). Season 4 rows open the picture view; Season 3 rows the confirm screen.
    local items, names = {}, {}
    local lastPoint, lastSave
    if withRestart then
        table.insert(items, { label = kText.restart, action = "TWDRewind_Restart()", image = stepPicture(ep, 1) or image,
                              text = kText.restart, go = "TWDRewind_Restart()" })
    end
    for i, p in ipairs(points) do
        table.insert(items, { label = fit(p.label), action = "TWDRewind_PickScene(" .. i .. ")",
                              image = R.Picture(ep, p.name, p.step) or image, text = p.label,
                              go = "TWDRewind_JumpDo(" .. i .. ")" })
        lastPoint = #items
    end
    local savedBase = #items
    for i, save in ipairs(saves) do
        names[i] = pointName(save)
        local text = string.format(kText.saved, names[i] or ("point " .. i))
        table.insert(items, { label = fit(text), action = "TWDRewind_Pick(" .. i .. ")",
                              image = stepPicture(ep, saveSteps[i]) or image,
                              text = text, go = "TWDRewind_Do(" .. i .. ")" })
        lastSave = #items
    end
    if #points == 0 and #saves == 0 then
        table.insert(items, { label = kText.none, action = "TWDRewind_Noop()", image = image })
    end
    -- Numbered as the picture view counts them ("Rewind point 6 of 10").
    local n = 0
    for _, item in ipairs(items) do
        if item.go then
            n = n + 1
            item.label = fit(n .. ". " .. item.text)
        end
    end
    -- Rows an add-on adds (see the end of the file); the released mod has none.
    if R.ExtraRows then
        local okRows, errRows = pcall(R.ExtraRows, ep, items, image)
        if not okRows then
            log("extra rows failed: " .. tostring(errRows))
        end
    end
    if pictureKind() == "background" then
        for i, item in ipairs(items) do
            if item.go then
                item.action = "TWDRewind_View(" .. i .. ")"
            end
        end
    end
    R.state = { ep = ep, image = image, items = items, points = points, saves = saves, names = names,
                savedBase = savedBase, pages = paginate(#items) }
    -- Season 3: we are called from inside the stock More Options popup; close it first.
    try("Menu_Episodes_DismissMoreOptions")
    -- Season 4: straight to the picture of the latest point (the scene reached last, else the
    -- newest save, else the restart).
    local start = lastPoint or lastSave or (withRestart and 1) or nil
    if pictureKind() == "background" and start then
        R.View(start)
        return
    end
    reopen(buildList(1))
end

function TWDRewind_Open(ep)
    local ok, err = pcall(R.Open, ep, R.images and R.images[ep], true)
    if not ok then
        log("Open failed: " .. tostring(err))
    end
end

function TWDRewind_OpenS4(ep)
    local ok, err = pcall(R.Open, ep, nil, kInterceptRestartS4)
    if not ok then
        log("Open failed: " .. tostring(err))
    end
end

function TWDRewind_Page(page)
    if R.state then
        reopen(buildList(page))
    end
end

local function confirmScreen(label, doAction, itemIndex)
    local st = R.state
    local image = st.items[itemIndex] and st.items[itemIndex].image or st.image
    reopen({
        title = popupTitle(st.ep), image = image,
        { label = label, action = "TWDRewind_Noop()", image = image },
        { label = kText.confirm, action = doAction, image = image },
        { label = kText.cancel, action = "TWDRewind_Page(" .. pageOf(itemIndex) .. ")" },
    })
end

-- A numbered save kept while playing with the mod: exact state.
function TWDRewind_Pick(index)
    local st = R.state
    if st and st.saves[index] then
        confirmScreen(st.items[st.savedBase + index].label, "TWDRewind_Do(" .. index .. ")", st.savedBase + index)
    end
end

-- A scene point rebuilt from the event log.
function TWDRewind_PickScene(index)
    local st = R.state
    if st and st.points[index] then
        local itemIndex = index + (st.items[1] and st.items[1].action == "TWDRewind_Restart()" and 1 or 0)
        confirmScreen(fit(st.points[index].label), "TWDRewind_JumpDo(" .. index .. ")", itemIndex)
    end
end

-- Windows virtual-key codes, read with the engine's InputPCIsVKeyPressed (as Input.lua does, twice).
local kVkTab, kVkLeft, kVkRight = 0x09, 0x25, 0x27

local function keyDown(vk)
    pcall(InputPCIsVKeyPressed, vk)
    local ok, down = pcall(InputPCIsVKeyPressed, vk)
    return ok and down and true or false
end

-- Season 4: one rewind point at a time in the stock picture popup (Menu_PopupWindow, the one used for
-- the Crowd Play intro): its picture on the left, its name, and Previous / Next / Rewind here (it
-- takes three buttons). Previous and Next step through the episode's rewind points, wrapping around;
-- so do the Left / Right arrow keys and a controller's bumpers. Tab (Y) shows the list of all points,
-- Esc (B) closes. The popup's buttons run their command without closing it, hence the Menu_Pop() in
-- front. (Its text can't contain "<", which starts a text tag.)
function R.View(index)
    local st = R.state
    if not st then
        return
    end
    local order, pos = {}, nil
    for i, item in ipairs(st.items) do
        if item.go then
            table.insert(order, i)
            if i == index then
                pos = #order
            end
        end
    end
    if not pos then
        return
    end
    local item = st.items[index]
    local prev = order[(pos - 2) % #order + 1]
    local nextI = order[pos % #order + 1]
    local goPrev = "TWDRewind_View(" .. prev .. ")"
    local goNext = "TWDRewind_View(" .. nextI .. ")"
    local goList = "TWDRewind_Back(" .. index .. ")"
    -- Each view has its own token; the keyboard loop of an older view stops when it changes.
    R.viewToken = (R.viewToken or 0) + 1
    local token = R.viewToken
    R.ClosePopup()
    ThreadStart(function()
        WaitForNextFrame()
        if G("Menu_PopupWindow") == nil then
            pcall(require, "UI_PopupWindow.lua")
        end
        local ok, err = pcall(Menu_PopupWindow, {
            message = string.format(kText.viewMessage, item.text, pos, #order),
            texture = item.image,
            -- Previous first: the view opens at the latest point, so going back is the usual move,
            -- and a quick select press doesn't rewind.
            buttons = {
                { text = kText.previous, command = "Menu_Pop() " .. goPrev },
                { text = kText.next, command = "Menu_Pop() " .. goNext },
                { text = kText.rewindHere, command = "Menu_Pop() " .. item.go },
            },
            -- Controller (Season 4's own popups add legend entries the same way, see Menu_Main's
            -- legendOverride; the bumper names are UI_legend.lua's).
            legendOverride = {
                { button = "faceButtonDown", text = "legend_select" },
                { button = "shoulderButtonLeft", text = kText.previous, command = "Menu_Pop() " .. goPrev },
                { button = "shoulderButtonRight", text = kText.next, command = "Menu_Pop() " .. goNext },
                { button = "faceButtonUp", text = kText.allPoints, command = "Menu_Pop() " .. goList },
                { button = "faceButtonRight", text = "legend_close", command = "Menu_Pop() TWDRewind_Close()" },
            },
        })
        if not ok then
            log("View failed: " .. tostring(err))
            return
        end
        local okMenu, menu = try("Menu_GetCurrentMenu")
        if not okMenu or type(menu) ~= "table" then
            return
        end
        -- Keyboard: Esc closes (the legend only answers controller buttons).
        menu.OnEscape = function()
            Menu_Pop()
            TWDRewind_Close()
        end
        -- Keyboard: Left / Right browse, Tab shows the list. Polled while this view is the open menu.
        local held = true            -- ignore a key still down from the previous view
        while R.viewToken == token do
            local okCur, cur = try("Menu_GetCurrentMenu")
            if not okCur or cur ~= menu then
                break
            end
            local left, right, tab = keyDown(kVkLeft), keyDown(kVkRight), keyDown(kVkTab)
            if not (left or right or tab) then
                held = false
            elseif not held then
                Menu_Pop()
                if tab then
                    TWDRewind_Back(index)
                elseif left then
                    TWDRewind_View(prev)
                else
                    TWDRewind_View(nextI)
                end
                break
            end
            WaitForNextFrame()
        end
    end)
end

-- From the picture view to the list page that has that rewind point.
function TWDRewind_Back(index)
    if R.state then
        reopen(buildList(pageOf(index)))
    end
end

function TWDRewind_View(index)
    local ok, err = pcall(R.View, index)
    if not ok then
        log("View failed: " .. tostring(err))
    end
end

function TWDRewind_Close()
    R.ClosePopup()
    R.state = nil
end

function TWDRewind_Noop()
end

function TWDRewind_Restart()
    local st = R.state
    TWDRewind_Close()
    if st then
        R.RunRestart(st.ep)
    end
end

---------------------------------------------------------------------------------------------
-- The rewind itself (same sequence as Michonne's Menu_Rewind_DoRewind, then the season's own
-- Continue, which ends in Menu_LoadEpisode(ep, true) -> SaveLoad_AutoLoad()).
---------------------------------------------------------------------------------------------

local function waitForCloudSync()
    local okPrefs, prefs = try("GetPreferences")
    if not okPrefs or not prefs then
        return
    end
    local okEnabled, enabled = pcall(PropertyGet, prefs, "Menu - Enable Cloud Saves")
    if not okEnabled or not enabled then
        return
    end
    local okSlot, slot = try("SaveLoad_GetSlot")
    local okCloud, cloudSlot = pcall(PropertyGet, prefs, "Menu - Cloud Save Slot")
    if okSlot and okCloud and slot == cloudSlot then
        try("SaveLoad_SyncToCloudSave", false)
        while true do
            local okSync, syncing = try("SaveLoad_IsCloudSyncing")
            if not okSync or not syncing then
                break
            end
            WaitForNextFrame()
        end
    end
end

R.WaitForCloudSync = waitForCloudSync

function TWDRewind_Do(index)
    local st = R.state
    TWDRewind_Close()
    if not st or not st.saves[index] then
        return
    end
    local ep, save = st.ep, st.saves[index]
    ThreadStart(function()
        WaitForNextFrame()
        log("rewinding episode " .. tostring(ep) .. " to " .. tostring(save))
        try("CreateEventLogEvent", "User Rewind", "true", true)
        local ok, err = pcall(SaveLoad_Revert, save)
        if not ok then
            log("SaveLoad_Revert failed: " .. tostring(err))
            return
        end
        Yield()
        SaveLoad_SetEpisode(ep)
        Yield()
        waitForCloudSync()
        Menu_Episodes_Continue(ep, true)
    end)
end

---------------------------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------------------------

R.originals = R.originals or {}
R.wrappers = R.wrappers or {}

-- Replaces global `name` with makeWrapper(original), unless it is already our wrapper. Run again
-- after the stock file is reloaded, it wraps the new definition.
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

-- Season 3: "Rewind" entry in the episode's More Options popup.
local function hookSeason3()
    return R.Wrap("Menu_Episodes_GenerateMoreOptions", function(orig)
        return function(eltName, ...)
            local opts = orig(eltName, ...)
            if R.Season() == 3 and type(opts) == "table" and type(eltName) == "string" then
                local ep = tonumber(string.sub(eltName, -1, -1)) or 0
                local ok, can = pcall(R.CanRewind, ep)
                if ok and can then
                    R.images = R.images or {}
                    R.images[ep] = opts.image
                    table.insert(opts, { label = kText.rewind, action = "TWDRewind_Open(" .. ep .. ")" })
                end
            end
            return opts
        end
    end)
end

-- Finds a local variable a function closes over, by name (needs the debug library).
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

local function episodeOfWidget(w)
    if type(w) == "table" and type(w.episodeData) == "table" then
        return w.episodeData.episode
    end
    return nil
end

-- Season 4: legend entry on the episode list, and the Restart button opens the list.
local function hookSeason4()
    local okLegend = R.Wrap("Menu_Episodes_UpdateLegend", function(orig)
        return function(elementWidget, ...)
            local result = orig(elementWidget, ...)
            if R.Season() == 4 then
                local ep = episodeOfWidget(elementWidget)
                local ok, can = pcall(R.CanRewind, ep)
                if ok and can then
                    local legend = upvalue(orig, "mLegendWidget")
                    if legend then
                        pcall(Legend_UpdateAdd, legend, "faceButtonLeft", kText.rewind, "TWDRewind_OpenS4(" .. ep .. ")")
                    end
                end
            end
            return result
        end
    end)
    local okRestart = true
    if kInterceptRestartS4 then
        okRestart = R.Wrap("Menu_Episodes_Restart", function(orig)
            return function(ep, confirmed, ...)
                -- Opens even with no rewind points yet, so it's visible that the mod is loaded.
                if not confirmed and not R.bypassRestart and R.Season() == 4
                    and G("SaveLoad_Revert") ~= nil and type(ep) == "number" then
                    local okOpen, err = pcall(R.Open, ep, nil, true)
                    if okOpen then
                        return
                    end
                    log("Open failed: " .. tostring(err))
                end
                return orig(ep, confirmed, ...)
            end
        end)
    end
    return okLegend and okRestart
end

-- Runs the stock restart (with its own confirmation popup), skipping our interception.
function R.RunRestart(ep)
    local restart = R.originals["Menu_Episodes_Restart"] or G("Menu_Episodes_Restart")
    if restart then
        R.bypassRestart = true
        local ok, err = pcall(restart, ep, false, true)
        R.bypassRestart = false
        if not ok then
            log("restart failed: " .. tostring(err))
        end
    end
end

-- Wraps whatever is present. Every wrapper checks R.Season() each time it runs, so wrapping a
-- function of another season's scripts is harmless.
function R.Install()
    if G("SaveLoad_Checkpoint") ~= nil then
        hookCheckpoints()
    end
    if G("SubProject_GetEpisodeFirstScript") ~= nil then
        hookEpisodeStart()
    end
    if G("Game_StartScene") ~= nil then
        hookSceneStart()
    end
    if G("Menu_Episodes_GenerateMoreOptions") ~= nil and G("Menu_Episodes_Context") ~= nil then
        -- Season 3's Menu_Episodes.lua (the only one with a More Options popup on the episode screen).
        hookSeason3()
    end
    if G("Menu_Episodes_UpdateLegend") ~= nil and G("Menu_Episodes_OpenRewindMenu") ~= nil then
        -- The shared Definitive Menu_Episodes.lua that Season 4 uses.
        hookSeason4()
    end
end

-- require() runs a file only once, so the hook files can't re-trigger this one. Re-check the hooks
-- after every require instead: SaveLoad.lua and Menu_Episodes.lua are loaded that way.
if type(require) == "function" and require ~= R.requireWrapper then
    local baseRequire = require
    R.requireWrapper = function(...)
        local result = baseRequire(...)
        local ok, err = pcall(R.Install)
        if not ok then
            log("install failed: " .. tostring(err))
        end
        return result
    end
    require = R.requireWrapper
end

local ok, err = pcall(R.Install)
if not ok then
    log("install failed: " .. tostring(err))
end

-- Inside a Season 4 episode (a fresh Lua state; the GameOverrides.lua wrapper loads this file): a jump
-- pending for this episode was answered by the menu's state, so the episode has booted into its
-- scene. Arm the entry's setup for that scene's start.
ok, err = pcall(R.ArmIfPending)
if not ok then
    log("arming the jump failed: " .. tostring(err))
end

-- Add-ons: an archive that mounts TWDRewindAddon.lua gets it loaded here, with these helpers. It can
-- wrap R.BeforeSceneStart (every scene start) and R.ExtraRows (rows added to the rewind list). The
-- released mod ships no add-on; tools/capture-tour (the screenshot tour that took the Season 4
-- pictures) is one.
R.Try, R.SetPref, R.GetPref, R.Now = try, setPref, getPref, now
R.LogFile, R.QueryLog = logFile, queryLog
pcall(require, "TWDRewindAddon.lua")
