-- Season 4 episodes load GameOverrides.lua (EpisodeInclude.lua, right after Game.lua). This copy runs
-- the stock one, shipped as TWDRewind_S4_GameOverrides.lua (extracted from the game at build time),
-- then loads the mod: retail episodes never load it otherwise (ProjectInclude.lua requires
-- WalkingDeadTools.lua in tool builds only).
require("TWDRewind_S4_GameOverrides.lua")
pcall(require, "TWDRewind.lua")
