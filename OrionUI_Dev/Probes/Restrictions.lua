-- /ouidev restrictions  and  /ouidev cleu
-- Dumps C_RestrictedActions state per restriction type, C_Secrets global predicates,
-- and whether the combat log is restricted. We never register
-- COMBAT_LOG_EVENT_UNFILTERED here: registering it while restricted can itself cause
-- ADDON_ACTION_FORBIDDEN (CLAUDE.md §4.1). We only ask IsCombatLogRestricted().
local _, ns = ...

local Report = ns.Report
local Describe, Try = ns.Describe, ns.Try

-- Short labels for the compact context line; full names come from Enum at runtime.
local SHORT = { Combat = "cmb", Encounter = "enc", ChallengeMode = "mplus", PvPMatch = "pvp", Map = "map", Chat = "chat" }
local STATE = { [0] = "off", [1] = "activating", [2] = "ON" }

local function SortedTypes()
    local list = {}
    for name, value in pairs(Enum.AddOnRestrictionType or {}) do
        list[#list + 1] = { name = name, value = value }
    end
    table.sort(list, function(a, b) return a.value < b.value end)
    return list
end

local function StateOf(value)
    local ok, state = Try(C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState, value)
    if not ok then return "ERR" end
    if ns.IsSecret(state) then return "<secret>" end
    return STATE[state] or tostring(state)
end

function ns.RestrictionSummary()
    local parts = {}
    for _, t in ipairs(SortedTypes()) do
        parts[#parts + 1] = (SHORT[t.name] or t.name) .. "=" .. StateOf(t.value)
    end
    return table.concat(parts, " ")
end

local function CombatLogState()
    local ok, r = Try(C_CombatLog and C_CombatLog.IsCombatLogRestricted)
    return ok and Describe(r) or ("ERR " .. tostring(r))
end

function ns.ProbeRestrictions(args)
    Report:Begin("RESTRICTIONS")
    for _, t in ipairs(SortedTypes()) do
        local ok, active = Try(C_RestrictedActions.IsAddOnRestrictionActive, t.value)
        Report:Line("%-14s (%d) state=%s active=%s", t.name, t.value, StateOf(t.value), ok and Describe(active) or "ERR")
    end
    local S = C_Secrets or {}
    for _, fn in ipairs({ "HasSecretRestrictions", "ShouldCooldownsBeSecret", "ShouldAurasBeSecret" }) do
        local ok, v = Try(S[fn])
        Report:Line("C_Secrets.%s = %s", fn, ok and Describe(v) or ("ERR " .. tostring(v)))
    end
    Report:Line("C_CombatLog.IsCombatLogRestricted = %s", CombatLogState())
    Report:Line("InCombatLockdown=%s UnitAffectingCombat(player)=%s IsEncounterInProgress=%s",
        Describe(InCombatLockdown()), Describe(UnitAffectingCombat("player")), Describe(IsEncounterInProgress()))
    return Report:End(args.show ~= false)
end

function ns.ProbeCLEU(args)
    Report:Begin("CLEU")
    Report:Line("C_CombatLog.IsCombatLogRestricted = %s", CombatLogState())
    Report:Line("(changes are also logged automatically while /ouidev watch is on)")
    return Report:End(args.show ~= false)
end

-- Event stream: every restriction transition, plus the combat-log state at that moment.
ns.On("ADDON_RESTRICTION_STATE_CHANGED", function(_, rtype, state)
    if not (ns.db and ns.db.watch) then return end
    if ns.IsSecret(rtype) or ns.IsSecret(state) then
        Report:Event("RESTRICTION payload secret: type=%s state=%s", Describe(rtype), Describe(state))
        return
    end
    local name = tostring(rtype)
    for _, t in ipairs(SortedTypes()) do
        if t.value == rtype then name = t.name end
    end
    Report:Event("RESTRICTION %s -> %s  cleuRestricted=%s", name, STATE[state] or tostring(state), CombatLogState())
end)
