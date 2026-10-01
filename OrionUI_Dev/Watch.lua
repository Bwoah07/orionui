-- Watch mode (on by default): takes probe snapshots automatically at the moments that
-- are awkward to type commands in: shortly after entering combat, after an encounter
-- starts, and after a Mythic+ key starts. Results go to the saved log (/ouidev log),
-- silently: no chat line per snapshot (Stig, 2026-10-01).
local _, ns = ...

local Report = ns.Report

local COMBAT_DELAY, ENCOUNTER_DELAY, MPLUS_DELAY = 2, 3, 5
local COMBAT_COOLDOWN = 60 -- trash pulls in M+ would otherwise snapshot constantly
local lastCombatSnapshot = -math.huge

local function Snapshot(reason)
    if not (ns.db and ns.db.watch) then return end
    Report:Event("SNAPSHOT %s", reason)
    local quiet = { show = false }
    ns.ProbeRestrictions(quiet)
    ns.ProbeSecrets(quiet)
    ns.ProbeAuras(quiet)
    ns.ProbeThreat(quiet)
end

ns.On("PLAYER_REGEN_DISABLED", function()
    if not (ns.db and ns.db.watch) then return end
    local now = GetTime()
    if now - lastCombatSnapshot < COMBAT_COOLDOWN then return end
    lastCombatSnapshot = now
    C_Timer.After(COMBAT_DELAY, function() Snapshot("combat+" .. COMBAT_DELAY .. "s") end)
end)

ns.On("ENCOUNTER_START", function(_, encounterID, encounterName)
    if not (ns.db and ns.db.watch) then return end
    local label = "encounter " .. ns.Describe(encounterID) .. " " .. ns.Describe(encounterName)
    C_Timer.After(ENCOUNTER_DELAY, function() Snapshot(label .. " +" .. ENCOUNTER_DELAY .. "s") end)
end)

ns.On("CHALLENGE_MODE_START", function()
    if not (ns.db and ns.db.watch) then return end
    C_Timer.After(MPLUS_DELAY, function() Snapshot("mplus start +" .. MPLUS_DELAY .. "s") end)
end)

function ns.SetWatch(on)
    ns.db.watch = on
    ns.Chat("watch " .. (on and "|cff55ff55on|r" or "|cffff5555off|r"))
end
