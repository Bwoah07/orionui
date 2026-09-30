local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
local KeySync = RC:NewModule("KeySync", "AceEvent-3.0", "AceComm-3.0")
local COMM_PREFIX = "RCKEYS"
local ROSTER_REQUEST_COOLDOWN = 5
local KEY_EXPIRY_SECONDS = 1800

local function CancelTimer(timer)
    if timer and timer.Cancel then
        timer:Cancel()
    end
end

local function Now()
    return GetTime and GetTime() or 0
end

local function GetPlayerName()
    local name, realm
    if UnitFullName then
        name, realm = UnitFullName("player")
    end
    if name and realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name or UnitName("player")
end

local function GetCommChannel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    elseif IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

function KeySync:OnInitialize()
    self.db = RC.db.profile
    self.partyKeys = {}
    self.keyUpdatedAt = {}

    -- WoW Forever has no Mythic+ keystones, so there is nothing to sync.
    if RC.SupportsMythicPlus and not RC:SupportsMythicPlus() then
        self:SetEnabledState(false)
    end
end

function KeySync:OnEnable()
    self:RegisterComm(COMM_PREFIX)
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnBagUpdateDelayed")
    self:QueueRosterSync(0.75)
end

function KeySync:OnDisable()
    CancelTimer(self.rosterTimer)
    CancelTimer(self.responseTimer)
    self.rosterTimer = nil
    self.responseTimer = nil
end

function KeySync:OnBagUpdateDelayed()
    self:ScanOwnKeystone(true)
end

function KeySync:SetOwnKeystone(keyData, shouldBroadcast)
    local playerName = GetPlayerName()
    if not playerName then
        return
    end

    local previous = self.partyKeys[playerName]
    self.partyKeys[playerName] = keyData
    if keyData then
        self.keyUpdatedAt[playerName] = Now()
    else
        self.keyUpdatedAt[playerName] = nil
    end

    if shouldBroadcast and previous ~= keyData then
        self:BroadcastOwnKeystone()
    end
end

-- Scan only the player's bags/native keystone cache. Other players sync over addon comms.
function KeySync:ScanOwnKeystone(shouldBroadcast)
    if not self.db.enableKeySync or not IsInGroup() then
        return
    end

    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneLevel then
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        local level = C_MythicPlus.GetOwnedKeystoneLevel()
        if mapID and level and level > 0 then
            local mapName = C_ChallengeMode and C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)
            if mapName then
                self:SetOwnKeystone(("%s +%s"):format(mapName, level), shouldBroadcast)
                return
            end
        end
    end

    if C_Container then
        local keystoneIDs = { [180653] = true, [158923] = true }
        for bag = 0, 4 do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                local itemID = C_Container.GetContainerItemID(bag, slot)
                if itemID and keystoneIDs[itemID] then
                    local itemLink = C_Container.GetContainerItemLink(bag, slot)
                    local mapID, level
                    if itemLink then
                        mapID, level = itemLink:match("keystone:%d+:(%d+):(%d+)")
                    end
                    local mapName = mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo
                        and C_ChallengeMode.GetMapUIInfo(tonumber(mapID))
                    if mapName and level then
                        self:SetOwnKeystone(("%s +%s"):format(mapName, level), shouldBroadcast)
                        return
                    end
                end
            end
        end
    end

    self:SetOwnKeystone(nil, shouldBroadcast)
end

function KeySync:BroadcastOwnKeystone()
    if not self.db.enableKeySync or not IsInGroup() then
        return
    end
    local channel = GetCommChannel()
    local playerName = GetPlayerName()
    if not channel or not playerName then
        return
    end
    local keyData = self.partyKeys[playerName]
    self:SendCommMessage(COMM_PREFIX, keyData and ("KEY:" .. keyData) or "NONE", channel)
end

function KeySync:RequestKeys(skipScan)
    if not self.db.enableKeySync or not IsInGroup() then
        return
    end
    if not skipScan then
        self:ScanOwnKeystone(false)
    end
    local channel = GetCommChannel()
    if channel then
        self:BroadcastOwnKeystone()
        self:SendCommMessage(COMM_PREFIX, "REQ", channel)
        self.lastRosterRequest = Now()
    end
end

function KeySync:OnCommReceived(prefix, message, _, sender)
    if prefix ~= COMM_PREFIX or not message or not self.db.enableKeySync or not sender then
        return
    end
    if message == "REQ" then
        if self.responseTimer then
            return
        end
        local function Respond()
            self.responseTimer = nil
            self:BroadcastOwnKeystone()
        end
        local delay = 0.2 + math.random() * 0.8
        if C_Timer and C_Timer.NewTimer then
            self.responseTimer = C_Timer.NewTimer(delay, Respond)
        elseif C_Timer and C_Timer.After then
            C_Timer.After(delay, Respond)
        else
            Respond()
        end
        return
    end
    if message == "NONE" then
        self.partyKeys[sender] = nil
        self.keyUpdatedAt[sender] = nil
        return
    end
    local keyData = message:match("^KEY:(.+)$")
    if keyData and #keyData <= 160 then
        self.partyKeys[sender] = keyData
        self.keyUpdatedAt[sender] = Now()
    end
end

function KeySync:PrunePartyKeys()
    local now = Now()
    local currentNames = {}
    local memberCount = GetNumGroupMembers and GetNumGroupMembers() or 0

    local function AddUnit(unit)
        local name, realm
        if UnitFullName then
            name, realm = UnitFullName(unit)
        end
        name = name or (UnitName and UnitName(unit))
        if name then
            local fullName = realm and realm ~= "" and (name .. "-" .. realm) or name
            currentNames[fullName:lower()] = true
            currentNames[name:lower()] = true
        end
    end

    AddUnit("player")
    if IsInRaid and IsInRaid() then
        for index = 1, memberCount do
            AddUnit("raid" .. index)
        end
    else
        for index = 1, math.max(0, memberCount - 1) do
            AddUnit("party" .. index)
        end
    end

    for name in pairs(self.partyKeys) do
        local shortName = (name:match("^([^%-]+)") or name):lower()
        local updatedAt = self.keyUpdatedAt[name] or 0
        local leftGroup = not currentNames[name:lower()] and not currentNames[shortName]
        local expired = updatedAt > 0 and now - updatedAt > KEY_EXPIRY_SECONDS
        if leftGroup or expired then
            self.partyKeys[name] = nil
            self.keyUpdatedAt[name] = nil
        end
    end
end

function KeySync:QueueRosterSync(delay)
    CancelTimer(self.rosterTimer)
    self.rosterTimer = nil

    local function Sync()
        self.rosterTimer = nil
        self:SyncGroupKeys()
    end

    if C_Timer and C_Timer.NewTimer then
        self.rosterTimer = C_Timer.NewTimer(delay or 0.75, Sync)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.75, Sync)
    else
        Sync()
    end
end

function KeySync:SyncGroupKeys()
    if not self.db.enableKeySync then
        return
    end
    if not IsInGroup() then
        wipe(self.partyKeys)
        wipe(self.keyUpdatedAt)
        self.lastRosterRequest = nil
        return
    end

    self:PrunePartyKeys()
    local now = Now()
    if not self.lastRosterRequest or now - self.lastRosterRequest >= ROSTER_REQUEST_COOLDOWN then
        self:RequestKeys()
    end
end

function KeySync:GROUP_ROSTER_UPDATE()
    self:QueueRosterSync(0.75)
end

function KeySync:AnnounceKeys()
    if not self.db.enableKeySync then
        RC:Print(L["KeySync is disabled in Settings."])
        return
    end

    self:RequestKeys()
    self:PrunePartyKeys()

    local names = {}
    for name in pairs(self.partyKeys) do
        table.insert(names, name)
    end
    table.sort(names)

    if #names == 0 then
        RC:Print(L["No group Keystones found."])
        return
    end

    local entries = {}
    for _, name in ipairs(names) do
        table.insert(entries, ("[%s]: %s"):format(name, self.partyKeys[name]))
    end
    RC:Printf(L["|cFF00FFFF[RaidControl Keystones]:|r %s"], table.concat(entries, " | "))
end
