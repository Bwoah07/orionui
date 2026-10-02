local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
---@class RaidSplit : AceModule, AceEvent-3.0, AceConsole-3.0
---@field db table
---@field frame Frame
---@field rosterData table
---@field groupFrames table
---@field draggingFrame Frame
---@field draggingSlot table
---@field originalData table
---@field inCombat boolean
---@field numMelee number
---@field numRanged number
---@field isScanning boolean
local RaidSplit = RC:NewModule("RaidSplit", "AceEvent-3.0", "AceConsole-3.0")

-- Constants
local FRAME_WIDTH  = (RC.WorkspaceSize and RC.WorkspaceSize.width) or 1058
local FRAME_HEIGHT = (RC.WorkspaceSize and RC.WorkspaceSize.height) or 640
local SIDE_PANEL_W = 180
local BUFF_PANEL_W = 216
local GUILD_PANEL_W = 252
local GROUP_WIDTH  = 156
local SLOT_HEIGHT  = 40
local SLOT_HEIGHT_MIN = 30
local SLOT_HEIGHT_MAX = 52 -- OrionUI: was 44, which left empty space at the bottom of every group
local GROUP_MIN_WIDTH = 110
local GROUP_HEADER_HEIGHT = 30
local GROUP_SLOT_INSET = 6
local GROUP_SLOT_GAP = 4
local DOCK_BUFF_PANEL_WIDTH = 200
local RAIDSPLIT_SCALE_MIN = 0.50
local RAIDSPLIT_SCALE_MAX = 2.00
local RAIDSPLIT_SCALE_STEP = 0.01
local SPLIT_TEAM_COLORS = {
    { r = 1.00, g = 0.72, b = 0.18 },
    { r = 0.18, g = 0.62, b = 1.00 },
    { r = 0.30, g = 0.90, b = 0.44 },
    { r = 1.00, g = 0.36, b = 0.22 },
}
local C_GuildInfo_GuildRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or GuildRoster

local function IsInCombat()
    return (InCombatLockdown and InCombatLockdown())
        or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

local function ClampRaidSplitScale(rawValue)
    local numeric = tonumber(rawValue) or 1
    local snapped = math.floor((numeric / RAIDSPLIT_SCALE_STEP) + 0.5) * RAIDSPLIT_SCALE_STEP
    if snapped < RAIDSPLIT_SCALE_MIN then
        snapped = RAIDSPLIT_SCALE_MIN
    elseif snapped > RAIDSPLIT_SCALE_MAX then
        snapped = RAIDSPLIT_SCALE_MAX
    end
    return snapped
end

local function NormalizeRosterName(name)
    if not name or name == "" then
        return nil
    end

    name = tostring(name)
        :gsub("^%s+", "")
        :gsub("%s+$", "")
        :gsub("^%*+", "")
        :gsub("%*+$", "")

    if name == "" then
        return nil
    end

    return name
end

local function GetShortName(name)
    name = NormalizeRosterName(name)
    if not name then
        return nil
    end
    if Ambiguate then
        local short = Ambiguate(name, "short")
        if short and short ~= "" then
            name = short
        end
    end
    if strsplit then
        local short = strsplit("-", name)
        if short and short ~= "" then
            return short:gsub("^%*+", ""):gsub("%*+$", "")
        end
    end
    return (name:match("^([^%-]+)") or name):gsub("^%*+", ""):gsub("%*+$", "")
end

local function GetRosterNameKey(name)
    local normalized = NormalizeRosterName(name)
    return normalized and string.lower(normalized) or nil
end

local function GetShortNameKey(name)
    local short = GetShortName(name)
    return short and string.lower(short) or nil
end

local function NewRosterNameLookup()
    return {
        exact = {},
        short = {},
        shortOwner = {},
        ambiguousShort = {},
    }
end

local function AddRosterNameLookup(lookup, name, value)
    local exactKey = GetRosterNameKey(name)
    if not exactKey then
        return
    end

    lookup.exact[exactKey] = value

    local shortKey = GetShortNameKey(name)
    if not shortKey or lookup.ambiguousShort[shortKey] then
        return
    end

    local owner = lookup.shortOwner[shortKey]
    if owner and owner ~= exactKey then
        lookup.short[shortKey] = nil
        lookup.shortOwner[shortKey] = nil
        lookup.ambiguousShort[shortKey] = true
        return
    end

    lookup.shortOwner[shortKey] = exactKey
    lookup.short[shortKey] = value
end

local function ResolveRosterNameLookup(lookup, name)
    if not lookup then
        return nil, "missing"
    end

    local exactKey = GetRosterNameKey(name)
    if exactKey and lookup.exact[exactKey] ~= nil then
        return lookup.exact[exactKey], "exact"
    end

    local shortKey = GetShortNameKey(name)
    if shortKey and lookup.ambiguousShort[shortKey] then
        return nil, "ambiguous"
    end
    if shortKey and lookup.short[shortKey] ~= nil then
        return lookup.short[shortKey], "short"
    end

    return nil, "missing"
end

local function NamesMatch(nameA, nameB)
    if not nameA or not nameB then
        return false
    end
    local normalizedA = NormalizeRosterName(nameA)
    local normalizedB = NormalizeRosterName(nameB)
    if not normalizedA or not normalizedB then
        return false
    end

    if string.lower(normalizedA) == string.lower(normalizedB) then
        return true
    end

    -- Two explicit realm-qualified names are different characters even if their
    -- short names match. A short-name fallback is only safe when one side lacks
    -- a realm (for example UnitName("player") on the local realm).
    if normalizedA:find("-", 1, true) and normalizedB:find("-", 1, true) then
        return false
    end

    local shortA = GetShortNameKey(normalizedA)
    local shortB = GetShortNameKey(normalizedB)
    return shortA and shortB and shortA == shortB
end

local function ResolveRosterIndex(playerToIndex, targetName)
    return ResolveRosterNameLookup(playerToIndex, targetName)
end

local function CancelTimer(timer)
    if timer and timer.Cancel then
        timer:Cancel()
    end
end

local function ClampGroupIndex(group)
    local g = tonumber(group) or 0
    g = math.floor(g + 0.5)
    if g < 0 then
        return 0
    elseif g > 8 then
        return 8
    end
    return g
end

local function GetSplitTeamColor(teamIndex)
    local index = tonumber(teamIndex) or 1
    local color = SPLIT_TEAM_COLORS[((index - 1) % #SPLIT_TEAM_COLORS) + 1]
    return color or SPLIT_TEAM_COLORS[1]
end

local function RankKey(rankIndex)
    return tostring(rankIndex or 99)
end

-- Local Draft Table: { [unitName] = { group = 1, class = "WARRIOR", ... } }
RaidSplit.DraftRoster = {}

-- Class Classification
local MeleeClasses = {
    ["WARRIOR"] = true,
    ["PALADIN"] = true,
    ["DEATHKNIGHT"] = true,
    ["ROGUE"] = true,
    ["MONK"] = true,
    ["DEMONHUNTER"] = true,
    ["DRUID"] = { ["Feral"] = true, ["Guardian"] = true }, -- Spec check needed for Druid/Sham/Pal/Monk actually
    ["SHAMAN"] = { ["Enhancement"] = true },
    ["HUNTER"] = { ["Survival"] = true },
}

-- Melee Spec IDs (these are constant across all locales)
local MeleeSpecIDs = {
    [70] = true,   -- Paladin: Retribution
    [66] = true,   -- Paladin: Protection
    [103] = true,  -- Druid: Feral
    [104] = true,  -- Druid: Guardian
    [263] = true,  -- Shaman: Enhancement
    [264] = false, -- Shaman: Restoration (ranged/healer)
    [262] = false, -- Shaman: Elemental (ranged)
    [255] = true,  -- Hunter: Survival
    [253] = false, -- Hunter: Beast Mastery (ranged)
    [254] = false, -- Hunter: Marksmanship (ranged)
    [268] = true,  -- Monk: Brewmaster
    [269] = true,  -- Monk: Windwalker
    [270] = false, -- Monk: Mistweaver (ranged/healer)
}

-- Pure melee classes (always melee regardless of spec)
local PureMeleeClasses = {
    ["WARRIOR"] = true,
    ["DEATHKNIGHT"] = true,
    ["ROGUE"] = true,
    ["DEMONHUNTER"] = true,
}

-- Pure ranged classes (never melee)
local PureRangedClasses = {
    ["MAGE"] = true,
    ["PRIEST"] = true,
    ["WARLOCK"] = true,
    ["EVOKER"] = true,
}

local HybridSpecClasses = {
    ["PALADIN"] = true,
    ["DRUID"] = true,
    ["SHAMAN"] = true,
    ["HUNTER"] = true,
    ["MONK"] = true,
}

-- Get SpecID for a unit (used for reliable melee detection)
local function GetUnitSpecID(unit)
    if UnitIsUnit(unit, "player") then
        return (RC:GetPlayerSpecializationInfo())
    end
    return RC:GetInspectSpecID(unit)
end

-- Helper to check if unit is melee
-- Uses SpecID for accuracy (locale-independent) with class-based fallback
local function IsMelee(class, specName, specID)
    -- Pure melee classes are always melee
    if PureMeleeClasses[class] then
        return true
    end

    -- Pure ranged classes are never melee
    if PureRangedClasses[class] then
        return false
    end

    -- If we have a spec ID, use it for accurate determination
    if specID and MeleeSpecIDs[specID] ~= nil then
        return MeleeSpecIDs[specID]
    end

    -- Fallback: use class-based heuristics
    -- These classes can be either melee or ranged depending on spec
    if class == "PALADIN" then
        return true -- Ret/Prot are melee; Holy is usually played in melee range
    end
    if class == "DRUID" then
        -- Feral and Guardian are melee; Balance/Restoration are ranged
        if specName then
            local specLower = specName:lower()
            if specLower:find("feral") or specLower:find("guardian") then
                return true
            end
        end
        return false -- Assume ranged if unknown
    end
    if class == "SHAMAN" then
        -- Only Enhancement is melee
        if specName then
            local specLower = specName:lower()
            if specLower:find("enhancement") or specLower:find("enh") then
                return true
            end
        end
        return false
    end
    if class == "HUNTER" then
        -- Only Survival is melee
        if specName then
            local specLower = specName:lower()
            if specLower:find("survival") or specLower:find("sv") then
                return true
            end
        end
        return false
    end
    if class == "MONK" then
        -- Mistweaver is ranged/healer, Brewmaster and Windwalker are melee
        if specName then
            local specLower = specName:lower()
            if specLower:find("mistweaver") or specLower:find("mw") then
                return false
            end
        end
        return true -- Default to melee for Monks
    end

    return false
end

function RaidSplit:OnInitialize()
    self.inspectSpecCache = {}
    self.inspectSpecNameCache = {}
    self.inspectQueue = {}
    self.inspectQueuedGUIDs = {}
    self.inspectRetryAfter = {}
    self.inspectRequestID = 0
    self.pendingInspectGUID = nil
    self.pendingInspectUnit = nil
    self.pendingMeleeRangedRefresh = nil
end

function RaidSplit:OnEnable()
    -- Called when module is enabled
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupRosterUpdate")
    self:RegisterEvent("GUILD_ROSTER_UPDATE", "OnGuildRosterUpdate")
    self:RegisterEvent("INSPECT_READY", "OnInspectReady")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
    self:RegisterEvent("ENCOUNTER_START", "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
end

function RaidSplit:OnDisable()
    CancelTimer(self.inspectTimeoutTimer)
    CancelTimer(self.processTimer)
    CancelTimer(self.syncTimer)
    CancelTimer(self.rosterRefreshTimer)
    self.inspectTimeoutTimer = nil
    self.processTimer = nil
    self.syncTimer = nil
    self.rosterRefreshTimer = nil
    self.inspectQueue = {}
    self.inspectQueuedGUIDs = {}
    self.pendingInspectGUID = nil
    self.pendingInspectUnit = nil
    self.pendingMeleeRangedRefresh = nil
    self.isProcessing = false
    self.processGeneration = (self.processGeneration or 0) + 1
    if ClearInspectPlayer and not IsInCombat() then
        pcall(ClearInspectPlayer)
    end
end

function RaidSplit:OnGroupRosterUpdate()
    self:ScheduleRosterRefresh(0.5)
    if self.isProcessing then
        self:ScheduleNextMove(0.20, self.processGeneration)
    end
end

function RaidSplit:ScheduleRosterRefresh(delay)
    CancelTimer(self.rosterRefreshTimer)
    self.rosterRefreshTimer = nil

    local function Refresh()
        self.rosterRefreshTimer = nil
        self:RefreshBuffPanel()
    end

    if C_Timer and C_Timer.NewTimer then
        self.rosterRefreshTimer = C_Timer.NewTimer(delay or 0.5, Refresh)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(delay or 0.5, Refresh)
    else
        Refresh()
    end
end

function RaidSplit:OnEncounterStart(_, encounterID, encounterName)
    self.CurrentEncounterID = encounterID
    self.CurrentEncounterName = encounterName
end

function RaidSplit:OnEncounterEnd()
    self.CurrentEncounterID = nil
    self.CurrentEncounterName = nil
end

function RaidSplit:SetFrameScaleStable(scale)
    local snapped = ClampRaidSplitScale(scale)
    local workspace = RC.GetModule and RC:GetModule("Workspace", true)
    local hosted = self.Frame and self.Frame.rcWorkspaceHosted and workspace and workspace.host
    RC.db.profile.raidSplitScale = hosted and workspace:GetScale() or snapped

    local scaleTarget = self.ContentFrame or self.Frame
    if not scaleTarget then
        return snapped
    end

    if hosted then
        scaleTarget:SetScale(1)
        return workspace:GetScale()
    end

    if self.ContentFrame and self.Frame and scaleTarget == self.ContentFrame then
        scaleTarget:SetScale(snapped)
        scaleTarget:ClearAllPoints()
        scaleTarget:SetPoint("CENTER", self.Frame, "CENTER", 0, 0)
        return snapped
    end

    scaleTarget:SetScale(snapped)

    return snapped
end

function RaidSplit:GetWorkspaceScale()
    local workspace = RC:GetModule("Workspace", true)
    if workspace and workspace.GetScale then
        return workspace:GetScale()
    end
    return RC.db.profile.workspaceScale or RC.db.profile.raidSplitScale or 1
end

function RaidSplit:SaveFramePosition()
    if not self.Frame or not RC.db or not RC.db.profile then
        return
    end
    if self.Frame.rcWorkspaceHosted then
        return
    end
    local point, _, relativePoint, x, y = self.Frame:GetPoint(1)
    if point and relativePoint and type(x) == "number" and type(y) == "number" then
        RC.db.profile.raidSplitPos = { point, "UIParent", relativePoint, x, y }
    end
end

function RaidSplit:RestoreFramePosition()
    if not self.Frame then
        return
    end
    if self.Frame.rcWorkspaceHosted then
        return
    end
    local pos = RC.db.profile.raidSplitPos or { "CENTER", "UIParent", "CENTER", 0, 0 }
    self.Frame:ClearAllPoints()
    self.Frame:SetPoint(pos[1] or "CENTER", UIParent, pos[3] or pos[1] or "CENTER", pos[4] or 0, pos[5] or 0)
end

function RaidSplit:ResetPosition()
    local workspace = RC.GetModule and RC:GetModule("Workspace", true)
    if self.Frame and self.Frame.rcWorkspaceHosted and workspace and workspace.ResetActiveWindow then
        return workspace:ResetActiveWindow()
    end
    RC.db.profile.raidSplitPos = { "CENTER", "UIParent", "CENTER", 0, 0 }
    self:RestoreFramePosition()
end

function RaidSplit:OnGuildRosterUpdate()
    if self.pendingGuildImport or (self.GuildImportPanel and self.GuildImportPanel:IsShown()) then
        self:ImportGuildRoster(true)
    end
end

function RaidSplit:CacheSpecByGUID(guid, specID, specName)
    if not guid or not specID or specID <= 0 then
        return
    end
    self.inspectSpecCache = self.inspectSpecCache or {}
    self.inspectSpecNameCache = self.inspectSpecNameCache or {}
    self.inspectSpecCache[guid] = specID

    if not specName and GetSpecializationInfoByID then
        specName = select(2, GetSpecializationInfoByID(specID))
    end
    if specName and specName ~= "" then
        self.inspectSpecNameCache[guid] = specName
    end
end

function RaidSplit:GetCachedSpecByGUID(guid)
    if not guid or not self.inspectSpecCache then
        return nil, nil
    end

    local specID = self.inspectSpecCache[guid]
    if not specID then
        return nil, nil
    end

    local specName = self.inspectSpecNameCache and self.inspectSpecNameCache[guid]
    if not specName and GetSpecializationInfoByID then
        specName = select(2, GetSpecializationInfoByID(specID))
        if specName and specName ~= "" then
            self.inspectSpecNameCache = self.inspectSpecNameCache or {}
            self.inspectSpecNameCache[guid] = specName
        end
    end

    return specID, specName
end

function RaidSplit:QueueInspectUnit(unit)
    if IsInCombat() then
        self.inspectPendingAfterCombat = true
        return false
    end
    if not unit or UnitIsUnit(unit, "player") then
        return false
    end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        return false
    end
    if not CanInspect or not CanInspect(unit, false) then
        return false
    end

    local guid = UnitGUID(unit)
    if not guid then
        return false
    end

    if self.inspectSpecCache and self.inspectSpecCache[guid] then
        return false
    end

    local retryAt = self.inspectRetryAfter and self.inspectRetryAfter[guid]
    if retryAt and GetTime and GetTime() < retryAt then
        return false
    end

    self.inspectQueue = self.inspectQueue or {}
    self.inspectQueuedGUIDs = self.inspectQueuedGUIDs or {}

    if self.inspectQueuedGUIDs[guid] then
        return false
    end

    table.insert(self.inspectQueue, { unit = unit, guid = guid })
    self.inspectQueuedGUIDs[guid] = true
    self:ProcessInspectQueue()
    return true
end

function RaidSplit:ProcessInspectQueue()
    if IsInCombat() then
        self.inspectPendingAfterCombat = true
        return false
    end
    if self.pendingInspectGUID then
        return
    end
    if not self.inspectQueue or #self.inspectQueue == 0 then
        return
    end

    while #self.inspectQueue > 0 do
        local entry = table.remove(self.inspectQueue, 1)
        if entry and entry.guid and self.inspectQueuedGUIDs then
            self.inspectQueuedGUIDs[entry.guid] = nil
        end

        if entry and entry.unit and entry.guid and UnitExists(entry.unit) and UnitGUID(entry.unit) == entry.guid then
            if CanInspect and CanInspect(entry.unit, false) and NotifyInspect then
                self.pendingInspectGUID = entry.guid
                self.pendingInspectUnit = entry.unit
                self.inspectRequestID = (self.inspectRequestID or 0) + 1
                local requestID = self.inspectRequestID
                local requestedGUID = entry.guid
                CancelTimer(self.inspectTimeoutTimer)
                local okNotify = pcall(NotifyInspect, entry.unit)
                if not okNotify then
                    self.pendingInspectGUID = nil
                    self.pendingInspectUnit = nil
                    self.inspectPendingAfterCombat = true
                    return false
                end

                local function OnInspectTimeout()
                    if self.pendingInspectGUID ~= requestedGUID or self.inspectRequestID ~= requestID then
                        return
                    end
                    if IsInCombat() then
                        self.pendingInspectGUID = nil
                        self.pendingInspectUnit = nil
                        self.inspectTimeoutTimer = nil
                        self.inspectPendingAfterCombat = true
                        return
                    end
                    if ClearInspectPlayer then
                        pcall(ClearInspectPlayer)
                    end
                    self.pendingInspectGUID = nil
                    self.pendingInspectUnit = nil
                    self.inspectTimeoutTimer = nil
                    self.inspectRetryAfter = self.inspectRetryAfter or {}
                    self.inspectRetryAfter[requestedGUID] = (GetTime and GetTime() or 0) + 5
                    local refreshed = self:ProcessInspectQueue()
                    if not refreshed then
                        self:FinishPendingInspectRefresh()
                    end
                end

                if C_Timer and C_Timer.NewTimer then
                    self.inspectTimeoutTimer = C_Timer.NewTimer(2, OnInspectTimeout)
                elseif C_Timer and C_Timer.After then
                    C_Timer.After(2, OnInspectTimeout)
                end
                return
            end
        end
    end


    return self:FinishPendingInspectRefresh()
end

function RaidSplit:FinishPendingInspectRefresh()
    local inspectBusy = self.pendingInspectGUID or (self.inspectQueue and #self.inspectQueue > 0)
    if not self.pendingMeleeRangedRefresh or inspectBusy then
        return false
    end

    self.pendingMeleeRangedRefresh = nil
    if self.Frame and self.Frame:IsShown() then
        self:SyncRoster()
        self:MeleeRangedSplit(true)
        self:Print("Melee/range split updated with inspected specs.")
    end
    return true
end

function RaidSplit:QueueMissingHybridSpecInspects()
    local queued = 0

    local function TryQueue(unit)
        if not unit or not UnitExists(unit) then
            return
        end

        local _, class = UnitClass(unit)
        if not class or not HybridSpecClasses[class] then
            return
        end

        local guid = UnitGUID(unit)
        if not guid then
            return
        end
        if self.inspectSpecCache and self.inspectSpecCache[guid] then
            return
        end

        if self:QueueInspectUnit(unit) then
            queued = queued + 1
        end
    end

    if IsInRaid() then
        for i = 1, 40 do
            TryQueue("raid" .. i)
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            TryQueue("party" .. i)
        end
    end

    return queued
end

function RaidSplit:FindUnitByGUID(guid)
    if not guid then
        return nil
    end

    if IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitGUID(unit) == guid then
                return unit
            end
        end
    elseif IsInGroup() then
        if UnitGUID("player") == guid then
            return "player"
        end
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) and UnitGUID(unit) == guid then
                return unit
            end
        end
    else
        if UnitGUID("player") == guid then
            return "player"
        end
    end

    return nil
end

function RaidSplit:OnInspectReady(_, guid)
    if not guid then
        return
    end
    if IsInCombat() then
        CancelTimer(self.inspectTimeoutTimer)
        self.inspectTimeoutTimer = nil
        self.pendingInspectGUID = nil
        self.pendingInspectUnit = nil
        self.inspectPendingAfterCombat = true
        return
    end

    local unit
    if self.pendingInspectUnit and UnitExists(self.pendingInspectUnit) and UnitGUID(self.pendingInspectUnit) == guid then
        unit = self.pendingInspectUnit
    else
        unit = self:FindUnitByGUID(guid)
    end

    if unit and GetInspectSpecialization then
        local specID = GetInspectSpecialization(unit)
        if specID and specID > 0 then
            local specName = nil
            if GetSpecializationInfoByID then
                specName = select(2, GetSpecializationInfoByID(specID))
            end
            self:CacheSpecByGUID(guid, specID, specName)
        end
    end

    if ClearInspectPlayer then
        pcall(ClearInspectPlayer)
    end
    CancelTimer(self.inspectTimeoutTimer)
    self.inspectTimeoutTimer = nil
    if self.inspectRetryAfter then
        self.inspectRetryAfter[guid] = nil
    end
    self.pendingInspectGUID = nil
    self.pendingInspectUnit = nil

    local refreshed = self:ProcessInspectQueue()
    if not refreshed then
        refreshed = self:FinishPendingInspectRefresh()
    end
    if refreshed then
        return
    end

    if self.Frame and self.Frame:IsShown() then
        self:SyncRoster()
    end
end

function RaidSplit:OnPlayerRegenEnabled()
    if self.inspectPendingAfterCombat and ClearInspectPlayer then
        pcall(ClearInspectPlayer)
    end
    self.inspectPendingAfterCombat = nil
    self.pendingInspectGUID = nil
    self.pendingInspectUnit = nil
    self:ProcessInspectQueue()
    if self.Frame and self.Frame:IsShown() then
        self:SyncRoster()
    end
end

function RaidSplit:Toggle()
    -- IsVisible, not IsShown: the page stays "shown" inside the workspace host after the host closes.
    if self:_IsMainFrameUsable() and self.Frame:IsVisible() then
        self.Frame:Hide()
        return
    end
    self:Open()
end

function RaidSplit:Open()
    if not self:_IsMainFrameUsable() then
        local ok, frameOrError = pcall(function()
            return self:CreateMainFrame()
        end)
        if not ok then
            self:_ResetBrokenMainFrame()
            RC:Print("RaidSplit failed to open: " .. tostring(frameOrError))
            return
        end
    end
    if not self:_IsMainFrameUsable() then
        self:_ResetBrokenMainFrame()
        RC:Print("RaidSplit frame is not ready yet. Try again after /reload if this repeats.")
        return
    end
    local ok, err = pcall(self.Frame.Show, self.Frame)
    if not ok then
        self:_ResetBrokenMainFrame()
        RC:Print("RaidSplit failed to show: " .. tostring(err))
        return
    end
    -- OrionUI: the frame lives inside the workspace host. If the page was still flagged shown
    -- from last time, Show() does nothing and the host stays closed, so open the host too.
    local workspace = RC:GetModule("Workspace", true)
    if self.Frame.rcWorkspaceHosted and workspace and workspace.ShowPage then
        workspace:ShowPage("split")
    end
    pcall(function()
        self:SyncRoster()
    end)
end

function RaidSplit:_IsMainFrameUsable()
    return self.Frame
        and self._mainFrameBuilt
        and self.ContentFrame
        and self.HeaderFrame
        and self.ActionBar
        and self.Groups
end

function RaidSplit:_ResetBrokenMainFrame()
    if self.Frame then
        pcall(self.Frame.Hide, self.Frame)
        pcall(self.Frame.SetParent, self.Frame, nil)
    end
    self.Frame = nil
    self.ContentFrame = nil
    self.HeaderFrame = nil
    self.ActionBar = nil
    self.Groups = nil
    self.BuffPanel = nil
    self.SidePanel = nil
    self.GuildImportPanel = nil
    self.HeaderScaleSlider = nil
    self.SideScaleSlider = nil
    self._profilePopup = nil
    self._layoutManagerPopup = nil
    self._themeButtons = nil
    self.splitButtons = nil
    self._mainFrameBuilt = false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Raid Split clean border helper
-- ─────────────────────────────────────────────────────────────────────────────
local function SetRaidSplitSoftBorder(frame, alpha, exact)
    if not frame or not frame.SetBackdropBorderColor then
        return
    end
    local border = RC.Config.Border
    local resolvedAlpha = alpha or 0.45
    if not exact then
        resolvedAlpha = math.max(resolvedAlpha, border.a or 0)
    end
    frame:SetBackdropBorderColor(border.r, border.g, border.b, resolvedAlpha)
end

local function SetRaidSplitLine(texture, alpha)
    if texture and texture.SetColorTexture then
        texture:SetColorTexture(RC.Config.SeparatorColor.r, RC.Config.SeparatorColor.g, RC.Config.SeparatorColor.b, alpha or RC.Config.SeparatorColor.a or 0.35)
    end
end

local function ApplyRaidSplitColumnTheme(frame)
    if not frame then
        return
    end
    local workspace = RC:GetModule("Workspace", true)
    if workspace and workspace.ApplyPageSection then
        workspace:ApplyPageSection(frame)
    else
        RC:ApplyThemedSection(frame)
    end
    if RaidSplit.Frame and RaidSplit.Frame.rcWorkspaceShellPage then
        frame:SetBackdropColor(
            RC.Config.SectionBg.r,
            RC.Config.SectionBg.g,
            RC.Config.SectionBg.b,
            0.20
        )
        frame:SetBackdropBorderColor(
            RC.Config.Border.r,
            RC.Config.Border.g,
            RC.Config.Border.b,
            0.16
        )
    end
end

local function GetRaidSplitHeaderHeight()
    return 52
end

local function GetRaidSplitActionBarHeight()
    return 44
end

local function GetRaidSplitPanelPad()
    return 8
end

local function GetRaidSplitPanelGap()
    return 6
end

-- Resolves the size the page is actually drawn at. Docked pages fill the shared
-- shell pane, whose size is only known once WoW has resolved the anchors.
local function GetRaidSplitContentSize(content, docked)
    local width = content and content.GetWidth and content:GetWidth() or 0
    local height = content and content.GetHeight and content:GetHeight() or 0
    if width > 1 and height > 1 then
        return width, height
    end
    if docked and RC.SettingsV2 and RC.SettingsV2.Layout and RC.SettingsV2.Layout.GetMetrics then
        local m = RC.SettingsV2.Layout:GetMetrics()
        return m.width - m.sidebarWidth - 1, m.height - m.headerHeight - m.footerHeight
    end
    return FRAME_WIDTH, FRAME_HEIGHT
end

-- One source of truth for the page geometry: every column shares the same outer
-- padding and the same gap, and the group cards take whatever width and height
-- are left so the grid always lines up with the side columns.
function RaidSplit:GetLayoutMetrics()
    local frame = self.Frame
    local docked = frame and frame.rcWorkspaceShellPage and true or false
    local headerShown = self.HeaderFrame and self.HeaderFrame:IsShown()
    local pad = GetRaidSplitPanelPad()
    local gap = GetRaidSplitPanelGap()
    local width, height = GetRaidSplitContentSize(self.ContentFrame, docked)

    local m = {
        docked = docked,
        pad = pad,
        gap = gap,
        -- OrionUI: hosted, our header is hidden but the host's 52 px title bar sits over the top
        -- of the page, so the toolbar has to start below it (it was hidden under it).
        headerHeight = (headerShown or (frame and frame.rcWorkspaceHosted and not docked)) and GetRaidSplitHeaderHeight() or 0,
        actionHeight = GetRaidSplitActionBarHeight(),
        sideWidth = SIDE_PANEL_W,
        buffWidth = docked and DOCK_BUFF_PANEL_WIDTH or BUFF_PANEL_W,
    }
    m.bodyTop = m.headerHeight + m.actionHeight + 1 + pad
    m.bodyBottom = 1 + pad

    local innerWidth = width - 2 - pad * 2
    local gridWidth = innerWidth - m.sideWidth - m.buffWidth - gap * 2
    m.groupWidth = math.max(GROUP_MIN_WIDTH, math.floor((gridWidth - gap * 3) / 4))

    local bodyHeight = height - m.bodyTop - m.bodyBottom
    m.groupHeight = math.max(GROUP_HEADER_HEIGHT + SLOT_HEIGHT_MIN * 5, math.floor((bodyHeight - gap) / 2))

    local slotSpace = m.groupHeight - GROUP_HEADER_HEIGHT - GROUP_SLOT_INSET * 2 - GROUP_SLOT_GAP * 4
    m.slotHeight = math.max(SLOT_HEIGHT_MIN, math.min(SLOT_HEIGHT_MAX, math.floor(slotSpace / 5)))
    m.slotWidth = m.groupWidth - GROUP_SLOT_INSET * 2
    return m
end

local function GetRaidSplitSlotOffset(slotIndex, slotHeight)
    return -(GROUP_HEADER_HEIGHT + GROUP_SLOT_INSET) - ((slotIndex - 1) * (slotHeight + GROUP_SLOT_GAP))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared flat button helper (used by CreateMainFrame and CreateProfileButton)
-- ─────────────────────────────────────────────────────────────────────────────
local function MakeBtn(parent, w, h, label, r, g, b)
    local useAccent = r ~= nil or g ~= nil or b ~= nil
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(w, h)
    btn:SetBackdrop(RC.Config.Backdrop)
    RC:ApplyThemedPanel(btn, "button")
    btn._rcRaidSplitAccentButton = useAccent

    -- Retained as a state hook, but deliberately invisible in the clean skin.
    local line = btn:CreateTexture(nil, "OVERLAY")
    line:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  0, 0)
    line:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    line:SetHeight(1)
    line:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.80)
    line:SetAlpha(0)
    line:Hide()
    btn.accentLine = line

    local fs = btn:CreateFontString(nil, "OVERLAY")
    RC:SetFont(fs, 11, "")
    fs:SetPoint("CENTER")
    fs:SetText(label)
    btn.labelText = fs

    local function ApplyButtonStyle(state)
        local bg
        if state == "pressed" then
            bg = RC.Config.ButtonPressed
        elseif state == "hover" then
            bg = btn._rcRaidSplitAccentButton and RC.Config.AccentHover or RC.Config.ButtonHover
        elseif btn._rcRaidSplitAccentButton then
            bg = RC.Config.Accent
        else
            bg = RC.Config.ButtonBg
        end
        btn:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
        if state == "hover" or state == "pressed" or btn._rcRaidSplitAccentButton then
            btn:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
        else
            SetRaidSplitSoftBorder(btn, RC:IsShadowsteelTheme() and 1 or 0.40)
        end
        if btn.labelText then
            if btn._rcRaidSplitAccentButton then
                btn.labelText:SetTextColor(0.02, 0.08, 0.07, 1)
            else
                btn.labelText:SetTextColor(RC:GetButtonTextColor())
            end
        end
        if btn.accentLine then
            btn.accentLine:SetColorTexture(RC.Config.NavSelectedBorder.r, RC.Config.NavSelectedBorder.g, RC.Config.NavSelectedBorder.b, 0.80)
            btn.accentLine:Hide()
        end
    end

    function btn:RefreshTheme()
        RC:ApplyThemedPanel(self, "button")
        ApplyButtonStyle("normal")
    end

    btn:SetScript("OnEnter", function()
        ApplyButtonStyle("hover")
    end)
    btn:SetScript("OnLeave", function()
        ApplyButtonStyle("normal")
    end)
    btn:SetScript("OnMouseDown", function()
        ApplyButtonStyle("pressed")
    end)
    btn:SetScript("OnMouseUp", function()
        ApplyButtonStyle(btn:IsMouseOver() and "hover" or "normal")
    end)
    btn:RefreshTheme()
    if RaidSplit._themeButtons then
        table.insert(RaidSplit._themeButtons, btn)
    end
    return btn
end

-- Split presets behave like a segmented control: the last preset used stays lit
-- in the theme's selected-navigation colors until another one is picked.
local function StyleSplitPresetButton(btn)
    if not btn then
        return
    end
    if btn.active then
        local border = RC.Config.NavSelectedBorder or RC.Config.Accent
        local text = RC.Config.NavSelectedText or RC.Config.Accent
        btn:SetBackdropBorderColor(border.r, border.g, border.b, 0.72)
        if btn.labelText then
            btn.labelText:SetTextColor(text.r, text.g, text.b, 1)
        end
    else
        SetRaidSplitSoftBorder(btn, 0.40)
        if btn.labelText then
            btn.labelText:SetTextColor(RC:GetButtonTextColor())
        end
    end
    if btn.accentLine then
        btn.accentLine:SetShown(btn.active and true or false)
    end
end

local function AddButtonTooltip(btn, title, body)
    btn:HookScript("OnEnter", function(owner)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)
        if body then
            GameTooltip:AddLine(body, 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function CreateHeaderScaleSlider(parent, options)
    local minScale = options.minScale or RAIDSPLIT_SCALE_MIN
    local maxScale = options.maxScale or RAIDSPLIT_SCALE_MAX
    local stepScale = options.stepScale or RAIDSPLIT_SCALE_STEP
    local defaultScale = options.defaultScale or 1.00
    local applyScale = options.applyScale
    local getScale = options.getScale
    local tooltipTitle = options.tooltipTitle or "Scale"
    local mrtLike = options.mrtLike and true or false
    local liveApply = options.liveApply and true or false

    do
        local control = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        control:SetSize(math.max(options.width or 104, 104), math.max(options.height or 20, 20))
        control:SetPoint(unpack(options.point))
        control:SetFrameStrata(options.frameStrata or parent:GetFrameStrata())
        control:SetFrameLevel(options.frameLevel or (parent:GetFrameLevel() + 1))
        control:EnableMouse(true)
        control:EnableMouseWheel(true)
        RC:SkinFrame(control)
        RC:ApplyThemedPanel(control, "input")

        local function ClampPercent(rawValue)
            return math.max(minScale * 100, math.min(maxScale * 100, tonumber(rawValue) or (defaultScale * 100)))
        end

        local function SnapPercent(rawValue)
            local stepPercent = stepScale * 100
            local snapped = math.floor((rawValue or 0) / stepPercent + 0.5) * stepPercent
            return ClampPercent(snapped)
        end

        local currentPercent = ClampPercent(((getScale and getScale()) or defaultScale) * 100)

        local minus = CreateFrame("Button", nil, control, "BackdropTemplate")
        minus:SetSize(20, 16)
        minus:SetPoint("LEFT", control, "LEFT", 2, 0)
        RC:SkinFrame(minus)
        RC:ApplyThemedPanel(minus, "button")

        local minusText = minus:CreateFontString(nil, "OVERLAY")
        RC:SetFont(minusText, 12, "OUTLINE")
        minusText:SetPoint("CENTER")
        minusText:SetText("-")

        local plus = CreateFrame("Button", nil, control, "BackdropTemplate")
        plus:SetSize(20, 16)
        plus:SetPoint("RIGHT", control, "RIGHT", -2, 0)
        RC:SkinFrame(plus)
        RC:ApplyThemedPanel(plus, "button")

        local plusText = plus:CreateFontString(nil, "OVERLAY")
        RC:SetFont(plusText, 12, "OUTLINE")
        plusText:SetPoint("CENTER")
        plusText:SetText("+")

        local valueText = control:CreateFontString(nil, "OVERLAY")
        RC:SetFont(valueText, 10, "OUTLINE")
        valueText:SetPoint("LEFT", minus, "RIGHT", 2, 0)
        valueText:SetPoint("RIGHT", plus, "LEFT", -2, 0)
        valueText:SetJustifyH("CENTER")
        valueText:SetTextColor(RC.Config.SectionAccent.r, RC.Config.SectionAccent.g, RC.Config.SectionAccent.b, 1)

        local valueHitBox = CreateFrame("Button", nil, control)
        valueHitBox:SetPoint("LEFT", minus, "RIGHT", 2, 0)
        valueHitBox:SetPoint("RIGHT", plus, "LEFT", -2, 0)
        valueHitBox:SetHeight(16)

        local valueEdit = CreateFrame("EditBox", nil, control, "BackdropTemplate")
        valueEdit:SetPoint("LEFT", minus, "RIGHT", 2, 0)
        valueEdit:SetPoint("RIGHT", plus, "LEFT", -2, 0)
        valueEdit:SetHeight(16)
        valueEdit:SetAutoFocus(false)
        valueEdit:SetJustifyH("CENTER")
        valueEdit:SetNumeric(false)
        valueEdit:SetTextInsets(2, 2, 0, 0)
        RC:SkinFrame(valueEdit)
        RC:SetFont(valueEdit, 10, "OUTLINE")
        valueEdit:Hide()

        local editingValue = false

        local function UpdateText()
            valueText:SetText(string.format("%d%%", math.floor(currentPercent + 0.5)))
            if not editingValue then
                valueEdit:SetText(tostring(math.floor(currentPercent + 0.5)))
            end
        end

        local function ApplyPercent(percent, snapToStep)
            local applied = snapToStep and SnapPercent(percent) or ClampPercent(percent)
            if math.abs(currentPercent - applied) < 0.001 then
                UpdateText()
                return
            end
            currentPercent = applied
            UpdateText()
            if applyScale then
                applyScale(applied / 100)
            end
        end

        local function FinishEditing(apply)
            if not editingValue then return end
            editingValue = false
            if apply then
                local typed = tostring(valueEdit:GetText() or ""):match("[-%d%.]+")
                local percent = typed and tonumber(typed)
                if percent then
                    ApplyPercent(percent, false)
                else
                    UpdateText()
                end
            else
                UpdateText()
            end
            valueEdit:ClearFocus()
            valueEdit:Hide()
            valueText:Show()
            valueHitBox:Show()
        end

        local function StartEditing()
            if editingValue then return end
            editingValue = true
            valueHitBox:Hide()
            valueText:Hide()
            valueEdit:SetText(tostring(math.floor(currentPercent + 0.5)))
            valueEdit:Show()
            valueEdit:SetFocus()
            valueEdit:HighlightText()
        end

        local function Step(direction)
            ApplyPercent(currentPercent + (direction * stepScale * 100), false)
        end

        minus:SetScript("OnClick", function() Step(-1) end)
        plus:SetScript("OnClick", function() Step(1) end)
        valueHitBox:SetScript("OnClick", StartEditing)
        valueEdit:SetScript("OnEnterPressed", function() FinishEditing(true) end)
        valueEdit:SetScript("OnEscapePressed", function() FinishEditing(false) end)
        valueEdit:SetScript("OnEditFocusLost", function() FinishEditing(true) end)
        valueEdit:SetScript("OnEnter", function()
            valueEdit:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
        end)
        valueEdit:SetScript("OnLeave", function()
            valueEdit:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))
        end)
        control:SetScript("OnMouseWheel", function(_, delta)
            if not editingValue then
                Step(delta > 0 and 1 or -1)
            end
        end)
        control:SetScript("OnMouseDown", function(_, button)
            if button == "RightButton" then
                ApplyPercent(defaultScale * 100, false)
            end
        end)
        control:SetScript("OnEnter", function()
            control:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
            GameTooltip:SetOwner(control, "ANCHOR_TOP")
            GameTooltip:SetText(string.format("%s: %s", tooltipTitle, valueText:GetText()), 1, 1, 1, 1, true)
            GameTooltip:AddLine("Click +/- or mouse wheel. Click value to type. Right-click resets.", 0.75, 0.75, 0.75, true)
            GameTooltip:AddLine("Enter applies. Escape cancels.", 0.62, 0.62, 0.62, true)
            GameTooltip:Show()
        end)
        control:SetScript("OnLeave", function()
            control:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))
            GameTooltip:Hide()
        end)

        function control:RefreshFromDB(forcedScale)
            currentPercent = ClampPercent((forcedScale or (getScale and getScale()) or defaultScale) * 100)
            UpdateText()
        end

        function control:GetValue()
            return currentPercent
        end

        function control:RefreshTheme()
            RC:ApplyThemedPanel(control, "input")
            RC:ApplyThemedPanel(minus, "button")
            RC:ApplyThemedPanel(plus, "button")
            RC:ApplyThemedPanel(valueEdit, "input")
            valueText:SetTextColor(RC.Config.SectionAccent.r, RC.Config.SectionAccent.g, RC.Config.SectionAccent.b, 1)
        end

        control:RefreshFromDB()
        control:RefreshTheme()
        return control
    end

end

function RaidSplit:CreateMainFrame()
    if self.Frame then
        if self:_IsMainFrameUsable() then
            return self.Frame
        end
        self:_ResetBrokenMainFrame()
    end
    self._mainFrameBuilt = false
    self._themeButtons = {}

    -- ── Outer frame ────────────────────────────────────────────────────────────
    local f = CreateFrame("Frame", "RaidControlSplitFrame", UIParent)
    self.Frame = f
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    self:RestoreFramePosition()
    -- Root frame should not capture mouse. Interactive children handle input.
    f:EnableMouse(false)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")

    local content = CreateFrame("Frame", nil, f)
    self.ContentFrame = content
    content:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    content:SetPoint("CENTER", f, "CENTER", 0, 0)
    content:EnableMouse(false)
    content:SetClipsChildren(true)
    RC:SkinFrame(content)
    RC:ApplyThemedWindow(content, "window")

    self:SetFrameScaleStable(1)
    f:Hide()

    local lvl = content:GetFrameLevel()

    -- ══════════════════════════════════════════════════════════════════════════
    -- HEADER (50 px tall, polished split-builder title bar)
    -- ══════════════════════════════════════════════════════════════════════════
    local HDR_H = GetRaidSplitHeaderHeight()
    local header = CreateFrame("Frame", nil, content)
    self.HeaderFrame = header
    header:SetHeight(HDR_H)
    header:SetPoint("TOPLEFT",  content, "TOPLEFT",  1, -1)
    header:SetPoint("TOPRIGHT", content, "TOPRIGHT", -1, -1)
    header:SetFrameLevel(lvl + 12)
    header:EnableMouse(false)

    local hBg = header:CreateTexture(nil, "BACKGROUND")
    hBg:SetAllPoints()
    hBg:SetColorTexture(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 1)
    self.HeaderBg = hBg

    local hGlow = header:CreateTexture(nil, "BACKGROUND", nil, 1)
    hGlow:SetAllPoints()
    hGlow:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
    if hGlow.SetGradient and CreateColor then
        hGlow:SetGradient(
            "HORIZONTAL",
            CreateColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.10),
            CreateColor(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0)
        )
    else
        hGlow:SetAlpha(0.035)
    end
    self.HeaderGlow = hGlow

    -- Left accent stripe
    local hAccentBar = header:CreateTexture(nil, "BORDER")
    hAccentBar:SetWidth(2)
    hAccentBar:SetPoint("TOPLEFT",    header, "TOPLEFT",    0, -3)
    hAccentBar:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0,  3)
    hAccentBar:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
    self.HeaderAccentBar = hAccentBar

    -- Bottom separator line
    local hLine = header:CreateTexture(nil, "BORDER")
    hLine:SetHeight(1)
    hLine:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT",  0, 0)
    hLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
    SetRaidSplitLine(hLine, 0.42)
    self.HeaderLine = hLine

    -- Breadcrumb line 1: "Raid Split"
    local hTitle1 = header:CreateFontString(nil, "OVERLAY")
    RC:SetFont(hTitle1, 15, "OUTLINE")
    hTitle1:SetPoint("TOPLEFT", header, "TOPLEFT", 20, -8)
    hTitle1:SetText("Raid Split")
    hTitle1:SetTextColor(1, 1, 1)

    -- Breadcrumb line 2: "› Manager"
    local hTitle2 = header:CreateFontString(nil, "OVERLAY")
    RC:SetFont(hTitle2, 10, "OUTLINE")
    hTitle2:SetPoint("TOPLEFT", header, "TOPLEFT", 20, -27)
    hTitle2:SetText("Group builder")
    hTitle2:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)
    self.HeaderSubtitle = hTitle2

    -- Roster count (right of title)
    local rosterCount = header:CreateFontString(nil, "OVERLAY")
    RC:SetFont(rosterCount, 10, "OUTLINE")
    rosterCount:SetPoint("LEFT", hTitle1, "RIGHT", 10, 0)
    rosterCount:SetText("")
    rosterCount:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)
    self.RosterCountLabel = rosterCount

    -- Close button
    local closeBtn = RC:CreateCloseButton(header, 24)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -10, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    f.CloseButton = closeBtn

    -- Profiles button (left of close)
    local profilesBtn = MakeBtn(header, 84, 24, "Profiles")
    profilesBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)
    self:_WireProfileButton(profilesBtn, f)

    local saveBtn = MakeBtn(header, 56, 24, "Save")
    saveBtn:SetPoint("RIGHT", profilesBtn, "LEFT", -8, 0)
    saveBtn:SetScript("OnClick", function()
        self:QuickSaveLayout()
    end)
    saveBtn:HookScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:SetText("Quick Save", 1, 1, 1)
        GameTooltip:AddLine("Save the current draft setup with an automatic timestamped name.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    saveBtn:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Keep scale control in the header action cluster, aligned with Save / Profiles / Close.
    self.HeaderScaleSlider = CreateHeaderScaleSlider(content, {
        point = { "RIGHT", saveBtn, "LEFT", -8, 0 },
        width = 116,
        height = 24,
        frameLevel = lvl + 40,
        tooltipTitle = "Workspace Panels Scale",
        minScale = RAIDSPLIT_SCALE_MIN,
        maxScale = RAIDSPLIT_SCALE_MAX,
        stepScale = RAIDSPLIT_SCALE_STEP,
        defaultScale = 1.00,
        mrtLike = true,
        getScale = function()
            return self:GetWorkspaceScale()
        end,
        applyScale = function(value)
            self:UpdateScale(value, "header")
        end,
    })
    self.HeaderScaleSlider._rcAnchorXOff = -258
    self.HeaderScaleSlider._rcAnchorYOff = -13
    self.HeaderScaleSlider._rcAnchorWidth = 116
    self.HeaderScaleSlider._rcAnchorHeight = 24
    self.HeaderScaleSlider._rcTrackInset = 3
    self.HeaderScaleSlider:Hide()

    -- Realign once after slider creation so the current scale is immediately
    -- anchored to the thumb location (prevents first-drag jumps).
    self:SetFrameScaleStable(1)

    -- Dedicated drag zone on the left side of the header so slider/buttons never trigger frame movement.
    local dragHandle = CreateFrame("Frame", nil, header)
    dragHandle:SetPoint("TOPLEFT", header, "TOPLEFT", 1, -1)
    dragHandle:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -300, 1)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function()
        f:StartMoving()
    end)
    dragHandle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        self:SaveFramePosition()
    end)

    -- ══════════════════════════════════════════════════════════════════════════
    -- ACTION BAR (44 px): split buttons + Apply/Reset on right
    -- Placed directly below the header
    -- ══════════════════════════════════════════════════════════════════════════
    local ABH = GetRaidSplitActionBarHeight()
    local actionBar = CreateFrame("Frame", nil, content)
    self.ActionBar = actionBar
    actionBar:SetHeight(ABH)
    actionBar:SetPoint("TOPLEFT",  content, "TOPLEFT",  1, -(HDR_H + 1))
    actionBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -1, -(HDR_H + 1))
    actionBar:SetFrameLevel(lvl + 10)

    local abBg = actionBar:CreateTexture(nil, "BACKGROUND")
    abBg:SetAllPoints()
    abBg:SetColorTexture(RC.Config.TabBg.r, RC.Config.TabBg.g, RC.Config.TabBg.b, RC.Config.TabBg.a or 0.94)
    self.ActionBarBg = abBg

    local abTopLine = actionBar:CreateTexture(nil, "BORDER")
    abTopLine:SetHeight(1)
    abTopLine:SetPoint("TOPLEFT",  actionBar, "TOPLEFT",  0, 0)
    abTopLine:SetPoint("TOPRIGHT", actionBar, "TOPRIGHT", 0, 0)
    SetRaidSplitLine(abTopLine, 0.38)
    self.ActionBarTopLine = abTopLine

    local abBottomLine = actionBar:CreateTexture(nil, "BORDER")
    abBottomLine:SetHeight(1)
    abBottomLine:SetPoint("BOTTOMLEFT",  actionBar, "BOTTOMLEFT",  0, 0)
    abBottomLine:SetPoint("BOTTOMRIGHT", actionBar, "BOTTOMRIGHT", 0, 0)
    SetRaidSplitLine(abBottomLine, 0.38)
    self.ActionBarBottomLine = abBottomLine

    -- ── Split preset buttons ───────────────────────────────────────────────
    -- Left split presets use the same flat button style as the right action cluster.
    -- Both clusters use one button height and one gap; the outer inset is set by
    -- ApplyThemedLayout so the toolbar lines up with the columns below it.
    self.splitButtons = {}
    local BTN_H = 28
    local BTN_GAP = 6
    local splitDefs = {
        { label = "2 Groups", width = 76, onClick = function() self:SmartSplit(2) end,
          tip = "Smart split the raid into two teams." },
        { label = "3 Groups", width = 76, onClick = function() self:SmartSplit(3) end,
          tip = "Smart split the raid into three teams." },
        { label = "4 Groups", width = 76, onClick = function() self:SmartSplit(4) end,
          tip = "Smart split the raid into four teams." },
        { label = "Melee / Range", width = 104, onClick = function() self:MeleeRangedSplit() end,
          tip = "Put melee and ranged players in separate groups." },
    }

    local previousSplit
    for _, def in ipairs(splitDefs) do
        local btn = MakeBtn(actionBar, def.width, BTN_H, def.label)
        if previousSplit then
            btn:SetPoint("LEFT", previousSplit, "RIGHT", BTN_GAP, 0)
        else
            btn:SetPoint("LEFT", actionBar, "LEFT", GetRaidSplitPanelPad(), 0)
        end
        previousSplit = btn

        btn.active = false
        local capturedDef = def
        btn:SetScript("OnClick", function()
            for _, b in ipairs(RaidSplit.splitButtons) do
                b.active = (b == btn)
                StyleSplitPresetButton(b)
            end
            capturedDef.onClick()
        end)
        -- MakeBtn's hover handlers repaint the border; restore the selected look afterwards.
        btn:HookScript("OnEnter", function(b)
            if b.active then
                StyleSplitPresetButton(b)
            end
        end)
        btn:HookScript("OnLeave", StyleSplitPresetButton)
        AddButtonTooltip(btn, def.label, def.tip)

        table.insert(self.splitButtons, btn)
    end

    -- ── Apply / Reset buttons (right cluster) ────────────────────────────────
    local applyBtn = MakeBtn(
        actionBar,
        112,
        BTN_H,
        "Apply Changes",
        RC.Config.Accent.r,
        RC.Config.Accent.g,
        RC.Config.Accent.b
    )
    applyBtn:SetPoint("RIGHT", actionBar, "RIGHT", -GetRaidSplitPanelPad(), 0)
    applyBtn:SetScript("OnClick", function()
        self:ShowApplyConfirmation()
    end)
    AddButtonTooltip(applyBtn, "Apply Changes", "Move players in the live raid to match this draft.")
    self.ApplyButton = applyBtn

    -- Reset re-reads the live raid and throws away the draft. It replaces the old
    -- separate Sync button, which ran exactly the same action.
    local resetBtn = MakeBtn(actionBar, 64, BTN_H, "Reset")
    resetBtn:SetPoint("RIGHT", applyBtn, "LEFT", -BTN_GAP, 0)
    resetBtn:HookScript("OnEnter", function()
        resetBtn:SetBackdropColor(RC.Config.DangerColor.r * 0.5, 0.06, 0.06, 1)
    end)
    resetBtn:SetScript("OnClick", function() self:SyncRoster() end)
    AddButtonTooltip(resetBtn, "Reset", "Discard the draft and reload the current raid groups.")

    -- Thin divider between the draft actions and the roster/profile tools.
    local actionDivider = actionBar:CreateTexture(nil, "ARTWORK")
    actionDivider:SetSize(1, 18)
    actionDivider:SetPoint("RIGHT", resetBtn, "LEFT", -BTN_GAP * 2, 0)
    SetRaidSplitLine(actionDivider, 0.40)
    self.ActionBarDivider = actionDivider

    local guildImportBtn = MakeBtn(actionBar, 90, BTN_H, "Import Guild")
    guildImportBtn:SetPoint("RIGHT", actionDivider, "LEFT", -BTN_GAP * 2, 0)
    guildImportBtn:SetScript("OnClick", function()
        if self.GuildImportPanel and self.GuildImportPanel:IsShown() then
            self.GuildImportPanel:Hide()
            return
        end
        self:ImportGuildRoster()
    end)
    AddButtonTooltip(guildImportBtn, "Import Guild", "Show guild members next to the groups so you can drag them in. Click again to close.")
    f.GuildImportButton = guildImportBtn

    -- Build grid and side panel
    self:CreateGrid(content)
    self:CreateBuffPanel(content)
    self:CreateSidePanel(content)
    self:CreateGuildImportPanel(content)

    RC:RegisterEscapeFrame(f)

    local workspace = RC:GetModule("Workspace", true)
    if workspace and workspace.RegisterWindow then
        workspace:RegisterWindow("split", f, {
            chromeParent = header,
            placeChrome = function(bar)
                bar:ClearAllPoints()
                bar:SetPoint("CENTER", header, "CENTER", 0, 0)
            end,
            rightClickTargets = { dragHandle },
            pageRoot = content,
            legacyChrome = { header },
            onHosted = function()
                saveBtn:SetParent(actionBar)
                saveBtn:SetSize(56, BTN_H)
                profilesBtn:ClearAllPoints()
                profilesBtn:SetParent(actionBar)
                profilesBtn:SetSize(76, BTN_H)
                profilesBtn:SetPoint("RIGHT", guildImportBtn, "LEFT", -BTN_GAP, 0)
                saveBtn:ClearAllPoints()
                saveBtn:SetPoint("RIGHT", profilesBtn, "LEFT", -BTN_GAP, 0)
                header:Hide()
                self:ApplyThemedLayout()
                content:SetBackdropBorderColor(0, 0, 0, 0)
            end,
            onShellHosted = function()
                f.rcWorkspaceShellPage = true
                header:Hide()
                self:ApplyThemedLayout()
            end,
            reset = function()
                self:ResetPosition()
            end,
        })
    end

    -- Clean up tooltip and drag state when the frame is hidden
    f:HookScript("OnHide", function()
        GameTooltip:Hide()
        if self.DragFrame then self.DragFrame:Hide() end
        if self.DraggingSource and self.DraggingSource.SetAlpha then
            self.DraggingSource:SetAlpha(1)
        end
        self.DraggingData = nil
        self.DraggingSource = nil
        if self.GuildImportPanel then
            self.GuildImportPanel:Hide()
        end
    end)
    f:HookScript("OnShow", function()
        if self.HeaderScaleSlider then
            self.HeaderScaleSlider:RefreshFromDB()
        end
        if self.SideScaleSlider and self.SideScaleSlider.RefreshFromDB then
            self.SideScaleSlider:RefreshFromDB()
        end
        self:RefreshTheme()
    end)
    -- Docked pages only learn their real size after the shell lays out; re-fit then.
    content:HookScript("OnSizeChanged", function()
        if self._mainFrameBuilt then
            self:ApplyThemedLayout()
        end
    end)
    self._mainFrameBuilt = true
    self:RefreshTheme()
    return f
end

function RaidSplit:ApplyThemedLayout()
    local content = self.ContentFrame
    if not content or self._applyingLayout then
        return
    end
    self._applyingLayout = true

    local docked = self.Frame and self.Frame.rcWorkspaceShellPage

    content:ClearAllPoints()
    if docked then
        content:SetAllPoints(self.Frame)
    else
        content:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
        content:SetPoint("CENTER", self.Frame, "CENTER", 0, 0)
    end
    content:SetFrameLevel(self.Frame:GetFrameLevel() + 1)

    local m = self:GetLayoutMetrics()
    local headerH = m.headerHeight
    local actionH = m.actionHeight
    local pad = m.pad
    local gap = m.gap
    local groupWidth = m.groupWidth
    local groupHeight = m.groupHeight
    local slotHeight = m.slotHeight
    local buffPanelWidth = m.buffWidth

    if self.HeaderFrame then
        self.HeaderFrame:ClearAllPoints()
        self.HeaderFrame:SetHeight(GetRaidSplitHeaderHeight())
        self.HeaderFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 1, -1)
        self.HeaderFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -1, -1)
    end

    if self.ActionBar then
        self.ActionBar:ClearAllPoints()
        self.ActionBar:SetHeight(actionH)
        self.ActionBar:SetPoint("TOPLEFT", content, "TOPLEFT", 1, -(headerH + 1))
        self.ActionBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -1, -(headerH + 1))
        self.ActionBar:SetFrameLevel(content:GetFrameLevel() + 10)
        -- Toolbar buttons share the body's outer padding so they line up with the columns below.
        local firstSplit = self.splitButtons and self.splitButtons[1]
        if firstSplit then
            firstSplit:ClearAllPoints()
            firstSplit:SetPoint("LEFT", self.ActionBar, "LEFT", pad, 0)
        end
        if self.ApplyButton then
            self.ApplyButton:ClearAllPoints()
            self.ApplyButton:SetPoint("RIGHT", self.ActionBar, "RIGHT", -pad, 0)
        end
    end

    local startY = -(headerH + actionH + 1)
    local bodyY = startY - pad
    local colSpacing = groupWidth + gap
    local rowSpacing = groupHeight + gap
    for index, group in ipairs(self.Groups or {}) do
        local col = (index - 1) % 4
        local row = math.floor((index - 1) / 4)
        group:ClearAllPoints()
        group:SetSize(groupWidth, groupHeight)
        group:SetFrameLevel(content:GetFrameLevel() + 4)
        group:SetPoint("TOPLEFT", content, "TOPLEFT", 1 + pad + col * colSpacing, bodyY - row * rowSpacing)
        for slotIndex, slot in ipairs(group.Slots or {}) do
            slot:ClearAllPoints()
            slot:SetSize(m.slotWidth, slotHeight)
            slot:SetFrameLevel(group:GetFrameLevel() + 1)
            slot:SetPoint("TOPLEFT", group, "TOPLEFT", GROUP_SLOT_INSET, GetRaidSplitSlotOffset(slotIndex, slotHeight))
        end
    end

    local sideRight = -(1 + pad)
    local buffRight = sideRight - m.sideWidth - gap

    if self.BuffPanel then
        self.BuffPanel:ClearAllPoints()
        self.BuffPanel:SetWidth(buffPanelWidth)
        self.BuffPanel:SetFrameLevel(content:GetFrameLevel() + 4)
        self.BuffPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", buffRight, bodyY)
        self.BuffPanel:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", buffRight, m.bodyBottom)
        for _, row in pairs(self.BuffPanel.buffRows or {}) do
            row:SetWidth(buffPanelWidth - 20)
            if row.label then
                RC:SetFont(row.label, docked and 11 or 12, "OUTLINE")
            end
        end
        for _, row in ipairs(self.BuffPanel.synergyRows or {}) do
            row:SetWidth(buffPanelWidth - 20)
            if row.label then
                RC:SetFont(row.label, docked and 9 or 10, "OUTLINE")
            end
        end
    end

    if self.SidePanel then
        self.SidePanel:ClearAllPoints()
        self.SidePanel:SetWidth(m.sideWidth)
        self.SidePanel:SetFrameLevel(content:GetFrameLevel() + 4)
        self.SidePanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", sideRight, bodyY)
        self.SidePanel:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", sideRight, m.bodyBottom)
    end

    -- The guild list slides over the two right-hand columns. It used to sit past the
    -- page's right edge, where the clipping page and shell cut it off entirely.
    if self.GuildImportPanel then
        self.GuildImportPanel:ClearAllPoints()
        self.GuildImportPanel:SetWidth(m.sideWidth + gap + buffPanelWidth)
        self.GuildImportPanel:SetFrameLevel(content:GetFrameLevel() + 12)
        self.GuildImportPanel:SetPoint("TOPRIGHT", content, "TOPRIGHT", sideRight, bodyY)
        self.GuildImportPanel:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", sideRight, m.bodyBottom)
    end

    self._applyingLayout = nil
end

function RaidSplit:RefreshTheme()
    if self.Frame and not self:_IsMainFrameUsable() then
        self:_ResetBrokenMainFrame()
        return
    end
    self:ApplyThemedLayout()
    if self.ContentFrame then
        RC:ApplyThemedWindow(self.ContentFrame, "window")
        if self.Frame and self.Frame.rcWorkspaceHosted then
            local workspace = RC:GetModule("Workspace", true)
            if workspace and workspace.ApplyHostedPageRoot then
                workspace:ApplyHostedPageRoot(self.ContentFrame)
            end
        end
    end
    if self.HeaderBg then
        self.HeaderBg:SetColorTexture(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, RC.Config.HeaderBg.a or 1)
    end
    if self.HeaderGlow then
        self.HeaderGlow:SetShown(not RC:IsShadowsteelTheme())
        if self.HeaderGlow.SetGradient and CreateColor then
            self.HeaderGlow:SetGradient(
                "HORIZONTAL",
                CreateColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, RC.Config.Glow.a or 0.08),
                CreateColor(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0)
            )
        end
    end
    if self.HeaderAccentBar then
        self.HeaderAccentBar:SetColorTexture(RC.Config.SectionAccent.r, RC.Config.SectionAccent.g, RC.Config.SectionAccent.b, RC:IsShadowsteelTheme() and 0.85 or 1)
    end
    if self.HeaderLine then
        SetRaidSplitLine(self.HeaderLine, 0.42)
    end
    if self.HeaderSubtitle then
        self.HeaderSubtitle:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
    end
    if self.RosterCountLabel then
        self.RosterCountLabel:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
    end
    local docked = self.Frame and self.Frame.rcWorkspaceShellPage
    if self.ActionBarBg then
        self.ActionBarBg:SetColorTexture(
            RC.Config.TabBg.r,
            RC.Config.TabBg.g,
            RC.Config.TabBg.b,
            docked and 0.54 or (RC.Config.TabBg.a or 0.94)
        )
    end
    if self.ActionBarTopLine then
        SetRaidSplitLine(self.ActionBarTopLine, docked and 0.16 or 0.38)
    end
    if self.ActionBarBottomLine then
        SetRaidSplitLine(self.ActionBarBottomLine, docked and 0.20 or 0.38)
    end
    if self.HeaderScaleSlider and self.HeaderScaleSlider.RefreshTheme then
        self.HeaderScaleSlider:RefreshTheme()
    end
    if self.SideScaleSlider and self.SideScaleSlider.RefreshTheme then
        self.SideScaleSlider:RefreshTheme()
    end
    for _, btn in ipairs(self._themeButtons or {}) do
        if btn and btn.RefreshTheme then
            btn:RefreshTheme()
        end
    end
    for _, btn in ipairs(self.splitButtons or {}) do
        if btn.accentLine then
            btn.accentLine:SetColorTexture(RC.Config.NavSelectedBorder.r, RC.Config.NavSelectedBorder.g, RC.Config.NavSelectedBorder.b, 0.80)
        end
        StyleSplitPresetButton(btn)
    end
    if self.ActionBarDivider then
        SetRaidSplitLine(self.ActionBarDivider, docked and 0.28 or 0.40)
    end
    for _, group in ipairs(self.Groups or {}) do
        RC:ApplyThemedSection(group)
        if group.titleLabel then
            group.titleLabel:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
        end
        if group.headerLine then
            SetRaidSplitLine(group.headerLine, docked and 0.20 or 0.28)
        end
        if docked then
            group:SetBackdropColor(
                RC.Config.SectionBg.r,
                RC.Config.SectionBg.g,
                RC.Config.SectionBg.b,
                0.18
            )
            group:SetBackdropBorderColor(
                RC.Config.Border.r,
                RC.Config.Border.g,
                RC.Config.Border.b,
                0.16
            )
        end
    end
    if self.BuffPanel then
        if self.BuffPanel.RefreshTheme then
            self.BuffPanel:RefreshTheme()
        else
            ApplyRaidSplitColumnTheme(self.BuffPanel)
        end
    end
    if self.SidePanel then
        ApplyRaidSplitColumnTheme(self.SidePanel)
        if self.SidePanel._rcRefreshers then
            for _, refresh in ipairs(self.SidePanel._rcRefreshers) do
                pcall(refresh)
            end
        end
    end
    if self.GuildImportPanel then
        if self.GuildImportPanel.RefreshTheme then
            self.GuildImportPanel:RefreshTheme()
        else
            RC:ApplyThemedSection(self.GuildImportPanel)
        end
    end
    if self._profilePopup then
        if self._profilePopup.RefreshTheme then
            self._profilePopup:RefreshTheme()
        else
            self._profilePopup:SetBackdropColor(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, RC.Config.Color.a or 0.98)
            SetRaidSplitSoftBorder(self._profilePopup, 0.55)
        end
        if self._profilePopup:IsShown() and self._RefreshProfilePopup then
            self:_RefreshProfilePopup()
        end
    end
    if self.RefreshGrid and self.Groups then
        self:RefreshGrid()
    end
    if self.RefreshBuffPanel then
        self:RefreshBuffPanel()
    end
    if self.RefreshGuildImportPanel then
        self:RefreshGuildImportPanel()
    end
    if self.Frame and self.Frame.rcWorkspaceHosted and self.ContentFrame then
        self.ContentFrame:SetBackdropColor(0, 0, 0, 0)
        self.ContentFrame:SetBackdropBorderColor(0, 0, 0, 0)
    end
end

function RaidSplit:GetGuildRankVisibilityMap()
    RC.db.profile.raidSplitGuildRankVisibility = RC.db.profile.raidSplitGuildRankVisibility or {}
    return RC.db.profile.raidSplitGuildRankVisibility
end

function RaidSplit:IsGuildRankVisible(rankIndex)
    local state = self:GetGuildRankVisibilityMap()[RankKey(rankIndex)]
    if state == nil then
        return true
    end
    return state and true or false
end

function RaidSplit:SetGuildRankVisible(rankIndex, isVisible)
    self:GetGuildRankVisibilityMap()[RankKey(rankIndex)] = isVisible and true or false
end

function RaidSplit:FindDraftUnitByName(name)
    if not name or not self.DraftRoster then
        return nil
    end

    local lookup = NewRosterNameLookup()
    for _, unit in ipairs(self.DraftRoster) do
        if unit and unit.name then
            AddRosterNameLookup(lookup, unit.name, unit)
        end
    end

    return ResolveRosterNameLookup(lookup, name)
end

function RaidSplit:ResolveDragSourceUnit(sourceUnit)
    if not sourceUnit then
        return nil
    end

    self.DraftRoster = self.DraftRoster or {}

    if not sourceUnit.fromGuildRoster then
        return sourceUnit
    end

    local existing = self:FindDraftUnitByName(sourceUnit.name)
    if existing then
        return existing
    end

    if #self.DraftRoster >= 40 then
        self:Print("Draft is full (40 players).")
        return nil
    end

    local draftUnit = {
        name = sourceUnit.name,
        group = 0,
        class = sourceUnit.class,
        level = sourceUnit.level,
        role = sourceUnit.role or "DPS",
        specName = sourceUnit.specName,
        specID = sourceUnit.specID,
    }
    table.insert(self.DraftRoster, draftUnit)
    return draftUnit
end

function RaidSplit:StartDragFromData(unitData, sourceFrame)
    if not unitData then
        return
    end

    GameTooltip:Hide()

    if not self.DragFrame then
        local d = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        d:SetSize(GROUP_WIDTH - GROUP_SLOT_INSET * 2, SLOT_HEIGHT)
        d:SetFrameStrata("TOOLTIP")
        d:SetBackdrop(RC.Config.Backdrop)
        d:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, 0.92)
        d:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.55)
        d.stripe = d:CreateTexture(nil, "ARTWORK")
        d.stripe:SetWidth(4)
        d.stripe:SetPoint("TOPLEFT", d, "TOPLEFT", 0, -1)
        d.stripe:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", 0, 1)
        d.text = d:CreateFontString(nil, "OVERLAY")
        RC:SetFont(d.text, 12, "OUTLINE")
        d.text:SetPoint("LEFT", 10, 0)
        d.text:SetPoint("RIGHT", -6, 0)
        d.text:SetJustifyH("LEFT")
        d:SetScript("OnUpdate", function(dd)
            local x, y = GetCursorPosition()
            local sc = UIParent:GetEffectiveScale()
            dd:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc, y / sc)
        end)
        self.DragFrame = d
    end

    local color = RAID_CLASS_COLORS[unitData.class] or { r = 1, g = 1, b = 1 }
    if sourceFrame and sourceFrame.GetWidth and sourceFrame:GetWidth() > 0 then
        self.DragFrame:SetSize(sourceFrame:GetWidth(), sourceFrame:GetHeight())
    end
    self.DragFrame.text:SetText(unitData.name or "")
    self.DragFrame.text:SetTextColor(color.r, color.g, color.b)
    self.DragFrame.stripe:SetColorTexture(color.r, color.g, color.b, 0.90)
    self.DragFrame:Show()

    self.DraggingData = unitData
    self.DraggingSource = sourceFrame
    if sourceFrame and sourceFrame.SetAlpha then
        sourceFrame:SetAlpha(0.25)
    end
end

function RaidSplit:StopDragging(sourceFrame)
    if self.DragFrame then
        self.DragFrame:Hide()
    end

    SetCursor(nil)

    if sourceFrame and sourceFrame.SetAlpha then
        sourceFrame:SetAlpha(1)
    elseif self.DraggingSource and self.DraggingSource.SetAlpha then
        self.DraggingSource:SetAlpha(1)
    end

    C_Timer.After(0.05, function()
        self.DraggingData = nil
        self.DraggingSource = nil
    end)
end

function RaidSplit:BuildAssignedDraftLookup()
    local lookup = NewRosterNameLookup()
    for _, unit in ipairs(self.DraftRoster or {}) do
        if unit and unit.name then
            AddRosterNameLookup(lookup, unit.name, true)
        end
    end
    return lookup
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CREATE GRID  (8-group kanban board)
-- ─────────────────────────────────────────────────────────────────────────────
function RaidSplit:CreateGrid(parent)
    self.Groups = {}

    -- Grid area: 4 columns × 2 rows left of the buff and options columns.
    -- Initial placement only; ApplyThemedLayout re-fits everything to the real page size.
    local m = self:GetLayoutMetrics()
    local HDR_H     = m.headerHeight
    local ACTION_H  = m.actionHeight
    local START_Y   = -(HDR_H + ACTION_H + 1)
    local START_X   = 1 + m.pad
    local COL_SPC   = m.groupWidth + m.gap
    local ROW_SPC   = m.groupHeight + m.gap

    local STRIPE_W  = 4
    local SLOT_H    = m.slotHeight
    local SLOT_W_IN = m.slotWidth
    local HEADER_MID = -math.floor(GROUP_HEADER_HEIGHT / 2)

    for i = 1, 8 do
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)

        -- ── Group panel ───────────────────────────────────────────────────────
        local gf = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        gf:SetSize(m.groupWidth, m.groupHeight)
        gf:SetPoint("TOPLEFT", parent, "TOPLEFT",
            START_X + col * COL_SPC,
            START_Y - m.pad - row * ROW_SPC)
        gf:SetClipsChildren(true)
        gf:SetBackdrop(RC.Config.Backdrop)
        RC:ApplyThemedSection(gf)
        gf._rcRaidSplitGroup = true

        local teamTint = gf:CreateTexture(nil, "BACKGROUND")
        teamTint:SetPoint("TOPLEFT", gf, "TOPLEFT", 1, -1)
        teamTint:SetPoint("BOTTOMRIGHT", gf, "BOTTOMRIGHT", -1, 1)
        teamTint:SetColorTexture(0, 0, 0, 0)
        teamTint:Hide()
        gf.teamTint = teamTint

        -- ── Group header ───────────────────────────────────────────────────────
        local ghBg = gf:CreateTexture(nil, "BACKGROUND")
        ghBg:SetHeight(GROUP_HEADER_HEIGHT - 1)
        ghBg:SetPoint("TOPLEFT",  gf, "TOPLEFT",  1, -1)
        ghBg:SetPoint("TOPRIGHT", gf, "TOPRIGHT", -1, -1)
        ghBg:SetColorTexture(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0.94)
        gf.headerBg = ghBg

        -- Left edge stripe. Only lit when the group belongs to a split team, so the
        -- team colors carry meaning instead of every card wearing the same accent.
        local ghStripe = gf:CreateTexture(nil, "OVERLAY")
        ghStripe:SetWidth(2)
        ghStripe:SetPoint("TOPLEFT",    gf, "TOPLEFT",    0, -1)
        ghStripe:SetPoint("BOTTOMLEFT", gf, "BOTTOMLEFT", 0, 1)
        ghStripe:SetColorTexture(0, 0, 0, 0)
        gf.stripe = ghStripe

        -- 1px separator under header
        local ghLine = gf:CreateTexture(nil, "BORDER")
        ghLine:SetHeight(1)
        ghLine:SetPoint("TOPLEFT",  gf, "TOPLEFT",  1, -GROUP_HEADER_HEIGHT)
        ghLine:SetPoint("TOPRIGHT", gf, "TOPRIGHT", -1, -GROUP_HEADER_HEIGHT)
        SetRaidSplitLine(ghLine, 0.28)
        gf.headerLine = ghLine

        -- "Group N" label, aligned with the slot text below it
        local gLabel = gf:CreateFontString(nil, "OVERLAY")
        RC:SetFont(gLabel, 12, "OUTLINE")
        gLabel:SetPoint("LEFT", gf, "TOPLEFT", GROUP_SLOT_INSET + STRIPE_W + 6, HEADER_MID)
        gLabel:SetText("Group " .. i)
        gLabel:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b)
        gf.titleLabel = gLabel

        -- Member count (right side of header, aligned with the role icons below)
        local gCount = gf:CreateFontString(nil, "OVERLAY")
        RC:SetFont(gCount, 10, "OUTLINE")
        gCount:SetPoint("RIGHT", gf, "TOPRIGHT", -(GROUP_SLOT_INSET + 4), HEADER_MID)
        gCount:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)
        gCount:SetText("0/5")
        gf.countLabel = gCount

        local teamBadge = gf:CreateFontString(nil, "OVERLAY")
        RC:SetFont(teamBadge, 9, "OUTLINE")
        teamBadge:SetPoint("RIGHT", gCount, "LEFT", -8, 0)
        teamBadge:SetText("")
        teamBadge:SetTextColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
        teamBadge:Hide()
        gf.teamBadge = teamBadge

        -- ── Slots ─────────────────────────────────────────────────────────────
        gf.Slots = {}
        for j = 1, 5 do
            local yOff = GetRaidSplitSlotOffset(j, SLOT_H)

            local slot = CreateFrame("Button", nil, gf, "BackdropTemplate")
            slot:SetSize(SLOT_W_IN, SLOT_H)
            slot:SetPoint("TOPLEFT", gf, "TOPLEFT", GROUP_SLOT_INSET, yOff)
            slot:SetBackdrop(RC.Config.Backdrop)
            RC:ApplyThemedPanel(slot, "input", { alpha = RC.Config.InputBg.a or 0.88 })
            slot._rcRaidSplitSlotIndex = j
            slot:RegisterForDrag("LeftButton")
            slot:RegisterForClicks("AnyUp")

            -- Left class-color stripe
            local stripe = slot:CreateTexture(nil, "ARTWORK")
            stripe:SetWidth(STRIPE_W)
            stripe:SetPoint("TOPLEFT",    slot, "TOPLEFT",    0, -1)
            stripe:SetPoint("BOTTOMLEFT", slot, "BOTTOMLEFT", 0,  1)
            stripe:SetColorTexture(0.5, 0.5, 0.5, 0)
            slot.stripe = stripe

            -- Role icon (right side)
            local roleIcon = slot:CreateTexture(nil, "OVERLAY")
            roleIcon:SetSize(14, 14)
            roleIcon:SetPoint("RIGHT", slot, "RIGHT", -6, 0)
            roleIcon:Hide()
            slot.roleIcon = roleIcon

            -- DPS score (Details! balancing). Sits left of the role icon so the two
            -- never draw on top of each other.
            slot.dpsText = slot:CreateFontString(nil, "OVERLAY")
            RC:SetFont(slot.dpsText, 9, "OUTLINE")
            slot.dpsText:SetPoint("RIGHT", roleIcon, "LEFT", -2, 0)
            slot.dpsText:SetJustifyH("RIGHT")
            slot.dpsText:SetText("")

            -- Name text
            slot.text = slot:CreateFontString(nil, "OVERLAY")
            RC:SetFont(slot.text, 12, "OUTLINE")
            slot.text:SetPoint("LEFT",  slot, "LEFT",  STRIPE_W + 6, 0)
            slot.text:SetPoint("RIGHT", slot.dpsText, "LEFT", -2, 0)
            slot.text:SetJustifyH("LEFT")
            if slot.text.SetWordWrap then slot.text:SetWordWrap(false) end
            slot.text:SetText("")
            slot.text:SetTextColor(0.45, 0.45, 0.45)

            slot:SetScript("OnDragStart", function(s)
                if not s.data then return end
                self:StartDragFromData(s.data, s)
            end)

            slot:SetScript("OnDragStop", function(s)
                self:StopDragging(s)
            end)

            slot:SetScript("OnEnter", function(s)
                if s.data then
                    s:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.50)
                    GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
                    local color = RAID_CLASS_COLORS[s.data.class] or {r=1,g=1,b=1}
                    local hex = string.format("ff%02x%02x%02x", color.r*255, color.g*255, color.b*255)
                    GameTooltip:AddLine(string.format("|c%s%s|r", hex, s.data.name))
                    if s.data.role     then GameTooltip:AddLine(s.data.role,     0.7,0.7,0.7) end
                    if s.data.specName then GameTooltip:AddLine(s.data.specName, 0.7,0.7,0.7) end
                    GameTooltip:AddLine("|cffaaaaaaRight-click for options|r")
                    GameTooltip:Show()
                elseif self.DraggingData then
                    s:SetBackdropBorderColor(0.3, 0.9, 0.3, 0.8)
                end
            end)

            slot:SetScript("OnLeave", function(s)
                GameTooltip:Hide()
                local docked = self.Frame and self.Frame.rcWorkspaceShellPage
                if s.data then
                    SetRaidSplitSoftBorder(s, docked and 0.14 or 0.28, docked)
                else
                    SetRaidSplitSoftBorder(s, docked and 0.08 or 0.20, docked)
                end
            end)

            local function OnDrop(s)
                if self.DraggingData then
                    self:HandleDrop(self.DraggingData, i, s.data)
                    SetCursor(nil)
                end
            end
            slot:SetScript("OnReceiveDrag", OnDrop)
            slot:SetScript("OnClick", function(s, button)
                if button == "RightButton" then
                    if s.data then
                        self:ShowSlotContextMenu(s)
                    end
                    return
                end
                OnDrop(s)
            end)

            table.insert(gf.Slots, slot)
        end

        self.Groups[i] = gf
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CREATE SIDE PANEL  (right column: smart split options)
-- ─────────────────────────────────────────────────────────────────────────────
function RaidSplit:CreateBuffPanel(parent)
    -- Initial placement only; ApplyThemedLayout re-fits the column to the page.
    local m = self:GetLayoutMetrics()
    local right = -(1 + m.pad + m.sideWidth + m.gap)

    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetWidth(m.buffWidth)
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", right, -m.bodyTop)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", right, m.bodyBottom)
    panel:SetClipsChildren(true)
    panel:SetBackdrop(RC.Config.Backdrop)
    ApplyRaidSplitColumnTheme(panel)
    panel:SetFrameLevel(parent:GetFrameLevel() + 4)

    -- Heading rhythm matches the Smart split column next to it: 10pt accent
    -- label, hairline underline, first row 42px from the top.
    local PAD = 10
    local yOff = -18

    local title = panel:CreateFontString(nil, "OVERLAY")
    RC:SetFont(title, 10, "OUTLINE")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yOff)
    title:SetText("Raid buffs")

    local titleLine = panel:CreateTexture(nil, "ARTWORK")
    titleLine:SetHeight(1)
    titleLine:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yOff - 16)
    titleLine:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, yOff - 16)
    titleLine:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.25)

    local refresh = MakeBtn(panel, 60, 20, "Refresh")
    refresh:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, yOff + 6)
    refresh:SetScript("OnClick", function()
        RaidSplit:RefreshBuffPanel()
    end)
    AddButtonTooltip(refresh, "Refresh", "Re-scan food, flask, rune, weapon and core raid buffs.")
    panel.refresh = refresh
    yOff = yOff - 24

    panel.buffRows = {}
    -- Each row is: status dot, name, raid count. Your own status moved into the
    -- tooltip so the column reads as one clean list instead of three columns.
    local function BuffRow(key, label, description)
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(BUFF_PANEL_W - PAD * 2, 24)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yOff)
        row:EnableMouse(true)
        row.buffLabel = label
        row.description = description
        yOff = yOff - 24

        local stripe = row:CreateTexture(nil, "ARTWORK")
        stripe:SetSize(6, 6)
        stripe:SetPoint("LEFT", row, "LEFT", 0, 0)
        stripe:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.85)
        row.stripe = stripe

        row.label = row:CreateFontString(nil, "OVERLAY")
        RC:SetFont(row.label, 12, "OUTLINE")
        row.label:SetPoint("LEFT", row, "LEFT", 14, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -44, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetText(label)
        row.label:SetTextColor(0.82, 0.82, 0.82, 1)

        -- Kept for the refresh code; the personal status now lives in the tooltip.
        row.mine = row:CreateFontString(nil, "OVERLAY")
        RC:SetFont(row.mine, 10, "OUTLINE")
        row.mine:Hide()

        row.value = row:CreateFontString(nil, "OVERLAY")
        RC:SetFont(row.value, 12, "OUTLINE")
        row.value:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.value:SetWidth(34)
        row.value:SetJustifyH("RIGHT")
        row.value:SetText("0/0")

        row:SetScript("OnEnter", function(r)
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:SetText(r.buffLabel or "Raid Buffs", 1, 1, 1, 1, true)
            if r.description then
                GameTooltip:AddLine(r.description, 0.72, 0.72, 0.72, true)
            end
            if r.mineStatus then
                local sr, sg, sb = r.mineReady and 0.35 or 1, r.mineReady and 1 or 0.45, r.mineReady and 0.35 or 0.25
                GameTooltip:AddLine(r.mineStatus, sr, sg, sb, true)
            end
            if r.missingNames and #r.missingNames > 0 then
                GameTooltip:AddLine("Missing players:", 1, 0.78, 0.25, true)
                GameTooltip:AddLine(table.concat(r.missingNames, ", "), 1, 0.45, 0.25, true)
            else
                GameTooltip:AddLine("Raid covered.", 0.35, 1, 0.35, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        panel.buffRows[key] = row
    end

    BuffRow("food", "Food", "Well Fed from food or a feast.")
    BuffRow("flask", "Flask", "A flask or phial.")
    BuffRow("rune", "Augment rune", "An augment rune.")
    BuffRow("weapon", "Weapon oil", "A temporary weapon buff: mana or wizard oil, sharpening stone, weightstone, or a Shaman weapon imbue.")

    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yOff - 2)
    sep:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, yOff - 2)
    SetRaidSplitLine(sep, 0.28)
    yOff = yOff - 16

    panel.synergyLabel = panel:CreateFontString(nil, "OVERLAY")
    RC:SetFont(panel.synergyLabel, 10, "OUTLINE")
    panel.synergyLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yOff)
    panel.synergyLabel:SetText("Core buffs")
    panel.synergyLabel:SetTextColor(RC.Config.Accent.r * 0.85, RC.Config.Accent.g * 0.85, RC.Config.Accent.b * 0.85)
    yOff = yOff - 20

    panel.synergyRows = {}
    local coreRowCount = #(RC.GetCoreBuffRules and RC:GetCoreBuffRules() or {})
    for i = 1, math.max(coreRowCount, 11) do
        local row = CreateFrame("Frame", nil, panel)
        row:SetSize(BUFF_PANEL_W - PAD * 2, 20)
        row:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yOff - ((i - 1) * 20))
        row:EnableMouse(true)

        local stripe = row:CreateTexture(nil, "ARTWORK")
        stripe:SetSize(6, 6)
        stripe:SetPoint("LEFT", row, "LEFT", 0, 0)
        stripe:SetColorTexture(1, 0.35, 0.20, 0.9)
        row.stripe = stripe

        row.label = row:CreateFontString(nil, "OVERLAY")
        RC:SetFont(row.label, 10, "OUTLINE")
        row.label:SetPoint("LEFT", row, "LEFT", 14, 0)
        row.label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetTextColor(1, 0.45, 0.25, 1)
        if row.label.SetWordWrap then row.label:SetWordWrap(false) end
        if row.label.SetNonSpaceWrap then row.label:SetNonSpaceWrap(false) end

        row.state = row:CreateFontString(nil, "OVERLAY")
        RC:SetFont(row.state, 9, "OUTLINE")
        row.state:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.state:SetWidth(42)
        row.state:SetJustifyH("RIGHT")
        row.state:Hide()

        row:SetScript("OnEnter", function(r)
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            GameTooltip:SetText(r.buffLabel or "Core Buff", 1, 1, 1, 1, true)
            if r.raidStatus then
                local rr, rg, rb = r.raidReady and 0.35 or 1, r.raidReady and 1 or 0.45, r.raidReady and 0.35 or 0.25
                GameTooltip:AddLine(r.raidStatus, rr, rg, rb, true)
            end
            if r.personalStatus then
                local pr, pg, pb = r.personalReady and 0.35 or 1, r.personalReady and 1 or 0.45, r.personalReady and 0.35 or 0.25
                GameTooltip:AddLine(r.personalStatus, pr, pg, pb, true)
            end
            if r.providerText then
                GameTooltip:AddLine(r.providerText, 0.72, 0.72, 0.72, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:Hide()
        panel.synergyRows[i] = row
    end

    function panel:RefreshTheme()
        ApplyRaidSplitColumnTheme(self)
        title:SetTextColor(RC.Config.Accent.r * 0.85, RC.Config.Accent.g * 0.85, RC.Config.Accent.b * 0.85, 1)
        titleLine:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.25)
        SetRaidSplitLine(sep, 0.28)
        self.synergyLabel:SetTextColor(RC.Config.Accent.r * 0.85, RC.Config.Accent.g * 0.85, RC.Config.Accent.b * 0.85, 1)
        if self.refresh and self.refresh.RefreshTheme then
            self.refresh:RefreshTheme()
        end
    end

    self.BuffPanel = panel
    panel:RefreshTheme()
    self:RefreshBuffPanel()
end

function RaidSplit:CreateSidePanel(parent)
    -- Initial placement only; ApplyThemedLayout re-fits the column to the page.
    local m = self:GetLayoutMetrics()

    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetWidth(m.sideWidth)
    panel:SetPoint("TOPRIGHT",    parent, "TOPRIGHT",    -(1 + m.pad), -m.bodyTop)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(1 + m.pad), m.bodyBottom)
    panel:SetClipsChildren(true)
    panel:SetBackdrop(RC.Config.Backdrop)
    ApplyRaidSplitColumnTheme(panel)
    panel:SetFrameLevel(parent:GetFrameLevel() + 4)
    panel._rcRefreshers = {}
    self.SidePanel = panel

    local PAD   = 10
    local INNER = SIDE_PANEL_W - PAD * 2
    local yOff  = -10

    -- ── Local helpers ─────────────────────────────────────────────────────────
    local function SectionLabel(text)
        yOff = yOff - 8

        local lbl = panel:CreateFontString(nil, "OVERLAY")
        RC:SetFont(lbl, 10, "OUTLINE")
        lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yOff)
        lbl:SetText(text)
        lbl:SetTextColor(RC.Config.Accent.r * 0.85, RC.Config.Accent.g * 0.85, RC.Config.Accent.b * 0.85)
        yOff = yOff - 16

        local ul = panel:CreateTexture(nil, "ARTWORK")
        ul:SetHeight(1)
        ul:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD, yOff)
        ul:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, yOff)
        ul:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.25)
        yOff = yOff - 8

        local function Refresh()
            lbl:SetTextColor(RC.Config.Accent.r * 0.85, RC.Config.Accent.g * 0.85, RC.Config.Accent.b * 0.85, 1)
            ul:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.25)
        end
        table.insert(panel._rcRefreshers, Refresh)
    end

    local function Divider()
        yOff = yOff - 6
        local t = panel:CreateTexture(nil, "ARTWORK")
        t:SetHeight(1)
        t:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD, yOff)
        t:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, yOff)
        SetRaidSplitLine(t, 0.28)
        yOff = yOff - 6

        table.insert(panel._rcRefreshers, function()
            SetRaidSplitLine(t, 0.28)
        end)
    end

    local function Checkbox(text, dbKey, tip)
        local ROW_H = 28
        local BOX   = 14

        local btn = CreateFrame("Button", nil, panel)
        btn:SetSize(INNER, ROW_H)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yOff)
        yOff = yOff - ROW_H - 4

        local box = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        box:SetSize(BOX, BOX)
        box:SetPoint("LEFT", 0, 0)
        box:SetBackdrop(RC.Config.Backdrop)
        box:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, 1)
        SetRaidSplitSoftBorder(box, 0.48)

        local fill = box:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT",     box, "TOPLEFT",     2, -2)
        fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2,  2)
        fill:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        RC:SetFont(lbl, 11, "OUTLINE")
        lbl:SetPoint("LEFT", box, "RIGHT", 6, 0)
        lbl:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
        lbl:SetJustifyH("LEFT")
        if lbl.SetWordWrap then lbl:SetWordWrap(false) end
        if lbl.SetNonSpaceWrap then lbl:SetNonSpaceWrap(false) end
        lbl:SetText(text)

        local function Refresh()
            local on = RC.db.profile[dbKey]
            box:SetBackdropColor(RC.Config.CheckboxBg.r, RC.Config.CheckboxBg.g, RC.Config.CheckboxBg.b, RC.Config.CheckboxBg.a or 1)
            fill:SetColorTexture(RC.Config.CheckboxChecked.r, RC.Config.CheckboxChecked.g, RC.Config.CheckboxChecked.b, RC.Config.CheckboxChecked.a or 1)
            fill:SetShown(on and true or false)
            if on then
                box:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
                lbl:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
            else
                box:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.12, RC.Config.InputBorder.a or 0))
                lbl:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
            end
        end

        btn:SetScript("OnClick", function()
            RC.db.profile[dbKey] = not RC.db.profile[dbKey]
            Refresh()
        end)
        btn:SetScript("OnEnter", function()
            box:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 0.7)
            if tip then
                GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
                GameTooltip:SetText(tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function() Refresh(); GameTooltip:Hide() end)
        Refresh()
        table.insert(panel._rcRefreshers, Refresh)
    end

    local openDDs = {}

    local function Dropdown(labelText, dbKey, values, labels, tip)
        local DD_H = 30

        local lbl = panel:CreateFontString(nil, "OVERLAY")
        RC:SetFont(lbl, 10, "OUTLINE")
        lbl:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yOff)
        lbl:SetText(labelText)
        lbl:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
        yOff = yOff - 16

        local btn = CreateFrame("Button", nil, panel, "BackdropTemplate")
        btn:SetSize(INNER, DD_H)
        btn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yOff)
        btn:SetBackdrop(RC.Config.Backdrop)
        btn:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, 1)
        SetRaidSplitSoftBorder(btn, 0.48)
        yOff = yOff - DD_H - 8

        local valTxt = btn:CreateFontString(nil, "OVERLAY")
        RC:SetFont(valTxt, 11, "OUTLINE")
        valTxt:SetPoint("LEFT",  btn, "LEFT",  8, 0)
        valTxt:SetPoint("RIGHT", btn, "RIGHT", -24, 0)
        valTxt:SetJustifyH("LEFT")
        if valTxt.SetWordWrap then valTxt:SetWordWrap(false) end
        if valTxt.SetNonSpaceWrap then valTxt:SetNonSpaceWrap(false) end

        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(12, 12)
        arrow:SetPoint("RIGHT", btn, "RIGHT", -7, 0)
        if RC.Icons and RC.Icons.Texture and RC.Icons.ArrowDown then
            arrow:SetTexture(RC.Icons.Texture)
            arrow:SetTexCoord(unpack(RC.Icons.ArrowDown))
        else
            arrow:SetColorTexture(1, 1, 1, 0.55)
        end

        local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        popup:SetSize(INNER, #values * DD_H + 4)
        popup:SetFrameStrata("TOOLTIP")
        popup:SetFrameLevel(900)
        popup:SetBackdrop(RC.Config.Backdrop)
        popup:SetBackdropColor(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, 0.98)
        SetRaidSplitSoftBorder(popup, 0.55)
        popup:Hide()
        table.insert(openDDs, popup)

        local items = {}

        local function StyleClosed(hovered)
            btn:SetBackdropColor(RC.Config.DropdownBg.r, RC.Config.DropdownBg.g, RC.Config.DropdownBg.b, RC.Config.DropdownBg.a or 1)
            local border = (hovered or popup:IsShown()) and RC.Config.InputFocus or RC.Config.DropdownBorder
            btn:SetBackdropBorderColor(border.r, border.g, border.b, math.max(0.18, border.a or 1))
            valTxt:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
            arrow:SetVertexColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
            lbl:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
        end

        for idx, v in ipairs(values) do
            local item = CreateFrame("Button", nil, popup)
            item._value = v
            item._text = labels[idx]
            item:SetHeight(DD_H)
            item:SetPoint("LEFT",  popup, "LEFT",  1, 0)
            item:SetPoint("RIGHT", popup, "RIGHT", -1, 0)
            item:SetPoint("TOP",   popup, "TOP",   0, -2 - (idx - 1) * DD_H)
            item.selected = item:CreateTexture(nil, "BACKGROUND")
            item.selected:SetAllPoints()
            item.selected:Hide()
            item.hover = item:CreateTexture(nil, "ARTWORK")
            item.hover:SetAllPoints()
            item.hover:Hide()
            item.marker = item:CreateTexture(nil, "OVERLAY")
            item.marker:SetWidth(2)
            item.marker:SetPoint("TOPLEFT", item, "TOPLEFT", 3, -4)
            item.marker:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 3, 4)
            item.marker:Hide()
            local itxt = item:CreateFontString(nil, "OVERLAY")
            RC:SetFont(itxt, 11, "OUTLINE")
            itxt:SetPoint("LEFT", 10, 0)
            itxt:SetPoint("RIGHT", -8, 0)
            itxt:SetJustifyH("LEFT")
            itxt:SetText(labels[idx])
            item.text = itxt
            table.insert(items, item)
            item:SetScript("OnEnter", function(row)
                row.hover:Show()
                row.text:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 1)
            end)
            item:SetScript("OnLeave", function(row)
                row.hover:Hide()
                if row.RefreshState then
                    row:RefreshState()
                end
            end)
            item:SetScript("OnClick", function()
                RC.db.profile[dbKey] = v
                popup:Hide()
                if btn.RefreshDD then
                    btn:RefreshDD()
                end
            end)
        end

        local function RefreshDD()
            local val = RC.db.profile[dbKey]
            local matched = false
            popup:SetBackdropColor(RC.Config.DropdownBg.r, RC.Config.DropdownBg.g, RC.Config.DropdownBg.b, RC.Config.DropdownBg.a or 0.98)
            popup:SetBackdropBorderColor(RC.Config.DropdownBorder.r, RC.Config.DropdownBorder.g, RC.Config.DropdownBorder.b, math.max(0.18, RC.Config.DropdownBorder.a or 1))
            for idx, v in ipairs(values) do
                local item = items[idx]
                if item then
                    function item:RefreshState()
                        self.hover:SetColorTexture(RC.Config.DropdownHover.r, RC.Config.DropdownHover.g, RC.Config.DropdownHover.b, RC.Config.DropdownHover.a or 0.24)
                        self.selected:SetColorTexture(RC.Config.DropdownSelected.r, RC.Config.DropdownSelected.g, RC.Config.DropdownSelected.b, RC.Config.DropdownSelected.a or 0.28)
                        self.marker:SetColorTexture(RC.Config.SectionAccent.r, RC.Config.SectionAccent.g, RC.Config.SectionAccent.b, 0.85)
                        self.selected:SetShown(self._value == RC.db.profile[dbKey])
                        self.marker:SetShown(self._value == RC.db.profile[dbKey])
                        if self._value == RC.db.profile[dbKey] then
                            self.text:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 1)
                        else
                            self.text:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
                        end
                    end
                    item:RefreshState()
                end
                if v == val then
                    valTxt:SetText(labels[idx])
                    matched = true
                end
            end
            if not matched then
                valTxt:SetText(labels[1] or "")
            end
            StyleClosed(false)
        end

        btn.RefreshDD = RefreshDD
        btn:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then
                RC:Print("Raid Split dropdown options are unavailable during combat.")
                return
            end
            if popup:IsShown() then popup:Hide()
            else
                for _, p in ipairs(openDDs) do p:Hide() end
                popup:ClearAllPoints()
                popup:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 2)
                popup:Show()
                RefreshDD()
                StyleClosed(true)
            end
        end)
        btn:SetScript("OnEnter", function()
            StyleClosed(true)
            if tip then GameTooltip:SetOwner(btn,"ANCHOR_LEFT"); GameTooltip:SetText(tip,1,1,1,1,true); GameTooltip:Show() end
        end)
        btn:SetScript("OnLeave", function() RefreshDD(); GameTooltip:Hide() end)
        RefreshDD()
        table.insert(panel._rcRefreshers, RefreshDD)
    end

    -- ── Build the panel contents ─────────────────────────────────────────────
    SectionLabel("Smart split")
    Checkbox("Split Monks",       "smartSplitMonk",        "Split Monks across groups\n(Mystic Touch: +5% physical damage)")
    Checkbox("Split Demon Hunters", "smartSplitDH",          "Split Demon Hunters across groups\n(Chaos Brand: +5% magic damage)")
    Checkbox("Balance DPS",       "smartSplitBalanceDPS",   "Balance DPS between groups\n(requires Details! addon)")
    Checkbox("Keep self in G1",   "smartSplitKeepSelfG1",   "Always place yourself in Group 1")
    Checkbox("2-way odd/even",    "smartSplitTwoWayOddEven", "For 2-group splits, use 1/3/5/7 for Team 1 and 2/4/6/8 for Team 2.")

    Divider()
    SectionLabel("Targets")
    Dropdown("Healers per group", "smartSplitHealers",
        {0,1,2,3,4,5}, {"Auto","1","2","3","4","5"}, "Target healer count per group")
    Dropdown("Tanks per group", "smartSplitTanks",
        {0,1,2}, {"Auto","1","2"}, "Target tank count per group")

    self.SidePanel = panel
end

function RaidSplit:RefreshBuffPanel()
    local box = self.BuffPanel
    if not box or not RC.BuildBuffSnapshot or not RC.FormatBuffSnapshot then
        return
    end

    local snapshot = RC:BuildBuffSnapshot()
    local total = snapshot and (snapshot.available == nil and snapshot.total or snapshot.available) or 0
    local playerBuffs = RC.ScanUnitBuffStatus and RC:ScanUnitBuffStatus("player") or nil
    local playerBuffsAccessible = playerBuffs and playerBuffs.accessible ~= false
    local personalReady = {
        food = playerBuffs and playerBuffs.food and true or false,
        flask = playerBuffs and playerBuffs.flask and true or false,
        rune = playerBuffs and playerBuffs.rune and true or false,
        weapon = playerBuffs and (playerBuffs.weaponMain or playerBuffs.weaponOff or playerBuffs.shamanEnchant) and true or false,
    }

    local function SetBuffRow(key, value, missingNames)
        local row = box.buffRows and box.buffRows[key]
        if not row then
            return
        end

        row.missingNames = missingNames or {}
        row.value:SetText(string.format("%d/%d", value or 0, total or 0))
        if not playerBuffsAccessible then
            row.mine:SetText("N/A")
            row.mine:SetTextColor(0.55, 0.55, 0.55, 1)
            row.mineStatus = "You: aura data unavailable"
            row.mineReady = false
        elseif personalReady[key] then
            row.mine:SetText("OK")
            row.mine:SetTextColor(0.35, 1, 0.35, 1)
            row.mineStatus = "You: ready"
            row.mineReady = true
        else
            row.mine:SetText("MISS")
            row.mine:SetTextColor(1, 0.45, 0.25, 1)
            row.mineStatus = "You: missing"
            row.mineReady = false
        end

        if total > 0 and value == total then
            row.value:SetTextColor(0.35, 1, 0.35, 1)
            row.label:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 1)
            row.stripe:SetColorTexture(0.35, 1, 0.35, 0.9)
        elseif total > 0 then
            row.value:SetTextColor(1, 0.78, 0.25, 1)
            row.label:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 0.9)
            row.stripe:SetColorTexture(1, 0.62, 0.20, 0.85)
        else
            row.value:SetTextColor(0.45, 0.45, 0.45, 1)
            row.label:SetTextColor(0.55, 0.55, 0.55, 1)
            row.stripe:SetColorTexture(0.25, 0.25, 0.25, 0.9)
            row.mine:SetText("--")
            row.mine:SetTextColor(0.45, 0.45, 0.45, 1)
            row.mineStatus = "You: no live scan"
            row.mineReady = false
        end
    end

    SetBuffRow("food", snapshot and snapshot.food or 0, snapshot and snapshot.missingFood or nil)
    SetBuffRow("flask", snapshot and snapshot.flask or 0, snapshot and snapshot.missingFlask or nil)
    SetBuffRow("rune", snapshot and snapshot.rune or 0, snapshot and snapshot.missingRune or nil)
    SetBuffRow("weapon", snapshot and snapshot.weapon or 0, snapshot and snapshot.missingWeapon or nil)

    for _, row in ipairs(box.synergyRows or {}) do
        row:Hide()
    end

    local missingSynergy = {}
    if snapshot and snapshot.missingSynergy then
        for _, buffName in ipairs(snapshot.missingSynergy) do
            missingSynergy[buffName] = true
        end
    end

    local okCoreRows, missingCoreRows = {}, {}
    local coreRules = RC.GetCoreBuffRules and RC:GetCoreBuffRules() or {}
    for _, rule in ipairs(coreRules) do
        local covered = snapshot and snapshot.total and snapshot.total > 0 and not missingSynergy[rule.name]
        local personalKnown, hasPersonalAura, auraName = false, nil, nil
        if RC.ScanPersonalCoreBuffStatus then
            hasPersonalAura, auraName = RC:ScanPersonalCoreBuffStatus("player", rule.name)
            personalKnown = hasPersonalAura ~= nil
        end
        local rowReady = covered and ((not personalKnown) or hasPersonalAura)
        local entry = {
            name = rule.name,
            ready = rowReady,
            raidReady = covered,
            raidStatus = covered and "Raid: covered" or "Raid: missing provider",
            personalReady = personalKnown and hasPersonalAura or covered,
            personalStatus = personalKnown and (hasPersonalAura and ("You: " .. (auraName or "ready")) or "You: missing aura") or "You: provider coverage only",
            providerText = rule.classes and ("Providers: " .. table.concat(rule.classes, ", ")) or nil,
        }
        table.insert(rowReady and okCoreRows or missingCoreRows, entry)
    end

    local displayRows = {}
    for _, entry in ipairs(okCoreRows) do table.insert(displayRows, entry) end
    for _, entry in ipairs(missingCoreRows) do table.insert(displayRows, entry) end

    for index, entry in ipairs(displayRows) do
        local row = box.synergyRows and box.synergyRows[index]
        if row then
            local rowReady = entry.ready

            row.buffLabel = entry.name
            row.raidReady = entry.raidReady
            row.raidStatus = entry.raidStatus
            row.personalReady = entry.personalReady
            row.personalStatus = entry.personalStatus
            row.providerText = entry.providerText

            -- Covered buffs read in normal text with a green dot; missing ones stay
            -- quiet (muted text, amber dot) so a small group is not a wall of red.
            row.label:SetText(entry.name)
            row.state:SetText(rowReady and "OK" or "MISS")
            if rowReady then
                row.label:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 1)
                row.stripe:SetColorTexture(0.35, 1, 0.35, 0.9)
            else
                row.label:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.85)
                row.stripe:SetColorTexture(1, 0.62, 0.20, 0.85)
            end
            row.state:Hide()
            row:Show()
        end
    end

    if box.synergyLabel then
        if #displayRows > 0 then
            box.synergyLabel:SetText(string.format("Core buffs  %d/%d", #okCoreRows, #displayRows))
        else
            box.synergyLabel:SetText("Core buffs")
        end
    end
end

function RaidSplit:CreateGuildImportPanel(parent)
    if self.GuildImportPanel then
        return self.GuildImportPanel
    end

    -- The guild list takes over the two right-hand columns while it is open.
    -- ApplyThemedLayout owns the final placement.
    local m = self:GetLayoutMetrics()

    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetWidth(math.max(GUILD_PANEL_W, m.sideWidth + m.gap + m.buffWidth))
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(1 + m.pad), -m.bodyTop)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(1 + m.pad), m.bodyBottom)
    panel:SetFrameLevel(parent:GetFrameLevel() + 12)
    panel:SetFrameStrata(parent:GetFrameStrata())
    panel:SetBackdrop(RC.Config.Backdrop)
    RC:ApplyThemedSection(panel)

    -- Solid base so the columns underneath never bleed through a translucent theme.
    local solidBg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    solidBg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -1, 1)
    solidBg:SetColorTexture(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, 1)

    panel:SetScript("OnShow", function()
        if self.BuffPanel then self.BuffPanel:Hide() end
        if self.SidePanel then self.SidePanel:Hide() end
    end)
    panel:SetScript("OnHide", function()
        if self.BuffPanel then self.BuffPanel:Show() end
        if self.SidePanel then self.SidePanel:Show() end
    end)

    local title = panel:CreateFontString(nil, "OVERLAY")
    RC:SetFont(title, 12, "OUTLINE")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -10)
    title:SetText("Guild Members")
    title:SetTextColor(1, 1, 1)

    local subtitle = panel:CreateFontString(nil, "OVERLAY")
    RC:SetFont(subtitle, 9, "OUTLINE")
    subtitle:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -26)
    subtitle:SetText("Drag members into raid groups")
    subtitle:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)

    local closeBtn = RC:CreateCloseButton(panel, 18)
    closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8)
    closeBtn:SetScript("OnClick", function()
        panel:Hide()
    end)

    local showAllBtn = MakeBtn(panel, 60, 18, "Show All")
    showAllBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30, -28)
    showAllBtn.labelText:SetTextColor(0.75, 0.9, 0.75)

    local hideAllBtn = MakeBtn(panel, 60, 18, "Hide All")
    hideAllBtn:SetPoint("RIGHT", showAllBtn, "LEFT", -4, 0)
    hideAllBtn.labelText:SetTextColor(0.9, 0.75, 0.75)

    local rankLabel = panel:CreateFontString(nil, "OVERLAY")
    RC:SetFont(rankLabel, 9, "OUTLINE")
    rankLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -50)
    rankLabel:SetText("Ranks")
    rankLabel:SetTextColor(RC.Config.Accent.r * 0.85, RC.Config.Accent.g * 0.85, RC.Config.Accent.b * 0.85)

    local rankArea = CreateFrame("Frame", nil, panel)
    rankArea:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -64)
    rankArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -64)
    rankArea:SetHeight(18)

    local listLabel = panel:CreateFontString(nil, "OVERLAY")
    RC:SetFont(listLabel, 9, "OUTLINE")
    listLabel:SetPoint("TOPLEFT", rankArea, "BOTTOMLEFT", 0, -8)
    listLabel:SetText("Available")
    listLabel:SetTextColor(RC.Config.Accent.r * 0.85, RC.Config.Accent.g * 0.85, RC.Config.Accent.b * 0.85)

    local countLabel = panel:CreateFontString(nil, "OVERLAY")
    RC:SetFont(countLabel, 9, "OUTLINE")
    countLabel:SetPoint("TOPRIGHT", rankArea, "BOTTOMRIGHT", 0, -8)
    countLabel:SetJustifyH("RIGHT")
    countLabel:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)
    countLabel:SetText("0")

    local scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", listLabel, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -10, 8)
    scroll:SetClipsChildren(true)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    content:SetSize(math.max(1, GUILD_PANEL_W - 50), 1)
    scroll:SetScrollChild(content)
    local scrollbar = RC:CreateScrollbar(scroll, scroll)

    scroll:SetScript("OnSizeChanged", function(_, width)
        content:SetWidth(math.max(1, (width or 1) - 4))
        if self.GuildImportPanel and self.GuildImportPanel:IsShown() then
            self:RefreshGuildImportPanel()
        end
    end)

    local emptyText = content:CreateFontString(nil, "OVERLAY")
    RC:SetFont(emptyText, 10, "OUTLINE")
    emptyText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2)
    emptyText:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -2)
    emptyText:SetJustifyH("LEFT")
    emptyText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)
    emptyText:SetText("Click Import Guild to load members.")
    emptyText:Show()

    panel.RankArea = rankArea
    panel.ListLabel = listLabel
    panel.CountLabel = countLabel
    panel.Scroll = scroll
    panel.Scrollbar = scrollbar
    panel.Content = content
    panel.EmptyText = emptyText
    panel.RankButtons = {}
    panel.Rows = {}

    function panel:RefreshTheme()
        RC:ApplyThemedSection(self)
        solidBg:SetColorTexture(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, 1)
        title:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
        subtitle:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
        rankLabel:SetTextColor(RC.Config.Accent.r * 0.85, RC.Config.Accent.g * 0.85, RC.Config.Accent.b * 0.85, 1)
        listLabel:SetTextColor(RC.Config.Accent.r * 0.85, RC.Config.Accent.g * 0.85, RC.Config.Accent.b * 0.85, 1)
        countLabel:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
        emptyText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
        if scrollbar and scrollbar.RefreshTheme then
            scrollbar:RefreshTheme()
        end
        if showAllBtn.RefreshTheme then showAllBtn:RefreshTheme() end
        if hideAllBtn.RefreshTheme then hideAllBtn:RefreshTheme() end
    end

    showAllBtn:SetScript("OnClick", function()
        for _, rank in ipairs(self.GuildImportRanks or {}) do
            self:SetGuildRankVisible(rank.index, true)
        end
        self:RefreshGuildImportPanel()
    end)

    hideAllBtn:SetScript("OnClick", function()
        for _, rank in ipairs(self.GuildImportRanks or {}) do
            self:SetGuildRankVisible(rank.index, false)
        end
        self:RefreshGuildImportPanel()
    end)

    panel:Hide()
    self.GuildImportPanel = panel
    panel:RefreshTheme()
    return panel
end

function RaidSplit:RefreshGuildImportPanel()
    local panel = self.GuildImportPanel
    if not panel then
        return
    end

    local ranks = self.GuildImportRanks or {}
    local members = self.GuildImportMembers or {}
    local assignedLookup = self:BuildAssignedDraftLookup()

    local rankColumns = 2
    local rankRowH = 16
    local rankButtonW = math.max(90, math.floor((panel:GetWidth() - 26) / rankColumns))
    local rankButtonIndex = 1

    for idx, rank in ipairs(ranks) do
        local btn = panel.RankButtons[idx]
        if not btn then
            btn = CreateFrame("Button", nil, panel.RankArea)
            btn:SetHeight(rankRowH)

            local box = CreateFrame("Frame", nil, btn, "BackdropTemplate")
            box:SetSize(11, 11)
            box:SetPoint("LEFT", btn, "LEFT", 0, 0)
            box:SetBackdrop(RC.Config.Backdrop)
            box:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, 1)
            box:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.12, RC.Config.InputBorder.a or 0))

            local fill = box:CreateTexture(nil, "ARTWORK")
            fill:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
            fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
            fill:SetColorTexture(RC.Config.CheckboxChecked.r, RC.Config.CheckboxChecked.g, RC.Config.CheckboxChecked.b, RC.Config.CheckboxChecked.a or 1)

            local label = btn:CreateFontString(nil, "OVERLAY")
            RC:SetFont(label, 9, "OUTLINE")
            label:SetPoint("LEFT", box, "RIGHT", 4, 0)
            label:SetPoint("RIGHT", btn, "RIGHT", 0, 0)
            label:SetJustifyH("LEFT")

            btn.box = box
            btn.fill = fill
            btn.label = label

            btn:SetScript("OnClick", function(b)
                self:SetGuildRankVisible(b.rankIndex, not self:IsGuildRankVisible(b.rankIndex))
                self:RefreshGuildImportPanel()
            end)
            btn:SetScript("OnEnter", function(b)
                b.box:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
            end)
            btn:SetScript("OnLeave", function(b)
                if self:IsGuildRankVisible(b.rankIndex) then
                    b.box:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
                else
                    b.box:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.12, RC.Config.InputBorder.a or 0))
                end
            end)

            panel.RankButtons[idx] = btn
        end

        local col = (idx - 1) % rankColumns
        local row = math.floor((idx - 1) / rankColumns)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", panel.RankArea, "TOPLEFT", col * rankButtonW, -(row * (rankRowH + 2)))
        btn:SetWidth(rankButtonW - 4)
        btn.rankIndex = rank.index
        btn.label:SetText(string.format("%s (%d)", rank.name or ("Rank " .. tostring((rank.index or 0) + 1)), rank.count or 0))

        local visible = self:IsGuildRankVisible(rank.index)
        btn.box:SetBackdropColor(RC.Config.CheckboxBg.r, RC.Config.CheckboxBg.g, RC.Config.CheckboxBg.b, RC.Config.CheckboxBg.a or 1)
        btn.fill:SetColorTexture(RC.Config.CheckboxChecked.r, RC.Config.CheckboxChecked.g, RC.Config.CheckboxChecked.b, RC.Config.CheckboxChecked.a or 1)
        btn.fill:SetShown(visible)
        if visible then
            btn.label:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
            btn.box:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
        else
            btn.label:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
            btn.box:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.12, RC.Config.InputBorder.a or 0))
        end

        btn:Show()
        rankButtonIndex = idx + 1
    end

    for idx = rankButtonIndex, #panel.RankButtons do
        panel.RankButtons[idx]:Hide()
    end

    local rankRows = math.max(1, math.ceil(#ranks / rankColumns))
    panel.RankArea:SetHeight(rankRows * (rankRowH + 2))

    local filteredMembers = {}
    for _, member in ipairs(members) do
        local isAssigned = ResolveRosterNameLookup(assignedLookup, member.name)
        if member.name and self:IsGuildRankVisible(member.rankIndex) and not isAssigned then
            table.insert(filteredMembers, member)
        end
    end

    panel.CountLabel:SetText(tostring(#filteredMembers))

    local rowIndex = 1
    local yOffset = 0
    local currentRank = nil
    local contentWidth = math.max(1, (panel.Scroll:GetWidth() or (GUILD_PANEL_W - 50)) - 4)
    panel.Content:SetWidth(contentWidth)

    local function AcquireRow()
        local row = panel.Rows[rowIndex]
        if not row then
            row = CreateFrame("Button", nil, panel.Content, "BackdropTemplate")
            row:SetBackdrop(RC.Config.Backdrop)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0.94)

            local stripe = row:CreateTexture(nil, "ARTWORK")
            stripe:SetWidth(3)
            stripe:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
            stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 1)

            local text = row:CreateFontString(nil, "OVERLAY")
            RC:SetFont(text, 10, "OUTLINE")
            text:SetPoint("LEFT", row, "LEFT", 7, 0)
            text:SetPoint("RIGHT", row, "RIGHT", -64, 0)
            text:SetJustifyH("LEFT")

            local meta = row:CreateFontString(nil, "OVERLAY")
            RC:SetFont(meta, 9, "OUTLINE")
            meta:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            meta:SetJustifyH("RIGHT")

            local headerText = row:CreateFontString(nil, "OVERLAY")
            RC:SetFont(headerText, 9, "OUTLINE")
            headerText:SetPoint("LEFT", row, "LEFT", 0, 0)
            headerText:SetJustifyH("LEFT")
            headerText:SetTextColor(RC.Config.Accent.r * 0.9, RC.Config.Accent.g * 0.9, RC.Config.Accent.b * 0.9)

            local headerLine = row:CreateTexture(nil, "ARTWORK")
            headerLine:SetHeight(1)
            headerLine:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            headerLine:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            SetRaidSplitLine(headerLine, 0.28)

            row.bg = bg
            row.stripe = stripe
            row.text = text
            row.meta = meta
            row.headerText = headerText
            row.headerLine = headerLine

            row:RegisterForDrag("LeftButton")
            row:SetScript("OnDragStart", function(r)
                if not r.member then return end
                self:StartDragFromData({
                    fromGuildRoster = true,
                    name = r.member.name,
                    class = r.member.class,
                    level = r.member.level,
                    role = r.member.role,
                    specName = r.member.specName,
                    specID = r.member.specID,
                }, r)
            end)
            row:SetScript("OnDragStop", function(r)
                self:StopDragging(r)
            end)
            row:SetScript("OnEnter", function(r)
                if not r.member then
                    return
                end

                r.bg:SetColorTexture(RC.Config.Accent.r * 0.12, RC.Config.Accent.g * 0.12, RC.Config.Accent.b * 0.12, 1)
                r:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.75)

                local c = RAID_CLASS_COLORS[r.member.class] or { r = 0.8, g = 0.8, b = 0.8 }
                local hex = string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
                GameTooltip:SetOwner(r, "ANCHOR_LEFT")
                GameTooltip:AddLine(string.format("|c%s%s|r", hex, r.member.name))
                GameTooltip:AddLine(r.member.rankName or "", 0.7, 0.7, 0.7)
                if not r.member.online then
                    GameTooltip:AddLine("Offline", 0.9, 0.5, 0.5)
                end
                if r.member.role then
                    GameTooltip:AddLine(r.member.role, 0.7, 0.7, 0.7)
                end
                if r.member.specName then
                    GameTooltip:AddLine(r.member.specName, 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(r)
                GameTooltip:Hide()
                if r.member then
                    r.bg:SetColorTexture(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0.94)
                    r:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.18, RC.Config.InputBorder.a or 0))
                end
            end)

            panel.Rows[rowIndex] = row
        end

        rowIndex = rowIndex + 1
        return row
    end

    for _, member in ipairs(filteredMembers) do
        if member.rankIndex ~= currentRank then
            currentRank = member.rankIndex
            local headerRow = AcquireRow()
            headerRow.member = nil
            headerRow:ClearAllPoints()
            headerRow:SetPoint("TOPLEFT", panel.Content, "TOPLEFT", 0, -yOffset)
            headerRow:SetPoint("TOPRIGHT", panel.Content, "TOPRIGHT", -2, -yOffset)
            headerRow:SetHeight(16)
            headerRow:SetBackdropColor(0, 0, 0, 0)
            headerRow:SetBackdropBorderColor(0, 0, 0, 0)
            headerRow.bg:Hide()
            headerRow.stripe:Hide()
            headerRow.text:Hide()
            headerRow.meta:Hide()
            headerRow.headerText:Show()
            headerRow.headerLine:Show()
            headerRow.headerText:SetText(member.rankName or ("Rank " .. tostring((member.rankIndex or 0) + 1)))
            headerRow:Show()
            yOffset = yOffset + 18
        end

        local row = AcquireRow()
        row.member = member
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.Content, "TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", panel.Content, "TOPRIGHT", -2, -yOffset)
        row:SetHeight(20)
        row:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, 0.82)
        row:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.18, RC.Config.InputBorder.a or 0))
        row.bg:Show()
        row.bg:SetColorTexture(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0.94)
        row.headerText:Hide()
        row.headerLine:Hide()
        row.stripe:Show()
        row.text:Show()
        row.meta:Show()

        local color = RAID_CLASS_COLORS[member.class] or { r = 0.75, g = 0.75, b = 0.75 }
        row.text:SetText(member.name)
        row.text:SetTextColor(color.r, color.g, color.b)
        row.stripe:SetColorTexture(color.r, color.g, color.b, 0.9)

        local metaText = member.rankName or ""
        if not member.online then
            metaText = metaText .. "  off"
            row.meta:SetTextColor(0.6, 0.45, 0.45)
        else
            row.meta:SetTextColor(0.6, 0.6, 0.6)
        end
        row.meta:SetText(metaText)
        row:Show()

        yOffset = yOffset + 22
    end

    for idx = rowIndex, #panel.Rows do
        panel.Rows[idx]:Hide()
        panel.Rows[idx].member = nil
    end

    panel.Content:SetHeight(math.max(1, yOffset + 4))
    if panel.Scrollbar then
        panel.Scrollbar:Update(panel.Content:GetHeight() or 1, panel.Scroll:GetHeight() or 1)
    end
    panel.EmptyText:SetShown(#filteredMembers == 0)
    if #filteredMembers == 0 then
        if #members == 0 then
            panel.EmptyText:SetText("Click Import Guild to load members.")
        else
            panel.EmptyText:SetText("No members visible.\nEnable more ranks or import guild roster.")
        end
    end
end


function RaidSplit:ShowSlotContextMenu(slot)
    if not slot.data then return end
    local name = slot.data.name
    local isLeader   = UnitIsGroupLeader("player")
    if not isLeader then return end

    -- Re-use or create a tiny popup frame
    if not self.ContextMenu then
        local cm = CreateFrame("Frame", "RC_RaidSplitContextMenu", UIParent)
        cm:SetFrameStrata("FULLSCREEN_DIALOG")
        cm:SetFrameLevel(300)
        RC:SkinFrame(cm)
        cm:SetBackdropColor(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, 0.97)
        cm:EnableMouse(true)
        cm.buttons = {}

        -- Auto-close on outside click (delay avoids immediate close from opener click)
        cm:SetScript("OnShow", function(s)
            s.closeDelay = 0.12
            s:SetScript("OnUpdate", function(self, elapsed)
                if self.closeDelay and self.closeDelay > 0 then
                    self.closeDelay = self.closeDelay - elapsed
                    return
                end
                if (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) and not self:IsMouseOver() then
                    self:Hide()
                end
            end)
        end)
        cm:SetScript("OnHide", function(s)
            s:SetScript("OnUpdate", nil)
            s.closeDelay = nil
        end)
        self.ContextMenu = cm
    end

    local cm = self.ContextMenu
    cm:Hide()

    -- Release old buttons
    for _, b in ipairs(cm.buttons) do b:Hide() end
    wipe(cm.buttons)

    local ITEM_H  = 22
    local PAD     = 4
    local ITEM_W  = 170

    local function AddItem(text, onClick, isDanger)
        local idx = #cm.buttons + 1
        local btn = CreateFrame("Button", nil, cm)
        btn:SetSize(ITEM_W, ITEM_H)
        btn:SetPoint("TOPLEFT", cm, "TOPLEFT", PAD, -(PAD + (idx - 1) * (ITEM_H + 2)))

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0)

        local lbl = btn:CreateFontString(nil, "OVERLAY")
        RC:SetFont(lbl, 11, "OUTLINE")
        lbl:SetPoint("LEFT", 8, 0)
        if isDanger then
            lbl:SetTextColor(RC.Config.DangerColor.r + 0.2, RC.Config.DangerColor.g + 0.1, RC.Config.DangerColor.b + 0.1)
        else
            lbl:SetTextColor(0.85, 0.85, 0.85)
        end
        lbl:SetText(text)

        btn:SetScript("OnEnter", function()
            bg:SetColorTexture(RC.Config.Accent.r * 0.10, RC.Config.Accent.g * 0.10, RC.Config.Accent.b * 0.10, 1)
            lbl:SetTextColor(1, 1, 1)
        end)
        btn:SetScript("OnLeave", function()
            bg:SetColorTexture(0, 0, 0, 0)
            if isDanger then
                lbl:SetTextColor(RC.Config.DangerColor.r + 0.2, RC.Config.DangerColor.g + 0.1, RC.Config.DangerColor.b + 0.1)
            else
                lbl:SetTextColor(0.85, 0.85, 0.85)
            end
        end)
        btn:SetScript("OnClick", function()
            cm:Hide()
            onClick()
        end)
        btn:Show()
        table.insert(cm.buttons, btn)
    end

    -- Add separator (visual only)
    local function AddSep()
        local idx = #cm.buttons + 1
        local sep = CreateFrame("Frame", nil, cm)
        sep:SetSize(ITEM_W, 1)
        sep:SetPoint("TOPLEFT", cm, "TOPLEFT", PAD, -(PAD + (idx - 1) * (ITEM_H + 2)))
        local t = sep:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        SetRaidSplitLine(t, 0.34)
        sep:Show()
        -- treat as half-height item for spacing
        table.insert(cm.buttons, sep)
    end

    -- Build items
    AddItem("Promote to Assistant", function()
        RC:PromoteGroupAssistant(name)
    end)
    AddSep()
    AddItem("Demote Assistant", function()
        RC:DemoteGroupAssistant(name)
    end, true)

    -- Size the menu to its content
    local numItems = #cm.buttons
    cm:SetSize(ITEM_W + PAD * 2, PAD * 2 + numItems * (ITEM_H + 2))

    -- Position near the slot, clamped to screen
    cm:ClearAllPoints()
    cm:SetPoint("TOPLEFT", slot, "TOPRIGHT", 4, 0)
    cm:Show()
    cm:Raise()
end

function RaidSplit:GetUnitDetails(unit)
    local function NormalizeRole(roleValue)
        if roleValue == "DAMAGER" then
            return "DPS"
        end
        if roleValue == "NONE" or roleValue == "" then
            return nil
        end
        return roleValue
    end

    local role = NormalizeRole(UnitGroupRolesAssigned(unit))
    if not role and IsInRaid() and UnitInRaid and GetRaidRosterInfo then
        local raidIndex = UnitInRaid(unit)
        if raidIndex then
            local _, _, _, _, _, _, _, _, _, raidRole = GetRaidRosterInfo(raidIndex)
            role = NormalizeRole(raidRole)
        end
    end

    -- Spec
    local specName = nil
    local specID = nil
    local guid = UnitGUID(unit)
    if UnitIsUnit(unit, "player") then
        specID, specName = RC:GetPlayerSpecializationInfo()
        if guid and specID then
            self:CacheSpecByGUID(guid, specID, specName)
        end
    else
        if guid then
            specID, specName = self:GetCachedSpecByGUID(guid)
        end

        if (not specID or specID <= 0) and GetInspectSpecialization then
            local inspectedSpecID = GetInspectSpecialization(unit)
            if inspectedSpecID and inspectedSpecID > 0 then
                specID = inspectedSpecID
                if GetSpecializationInfoByID then
                    specName = select(2, GetSpecializationInfoByID(specID))
                end
                if guid then
                    self:CacheSpecByGUID(guid, specID, specName)
                end
            else
                local _, class = UnitClass(unit)
                if class and HybridSpecClasses[class] then
                    self:QueueInspectUnit(unit)
                end
            end
        end
        if specID and specID > 0 and (not specName or specName == "") and GetSpecializationInfoByID then
            specName = select(2, GetSpecializationInfoByID(specID))
        end
    end

    -- Prefer explicit role assignment, but promote tank/healer when spec clearly indicates it.
    local specRole = specID and NormalizeRole(GetSpecializationRoleByID(specID)) or nil
    if specRole == "TANK" or specRole == "HEALER" then
        role = specRole
    elseif not role then
        role = specRole
    end

    -- Raid role assignment fallback when role data is missing.
    if not role and GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then
        role = "TANK"
    end

    if not role then
        role = "DPS"
    end

    return role, specName, specID
end

function RaidSplit:ImportGuildRoster(fromRosterEvent)
    if not IsInGuild() then
        self:Print("You must be in a guild to import guild members.")
        return
    end

    if self.Frame then
        if not self.GuildImportPanel then
            self:CreateGuildImportPanel(self.Frame)
        end
        self.GuildImportPanel:Show()
    end

    local shouldAnnounce = (not fromRosterEvent) or self.pendingGuildImport

    local guildCount = GetNumGuildMembers() or 0
    if guildCount == 0 and not fromRosterEvent then
        self.pendingGuildImport = true
        if C_GuildInfo_GuildRoster then
            C_GuildInfo_GuildRoster()
        end
        self:Print("Requesting guild roster...")
        return
    elseif guildCount == 0 then
        -- Wait for the next roster update while the pending import flag is set.
        return
    end

    self.pendingGuildImport = nil

    local members = {}
    local rankCounts = {}
    local rankNames = {}
    local seen = {}
    local playerName = UnitName("player")

    for i = 1, guildCount do
        local name, rankName, rankIndex, level, _, _, _, _, online, _, class, _, _, isMobile = GetGuildRosterInfo(i)
        if name and name ~= "" and not isMobile then
            local normalized = NormalizeRosterName(name) or name
            local key = string.lower(normalized)
            if not seen[key] then
                seen[key] = true

                local role = "DPS"
                local specName, specID
                if NamesMatch(normalized, playerName) then
                    role, specName, specID = self:GetUnitDetails("player")
                end

                rankIndex = rankIndex or 99
                rankName = (rankName and rankName ~= "" and rankName) or ("Rank " .. tostring(rankIndex + 1))

                local entry = {
                    name = normalized,
                    key = key,
                    class = class,
                    level = level or 0,
                    role = role,
                    specName = specName,
                    specID = specID,
                    rankIndex = rankIndex,
                    rankName = rankName,
                    online = online and true or false,
                }

                table.insert(members, entry)
                rankCounts[rankIndex] = (rankCounts[rankIndex] or 0) + 1
                rankNames[rankIndex] = rankName
            end
        end
    end

    if #members == 0 then
        self:Print("No guild members available to import.")
        return
    end

    table.sort(members, function(a, b)
        if a.rankIndex == b.rankIndex then
            return a.name < b.name
        end
        return a.rankIndex < b.rankIndex
    end)

    local rankList = {}
    for rankIdx, count in pairs(rankCounts) do
        table.insert(rankList, {
            index = rankIdx,
            name = rankNames[rankIdx] or ("Rank " .. tostring(rankIdx + 1)),
            count = count,
        })
    end
    table.sort(rankList, function(a, b) return a.index < b.index end)

    self.GuildImportMembers = members
    self.GuildImportRanks = rankList

    local visibilityMap = self:GetGuildRankVisibilityMap()
    for _, rank in ipairs(rankList) do
        local key = RankKey(rank.index)
        if visibilityMap[key] == nil then
            visibilityMap[key] = true
        end
    end

    if not self.GuildImportPanel then
        self:CreateGuildImportPanel(self.Frame)
    end
    self.GuildImportPanel:Show()
    self:RefreshGuildImportPanel()

    local visibleRanks = 0
    for _, rank in ipairs(rankList) do
        if self:IsGuildRankVisible(rank.index) then
            visibleRanks = visibleRanks + 1
        end
    end
    if shouldAnnounce then
        self:Print(string.format("Loaded %d guild members across %d ranks (%d rank filters enabled).", #members, #rankList, visibleRanks))
    end
end

function RaidSplit:SyncRoster()
    self.DraftRoster = {}

    if not IsInRaid() then
        -- Mock for testing if not in raid/group
        if not IsInGroup() then
            local pName = UnitName("player")
            local _, pClass = UnitClass("player")
            local pLevel = UnitLevel("player")
            local role, specName, specID = self:GetUnitDetails("player")
            table.insert(self.DraftRoster,
                { name = pName, group = 1, class = pClass, level = pLevel, role = role, specName = specName, specID = specID })
        else
            -- Party loop
            local members = GetNumGroupMembers()
            if members > 0 then
                -- Include player
                local pName = UnitName("player")
                local _, pClass = UnitClass("player")
                local pLevel = UnitLevel("player")
                local pRole, pSpecName, pSpecID = self:GetUnitDetails("player")
                table.insert(self.DraftRoster,
                    { name = pName, group = 1, class = pClass, level = pLevel, role = pRole, specName = pSpecName, specID = pSpecID })

                for i = 1, members do -- Iterate party members
                    local unit = "party" .. i
                    if UnitExists(unit) then
                        local name = UnitName(unit)
                        local _, class = UnitClass(unit)
                        local level = UnitLevel(unit)
                        local role, specName, specID = self:GetUnitDetails(unit)
                        table.insert(self.DraftRoster,
                            { name = name, group = 1, class = class, level = level, role = role, specName = specName, specID = specID })
                    end
                end
            end
        end
    else
        for i = 1, 40 do
            -- Name, Rank, Subgroup, Level, Class (Loc), Class (File), Zone, Online, Dead, Role, ML
            local name, _, subgroup, level, _, class = GetRaidRosterInfo(i)
            local unit = "raid" .. i
            if name then
                local unitRole, specName, specID = self:GetUnitDetails(unit)
                table.insert(self.DraftRoster,
                    { name = name, group = subgroup, class = class, level = level, role = unitRole, specName = specName, specID = specID })
            end
        end
    end
    self:NormalizeDraftRoster()
    self:RefreshGrid()
end

function RaidSplit:NormalizeDraftRoster()
    self.DraftRoster = self.DraftRoster or {}

    local normalizedRoster = {}
    local seen = {}

    for _, unit in ipairs(self.DraftRoster) do
        if unit and unit.name and unit.name ~= "" then
            local key = GetRosterNameKey(unit.name)
            if not seen[key] then
                unit.group = ClampGroupIndex(unit.group)
                unit.level = unit.level or 0
                table.insert(normalizedRoster, unit)
                seen[key] = true
            end
        end

        if #normalizedRoster >= 40 then
            break
        end
    end

    self.DraftRoster = normalizedRoster
    return normalizedRoster
end

function RaidSplit:GetDraftGroupCounts()
    local counts = {0,0,0,0,0,0,0,0}
    for _, unit in ipairs(self.DraftRoster or {}) do
        local group = ClampGroupIndex(unit.group)
        unit.group = group
        if group >= 1 and group <= 8 then
            counts[group] = counts[group] + 1
        end
    end
    return counts
end

function RaidSplit:ValidateDraftLayout()
    self:NormalizeDraftRoster()

    local counts = self:GetDraftGroupCounts()
    local overflow = {}
    local unassigned = {}
    for group = 1, 8 do
        if counts[group] > 5 then
            table.insert(overflow, string.format("G%d has %d/5", group, counts[group]))
        end
    end

    for _, unit in ipairs(self.DraftRoster) do
        if not unit.group or unit.group < 1 or unit.group > 8 then
            table.insert(unassigned, unit.name or "unknown")
        end
    end

    if #overflow > 0 then
        return false, "Raid Split has overfilled groups: " .. table.concat(overflow, ", ")
    end

    if #unassigned > 0 then
        return false, "Raid Split has unassigned players: " .. table.concat(unassigned, ", ")
    end

    if IsInRaid() then
        local raidNames = NewRosterNameLookup()
        for i = 1, 40 do
            local name = GetRaidRosterInfo(i)
            if name then
                AddRosterNameLookup(raidNames, name, true)
            end
        end

        local missing = {}
        local ambiguous = {}
        for _, unit in ipairs(self.DraftRoster) do
            local found, matchType = ResolveRosterNameLookup(raidNames, unit.name)
            if matchType == "ambiguous" then
                table.insert(ambiguous, unit.name)
            elseif not found then
                table.insert(missing, unit.name)
            end
        end

        if #ambiguous > 0 then
            return false, "Raid Split has ambiguous cross-realm names: " .. table.concat(ambiguous, ", ")
        end

        if #missing > 0 then
            return false, "Raid Split roster is stale. Missing from raid: " .. table.concat(missing, ", ")
        end

        local draftNames = NewRosterNameLookup()
        for _, unit in ipairs(self.DraftRoster) do
            if unit and unit.name then
                AddRosterNameLookup(draftNames, unit.name, true)
            end
        end

        local missingFromDraft = {}
        local ambiguousFromDraft = {}
        for i = 1, 40 do
            local name = GetRaidRosterInfo(i)
            if name then
                local found, matchType = ResolveRosterNameLookup(draftNames, name)
                if matchType == "ambiguous" then
                    table.insert(ambiguousFromDraft, name)
                elseif not found then
                    table.insert(missingFromDraft, name)
                end
            end
        end

        if #ambiguousFromDraft > 0 then
            return false, "Raid Split draft has ambiguous cross-realm names: " .. table.concat(ambiguousFromDraft, ", ")
        end

        if #missingFromDraft > 0 then
            return false, "Raid Split roster is stale. Missing from draft: " .. table.concat(missingFromDraft, ", ")
        end
    end

    return true
end

function RaidSplit:BuildApplyConfidenceSummary()
    local valid, reason = self:ValidateDraftLayout()
    if not valid then
        return reason or "Raid Split layout is not valid.", false
    end

    local counts = self:GetDraftGroupCounts()
    local teamStats = {}
    local tankGroups = {}
    local healerGroups = {}
    local groupLines = {}

    for group = 1, 8 do
        local teamIndex = self.SplitGroupToTeam and self.SplitGroupToTeam[group] or nil
        if teamIndex then
            teamStats[teamIndex] = teamStats[teamIndex] or { players = 0, tanks = 0, healers = 0, dps = 0, groups = {} }
            table.insert(teamStats[teamIndex].groups, "G" .. group)
        end
        if counts[group] > 0 then
            table.insert(groupLines, string.format("G%d %d/5", group, counts[group]))
        end
    end

    for _, unit in ipairs(self.DraftRoster or {}) do
        local group = ClampGroupIndex(unit.group)
        local role = unit.role or "DAMAGER"
        local teamIndex = self.SplitGroupToTeam and self.SplitGroupToTeam[group] or nil
        if teamIndex then
            local stats = teamStats[teamIndex]
            stats.players = stats.players + 1
            if role == "TANK" then
                stats.tanks = stats.tanks + 1
            elseif role == "HEALER" then
                stats.healers = stats.healers + 1
            else
                stats.dps = stats.dps + 1
            end
        end
        if role == "TANK" then
            table.insert(tankGroups, string.format("%s G%d", unit.name or "Tank", group))
        elseif role == "HEALER" then
            table.insert(healerGroups, string.format("G%d", group))
        end
    end

    local lines = {
        "Apply raid split layout?",
        "",
        "Groups: " .. (#groupLines > 0 and table.concat(groupLines, ", ") or "empty"),
    }

    local teamIndexes = {}
    for teamIndex in pairs(teamStats) do
        table.insert(teamIndexes, teamIndex)
    end
    table.sort(teamIndexes)
    if #teamIndexes > 0 then
        table.insert(lines, "")
        table.insert(lines, "Split teams:")
        for _, teamIndex in ipairs(teamIndexes) do
            local s = teamStats[teamIndex]
            table.insert(lines, string.format(
                "T%d %s: %dp (%dT/%dH/%dD)",
                teamIndex,
                table.concat(s.groups, "+"),
                s.players,
                s.tanks,
                s.healers,
                s.dps
            ))
        end
    end

    if #tankGroups > 0 then
        table.insert(lines, "")
        table.insert(lines, "Tanks: " .. table.concat(tankGroups, ", "))
    end
    if #healerGroups > 0 then
        table.insert(lines, "Healer groups: " .. table.concat(healerGroups, ", "))
    end

    return table.concat(lines, "\n"), true
end

function RaidSplit:ShowApplyConfirmation()
    local summary, canApply = self:BuildApplyConfidenceSummary()
    if not canApply then
        self:Print(summary)
        return false
    end

    StaticPopupDialogs["RC_CONFIRM_RAID_SPLIT"] = {
        text = summary,
        button1 = "Apply",
        button2 = "Cancel",
        OnAccept = function() self:ApplyChanges() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("RC_CONFIRM_RAID_SPLIT")
    return true
end

function RaidSplit:HandleDrop(sourceUnit, targetGroup, targetUnit)
    -- sourceUnit: { name, class, group }
    -- targetGroup: number (1-8)
    -- targetUnit: { name, class, group } (nil if empty slot)

    sourceUnit = self:ResolveDragSourceUnit(sourceUnit)
    if not sourceUnit then
        return
    end

    -- Logic:
    -- 1. If targetUnit exists, swap groups.
    --    source.group <-> target.group
    --    Wait, targetGroup is the group we dropped ONTO.
    --    So source.group becomes targetGroup.
    --    TargetUnit's group becomes source's OLD group.
    -- 2. If targetUnit is nil (empty slot), just move source to targetGroup.

    targetGroup = ClampGroupIndex(targetGroup)
    if targetGroup < 1 or targetGroup > 8 then
        return
    end

    local oldGroup = ClampGroupIndex(sourceUnit.group)

    if targetUnit then
        -- SWAP
        sourceUnit.group = targetGroup
        targetUnit.group = oldGroup
    else
        -- MOVE
        sourceUnit.group = targetGroup
    end

    self:RefreshGrid()
end

function RaidSplit:SetSplitTeamMap(teamWoWGroupMap)
    self.SplitTeamMap = teamWoWGroupMap
    self.SplitGroupToTeam = {}

    for teamIndex, groups in ipairs(teamWoWGroupMap or {}) do
        for _, groupIndex in ipairs(groups or {}) do
            if groupIndex and groupIndex >= 1 and groupIndex <= 8 then
                self.SplitGroupToTeam[groupIndex] = teamIndex
            end
        end
    end
end

function RaidSplit:ClearSplitTeamMap()
    self.SplitTeamMap = nil
    self.SplitGroupToTeam = nil
end

function RaidSplit:RefreshGrid()
    self:NormalizeDraftRoster()
    local groupCounts = { 0, 0, 0, 0, 0, 0, 0, 0 }
    local docked = self.Frame and self.Frame.rcWorkspaceShellPage

    -- ── Reset all slots to empty state ────────────────────────────────────────
    for i = 1, 8 do
        local gf = self.Groups[i]
        if docked then
            gf:SetBackdropColor(
                RC.Config.SectionBg.r,
                RC.Config.SectionBg.g,
                RC.Config.SectionBg.b,
                0.18
            )
        end
        if gf.countLabel then gf.countLabel:SetText("0/5") end
        local teamIndex = self.SplitGroupToTeam and self.SplitGroupToTeam[i]
        if teamIndex then
            local color = GetSplitTeamColor(teamIndex)
            gf:SetBackdropBorderColor(color.r * 0.55, color.g * 0.55, color.b * 0.55, docked and 0.28 or 0.46)
            if gf.stripe then
                gf.stripe:SetColorTexture(color.r, color.g, color.b, 0.92)
            end
            if gf.headerBg then
                gf.headerBg:SetColorTexture(color.r * 0.16, color.g * 0.16, color.b * 0.16, docked and 0.62 or 1)
            end
            if gf.teamTint then
                gf.teamTint:SetColorTexture(color.r, color.g, color.b, 0.055)
                gf.teamTint:Show()
            end
            if gf.teamBadge then
                gf.teamBadge:SetText("T" .. teamIndex)
                gf.teamBadge:SetTextColor(color.r, color.g, color.b, 1)
                gf.teamBadge:Show()
            end
        else
            SetRaidSplitSoftBorder(gf, docked and 0.16 or 0.32, docked)
            if gf.stripe then
                gf.stripe:SetColorTexture(0, 0, 0, 0)
            end
            if gf.headerBg then
                gf.headerBg:SetColorTexture(
                    RC.Config.HeaderBg.r,
                    RC.Config.HeaderBg.g,
                    RC.Config.HeaderBg.b,
                    docked and 0.48 or 0.94
                )
            end
            if gf.teamTint then
                gf.teamTint:Hide()
            end
            if gf.teamBadge then
                gf.teamBadge:SetText("")
                gf.teamBadge:Hide()
            end
        end
        for _, slot in ipairs(gf.Slots) do
            slot.data = nil
            slot.text:SetText("")
            slot.text:SetTextColor(0.30, 0.30, 0.30)
            slot.stripe:SetColorTexture(0, 0, 0, 0)
            local emptyAlpha = docked and 0.32 or 0.88
            slot:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, emptyAlpha)
            slot:SetBackdropBorderColor(
                RC.Config.InputBorder.r,
                RC.Config.InputBorder.g,
                RC.Config.InputBorder.b,
                docked and 0.08 or math.max(0.16, RC.Config.InputBorder.a or 0)
            )
            if slot.roleIcon then slot.roleIcon:Hide() end
            if slot.dpsText  then slot.dpsText:SetText("") end
        end
    end

    local function FormatDPS(dps)
        if not dps or dps == 0 then return "" end
        if dps >= 1000000 then return string.format("%.1fM", dps/1000000)
        elseif dps >= 1000 then return string.format("%.1fk", dps/1000)
        else return string.format("%.0f", dps) end
    end

    local unassigned = {}

    -- ── Fill occupied slots ───────────────────────────────────────────────────
    for _, unit in ipairs(self.DraftRoster) do
        local g = unit.group
        if g and g >= 1 and g <= 8 then
            groupCounts[g] = groupCounts[g] + 1
            if groupCounts[g] <= 5 then
                local slot = self.Groups[g].Slots[groupCounts[g]]
                local color = RAID_CLASS_COLORS[unit.class] or {r=0.7,g=0.7,b=0.7}

                slot.data = unit
                slot.text:SetText(unit.name)
                slot.text:SetTextColor(color.r, color.g, color.b)

                -- Left class-color stripe
                slot.stripe:SetColorTexture(color.r, color.g, color.b, 0.90)

                -- Subtle class-tinted bg
                slot:SetBackdropColor(color.r*0.10, color.g*0.10, color.b*0.10, docked and 0.66 or 1)
                SetRaidSplitSoftBorder(slot, docked and 0.14 or 0.28, docked)

                -- Role icon (TANK/HEALER/DPS via RoleIcons atlas)
                if slot.roleIcon and unit.role then
                    local roleKey = unit.role == "TANK" and "TANK" or (unit.role == "HEALER" and "HEALER" or "DPS")
                    if RC.RoleIcons and RC.RoleIcons[roleKey] then
                        slot.roleIcon:SetTexture(RC.RoleIcons.Texture)
                        slot.roleIcon:SetTexCoord(unpack(RC.RoleIcons[roleKey]))
                        slot.roleIcon:Show()
                    end
                end

                -- DPS score (if Details! balancing enabled)
                if RC.db.profile.smartSplitBalanceDPS and unit.dpsScore and unit.dpsScore > 0 then
                    slot.dpsText:SetText(FormatDPS(unit.dpsScore))
                    slot.dpsText:SetTextColor(1, 1, 0.5, 0.85)
                elseif slot.dpsText then
                    slot.dpsText:SetText("")
                end
            end
        elseif g == 0 then
            table.insert(unassigned, unit)
        end
    end

    -- ── Update group count labels ─────────────────────────────────────────────
    for i = 1, 8 do
        local gf = self.Groups[i]
        if gf.countLabel then
            gf.countLabel:SetText(groupCounts[i] .. "/5")
            if groupCounts[i] > 5 then
                gf.countLabel:SetTextColor(1, 0.4, 0.4)
            elseif groupCounts[i] == 5 then
                gf.countLabel:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b)
            else
                gf.countLabel:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)
            end
        end
    end

    -- ── Overflow: unassigned players spill into G1 slots with red stripe ──────
    local g1Start = groupCounts[1]
    for idx, unit in ipairs(unassigned) do
        local slotIdx = g1Start + idx
        if slotIdx <= 5 then
            local slot = self.Groups[1].Slots[slotIdx]
            slot.data = unit
            slot.text:SetText(unit.name .. "  *")
            slot.text:SetTextColor(1, 0.40, 0.40)
            slot.stripe:SetColorTexture(1, 0.20, 0.20, 0.85)
            slot:SetBackdropColor(0.18, 0.05, 0.05, 1)
            slot:SetBackdropBorderColor(0.6, 0.1, 0.1, 1)
        end
    end

    if self.GuildImportPanel and self.GuildImportPanel:IsShown() then
        self:RefreshGuildImportPanel()
    end
end

function RaidSplit:ScheduleNextMove(delay, generation)
    generation = generation or self.processGeneration
    if not self.isProcessing or generation ~= self.processGeneration then
        return
    end

    CancelTimer(self.processTimer)
    self.processTimer = nil

    local function Continue()
        if not self.isProcessing or generation ~= self.processGeneration then
            return
        end
        self.processTimer = nil
        self:ProcessNextMove(false, generation)
    end

    if C_Timer and C_Timer.NewTimer then
        self.processTimer = C_Timer.NewTimer(delay or 0, Continue)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, Continue)
    else
        Continue()
    end
end

function RaidSplit:ScheduleRosterSync(delay)
    CancelTimer(self.syncTimer)
    self.syncTimer = nil
    local generation = self.processGeneration

    local function SyncIfIdle()
        self.syncTimer = nil
        if not self.isProcessing and generation == self.processGeneration then
            self:SyncRoster()
        end
    end

    if C_Timer and C_Timer.NewTimer then
        self.syncTimer = C_Timer.NewTimer(delay or 0, SyncIfIdle)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, SyncIfIdle)
    else
        SyncIfIdle()
    end
end

function RaidSplit:FinishApplyProcess(message)
    CancelTimer(self.processTimer)
    self.processTimer = nil
    self.isProcessing = false
    self.processGeneration = (self.processGeneration or 0) + 1
    if message and message ~= "" then
        self:Print(message)
    end
    self:ScheduleRosterSync(0.5)
end

function RaidSplit:ApplyChanges()
    if not IsInRaid() then
        self:Print("Not in a raid, cannot apply changes.")
        return
    end

    if UnitAffectingCombat("player") or (InCombatLockdown and InCombatLockdown()) then
        self:Print("Raid groups cannot be rearranged during combat.")
        return
    end

    if not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
        self:Print("Raid Split requires raid leader or assistant permissions.")
        return
    end

    local valid, reason = self:ValidateDraftLayout()
    if not valid then
        self:Print(reason)
        self:SyncRoster()
        return
    end

    -- Build target mappings
    self.targetSlots = {}
    local groupSizes = {0,0,0,0,0,0,0,0}
    for _, unit in ipairs(self.DraftRoster) do
        if unit.group >= 1 and unit.group <= 8 then
            groupSizes[unit.group] = groupSizes[unit.group] + 1
            if groupSizes[unit.group] <= 5 then
                local slotId = (unit.group - 1) * 5 + groupSizes[unit.group]
                self.targetSlots[slotId] = unit
                unit.processed = false
                unit.moveAttempts = 0
            else
                unit.processed = true -- Overflow
            end
        else
            unit.processed = true
        end
    end

    CancelTimer(self.processTimer)
    CancelTimer(self.syncTimer)
    self.processTimer = nil
    self.syncTimer = nil
    self.processGeneration = (self.processGeneration or 0) + 1
    local generation = self.processGeneration
    self.isProcessing = true
    self.processStart = GetTime()
    self.appliedCount = 0
    self.skippedCount = 0
    self:Print("Applying raid split layout...")

    self:ProcessNextMove(true, generation)
end

function RaidSplit:ProcessNextMove(_, generation)
    generation = generation or self.processGeneration
    if not self.isProcessing or generation ~= self.processGeneration then
        return
    end
    self.processTimer = nil

    -- A full 40-player reshuffle normally completes well below this.
    if GetTime() - (self.processStart or 0) > 20 then
        self:FinishApplyProcess("Raid split timed out before every move was confirmed; the live roster was refreshed.")
        return
    end

    if UnitAffectingCombat("player") or (InCombatLockdown and InCombatLockdown()) then
        self:FinishApplyProcess("Combat started. Halting raid split.")
        return
    end

    local groupCurSizes = {0,0,0,0,0,0,0,0}
    local playerToIndex = NewRosterNameLookup()
    local indexlink = {}
    local targetGroupByName = NewRosterNameLookup()

    for _, target in pairs(self.targetSlots or {}) do
        if target and target.name and target.group then
            AddRosterNameLookup(targetGroupByName, target.name, target.group)
        end
    end

    for i = 1, 40 do
        local name, rank, subgroup = GetRaidRosterInfo(i)
        if name and subgroup and groupCurSizes[subgroup] then
            groupCurSizes[subgroup] = groupCurSizes[subgroup] + 1
            AddRosterNameLookup(playerToIndex, name, i)
            indexlink[i] = { subgroup = subgroup, rank = rank or 0, name = name }
        end
    end

    local allProcessed = true
    for slotId = 1, 40 do
        local targetUnit = self.targetSlots[slotId]
        if targetUnit and not targetUnit.processed then
            local targetName = targetUnit.name
            local currentIndex = ResolveRosterIndex(playerToIndex, targetName)
            local current = currentIndex and indexlink[currentIndex]

            if current and current.subgroup == targetUnit.group then
                targetUnit.processed = true
            elseif current then
                allProcessed = false

                if (targetUnit.moveAttempts or 0) >= 3 then
                    targetUnit.processed = true
                    self.skippedCount = (self.skippedCount or 0) + 1
                    self:Print("Skipped " .. targetName .. ": the roster did not confirm the move after 3 attempts.")
                else
                    targetUnit.moveAttempts = (targetUnit.moveAttempts or 0) + 1
                    local actionIssued = false
                    local failureReason = "the game rejected the subgroup move"

                    if groupCurSizes[targetUnit.group] < 5 then
                        actionIssued = SetRaidSubgroup and pcall(SetRaidSubgroup, currentIndex, targetUnit.group)
                    else
                        local swapTargetIndex
                        for i = 1, 40 do
                            local name, rank, subgroup = GetRaidRosterInfo(i)
                            if name and subgroup == targetUnit.group and (rank or 0) < 2 then
                                local intendedGroup = ResolveRosterNameLookup(targetGroupByName, name)
                                if intendedGroup ~= subgroup then
                                    swapTargetIndex = i
                                    break
                                end
                            end
                        end

                        if not swapTargetIndex then
                            for i = 1, 40 do
                                local name, rank, subgroup = GetRaidRosterInfo(i)
                                if name
                                    and subgroup == targetUnit.group
                                    and not NamesMatch(name, targetName)
                                    and (rank or 0) < 2 then
                                    swapTargetIndex = i
                                    break
                                end
                            end
                        end

                        if swapTargetIndex then
                            actionIssued = SwapRaidSubgroup and pcall(SwapRaidSubgroup, swapTargetIndex, currentIndex)
                            failureReason = "the game rejected the subgroup swap"
                        else
                            failureReason = "target group is full and no safe swap was available"
                        end
                    end

                    if actionIssued then
                        self.appliedCount = (self.appliedCount or 0) + 1
                        self:ScheduleNextMove(0.40, generation)
                        return
                    end

                    targetUnit.processed = true
                    self.skippedCount = (self.skippedCount or 0) + 1
                    self:Print("Skipped " .. targetName .. ": " .. failureReason .. ".")
                end
            else
                allProcessed = false
                targetUnit.processed = true
                self.skippedCount = (self.skippedCount or 0) + 1
                self:Print("Skipped " .. (targetName or "unknown") .. ": player is no longer in the raid.")
            end
        end
    end

    if allProcessed then
        if (self.skippedCount or 0) > 0 then
            self:FinishApplyProcess(string.format(
                "Finished applying layout (%d moves, %d skipped).",
                self.appliedCount or 0,
                self.skippedCount or 0
            ))
        else
            self:FinishApplyProcess(string.format("Applied layout successfully (%d moves).", self.appliedCount or 0))
        end
    else
        self:ScheduleNextMove(0.05, generation)
    end
end

function RaidSplit:SmartSplit(numGroups)
    numGroups = tonumber(numGroups) or 2
    numGroups = math.floor(numGroups + 0.5)
    if numGroups < 1 then numGroups = 1 end
    if numGroups > 8 then numGroups = 8 end
    if not self.DraftRoster or #self.DraftRoster == 0 then
        self:SyncRoster()
    end

    -- Reset all groups to 0 first (unassigned)
    for _, unit in ipairs(self.DraftRoster) do
        unit.group = 0
    end

    -- Get player name for "Keep me in G1" feature
    local playerName = UnitName("player")

    -- Build list of players to distribute (excluding player if keepSelfG1 is enabled)
    local playersToDistribute = {}
    local playerUnit = nil

    for _, unit in ipairs(self.DraftRoster) do
        if RC.db.profile.smartSplitKeepSelfG1 and NamesMatch(unit.name, playerName) then
            playerUnit = unit
        else
            table.insert(playersToDistribute, unit)
        end
    end

    local totalPlayers = #playersToDistribute + (playerUnit and 1 or 0)
    if totalPlayers == 0 then
        self:RefreshGrid()
        return
    end

    local requestedTeams = numGroups
    local logicalTeams = requestedTeams

    local function RequiredWoWGroups(teamCount)
        local base = math.floor(totalPlayers / teamCount)
        local remainder = totalPlayers % teamCount
        local required = 0
        for team = 1, teamCount do
            local target = base + (team <= remainder and 1 or 0)
            required = required + math.max(1, math.ceil(target / 5))
        end
        return required
    end

    if RequiredWoWGroups(logicalTeams) > 8 then
        local bestTeams
        local bestDistance = math.huge
        for candidate = 1, 8 do
            if RequiredWoWGroups(candidate) <= 8 then
                local distance = math.abs(candidate - requestedTeams)
                if distance < bestDistance or (distance == bestDistance and candidate < bestTeams) then
                    bestTeams = candidate
                    bestDistance = distance
                end
            end
        end
        logicalTeams = bestTeams or 1
        self:Print(string.format(
            "%d teams cannot fit this %d-player roster into 8 raid groups; using %d teams.",
            requestedTeams,
            totalPlayers,
            logicalTeams
        ))
    end
    self.ResolvedLogicalTeams = logicalTeams

    local basePerTeam = math.floor(totalPlayers / logicalTeams)
    local extra = totalPlayers % logicalTeams

    local teamTargetSizes = {}
    for i = 1, logicalTeams do
        teamTargetSizes[i] = basePerTeam + (i <= extra and 1 or 0)
    end

    -- Map logical teams to WoW groups
    local teamWoWGroupMap = {}
    local nextWoWGroup = 1
    local usedWoWGroups = {}

    local function AddMappedWoWGroup(teamIndex, woWGroupIndex)
        if not teamWoWGroupMap[teamIndex] then
            teamWoWGroupMap[teamIndex] = {}
        end
        if not woWGroupIndex or woWGroupIndex < 1 or woWGroupIndex > 8 then
            return false
        end
        if usedWoWGroups[woWGroupIndex] then
            return false
        end
        table.insert(teamWoWGroupMap[teamIndex], woWGroupIndex)
        usedWoWGroups[woWGroupIndex] = true
        if woWGroupIndex >= nextWoWGroup then
            nextWoWGroup = woWGroupIndex + 1
        end
        return true
    end

    for i = 1, logicalTeams do
        teamWoWGroupMap[i] = {}
    end

    if logicalTeams == 2 and RC.db.profile.smartSplitTwoWayOddEven then
        -- Team 1 -> odd groups, Team 2 -> even groups.
        local oddGroups = { 1, 3, 5, 7 }
        local evenGroups = { 2, 4, 6, 8 }
        local team1Needed = math.max(1, math.ceil((teamTargetSizes[1] or 0) / 5))
        local team2Needed = math.max(1, math.ceil((teamTargetSizes[2] or 0) / 5))

        for j = 1, team1Needed do
            AddMappedWoWGroup(1, oddGroups[j])
        end
        for j = 1, team2Needed do
            AddMappedWoWGroup(2, evenGroups[j])
        end
    else
        for i = 1, logicalTeams do
            local woWGroupsNeeded = math.ceil(teamTargetSizes[i] / 5)
            if woWGroupsNeeded == 0 then woWGroupsNeeded = 1 end
            for _ = 1, woWGroupsNeeded do
                if nextWoWGroup <= 8 then
                    AddMappedWoWGroup(i, nextWoWGroup)
                end
            end
        end
    end

    -- Safety: ensure each logical team has at least one mapped group.
    for i = 1, logicalTeams do
        if #teamWoWGroupMap[i] == 0 then
            for woWGroupIndex = 1, 8 do
                if AddMappedWoWGroup(i, woWGroupIndex) then
                    break
                end
            end
        end
    end

    -- First unassigned group is the overflow start.
    nextWoWGroup = 8
    for woWGroupIndex = 1, 8 do
        if not usedWoWGroups[woWGroupIndex] then
            nextWoWGroup = woWGroupIndex
            break
        end
    end
    self:SetSplitTeamMap(teamWoWGroupMap)

    -- Details! Integration for DPS Balancing
    local dpsScores = NewRosterNameLookup()

    if RC.db.profile.smartSplitBalanceDPS and _G.Details then
        local data = nil
        local segments = _G.Details:GetCombatSegments()
        if segments then
            for _, segment in pairs(segments) do
                if segment and segment.__type == "overall" then
                    data = segment
                    break
                end
            end
        end
        if not data then data = _G.Details:GetCurrentCombat() end
        if not data then data = _G.Details:GetCombat("overall") end

        if data then
            local damageContainer = data:GetContainer(_G.Details.atributo_damage)
            if damageContainer then
                for _, actor in damageContainer:ListActors() do
                    if actor and actor:IsPlayer() then
                        local name = actor:name()
                        local dps = actor.last_dps
                        if not dps or dps == 0 then
                            local total = actor.total or 0
                            local activeTime = math.max(1, actor:Time() or 1)
                            dps = total / activeTime
                        end
                        AddRosterNameLookup(dpsScores, name, dps)
                    end
                end
            end
        end
    end

    local function GetDPSScore(unit)
        if not RC.db.profile.smartSplitBalanceDPS then return 0 end
        if unit.name then
            return ResolveRosterNameLookup(dpsScores, unit.name) or 0
        end
        return 0
    end

    -- Helper: Check if unit is a physical damage dealer (benefits from Monk buff)
    local function IsPhysicalDPS(unit)
        local class = unit.class
        local role = unit.role

        if role == "TANK" then return true end -- Tanks do physical damage
        if role == "HEALER" then return false end
        if class == "HUNTER" then return true end
        if IsMelee(class, unit.specName, unit.specID) then return true end

        return false
    end

    -- Helper: Check if unit is a magic damage dealer (benefits from DH buff)
    local function IsMagicDPS(unit)
        local class = unit.class
        local role = unit.role

        if role == "HEALER" then return true end -- Healers do magic
        if role == "TANK" then return false end
        if class == "HUNTER" then return false end
        if not IsMelee(class, unit.specName, unit.specID) then return true end

        return false
    end

    -- Categorize players
    local tanks = {}
    local healers = {}
    local melee = {}
    local casters = {}
    local allDPS = {}
    local allMonks = {}
    local allDHs = {}

    if playerUnit then
        playerUnit.dpsScore = GetDPSScore(playerUnit)
    end

    for _, unit in ipairs(playersToDistribute) do
        if unit.class == "MONK" then table.insert(allMonks, unit) end
        if unit.class == "DEMONHUNTER" then table.insert(allDHs, unit) end

        local role = unit.role
        unit.dpsScore = GetDPSScore(unit)

        if role == "TANK" then
            table.insert(tanks, unit)
        elseif role == "HEALER" then
            table.insert(healers, unit)
        else
            table.insert(allDPS, unit)
            if IsMelee(unit.class, unit.specName, unit.specID) then
                table.insert(melee, unit)
            else
                table.insert(casters, unit)
            end
        end
    end

    -- Sort DPS by score descending for balancing
    if RC.db.profile.smartSplitBalanceDPS then
        local function SortByDPSDesc(a, b)
            return (a.dpsScore or 0) > (b.dpsScore or 0)
        end
        table.sort(allDPS, SortByDPSDesc)
        table.sort(melee, SortByDPSDesc)
        table.sort(casters, SortByDPSDesc)
    end

    -- Track logical team composition
    local teamFillCounts = {}
    local teamRoleCounts = {}
    local groupHasPhysical = {}
    local groupHasMagic = {}
    for i = 1, logicalTeams do
        teamFillCounts[i] = 0
        teamRoleCounts[i] = { TANK = 0, HEALER = 0, DAMAGER = 0 }
        groupHasPhysical[i] = false
        groupHasMagic[i] = false
    end

    local teamWoWFillCounts = {}
    for i = 1, 8 do teamWoWFillCounts[i] = 0 end

    local function LogicalTeamHasSpace(teamIdx)
        if teamIdx > logicalTeams then return false end
        return teamFillCounts[teamIdx] < teamTargetSizes[teamIdx]
    end

    local function FindFirstTeamWithSpace()
        for t = 1, logicalTeams do
            if LogicalTeamHasSpace(t) then
                return t
            end
        end
        return nil
    end

    local function AddToTeam(unit, teamIdx)
        if teamIdx < 1 then teamIdx = 1 end
        if teamIdx > logicalTeams then teamIdx = logicalTeams end
        if not LogicalTeamHasSpace(teamIdx) then
            teamIdx = FindFirstTeamWithSpace()
        end
        if not teamIdx then
            return false
        end

        teamFillCounts[teamIdx] = teamFillCounts[teamIdx] + 1
        if IsPhysicalDPS(unit) then groupHasPhysical[teamIdx] = true end
        if IsMagicDPS(unit) then groupHasMagic[teamIdx] = true end
        local roleKey = unit.role == "TANK" and "TANK" or (unit.role == "HEALER" and "HEALER" or "DAMAGER")
        teamRoleCounts[teamIdx][roleKey] = (teamRoleCounts[teamIdx][roleKey] or 0) + 1

        -- map to wow group
        local wowGroupAssigned = nil
        for _, wg in ipairs(teamWoWGroupMap[teamIdx]) do
            if teamWoWFillCounts[wg] < 5 then
                wowGroupAssigned = wg
                teamWoWFillCounts[wg] = teamWoWFillCounts[wg] + 1
                break
            end
        end
        -- fallback to any physically available if map failed (unlikely)
        if not wowGroupAssigned then
            for wg = 1, 8 do
                if teamWoWFillCounts[wg] < 5 then
                    wowGroupAssigned = wg
                    teamWoWFillCounts[wg] = teamWoWFillCounts[wg] + 1
                    break
                end
            end
            if not wowGroupAssigned then wowGroupAssigned = 8 end
        end
        unit.group = wowGroupAssigned
        return true
    end

    local playerReservedTeam = nil
    if RC.db.profile.smartSplitKeepSelfG1 and playerUnit then
        if AddToTeam(playerUnit, 1) then
            playerReservedTeam = 1
        else
            playerUnit.group = 1
            playerReservedTeam = 1
        end
    end

    local function FindBestTeam(preferPhysical, preferMagic)
        local candidates = {}
        for i = 1, logicalTeams do
            if LogicalTeamHasSpace(i) then
                local score = 0
                if preferPhysical and not groupHasPhysical[i] then score = score + 100 end
                if preferMagic and not groupHasMagic[i] then score = score + 100 end
                score = score + (teamTargetSizes[i] - teamFillCounts[i])
                table.insert(candidates, {team = i, score = score})
            end
        end
        if #candidates == 0 then return nil end
        table.sort(candidates, function(a, b) return a.score > b.score end)
        return candidates[1].team
    end

    -- Smart seeding: Monks and DHs first
    local currentTeam = 1
    if playerReservedTeam == 1 and logicalTeams > 1 then
        currentTeam = 2
    end

    if RC.db.profile.smartSplitMonk then
        for _, unit in ipairs(allMonks) do
            local bestT = FindBestTeam(true, false) or FindBestTeam(false, false) or 1
            AddToTeam(unit, bestT)
        end
    end

    if RC.db.profile.smartSplitDH then
        for _, unit in ipairs(allDHs) do
            local bestT = FindBestTeam(false, true) or FindBestTeam(false, false) or 1
            AddToTeam(unit, bestT)
        end
    end

    -- After seeding, role counts already include Monk/DH seeds and the reserved player.
    local totalTankCount = #tanks + ((playerUnit and playerUnit.role == "TANK") and 1 or 0)
    local totalHealerCount = #healers + ((playerUnit and playerUnit.role == "HEALER") and 1 or 0)
    local targetTanksPerTeam = math.ceil(totalTankCount / logicalTeams)
    if RC.db.profile.smartSplitTanks and RC.db.profile.smartSplitTanks > 0 then
        targetTanksPerTeam = RC.db.profile.smartSplitTanks
    end
    local targetHealersPerTeam = math.ceil(totalHealerCount / logicalTeams)
    if RC.db.profile.smartSplitHealers and RC.db.profile.smartSplitHealers > 0 then
        targetHealersPerTeam = RC.db.profile.smartSplitHealers
    end

    local playerTankTeam = (playerUnit and playerUnit.role == "TANK" and playerReservedTeam) or nil

    local function TeamAllowedForTank(teamIdx)
        if not playerTankTeam or teamIdx ~= playerTankTeam or logicalTeams <= 1 then
            return true
        end
        for otherTeam = 1, logicalTeams do
            if otherTeam ~= playerTankTeam and LogicalTeamHasSpace(otherTeam) then
                return false
            end
        end
        return true
    end

    -- Distribute tanks: always pick the team with the fewest tanks already placed,
    -- and never place the co-tank into the player's team while another team can take it.
    for _, unit in ipairs(tanks) do
        if unit.group == 0 then
            local bestT, fewest, bestFill = nil, math.huge, math.huge
            for t = 1, logicalTeams do
                local tc = teamRoleCounts[t].TANK or 0
                local fill = teamFillCounts[t] or 0
                if LogicalTeamHasSpace(t) and TeamAllowedForTank(t) and tc < targetTanksPerTeam then
                    if tc < fewest or (tc == fewest and fill < bestFill) then
                        fewest = tc
                        bestFill = fill
                        bestT = t
                    end
                end
            end
            -- Fallback: ignore cap if no team has room under cap
            if not bestT then
                local fallbackFill = math.huge
                for t = 1, logicalTeams do
                    if LogicalTeamHasSpace(t) and TeamAllowedForTank(t) and (teamFillCounts[t] or 0) < fallbackFill then
                        fallbackFill = teamFillCounts[t] or 0
                        bestT = t
                    end
                end
            end
            if not bestT then
                for t = 1, logicalTeams do
                    if LogicalTeamHasSpace(t) then
                        bestT = t
                        break
                    end
                end
            end
            AddToTeam(unit, bestT or 1)
        end
    end

    -- Distribute healers: same fewest-first logic so seeded healer Monks/DHs
    -- don't stack multiple healers onto the same team.
    for _, unit in ipairs(healers) do
        if unit.group == 0 then
            local bestT, fewest, bestFill = nil, math.huge, math.huge
            for t = 1, logicalTeams do
                local hc = teamRoleCounts[t].HEALER or 0
                local fill = teamFillCounts[t] or 0
                if LogicalTeamHasSpace(t) and hc < targetHealersPerTeam then
                    if hc < fewest or (hc == fewest and fill < bestFill) then
                        fewest = hc
                        bestFill = fill
                        bestT = t
                    end
                end
            end
            -- Fallback: ignore cap if no team has room under cap
            if not bestT then
                local fallbackFill = math.huge
                for t = 1, logicalTeams do
                    if LogicalTeamHasSpace(t) and (teamFillCounts[t] or 0) < fallbackFill then
                        fallbackFill = teamFillCounts[t] or 0
                        bestT = t
                    end
                end
            end
            AddToTeam(unit, bestT or 1)
        end
    end

    -- Distribute DPS
    if RC.db.profile.smartSplitBalanceDPS and #allDPS > 0 then
        -- Snake draft for DPS balancing
        local teamDPSTotals = {}
        for i = 1, logicalTeams do teamDPSTotals[i] = 0 end
        for _, unit in ipairs(self.DraftRoster or {}) do
            if unit.group and unit.group ~= 0 and unit.role ~= "TANK" and unit.role ~= "HEALER" then
                local placedTeam = self.SplitGroupToTeam and self.SplitGroupToTeam[unit.group]
                if placedTeam and teamDPSTotals[placedTeam] then
                    teamDPSTotals[placedTeam] = teamDPSTotals[placedTeam] + (unit.dpsScore or 0)
                end
            end
        end

        local left = 1
        local right = #allDPS
        local useHigh = true

        while left <= right do
            local unit
            if useHigh then
                unit = allDPS[left]
                left = left + 1
            else
                unit = allDPS[right]
                right = right - 1
            end
            useHigh = not useHigh

            if unit and unit.group == 0 then
                -- Find team with lowest DPS that has space
                local bestT = nil
                local lowestDPS = math.huge
                for i = 1, logicalTeams do
                    if LogicalTeamHasSpace(i) and teamDPSTotals[i] < lowestDPS then
                        lowestDPS = teamDPSTotals[i]
                        bestT = i
                    end
                end
                if bestT and AddToTeam(unit, bestT) then
                    teamDPSTotals[bestT] = teamDPSTotals[bestT] + (unit.dpsScore or 0)
                end
            end
        end
    else
        local function NextRoundRobinTeamWithSpace()
            for _ = 1, logicalTeams do
                if LogicalTeamHasSpace(currentTeam) then
                    return currentTeam
                end
                currentTeam = (currentTeam % logicalTeams) + 1
            end
            return nil
        end

        -- Simple even distribution
        for _, unit in ipairs(melee) do
            if unit.group == 0 then
                local teamIdx = NextRoundRobinTeamWithSpace()
                if teamIdx then
                    AddToTeam(unit, teamIdx)
                    currentTeam = (currentTeam % logicalTeams) + 1
                end
            end
        end

        for _, unit in ipairs(casters) do
            if unit.group == 0 then
                local teamIdx = NextRoundRobinTeamWithSpace()
                if teamIdx then
                    AddToTeam(unit, teamIdx)
                    currentTeam = (currentTeam % logicalTeams) + 1
                end
            end
        end
    end

    -- Handle overflow - any players not assigned to target groups go to overflow groups
    local overflowGroup = nextWoWGroup
    if overflowGroup > 8 then overflowGroup = 8 end
    for _, unit in ipairs(playersToDistribute) do
        if unit.group == 0 then
            -- Put in next available group (overflow)
            while overflowGroup <= 8 do
                if teamWoWFillCounts[overflowGroup] < 5 then
                    unit.group = overflowGroup
                    teamWoWFillCounts[overflowGroup] = teamWoWFillCounts[overflowGroup] + 1
                    break
                end
                overflowGroup = overflowGroup + 1
            end
            -- If all groups full (40 players), force to group 8
            if unit.group == 0 then
                unit.group = 8
            end
        end
    end

    -- Handle Keep me in G1. The player is reserved before distribution, so do not
    -- swap a co-tank back into the player's team as a late correction.
    if RC.db.profile.smartSplitKeepSelfG1 and playerUnit then
        if not playerUnit.group or playerUnit.group == 0 then
            playerUnit.group = 1
        end
    elseif playerUnit then
        -- KeepSelfG1 is off but we still need to place the player
        if playerUnit.group == 0 then
            playerUnit.group = 1
        end
    end

    self:RefreshGrid()
end

function RaidSplit:MeleeRangedSplit(fromInspectRefresh)
    if not self.DraftRoster or #self.DraftRoster == 0 then
        self:SyncRoster()
    end

    local queuedInspects = self:QueueMissingHybridSpecInspects()
    if queuedInspects > 0 and not fromInspectRefresh then
        self.pendingMeleeRangedRefresh = true
        self:Print(string.format("Inspecting %d hybrid specs for melee/range split...", queuedInspects))
    end

    -- Reset all groups to 0 first (unassigned)
    for _, unit in ipairs(self.DraftRoster) do
        unit.group = 0
    end

    local playerName = UnitName("player")
    local keepSelfG1 = RC.db.profile.smartSplitKeepSelfG1
    local playerUnit = nil

    -- Categorize players. If requested, reserve the player before sorting.
    local melee = {}  -- Tanks + Melee DPS
    local ranged = {} -- Healers + Ranged DPS

    for _, unit in ipairs(self.DraftRoster) do
        local role = unit.role
        local isMel = IsMelee(unit.class, unit.specName, unit.specID)

        if keepSelfG1 and NamesMatch(unit.name, playerName) then
            playerUnit = unit
        elseif role == "TANK" then
            table.insert(melee, unit) -- Tanks go to melee groups
        elseif role == "HEALER" then
            table.insert(ranged, unit) -- Healers go to ranged groups
        elseif isMel then
            table.insert(melee, unit) -- Melee DPS
        else
            table.insert(ranged, unit) -- Ranged DPS
        end
    end

    -- Helper to find group with lowest count from a list
    local function FindLowestCountGroup(groupList, groupCounts)
        local bestG = nil
        local lowestCount = 6
        for _, g in ipairs(groupList) do
            if groupCounts[g] < 5 and groupCounts[g] < lowestCount then
                lowestCount = groupCounts[g]
                bestG = g
            end
        end
        return bestG
    end

    -- Define melee groups (odd) and ranged groups (even)
    local meleeGroups = {1, 3, 5, 7}
    local rangedGroups = {2, 4, 6, 8}
    local allGroups = {1, 2, 3, 4, 5, 6, 7, 8}

    -- Group counters
    local groupCounts = {}
    for i = 1, 8 do groupCounts[i] = 0 end

    local function AddToGroup(unit, groupIdx)
        if not groupIdx or groupIdx < 1 or groupIdx > 8 or groupCounts[groupIdx] >= 5 then
            return false
        end
        unit.group = groupIdx
        groupCounts[groupIdx] = groupCounts[groupIdx] + 1
        return true
    end

    if playerUnit then
        AddToGroup(playerUnit, 1)
    end

    local function BuildActiveGroups(baseGroups, count)
        if count <= 0 then
            return {}
        end

        local needed = math.ceil(count / 5)
        if needed < 1 then
            needed = 1
        elseif needed > #baseGroups then
            needed = #baseGroups
        end

        local active = {}
        for i = 1, needed do
            active[i] = baseGroups[i]
        end
        return active
    end

    local function EnsureActiveGroup(groups, groupIdx)
        if not groupIdx then
            return
        end
        for _, existing in ipairs(groups) do
            if existing == groupIdx then
                return
            end
        end
        table.insert(groups, 1, groupIdx)
    end

    local function PlaceUnits(units, preferredGroups)
        if #units == 0 then
            return
        end

        local groupsToUse = preferredGroups
        if #groupsToUse == 0 then
            groupsToUse = allGroups
        end

        for _, unit in ipairs(units) do
            local bestG = FindLowestCountGroup(groupsToUse, groupCounts)
            if bestG then
                AddToGroup(unit, bestG)
            else
                -- Fallback: put anywhere with space if preferred groups are full.
                for _, g in ipairs(allGroups) do
                    if groupCounts[g] < 5 then
                        AddToGroup(unit, g)
                        break
                    end
                end
            end
        end
    end

    -- Only use as many odd/even groups as required by current roster size.
    local activeMeleeGroups = BuildActiveGroups(meleeGroups, #melee + (playerUnit and 1 or 0))
    local activeRangedGroups = BuildActiveGroups(rangedGroups, #ranged)
    if playerUnit then
        EnsureActiveGroup(activeMeleeGroups, 1)
    end

    -- Distribute Melee evenly across odd groups (1, 3, 5, 7).
    PlaceUnits(melee, activeMeleeGroups)

    -- Distribute Ranged evenly across even groups (2, 4, 6, 8).
    PlaceUnits(ranged, activeRangedGroups)

    -- If we still have unassigned units (only possible in extreme overflow cases),
    -- force-place them anywhere with open slots.
    for _, unit in ipairs(self.DraftRoster) do
        if not unit.group or unit.group == 0 then
            for _, g in ipairs(allGroups) do
                if groupCounts[g] < 5 then
                    AddToGroup(unit, g)
                    break
                end
            end
        end
    end

    local meleeTeamGroups, rangedTeamGroups = {}, {}
    local assignedTeamByGroup = {}

    local function AssignMappedGroups(groups, teamIndex, destination)
        for _, group in ipairs(groups) do
            if not assignedTeamByGroup[group] then
                assignedTeamByGroup[group] = teamIndex
                table.insert(destination, group)
            end
        end
    end

    AssignMappedGroups(activeMeleeGroups, 1, meleeTeamGroups)
    AssignMappedGroups(activeRangedGroups, 2, rangedTeamGroups)

    local meleeMembers = {}
    if playerUnit then
        meleeMembers[playerUnit] = true
    end
    for _, unit in ipairs(melee) do
        meleeMembers[unit] = true
    end

    local meleeByGroup, rangedByGroup = {}, {}
    for _, unit in ipairs(self.DraftRoster) do
        local group = ClampGroupIndex(unit.group)
        if group >= 1 then
            if meleeMembers[unit] then
                meleeByGroup[group] = (meleeByGroup[group] or 0) + 1
            else
                rangedByGroup[group] = (rangedByGroup[group] or 0) + 1
            end
        end
    end

    -- Overflow can only happen when one side exceeds the 20 slots available in
    -- its odd/even groups. Map those occupied spill groups to their majority.
    for group = 1, 8 do
        if groupCounts[group] > 0 and not assignedTeamByGroup[group] then
            if (meleeByGroup[group] or 0) >= (rangedByGroup[group] or 0) then
                assignedTeamByGroup[group] = 1
                table.insert(meleeTeamGroups, group)
            else
                assignedTeamByGroup[group] = 2
                table.insert(rangedTeamGroups, group)
            end
        end
    end

    if #melee + (playerUnit and 1 or 0) > 20 or #ranged > 20 then
        self:Print("Melee/ranged split used mixed overflow groups because one side exceeds 20 players.")
    end

    self:SetSplitTeamMap({ meleeTeamGroups, rangedTeamGroups })
    self:RefreshGrid()
end

function RaidSplit:UpdateScale(scale, source)
    local workspace = RC:GetModule("Workspace", true)
    if source ~= "workspace" and workspace and workspace.SetScale and not workspace.applyingScale then
        return workspace:SetScale(scale)
    end
    local applied = self:SetFrameScaleStable(scale)
    if self.HeaderScaleSlider and source ~= "header" then
        self.HeaderScaleSlider:RefreshFromDB(applied)
    end
    if self.SideScaleSlider and self.SideScaleSlider.RefreshFromDB and source ~= "side" then
        self.SideScaleSlider:RefreshFromDB(applied)
    end
    return applied
end

-- ─────────────────────────────────────────────────────────────────────────────
-- LAYOUT SAVE / LOAD
-- ─────────────────────────────────────────────────────────────────────────────

local function TrimText(value)
    local text = tostring(value or "")
    if strtrim then
        return strtrim(text)
    end
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function CopyPlainValue(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[CopyPlainValue(k, seen)] = CopyPlainValue(v, seen)
    end
    return copy
end

local function FormatLayoutTimestamp(timestamp)
    local numeric = tonumber(timestamp)
    if numeric and numeric > 0 and date then
        return date("%Y-%m-%d %H:%M", numeric)
    end
    return "Unknown"
end

local function MakeBossKey(encounterID, bossName)
    local numericID = tonumber(encounterID)
    if numericID and numericID > 0 then
        return "encounter:" .. tostring(math.floor(numericID))
    end
    local name = TrimText(bossName)
    if name ~= "" then
        local key = name:lower():gsub("%s+", "-"):gsub("[^%w%-_]", "")
        if key ~= "" then
            return "boss:" .. key
        end
    end
    return "manual:unassigned"
end

local function CopySplitGroupToTeam(map)
    if type(map) ~= "table" then
        return nil
    end
    local copy = {}
    for group, team in pairs(map) do
        local groupIndex = tonumber(group)
        local teamIndex = tonumber(team)
        if groupIndex and teamIndex then
            copy[groupIndex] = teamIndex
        end
    end
    return next(copy) and copy or nil
end

local function GetLayoutBossName(layout)
    if type(layout) ~= "table" then
        return ""
    end
    if type(layout.boss) == "table" and layout.boss.name then
        return tostring(layout.boss.name)
    end
    return tostring(layout.bossName or "")
end

local function CountLayoutRoster(layout)
    local roster = type(layout) == "table" and layout.roster or nil
    return type(roster) == "table" and #roster or 0
end

function RaidSplit:GetLayoutStores()
    local profile = RC.db and RC.db.profile
    if not profile then
        return {}, {}
    end
    profile.savedLayouts = profile.savedLayouts or {}
    profile.raidSplitBossLayouts = profile.raidSplitBossLayouts or {}

    for name, layout in pairs(profile.savedLayouts) do
        if type(layout) == "table" then
            layout.name = layout.name or name
            layout.schema = layout.schema or 1
            layout.roster = type(layout.roster) == "table" and layout.roster or {}
            for _, entry in ipairs(layout.roster) do
                if type(entry) == "table" and entry.name then
                    entry.shortName = entry.shortName or GetShortName(entry.name)
                end
            end
        end
    end

    return profile.savedLayouts, profile.raidSplitBossLayouts
end

function RaidSplit:GetCurrentBossInfo(manualBossName)
    local context = RC.GetRaidContext and RC:GetRaidContext({
        manualBossName = manualBossName,
        encounterID = self.CurrentEncounterID,
        encounterName = self.CurrentEncounterName,
    })
    if not context then
        local manual = TrimText(manualBossName)
        local bossName = manual
        local encounterID = self.CurrentEncounterID
        local source = manual ~= "" and "manual" or nil

        if bossName == "" and self.CurrentEncounterName and self.CurrentEncounterName ~= "" then
            bossName = self.CurrentEncounterName
            source = "encounter"
        end

        if bossName == "" and GetInstanceInfo then
            local instanceName = GetInstanceInfo()
            if instanceName and instanceName ~= "" then
                bossName = instanceName
                source = "instance"
            end
        end

        if bossName == "" then
            bossName = "Unassigned"
            source = "manual"
        end

        return {
            key = MakeBossKey(encounterID, bossName),
            name = bossName,
            encounterID = tonumber(encounterID),
            source = source or "manual",
        }
    end

    return {
        key = context.legacyBossKey,
        name = context.bossName,
        encounterID = context.encounterID,
        source = context.source or "manual",
        raidName = context.raidName,
        raidKey = context.raidKey,
        contextBossKey = context.bossKey,
        difficultyID = context.difficultyID,
        difficultyName = context.difficultyName,
        difficultyKey = context.difficultyKey,
        instanceMapID = context.instanceMapID,
        journalInstanceID = context.journalInstanceID,
    }
end

function RaidSplit:BuildLayoutSnapshot(name, options)
    local roster = {}
    local maxGroup = 0
    for _, unit in ipairs(self.DraftRoster or {}) do
        if unit and unit.name then
            local group = ClampGroupIndex(unit.group)
            if group > maxGroup then
                maxGroup = group
            end
            table.insert(roster, {
                name = unit.name,
                shortName = GetShortName(unit.name),
                group = group,
                class = unit.class,
                level = unit.level,
                role = unit.role,
                specName = unit.specName,
                specID = unit.specID,
                melee = IsMelee(unit.class, unit.specName, unit.specID),
            })
        end
    end

    local now = time and time() or 0
    local boss = self:GetCurrentBossInfo(options and options.bossName)
    return {
        schema = 2,
        name = name,
        roster = roster,
        timestamp = now,
        updatedAt = now,
        boss = boss,
        bossKey = boss.key,
        bossName = boss.name,
        raidKey = boss.raidKey,
        raidName = boss.raidName,
        contextBossKey = boss.contextBossKey,
        difficultyKey = boss.difficultyKey,
        difficultyID = boss.difficultyID,
        difficultyName = boss.difficultyName,
        notes = TrimText(options and options.notes),
        groupCount = maxGroup,
        layoutMode = self.SplitGroupToTeam and "melee_ranged" or "manual",
        splitGroupToTeam = CopySplitGroupToTeam(self.SplitGroupToTeam),
        smartSplit = {
            monk = RC.db.profile.smartSplitMonk ~= false,
            demonHunter = RC.db.profile.smartSplitDH ~= false,
            healers = RC.db.profile.smartSplitHealers or 0,
            tanks = RC.db.profile.smartSplitTanks or 0,
            balanceDPS = RC.db.profile.smartSplitBalanceDPS and true or false,
            keepSelfGroupOne = RC.db.profile.smartSplitKeepSelfG1 and true or false,
            twoWayOddEven = RC.db.profile.smartSplitTwoWayOddEven ~= false,
        },
    }
end

function RaidSplit:SaveLayout(name, options)
    name = TrimText(name)
    if name == "" then
        return false
    end

    if not self.DraftRoster or #self.DraftRoster == 0 then
        self:Print("Nothing to save yet. Import or sync the roster first.")
        return false
    end

    local layouts, bossIndex = self:GetLayoutStores()
    local existing = layouts[name]
    local layout = self:BuildLayoutSnapshot(name, options)
    if existing and existing.timestamp then
        layout.timestamp = existing.timestamp
    end
    layouts[name] = layout
    if layout.bossKey then
        bossIndex[layout.bossKey] = name
    end
    self._selectedLayoutName = name
    self:Print("Layout '" .. name .. "' saved.")
    return true, layout
end

function RaidSplit:GetSuggestedLayoutName()
    local layouts = self:GetLayoutStores()
    local boss = self:GetCurrentBossInfo()
    local prefix = boss and boss.name and boss.name ~= "Unassigned" and boss.name or "Setup"
    local suffix = date and date("%m-%d %H:%M") or tostring(time and time() or "Now")
    local base = prefix .. " " .. suffix
    if not layouts[base] then
        return base
    end

    local index = 2
    local name = base .. " #" .. index
    while layouts[name] do
        index = index + 1
        name = base .. " #" .. index
    end
    return name
end

function RaidSplit:GetSortedLayouts()
    local layouts = self:GetLayoutStores()
    local list = {}
    for name, layout in pairs(layouts) do
        if type(layout) == "table" then
            table.insert(list, { name = name, layout = layout })
        end
    end
    table.sort(list, function(a, b)
        local bossA = GetLayoutBossName(a.layout)
        local bossB = GetLayoutBossName(b.layout)
        if bossA ~= bossB then
            return bossA < bossB
        end
        return (a.layout.updatedAt or a.layout.timestamp or 0) > (b.layout.updatedAt or b.layout.timestamp or 0)
    end)
    return list
end

function RaidSplit:GetSavedLayout(name)
    local layouts = self:GetLayoutStores()
    local layout = name and layouts[name]
    if type(layout) ~= "table" then
        return nil
    end
    layout.name = layout.name or name
    layout.roster = type(layout.roster) == "table" and layout.roster or {}
    return layout
end

function RaidSplit:BuildCurrentRosterLookup()
    local byName, list = NewRosterNameLookup(), {}
    for _, unit in ipairs(self.DraftRoster or {}) do
        local key = unit and unit.name and GetRosterNameKey(unit.name)
        if key then
            AddRosterNameLookup(byName, unit.name, unit)
            table.insert(list, unit)
        end
    end
    return byName, list
end

function RaidSplit:FindReplacementForLayoutEntry(entry, usedKeys, currentList)
    local bestUnit, bestScore, bestReason = nil, 0, nil
    local savedMelee = entry.melee
    if savedMelee == nil then
        savedMelee = IsMelee(entry.class, entry.specName, entry.specID)
    end

    for _, unit in ipairs(currentList or {}) do
        local key = unit and unit.name and GetRosterNameKey(unit.name)
        if key and not usedKeys[key] then
            local score = 0
            local reason = nil
            if entry.role and unit.role and entry.role == unit.role then
                score = score + 60
                reason = "same role"
            end
            if entry.class and unit.class and entry.class == unit.class then
                score = score + 50
                reason = reason or "same class"
            end
            if entry.specID and unit.specID and tonumber(entry.specID) == tonumber(unit.specID) then
                score = score + 40
                reason = reason or "same spec"
            elseif entry.specName and unit.specName and entry.specName == unit.specName then
                score = score + 35
                reason = reason or "same spec"
            end
            local unitMelee = IsMelee(unit.class, unit.specName, unit.specID)
            if savedMelee ~= nil and savedMelee == unitMelee then
                score = score + 20
                reason = reason or "same melee/ranged"
            end
            if not unit.group or unit.group == 0 then
                score = score + 5
                reason = reason or "unassigned"
            end
            if score > bestScore then
                bestUnit, bestScore, bestReason = unit, score, reason
            end
        end
    end

    if bestUnit then
        return bestUnit, bestReason or "available"
    end

    for _, unit in ipairs(currentList or {}) do
        local key = unit and unit.name and GetRosterNameKey(unit.name)
        if key and not usedKeys[key] then
            return unit, "available"
        end
    end
    return nil, "manual"
end

function RaidSplit:AnalyzeSavedLayout(layout)
    local currentByName, currentList = self:BuildCurrentRosterLookup()
    local usedKeys = {}
    local result = {
        present = {},
        missing = {},
        replacements = {},
        replacementsByEntry = {},
        currentByName = currentByName,
    }

    for _, entry in ipairs((layout and layout.roster) or {}) do
        if type(entry) == "table" and entry.name then
            local key = GetRosterNameKey(entry.name) or entry.name
            local exact = ResolveRosterNameLookup(currentByName, entry.name)
            if exact then
                usedKeys[GetRosterNameKey(exact.name) or key] = true
                table.insert(result.present, { entry = entry, unit = exact })
            else
                local replacement, reason = self:FindReplacementForLayoutEntry(entry, usedKeys, currentList)
                local missing = { entry = entry, replacement = replacement, reason = reason }
                table.insert(result.missing, missing)
                if replacement and replacement.name then
                    local replacementKey = GetRosterNameKey(replacement.name)
                    if replacementKey then
                        usedKeys[replacementKey] = true
                    end
                    result.replacements[key] = {
                        savedName = entry.name,
                        replacementName = replacement.name,
                        reason = reason,
                    }
                    result.replacementsByEntry[entry] = result.replacements[key]
                end
            end
        end
    end
    return result
end

function RaidSplit:LoadLayout(name, options)
    name = TrimText(name)
    if name == "" then return false end
    local saved = self:GetSavedLayout(name)
    if not saved then
        self:Print("Layout '" .. name .. "' not found.")
        return false
    end
    if not self.Frame then
        self:CreateMainFrame()
    end
    if not self.DraftRoster or #self.DraftRoster == 0 then
        self:SyncRoster()
    end

    local analysis = self:AnalyzeSavedLayout(saved)
    local applyReplacements = options and options.applyReplacements
    local currentByName = analysis.currentByName or {}

    for _, unit in ipairs(self.DraftRoster or {}) do
        unit.group = 0
    end

    local applied, replaced, unresolved = 0, 0, 0
    for _, entry in ipairs(saved.roster or {}) do
        local key = entry.name and GetRosterNameKey(entry.name)
        local unit = key and ResolveRosterNameLookup(currentByName, entry.name)
        local replacement = analysis.replacementsByEntry and analysis.replacementsByEntry[entry]
        if not unit and applyReplacements and replacement then
            local replacementName = replacement.replacementName
            unit = replacementName and ResolveRosterNameLookup(currentByName, replacementName)
            if unit then
                replaced = replaced + 1
            end
        end
        if unit then
            unit.group = ClampGroupIndex(entry.group)
            applied = applied + 1
        else
            unresolved = unresolved + 1
        end
    end

    self.SplitGroupToTeam = CopySplitGroupToTeam(saved.splitGroupToTeam)
    self._lastLayoutAnalysis = analysis
    self._selectedLayoutName = name
    self:RefreshGrid()
    if unresolved > 0 then
        self:Print(string.format("Layout '%s' loaded: %d assigned, %d missing%s.", name, applied, unresolved, replaced > 0 and (", " .. replaced .. " replaced") or ""))
    else
        self:Print(string.format("Layout '%s' loaded%s.", name, replaced > 0 and (" with " .. replaced .. " smart replacements") or ""))
    end
    if self._profilePopup and self._profilePopup:IsShown() then
        self:_RefreshProfilePopup(true)
    end
    return true, analysis
end

function RaidSplit:RenameLayout(oldName, newName)
    oldName = TrimText(oldName)
    newName = TrimText(newName)
    if oldName == "" or newName == "" or oldName == newName then return false end
    local layouts, bossIndex = self:GetLayoutStores()
    if not layouts[oldName] then return false end
    if layouts[newName] then
        self:Print("A layout named '" .. newName .. "' already exists.")
        return false
    end
    layouts[newName] = layouts[oldName]
    layouts[oldName] = nil
    layouts[newName].name = newName
    layouts[newName].updatedAt = time and time() or layouts[newName].updatedAt
    for key, value in pairs(bossIndex) do
        if value == oldName then
            bossIndex[key] = newName
        end
    end
    self._selectedLayoutName = newName
    self:Print("Layout renamed to '" .. newName .. "'.")
    return true
end

function RaidSplit:DeleteLayout(name)
    name = TrimText(name)
    local layouts, bossIndex = self:GetLayoutStores()
    if name == "" or not layouts[name] then return false end
    layouts[name] = nil
    for key, value in pairs(bossIndex) do
        if value == name then
            bossIndex[key] = nil
        end
    end
    if self._selectedLayoutName == name then
        self._selectedLayoutName = nil
    end
    self:Print("Layout '" .. name .. "' deleted.")
    return true
end

function RaidSplit:DuplicateLayout(name)
    name = TrimText(name)
    local layouts = self:GetLayoutStores()
    local layout = layouts[name]
    if not layout then return false end
    local base = name .. " Copy"
    local copyName = base
    local index = 2
    while layouts[copyName] do
        copyName = base .. " " .. index
        index = index + 1
    end
    layouts[copyName] = CopyPlainValue(layout)
    layouts[copyName].name = copyName
    layouts[copyName].timestamp = time and time() or layouts[copyName].timestamp
    layouts[copyName].updatedAt = layouts[copyName].timestamp
    self._selectedLayoutName = copyName
    self:Print("Layout duplicated as '" .. copyName .. "'.")
    return true
end

-- OrionUI: share a layout as a !OUI:S:1! string (Stig, 2026-10-02). Without a selected
-- layout the current draft is exported.
function RaidSplit:ExportLayoutString(name)
    local layout = name and self:GetSavedLayout(name)
    if not layout then
        if not self.DraftRoster or #self.DraftRoster == 0 then
            self:Print("Nothing to export yet. Save a layout or sync the roster first.")
            return nil
        end
        layout = self:BuildLayoutSnapshot(self:GetSuggestedLayoutName())
    end
    local str, err = ns.Serialize:Encode("S", { layout = CopyPlainValue(layout) })
    if not str then self:Print("Export failed: " .. tostring(err)) end
    return str, layout.name
end

-- -> ok, message. Imported layouts are saved under a free name; nothing existing is overwritten.
function RaidSplit:ImportLayoutString(str)
    local ok, kind, payload = ns.Serialize:Decode(str)
    if not ok then return false, kind end
    if kind ~= "S" then return false, "This is not a Raid Split layout string." end
    local layout = type(payload) == "table" and payload.layout
    if type(layout) ~= "table" or type(layout.roster) ~= "table" then
        return false, "The layout in this string is damaged."
    end
    local roster = {}
    for _, entry in ipairs(layout.roster) do
        if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
            entry.group = ClampGroupIndex(tonumber(entry.group) or 1)
            entry.shortName = GetShortName(entry.name)
            roster[#roster + 1] = entry
        end
        if #roster >= 40 then break end
    end
    if #roster == 0 then return false, "The layout in this string has no players." end
    layout.roster = roster

    local layouts = self:GetLayoutStores()
    local base = TrimText(type(layout.name) == "string" and layout.name or "")
    if base == "" then base = "Imported" end
    local name, index = base, 2
    while layouts[name] do
        name = base .. " " .. index
        index = index + 1
    end
    layout.name = name
    layout.updatedAt = time and time() or layout.updatedAt
    layout.timestamp = layout.timestamp or layout.updatedAt
    layouts[name] = layout
    self._selectedLayoutName = name
    if self._layoutManagerPopup and self._layoutManagerPopup:IsShown() then
        self:_RefreshProfilePopup(true)
    end
    return true, "Imported as '" .. name .. "' (" .. #roster .. " players). Pick it in the list and press Load Selected."
end

function RaidSplit:AssignLayoutBoss(name, bossName)
    name = TrimText(name)
    local layouts, bossIndex = self:GetLayoutStores()
    local layout = layouts[name]
    if not layout then return false end
    local boss = self:GetCurrentBossInfo(bossName)
    layout.boss = boss
    layout.bossKey = boss.key
    layout.bossName = boss.name
    layout.raidKey = boss.raidKey
    layout.raidName = boss.raidName
    layout.contextBossKey = boss.contextBossKey
    layout.difficultyKey = boss.difficultyKey
    layout.difficultyID = boss.difficultyID
    layout.difficultyName = boss.difficultyName
    layout.updatedAt = time and time() or layout.updatedAt
    bossIndex[boss.key] = name
    self:Print("Layout '" .. name .. "' assigned to " .. boss.name .. ".")
    return true
end

function RaidSplit:QuickSaveLayout()
    if not self.DraftRoster or #self.DraftRoster == 0 then
        self:Print("Nothing to save yet. Import or sync the roster first.")
        return
    end

    local name = self:GetSuggestedLayoutName()
    self:SaveLayout(name)
    if self._profilePopup and self._profilePopup:IsShown() then
        self:_RefreshProfilePopup(true)
    end
end

function RaidSplit:ListLayouts()
    local layouts = self:GetSortedLayouts()
    if #layouts == 0 then
        self:Print("No saved layouts.")
        return
    end
    for _, record in ipairs(layouts) do
        local layout = record.layout
        local boss = GetLayoutBossName(layout)
        local suffix = boss ~= "" and (" [" .. boss .. "]") or ""
        self:Print("Layout: " .. record.name .. suffix)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- PROFILES DROPDOWN  (wired to the "Profiles ▾" button in the header)
-- ─────────────────────────────────────────────────────────────────────────────

function RaidSplit:_WireLegacyProfileButton(btn, mainFrame)
    local W = 185
    -- Parent to UIParent so it floats above the main frame without z-order issues
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetWidth(W)
    popup:SetHeight(10) -- height set dynamically in _RefreshProfilePopup
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(200)
    popup:SetBackdrop(RC.Config.Backdrop)
    popup:SetBackdropColor(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, 0.98)
    SetRaidSplitSoftBorder(popup, 0.55)
    popup:Hide()
    self._profilePopup = popup

    btn:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            RC:Print("Raid Split profiles are unavailable during combat.")
            return
        end
        if popup:IsShown() then
            popup:Hide()
            return
        end
        popup:ClearAllPoints()
        popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
        self:_RefreshProfilePopup()
        popup:Show()
    end)

    -- Close popup when the main frame is hidden
    mainFrame:HookScript("OnHide", function()
        popup:Hide()
    end)
end

function RaidSplit:_RefreshLegacyProfilePopup()
    local popup = self._profilePopup
    if not popup then return end

    local W = popup:GetWidth()
    local PAD = 10
    local INNER = W - PAD * 2
    local y = -PAD
    popup:SetBackdropColor(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, RC.Config.Color.a or 0.98)
    SetRaidSplitSoftBorder(popup, 0.55)

    -- ── Save section ──────────────────────────────────────────────────────────
    if not popup._saveLabel then
        local lbl = popup:CreateFontString(nil, "OVERLAY")
        RC:SetFont(lbl, 10, "OUTLINE")
        lbl:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)
        popup._saveLabel = lbl
    end
    popup._saveLabel:ClearAllPoints()
    popup._saveLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, y)
    popup._saveLabel:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
    popup._saveLabel:SetText("Save current layout as:")
    popup._saveLabel:Show()
    y = y - 16

    if not popup._editBox then
        local eb = CreateFrame("EditBox", nil, popup, "BackdropTemplate")
        eb:SetSize(INNER, 22)
        eb:SetBackdrop(RC.Config.Backdrop)
        eb:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, 1)
        eb:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.20, RC.Config.InputBorder.a or 0))
        eb:SetAutoFocus(false)
        eb:SetFontObject(GameFontNormal)
        eb:SetTextInsets(5, 5, 0, 0)
        eb:SetMaxLetters(32)
        popup._editBox = eb
        eb:SetScript("OnEscapePressed", function() popup:Hide() end)
        eb:SetScript("OnEnterPressed", function()
            local name = (eb:GetText() or ""):trim()
            if name ~= "" then self:SaveLayout(name); popup:Hide() end
        end)
    end
    popup._editBox:ClearAllPoints()
    popup._editBox:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, y)
    popup._editBox:SetWidth(INNER)
    popup._editBox:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, RC.Config.InputBg.a or 1)
    popup._editBox:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.20, RC.Config.InputBorder.a or 0))
    popup._editBox:SetText(self:GetSuggestedLayoutName())
    popup._editBox:HighlightText()
    popup._editBox:Show()
    y = y - 26

    if not popup._saveBtn then
        popup._saveBtn = MakeBtn(popup, INNER, 22, "Save")
        popup._saveBtn:SetScript("OnClick", function()
            local name = (popup._editBox:GetText() or ""):trim()
            if name ~= "" then self:SaveLayout(name); popup:Hide() end
        end)
    end
    popup._saveBtn:ClearAllPoints()
    popup._saveBtn:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, y)
    popup._saveBtn:SetWidth(INNER)
    popup._saveBtn:Show()
    y = y - 30

    -- ── Separator ─────────────────────────────────────────────────────────────
    if not popup._sep then
        local sep = popup:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        popup._sep = sep
    end
    popup._sep:ClearAllPoints()
    popup._sep:SetPoint("TOPLEFT",  popup, "TOPLEFT",  0, y + 4)
    popup._sep:SetPoint("TOPRIGHT", popup, "TOPRIGHT", 0, y + 4)
    SetRaidSplitLine(popup._sep, 0.34)
    y = y - 8

    -- ── Load section ──────────────────────────────────────────────────────────
    if not popup._loadLabel then
        local lbl = popup:CreateFontString(nil, "OVERLAY")
        RC:SetFont(lbl, 10, "OUTLINE")
        lbl:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)
        popup._loadLabel = lbl
    end
    popup._loadLabel:ClearAllPoints()
    popup._loadLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, y)
    popup._loadLabel:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
    popup._loadLabel:SetText("Load layout:")
    popup._loadLabel:Show()
    y = y - 18

    popup._layoutBtns = popup._layoutBtns or {}
    local btnIdx = 0
    local layouts = RC.db.profile.savedLayouts or {}

    for name, _ in pairs(layouts) do
        btnIdx = btnIdx + 1
        if not popup._layoutBtns[btnIdx] then
            popup._layoutBtns[btnIdx] = MakeBtn(popup, INNER, 20, "")
        end
        local lb = popup._layoutBtns[btnIdx]
        lb.labelText:SetText(name)
        lb:ClearAllPoints()
        lb:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, y)
        lb:SetWidth(INNER)
        lb:Show()
        local n = name
        lb:SetScript("OnClick", function() self:LoadLayout(n); popup:Hide() end)
        y = y - 24
    end

    for i = btnIdx + 1, #popup._layoutBtns do
        popup._layoutBtns[i]:Hide()
    end

    if btnIdx == 0 then
        if not popup._emptyLabel then
            local lbl = popup:CreateFontString(nil, "OVERLAY")
            RC:SetFont(lbl, 10, "OUTLINE")
            popup._emptyLabel = lbl
        end
        popup._emptyLabel:ClearAllPoints()
        popup._emptyLabel:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD, y)
        popup._emptyLabel:SetTextColor(RC.Config.DisabledText.r, RC.Config.DisabledText.g, RC.Config.DisabledText.b, RC.Config.DisabledText.a or 1)
        popup._emptyLabel:SetText("No saved layouts")
        popup._emptyLabel:Show()
        y = y - 18
    elseif popup._emptyLabel then
        popup._emptyLabel:Hide()
    end

    popup:SetHeight(math.abs(y) + PAD)
end

local function CreateManagerLabel(parent, text, size)
    local label = parent:CreateFontString(nil, "OVERLAY")
    RC:SetFont(label, size or 10, "OUTLINE")
    label:SetText(text or "")
    label:SetJustifyH("LEFT")
    return label
end

local function CreateManagerEditBox(parent, width)
    local edit = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    edit:SetSize(width or 180, 22)
    edit:SetBackdrop(RC.Config.Backdrop)
    edit:SetAutoFocus(false)
    edit:SetFontObject(GameFontNormal)
    edit:SetTextInsets(6, 6, 0, 0)
    edit:SetMaxLetters(96)
    RC:ApplyThemedPanel(edit, "input")
    edit:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(e) e:ClearFocus() end)
    return edit
end

function RaidSplit:_StyleLayoutManagerRow(row)
    if not row then return end
    local selected = row.layoutName and row.layoutName == self._selectedLayoutName
    local bg = selected and RC.Config.NavSelectedBg or (row.hovered and RC.Config.RowHover or RC.Config.InputBg)
    local border = selected and RC.Config.NavSelectedBorder or RC.Config.InputBorder
    row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 0.82)
    row:SetBackdropBorderColor(border.r, border.g, border.b, math.max(selected and 0.55 or 0.14, border.a or 0))
    if row.nameText then
        row.nameText:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
    end
    if row.bossText then
        row.bossText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
    end
end

function RaidSplit:CreateLayoutManagerPopup(mainFrame)
    if self._layoutManagerPopup then
        return self._layoutManagerPopup
    end

    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetSize(620, 430)
    popup:SetFrameStrata("DIALOG")
    popup:SetFrameLevel(260)
    popup:SetBackdrop(RC.Config.Backdrop)
    RC:ApplyThemedWindow(popup, "window")
    popup:EnableMouse(true)
    popup:SetClampedToScreen(true)
    popup:Hide()
    self._layoutManagerPopup = popup
    self._profilePopup = popup

    popup.title = CreateManagerLabel(popup, "RaidSplit Layout Manager", 14)
    popup.title:SetPoint("TOPLEFT", popup, "TOPLEFT", 14, -12)
    popup.subtitle = CreateManagerLabel(popup, "Save boss layouts, inspect missing players, and apply deliberate replacements.", 9)
    popup.subtitle:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -3)

    popup.close = RC:CreateCloseButton(popup, 22)
    popup.close:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -10, -10)
    popup.close:SetScript("OnClick", function() popup:Hide() end)

    local left = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    left:SetPoint("TOPLEFT", popup, "TOPLEFT", 12, -54)
    left:SetPoint("BOTTOMLEFT", popup, "BOTTOMLEFT", 12, 12)
    left:SetWidth(234)
    left:SetBackdrop(RC.Config.Backdrop)
    RC:ApplyThemedSection(left)
    popup.left = left

    local right = CreateFrame("Frame", nil, popup, "BackdropTemplate")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
    right:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -12, 12)
    right:SetBackdrop(RC.Config.Backdrop)
    RC:ApplyThemedSection(right)
    popup.right = right

    popup.listTitle = CreateManagerLabel(left, "Saved Layouts", 11)
    popup.listTitle:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -9)

    popup.rows = {}
    popup.visibleRows = 11
    for i = 1, popup.visibleRows do
        local row = CreateFrame("Button", nil, left, "BackdropTemplate")
        row:SetSize(214, 28)
        row:SetPoint("TOPLEFT", left, "TOPLEFT", 10, -30 - (i - 1) * 30)
        row:SetBackdrop(RC.Config.Backdrop)
        row.nameText = CreateManagerLabel(row, "", 10)
        row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 7, -4)
        row.nameText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row.bossText = CreateManagerLabel(row, "", 8)
        row.bossText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, 1)
        row.bossText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        row:SetScript("OnClick", function(r)
            if r.layoutName then
                self._selectedLayoutName = r.layoutName
                self:_RefreshProfilePopup(true)
            end
        end)
        row:SetScript("OnEnter", function(r) r.hovered = true; self:_StyleLayoutManagerRow(r) end)
        row:SetScript("OnLeave", function(r) r.hovered = false; self:_StyleLayoutManagerRow(r) end)
        popup.rows[i] = row
    end

    popup.prevBtn = MakeBtn(left, 48, 20, "Prev")
    popup.prevBtn:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 10, 8)
    popup.nextBtn = MakeBtn(left, 48, 20, "Next")
    popup.nextBtn:SetPoint("LEFT", popup.prevBtn, "RIGHT", 6, 0)
    popup.pageText = CreateManagerLabel(left, "", 9)
    popup.pageText:SetPoint("LEFT", popup.nextBtn, "RIGHT", 8, 0)
    popup.prevBtn:SetScript("OnClick", function()
        popup.page = math.max(1, (popup.page or 1) - 1)
        self:_RefreshProfilePopup(false)
    end)
    popup.nextBtn:SetScript("OnClick", function()
        popup.page = (popup.page or 1) + 1
        self:_RefreshProfilePopup(false)
    end)

    popup.detailTitle = CreateManagerLabel(right, "Layout Details", 11)
    popup.detailTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -10)

    popup.nameLabel = CreateManagerLabel(right, "Name", 9)
    popup.nameLabel:SetPoint("TOPLEFT", right, "TOPLEFT", 12, -36)
    popup.nameEdit = CreateManagerEditBox(right, 330)
    popup.nameEdit:SetPoint("TOPLEFT", popup.nameLabel, "BOTTOMLEFT", 0, -4)

    popup.bossLabel = CreateManagerLabel(right, "Boss / Encounter", 9)
    popup.bossLabel:SetPoint("TOPLEFT", popup.nameEdit, "BOTTOMLEFT", 0, -8)
    popup.bossEdit = CreateManagerEditBox(right, 330)
    popup.bossEdit:SetPoint("TOPLEFT", popup.bossLabel, "BOTTOMLEFT", 0, -4)

    popup.notesLabel = CreateManagerLabel(right, "Notes", 9)
    popup.notesLabel:SetPoint("TOPLEFT", popup.bossEdit, "BOTTOMLEFT", 0, -8)
    popup.notesEdit = CreateManagerEditBox(right, 330)
    popup.notesEdit:SetPoint("TOPLEFT", popup.notesLabel, "BOTTOMLEFT", 0, -4)

    popup.metaText = CreateManagerLabel(right, "", 9)
    popup.metaText:SetPoint("TOPLEFT", popup.notesEdit, "BOTTOMLEFT", 0, -9)
    popup.metaText:SetPoint("RIGHT", right, "RIGHT", -12, 0)

    popup.statusTitle = CreateManagerLabel(right, "Roster Check", 10)
    popup.statusTitle:SetPoint("TOPLEFT", popup.metaText, "BOTTOMLEFT", 0, -12)
    popup.statusLines = {}
    for i = 1, 8 do
        local line = CreateManagerLabel(right, "", 8)
        line:SetPoint("TOPLEFT", popup.statusTitle, "BOTTOMLEFT", 0, -4 - (i - 1) * 15)
        line:SetPoint("RIGHT", right, "RIGHT", -12, 0)
        popup.statusLines[i] = line
    end

    popup.saveBtn = MakeBtn(right, 94, 22, "Save Current")
    popup.saveBtn:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 70)
    popup.loadBtn = MakeBtn(right, 100, 22, "Load Selected")
    popup.loadBtn:SetPoint("LEFT", popup.saveBtn, "RIGHT", 6, 0)
    popup.smartBtn = MakeBtn(right, 122, 22, "Apply Replacements")
    popup.smartBtn:SetPoint("LEFT", popup.loadBtn, "RIGHT", 6, 0)

    popup.renameBtn = MakeBtn(right, 76, 22, "Rename")
    popup.renameBtn:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 40)
    popup.duplicateBtn = MakeBtn(right, 76, 22, "Duplicate")
    popup.duplicateBtn:SetPoint("LEFT", popup.renameBtn, "RIGHT", 6, 0)
    popup.assignBtn = MakeBtn(right, 88, 22, "Assign Boss")
    popup.assignBtn:SetPoint("LEFT", popup.duplicateBtn, "RIGHT", 6, 0)
    popup.deleteBtn = MakeBtn(right, 68, 22, "Delete")
    popup.deleteBtn:SetPoint("LEFT", popup.assignBtn, "RIGHT", 6, 0)

    popup.exportBtn = MakeBtn(right, 76, 22, "Export")
    popup.exportBtn:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 12, 10)
    popup.importBtn = MakeBtn(right, 76, 22, "Import")
    popup.importBtn:SetPoint("LEFT", popup.exportBtn, "RIGHT", 6, 0)
    AddButtonTooltip(popup.exportBtn, "Export", "Copy the selected layout as a string to share.")
    AddButtonTooltip(popup.importBtn, "Import", "Paste a Raid Split layout string. It is added as a new layout.")
    popup.exportBtn:SetScript("OnClick", function()
        local str, name = self:ExportLayoutString(self._selectedLayoutName)
        if str then ns.CopyBox:Show("Raid Split layout: " .. tostring(name), str) end
    end)
    popup.importBtn:SetScript("OnClick", function()
        ns.CopyBox:Prompt("Import Raid Split layout", "Paste a Raid Split layout string.", "Import", function(text)
            return self:ImportLayoutString(text)
        end)
    end)

    popup.saveBtn:SetScript("OnClick", function()
        local name = TrimText(popup.nameEdit:GetText())
        if name == "" then name = self:GetSuggestedLayoutName() end
        if self:SaveLayout(name, { bossName = popup.bossEdit:GetText(), notes = popup.notesEdit:GetText() }) then
            self:_RefreshProfilePopup(true)
        end
    end)
    popup.loadBtn:SetScript("OnClick", function()
        if self._selectedLayoutName then self:LoadLayout(self._selectedLayoutName) end
    end)
    popup.smartBtn:SetScript("OnClick", function()
        if self._selectedLayoutName then self:LoadLayout(self._selectedLayoutName, { applyReplacements = true }) end
    end)
    popup.renameBtn:SetScript("OnClick", function()
        if self:RenameLayout(self._selectedLayoutName, popup.nameEdit:GetText()) then self:_RefreshProfilePopup(true) end
    end)
    popup.duplicateBtn:SetScript("OnClick", function()
        if self:DuplicateLayout(self._selectedLayoutName) then self:_RefreshProfilePopup(true) end
    end)
    popup.assignBtn:SetScript("OnClick", function()
        if self:AssignLayoutBoss(self._selectedLayoutName, popup.bossEdit:GetText()) then self:_RefreshProfilePopup(true) end
    end)
    popup.deleteBtn:SetScript("OnClick", function()
        if self:DeleteLayout(self._selectedLayoutName) then self:_RefreshProfilePopup(true) end
    end)

    function popup:RefreshTheme()
        RC:ApplyThemedWindow(self, "window")
        RC:ApplyThemedSection(self.left)
        RC:ApplyThemedSection(self.right)
        for _, edit in ipairs({ self.nameEdit, self.bossEdit, self.notesEdit }) do
            RC:ApplyThemedPanel(edit, "input")
        end
        for _, button in ipairs({
            self.close, self.prevBtn, self.nextBtn, self.saveBtn, self.loadBtn, self.smartBtn,
            self.renameBtn, self.duplicateBtn, self.assignBtn, self.deleteBtn, self.exportBtn, self.importBtn,
        }) do
            if button and button.RefreshTheme then button:RefreshTheme() end
        end
        self.title:SetTextColor(RC.Config.HeaderText.r, RC.Config.HeaderText.g, RC.Config.HeaderText.b, RC.Config.HeaderText.a or 1)
        self.subtitle:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
        self.listTitle:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
        self.detailTitle:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
        self.metaText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
        self.statusTitle:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
        self.pageText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
        for _, row in ipairs(self.rows or {}) do
            RaidSplit:_StyleLayoutManagerRow(row)
        end
    end

    mainFrame:HookScript("OnHide", function() popup:Hide() end)
    popup:RefreshTheme()
    return popup
end

function RaidSplit:_WireProfileButton(btn, mainFrame)
    local popup = self:CreateLayoutManagerPopup(mainFrame)
    btn:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            RC:Print("Raid Split layout manager is unavailable during combat.")
            return
        end
        if popup:IsShown() then
            popup:Hide()
            return
        end
        popup:ClearAllPoints()
        local workspace = RC.GetModule and RC:GetModule("Workspace", true)
        local host = mainFrame.rcWorkspaceHosted and workspace and workspace.host
        if host then
            popup:SetParent(host)
            popup:SetFrameStrata(host:GetFrameStrata())
            popup:SetFrameLevel((host.header and host.header:GetFrameLevel() or host:GetFrameLevel()) + 100)
            popup:SetPoint("CENTER", host, "CENTER", 0, -24)
        else
            popup:SetParent(UIParent)
            popup:SetFrameStrata("DIALOG")
            popup:SetFrameLevel(260)
            popup:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -14, -38)
        end
        self:_RefreshProfilePopup(true)
        popup:Show()
    end)
end

function RaidSplit:_RefreshProfilePopup(forceFields)
    local popup = self._layoutManagerPopup or self._profilePopup
    if not popup then return end
    if popup.RefreshTheme then popup:RefreshTheme() end

    local layouts = self:GetSortedLayouts()
    if (not self._selectedLayoutName or not self:GetSavedLayout(self._selectedLayoutName)) and #layouts > 0 then
        self._selectedLayoutName = layouts[1].name
        forceFields = true
    end

    popup.page = math.max(1, popup.page or 1)
    local totalPages = math.max(1, math.ceil(#layouts / popup.visibleRows))
    if popup.page > totalPages then popup.page = totalPages end
    local startIndex = ((popup.page - 1) * popup.visibleRows) + 1

    for i, row in ipairs(popup.rows) do
        local record = layouts[startIndex + i - 1]
        if record then
            row.layoutName = record.name
            row.nameText:SetText(record.name)
            local boss = GetLayoutBossName(record.layout)
            local dateText = FormatLayoutTimestamp(record.layout.updatedAt or record.layout.timestamp)
            row.bossText:SetText((boss ~= "" and boss or "Unassigned") .. " - " .. dateText)
            row:Show()
        else
            row.layoutName = nil
            row:Hide()
        end
        self:_StyleLayoutManagerRow(row)
    end
    popup.pageText:SetText(string.format("%d/%d", popup.page, totalPages))

    local layout = self:GetSavedLayout(self._selectedLayoutName)
    if layout then
        if forceFields or popup.fieldLayoutName ~= self._selectedLayoutName then
            popup.nameEdit:SetText(self._selectedLayoutName or "")
            popup.bossEdit:SetText(GetLayoutBossName(layout))
            popup.notesEdit:SetText(layout.notes or "")
            popup.fieldLayoutName = self._selectedLayoutName
        end
        local boss = layout.boss or {}
        local encounter = boss.encounterID and (" | Encounter ID: " .. tostring(boss.encounterID)) or ""
        popup.metaText:SetText(string.format("Saved: %s | Players: %d | Boss: %s%s",
            FormatLayoutTimestamp(layout.updatedAt or layout.timestamp),
            CountLayoutRoster(layout),
            GetLayoutBossName(layout) ~= "" and GetLayoutBossName(layout) or "Unassigned",
            encounter
        ))

        local analysis = self:AnalyzeSavedLayout(layout)
        popup.statusTitle:SetText(string.format("Roster Check: %d present, %d missing", #analysis.present, #analysis.missing))
        for i, line in ipairs(popup.statusLines) do
            local missing = analysis.missing[i]
            if missing then
                if missing.replacement then
                    line:SetText(string.format("%s -> %s (%s)", missing.entry.name or "Unknown", missing.replacement.name or "Unknown", missing.reason or "match"))
                    line:SetTextColor(RC.Config.WarningColor.r, RC.Config.WarningColor.g, RC.Config.WarningColor.b, RC.Config.WarningColor.a or 1)
                else
                    line:SetText(string.format("%s -> manual replacement needed", missing.entry.name or "Unknown"))
                    line:SetTextColor(RC.Config.DangerColor.r, RC.Config.DangerColor.g, RC.Config.DangerColor.b, RC.Config.DangerColor.a or 1)
                end
                line:Show()
            elseif i == 1 and #analysis.missing == 0 then
                line:SetText("All saved players currently present.")
                line:SetTextColor(RC.Config.SuccessColor.r, RC.Config.SuccessColor.g, RC.Config.SuccessColor.b, RC.Config.SuccessColor.a or 1)
                line:Show()
            else
                line:SetText("")
                line:Hide()
            end
        end
    else
        if forceFields or not popup.fieldLayoutName then
            popup.nameEdit:SetText(self:GetSuggestedLayoutName())
            popup.bossEdit:SetText(self:GetCurrentBossInfo().name or "")
            popup.notesEdit:SetText("")
            popup.fieldLayoutName = nil
        end
        popup.metaText:SetText("No layout selected.")
        popup.statusTitle:SetText("Roster Check")
        for i, line in ipairs(popup.statusLines) do
            if i == 1 then
                line:SetText("Save the current RaidSplit layout to begin.")
                line:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
                line:Show()
            else
                line:Hide()
            end
        end
    end
end
