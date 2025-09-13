-- [SmithsReach/Stash.lua] - minimal, cleaned
SmithsReach = SmithsReach or {}
local M = {}

local function dbg(msg) System.LogAlways("[SmithsReach][Stash] " .. msg) end

function M.GetStash()
    local list = System.GetEntitiesByClass("Stash") or {}
    for _, stash in pairs(list) do
        local nm = EntityUtils.GetName(stash)
        if nm and string.find(nm, "playerMasterChest", 1, true) then
            return stash
        end
    end
    return nil
end

-- Instance resolver: GetInventoryTable() returns list of WUIDs; aggregate by classId
function M.Snapshot(invOrEntity)
    local inv = invOrEntity and (invOrEntity.inventory or invOrEntity)
    local out = {}
    if not inv or not inv.GetInventoryTable then
        dbg("Snapshot: no inventory/GetInventoryTable"); return out
    end

    local ok, tbl = pcall(function() return inv:GetInventoryTable() end)
    if not ok or not tbl then
        dbg("Snapshot: table fetch failed"); return out
    end

    local entries, resolved = 0, 0
    for _, wuid in pairs(tbl) do
        entries = entries + 1
        if ItemManager and ItemManager.GetItem then
            local okItem, t = pcall(function() return ItemManager.GetItem(wuid) end)
            if okItem and t then
                resolved = resolved + 1
                local cid = t.classId or t.class or t.type or t.kind
                if cid then
                    out[cid] = (out[cid] or 0) + 1
                else
                    out[tostring(wuid)] = (out[tostring(wuid)] or 0) + 1
                end
            end
        end
    end
    dbg(("Snapshot: entries=%d resolved=%d kinds=%d"):format(entries, resolved,
        (function(t)
            local c = 0; for _ in pairs(t) do c = c + 1 end; return c
        end)(out)))
    return out
end

-- Print N raw rows with type info (debug)
function M.DebugDumpRaw(invOrEntity, N)
    local inv = invOrEntity and (invOrEntity.inventory or invOrEntity)
    if not inv or not inv.GetInventoryTable then
        dbg("raw: no inventory/GetInventoryTable"); return
    end
    local ok, tbl = pcall(function() return inv:GetInventoryTable() end)
    if not ok or not tbl then
        dbg("raw: table fetch failed"); return
    end
    local i = 0
    for k, v in pairs(tbl) do
        System.LogAlways(("[SmithsReach][Stash][RAW] k=%s (%s)  v=%s (%s)"):format(tostring(k), type(k), tostring(v),
            type(v)))
        i = i + 1; if i >= (N or 40) then break end
    end
end

-- Print engine-side inventory dump if available
function M.DebugDumpInventory(invOrEntity)
    local inv = invOrEntity and (invOrEntity.inventory or invOrEntity)
    if not inv or not inv.Dump then
        dbg("Dump: inventory or :Dump() missing"); return
    end
    inv:Dump()
end

-- List first N instance entries with names (WUID -> item -> classId -> names)
function M.DebugResolveNames(invOrEntity, N)
    local inv = invOrEntity and (invOrEntity.inventory or invOrEntity)
    if not inv or not inv.GetInventoryTable then
        dbg("names: no inventory/GetInventoryTable"); return
    end
    local ok, tbl = pcall(function() return inv:GetInventoryTable() end)
    if not ok or not tbl then
        dbg("names: table fetch failed"); return
    end

    local printed = 0
    for k, wuid in pairs(tbl) do
        local itemTbl = nil
        if ItemManager and ItemManager.GetItem then
            local okItem, t = pcall(function() return ItemManager.GetItem(wuid) end)
            if okItem then itemTbl = t end
        end

        local classId = itemTbl and (itemTbl.classId or itemTbl.class) or nil
        local uiName, dbName
        if classId and ItemManager then
            local okUi, ui = pcall(function() return ItemManager.GetItemUIName(classId) end); if okUi then uiName = ui end
            local okDb, dn = pcall(function() return ItemManager.GetItemName(classId) end); if okDb then dbName = dn end
        end

        local wuidStr = (Framework and Framework.WUIDToString) and Framework.WUIDToString(wuid) or tostring(wuid)
        local wuidUI  = (Framework and Framework.WUIDToUI) and Framework.WUIDToUI(wuid) or "?"

        System.LogAlways(("[SmithsReach][Stash] %s (%s) x1  class=%s id=%s  [wuid=%s ui=%s k=%s]")
            :format(tostring(uiName or "?"), tostring(dbName or "?"),
                tostring(classId), tostring(itemTbl and itemTbl.id or "?"),
                wuidStr, wuidUI, tostring(k)))

        printed = printed + 1
        if printed >= (N or 30) then break end
    end
end

-- Pretty summary with names
function M.PrintSnapshotWithNames(invOrEntity, limit)
    local map = M.Snapshot(invOrEntity)
    local shown = 0
    for cid, count in pairs(map) do
        local ui, db
        if ItemManager then
            local okUi, uiName = pcall(function() return ItemManager.GetItemUIName(cid) end); if okUi then ui = uiName end
            local okDb, dbName = pcall(function() return ItemManager.GetItemName(cid) end); if okDb then db = dbName end
        end
        System.LogAlways(("[SmithsReach][Stash] %s (%s) x%d  class=%s"):format(tostring(ui or "?"), tostring(db or "?"),
            count, tostring(cid)))
        shown = shown + 1
        if limit and shown >= limit then break end
    end
end

SmithsReach.Stash = M
