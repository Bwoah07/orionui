local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
---@class AutoAssist : AceModule, AceEvent-3.0
local AutoAssist = RC:NewModule("AutoAssist", "AceEvent-3.0")

local DEFAULT_CHECK_DELAY = 0.25
local NEW_MEMBER_RECHECK_DELAY = 0.75
local GUILD_INFO_RETRY_LIMIT = 4
local ACTION_RETRY_COOLDOWN = 2
local ACTION_RETRY_LIMIT = 3
local ACTION_ATTEMPT_RESET = 30

local function CancelTimer(timer)
    if timer and timer.Cancel then
        timer:Cancel()
    end
end

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function SafeString(value)
    if type(value) ~= "string" or value == "" or IsSecret(value) then
        return nil
    end
    return value
end

local function SafeNumber(value)
    if type(value) ~= "number" or IsSecret(value) then
        return nil
    end
    return value
end

local function NameKey(value)
    local name = SafeString(value)
    if not name then
        return nil
    end
    name = strtrim and strtrim(name) or name:match("^%s*(.-)%s*$")
    return name ~= "" and name:lower() or nil
end

local function ShortNameKey(value)
    local key = NameKey(value)
    return key and key:match("^([^-]+)") or nil
end

local function ClearTable(target)
    for key in pairs(target or {}) do
        target[key] = nil
    end
end

local function GetNow()
    if GetTime then
        local now = GetTime()
        if type(now) == "number" and not IsSecret(now) then
            return now
        end
    end
    return 0
end

AutoAssist.GuildRanks = {}

function AutoAssist:OnInitialize()
    self.db = RC.db.profile
    self.knownRoster = {}
    self.guildInfoRetries = {}
    self.pendingAssistantPromotions = {}
    self.assistantAttemptCounts = {}
    self.playerGuildRetries = 0
    self:UpdateGuildRanks()
end

function AutoAssist:OnEnable()
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "QueueRosterCheck")
    self:RegisterEvent("PARTY_LEADER_CHANGED", "OnRaidAuthorityChanged")
    self:RegisterEvent("PLAYER_ROLES_ASSIGNED", "QueueRosterCheck")
    self:RegisterEvent("ROLE_CHANGED_INFORM", "QueueRosterCheck")
    self:RegisterEvent("UNIT_CONNECTION", "QueueRosterCheck")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "QueueRosterCheck")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
    self:RegisterEvent("GUILD_RANKS_UPDATE", "UpdateGuildRanks")
    self:RegisterEvent("GUILD_ROSTER_UPDATE", "OnGuildRosterUpdate")
    self:RegisterEvent("PLAYER_GUILD_UPDATE", "UpdateGuildRanks")
    self:QueueRosterCheck(0.5)
end

function AutoAssist:OnDisable()
    CancelTimer(self.rosterCheckTimer)
    self.rosterCheckTimer = nil
    self.pendingAfterCombat = nil
end

function AutoAssist:OnRaidAuthorityChanged()
    ClearTable(self.pendingAssistantPromotions)
    ClearTable(self.assistantAttemptCounts)
    self:QueueRosterCheck(0.1)
end

function AutoAssist:OnGuildRosterUpdate()
    ClearTable(self.guildInfoRetries)
    self.playerGuildRetries = 0
    self:QueueRosterCheck(0.25)
end

function AutoAssist:OnPlayerRegenEnabled()
    if self.pendingAfterCombat then
        self.pendingAfterCombat = nil
        self:QueueRosterCheck(0.1)
    end
end

function AutoAssist:UpdateGuildRanks()
    ClearTable(self.GuildRanks)
    ClearTable(self.guildInfoRetries)
    self.playerGuildRetries = 0

    if not IsInGuild or not IsInGuild() then
        self:QueueRosterCheck(0.5)
        return
    end

    local numRanks = GuildControlGetNumRanks and GuildControlGetNumRanks()
    numRanks = SafeNumber(numRanks)
    if not numRanks or numRanks <= 0 then
        numRanks = 10
    end

    for index = 1, math.min(numRanks, 20) do
        local rankName = GuildControlGetRankName and SafeString(GuildControlGetRankName(index))
        if rankName then
            self.GuildRanks[#self.GuildRanks + 1] = {
                index = index,
                name = rankName,
            }
        end
    end

    table.sort(self.GuildRanks, function(left, right)
        return left.index < right.index
    end)

    if self.db.autoAssistRankName then
        local found = false
        for _, rank in ipairs(self.GuildRanks) do
            if rank.name == self.db.autoAssistRankName then
                found = true
                self.db.autoAssistMinRank = rank.index
                break
            end
        end
        if not found then
            self.db.autoAssistRankName = nil
        end
    end
    self:QueueRosterCheck(0.5)
end

function AutoAssist:GetMaxRankIndex()
    if self.db.autoAssistRankName then
        for _, rank in ipairs(self.GuildRanks) do
            if rank.name == self.db.autoAssistRankName then
                return rank.index
            end
        end
    end
    local rank = SafeNumber(self.db.autoAssistMinRank) or 1
    return math.max(0, math.min(math.floor(rank), 20))
end

function AutoAssist:GetGuildRankList()
    local list = {}
    for _, rank in ipairs(self.GuildRanks) do
        list[rank.index] = rank.name
    end
    if #self.GuildRanks == 0 then
        for index = 1, 10 do
            list[index] = string.format(L["Rank %d"], index)
        end
    end
    return list
end

function AutoAssist:IsQualifiedRank(guildRankIndex)
    guildRankIndex = SafeNumber(guildRankIndex)
    local minRank = self:GetMaxRankIndex()
    if not guildRankIndex or not minRank or minRank <= 0 then
        return false
    end
    return (guildRankIndex + 1) <= minRank
end

function AutoAssist:BuildAssistNameList()
    local list = {}
    local raw = SafeString(self.db.autoAssistList)
    if not raw then
        return list
    end
    for name in raw:gmatch("[^,;\n]+") do
        local fullKey = NameKey(name)
        local shortKey = ShortNameKey(name)
        if fullKey then list[fullKey] = true end
        if shortKey then list[shortKey] = true end
    end
    return list
end

function AutoAssist:IsNameListed(name, list)
    local fullKey = NameKey(name)
    local shortKey = ShortNameKey(name)
    return (fullKey and list[fullKey]) or (shortKey and list[shortKey]) or false
end

function AutoAssist:QueueRosterCheck(delay)
    CancelTimer(self.rosterCheckTimer)
    self.rosterCheckTimer = nil

    local function RunCheck()
        self.rosterCheckTimer = nil
        self:CheckRoster()
    end

    if not C_Timer then
        RunCheck()
        return
    end

    delay = tonumber(delay) or DEFAULT_CHECK_DELAY
    if C_Timer.NewTimer then
        self.rosterCheckTimer = C_Timer.NewTimer(delay, RunCheck)
    elseif C_Timer.After then
        C_Timer.After(delay, RunCheck)
    else
        RunCheck()
    end
end

function AutoAssist:GetRosterIdentity(unit, name)
    local guid = UnitGUID and SafeString(UnitGUID(unit))
    return guid or NameKey(name) or unit
end

function AutoAssist:RequestFollowUp(delay)
    delay = tonumber(delay)
    if not delay then return end
    if not self.nextFollowUpDelay or delay < self.nextFollowUpDelay then
        self.nextFollowUpDelay = delay
    end
end

function AutoAssist:CanAttemptAction(cache, counts, identity)
    local now = GetNow()
    local lastAttempt = cache[identity]
    local attemptCount = counts[identity] or 0
    if lastAttempt and attemptCount >= ACTION_RETRY_LIMIT then
        if (now - lastAttempt) < ACTION_ATTEMPT_RESET then
            return false
        end
        counts[identity] = 0
        attemptCount = 0
    end
    if lastAttempt then
        local remaining = ACTION_RETRY_COOLDOWN - (now - lastAttempt)
        if remaining > 0 then
            self:RequestFollowUp(remaining + 0.05)
            return false
        end
    end
    return attemptCount < ACTION_RETRY_LIMIT
end

function AutoAssist:PromoteAssistant(name, identity)
    if not self:CanAttemptAction(self.pendingAssistantPromotions, self.assistantAttemptCounts, identity) then
        return false
    end
    self.pendingAssistantPromotions[identity] = GetNow()
    self.assistantAttemptCounts[identity] = (self.assistantAttemptCounts[identity] or 0) + 1
    local promoted = RC:PromoteGroupAssistant(name)
    if promoted then
        if self.assistantAttemptCounts[identity] < ACTION_RETRY_LIMIT then
            self:RequestFollowUp(ACTION_RETRY_COOLDOWN + 0.05)
        end
        return true
    end
    if self.assistantAttemptCounts[identity] < ACTION_RETRY_LIMIT then
        self:RequestFollowUp(ACTION_RETRY_COOLDOWN + 0.05)
    end
    return false
end

function AutoAssist:PruneRosterState(currentRoster)
    local caches = {
        self.knownRoster,
        self.guildInfoRetries,
        self.pendingAssistantPromotions,
        self.assistantAttemptCounts,
    }
    for _, cache in ipairs(caches) do
        for identity in pairs(cache) do
            if not currentRoster[identity] then
                cache[identity] = nil
            end
        end
    end
end

function AutoAssist:CheckRoster()
    self.db = RC.db.profile
    if not IsInRaid or not IsInRaid() then
        self:PruneRosterState({})
        self.pendingAfterCombat = nil
        self.playerGuildRetries = 0
        self.nextFollowUpDelay = nil
        return
    end
    local assistEnabled = self.db.enableAutoAssist == true
    if not assistEnabled then
        ClearTable(self.pendingAssistantPromotions)
        ClearTable(self.assistantAttemptCounts)
        ClearTable(self.guildInfoRetries)
        self.playerGuildRetries = 0
    end
    if not assistEnabled then
        self.pendingAfterCombat = nil
        self.nextFollowUpDelay = nil
        return
    end

    local isLeader = UnitIsGroupLeader and UnitIsGroupLeader("player") == true
    local isAssistant = UnitIsGroupAssistant and UnitIsGroupAssistant("player") == true
    if not isLeader and not isAssistant then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingAfterCombat = true
        return
    end
    self.pendingAfterCombat = nil
    self.nextFollowUpDelay = nil

    local groupCount = GetNumGroupMembers and SafeNumber(GetNumGroupMembers()) or 0
    groupCount = math.max(0, math.min(math.floor(groupCount or 0), 40))
    local currentRoster = {}
    local assistNames = self:BuildAssistNameList()
    local playerGuild = assistEnabled and self.db.autoAssistOfficers and GetGuildInfo and SafeString(GetGuildInfo("player")) or nil
    if assistEnabled and self.db.autoAssistOfficers and GetGuildInfo then
        if playerGuild then
            self.playerGuildRetries = 0
        elseif self.playerGuildRetries < GUILD_INFO_RETRY_LIMIT then
            self.playerGuildRetries = self.playerGuildRetries + 1
            self:RequestFollowUp(NEW_MEMBER_RECHECK_DELAY)
        end
    end

    for index = 1, groupCount do
        local name, raidRank = GetRaidRosterInfo(index)
        name = SafeString(name)
        if name then
            local unit = "raid" .. index
            local identity = self:GetRosterIdentity(unit, name)
            currentRoster[identity] = true
            local isNew = not self.knownRoster[identity]
            self.knownRoster[identity] = true
            if isNew then
                self.guildInfoRetries[identity] = 0
                self.pendingAssistantPromotions[identity] = nil
                self.assistantAttemptCounts[identity] = nil
                self:RequestFollowUp(NEW_MEMBER_RECHECK_DELAY)
            end

            local connected = true
            if UnitIsConnected then
                local connectionState = UnitIsConnected(unit)
                connected = not IsSecret(connectionState) and connectionState ~= false
            end
            raidRank = SafeNumber(raidRank)
            if raidRank and raidRank > 0 then
                self.pendingAssistantPromotions[identity] = nil
                self.assistantAttemptCounts[identity] = nil
            end

            if connected and assistEnabled and isLeader and raidRank == 0 then
                local shouldAssist = self:IsNameListed(name, assistNames)
                if not shouldAssist and self.db.autoAssistOfficers and playerGuild and GetGuildInfo then
                    local guildName, _, guildRankIndex = GetGuildInfo(unit)
                    guildName = SafeString(guildName)
                    guildRankIndex = SafeNumber(guildRankIndex)
                    if guildName and guildName == playerGuild and guildRankIndex then
                        self.guildInfoRetries[identity] = nil
                        if self:IsQualifiedRank(guildRankIndex) then
                            shouldAssist = true
                        end
                    elseif not guildName or (guildName == playerGuild and not guildRankIndex) then
                        local retries = self.guildInfoRetries[identity] or 0
                        if retries < GUILD_INFO_RETRY_LIMIT then
                            self.guildInfoRetries[identity] = retries + 1
                            self:RequestFollowUp(NEW_MEMBER_RECHECK_DELAY)
                        end
                    end
                end

                if shouldAssist then
                    self:PromoteAssistant(name, identity)
                end
            end

        end
    end

    self:PruneRosterState(currentRoster)
    if self.nextFollowUpDelay then
        local delay = self.nextFollowUpDelay
        self.nextFollowUpDelay = nil
        self:QueueRosterCheck(delay)
    end
end
