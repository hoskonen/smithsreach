-- [SmithsReach/Core.lua] - minimal, cleaned
SmithsReach = SmithsReach or {}
SmithsReach._Session = SmithsReach._Session or { active = false }

-- ----- Defaults (authoritative, safe) -----
local DEFAULTS = {
    Behavior = {
        showTransferFX = true,
        verboseLogs    = true,
    },
    PullCaps = {
        max_kinds = 12,
        max_each  = 10,
        max_total = 60,
    },
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

local function _is_visible(name)
    if not (UIAction and UIAction.IsVisible) then return nil end
    local ok, res = pcall(function() return UIAction:IsVisible(name) end)
    if ok and type(res) == "boolean" then return res end
    ok, res = pcall(function() return UIAction:IsVisible(name, 0, nil) end)
    if ok and type(res) == "boolean" then return res end
    return nil
end

local function _any_visible(names)
    local any, known = false, false
    for _, n in ipairs(names or {}) do
        local v = _is_visible(n)
        if v ~= nil then known = true end
        if v == true then return true, true end
    end
    return false, known
end

-- raw snapshot of all classes
local function _snapshot_raw_map(entity, label)
    local with = SmithsReach.Stash and SmithsReach.Stash.SnapshotWithLog
    if type(with) == "function" then return with(entity, label) end
    local raw = {}
    local ok, map = pcall(function()
        local t, _ = SmithsReach.Stash.Snapshot(entity); return t
    end)
    if ok and map then raw = map end
    return raw
end

local function _filter_non_mats(raw)
    local out = {}
    for cid, n in pairs(raw or {}) do
        if n > 0 and not (SmithsReach.CraftingMats and SmithsReach.CraftingMats[cid]) then
            out[cid] = n
        end
    end
    return out
end

local function _positive_deltas(curr, base)
    local d = {}
    for cid, n in pairs(curr or {}) do
        local b = (base and base[cid]) or 0
        if n > b then d[cid] = n - b end
    end
    return d
end

function SmithsReach.Init()
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

    -- Events
    System.AddCCommand("smithsreach_craft_probe", "SmithsReach_CraftProbe()",
        "Probe ApseCrafting* elements for OnShow/OnHide and FC_*")

    -- Crafting FC hooks (ApseCraftingContent) ---
    System.AddCCommand("smithsreach_craft_bind", "SmithsReach_CraftBind()",
        "Bind to ApseCraftingContent fc_activateCrafting/fc_deactivateCrafting")

    -- Config Dump
    System.AddCCommand("smithsreach_config_dump", "SmithsReach_ConfigDump()", "Print effective SmithsReach config")

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

    -- Where are my mats? (scan whitelist across stash & player)
    System.AddCCommand("smithsreach_mats_where", "SmithsReach_MatsWhere()",
        "Show counts for each known mat in stash vs player")

    -- Find by substring in UI/DB name (to discover things like charcoal/ore/ingot)
    System.AddCCommand("smithsreach_find", "SmithsReach_Find()", "Usage: smithsreach_find <substring>")

    System.AddCCommand("smithsreach_hook_psh_end", "SmithsReach_HookPSHEnd()", "Wrap PlayerStateHandler end-of-minigame")

    System.AddCCommand("smithsreach_scan_unmatched", "SmithsReach_ScanUnmatched()",
        "List items in stash that are NOT in CraftingMats (up to 40)")

    -- optional: once you know the exact id, a targeted listener
    System.AddCCommand("smithsreach_craft_listen", "SmithsReach_CraftListen()",
        "Usage: smithsreach_craft_listen <ElementId>")
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

function SmithsReach_CraftProbe() SmithsReach.DebugCraftProbe() end

function SmithsReach_CraftBind() SmithsReach.DebugCraftBind() end

function SmithsReach_HookSmithery() SmithsReach.HookSmithery() end

function SmithsReach_HookMinigame() SmithsReach.HookMinigame() end

function SmithsReach_CraftEnd() SmithsReach._ForgeOnClose() end

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

function SmithsReach.DebugCraftProbe()
    if not UIAction then
        System.LogAlways("[SmithsReach] craft_probe: UIAction not available")
        return
    end

    local ids = {
        "ApseCraftingContent",
        "ApseCraftingList",
        "ApseModalDialog",
        -- a couple of likely fallbacks if the symbol name differs from file name
        "CraftingContent", "CraftingList", "ModalDialog",
    }

    local function regElem(id, ev, tag, fn)
        if UIAction.RegisterElementListener then
            UIAction.RegisterElementListener(id, ev, tag .. "_" .. id, fn)
        end
    end

    local function regFC(id, cb, tag, fn)
        -- try both common callback registration names, if present in this build
        if UIAction.RegisterFlashCallback then
            UIAction.RegisterFlashCallback(id, cb, tag .. "_" .. id .. "_" .. cb, fn)
        elseif UIAction.RegisterElementFCListener then
            UIAction.RegisterElementFCListener(id, cb, tag .. "_" .. id .. "_" .. cb, fn)
        end
    end

    for _, id in ipairs(ids) do
        -- element show/hide
        regElem(id, "OnShow", "[SmithsReach] CRAFT OnShow",
            function() System.LogAlways("[SmithsReach] CRAFT OnShow: " .. id) end)
        regElem(id, "OnHide", "[SmithsReach] CRAFT OnHide",
            function() System.LogAlways("[SmithsReach] CRAFT OnHide: " .. id) end)

        -- a couple of focus-y events sometimes used
        regElem(id, "OnFocus", "[SmithsReach] CRAFT OnFocus",
            function() System.LogAlways("[SmithsReach] CRAFT OnFocus: " .. id) end)
        regElem(id, "OnFocusLost", "[SmithsReach] CRAFT OnFocusLost",
            function() System.LogAlways("[SmithsReach] CRAFT OnFocusLost: " .. id) end)

        -- Flash callbacks (case/variant coverage)
        for _, cb in ipairs({ "FC_Open", "FC_Close", "fc_open", "fc_close", "Open", "Close" }) do
            regFC(id, cb, "[SmithsReach] CRAFT FC", function(...)
                System.LogAlways("[SmithsReach] CRAFT FC " .. cb .. ": " .. id)
            end)
        end
    end

    System.LogAlways("[SmithsReach] craft_probe: listeners registered on " .. #ids .. " ids")
end

function SmithsReach_CraftListen()
    local args = System.GetCVarArg and System.GetCVarArg() or {}
    local id = args[1]
    if not id then
        System.LogAlways("[SmithsReach] usage: smithsreach_craft_listen <ElementId>")
        return
    end
    if not (UIAction and UIAction.RegisterElementListener) then
        System.LogAlways("[SmithsReach] craft_listen: UIAction missing")
        return
    end
    UIAction.RegisterElementListener(id, "OnShow", "SmithsReach_Forge_OnShow",
        function() System.LogAlways("[SmithsReach] Forge UI OnShow (" .. id .. ")") end)
    UIAction.RegisterElementListener(id, "OnHide", "SmithsReach_Forge_OnHide",
        function() System.LogAlways("[SmithsReach] Forge UI OnHide (" .. id .. ")") end)
    System.LogAlways("[SmithsReach] Forge listeners registered for '" .. id .. "'")
end

function SmithsReach.DebugCraftBind()
    if not UIAction then
        System.LogAlways("[SmithsReach] craft_bind: UIAction not available")
        return
    end

    local id = "ApseCraftingContent"

    local function regFC(cb, tag, fn)
        -- Try both common registration APIs (build-dependent)
        if UIAction.RegisterFlashCallback then
            UIAction.RegisterFlashCallback(id, cb, tag .. "_" .. cb, fn)
            return true
        elseif UIAction.RegisterElementFCListener then
            UIAction.RegisterElementFCListener(id, cb, tag .. "_" .. cb, fn)
            return true
        end
        return false
    end

    local ok1 = regFC("fc_activateCrafting", "[SmithsReach] CRAFT",
        function(anim) System.LogAlways("[SmithsReach] fc_activateCrafting anim=" .. tostring(anim)) end)
    local ok2 = regFC("fc_deactivateCrafting", "[SmithsReach] CRAFT",
        function(anim) System.LogAlways("[SmithsReach] fc_deactivateCrafting anim=" .. tostring(anim)) end)

    -- Fallback: also listen to element show/hide (some builds emit these too)
    if UIAction.RegisterElementListener then
        UIAction.RegisterElementListener(id, "OnShow", "SmithsReach_CRAFT_OnShow",
            function() System.LogAlways("[SmithsReach] CRAFT OnShow") end)
        UIAction.RegisterElementListener(id, "OnHide", "SmithsReach_CRAFT_OnHide",
            function() System.LogAlways("[SmithsReach] CRAFT OnHide") end)
    end

    System.LogAlways("[SmithsReach] craft_bind: bound to " ..
        id .. " (fc_activate/ fc_deactivate; plus OnShow/OnHide fallback). "
        .. "FC ok: " .. tostring(ok1 and ok2))
end

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
    for cid, cnt in pairs(S_before) do
        if kinds >= caps.max_kinds or total >= caps.max_total then break end
        local give = math.min(cnt, caps.max_each, caps.max_total - clonedTotal)
        if give > 0 then
            pcall(function() player.inventory:CreateItem(cid, give, 1) end)
            cloned[cid] = give
            clonedTotal = clonedTotal + give
            kinds = kinds + 1
            total = total + give
        end
    end

    -- New session UID
    SmithsReach._SessionSerial = (SmithsReach._SessionSerial or 0) + 1
    local uid = SmithsReach._SessionSerial

    -- Build the session FIRST...
    local sess = {
        uid        = uid,
        active     = true,
        station_id = stationEnt and stationEnt.id or nil, -- used by proximity watcher
        stash_id   = stashEnt.id,
        player_id  = player and player.id or nil,
        P_before   = P_before,
        S_before   = S_before,
        cloned     = cloned,
    }

    -- ...then record the NON-material baseline AFTER cloning
    sess.NM_before = _snapshot_nonmats(player)

    -- Publish the session
    SmithsReach._Session = sess

    System.LogAlways(("[SmithsReach] OPEN: player %d/%d  stash %d/%d  cloned %d kinds / %d items")
        :format(_k(P_before), _sum(P_before), _k(S_before), _sum(S_before), _k(cloned), clonedTotal))

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
    if SmithsReach._StartProximityClose then SmithsReach._StartProximityClose() end
    if SmithsReach._StartCraftDetect then SmithsReach._StartCraftDetect() end

    SmithsReach._StartHeartbeat()
end

function SmithsReach._ForgeOnClose()
    local sess = SmithsReach._Session
    if not (sess and sess.active) then
        System.LogAlways("[SmithsReach] CLOSE: no active session"); return
    end

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

    System.LogAlways(("[SmithsReach] CLOSE: want_used=%d want_leftover=%d | removed_used=%d removed_leftover=%d")
        :format(wantUsed, wantLeft, remUsed, remLeft))

    sess.active = false
end

function SmithsReach_Find()
    local args = System.GetCVarArg and System.GetCVarArg() or {}
    local q = args[1]
    if not q or q == "" then
        System.LogAlways("[SmithsReach] usage: smithsreach_find <substring>"); return
    end
    q = string.lower(q)

    local s = SmithsReach.Stash.GetStash()
    if not (s and s.inventory) then
        System.LogAlways("[SmithsReach] find: stash not found"); return
    end
    local S = SmithsReach.Stash.Snapshot(s)

    local shown = 0
    for cid, cnt in pairs(S) do
        if cnt > 0 then
            local ui, db = nil, nil
            if ItemManager then
                local okUi, uiName = pcall(function() return ItemManager.GetItemUIName(cid) end); if okUi then
                    ui =
                        uiName
                end
                local okDb, dbName = pcall(function() return ItemManager.GetItemName(cid) end); if okDb then
                    db =
                        dbName
                end
            end
            local name = string.lower(tostring(ui or db or ""))
            if name ~= "" and string.find(name, q, 1, true) then
                System.LogAlways(("[SmithsReach] FIND %s (%s) x%d  class=%s"):format(tostring(ui or "?"),
                    tostring(db or "?"), cnt, cid))
                shown = shown + 1
                if shown >= 60 then
                    System.LogAlways("[SmithsReach] find: truncated"); break
                end
            end
        end
    end
    if shown == 0 then System.LogAlways("[SmithsReach] find: no matches for '" .. q .. "' in stash") end
end

function SmithsReach_MatsWhere()
    local s = SmithsReach.Stash.GetStash()
    if not (s and s.inventory and player and player.inventory) then
        System.LogAlways("[SmithsReach] mats_where: missing stash/player"); return
    end
    local S = SmithsReach.Stash.Snapshot(s)      -- all items by classId
    local P = SmithsReach.Stash.Snapshot(player) -- all items by classId
    local hits = 0
    for cid, meta in pairs(SmithsReach.CraftingMats or {}) do
        local sc = S[cid] or 0
        local pc = P[cid] or 0
        if sc > 0 or pc > 0 then
            local name = meta.UIName or meta.Name or cid
            System.LogAlways(("[SmithsReach] MAT %s  stash=%d  player=%d  class=%s"):format(tostring(name), sc, pc,
                cid))
            hits = hits + 1
        end
    end
    if hits == 0 then System.LogAlways("[SmithsReach] mats_where: no Type=3 mats found in stash/player") end
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

function SmithsReach_ConfigDump()
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
    System.LogAlways("[SmithsReach] Config dump:")
    dump(SmithsReach.Config)
end

function SmithsReach.HookCraftingUI()
    if not (UIAction and UIAction.RegisterElementListener) then return end
    UIAction.RegisterElementListener("ApseCraftingContent", "OnHide",
        "SmithsReach_Crafting_OnHide",
        function()
            if SmithsReach._Session and SmithsReach._Session.active then
                System.LogAlways("[SmithsReach] Blacksmithing END (ApseCraftingContent.OnHide)")
                pcall(SmithsReach._ForgeOnClose)
            end
        end
    )
    if SmithsReach.Config.Behavior.verboseLogs then
        System.LogAlways("[SmithsReach] Hooked ApseCraftingContent.OnHide")
    end
end

function SmithsReach_ScanUnmatched()
    local s = SmithsReach.Stash.GetStash()
    if not (s and s.inventory) then
        System.LogAlways("[SmithsReach] scan_unmatched: no stash"); return
    end
    local raw = SmithsReach.Stash.Snapshot(s)
    local shown = 0
    for cid, cnt in pairs(raw) do
        if cnt > 0 and (not SmithsReach.CraftingMats or not SmithsReach.CraftingMats[cid]) then
            local ui = ItemManager and ItemManager.GetItemUIName and ItemManager.GetItemUIName(cid) or nil
            local db = ItemManager and ItemManager.GetItemName and ItemManager.GetItemName(cid) or nil
            System.LogAlways(("[SmithsReach] UNMATCHED %s (%s) x%d  class=%s")
                :format(tostring(ui or "?"), tostring(db or "?"), cnt, cid))
            shown = shown + 1; if shown >= 40 then
                System.LogAlways("[SmithsReach] scan_unmatched: truncated"); break
            end
        end
    end
    if shown == 0 then System.LogAlways("[SmithsReach] scan_unmatched: all stash kinds are whitelisted") end
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

function SmithsReach._StartHeartbeat()
    local hbCfg = SmithsReach.Config.Heartbeat
    local names = SmithsReach.Config.UI.CraftingElements

    -- session-local state
    local S = SmithsReach._Session
    S.phase = "AwaitUI"
    S.phaseTicks = 0
    S.seenOpen = false
    S.hideBeats = 0
    S.resultBeats = 0
    -- baseline for non-mats
    S.NonMats_before = _filter_non_mats(_snapshot_raw_map(player, nil))
    S.Crafted = {}
    S.craftedSeen = false

    local function beat()
        if not (SmithsReach._Session and SmithsReach._Session.active) then return end
        local vis, known = _any_visible(names)
        local intervalMs = hbCfg.intervalMs
        local function nextBeat() Script.SetTimer(intervalMs, beat) end
        local function tryClose(reason)
            System.LogAlways("[SmithsReach] END via " .. reason)
            local ok, err = xpcall(SmithsReach._ForgeOnClose, debug.traceback)
            if not ok then System.LogAlways("[SmithsReach] _ForgeOnClose ERROR:\n" .. tostring(err)) end
        end

        S.phaseTicks = S.phaseTicks + 1

        if S.phase == "AwaitUI" then
            if vis == true then
                S.seenOpen = true
                S.phase = "Active"; S.phaseTicks = 0
            else
                -- UI never appeared quickly -> grace-cancel
                if known and (S.phaseTicks * intervalMs >= hbCfg.openGraceMs) then
                    tryClose("UI timeout (never became visible)")
                    return
                end
            end
            nextBeat(); return
        end

        if S.phase == "Active" then
            -- detect crafted outputs while UI visible
            if vis == true then
                local nonNow = _filter_non_mats(_snapshot_raw_map(player, nil))
                local deltas = _positive_deltas(nonNow, S.NonMats_before)
                local saw    = false
                for cid, n in pairs(deltas) do
                    if n > 0 then
                        S.Crafted[cid] = (S.Crafted[cid] or 0) + n
                        saw = true
                    end
                end
                if saw then S.craftedSeen = true end
            end

            if vis == false and S.seenOpen then
                S.hideBeats = S.hideBeats + 1
                if S.hideBeats >= hbCfg.hideDebounceBeats then
                    S.phase = "AwaitResult"; S.phaseTicks = 0
                end
            else
                S.hideBeats = 0
            end
            nextBeat(); return
        end

        if S.phase == "AwaitResult" then
            -- one last small stabilization window for result popup / inventory settle
            S.resultBeats = S.resultBeats + 1
            if S.resultBeats >= hbCfg.resultDebounceBeats then
                tryClose(S.craftedSeen and "UI hidden (crafted)" or "UI hidden (no craft)")
                return
            end
            nextBeat(); return
        end

        -- default
        nextBeat()
    end

    -- small mount delay
    Script.SetTimer(150, beat)
end
