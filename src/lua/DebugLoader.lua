-- DebugLoader.lua
-- Telltale's developer builds ship a DebugLoader.lua; the retail game does not. Several stock
-- scripts (Menu_Main.lua of Seasons 3 and 4, the shared Definitive Menu_Main.lua, Michonne's,
-- BootTitle.lua, some Menu_Pause.lua) check ResourceExists("DebugLoader.lua"), require it, and
-- then call Callback_OnLoadDebugMenu:Add(...). This mod ships a DebugLoader.lua only to get its
-- own script loaded at that point; it does not add any debug features. (Season 4 episodes load
-- the mod through GameOverrides.lua instead.)
--
-- The real DebugLoader defines Callback_OnLoadDebugMenu, so this one must too, or those
-- :Add(...) calls would fail. Callbacks added here are kept but never fired.

if rawget(_G, "Callback_OnLoadDebugMenu") == nil then
    local callbacks = {}
    Callback_OnLoadDebugMenu = {
        Add = function(self, fn)
            table.insert(callbacks, fn)
        end,
        Remove = function(self, fn)
            for i = #callbacks, 1, -1 do
                if callbacks[i] == fn then
                    table.remove(callbacks, i)
                end
            end
        end,
        Call = function(self, ...)
        end,
    }
end

local ok, err = pcall(require, "TWDRewind.lua")
if not ok then
    pcall(print, "[TWDRewind] failed to load: " .. tostring(err))
end
-- TWDRewind.lua may already have been loaded earlier in this state; its hooks re-check after every
-- require, but check once more here, right after Menu_Episodes.lua has been loaded.
if TWDRewind and TWDRewind.Install then
    pcall(TWDRewind.Install)
end
