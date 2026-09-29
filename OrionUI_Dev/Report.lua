-- Report buffer: every probe writes plain-text lines here. The latest report is shown
-- in the copy window; everything is also appended to OrionUIDevDB.log (capped) so
-- results survive /reload and can be read from the WTF SavedVariables file.
local _, ns = ...

local MAX_LOG_LINES = 6000
local format, date = string.format, date

local Report = {}
ns.Report = Report

local current -- lines of the report being built

local function Append(line)
    if current then current[#current + 1] = line end
    local log = ns.db and ns.db.log
    if log then
        log[#log + 1] = line
        local excess = #log - MAX_LOG_LINES
        if excess > 0 then
            for _ = 1, excess do table.remove(log, 1) end
        end
    end
end

-- State summary stamped on every report so results can be read without guessing
-- where the player was when they ran the command.
function ns.ContextLine()
    local version, build = GetBuildInfo()
    local name, instanceType, difficultyID, _, _, _, _, instanceMapID = GetInstanceInfo()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    local specID, specName = nil, "none"
    if specIndex then
        specID, specName = C_SpecializationInfo.GetSpecializationInfo(specIndex)
    end
    local cm = C_ChallengeMode.IsChallengeModeActive()
    return format("build=%s(%s) spec=%s(%s) combat=%s encounter=%s mplus=%s instance=%s type=%s diff=%s map=%s restrict=[%s]",
        version, build, tostring(specName), tostring(specID),
        tostring(InCombatLockdown()), tostring(IsEncounterInProgress()), tostring(cm),
        tostring(name), tostring(instanceType), tostring(difficultyID), tostring(instanceMapID),
        ns.RestrictionSummary and ns.RestrictionSummary() or "?")
end

function Report:Begin(title)
    current = {}
    Append("")
    Append(format("===== %s  %s =====", title, date("%Y-%m-%d %H:%M:%S")))
    Append(ns.ContextLine())
end

function Report:Line(fmt, ...)
    if select("#", ...) > 0 then fmt = format(fmt, ...) end
    Append(fmt)
end

-- Lines logged outside a report (event streams). Timestamped with GetTime().
function Report:Event(fmt, ...)
    if select("#", ...) > 0 then fmt = format(fmt, ...) end
    local saved = current
    current = nil
    Append(format("[%.1f] %s", GetTime(), fmt))
    current = saved
end

-- Ends the report. show=true opens the copy window with just this report.
function Report:End(show)
    local lines = current or {}
    current = nil
    if show then ns.CopyWindow:Show(table.concat(lines, "\n")) end
    return lines
end

function Report:ShowLog(lastN)
    local log = ns.db and ns.db.log or {}
    local first = math.max(1, #log - (lastN or #log) + 1)
    local out = {}
    for i = first, #log do out[#out + 1] = log[i] end
    ns.CopyWindow:Show(table.concat(out, "\n"))
end

function Report:ClearLog()
    if ns.db then ns.db.log = {} end
end
