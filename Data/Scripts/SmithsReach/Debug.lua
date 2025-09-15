-- [scripts/SmithsReach/Debug.lua]
SmithsReach = SmithsReach or {}
local M     = SmithsReach
M.Debug     = M.Debug or {}

-- tiny fallbacks for counts/sums (use Core's if present)
local _k    = M._k or
    function(t)
        local c = 0; if type(t) ~= "table" then return 0 end
        for _ in pairs(t) do c = c + 1 end
        return c
    end
local _sum  = M._sum or
    function(t)
        local s = 0; if type(t) ~= "table" then return 0 end
        for _, v in pairs(t) do s = s + (tonumber(v) or 0) end
        return s
    end

local function _snap_map(entity, label, silent)
    if M.Stash and M.Stash.Snapshot then
        local ok, map = pcall(M.Stash.Snapshot, entity)
        if ok and type(map) == "table" then return map end
    end
    -- fallback read from inventory table
    local inv = entity and entity.inventory
    if inv and inv.GetInventoryTable then
        local ok, tbl = pcall(inv.GetInventoryTable, inv)
        if ok and type(tbl) == "table" then
            local out = {}
            for _, w in pairs(tbl) do
                if ItemManager and ItemManager.GetItem then
                    local okI, t = pcall(ItemManager.GetItem, w)
                    if okI and t then
                        local cid = t.classId or t.class or t.type
                        if cid then out[cid] = (out[cid] or 0) + 1 end
                    end
                end
            end
            return out
        end
    end
    return {}
end

-- replace the current _player() in Debug.lua with this:
local function _player() return rawget(_G, "player") end

local function _stash() return M.Stash and M.Stash.GetStash and M.Stash.GetStash() or nil end

-- 1) ping
function M.Debug.Ping() System.LogAlways("[SmithsReach] pong") end

System.AddCCommand("smithsreach_ping", "SmithsReach.Debug.Ping()", "Ping test")

-- 2) config_dump (concise summary)
function M.Debug.ConfigDump()
    local C = M.Config or {}
    local B = C.Behavior or {}
    local P = C.PullCaps or {}
    System.LogAlways(("[SmithsReach][cfg] verbose=%s showFX=%s caps=%s/%s/%s")
        :format(tostring(B.verboseLogs), tostring(B.showTransferFX),
            tostring(P.max_kinds), tostring(P.max_each), tostring(P.max_total)))
end

System.AddCCommand("smithsreach_config_dump", "SmithsReach.Debug.ConfigDump()", "Config summary")

-- 3) mats_where (only whitelisted mats)
function M.Debug.MatsWhere()
    local p, s = _player(), _stash()
    if not p or not s then
        System.LogAlways("[SmithsReach] player/stash unavailable"); return
    end
    local mats = M.CraftingMats or {}
    local P = _snap_map(p, "player", true)
    local S = _snap_map(s, "stash", true)
    System.LogAlways("[SmithsReach] Mats (cid → stash / player | ui (db))")
    for cid in pairs(mats) do
        local st = tonumber(S[cid]) or 0
        local pl = tonumber(P[cid]) or 0
        if st > 0 or pl > 0 then
            local info = mats[cid]
            local ui = ItemManager and ItemManager.GetItemUIName and ItemManager.GetItemUIName(cid) or
                (info and info.UIName or "?")
            local db = ItemManager and ItemManager.GetItemName and ItemManager.GetItemName(cid) or
                (info and info.Name or "?")
            System.LogAlways(("  %s → %d / %d  | %s (%s)"):format(cid, st, pl, ui, db))
        end
    end
    System.LogAlways(("[SmithsReach] Totals: stash=%d kinds/%d items | player=%d kinds/%d items")
        :format(_k(S), _sum(S), _k(P), _sum(P)))
end

System.AddCCommand("smithsreach_mats_where", "SmithsReach.Debug.MatsWhere()", "List mats in stash vs player")

-- 4) scan_unmatched (bsmt-like cids in stash not in table)
function M.Debug.ScanUnmatched()
    local s = _stash()
    if not s or not s.inventory or not s.inventory.GetInventoryTable then
        System.LogAlways("[SmithsReach] stash not available"); return
    end
    local ok, tbl = pcall(s.inventory.GetInventoryTable, s.inventory)
    if not ok or type(tbl) ~= "table" then
        System.LogAlways("[SmithsReach] stash read failed"); return
    end
    local mats = M.CraftingMats or {}
    local seen, misses = {}, 0
    for _, w in pairs(tbl) do
        local item = ItemManager and ItemManager.GetItem and ItemManager.GetItem(w)
        local cid  = item and (item.classId or item.class or item.type)
        if cid and not seen[cid] then
            seen[cid] = true
            if not mats[cid] then
                local ui = ItemManager and ItemManager.GetItemUIName and ItemManager.GetItemUIName(cid) or "?"
                if type(ui) == "string" and ui:match("^ui_nm_bsmt_") then
                    local db = ItemManager and ItemManager.GetItemName and ItemManager.GetItemName(cid) or "?"
                    System.LogAlways(("  [\"%s\"] = { Name = \"%s\", UIName = \"%s\" },"):format(cid, db, ui))
                    misses = misses + 1
                end
            end
        end
    end
    System.LogAlways(("[SmithsReach] scan complete. missing=%d"):format(misses))
end

System.AddCCommand("smithsreach_scan_unmatched", "SmithsReach.Debug.ScanUnmatched()",
    "Find stash smithing mats missing from table")

-- 5) find (substring in UI/DB)
function M.Debug.Find()
    local args = System.GetCVarArg and System.GetCVarArg() or {}
    local sub = tostring(args[1] or ""):lower()
    if #sub < 2 then
        System.LogAlways("[SmithsReach] find: need at least 2 chars"); return
    end
    local s = _stash()
    if not s or not s.inventory or not s.inventory.GetInventoryTable then
        System.LogAlways("[SmithsReach] stash not available"); return
    end
    local ok, tbl = pcall(s.inventory.GetInventoryTable, s.inventory)
    if not ok or type(tbl) ~= "table" then
        System.LogAlways("[SmithsReach] stash read failed"); return
    end
    local hits = 0
    for _, w in pairs(tbl) do
        local item = ItemManager and ItemManager.GetItem and ItemManager.GetItem(w)
        local cid  = item and (item.classId or item.class or item.type)
        if cid then
            local ui = ItemManager and ItemManager.GetItemUIName and ItemManager.GetItemUIName(cid) or "?"
            local db = ItemManager and ItemManager.GetItemName and ItemManager.GetItemName(cid) or "?"
            if (type(ui) == "string" and ui:lower():find(sub, 1, true)) or (type(db) == "string" and db:lower():find(sub, 1, true)) then
                System.LogAlways(("[Find] %s  ui=%s  db=%s"):format(cid, ui, db)); hits = hits + 1
            end
        end
    end
    System.LogAlways(("[SmithsReach] find done. hits=%d"):format(hits))
end

System.AddCCommand("smithsreach_find", "SmithsReach.Debug.Find()", "Find stash items by name substring")

-- ---- Stash debug commands (moved from Core) ----

-- smithsreach_stash_methods
function M.Debug.StashMethods()
    local s = _stash()
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

System.AddCCommand("smithsreach_stash_methods", "SmithsReach.Debug.StashMethods()", "Probe stash.inventory methods")

-- smithsreach_stash_names
function M.Debug.StashNames()
    local s = _stash()
    if not s then
        System.LogAlways("[SmithsReach] names: NOT FOUND"); return
    end
    if SmithsReach.Stash and SmithsReach.Stash.DebugResolveNames then
        SmithsReach.Stash.DebugResolveNames(s, 30)
    else
        System.LogAlways("[SmithsReach] names: no resolver")
    end
end

System.AddCCommand("smithsreach_stash_names", "SmithsReach.Debug.StashNames()", "List first N stash items with names")

-- smithsreach_stash_summary
function M.Debug.StashSummary()
    local s = _stash()
    if not s then
        System.LogAlways("[SmithsReach] summary: NOT FOUND"); return
    end
    if SmithsReach.Stash and SmithsReach.Stash.PrintSnapshotWithNames then
        SmithsReach.Stash.PrintSnapshotWithNames(s, 60)
    else
        System.LogAlways("[SmithsReach] summary: no printer")
    end
end

System.AddCCommand("smithsreach_stash_summary", "SmithsReach.Debug.StashSummary()", "Summarize stash by class with names")

-- smithsreach_stash_raw
function M.Debug.StashRaw()
    local s = _stash()
    if not s then
        System.LogAlways("[SmithsReach] raw: NOT FOUND"); return
    end
    if SmithsReach.Stash and SmithsReach.Stash.DebugDumpRaw then
        SmithsReach.Stash.DebugDumpRaw(s, 40)
    else
        System.LogAlways("[SmithsReach] raw: no dumper")
    end
end

System.AddCCommand("smithsreach_stash_raw", "SmithsReach.Debug.StashRaw()", "Dump raw GetInventoryTable entry types")

-- smithsreach_stash_dump
function M.Debug.StashDump()
    local s = _stash()
    if not s then
        System.LogAlways("[SmithsReach] dump: NOT FOUND"); return
    end
    if SmithsReach.Stash and SmithsReach.Stash.DebugDumpInventory then
        SmithsReach.Stash.DebugDumpInventory(s)
    else
        System.LogAlways("[SmithsReach] dump: no inv dumper")
    end
end

System.AddCCommand("smithsreach_stash_dump", "SmithsReach.Debug.StashDump()", "Call stash.inventory:Dump()")

-- Inventory debug commands
function M.Debug.ItemDump()
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

System.AddCCommand("smithsreach_item_dump", "SmithsReach.Debug.ItemDump()", "Dump ItemManager:GetItem(<wuid-string>)")

-- inv_methods
function M.Debug.InvMethods()
    local p = rawget(_G, "player")
    if not p or not p.inventory then
        System.LogAlways("[SmithsReach] inv_methods: no player/inventory"); return
    end
    local inv = p.inventory
    local function has(name) return type(inv[name]) == "function" end
    System.LogAlways("[SmithsReach] inv_methods: "
        .. "GetInventoryTable=" .. tostring(has("GetInventoryTable")) .. ", "
        .. "FindItem=" .. tostring(has("FindItem")) .. ", "
        .. "CreateItem=" .. tostring(has("CreateItem")) .. ", "
        .. "AddItem=" .. tostring(has("AddItem")) .. ", "
        .. "Dump=" .. tostring(has("Dump")))
end

System.AddCCommand("smithsreach_inv_methods", "SmithsReach.Debug.InvMethods()", "Probe player.inventory methods")

-- inv_dump
function M.Debug.InvDump()
    local p = rawget(_G, "player")
    if not p or not p.inventory then
        System.LogAlways("[SmithsReach] inv_dump: no player/inventory"); return
    end
    if p.inventory.Dump then p.inventory:Dump() else System.LogAlways("[SmithsReach] inv_dump: no :Dump()") end
end

System.AddCCommand("smithsreach_inv_dump", "SmithsReach.Debug.InvDump()", "Call player.inventory:Dump()")

-- inv_summary (pretty list of player's items by class with names)
function M.Debug.InvSummary()
    local p = rawget(_G, "player")
    if not p or not p.inventory then
        System.LogAlways("[SmithsReach] inv_summary: no player/inventory"); return
    end
    if SmithsReach.Stash and SmithsReach.Stash.PrintSnapshotWithNames then
        SmithsReach.Stash.PrintSnapshotWithNames(p, 80)
    else
        System.LogAlways("[SmithsReach] inv_summary: printer missing")
    end
end

System.AddCCommand("smithsreach_inv_summary", "SmithsReach.Debug.InvSummary()",
    "Summarize player inventory by class with names")

-- diff_stash_pl (diff stash vs player by class counts)
function M.Debug.DiffStashPl()
    local s = SmithsReach.Stash and SmithsReach.Stash.GetStash and SmithsReach.Stash.GetStash()
    local p = rawget(_G, "player")
    if not s then
        System.LogAlways("[SmithsReach] diff: stash NOT FOUND"); return
    end
    if not p or not p.inventory then
        System.LogAlways("[SmithsReach] diff: no player inv"); return
    end

    local stashMap  = SmithsReach.Stash.Snapshot(s)
    local playerMap = SmithsReach.Stash.Snapshot(p)

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

System.AddCCommand("smithsreach_diff_stash_pl", "SmithsReach.Debug.DiffStashPl()", "Diff stash vs player (class counts)")

-- ---- One-off helpers (moved from Core) ----

-- pull_one: clone first stash item into player (for sanity testing)
function M.Debug.PullOne()
    local s = SmithsReach.Stash and SmithsReach.Stash.GetStash and SmithsReach.Stash.GetStash()
    local p = rawget(_G, "player")
    if not s or not s.inventory or not p or not p.inventory then
        System.LogAlways("[SmithsReach] pull_one: missing stash/player"); return
    end

    local invS, invP = s.inventory, p.inventory

    local ok, tbl = pcall(function() return invS:GetInventoryTable() end)
    if not ok or not tbl then
        System.LogAlways("[SmithsReach] pull_one: no table"); return
    end

    local wuid = nil; for _, v in pairs(tbl) do
        wuid = v; break
    end
    if not wuid then
        System.LogAlways("[SmithsReach] pull_one: stash empty"); return
    end

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

    if invP.CreateItem then
        local okCreate = pcall(function() invP:CreateItem(classId, 1, 1) end)
        if okCreate and Game and Game.ShowItemsTransfer then pcall(function() Game.ShowItemsTransfer(classId, 1) end) end
        System.LogAlways("[SmithsReach] pull_one: cloned " .. tostring(classId) .. " into player")
    else
        System.LogAlways("[SmithsReach] pull_one: player.inventory.CreateItem missing")
    end
end

System.AddCCommand("smithsreach_pull_one", "SmithsReach.Debug.PullOne()",
    "Clone first item from stash into player (test)")
