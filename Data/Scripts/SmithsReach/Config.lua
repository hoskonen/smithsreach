-- [SmithsReach/Config.lua]
SmithsReach = SmithsReach or {}

SmithsReach.Config = {
    -- QoL behavior
    Behavior = {
        cloneOnOpen     = true, -- if false, we only snapshot/log
        returnLeftovers = false, -- remove cloned-but-unused from player on close
        showTransferFX  = true, -- Game.ShowItemsTransfer(...) when cloning
        verboseLogs     = true,
    },

    -- Safety caps (keeps weight/ spam down)
    PullCaps = {
        max_kinds = 12, -- how many distinct mats to pull at most
        max_each  = 10, -- per-class cap
        max_total = 60, -- total items cap
    },
}
