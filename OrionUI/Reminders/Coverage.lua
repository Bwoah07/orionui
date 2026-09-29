-- Coverage (CLAUDE.md §7.8): is a defensive already running, so we don't tell the player
-- to press another one on top?
--
-- Player auras are withheld in combat (verified 2026-09-29), and UNIT_SPELLCAST_SUCCEEDED
-- is SecretWhenUnitSpellCastRestricted. What stays readable is the cooldown's isActive
-- flag, so the main signal is: inside SPELL_UPDATE_COOLDOWN, a tracked defensive goes
-- from "not on cooldown" to "on cooldown" -> it was just used -> active for its duration.
-- A readable UNIT_SPELLCAST_SUCCEEDED and (out of combat) the aura itself refine that.
-- Anything unknown counts as "not active": we never suppress on a guess.
local _, ns = ...

local Coverage = { activeUntil = {}, onCooldown = {} }
ns.Coverage = Coverage

local function Catalog() return ns.Data.Defensives[ns.Player.specID] or {} end

local function MarkUsed(def)
    Coverage.activeUntil[def.key] = GetTime() + def.duration
    ns.Log:Debug("Coverage", "%s used, active %.0fs", def.key, def.duration)
end

-- Re-reads each tracked defensive's cooldown and records false -> true transitions.
function Coverage:Scan()
    for _, def in ipairs(Catalog()) do
        local now = ns.Readiness:OnRealCooldown(def.spell)
        if now ~= nil then
            if now and self.onCooldown[def.key] == false then MarkUsed(def) end
            self.onCooldown[def.key] = now
        end
    end
end

-- Active defensive entry with the highest strength, or nil.
function Coverage:Strongest()
    local now, best = GetTime(), nil
    for _, def in ipairs(Catalog()) do
        if (self.activeUntil[def.key] or 0) > now and (not best or def.strength > best.strength) then
            best = def
        end
    end
    return best
end

function Coverage:IsActive(key)
    return (self.activeUntil[key] or 0) > GetTime()
end

-- Is `def` covered by something already running (equal or stronger)?
function Coverage:Covers(def)
    local s = self:Strongest()
    if s and s.strength >= def.strength then return true, s end
    return false
end

function Coverage:Reset()
    wipe(self.activeUntil)
    wipe(self.onCooldown)
    self:Scan()
end

ns.Events:On("SPELL_UPDATE_COOLDOWN", Coverage, function() Coverage:Scan() end)
ns.Events:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, Coverage, function(_, _, _, _, spellID)
    if ns.Secret.Is(spellID) then return end
    for _, def in ipairs(Catalog()) do
        if def.spell == spellID then MarkUsed(def) end
    end
end)
ns.Events:On("OUI_SPEC_CHANGED", Coverage, function() Coverage:Reset() end)
ns.Events:On("PLAYER_ENTERING_WORLD", Coverage, function() Coverage:Reset() end)
Coverage.name = "Coverage"
