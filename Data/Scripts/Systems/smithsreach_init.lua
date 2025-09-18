Script.ReloadScript("scripts/SmithsReach/Util.lua")
Script.ReloadScript("scripts/SmithsReach/Config.lua")
Script.ReloadScript("scripts/SmithsReach/CraftingMats.lua")
Script.ReloadScript("scripts/SmithsReach/Stash.lua")
Script.ReloadScript("scripts/SmithsReach/Core.lua")
Script.ReloadScript("scripts/SmithsReach/Debug.lua") -- now owns: ping/config_dump/mats_where/scan_unmatched/find

if SmithsReach and SmithsReach.Init then
    SmithsReach.Init()
    if SmithsReach.HookSmithery then SmithsReach.HookSmithery() end
    if SmithsReach.HookPSHEnd then SmithsReach.HookPSHEnd() end
end
