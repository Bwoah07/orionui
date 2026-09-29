-- DefensiveResolver (CLAUDE.md §7.7): mechanic + player spec -> which defensive to press.
--
-- Preset chain, most specific wins:
--   ability binding (spec x encounter x mechanic) -> user spec preset -> Data default.
-- Candidate filter, in order: known -> damage type fits -> ready -> not covered.
-- Known-ready candidates win over maybe-ready (unknown readiness) ones.
local _, ns = ...

local Resolver = {}
ns.DefensiveResolver = Resolver

-- Ordered defensive keys for this spec/binding.
function Resolver:Chain(specID, binding)
    if binding and binding.defensives and #binding.defensives > 0 then return binding.defensives, "ability" end
    local db = ns.Reminders.db
    local user = db and db.presets[specID]
    if user and #user > 0 then return user, "spec" end
    return ns.Data.DefensivePresets[specID] or {}, "default"
end

-- Damage type of a mechanic from curated tags ("physical" / "magicDamage"); nil = unknown.
local function DamageType(mechanic)
    local t = mechanic and mechanic.tags or {}
    if t.physical then return "physical" end
    if t.magicDamage then return "magic" end
end

local function Fits(def, dmg)
    return dmg == nil or def.dmg == "all" or def.dmg == dmg
end

-- -> result = { pick = def|nil, maybe = bool, covered = def|nil, reasons = { ... } }
function Resolver:Resolve(mechanic, binding)
    local specID = ns.Player.specID
    local result = { reasons = {} }
    local function Why(fmt, ...) result.reasons[#result.reasons + 1] = fmt:format(...) end
    local keys, source = self:Chain(specID, binding)
    local dmg = DamageType(mechanic)
    local skipCovered = ns.Reminders.db.skipCovered
    local maybe
    for _, key in ipairs(keys) do
        local def = ns.Data.DefensiveByKey(specID, key)
        if not def then
            Why("%s: unknown for this spec", key)
        elseif not C_SpellBook.IsSpellKnown(def.spell) then
            Why("%s: not known", key)
        elseif not Fits(def, dmg) then
            Why("%s: wrong damage type", key)
        else
            local ready = ns.Readiness:IsReady(def.spell)
            local covered, by = ns.Coverage:Covers(def)
            if ready == false then
                Why("%s: on cooldown", key)
            elseif skipCovered and covered then
                Why("%s: covered by %s", key, by.key)
                result.covered = result.covered or by
            elseif ready == true then
                result.pick = def
                Why("picked %s (%s preset)", key, source)
                return result
            else
                maybe = maybe or def
                Why("%s: readiness unknown", key)
            end
        end
    end
    if maybe then
        result.pick, result.maybe = maybe, true
        Why("picked %s (readiness unknown)", maybe.key)
    end
    return result
end
