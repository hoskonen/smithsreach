-- [SmithsReach/Core.lua] - minimal, cleaned
SmithsReach = SmithsReach or {}

function SmithsReach.Init()
    Script.ReloadScript("scripts/SmithsReach/Stash.lua")

    -- Stash-side commands
    System.AddCCommand("smithsreach_ping", "SmithsReach_Ping()", "Ping test")
    System.AddCCommand("smithsreach_stash_methods", "SmithsReach_StashMethods()", "Probe stash.inventory methods")
    System.AddCCommand("smithsreach_stash_names", "SmithsReach_StashNames()", "List first N stash items with names")
    System.AddCCommand("smithsreach_stash_summary", "SmithsReach_StashSummary()", "Summarize stash by class with names")
    System.AddCCommand("smithsreach_stash_raw", "SmithsReach_StashRaw()", "Dump raw GetInventoryTable entry types")
    System.AddCCommand("smithsreach_stash_dump", "SmithsReach_StashDump()", "Call stash.inventory:Dump()")
    System.AddCCommand("smithsreach_item_dump", "SmithsReach_ItemDump()", "Dump ItemManager:GetItem(<wuid-string>)")

    -- Player-side commands
    System.AddCCommand("smithsreach_inv_methods", "SmithsReach_InvMethods()", "Probe player.inventory methods")
    System.AddCCommand("smithsreach_inv_dump", "SmithsReach_InvDump()", "Call player.inventory:Dump()")
    System.AddCCommand("smithsreach_inv_summary", "SmithsReach_InvSummary()",
        "Summarize player inventory by class with names")
    System.AddCCommand("smithsreach_pull_one", "SmithsReach_PullOne()", "Clone first item from stash into player (test)")

    -- Diff
    System.AddCCommand("smithsreach_diff_stash_pl", "SmithsReach_DiffStashPl()", "Diff stash vs player (class counts)")

    if UIAction and UIAction.RegisterEventSystemListener then
        UIAction.RegisterEventSystemListener(SmithsReach, "System", "OnGameplayStarted", "OnGameplayStarted")
    end
end

function SmithsReach:OnGameplayStarted(_, _, _)
    System.LogAlways("[SmithsReach] Initialized!")
end

-- ---- Global wrappers (console-friendly) ----
function SmithsReach_Ping() SmithsReach.DebugPing() end

function SmithsReach_StashMethods() SmithsReach.DebugStashMethods() end

function SmithsReach_StashNames() SmithsReach.DebugStashNames() end

function SmithsReach_StashSummary() SmithsReach.DebugStashSummary() end

function SmithsReach_StashRaw() SmithsReach.DebugStashRaw() end

function SmithsReach_StashDump() SmithsReach.DebugStashDump() end

function SmithsReach_ItemDump() SmithsReach.DebugItemDump() end

function SmithsReach_InvMethods() SmithsReach.DebugInvMethods() end

function SmithsReach_InvDump() SmithsReach.DebugInvDump() end

function SmithsReach_InvSummary() SmithsReach.DebugInvSummary() end

function SmithsReach_DiffStashPl() SmithsReach.DebugDiffStashPl() end

function SmithsReach_PullOne() SmithsReach.DebugPullOne() end

-- ---- Internals ----
function SmithsReach.DebugPing()
    System.LogAlways("[SmithsReach] ping")
end

function SmithsReach.DebugStashMethods()
    local s = SmithsReach.Stash.GetStash()
    if not s then
        System.LogAlways("[SmithsReach] methods: NOT FOUND"); return
    end
    local inv = s.inventory
    if not inv then
        System.LogAlways("[SmithsReach] methods: stash has no .inventory"); return
    end
    local function has(name) return type(inv[name]) == "function" end
    System.LogAlways("[SmithsReach] methods: "
        .. "GetInventoryTable=" .. tostring(has("GetInventoryTable")) .. ", "
        .. "FindItem=" .. tostring(has("FindItem")) .. ", "
        .. "CreateItem=" .. tostring(has("CreateItem")) .. ", "
        .. "AddItem=" .. tostring(has("AddItem")) .. ", "
        .. "Dump=" .. tostring(has("Dump")))
end

function SmithsReach.DebugStashNames()
    local s = SmithsReach.Stash.GetStash()
    if not s then
        System.LogAlways("[SmithsReach] names: NOT FOUND"); return
    end
    SmithsReach.Stash.DebugResolveNames(s, 30)
end

function SmithsReach.DebugStashSummary()
    local s = SmithsReach.Stash.GetStash()
    if not s then
        System.LogAlways("[SmithsReach] summary: NOT FOUND"); return
    end
    SmithsReach.Stash.PrintSnapshotWithNames(s, 60)
end

function SmithsReach.DebugStashRaw()
    local s = SmithsReach.Stash.GetStash()
    if not s then
        System.LogAlways("[SmithsReach] raw: NOT FOUND"); return
    end
    SmithsReach.Stash.DebugDumpRaw(s, 40)
end

function SmithsReach.DebugStashDump()
    local s = SmithsReach.Stash.GetStash()
    if not s then
        System.LogAlways("[SmithsReach] dump: NOT FOUND"); return
    end
    SmithsReach.Stash.DebugDumpInventory(s)
end

function SmithsReach.DebugItemDump()
    local args = System.GetCVarArg and System.GetCVarArg() or {}
    local wuid = args[1]
    if not wuid then
        System.LogAlways("[SmithsReach] item_dump usage: smithsreach_item_dump <wuid-string>"); return
    end
    if not (ItemManager and ItemManager.GetItem) then
        System.LogAlways("[SmithsReach] item_dump: ItemManager.GetItem missing"); return
    end
    local ok, item = pcall(function() return ItemManager.GetItem(wuid) end)
    if not ok or not item then
        System.LogAlways("[SmithsReach] item_dump: no item for " .. tostring(wuid)); return
    end
    System.LogAlways("[SmithsReach] item_dump BEGIN " .. tostring(wuid))
    for k, v in pairs(item) do System.LogAlways(("  %s = %s"):format(tostring(k), tostring(v))) end
    System.LogAlways("[SmithsReach] item_dump END")
end

function SmithsReach.DebugInvMethods()
    if not player or not player.inventory then
        System.LogAlways("[SmithsReach] inv_methods: no player/inventory"); return
    end
    local inv = player.inventory
    local function has(name) return type(inv[name]) == "function" end
    System.LogAlways("[SmithsReach] inv_methods: "
        .. "GetInventoryTable=" .. tostring(has("GetInventoryTable")) .. ", "
        .. "FindItem=" .. tostring(has("FindItem")) .. ", "
        .. "CreateItem=" .. tostring(has("CreateItem")) .. ", "
        .. "AddItem=" .. tostring(has("AddItem")) .. ", "
        .. "Dump=" .. tostring(has("Dump")))
end

function SmithsReach.DebugInvDump()
    if not player or not player.inventory then
        System.LogAlways("[SmithsReach] inv_dump: no player/inventory"); return
    end
    if player.inventory.Dump then player.inventory:Dump() else System.LogAlways("[SmithsReach] inv_dump: no :Dump()") end
end

function SmithsReach.DebugInvSummary()
    if not player or not player.inventory then
        System.LogAlways("[SmithsReach] inv_summary: no player/inventory"); return
    end
    SmithsReach.Stash.PrintSnapshotWithNames(player, 80)
end

function SmithsReach.DebugDiffStashPl()
    local s = SmithsReach.Stash.GetStash()
    if not s then
        System.LogAlways("[SmithsReach] diff: stash NOT FOUND"); return
    end
    if not player or not player.inventory then
        System.LogAlways("[SmithsReach] diff: no player inv"); return
    end

    local stashMap  = SmithsReach.Stash.Snapshot(s)
    local playerMap = SmithsReach.Stash.Snapshot(player)

    local keys      = {}
    for k in pairs(stashMap) do keys[k] = true end
    for k in pairs(playerMap) do keys[k] = true end

    local function uiName(cid)
        if ItemManager and ItemManager.GetItemUIName then
            local ok, name = pcall(function() return ItemManager.GetItemUIName(cid) end)
            if ok and name then return name end
        end
        return tostring(cid)
    end

    System.LogAlways("[SmithsReach] diff (stash - player):")
    local rows = 0
    for cid in pairs(keys) do
        local d = (stashMap[cid] or 0) - (playerMap[cid] or 0)
        if d ~= 0 then
            System.LogAlways(("  %s  stash=%d  player=%d  Δ=%+d"):format(uiName(cid), stashMap[cid] or 0,
                playerMap[cid] or 0, d))
            rows = rows + 1
            if rows >= 100 then
                System.LogAlways("  ... (truncated)"); break
            end
        end
    end
    if rows == 0 then System.LogAlways("  (no differences)") end
end

function SmithsReach.DebugPullOne()
    local s = SmithsReach.Stash.GetStash()
    if not s or not s.inventory or not player or not player.inventory then
        System.LogAlways("[SmithsReach] pull_one: missing stash/player"); return
    end

    local invS = s.inventory
    local invP = player.inventory

    -- stash GetInventoryTable() -> array of WUIDs
    local ok, tbl = pcall(function() return invS:GetInventoryTable() end)
    if not ok or not tbl then
        System.LogAlways("[SmithsReach] pull_one: no table"); return
    end

    local wuid = nil
    for _, v in pairs(tbl) do
        wuid = v; break
    end
    if not wuid then
        System.LogAlways("[SmithsReach] pull_one: stash empty"); return
    end

    -- Resolve classId via ItemManager.GetItem(wuid)
    if not (ItemManager and ItemManager.GetItem) then
        System.LogAlways("[SmithsReach] pull_one: ItemManager.GetItem missing"); return
    end
    local okItem, itemTbl = pcall(function() return ItemManager.GetItem(wuid) end)
    if not okItem or not itemTbl then
        System.LogAlways("[SmithsReach] pull_one: cannot resolve item"); return
    end

    local classId = itemTbl.classId or itemTbl.class
    if not classId then
        System.LogAlways("[SmithsReach] pull_one: item has no classId"); return
    end

    -- Clone into player (CreateItem expects a guid/class id)
    if invP.CreateItem then
        local okCreate = pcall(function() invP:CreateItem(classId, 1, 1) end)
        if okCreate and Game and Game.ShowItemsTransfer then
            pcall(function() Game.ShowItemsTransfer(classId, 1) end)
        end
        System.LogAlways("[SmithsReach] pull_one: cloned " .. tostring(classId) .. " into player")
    else
        System.LogAlways("[SmithsReach] pull_one: player.inventory.CreateItem missing")
    end
end
