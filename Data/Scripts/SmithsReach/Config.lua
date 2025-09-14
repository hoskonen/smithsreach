-- [SmithsReach/Config.lua]
SmithsReach = SmithsReach or {}

SmithsReach.Config = {
    -- QoL behavior
    Behavior = {
        showTransferFX = true, -- Game.ShowItemsTransfer(...) when cloning
        verboseLogs    = true,
        fxAtClose      = true, -- if true, use the queue; if false, show inline (maybe with delay)
        fxOpenDelayMs  = 250,
    },
    Close = {
        distM      = 2.0, -- meters before we consider you “away”
        graceTicks = 2,   -- consecutive ticks away before closing
        tickMs     = 200, -- polling rate
    },
    -- Safety caps (keeps weight/ spam down)
    PullCaps = {
        max_kinds = 12, -- how many distinct mats to pull at most
        max_each  = 10, -- per-class cap
        max_total = 60, -- total items cap
    },
    Notif = {
        onOpen   = false, -- clone toasts (off by default to avoid spam)
        onClose  = true,  -- cleanup toasts
        maxItems = 8,     -- cap per event
    },
    Heartbeat = {
        intervalMs = 250,
        openGraceMs = 2500,      -- give the panel time to appear if user backed out fast
        hideDebounceBeats = 2,   -- require # consecutive “not visible” polls
        resultDebounceBeats = 2, -- beat(s) after result to stabilize counts
    },
    UI = {
        CraftingElements = {
            "ApseCraftingContent", "ApseCraftingList", "ApseModalDialog"
        }
    }
}
