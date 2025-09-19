-- [SmithsReach/Stash.lua] - minimal, cleaned
SmithsReach = SmithsReach or {}
local M = {}

local function dbg(msg)
    local B = SmithsReach and SmithsReach.Config and SmithsReach.Config.Behavior or {}
    if B.verboseLogs then
        System.LogAlways(("[SmithsReach][Stash] %s"):format(msg))
    end
end

-- ── Quantity config (pin to one field/method) ────────────────────────────────
local QTY_FIELD  = (SmithsReach.Config and SmithsReach.Config.Behavior and SmithsReach.Config.Behavior.qty_field) or
    "amount"
local QTY_METHOD = (SmithsReach.Config and SmithsReach.Config.Behavior and SmithsReach.Config.Behavior.qty_getter) or
    "GetAmount"

local function _ucfirst(s) return (s and s:sub(1, 1):upper() .. s:sub(2)) end

local function _to_int(v)
    if type(v) == "number" then return (v > 0) and math.floor(v + 0.00001) or 1 end
    local n = tonumber(v); return (n and n > 0) and math.floor(n + 0.00001) or 1
end

local function _resolve(handle_or_item)
    if type(handle_or_item) == "table" then return handle_or_item end
    if ItemManager and ItemManager.GetItem then
        local ok, obj = pcall(ItemManager.GetItem, handle_or_item)
        if ok and type(obj) == "table" then return obj end
    end
    return handle_or_item
end

-- Returns player's WUID or nil
local function _player_wuid()
    local pl = SmithsReach.Util.Player()
    if not pl then return nil end
    local ok, wuid = pcall(XGenAIModule.GetMyWUID, pl)
    return ok and Framework.IsValidWUID and Framework.IsValidWUID(wuid) and wuid or nil
end

-- Score a stash for "is this the player's main stash?"
local function _score_player_stash(stash)
    local info = StashInventoryCollector.GetStashInformation(stash)
    -- hard filters
    if info.isShopStash then return -math.huge end

    local score = 0
    -- primary: master stash network (player stash system)
    if info.isMasterStash then score = score + 1000 else score = score - 100 end

    -- owner preference (if resolvable)
    local pw = (function()
        local pl = SmithsReach.Util.Player()
        if not pl then return nil end
        local ok, wuid = pcall(XGenAIModule.GetMyWUID, pl)
        return ok and wuid or nil
    end)()
    local ctx = { wuid = StashInventoryCollector.GetStashWuid(stash) }
    ctx.owner = StashInventoryCollector.GetStashOwner(ctx)
    if pw and ctx.owner == pw then score = score + 200 end

    -- small context nudge (optional)
    if info.contextLabel and (info.contextLabel == "bedside" or info.contextLabel == "workshop") then
        score = score + 15
    end

    return score
end


-- Find the best candidate near player (2D radius), falling back to global best if needed
function M.FindBestPlayerStashNear(player, searchRadiusM)
    local best, bestScore, bestD = nil, -math.huge, math.huge
    local pp = SmithsReach.Util.Pos(player)
    if not pp then return nil, math.huge end

    local all = System.GetEntitiesByClass and System.GetEntitiesByClass("Stash") or {}
    for _, s in pairs(all) do
        if s and s.inventory and s.inventory.GetInventoryTable then
            local sc = _score_player_stash(s)
            if sc > -math.huge then
                local d = SmithsReach.Util.DistPos2D(SmithsReach.Util.Pos(s), pp)
                -- prioritize within radius; otherwise consider farther only if no near hit
                local inRange = (tonumber(searchRadiusM) and d <= searchRadiusM) or false
                local tie = (sc == bestScore) and (d < bestD)
                if (inRange and (sc > bestScore or tie)) or (best == nil and (sc > bestScore or tie)) then
                    best, bestScore, bestD = s, sc, d
                end
            end
        end
    end
    return best, bestD
end

-- Preferred-or-best stash used by Core
function M.GetPreferredOrBestStash(player, radiusM)
    -- preferred binding wins if valid
    if M._preferredStashId then
        local e = System.GetEntity and System.GetEntity(M._preferredStashId)
        if e and e.inventory and e.inventory.GetInventoryTable then
            return e
        end
    end
    -- try smart resolver
    local s = nil
    if M.FindBestPlayerStashNear then
        s = M.FindBestPlayerStashNear(player, radiusM or 30)
        if type(s) == "table" then s = s end
    end
    -- fallback legacy
    return s or (M.GetStash and M.GetStash() or nil)
end

-- Read qty using pinned field/method only (no guessing loops)
local function _qty_from_item(itm)
    if type(itm) ~= "table" then return 1 end

    -- 1) field (amount / Amount)
    local v = rawget(itm, QTY_FIELD) or rawget(itm, _ucfirst(QTY_FIELD))
    if v ~= nil then return _to_int(v) end

    -- 2) method (GetAmount by default)
    local getter = rawget(itm, QTY_METHOD) or rawget(itm, _ucfirst(QTY_METHOD))
    if type(getter) == "function" then
        local ok, r = pcall(getter, itm)
        if ok and r ~= nil then return _to_int(r) end
    end

    return 1
end

-- Names we consider "player stash" (extend if needed)
local STASH_KEYS = { "playerMasterChest", "player_master_chest", "playerChest", "playerStash" }

local function _is_player_stash_name(nm)
    if type(nm) ~= "string" then return false end
    for _, key in ipairs(STASH_KEYS) do
        if nm:find(key, 1, true) then return true end
    end
    return false
end

function M.FindPlayerStashNear(player, maxRadius)
    local best, bestD2 = nil, math.huge
    local list = System.GetEntitiesByClass and System.GetEntitiesByClass("Stash") or {}
    local ppos = SmithsReach.Util.Pos(player)
    for _, e in pairs(list) do
        local nm = (EntityUtils and EntityUtils.GetName and EntityUtils.GetName(e)) or (e.GetName and e:GetName()) or ""
        if _is_player_stash_name(nm) then
            if e.inventory and e.inventory.GetInventoryTable then
                local d2 = SmithsReach.Util.DistPos2D(SmithsReach.Util.Pos(e), ppos)
                if d2 < bestD2 then best, bestD2 = e, d2 end
            end
        end
    end
    if best and (not maxRadius or bestD2 <= maxRadius) then
        return best, bestD2
    end
    return nil, math.huge
end

-- Public API used by Core/Debug
function M.GetQty(handle_or_item)
    return _qty_from_item(_resolve(handle_or_item))
end

-- Optional: expose what we’re using (for a debug command)
function M.GetQtyConfig()
    return QTY_FIELD, QTY_METHOD
end

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

    local okTable, tbl = pcall(function() return inv:GetInventoryTable() end)
    if not okTable or type(tbl) ~= "table" then
        dbg("Snapshot: table fetch failed"); return out
    end

    local entries, resolved = 0, 0
    local mats = SmithsReach and SmithsReach.CraftingMats or {}
    local canClassCount = type(inv.GetCountOfClass) == "function"

    if canClassCount then
        -- 1) Whitelist pass
        for cid, _ in pairs(mats) do
            local okc, n = pcall(inv.GetCountOfClass, inv, cid)
            if okc and type(n) == "number" and n > 0 then out[cid] = n end
        end
        -- 2) Discovery pass
        local seen = {}
        for _, wuid in pairs(tbl) do
            entries = entries + 1
            local okItem, t = pcall(ItemManager.GetItem, wuid)
            if okItem and t then
                resolved = resolved + 1
                local cid = t.classId or t.class or t.class_id or t.type or t.kind
                if cid and not seen[cid] and out[cid] == nil then
                    seen[cid] = true
                    local okc, n = pcall(inv.GetCountOfClass, inv, cid)
                    if okc and type(n) == "number" and n > 0 then out[cid] = n end
                end
            end
        end
    else
        -- 3) Fallback: per-instance, but use our single source of truth for qty
        for _, wuid in pairs(tbl) do
            entries = entries + 1
            local okItem, t = pcall(ItemManager.GetItem, wuid)
            if okItem and t then
                resolved = resolved + 1
                local cid = t.classId or t.class or t.class_id or t.type or t.kind
                local q = (M.GetQty and M.GetQty(t)) or 1
                if cid then
                    out[cid] = (out[cid] or 0) + q
                else
                    out[tostring(wuid)] = (out[tostring(wuid)] or 0) + q
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

function SmithsReach.IsMaterial(classId)
    return SmithsReach.CraftingMats[classId] ~= nil
end

function SmithsReach.GetMaterialName(classId)
    local e = SmithsReach.CraftingMats[classId]
    return e and (e.UIName or e.Name or classId) or tostring(classId)
end

SmithsReach.Stash = M
