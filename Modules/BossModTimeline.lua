-- Links Blizzard's boss timeline events to BigWigs' spell keys for tank assist.
--
-- Blizzard's encounter timeline hides spell IDs and names during fights, but BigWigs links
-- each bar to its timeline event (9th BigWigs_StartBar argument) with a plain key and text:
--   BigWigs_StartBar(mod, key, text, time, icon, isApprox, maxTime, nil, timelineEventId)
-- Tank assist reads ns.BossModTimeline[timelineEventID] = { spellID, name } to know which
-- mechanic a timeline event is instead of guessing from the timer length. Event ids restart
-- every pull, so the table is wiped on engage and at the end of a fight. Without BigWigs the
-- table stays empty and tank assist falls back to timer lengths.
local _, ns = ...

ns.BossModTimeline = ns.BossModTimeline or {}

local issecretvalue = issecretvalue
local owner = {} -- BigWigsLoader.RegisterMessage needs a table to own the callbacks
local registered = false

local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

-- Only boss modules count: plugins and trash modules have no engage ID.
local function IsBossModule(mod)
    if type(mod) ~= "table" then return false end
    local ok, id = pcall(function() return mod.engageId end)
    return ok and type(Plain(id)) == "number"
end

local function Remember(mod, key, text, timelineEventID)
    if not IsBossModule(mod) then return end
    timelineEventID = Plain(timelineEventID)
    if type(timelineEventID) ~= "number" then return end
    key = Plain(key)
    text = Plain(text)
    ns.BossModTimeline[timelineEventID] = {
        spellID = type(key) == "number" and key or nil,
        name = type(text) == "string" and text:gsub("%s*%(%d+%)%s*$", ""):lower() or nil,
    }
end

local function Clear(_, mod)
    if IsBossModule(mod) then wipe(ns.BossModTimeline) end
end

local handlers = {
    BigWigs_StartBar = function(_, mod, key, text, _, _, _, _, _, timelineEventID)
        Remember(mod, key, text, timelineEventID)
    end,
    BigWigs_OnBossEngage = Clear,
    BigWigs_OnBossWin = Clear,
    BigWigs_OnBossWipe = Clear,
    BigWigs_OnBossDisable = Clear,
}

local function TryRegister()
    if registered then return true end
    local loader = _G.BigWigsLoader
    if not (loader and loader.RegisterMessage) then return false end
    for message, fn in pairs(handlers) do
        loader.RegisterMessage(owner, message, function(...)
            local ok, err = pcall(fn, ...)
            if not ok then geterrorhandler()(err) end
        end)
    end
    registered = true
    return true
end

-- BigWigs can load before or after us; try now, then whenever an addon loads.
if not TryRegister() then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        if TryRegister() then self:UnregisterAllEvents() end
    end)
end
