-- [SmithsReach/Config.lua]
SmithsReach = SmithsReach or {}

SmithsReach.Config = {
    -- QoL behavior
    Behavior = {
        showTransferFX           = true, -- Game.ShowItemsTransfer(...) when cloning
        verboseLogs              = true,
        fxAtClose                = true, -- if true, use the queue; if false, show inline (maybe with delay)
        fxOpenDelayMs            = 250,
        -- Immersion / Bed and stash detection, Maintenance Level Req
        forgeProximityEnabled    = true,
        forgeProximityRadiusM    = 12,   -- base radius
        forgeNeedOwnedBed        = true, -- allow bed to satisfy gate
        forgeGateMode            = "both", -- "either" | "both" | "stash"
        forgeGateOpenPadM        = 1.0,  -- extra meters for opening
        forgeGateClosePadM       = 3.0,  -- extra meters for staying open
        forgeBedSearch           = "stash", -- "stash" | "player"
        forgeBedStrict           = true, -- require Sleep&Save bed (WillSleepingOnThisBedSave)
        requireMaintenanceLevel  = true, -- enable level gate
        requiredMaintenanceLevel = 15    -- threshold
    },
    Close = {
        enableProximity = true, -- keep OFF for this branch
        distM           = 6.0,  -- meters before we consider you “away”
        graceTicks      = 2,    -- consecutive ticks away before closing
        tickMs          = 200,  -- polling rate
    },
    -- Safety caps (keeps weight/ spam down)
    PullCaps = {
        max_kinds = 70,  -- how many distinct mats to pull at most
        max_each  = 4,   -- per-class cap
        max_total = 200, -- total items cap
    },
    Notif = {
        onOpen   = false, -- clone toasts (off by default to avoid spam)
        onClose  = true,  -- cleanup toasts
        maxItems = 8,     -- cap per event
    },
    Heartbeat = {
        intervalMs          = 250,
        openGraceMs         = 2500,           -- give the panel time to appear if user backed out fast
        hideDebounceBeats   = 2,              -- require # consecutive “not visible” polls
        resultDebounceBeats = 2,              -- beat(s) after result to stabilize counts
        armMs               = 2000,           -- ignore “left” checks right after OnUsed
        settleBeats         = 3,              -- no new output for N beats = settled
        cancelFarMs         = 4000,           -- if far & no craft for this long → cancel
        cancelMaxMs         = 12 * 60 * 1000, -- absolute ceiling ~12 min
        endOnFirstCrafted   = false,          -- default: wait & settle
        completeIdleMs      = 4000            -- or 4s since last delta
    },
    -- these items are spawned to player when blacksmithing minigame begins
    CraftedIgnore = {
        classIds = {
            ["f22b7bb9-fa73-4aa1-92e6-3943e2be7e69"] = true, -- tongs
            ["0502824d-a654-4471-9978-c1624860dde1"] = true, -- blacksmith's hammer
        }
    },
    namePatterns = {
        "blacksmith", "tongs", "bellows", "smith", -- very conservative; adjust as needed
    }
}
