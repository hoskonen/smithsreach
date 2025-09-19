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

function SmithsReach.Util.DistPos2D(a, b)
    if not a or not b then return math.huge end
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function SmithsReach.Util.DistEnt2D(aEnt, bEnt)
    return SmithsReach.Util.DistPos2D(SmithsReach.Util.Pos(aEnt), SmithsReach.Util.Pos(bEnt))
end
