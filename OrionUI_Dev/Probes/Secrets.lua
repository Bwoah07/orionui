-- /ouidev secrets [all | spellID ...]
-- Answers CLAUDE.md §4.2: for each defensive, which cooldown/charge fields are secret
-- right now, and what C_Secrets says about the spell. Run it out of combat, on a dummy
-- in combat, during a dungeon boss, and in M+.
local _, ns = ...

local Report = ns.Report
local Describe, DescribeFields, SecretSummary, Try = ns.Describe, ns.DescribeFields, ns.SecretSummary, ns.Try

-- Field lists from SpellSharedDocumentation.lua (12.1.0 build 69933).
local COOLDOWN_FIELDS = { "startTime", "duration", "isEnabled", "isActive", "modRate", "activeCategory", "timeUntilEndOfStartRecovery", "isOnGCD" }
local CHARGE_FIELDS = { "currentCharges", "maxCharges", "cooldownStartTime", "cooldownDuration", "chargeModRate", "isActive" }

-- Enum value -> name, only for readable values.
local function EnumName(enumTable, v)
    if ns.IsSecret(v) or v == nil or not enumTable then return Describe(v) end
    for name, value in pairs(enumTable) do
        if value == v then return name end
    end
    return tostring(v)
end

local function Call(fn, ...)
    local ok, a = Try(fn, ...)
    if not ok then return "ERR(" .. tostring(a) .. ")" end
    return a
end

local function GlobalSecretState()
    local S = C_Secrets
    if not S then return "C_Secrets missing" end
    return string.format("HasSecretRestrictions=%s ShouldCooldownsBeSecret=%s ShouldAurasBeSecret=%s",
        Describe(Call(S.HasSecretRestrictions)), Describe(Call(S.ShouldCooldownsBeSecret)), Describe(Call(S.ShouldAurasBeSecret)))
end

-- "Can Lua decide readiness for this spell right now?" isActive and isOnGCD are
-- documented NeverSecret; this checks whether that holds for the returned table.
local function Verdict(cd)
    if type(cd) == "nil" then return "no cooldown info (unknown spell?)" end
    if type(cd) ~= "table" then return Describe(cd) end
    if not ns.CanReadTable(cd) then return "table itself inaccessible" end
    if ns.IsSecret(cd.isActive) then return "isActive SECRET: cannot branch" end
    local timing = (ns.IsSecret(cd.startTime) or ns.IsSecret(cd.duration)) and "timing secret" or "timing readable"
    return "isActive readable: can branch (" .. timing .. ")"
end

local function ProbeSpell(entry)
    local id = entry.id
    local S = C_Secrets or {}
    Report:Line("-- %d %s [%s]", id, entry.label or "?", entry.status or "custom")
    Report:Line("   name=%s known=%s passive=%s",
        Describe(Call(C_Spell.GetSpellName, id)),
        Describe(Call(C_SpellBook.IsSpellKnown, id)),
        Describe(Call(C_Spell.IsSpellPassive, id)))
    Report:Line("   cdSecrecy=%s shouldCdBeSecret=%s auraSecrecy=%s castSecrecy=%s",
        EnumName(Enum.SecrecyLevel, Call(S.GetSpellCooldownSecrecy, id)),
        Describe(Call(S.ShouldSpellCooldownBeSecret, id)),
        EnumName(Enum.SecrecyLevel, Call(S.GetSpellAuraSecrecy, id)),
        EnumName(Enum.SecrecyLevel, Call(S.GetSpellCastSecrecy, id)))

    local cd = Call(C_Spell.GetSpellCooldown, id)
    Report:Line("   cooldown: %s", DescribeFields(cd, COOLDOWN_FIELDS))
    Report:Line("   cooldown secrecy: %s", SecretSummary(cd, COOLDOWN_FIELDS))

    local ch = Call(C_Spell.GetSpellCharges, id)
    if type(ch) ~= "nil" then
        Report:Line("   charges: %s", DescribeFields(ch, CHARGE_FIELDS))
        Report:Line("   charges secrecy: %s", SecretSummary(ch, CHARGE_FIELDS))
    else
        Report:Line("   charges: nil (not a charge spell)")
    end

    -- Duration objects are for display widgets; we only record that one came back.
    local dur = Call(C_Spell.GetSpellCooldownDuration, id)
    Report:Line("   durationObject=%s", Describe(dur))
    Report:Line("   VERDICT: %s", Verdict(cd))
end

function ns.ProbeSecrets(args)
    local list = {}
    if args[1] == "all" then
        for _, specList in pairs(ns.SpellLists) do
            for _, e in ipairs(specList) do list[#list + 1] = e end
        end
    elseif tonumber(args[1]) then
        for _, a in ipairs(args) do
            local id = tonumber(a)
            if id then list[#list + 1] = { id = id, label = "custom" } end
        end
    else
        list = ns.SpellLists[ns.CurrentSpecID() or 0] or {}
        if #list == 0 then
            ns.Chat("No list for this spec; using all tank lists. Or: /ouidev secrets <spellID> ...")
            return ns.ProbeSecrets({ "all" })
        end
    end

    Report:Begin("SECRETS")
    Report:Line(GlobalSecretState())
    Report:Line("note: isOnGCD is only trustworthy inside SPELL_UPDATE_COOLDOWN (per API docs)")
    for _, e in ipairs(list) do ProbeSpell(e) end
    return Report:End(args.show ~= false)
end
