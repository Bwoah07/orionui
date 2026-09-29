-- /ouidev bossmod
-- While /ouidev watch is on, logs every BigWigs message, DBM callback, and Blizzard
-- encounter timeline/warning event we care about, with each argument's type and
-- whether it is secret. This shows the real payload shapes the BossModBridge must
-- handle (CLAUDE.md §7.4) and which fields arrive secret in 12.x.
--
-- Message/callback names verified against BigWigs (Core/BossPrototype.lua, Loader.lua)
-- and DBM-Core (DBMCallbackEvent alias) sources cloned 2026-09-29.
local _, ns = ...

local Report = ns.Report
local Describe, DescribeFields = ns.Describe, ns.DescribeFields
local select = select

local MAX_LINES_PER_PULL = 500 -- one pull must not flood the saved log
local linesThisPull = 0

local BIGWIGS_MESSAGES = {
    "BigWigs_OnBossEngage", "BigWigs_OnBossWin", "BigWigs_OnBossWipe", "BigWigs_OnBossDisable",
    "BigWigs_StartBar", "BigWigs_Timer", "BigWigs_TargetTimer", "BigWigs_StopBar", "BigWigs_StopBars",
    "BigWigs_PauseBar", "BigWigs_ResumeBar", "BigWigs_Message", "BigWigs_SetStage",
}
local DBM_CALLBACKS = {
    "DBM_Pull", "DBM_Kill", "DBM_Wipe", "DBM_SetStage",
    "DBM_TimerBegin", "DBM_TimerStop", "DBM_TimerUpdate", "DBM_TimerPause", "DBM_TimerResume",
    "DBM_Announce",
}
-- EncounterTimelineDocumentation.lua / EncounterWarningsDocumentation.lua
local TIMELINE_INFO_FIELDS = { "id", "source", "spellName", "spellID", "iconFileID", "duration", "maxQueueDuration", "icons", "severity", "isApproximate" }
local WARNING_FIELDS = { "text", "casterName", "targetName", "iconFileID", "tooltipSpellID", "isDeadly", "duration", "severity", "shouldPlaySound", "shouldShowWarning" }

local function Args(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, math.min(n, 16) do
        parts[i] = Describe((select(i, ...)))
    end
    if n > 16 then parts[#parts + 1] = "…+" .. (n - 16) end
    return "(" .. n .. ") " .. table.concat(parts, ", ")
end

local function Log(prefix, name, detail)
    if not (ns.db and ns.db.watch) then return end
    linesThisPull = linesThisPull + 1
    if linesThisPull == MAX_LINES_PER_PULL then
        Report:Event("BM cap of %d lines reached for this pull; further boss-mod lines dropped", MAX_LINES_PER_PULL)
    end
    if linesThisPull >= MAX_LINES_PER_PULL then return end
    Report:Event("%s %s %s", prefix, name, detail)
end

---------------------------------------------------------------------------
-- BigWigs: BigWigsLoader.RegisterMessage(owner, message, func); func(message, ...)
---------------------------------------------------------------------------
local bwOwner = {}
local bwRegistered = false
local function RegisterBigWigs()
    if bwRegistered or not BigWigsLoader or not BigWigsLoader.RegisterMessage then return end
    for _, msg in ipairs(BIGWIGS_MESSAGES) do
        BigWigsLoader.RegisterMessage(bwOwner, msg, function(event, ...)
            Log("BW", event, Args(...))
        end)
    end
    bwRegistered = true
end

---------------------------------------------------------------------------
-- DBM: DBM:RegisterCallback(event, func); func(event, ...)
---------------------------------------------------------------------------
local dbmRegistered = false
local function RegisterDBM()
    if dbmRegistered or not DBM or not DBM.RegisterCallback then return end
    for _, cb in ipairs(DBM_CALLBACKS) do
        DBM:RegisterCallback(cb, function(event, ...)
            Log("DBM", event, Args(...))
        end)
    end
    dbmRegistered = true
end

---------------------------------------------------------------------------
-- Blizzard encounter events (12.x built-in timeline and warnings)
---------------------------------------------------------------------------
ns.On("ENCOUNTER_START", function(_, ...)
    linesThisPull = 0
    Log("ENC", "ENCOUNTER_START", Args(...))
end)
ns.On("ENCOUNTER_END", function(_, ...) Log("ENC", "ENCOUNTER_END", Args(...)) end)
ns.On("ENCOUNTER_TIMELINE_EVENT_ADDED", function(_, info)
    Log("TL", "EVENT_ADDED", DescribeFields(info, TIMELINE_INFO_FIELDS))
end)
for _, ev in ipairs({ "ENCOUNTER_TIMELINE_EVENT_REMOVED", "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", "ENCOUNTER_TIMELINE_EVENT_HIGHLIGHT" }) do
    ns.On(ev, function(event, ...) Log("TL", (event:gsub("^ENCOUNTER_TIMELINE_", "")), Args(...)) end)
end
ns.On("ENCOUNTER_WARNING", function(_, info)
    Log("WARN", "ENCOUNTER_WARNING", DescribeFields(info, WARNING_FIELDS))
end)

ns.On("PLAYER_LOGIN", function()
    RegisterBigWigs()
    RegisterDBM()
end)
-- Boss mods can load late (load-on-demand parts): retry whenever one loads.
ns.On("ADDON_LOADED", function(_, name)
    if name == "BigWigs_Core" or name == "BigWigs" then RegisterBigWigs() end
    if name == "DBM-Core" then RegisterDBM() end
end)

function ns.ProbeBossMod(args)
    Report:Begin("BOSSMOD")
    Report:Line("BigWigs listener=%s (BigWigsLoader %s)", tostring(bwRegistered), BigWigsLoader and "present" or "absent")
    Report:Line("DBM listener=%s (DBM %s)", tostring(dbmRegistered), DBM and "present" or "absent")
    Report:Line("Blizzard timeline/warning listeners always on. watch=%s", tostring(ns.db and ns.db.watch))
    Report:Line("Boss-mod lines are timestamped in the log. After a pull: /ouidev log")
    return Report:End(args.show ~= false)
end
