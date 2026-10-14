local _, ns = ...
local RC = ns.RC
local L = RC.L
---@class Durability : AceModule, AceComm-3.0
local Durability = RC:NewModule("Durability", "AceComm-3.0")

-- Durability sync for the ready check panel. Each RaidControl user sends their lowest item
-- durability when a ready check starts (and when asked), and the panel shows it per player.
-- Same prefix and messages as RaidControl's raid lead tools ("DREQ" asks, "DURA:<percent>"
-- answers), so every RaidControl version in the group shares one pool.
local COMM_PREFIX = "RCLEAD"

local function IsSecret(value)
    if not issecretvalue then
        return false
    end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

local function NormalizeName(name)
    if name == nil or IsSecret(name) or name == "" then
        return nil
    end
    name = tostring(name)
    if Ambiguate then
        local short = Ambiguate(name, "short")
        if short and short ~= "" then
            name = short
        end
    end
    return name:match("^([^%-]+)") or name
end

local function Now()
    return time and time() or 0
end

local function GetCommChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
        and not (LE_PARTY_CATEGORY_HOME and IsInGroup(LE_PARTY_CATEGORY_HOME)) then
        return "INSTANCE_CHAT"
    elseif IsInRaid and IsInRaid() then
        return "RAID"
    elseif IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function GetLowestDurabilityPercent()
    local lowest
    for slot = 1, 19 do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            local percent = math.floor((current / maximum) * 100 + 0.5)
            if not lowest or percent < lowest then
                lowest = percent
            end
        end
    end
    return lowest
end

function Durability:OnInitialize()
    self.db = RC.db.profile
    self.durability = {}
end

function Durability:OnEnable()
    self:RegisterComm(COMM_PREFIX)
end

function Durability:IsSyncEnabled()
    return self.db.enableDurabilityComm ~= false
end

local function RefreshPanel()
    local readyTracker = RC:GetModule("ReadyTracker", true)
    if readyTracker and readyTracker.UpdateFrame then
        readyTracker:UpdateFrame()
    end
end

function Durability:SendDurability()
    if not self:IsSyncEnabled() then
        return
    end
    local percent = GetLowestDurabilityPercent()
    if not percent then
        return
    end
    local playerName = NormalizeName(UnitName("player"))
    if playerName then
        self.durability[playerName] = { percent = percent, updated = Now() }
    end
    local channel = GetCommChannel()
    if channel then
        self:SendCommMessage(COMM_PREFIX, "DURA:" .. tostring(percent), channel)
    end
end

-- Asks the group for durability. manual = typed or clicked by the player: also prints who is low.
function Durability:RequestDurability(manual)
    if not self:IsSyncEnabled() then
        return
    end
    self:SendDurability()
    local channel = GetCommChannel()
    if channel then
        self:SendCommMessage(COMM_PREFIX, "DREQ", channel)
    end
    if manual then
        C_Timer.After(2, function()
            self:ReportDurability(true)
        end)
    end
end

-- The ready check panel calls this after a ready check; it only refreshes the panel there.
-- Chat output is only for a manual check.
function Durability:ReportDurability(toChat)
    RefreshPanel()
    if not toChat then
        return
    end
    local threshold = tonumber(self.db.durabilityWarnThreshold) or 30
    local low = {}
    for name, info in pairs(self.durability) do
        if info.percent and info.percent <= threshold then
            table.insert(low, string.format("%s %d%%", name, info.percent))
        end
    end
    table.sort(low)
    if #low == 0 then
        RC:Print(string.format(L["Durability: no RaidControl users below %d%%."], threshold))
    else
        RC:Print(string.format(L["Low durability: %s"], table.concat(low, ", ")))
    end
end

function Durability:GetDurabilityForName(name)
    local key = NormalizeName(name)
    local info = key and self.durability[key]
    if info then
        return info.percent, info.updated
    end
    return nil
end

function Durability:OnCommReceived(prefix, message, _, sender)
    if prefix ~= COMM_PREFIX or type(message) ~= "string" or not self:IsSyncEnabled() then
        return
    end
    if message == "DREQ" then
        C_Timer.After(0.2 + math.random() * 0.8, function()
            self:SendDurability()
        end)
        return
    end
    local percent = message:match("^DURA:(%d+)$")
    local name = percent and NormalizeName(sender)
    if name then
        self.durability[name] = { percent = math.min(100, tonumber(percent) or 0), updated = Now() }
        RefreshPanel()
    end
end
