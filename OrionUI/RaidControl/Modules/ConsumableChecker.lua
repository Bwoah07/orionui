local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
local ConsumableChecker = RC:NewModule("ConsumableChecker", "AceEvent-3.0")

function ConsumableChecker:OnInitialize()
    self.db = RC.db.profile
end

function ConsumableChecker:OnEnable()
    -- Scanner is triggered manually typically, so no passive events are strictly needed unless we want Auto-Scans.
end

local function CheckPlayerAuras(unit)
    local data = RC.ScanUnitBuffStatus and RC:ScanUnitBuffStatus(unit) or {}
    return data.food and true or false, data.flask and true or false, data.accessible ~= false
end

-- Chat lines are capped at 255 characters; long raid lists are split so the
-- whole report actually reaches chat instead of failing silently.
local MAX_CHAT_LENGTH = 255

local function SendNameList(label, names, chatType)
    local line = label
    local separator = ""
    for _, name in ipairs(names) do
        local piece = separator .. name
        if #line + #piece > MAX_CHAT_LENGTH then
            RC:SendChat(line, chatType)
            line = label .. name
        else
            line = line .. piece
        end
        separator = ", "
    end
    RC:SendChat(line, chatType)
end

local function FullUnitName(unit)
    if GetUnitName then
        return GetUnitName(unit, true)
    end
    return UnitName(unit)
end

function ConsumableChecker:ScanRaid()
    if not self.db.enableConsumableChecker then
        RC:Print(L["Consumable Checker is disabled in Settings."])
        return
    end

    if not IsInGroup() then
        RC:Print(L["You are not in a group."])
        return
    end

    local prefix = IsInRaid() and "raid" or "party"
    local numMembers = GetNumGroupMembers()
    local chatType = RC:GetGroupChannel() or (IsInRaid() and "RAID" or "PARTY")
    local playerName = FullUnitName("player")

    local missingFood = {}
    local missingFlask = {}
    local unavailable = {}

    local function record(unit, name)
        local food, flask, accessible = CheckPlayerAuras(unit)
        if not accessible then
            table.insert(unavailable, name)
            return
        end
        if not food then table.insert(missingFood, name) end
        if not flask then table.insert(missingFlask, name) end

        if self.db.whisperSlackers and name ~= playerName then
            if not food and not flask then
                RC:SendChat(L["RaidControl: You are missing Food and a Flask!"], "WHISPER", nil, name)
            elseif not food then
                RC:SendChat(L["RaidControl: You are missing Food!"], "WHISPER", nil, name)
            elseif not flask then
                RC:SendChat(L["RaidControl: You are missing a Flask!"], "WHISPER", nil, name)
            end
        end
    end

    -- Include player in party scan
    if not IsInRaid() then
        record("player", playerName)
    end

    for i = 1, numMembers do
        local unit = prefix .. i
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            local name = FullUnitName(unit)
            if name and name ~= "" then
                record(unit, name)
            end
        end
    end

    -- Formatting output cleanly
    if self.db.reportToChat then
        if #missingFood > 0 then
            SendNameList(L["Missing Food: "], missingFood, chatType)
        end
        if #missingFlask > 0 then
            SendNameList(L["Missing Flask: "], missingFlask, chatType)
        end
        if #unavailable > 0 then
            SendNameList(L["Aura data unavailable: "], unavailable, chatType)
        elseif #missingFood == 0 and #missingFlask == 0 then
            RC:SendChat(L["Everyone is fully buffed with Food & Flasks!"], chatType)
        end
    else
        RC:Print(L["--- Consumable Check ---"])

        if #missingFood > 0 then
            RC:Printf(L["|cffff3333Missing Food:|r %s"], table.concat(missingFood, ", "))
        elseif #unavailable > 0 then
            RC:Print(L["|cffaaaaaaFood data incomplete.|r"])
        else
            RC:Print(L["|cff33ff33Everyone has Food!|r"])
        end

        if #missingFlask > 0 then
            RC:Printf(L["|cffff3333Missing Flask:|r %s"], table.concat(missingFlask, ", "))
        elseif #unavailable > 0 then
            RC:Print(L["|cffaaaaaaFlask data incomplete.|r"])
        else
            RC:Print(L["|cff33ff33Everyone has Flasks!|r"])
        end

        if #unavailable > 0 then
            RC:Printf(L["|cffaaaaaaAura data unavailable:|r %s"], table.concat(unavailable, ", "))
        end

        RC:Printf("------------------------")
    end
end
