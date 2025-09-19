-- [SmithsReach/Core.lua] - minimal, cleaned
SmithsReach          = SmithsReach or {}
SmithsReach._Session = SmithsReach._Session or { active = false }

-- Simple planner: cap per-kind, respect max_kinds, derive total budget.
-- in:  candidates = { [cid] = stash_count }
--      caps = { max_kinds, max_each, max_total }
-- out: plan = { {cid=..., want=...}, ... } (sorted, truncated to max_kinds)
--      budget = min(sum(want), caps.max_total or sum)
local function _plan_simple(candidates, caps)
    local max_each  = caps.max_each or 4
    local max_kinds = caps.max_kinds or math.huge
    local want_list = {}

    for cid, cnt in pairs(candidates) do
        local n = math.min(tonumber(cnt) or 0, max_each)
        if n > 0 then
            want_list[#want_list + 1] = { cid = cid, want = n }
        end
    end

    table.sort(want_list, function(a, b) return tostring(a.cid) < tostring(b.cid) end)

    if #want_list > max_kinds then
        for i = max_kinds + 1, #want_list do want_list[i] = nil end
    end

    local sum = 0
    for i = 1, #want_list do sum = sum + want_list[i].want end

    local budget = math.min(sum, caps.max_total or sum)
    return want_list, budget
end


-- Facade for debug (filled by Debug.lua; safe no-ops if not loaded)
SmithsReach.Debug               = SmithsReach.Debug or {}
SmithsReach.Debug.Ping          = SmithsReach.Debug.Ping or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.ConfigDump    = SmithsReach.Debug.ConfigDump or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.MatsWhere     = SmithsReach.Debug.MatsWhere or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.ScanUnmatched = SmithsReach.Debug.ScanUnmatched or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.Find          = SmithsReach.Debug.Find or
    function() System.LogAlways("[SmithsReach] debug not loaded") end

SmithsReach.Debug.StashMethods  = SmithsReach.Debug.StashMethods or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.StashNames    = SmithsReach.Debug.StashNames or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.StashSummary  = SmithsReach.Debug.StashSummary or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.StashRaw      = SmithsReach.Debug.StashRaw or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.StashDump     = SmithsReach.Debug.StashDump or
    function() System.LogAlways("[SmithsReach] debug not loaded") end

SmithsReach.Debug.ItemDump      = SmithsReach.Debug.ItemDump or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.InvMethods    = SmithsReach.Debug.InvMethods or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.InvDump       = SmithsReach.Debug.InvDump or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.InvSummary    = SmithsReach.Debug.InvSummary or
    function() System.LogAlways("[SmithsReach] debug not loaded") end
SmithsReach.Debug.DiffStashPl   = SmithsReach.Debug.DiffStashPl or
    function() System.LogAlways("[SmithsReach] debug not loaded") end

SmithsReach.Debug.PullOne       = SmithsReach.Debug.PullOne or
    function() System.LogAlways("[SmithsReach] debug not loaded") end

local function LOG(fmt, ...) System.LogAlways(("[SmithsReach] " .. fmt):format(...)) end
local function VLOG(fmt, ...)
    local B = SmithsReach.Config and SmithsReach.Config.Behavior or {}
    if B.verboseLogs then LOG(fmt, ...) end
end


-- ----- Defaults (authoritative, safe) -----
local DEFAULTS = {
    Behavior = {
        showTransferFX = true,
        verboseLogs    = true,
    },
    PullCaps = { max_kinds = 70, max_each = 4, max_total = 200 }
}

-- shallow+deep fill without clobbering user config
local function _deep_fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            _deep_fill(dst[k], v)
        else
            if dst[k] == nil then dst[k] = v end -- only fill when missing
        end
    end
end

-- Ensure config table exists (Config.lua should create it; this backs it up)
SmithsReach.Config = SmithsReach.Config or {}
_deep_fill(SmithsReach.Config, DEFAULTS)

-- (optional) quick sanity log
-- System.LogAlways("[SmithsReach] Config effective: kinds="..tostring(SmithsReach.Config.PullCaps.max_kinds))

local function _filterMats(raw)
    local out = {}
    for cid, cnt in pairs(raw or {}) do
        if SmithsReach.CraftingMats and SmithsReach.CraftingMats[cid] and cnt > 0 then
            out[cid] = cnt
        end
    end
    return out
end

-- Materials helpers (read-only) ---
-- keep this version only
local function _matSnapshot(entity, label)
    local snapWith = SmithsReach.Stash and SmithsReach.Stash.SnapshotWithLog
    local snapRaw  = SmithsReach.Stash and SmithsReach.Stash.Snapshot

    if type(snapWith) == "function" then
        local ok, raw = xpcall(function() return snapWith(entity, label) end, debug.traceback)
        if not ok then
            System.LogAlways("[SmithsReach] _matSnapshot ERROR (" .. tostring(label) .. "):\n" .. tostring(raw)); return {}
        end
        return _filterMats(raw)
    elseif type(snapRaw) == "function" then
        local ok, raw, meta = xpcall(function() return snapRaw(entity) end, debug.traceback)
        if not ok then
            System.LogAlways("[SmithsReach] _matSnapshot ERROR (" .. tostring(label) .. "):\n" .. tostring(raw)); return {}
        end
        local function k(t)
            local c = 0
            for _ in pairs(t or {}) do c = c + 1 end
            return c
        end
        System.LogAlways(("[SmithsReach][%s] Snapshot: entries=%s resolved=%s kinds=%d")
            :format(label or "INV", tostring(meta and meta.entries or "?"), tostring(meta and meta.resolved or "?"),
                k(raw)))
        return _filterMats(raw)
    else
        System.LogAlways("[SmithsReach] _matSnapshot: no Snapshot function available")
        return {}
    end
end

local function _sum(m)
    local s = 0
    for _, v in pairs(m or {}) do s = s + v end
    return s
end

local function _k(m)
    local c = 0
    for _ in pairs(m or {}) do c = c + 1 end
    return c
end

-- Minimal, robust delete-by-class for any inventory owner (entity or inventory)
local function _delete_class_units(invOwner, classId, need)
    need = tonumber(need) or 0
    if need <= 0 then return 0 end

    local inv = invOwner and (invOwner.inventory or invOwner)
    if not inv then return 0 end

    local removed = 0
    local classText = tostring(classId)

    -- 1) Preferred: engine bulk-by-class (loop per unit = precise & portable)
    if type(inv.DeleteItemOfClass) == "function" then
        for i = 1, need do
            local ok = pcall(function() inv:DeleteItemOfClass(classText, 1) end)
            if not ok then break end
            removed = removed + 1
        end
        return removed
    end

    -- 2) Fallback: per-item delete
    if type(inv.FindItem) == "function" and type(inv.DeleteItem) == "function" then
        for i = 1, need do
            local okF, wuid = pcall(function() return inv:FindItem(classId) end)
            if not okF or not wuid then break end
            local okD = pcall(function() inv:DeleteItem(wuid) end)
            if not okD then break end
            removed = removed + 1
        end
        return removed
    end

    return 0
end

local function _player_far_from(entity, distM, player)
    if not entity or not player then return false end

    -- Prefer Actor.CanInteractWith (game-authored proximity)
    if SmithsReach.Config.Close.useActorCanInteract
        and type(player.CanInteractWith) == "function" then
        local ok, can = pcall(function() return player:CanInteractWith(entity) end)
        if ok then return not can end
    end

    -- Fallback: Euclidean distance
    if player.GetPos and entity.GetPos then
        local p, s       = player:GetPos(), entity:GetPos()
        local dx, dy, dz = p.x - s.x, p.y - s.y, p.z - s.z
        local d2         = dx * dx + dy * dy + dz * dz
        local r          = (distM or SmithsReach.Config.Close.distM or 6.0)
        return d2 > (r * r)
    end

    return false
end

-- Optional extra hint (best-effort; safe if missing)
local function _smithery_usable_again(entity, player)
    if not entity or not player then return false end
    if type(entity.IsUsableBy) == "function" then
        local ok, isU = pcall(function() return entity:IsUsableBy(player) end)
        if ok then return isU == true end
    end
    return false
end

-- Count all inventory items that are NOT in the CraftingMats whitelist
local function _snapshot_nonmats(ent)
    local inv = ent and ent.inventory
    if not (inv and inv.GetInventoryTable) then return {} end
    local ok, tbl = pcall(function() return inv:GetInventoryTable() end)
    if not ok or not tbl then return {} end
    local out = {}
    for _, wuid in pairs(tbl) do
        local itm = ItemManager and ItemManager.GetItem and ItemManager.GetItem(wuid) or nil
        local cid = itm and (itm.classId or itm.class or itm.type)
        if cid and (not SmithsReach.CraftingMats or not SmithsReach.CraftingMats[cid]) then
            out[cid] = (out[cid] or 0) + 1
        end
    end
    return out
end

local function _toast_transfer(cid, amount)
    if not amount or amount == 0 then return end
    if Game and type(Game.ShowItemsTransfer) == "function" then
        pcall(function() Game.ShowItemsTransfer(tostring(cid), amount) end)
    else
        System.LogAlways(("[SmithsReach][Toast] %s %+d"):format(tostring(cid), amount))
    end
end

local function _ignore_delta_cid(cid)
    local ig = SmithsReach.Config.CraftedIgnore or {}
    if (ig.classIds or {})[cid] then return true end

    -- optional: fuzzy by UI name (best-effort)
    local nm
    if ItemManager and ItemManager.GetItemUIName then
        local ok, got = pcall(ItemManager.GetItemUIName, cid)
        if ok then nm = tostring(got or ""):lower() end
    end
    if nm and ig.namePatterns then
        for _, pat in ipairs(ig.namePatterns) do
            if pat ~= "" and string.find(nm, pat, 1, true) then return true end
        end
    end
    return false
end

function SmithsReach.Init()
    if UIAction and UIAction.RegisterEventSystemListener then
        UIAction.RegisterEventSystemListener(SmithsReach, "System", "OnGameplayStarted", "OnGameplayStarted")
    end

    -- Smithery hook (start of blacksmithing)
    System.AddCCommand("smithsreach_hook_smithery", "SmithsReach_HookSmithery()",
        "Wrap Smithery.OnUsed to detect minigame start")

    -- Minigame end listeners
    System.AddCCommand("smithsreach_hook_minigame", "SmithsReach_HookMinigame()", "Listen for minigame end events")

    -- Temp Crafting Close
    System.AddCCommand("smithsreach_craft_end", "SmithsReach_CraftEnd()",
        "Manually simulate blacksmithing end for testing")

    System.AddCCommand("smithsreach_hook_psh_end", "SmithsReach_HookPSHEnd()", "Wrap PlayerStateHandler end-of-minigame")
end

-- Find an OWNED bed (Sleep & Save) within radius of the given anchor entity (e.g., the stash).
-- strict: only beds that show "Sleep & Save"
local function _owned_bed_near_anchor(anchorEnt, radius)
    if not anchorEnt then return false, math.huge end
    if not (EntityModule and EntityModule.WillSleepingOnThisBedSave) then
        return false, math.huge
    end

    local av = SmithsReach.Util.Pos(anchorEnt)
    if not av then return false, math.huge end

    local list = (System.GetEntitiesInSphere and System.GetEntitiesInSphere(av, radius))
        or (System.GetEntities and System.GetEntities()) or {}
    local best = math.huge

    for _, e in pairs(list) do
        if e and (e.class == "Bed" or e.OnUsed or e.OnUsedHold) then
            local owned = EntityModule.WillSleepingOnThisBedSave(e.id)
            if owned then
                local ev = SmithsReach.Util.Pos(e)
                if ev then
                    local d = SmithsReach.Util.DistPos(ev, av)
                    if d < best then best = d end
                end
            end
        end
    end

    return (best ~= math.huge and best <= radius), (best ~= math.huge) and best or math.huge
end

local function _stash_ok(player, baseR, pad)
    local stash = SmithsReach.Stash and SmithsReach.Stash.GetStash and SmithsReach.Stash.GetStash()
    if not stash then return false, math.huge, nil end
    local d = SmithsReach.Util.DistEnt(player, stash)
    return d <= (baseR + (pad or 0)), d, stash
end

-- bed_ok that anchors to stash when available (or the player otherwise)
local function _bed_ok(player, baseR, pad, stashEnt)
    local B = SmithsReach.Config.Behavior or {}
    local radius = (baseR + (pad or 0))

    local anchor = (B.forgeBedSearch == "stash" and stashEnt) or player
    if not anchor then return false, math.huge end

    -- try strict owned-bed search near the chosen anchor
    local ok, d = _owned_bed_near_anchor(anchor, radius)
    if ok then return true, d end

    -- optional relaxed fallback if you want (toggle via B.forgeBedStrict)
    if B.forgeBedStrict == false then
        local av = SmithsReach.Util.Pos(anchor)
        if not av then return false, math.huge end
        local list = (System.GetEntitiesInSphere and System.GetEntitiesInSphere(av, radius))
            or (System.GetEntities and System.GetEntities()) or {}
        local best = math.huge
        for _, e in pairs(list) do
            if e and (e.class == "Bed" or e.OnUsed or e.OnUsedHold) then
                local ev = SmithsReach.Util.Pos(e)
                if ev then
                    local d2 = SmithsReach.Util.DistPos(ev, av)
                    if d2 < best then best = d2 end
                end
            end
        end
        return (best ~= math.huge and best <= radius), (best ~= math.huge) and best or math.huge
    end

    return false, math.huge
end

function SmithsReach_CheckForgeGate(is_close_phase)
    local B = SmithsReach.Config.Behavior or {}
    if not B.forgeProximityEnabled then return true end

    local player = SmithsReach.Util.Player()
    if not player then return false end

    local baseR                     = B.forgeProximityRadiusM or 12
    local pad                       = (is_close_phase and (B.forgeGateClosePadM or 3.0)) or (B.forgeGateOpenPadM or 1.0)

    -- 1) stash check (and keep the stash entity for bed anchoring)
    local stashOK, dStash, stashEnt = _stash_ok(player, baseR, pad)

    -- 2) bed check relative to stash (preferred) or player
    local bedOK, dBed               = false, math.huge
    if B.forgeNeedOwnedBed ~= false then
        bedOK, dBed = _bed_ok(player, baseR, pad, stashEnt)
    end

    -- 3) skill gate (use blacksmithing; fall back to maintenance)
    if B.requireMaintenanceLevel then
        local lvl = 0
        if player and player.soul then
            if type(player.soul.GetSkillLevel) == "function" then
                local ok, res = pcall(player.soul.GetSkillLevel, player.soul, "repairing")
                if ok and type(res) == "number" then
                    lvl = res
                else
                    -- fallback: maintenance (some builds)
                    ok, res = pcall(player.soul.GetSkillLevel, player.soul, "maintenance")
                    if ok and type(res) == "number" then lvl = res end
                end
            end
        end
        local need = B.requiredMaintenanceLevel or 15
        if lvl < need then
            if B.verboseLogs ~= false then
                System.LogAlways(("[SmithsReach] Gate blocked: smithing skill %d < required %d")
                    :format(lvl, need))
            end
            return false
        end
    end

    local mode = B.forgeGateMode or "either"
    local pass =
        (mode == "either" and (stashOK or bedOK)) or
        (mode == "both" and (stashOK and bedOK)) or
        (mode == "stash" and stashOK) or false

    if pass then
        if B.verboseLogs then
            System.LogAlways(("[SmithsReach] Gate OK (%s): stash=%.1fm, bed=%.1fm (≤ %.1f+%.1f)")
                :format(mode, dStash or -1, dBed or -1, baseR, pad))
        end
        return true
    else
        if B.verboseLogs ~= false then
            System.LogAlways(("[SmithsReach] Gate blocked (%s): stash=%.1fm, bed=%.1fm (r=%.1f+%.1f)")
                :format(mode, dStash or -1, dBed or -1, baseR, pad))
        end
        return false
    end
end

function SmithsReach.OnGameplayStarted(actionName, eventName, argTable)
    System.LogAlways("[SmithsReach] Initialized!")

    if SmithsReach.Config and SmithsReach.Config.Behavior.verboseLogs then
        System.LogAlways("[SmithsReach] Effective Config dump:")
        local function dump(tbl, indent)
            indent = indent or ""
            for k, v in pairs(tbl) do
                if type(v) == "table" then
                    System.LogAlways(indent .. tostring(k) .. ":")
                    dump(v, indent .. "  ")
                else
                    System.LogAlways(indent .. tostring(k) .. " = " .. tostring(v))
                end
            end
        end
        dump(SmithsReach.Config, "  ")
    end
end

-- Global wrappers (console-friendly) ----
function SmithsReach_HookSmithery() SmithsReach.HookSmithery() end

function SmithsReach_HookMinigame() SmithsReach.HookMinigame() end

function SmithsReach_CraftEnd() SmithsReach._ForgeOnClose() end

-- Internals ----
function SmithsReach.HookSmithery()
    if not Smithery then
        System.LogAlways("[SmithsReach] HookSmithery: Smithery table not found (load order?)")
        return
    end
    if SmithsReach._orig_Smithery_OnUsed then
        System.LogAlways("[SmithsReach] HookSmithery: already hooked")
        return
    end

    local orig = Smithery.OnUsed
    if type(orig) ~= "function" then
        System.LogAlways("[SmithsReach] HookSmithery: Smithery.OnUsed is not a function")
        return
    end

    SmithsReach._orig_Smithery_OnUsed = orig
    Smithery.OnUsed = function(self, user, slot)
        System.LogAlways("[SmithsReach] Blacksmithing BEGIN (Smithery.OnUsed)")

        -- Call our open with the actual station + args (pre-vanilla so mats are ready as UI mounts)
        if type(SmithsReach._ForgeOnOpen) == "function" then
            local ok, err = xpcall(function()
                SmithsReach._ForgeOnOpen(self, user, slot) -- << pass station/user/slot
            end, debug.traceback)
            if not ok then
                System.LogAlways("[SmithsReach] _ForgeOnOpen ERROR:\n" .. tostring(err))
            end
        end

        -- Call vanilla behavior (starts the minigame)
        return orig(self, user, slot) -- note: colon-call semantics preserved
    end

    System.LogAlways("[SmithsReach] HookSmithery: OK (OnUsed wrapped)")
end

function SmithsReach.HookMinigame()
    if not (UIAction and UIAction.RegisterEventSystemListener) then
        System.LogAlways("[SmithsReach] HookMinigame: UIAction listener API missing")
        return
    end

    local function wrap(tag)
        return function(...)
            -- log args to discover the signature in this build
            System.LogAlways("[SmithsReach] " .. tag .. " fired args=" .. tostring(select("#", ...)))
            -- If we can read 'type' from args, gate on blacksmithing here.
            -- For now, just call close unconditionally; we’ll refine after one capture.
            if SmithsReach._ForgeOnClose then pcall(SmithsReach._ForgeOnClose) end
        end
    end

    -- Try multiple buses & event names; harmless if some don’t exist:
    UIAction.RegisterEventSystemListener(SmithsReach, "Minigame", "OnMinigameFinished", "SmithsReach_OnMgFinished",
        wrap("OnMinigameFinished"))
    UIAction.RegisterEventSystemListener(SmithsReach, "Minigame", "OnMinigameAborted", "SmithsReach_OnMgAborted",
        wrap("OnMinigameAborted"))
    UIAction.RegisterEventSystemListener(SmithsReach, "Minigame", "OnMinigameEnded", "SmithsReach_OnMgEnded",
        wrap("OnMinigameEnded"))
    UIAction.RegisterEventSystemListener(SmithsReach, "PlayerStateHandler", "OnMinigameFinished",
        "SmithsReach_OnPshFinished", wrap("PSH.OnMinigameFinished"))

    System.LogAlways("[SmithsReach] HookMinigame: listeners registered")
end

function SmithsReach._ForgeOnOpen(stationEnt, user, slot)
    System.LogAlways("[SmithsReach] _ForgeOnOpen: enter")
    local player = SmithsReach.Util.Player()
    if not SmithsReach_CheckForgeGate(false) then
        -- Optional: clarity log
        local B = SmithsReach.Config.Behavior or {}
        if B.verboseLogs ~= false then
            System.LogAlways("[SmithsReach] Gate blocked on OPEN – transfers disabled.")
        end
        return -- ✅ nothing cloned
    end

    -- Soft-restart if a session was left active
    if SmithsReach._Session and SmithsReach._Session.active then
        pcall(SmithsReach._ForgeOnClose)
    end

    -- Resolve stash/player
    local stashEnt = SmithsReach.Stash.GetStash()
    if not (stashEnt and stashEnt.inventory and player and player.inventory) then
        System.LogAlways("[SmithsReach] _ForgeOnOpen: missing stash/player"); return
    end

    -- BEFORE snapshots
    local P_before = _matSnapshot(player, "Player")
    local S_before = _matSnapshot(stashEnt, "Stash")

    -- Clone bounded mats from stash -> player (stash unchanged)
    local cloned, clonedTotal, kinds, total = {}, 0, 0, 0
    local caps = SmithsReach.Config.PullCaps

    -- Build a simple plan capped per-kind and derive a budget from the stash snapshot
    local plan, budget = _plan_simple(S_before, caps)

    -- Hard safety cap to avoid runaway creation (defensive)
    local HARD_MAX = 200
    if budget > HARD_MAX then budget = HARD_MAX end

    for i = 1, #plan do
        local cid  = plan[i].cid
        local want = plan[i].want
        if want > 0 then
            kinds = kinds + 1
            local give = math.min(want, budget - clonedTotal)
            for j = 1, give do
                local ok = pcall(function()
                    player.inventory:CreateItem(cid, 1, 1)
                end)
                if ok then
                    cloned[cid] = (cloned[cid] or 0) + 1
                    clonedTotal = clonedTotal + 1
                    total       = total + 1
                    if clonedTotal >= budget then break end
                end
            end
            if clonedTotal >= budget then break end
        end
    end

    -- New session UID
    SmithsReach._SessionSerial = (SmithsReach._SessionSerial or 0) + 1
    local uid                  = SmithsReach._SessionSerial

    -- Build the session FIRST...
    local sess                 = {
        uid        = uid,
        active     = true,
        station_id = stationEnt and stationEnt.id or nil, -- used by proximity watcher
        stash_id   = stashEnt.id,
        player_id  = player and player.id or nil,
        P_before   = P_before,
        S_before   = S_before,
        cloned     = cloned,
    }

    -- session environment (used by poller/cancel logic)
    sess.smitheryEnt           = stationEnt
    sess.smitheryPos           = (stationEnt and stationEnt.GetPos and stationEnt:GetPos()) or
        (player and player.GetPos and player:GetPos()) or nil
    sess.armedAtMs             = (Game and Game.GetTimeMs and Game:GetTimeMs()) or 0


    -- ...then record the NON-material baseline AFTER cloning
    sess.NM_before = _snapshot_nonmats(player)

    -- Publish the session
    SmithsReach._Session = sess

    VLOG("OPEN: player %d/%d  stash %d/%d  cloned %d kinds / %d items",
        _k(P_before), _sum(P_before), _k(S_before), _sum(S_before), _k(cloned), clonedTotal)

    if not (SmithsReach.Config.Behavior or {}).verboseLogs then
        LOG("OPEN: cloned %d kinds / %d items", kinds, clonedTotal)
    end

    -- show item transfer
    do
        local N = SmithsReach.Config.Notif or {}
        if N.onOpen then
            local shown = 0
            for cid, n in pairs(cloned) do
                if n > 0 then
                    _toast_transfer(cid, n) -- +N into player
                    shown = shown + 1
                    if shown >= (N.maxItems or 8) then break end
                end
            end
        end
    end

    -- Start watchers AFTER session is set
    --if SmithsReach._StartProximityClose then SmithsReach._StartProximityClose() end
    if SmithsReach._StartCraftDetect then SmithsReach._StartCraftDetect() end

    SmithsReach._StartPoller() -- new poller, no UI dependency
end

function SmithsReach._ForgeOnClose()
    if not SmithsReach_CheckForgeGate(true) then
        local B = SmithsReach.Config.Behavior or {}
        if B.verboseLogs ~= false then
            System.LogAlways("[SmithsReach] Gate blocked on CLOSE – nothing to reconcile.")
        end
        return -- ✅ no stash reconciliation / return
    end
    local sess = SmithsReach._Session
    if not (sess and sess.active) then
        System.LogAlways("[SmithsReach] CLOSE: no active session"); return
    end

    local player = SmithsReach.Util.Player()

    local stashEnt = System.GetEntity and System.GetEntity(sess.stash_id)
    if not (stashEnt and stashEnt.inventory and player and player.inventory) then
        System.LogAlways("[SmithsReach] CLOSE: missing stash/player"); sess.active = false; return
    end

    -- AFTER snapshot
    local P_after            = _matSnapshot(player, "INV")

    local P0                 = sess.P_before or {}
    local C                  = sess.cloned or {}

    -- build per-class maps first (no mutations yet)
    local usedMap, leftMap   = {}, {}
    local wantUsed, wantLeft = 0, 0

    for cid, c in pairs(C) do
        local p0 = P0[cid] or 0
        local p1 = P_after[cid] or 0
        local delta = p1 - p0 -- extra mats still on player
        if delta < 0 then delta = 0 end
        if delta > c then delta = c end

        local leftN = delta     -- leftover clones to remove from player
        local usedN = c - delta -- mats to debit from stash

        if usedN > 0 then
            usedMap[cid] = usedN; wantUsed = wantUsed + usedN
        end
        if leftN > 0 then
            leftMap[cid] = leftN; wantLeft = wantLeft + leftN
        end
    end

    -- 1) Stash -= used
    local remUsed = 0
    for cid, u in pairs(usedMap) do
        local n = _delete_class_units(stashEnt, cid, u) or 0
        remUsed = remUsed + n
        if n < u then
            System.LogAlways(("[SmithsReach] WARN: stash shortfall class=%s want=%d removed=%d")
                :format(tostring(cid), u, n))
        end
    end

    -- 2) Player -= leftover clones (and toast once per cid)
    local remLeft = 0
    do
        local N = SmithsReach.Config.Notif or {}
        local maxLines = N.maxItems or 8
        local shown = 0
        for cid, l in pairs(leftMap) do
            local n = _delete_class_units(player, cid, l) or 0
            remLeft = remLeft + n
            if n < l then
                System.LogAlways(("[SmithsReach] WARN: player leftover shortfall class=%s want=%d removed=%d")
                    :format(tostring(cid), l, n))
            end
            if N.onClose and n > 0 and shown < maxLines then
                _toast_transfer(cid, -n) -- built-in Game.ShowItemsTransfer
                shown = shown + 1
            end
        end
    end

    VLOG("CLOSE: want_used=%d want_leftover=%d | removed_used=%d removed_leftover=%d",
        wantUsed, wantLeft, remUsed, remLeft)
    LOG("CLOSE: used=%d  returned=%d", remUsed, remLeft)

    sess.active = false
end

function SmithsReach_HookPSHEnd()
    if not PlayerStateHandler then
        System.LogAlways("[SmithsReach] PSH hook: PlayerStateHandler not found")
        return
    end

    -- try to wrap both; whichever exists will help
    local function wrapIf(funcName)
        local orig = PlayerStateHandler[funcName]
        if type(orig) ~= "function" then return false end
        if SmithsReach["_orig_PSH_" .. funcName] then return true end

        SmithsReach["_orig_PSH_" .. funcName] = orig
        PlayerStateHandler[funcName] = function(...)
            local r = orig(...)
            if SmithsReach._Session and SmithsReach._Session.active then
                System.LogAlways("[SmithsReach] PSH " .. funcName .. " -> closing forge session")
                pcall(function() SmithsReach._ForgeOnClose() end)
            end
            return r
        end
        return true
    end

    local any = wrapIf("EndMinigame") or wrapIf("FinishMinigame")
    System.LogAlways("[SmithsReach] PSH hook: " .. (any and "OK" or "no target functions"))
end

-- Proximity-only close watcher / Terrible way to detect when blacksmithing is closed
local function _dist2(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

function SmithsReach._StartProximityClose()
    local s = SmithsReach._Session
    if not (s and s.active and s.station_id and s.player_id) then return end
    if s._closeRunning then return end
    s._closeRunning, s._awayTicks = true, 0

    local cfg                     = SmithsReach.Config.Close or { distM = 2.0, graceTicks = 2, tickMs = 200 }
    local dist2Limit              = (cfg.distM or 2.0) ^ 2
    local grace                   = cfg.graceTicks or 2
    local tickMs                  = cfg.tickMs or 200

    local function tick()
        if not (SmithsReach._Session and SmithsReach._Session.active) then
            s._closeRunning = false; return
        end
        local station = System.GetEntity(s.station_id)
        local pl      = System.GetEntity(s.player_id)
        if not station or not pl then
            s._closeRunning = false; return
        end

        local sp, pp = station:GetWorldPos(), pl:GetWorldPos()
        if not sp or not pp then
            s._closeRunning = false; return
        end

        if _dist2(pp, sp) >= dist2Limit then
            s._awayTicks = s._awayTicks + 1
            if s._awayTicks >= grace then
                System.LogAlways(("[SmithsReach] END via proximity (>%.1fm)"):format(math.sqrt(dist2Limit)))
                SmithsReach._ForgeOnClose()
                s._closeRunning = false
                return
            end
        else
            s._awayTicks = 0
        end
        Script.SetTimer(tickMs, tick)
    end

    Script.SetTimer(tickMs, tick)
end

-- Close when a new NON-material item appears in player inventory
function SmithsReach._StartCraftDetect()
    local s = SmithsReach._Session
    if not (s and s.active and s.player_id and s.NM_before) then return end
    if s._craftDetectRunning then return end
    s._craftDetectRunning = true
    s._craftConfirm = 0

    local tickMs = (SmithsReach.Config.Close and SmithsReach.Config.Close.tickMs) or 200
    local uid = s.uid or 0

    local function tick()
        if not SmithsReach._Session or SmithsReach._Session ~= s or (s.uid and SmithsReach._Session.uid ~= uid) then
            return
        end
        if not s.active then
            s._craftDetectRunning = false; return
        end

        local pl = System.GetEntity(s.player_id)
        if not pl then
            s._craftDetectRunning = false; return
        end

        local nowNM = _snapshot_nonmats(pl)
        local increased = false

        -- any non-mat cid whose count grew vs baseline?
        for cid, nowCnt in pairs(nowNM) do
            local base = s.NM_before[cid] or 0
            if nowCnt > base then
                increased = true; break
            end
        end
        -- also treat entirely new non-mat cid as increase
        if not increased then
            for cid, _ in pairs(s.NM_before) do
                -- no-op; above loop already handles growth; new cids are covered by the first loop too
            end
        end

        if increased then
            s._craftConfirm = s._craftConfirm + 1
            if s._craftConfirm >= 2 then -- small debounce
                System.LogAlways("[SmithsReach] END via crafted output detected")
                SmithsReach._ForgeOnClose()
                s._craftDetectRunning = false
                return
            end
        else
            s._craftConfirm = 0
        end

        Script.SetTimer(tickMs, tick)
    end

    Script.SetTimer(tickMs, tick)
end

function SmithsReach._StartPoller()
    local cfg      = SmithsReach.Config.Heartbeat or {}
    local close    = SmithsReach.Config.Close or {}
    local interval = cfg.intervalMs or 250

    local S        = SmithsReach._Session
    if not (S and S.active) then return end
    S._ticks        = 0
    S._settle       = 0
    S.craftedSeen   = false
    S.lastCraftTick = nil

    local function nowMs()
        return (Game and Game.GetTimeMs and Game:GetTimeMs()) or (S._ticks * interval)
    end

    local function far_or_usable_again()
        local pl = System.GetEntity(S.player_id)
        local far = _player_far_from(S.smitheryEnt, close.distM, pl)
        local usable = _smithery_usable_again(S.smitheryEnt, pl)
        return far or usable
    end

    local function beat()
        if not (SmithsReach._Session and SmithsReach._Session.active and SmithsReach._Session == S) then return end
        S._ticks = S._ticks + 1

        -- DEBUG heartbeat logging
        if SmithsReach.Config.Behavior.verboseLogs and (S._ticks % 10 == 0) then
            System.LogAlways(("[SmithsReach][HB] waiting… crafted=%s settle=%d")
                :format(S.craftedSeen and "yes" or "no", S._settle or 0))
        end

        -- ARMING window: ignore cancel checks (walk-in animation etc.)
        local armed                            = (nowMs() - (S.armedAtMs or 0)) >= (cfg.armMs or 1500)

        -- === Detect crafted outputs (non-mats deltas) with ignore filter ===
        local nowNM                            = _snapshot_nonmats(pl)
        local baseNM                           = S.NM_before or {}
        local rawCount, ignoredCount, effCount = 0, 0, 0
        local effItems                         = {}

        for cid, nowCnt in pairs(nowNM) do
            local before = baseNM[cid] or 0
            if nowCnt > before then
                rawCount = rawCount + 1
                if _ignore_delta_cid(cid) then
                    ignoredCount = ignoredCount + 1
                    -- IMPORTANT: raise baseline for ignored cids so they don't retrigger next tick
                    baseNM[cid] = nowCnt
                    if SmithsReach.Config.Behavior.verboseLogs then
                        System.LogAlways(("[SmithsReach][HB] ignore delta: cid=%s +%d (tool/work item)")
                            :format(tostring(cid), nowCnt - before))
                    end
                else
                    effCount = effCount + 1
                    table.insert(effItems, { cid = cid, gain = nowCnt - before, total = nowCnt })
                end
            end
        end

        if effCount > 0 then
            -- Log exactly what we think is crafted
            for _, d in ipairs(effItems) do
                local ui = (ItemManager and ItemManager.GetItemUIName and ItemManager.GetItemUIName(d.cid)) or "?"
                VLOG("[Crafted] %s (cid=%s) +%d → total=%d",
                    (ItemManager and ItemManager.GetItemUIName and ItemManager.GetItemUIName(d.cid)) or "?",
                    tostring(d.cid), d.gain, d.total)
            end

            local totalGain = 0
            for _, d in ipairs(effItems) do totalGain = totalGain + (d.gain or 0) end
            if not (SmithsReach.Config.Behavior or {}).verboseLogs then
                LOG("CRAFTED: +%d item(s)", totalGain)
            end

            S.craftedSeen   = true
            S.lastCraftTick = S._ticks
            S._settle       = 0

            if SmithsReach.Config.Heartbeat.endOnFirstCrafted == true then
                System.LogAlways("[SmithsReach] END via crafted output detected")
                xpcall(SmithsReach._ForgeOnClose, debug.traceback); return
            end
        else
            -- no effective (non-ignored) deltas this tick
            S._settle = (S._settle or 0) + 1
        end

        -- CANCEL path (only after arming): no craft ever + far/usable-again for long enough
        if armed and not S.craftedSeen and (close.enableProximity == true) then
            S._farTicks = (S._farTicks or 0) + (far_or_usable_again() and 1 or 0)
            local farMs = (S._farTicks or 0) * interval
            if farMs >= (cfg.cancelFarMs or 4000) then
                VLOG("END (cancel: far/usable-again & no craft)"); LOG("END (cancel)")
                xpcall(SmithsReach._ForgeOnClose, debug.traceback)
                return
            end
        end

        -- Absolute cancel ceiling (even if still near)
        if armed and not S.craftedSeen then
            if (nowMs() - (S.armedAtMs or 0)) >= (cfg.cancelMaxMs or (12 * 60 * 1000)) then
                VLOG("END (cancel: absolute timeout)"); LOG("END (timeout)")
                xpcall(SmithsReach._ForgeOnClose, debug.traceback)
                return
            end
        end

        -- COMPLETE path: we saw craft, then no new deltas for 'settleBeats' OR idle since last delta for long enough
        if S.craftedSeen then
            local cfg        = SmithsReach.Config.Heartbeat or {}
            local settled    = (S._settle or 0) >= (cfg.settleBeats or 3)
            local ticksSince = S.lastCraftTick and (S._ticks - S.lastCraftTick) or math.huge
            local msSince    = ticksSince * ((cfg.intervalMs or 250))
            local longIdle   = msSince >= (cfg.completeIdleMs or 4000)

            if settled or longIdle then
                VLOG("END (complete: outputs settled)"); LOG("END (complete)")
                xpcall(SmithsReach._ForgeOnClose, debug.traceback); return
            end
        end


        Script.SetTimer(interval, beat)
    end

    -- kick
    Script.SetTimer(interval, beat)
end
