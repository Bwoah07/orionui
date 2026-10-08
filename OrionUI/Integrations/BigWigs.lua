-- BigWigs adapter -> BossModBridge. Payload shapes verified against BigWigs source
-- (Core/BossPrototype.lua, cloned 2026-09-29) and live logs from a dungeon and M+:
--   BigWigs_StartBar(mod, key, text, time, icon, isApprox, maxTime, nil, timelineEventId)
--   BigWigs_Timer(mod, key, time, maxTime, text, counter, icon, isApprox, isBarEnabled)
--   BigWigs_TargetTimer(mod, key, time, maxTime, text, counter, icon, player, isBarEnabled)
--   BigWigs_StopBar(mod, text)            -- text only, no key
--   BigWigs_StopBars(mod)
--   BigWigs_PauseBar(mod, text) / BigWigs_ResumeBar(mod, text)
--   BigWigs_Message(mod, key, text, color, icon, emphasized, displayTime)
--   BigWigs_OnBossWin/Wipe/Disable(mod, ...)
-- Every timer arrives as BOTH StartBar and Timer; we key bars by text (BigWigs' own bar
-- identity, which StopBar uses) and the bridge dedupes. Only boss modules count: plugins
-- (Victory, Statistics, BossBlock) and trash modules have no engage ID.
local _, ns = ...

local SOURCE = "BigWigs"
local Plain = ns.Secret.Plain
local owner = {} -- BigWigsLoader.RegisterMessage needs a table to own the callbacks
local registered = false

local function Bridge() return ns.BossModBridge end

-- Encounter ID if `mod` is a boss module, else nil.
local function BossEncounter(mod)
    if type(mod) ~= "table" or not ns.Secret.CanRead(mod) then return nil end
    local id = Plain(mod.engageId)
    if type(id) == "number" then return id end
end

local function Key(key)
    key = Plain(key)
    local t = type(key)
    if t == "number" or t == "string" then return key end
end

-- Blizzard's timeline hides spell IDs and names in encounters, but BigWigs links
-- each bar to its timeline event (9th StartBar argument) with a plain key and
-- text. Tank assist reads this to know WHICH mechanic a timeline event is,
-- instead of guessing from the timer length. Event ids restart every pull, so
-- the table is wiped on engage and at the end of a fight.
ns.BossModTimeline = ns.BossModTimeline or {}

local function RememberTimelineEvent(mod, key, text, timelineEventID)
    if not BossEncounter(mod) then return end
    timelineEventID = Plain(timelineEventID)
    if type(timelineEventID) ~= "number" then return end
    key = Key(key)
    text = Plain(text)
    local name = type(text) == "string" and text:gsub("%s*%(%d+%)%s*$", ""):lower() or nil
    ns.BossModTimeline[timelineEventID] = {
        spellID = type(key) == "number" and key or nil,
        name = name,
    }
end

local function OnTimer(mod, key, text, duration, icon, approx)
    local encounterID = BossEncounter(mod)
    if not encounterID then return end
    text = Plain(text)
    duration = Plain(duration)
    if type(text) ~= "string" or type(duration) ~= "number" then return end
    Bridge():Timer({
        source = SOURCE, id = text, key = Key(key), text = text,
        icon = Plain(icon), duration = duration, approx = Plain(approx) == true, encounterID = encounterID,
    })
end

local handlers = {
    BigWigs_StartBar = function(_, mod, key, text, time, icon, isApprox, _, _, timelineEventID)
        RememberTimelineEvent(mod, key, text, timelineEventID)
        OnTimer(mod, key, text, time, icon, isApprox)
    end,
    BigWigs_OnBossEngage = function(_, mod)
        if BossEncounter(mod) then wipe(ns.BossModTimeline) end
    end,
    BigWigs_Timer = function(_, mod, key, time, _, text, _, icon, isApprox)
        OnTimer(mod, key, text, time, icon, isApprox)
    end,
    BigWigs_TargetTimer = function(_, mod, key, time, _, text, _, icon)
        OnTimer(mod, key, text, time, icon, false)
    end,
    BigWigs_StopBar = function(_, mod, text)
        text = Plain(text)
        if BossEncounter(mod) and type(text) == "string" then Bridge():Cancel(SOURCE, text) end
    end,
    BigWigs_StopBars = function(_, mod)
        if BossEncounter(mod) then Bridge():CancelAll(SOURCE) end
    end,
    BigWigs_PauseBar = function(_, mod, text)
        text = Plain(text)
        if BossEncounter(mod) and type(text) == "string" then Bridge():Pause(SOURCE, text) end
    end,
    BigWigs_ResumeBar = function(_, mod, text)
        text = Plain(text)
        if BossEncounter(mod) and type(text) == "string" then Bridge():Resume(SOURCE, text) end
    end,
    BigWigs_Message = function(_, mod, key, text, _, icon)
        local encounterID = BossEncounter(mod)
        text = Plain(text)
        if not encounterID or type(text) ~= "string" then return end
        Bridge():Message({ source = SOURCE, key = Key(key), text = text, icon = Plain(icon), encounterID = encounterID })
    end,
}
local function EndOfFight(_, mod)
    if BossEncounter(mod) then
        Bridge():CancelAll(SOURCE)
        wipe(ns.BossModTimeline)
    end
end
handlers.BigWigs_OnBossWin = EndOfFight
handlers.BigWigs_OnBossWipe = EndOfFight
handlers.BigWigs_OnBossDisable = EndOfFight

ns.BossModBridge:RegisterAdapter(SOURCE, {
    IsLoaded = function() return BigWigsLoader ~= nil and BigWigsLoader.RegisterMessage ~= nil end,
    Register = function()
        if registered then return end
        for message, fn in pairs(handlers) do
            BigWigsLoader.RegisterMessage(owner, message, function(...)
                ns.SafeCall("BigWigs:" .. message, fn, ...)
            end)
        end
        registered = true
        ns.Log:Info("BigWigs", "listening to BigWigs")
    end,
})
