-- Minimal object pool for repeated frames (bars, icons). Frames are never destroyed
-- in WoW, so reuse instead of creating new ones per reminder.
local _, ns = ...

local Pool = {}
Pool.__index = Pool
ns.Pool = Pool

-- create() -> new object; reset(obj) clears it on release (default: Hide + ClearAllPoints).
function Pool:New(create, reset)
    return setmetatable({ create = create, reset = reset, free = {}, active = {} }, Pool)
end

function Pool:Acquire()
    local obj = table.remove(self.free) or self.create()
    self.active[obj] = true
    return obj
end

local function DefaultReset(obj)
    if obj.Hide then obj:Hide() end
    if obj.ClearAllPoints then obj:ClearAllPoints() end
end

function Pool:Release(obj)
    if not self.active[obj] then return end
    self.active[obj] = nil;
    (self.reset or DefaultReset)(obj)
    self.free[#self.free + 1] = obj
end

function Pool:ReleaseAll()
    for obj in pairs(self.active) do self:Release(obj) end
end

function Pool:ActiveCount()
    return ns.Util.Count(self.active)
end
