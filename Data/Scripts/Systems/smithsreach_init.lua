-- [SmithsReach/init.lua]
Script.ReloadScript("scripts/SmithsReach/Config.lua")       -- 1) config first
Script.ReloadScript("scripts/SmithsReach/Core.lua")         -- 2) core (commands, stubs)
Script.ReloadScript("scripts/SmithsReach/CraftingMats.lua") -- 3) data (GUIDs)
Script.ReloadScript("scripts/SmithsReach/Stash.lua")        -- 4) stash utils

-- Kick once; then hook gameplay start/end (idempotent in Core)
if SmithsReach and SmithsReach.Init then
    SmithsReach.Init()
    if SmithsReach.HookSmithery then SmithsReach.HookSmithery() end -- BEGIN
    if SmithsReach.HookPSHEnd then SmithsReach.HookPSHEnd() end     -- END (use PSH wrapper)
    if SmithsReach.HookCraftingUI then SmithsReach.HookCraftingUI() end
end
