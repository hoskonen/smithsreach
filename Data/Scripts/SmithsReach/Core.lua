-- [SmithsReach/Core.lua]
SmithsReach = SmithsReach or {}

function SmithsReach.Init()
    Script.ReloadScript("scripts/SmithsReach/Stash.lua")

    -- Register console commands early
    -- Use GLOBAL wrappers to avoid any table-lookup quirks.
    System.AddCCommand("smithsreach_ping", "SmithsReach_Ping()", "Ping test")
    System.AddCCommand("smithsreach_stash_methods", "SmithsReach_StashMethods()", "Probe stash.inventory methods")
    System.AddCCommand("smithsreach_stash_list", "SmithsReach_StashList()", "List stash contents (safe)")
    System.AddCCommand("smithsreach_stash_names", "SmithsReach_StashNames()", "Resolve stash entries to names")
    System.AddCCommand("smithsreach_stash_raw", "SmithsReach_StashRaw()", "Dump raw GetInventoryTable entries (types)")
    System.AddCCommand("smithsreach_stash_dump", "SmithsReach_StashDump()", "Call stash.inventory:Dump()")
    System.AddCCommand("smithsreach_stash_summary", "SmithsReach_StashSummary()", "Summarize stash by class with names")

    if UIAction and UIAction.RegisterEventSystemListener then
        UIAction.RegisterEventSystemListener(SmithsReach, "System", "OnGameplayStarted", "OnGameplayStarted")
    end
end

function SmithsReach:OnGameplayStarted(_, _, _)
    System.LogAlways("[SmithsReach] Initialized!")
end

-- ===== Global wrappers (robust for console) =====
function SmithsReach_Ping() SmithsReach.DebugPing() end

function SmithsReach_StashMethods() SmithsReach.DebugStashMethods() end

function SmithsReach_StashList() SmithsReach.DebugListStash() end

-- ===== Internals =====
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
        .. "GetAllItems=" .. tostring(has("GetAllItems")) .. ", "
        .. "ForEachItem=" .. tostring(has("ForEachItem")) .. ", "
        .. "GetSlotCount=" .. tostring(has("GetSlotCount")) .. ", "
        .. "GetItemBySlot=" .. tostring(has("GetItemBySlot")))
end

function SmithsReach.DebugListStash()
    local ok, err = pcall(function()
        local s = SmithsReach.Stash.GetStash()
        if not s then
            System.LogAlways("[SmithsReach] Stash list: NOT FOUND"); return
        end
        local map = SmithsReach.Stash.Snapshot(s) -- safe, crash-guarded
        local kinds, total = 0, 0
        for _, c in pairs(map) do
            kinds = kinds + 1; total = total + (c or 0)
        end
        System.LogAlways(("[SmithsReach] Stash list: kinds=%d total=%d"):format(kinds, total))
        local n = 0
        for k, c in pairs(map) do
            System.LogAlways(("  %s x%d"):format(tostring(k), c or 0))
            n = n + 1; if n >= 50 then
                System.LogAlways("  ... (truncated)"); break
            end
        end
    end)
    if not ok then
        System.LogAlways("[SmithsReach] Stash list ERROR: " .. tostring(err))
    end
end

function SmithsReach_StashNames() SmithsReach.DebugStashNames() end

function SmithsReach.DebugStashNames()
    local s = SmithsReach.Stash.GetStash()
    if not s then
        System.LogAlways("[SmithsReach] names: NOT FOUND"); return
    end
    SmithsReach.Stash.DebugResolveNames(s, 30)
end

function SmithsReach_StashRaw() SmithsReach.DebugStashRaw() end

function SmithsReach.DebugStashRaw()
    local s = SmithsReach.Stash.GetStash()
    if not s then
        System.LogAlways("[SmithsReach] raw: NOT FOUND"); return
    end
    SmithsReach.Stash.DebugDumpRaw(s, 40)
end

function SmithsReach_StashDump() SmithsReach.DebugStashDump() end

function SmithsReach.DebugStashDump()
    local s = SmithsReach.Stash.GetStash()
    if not s then
        System.LogAlways("[SmithsReach] dump: NOT FOUND")
        return
    end
    SmithsReach.Stash.DebugDumpInventory(s)
end

function SmithsReach_StashSummary() SmithsReach.DebugStashSummary() end

function SmithsReach.DebugStashSummary()
    local s = SmithsReach.Stash.GetStash()
    if not s then
        System.LogAlways("[SmithsReach] summary: NOT FOUND"); return
    end
    SmithsReach.Stash.PrintSnapshotWithNames(s, 60)
end
