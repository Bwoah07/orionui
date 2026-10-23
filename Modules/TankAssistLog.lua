local _, ns = ...
local RC = ns.RC
local TankAssist = RC:GetModule("TankAssist", true)

if not TankAssist then
    return
end

-- Pull log for tank assist: what each boss ability was taken as and which warning showed, so
-- a wrong call can be traced after the raid. Kept in RaidControlDB.global.tankAssistLog (last
-- MAX_LINES lines). `/rc tanklog` prints the latest pull, `/rc tanklog clear` empties it.
-- Nothing is printed during the fight.

local MAX_LINES = 600

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

local function Text(value)
    if value == nil then
        return "-"
    end
    if IsSecret(value) then
        return "secret"
    end
    local ok, text = pcall(tostring, value)
    return ok and text or "?"
end

local function Lines()
    local global = RC.db and RC.db.global
    if not global then
        return nil
    end
    global.tankAssistLog = global.tankAssistLog or {}
    return global.tankAssistLog
end

local function Add(line)
    local lines = Lines()
    if not lines then
        return
    end
    local pullTime = TankAssist.logPullStart and (GetTime() - TankAssist.logPullStart) or 0
    lines[#lines + 1] = string.format("%6.1f %s", pullTime, line)
    while #lines > MAX_LINES do
        table.remove(lines, 1)
    end
end

local function Wrap(name, before)
    local original = TankAssist[name]
    if type(original) ~= "function" then
        return
    end
    TankAssist[name] = function(self, ...)
        pcall(before, self, ...)
        return original(self, ...)
    end
end

Wrap("ENCOUNTER_START", function(self, _, encounterID, encounterName, difficultyID)
    self.logPullStart = GetTime()
    local lines = Lines()
    if lines then
        local okTank, isTank = pcall(self.IsPlayerTank, self)
        lines[#lines + 1] = string.format("=== %s %s (%s) difficulty %s, %s", date("%Y-%m-%d %H:%M"),
            Text(encounterName), Text(encounterID), Text(difficultyID),
            okTank and (isTank == true and "tank" or "not tank") or "?")
    end
end)

Wrap("ENCOUNTER_END", function(self, _, _, _, _, _, success)
    Add("end " .. (success == 1 and "kill" or "wipe/other"))
    self.logPullStart = nil
end)

Wrap("HandleTimelineFinished", function(self, tracked)
    if not self.logPullStart or type(tracked) ~= "table" then
        return
    end
    Add(string.format("ability %s | kind %s | action %s | by %s | stage %s", Text(tracked.label),
        Text(tracked.kind), Text(tracked.action), Text(tracked.identifiedBy),
        Text(self.timelineState and (self.timelineState.midnightStage or self.timelineState.ulatekStage))))
end)

Wrap("ShowPersonalMechanicStart", function(self, tracked, owner)
    if not self.logPullStart or type(tracked) ~= "table" then
        return
    end
    Add(string.format("start %s | boss held by %s", Text(tracked.label), Text(owner)))
end)

Wrap("Alert", function(self, title, detail, spokenText, key)
    if not self.logPullStart then
        return
    end
    Add(string.format("alert \"%s\" (%s) key %s", Text(title), Text(spokenText), Text(key)))
end)

Wrap("ShowActiveMechanicCountdown", function(self, tracked, duration, title)
    if not self.logPullStart then
        return
    end
    Add(string.format("countdown \"%s\" %ss", Text(title), Text(duration)))
end)

function TankAssist:PrintLog(clear)
    local lines = Lines()
    if not lines then
        return
    end
    if clear then
        wipe(lines)
        RC:Print("Tank Assist log cleared.")
        return
    end
    local start = 1
    for i = #lines, 1, -1 do
        if lines[i]:sub(1, 3) == "===" then
            start = i
            break
        end
    end
    if #lines == 0 then
        RC:Print("Tank Assist log is empty: it fills during boss pulls.")
        return
    end
    for i = start, #lines do
        print(lines[i])
    end
end
