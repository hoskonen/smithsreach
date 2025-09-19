SmithsReach = SmithsReach or {}
SmithsReach.Util = SmithsReach.Util or {}

function SmithsReach.Util.Player()
    return System.GetEntityByName("Henry") or System.GetEntityByName("dude")
end

function SmithsReach.Util.Pos(ent)
    if ent and ent.GetWorldPos then
        local v = { x = 0, y = 0, z = 0 }; ent:GetWorldPos(v); return v
    end
    return nil
end

function SmithsReach.Util.DistPos(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function SmithsReach.Util.DistEnt(aEnt, bEnt)
    local ap, bp = SmithsReach.Util.Pos(aEnt), SmithsReach.Util.Pos(bEnt)
    return SmithsReach.Util.DistPos(ap, bp)
end

-- New: experiment for perk detection
function SmithsReach.Util.DebugListPerks(stat)
    local pl = SmithsReach.Util.Player()
    if not pl or not pl.soul or not pl.soul.GetDerivedStat then
        System.LogAlways("[SmithsReach] DebugListPerks: no player or soul")
        return
    end

    local perks = {}
    local val = pl.soul:GetDerivedStat(stat or "maintenance", nil, perks)
    System.LogAlways(("[SmithsReach] DerivedStat %s = %s"):format(stat or "maintenance", tostring(val)))

    if type(perks) == "table" then
        for i, perk in ipairs(perks) do
            System.LogAlways(("[SmithsReach] perk[%d] = %s"):format(i, tostring(perk)))
        end
    else
        System.LogAlways("[SmithsReach] no perks returned")
    end
end
