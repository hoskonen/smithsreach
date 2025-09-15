-- [scripts/SmithsReach/Debug.lua]
SmithsReach = SmithsReach or {}
local M = SmithsReach

-- ---- tiny helpers (use Core’s if available) ----
local function _kcount(t)
    if M._k then return M._k(t) end
    local c = 0; if type(t) ~= "table" then return 0 end
    for _ in pairs(t) do c = c + 1 end
    return c
end

local function _sum(t)
    if M._sum then return M._sum(t) end
    local s = 0; if type(t) ~= "table" then return 0 end
    for _, v in pairs(t) do s = s + (tonumber(v) or 0) end
    return s
end

-- Prefer stash snapshot (unsilenced here by default so you see dumps)
local function _snap_map(entity, label, silent)
    if M.Stash and M.Stash.Snapshot then
        local ok, map = pcall(M.Stash.Snapshot, entity, label, silent)
        if ok and type(map) == "table" then return map end
    end
    -- Fallback: inventory table → counts map
    local inv = entity and entity.inventory
    if inv and inv.GetInventoryTable then
        local ok, tbl = pcall(inv.GetInventoryTable, inv)
        if ok and type(tbl) == "table" then
            local out = {}
            for _, itm in pairs(tbl) do
                local cid = itm.classId or itm.class or itm.class_id
                if cid then out[cid] = (out[cid] or 0) + 1 end
            end
            return out
        end
    end
    return {}
end

local function _player() return _G.player end
local function _stash()
    return M.Stash and M.Stash.GetStash and M.Stash.GetStash() or nil
end

-- ---- commands you actually use day-to-day ----

-- 1) config dump (compact)
function SmithsReach_ConfigDump()
    local C = M.Config or {}
    System.LogAlways("[SmithsReach][cfg] Behavior=" ..
        (C.Behavior and (C.Behavior.verboseLogs and "verbose" or "quiet") or "?")
        .. " caps(kinds/each/total)=" ..
        (C.PullCaps and (tostring(C.PullCaps.max_kinds) .. "/" .. tostring(C.PullCaps.max_each) .. "/" .. tostring(C.PullCaps.max_total)) or "?"))
end

System.AddCCommand("smithsreach_config_dump", "SmithsReach_ConfigDump()", "Print SmithsReach config summary")

-- 2) where are mats (stash vs player)
function SmithsReach_MatsWhere()
    local p = _player(); local s = _stash()
    if not p or not s then
        System.LogAlways("[SmithsReach] player/stash unavailable"); return
    end

    local mats = M.CraftingMats or {}
    local P = _snap_map(p, "player", true)
    local S = _snap_map(s, "stash", true)

    local function line(cid)
        local info = mats[cid]
        local ui = (ItemManager and ItemManager.GetItemUIName and ItemManager.GetItemUIName(cid)) or
        (info and info.UIName) or "?"
        local db = (ItemManager and ItemManager.GetItemName and ItemManager.GetItemName(cid)) or (info and info.Name) or
        "?"
        return ui, db
    end

    System.LogAlways("[SmithsReach] Mats (cid → stash / player  | ui (db))")
    for cid, _ in pairs(mats) do
        local st = tonumber(S[cid]) or 0
        local pl = tonumber(P[cid]) or 0
        if st > 0 or pl > 0 then
            local ui, db = line(cid)
            System.LogAlways(("  %s → %d / %d  | %s (%s)"):format(cid, st, pl, ui, db))
        end
    end
    System.LogAlways(("[SmithsReach] Totals: stash=%d kinds/%d items | player=%d kinds/%d items")
        :format(_kcount(S), _sum(S), _kcount(P), _sum(P)))
end

System.AddCCommand("smithsreach_mats_where", "SmithsReach_MatsWhere()", "List blacksmithing mats in stash vs player")

-- 3) scan stash for smithing-like items not in our table (future GUID drift hunter)
function SmithsReach_ScanUnmatched()
    local s = _stash()
    if not s then
        System.LogAlways("[SmithsReach] No stash entity"); return
    end
    local inv = s.inventory
    if not inv or not inv.GetInventoryTable then
        System.LogAlways("[SmithsReach] Stash inventory not readable"); return
    end

    local ok, tbl = pcall(inv.GetInventoryTable, inv)
    if not ok or type(tbl) ~= "table" then
        System.LogAlways("[SmithsReach] Stash inventory read failed"); return
    end

    local mats = M.CraftingMats or {}
    local seen, misses = {}, 0
    for _, itm in pairs(tbl) do
        local cid = itm.classId or itm.class or itm.class_id
        if cid and not seen[cid] then
            seen[cid] = true
            local ui = (ItemManager and ItemManager.GetItemUIName and ItemManager.GetItemUIName(cid)) or "?"
            if type(ui) == "string" and ui:match("^ui_nm_bsmt_") and not mats[cid] then
                local db = (ItemManager and ItemManager.GetItemName and ItemManager.GetItemName(cid)) or "?"
                System.LogAlways(("[SmithsReach][MISSING] cid=%s ui=%s db=%s  -> add to CraftingMats.lua")
                    :format(tostring(cid), tostring(ui), tostring(db)))
                System.LogAlways(("  [\"%s\"] = { Name = \"%s\", UIName = \"%s\" },"):format(tostring(cid), tostring(db),
                    tostring(ui)))
                misses = misses + 1
            end
        end
    end
    System.LogAlways(("[SmithsReach] scan complete. missing=%d"):format(misses))
end

System.AddCCommand("smithsreach_scan_unmatched", "SmithsReach_ScanUnmatched()",
    "Find stash smithing mats missing from our table")

-- 4) find stash items by UI/DB name substring
function SmithsReach_Find(sub)
    sub = tostring(sub or ""):lower()
    local s = _stash()
    if #sub < 2 then
        System.LogAlways("[SmithsReach] find: need at least 2 chars"); return
    end
    if not s or not s.inventory or not s.inventory.GetInventoryTable then
        System.LogAlways("[SmithsReach] Stash unavailable"); return
    end
    local ok, tbl = pcall(s.inventory.GetInventoryTable, s.inventory)
    if not ok or type(tbl) ~= "table" then
        System.LogAlways("[SmithsReach] stash read fail"); return
    end

    local hits = 0
    for _, itm in pairs(tbl) do
        local cid = itm.classId or itm.class or itm.class_id
        if cid then
            local ui = (ItemManager and ItemManager.GetItemUIName and ItemManager.GetItemUIName(cid)) or "?"
            local db = (ItemManager and ItemManager.GetItemName and ItemManager.GetItemName(cid)) or "?"
            if (type(ui) == "string" and ui:lower():find(sub, 1, true)) or (type(db) == "string" and db:lower():find(sub, 1, true)) then
                System.LogAlways(("[Find] %s  ui=%s  db=%s"):format(cid, tostring(ui), tostring(db)))
                hits = hits + 1
            end
        end
    end
    System.LogAlways(("[SmithsReach] find done. hits=%d"):format(hits))
end

System.AddCCommand("smithsreach_find", "SmithsReach_Find(%line)", "Find stash items by name substring (ui/db)")
