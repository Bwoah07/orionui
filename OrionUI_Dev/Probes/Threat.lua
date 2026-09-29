-- /ouidev threat
-- Can TankOwnership (CLAUDE.md §7.6) read "am I tanking bossN?" in each state?
-- Checks boss1..boss5 plus "target" so it can also be run on a training dummy.
local _, ns = ...

local Report = ns.Report
local Describe, Try = ns.Describe, ns.Try

local UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5", "target" }

local function Call(fn, ...)
    local ok, a, b, c, d, e = Try(fn, ...)
    if not ok then return "ERR(" .. tostring(a) .. ")" end
    return a, b, c, d, e
end

-- Readable/secret only: never print a GUID's content.
local function Readability(v)
    if ns.IsSecret(v) then return "<secret>" end
    if v == nil then return "nil" end
    return "readable"
end

local function ProbeUnit(unit)
    local exists = Call(UnitExists, unit)
    if ns.IsSecret(exists) then
        Report:Line("%-6s exists=<secret>", unit)
        return
    end
    if exists ~= true then
        Report:Line("%-6s exists=%s", unit, Describe(exists))
        return
    end
    local status = Call(UnitThreatSituation, "player", unit)
    local isTanking, dStatus, scaled, raw, rawThreat = Call(UnitDetailedThreatSituation, "player", unit)
    Report:Line("%-6s exists=true canAttack=%s guid=%s", unit,
        Describe(Call(UnitCanAttack, "player", unit)), Readability(Call(UnitGUID, unit)))
    Report:Line("       UnitThreatSituation=%s", Describe(status))
    Report:Line("       Detailed: isTanking=%s status=%s scaled%%=%s raw%%=%s rawThreat=%s",
        Describe(isTanking), Describe(dStatus), Describe(scaled), Describe(raw), Describe(rawThreat))
    if unit ~= "target" then
        Report:Line("       CanCompareUnitTokens(target,%s)=%s UnitIsUnit=%s", unit,
            Describe(Call(C_Secrets and C_Secrets.CanCompareUnitTokens, "target", unit)),
            Describe(Call(UnitIsUnit, "target", unit)))
    end
end

function ns.ProbeThreat(args)
    Report:Begin("THREAT")
    Report:Line("UnitThreatSituation(player) overall=%s", Describe(Call(UnitThreatSituation, "player")))
    for _, u in ipairs(UNITS) do ProbeUnit(u) end
    return Report:End(args.show ~= false)
end
