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
    }
}
