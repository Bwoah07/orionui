-- TankOwnership (CLAUDE.md §7.6): "should THIS player react to THIS mechanic?"
--
-- Verified in game 2026-09-29 (dungeon + M+): UnitThreatSituation("player", "bossN") is
-- readable during encounters; UnitDetailedThreatSituation on bossN is always secret, so we
-- only use the former. Status 2 or 3 = tanking. nil = not on that unit's threat table.
-- Unreadable (secret) or no information at all -> fail open (warn rather than miss).
local _, ns = ...

local Ownership = { lastTankedAt = {} }
ns.TankOwnership = Ownership

local MAX_BOSSES = 5

-- true / false / nil (unknown) for one boss unit, updating the grace memory.
local function TankingUnit(unit)
    local exists = UnitExists(unit)
    if ns.Secret.Is(exists) or not exists then return nil end
    local status = UnitThreatSituation("player", unit)
    if ns.Secret.Is(status) then return nil end
    if status == nil then return false end
    local tanking = status >= 2
    if tanking then Ownership.lastTankedAt[unit] = GetTime() end
    return tanking
end

local function WithinGrace(unit)
    local t = Ownership.lastTankedAt[unit]
    return t ~= nil and GetTime() - t <= ns.TANKED_GRACE
end

-- ownerUnit: N for bossN (curated), or nil for "any boss".
-- -> ok (boolean, always decided), reason (for the log)
function Ownership:ShouldReact(ownerUnit)
    if ownerUnit then
        local unit = "boss" .. ownerUnit
        local t = TankingUnit(unit)
        if t == true then return true, "tanking " .. unit end
        if WithinGrace(unit) then return true, "tanked " .. unit .. " recently" end
        if t == nil then return true, "no threat info for " .. unit .. " (fail open)" end
        return false, "not tanking " .. unit
    end
    local anyKnown = false
    for i = 1, MAX_BOSSES do
        local unit = "boss" .. i
        local t = TankingUnit(unit)
        if t == true then return true, "tanking " .. unit end
        if WithinGrace(unit) then return true, "tanked " .. unit .. " recently" end
        if t == false then anyKnown = true end
    end
    if not anyKnown then return true, "no threat info (fail open)" end
    return false, "not tanking any boss"
end

function Ownership:Reset() wipe(self.lastTankedAt) end

ns.Events:On("OUI_ENCOUNTER_END", Ownership, function() Ownership:Reset() end)
Ownership.name = "TankOwnership"
