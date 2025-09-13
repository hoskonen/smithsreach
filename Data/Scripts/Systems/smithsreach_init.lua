-- [SmithsReach/init.lua]
Script.ReloadScript("scripts/SmithsReach/Core.lua")

-- kick once; Core will hook OnGameplayStarted
if SmithsReach and SmithsReach.Init then
    SmithsReach.Init()
end
