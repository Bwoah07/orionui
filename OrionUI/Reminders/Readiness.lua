-- Cooldown readiness (CLAUDE.md §4.2). Strategy chosen from the in-game results of
-- 2026-09-29: C_Spell.GetSpellCooldown's isActive / isEnabled stay readable in combat,
-- encounters and Mythic+ (all 168 probe samples), while start/duration are secret.
-- So "ready or not" is known; "how long until ready" is not.
--
-- Tri-state: true (ready), false (on cooldown), nil (unknown). Unknown never becomes
-- false: the resolver treats it as "maybe ready" and ranks it after known-ready ones.
local _, ns = ...

local Readiness = {}
ns.Readiness = Readiness

local Bool = ns.Secret.Bool

function Readiness:IsReady(spellID)
    local info = C_Spell.GetSpellCooldown(spellID)
    if not ns.Secret.CanRead(info) then return nil end
    if Bool(info.isEnabled) == false then return false end -- held (e.g. waiting for a buff to drop)
    local active = Bool(info.isActive)
    if active == nil then return nil end
    if not active then return true end
    -- The global cooldown makes on-GCD spells look active; isOnGCD is only reliable inside
    -- SPELL_UPDATE_COOLDOWN, so a nil here means "can't tell" rather than "on cooldown".
    local onGCD = Bool(info.isOnGCD)
    if onGCD == true then return true end
    return false
end

-- Readable "is it on cooldown right now" for Coverage's cast detection:
-- true only when it is active and not merely on the GCD.
function Readiness:OnRealCooldown(spellID)
    local info = C_Spell.GetSpellCooldown(spellID)
    if not ns.Secret.CanRead(info) then return nil end
    local active = Bool(info.isActive)
    if active == nil then return nil end
    return active and Bool(info.isOnGCD) ~= true
end
