local _, ns = ...
local RC = ns.RC
local L = RC.L
---@class AutoMarker : AceModule, AceEvent-3.0
local AutoMarker = RC:NewModule("AutoMarker", "AceEvent-3.0")

local DEFAULT_TANK_ICON = 6   -- Square
local DEFAULT_HEALER_ICON = 2 -- Circle
local MYTHIC_DUNGEON_DIFFICULTIES = {
    [8] = true,  -- Mythic Keystone
    [23] = true, -- Mythic
}

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- The player has an inspect window open: never switch or clear the inspected unit then.
local function PlayerIsInspecting()
    local frame = _G.InspectFrame
    return frame ~= nil and frame.IsShown ~= nil and frame:IsShown() == true
end

local function ClearOwnInspect()
    if ClearInspectPlayer and not IsInCombat() and not PlayerIsInspecting() then
        pcall(ClearInspectPlayer)
    end
end


local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function CancelTimer(timer)
    if timer and timer.Cancel then
        timer:Cancel()
    end
end

local function Now()
    return GetTime and GetTime() or 0
end

local function IsChallengeModeActive()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok and not IsSecret(active) then
            return active == true
        end
    end
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok and not IsSecret(mapID) then
            return type(mapID) == "number" and mapID > 0
        end
    end
    return false
end

local function ToRaidIcon(icon)
    local iconNum = tonumber(icon)
    if not iconNum then
        return nil
    end
    iconNum = math.floor(iconNum + 0.5)
    if iconNum < 1 or iconNum > 8 then
        return nil
    end
    return iconNum
end

local function NormalizeRole(roleValue)
    if type(roleValue) ~= "string" or IsSecret(roleValue) then
        return nil
    end
    if roleValue == "DAMAGER" then
        return "DPS"
    end
    if roleValue == "NONE" or roleValue == "" then
        return nil
    end
    return roleValue
end

function AutoMarker:OnInitialize()
    self.db = RC.db.profile
    self.roleMarkButton = nil
    self.inspectSpecCache = {}
    self.inspectRoleCache = {}
    self.inspectQueue = {}
    self.inspectQueuedGUIDs = {}
    self.pendingInspectGUID = nil
    self.pendingInspectUnit = nil
    self.autoMarkQueued = false
    self.autoMarkPendingAfterCombat = false
    self.autoMarkTimer = nil
    self.lastRolePlan = nil
    self.layoutModeActive = false
    self.rolePreviewTimer = nil
    self.roleMarkSettlingUntil = nil
    self.roleMarkCycleToken = self.db.autoMarkRolePromptCycleToken
    self.roleMarkCycleDismissed = self.db.autoMarkRolePromptDismissed == true
    self.roleMarkChallengeActive = false
end

function AutoMarker:OnEnable()
    self.db = RC.db.profile
    self:UpdateEvents()
    self:RefreshRoleMarkPromptCycle("ENABLE")
    self:ScheduleAutoPartyMark(0.5)
end

function AutoMarker:OnDisable()
    self:UnregisterAllEvents()
    CancelTimer(self.autoMarkTimer)
    self.autoMarkTimer = nil
    CancelTimer(self.rolePreviewTimer)
    self.rolePreviewTimer = nil
    self.autoMarkQueued = false
    self.autoMarkPendingAfterCombat = false
    self.pendingInspectGUID = nil
    self.pendingInspectUnit = nil
    if self.roleMarkButton and not IsInCombat() then
        self:SetRoleMarkButtonActive(self.roleMarkButton, false)
    end
    if self.inspectWindowTimer then
        self.inspectWindowTimer:Cancel()
        self.inspectWindowTimer = nil
    end
    ClearOwnInspect()
end

function AutoMarker:IsRoleMarkingEnabled()
    if not self.db then
        return false
    end
    local markTanks = self.db.autoMarkTanks ~= false
    local markHealers = self.db.autoMarkHealers ~= false
    return markTanks or markHealers
end

function AutoMarker:GetRoleMarkDungeonToken()
    local okInstance, inInstance, instanceType = pcall(IsInInstance)
    if not okInstance or IsSecret(inInstance) or IsSecret(instanceType)
        or not inInstance or instanceType ~= "party" then
        return nil
    end

    if not GetInstanceInfo then
        return "party:unknown"
    end
    local okInfo, instanceName, infoType, difficultyID, _, _, _, _, instanceID = pcall(GetInstanceInfo)
    if not okInfo or IsSecret(infoType) or infoType ~= "party" then
        return nil
    end
    if IsSecret(difficultyID) or IsSecret(instanceID) or IsSecret(instanceName) then
        return nil
    end
    difficultyID = tonumber(difficultyID)
    if not MYTHIC_DUNGEON_DIFFICULTIES[difficultyID] and not IsChallengeModeActive() then
        return nil
    end
    local identity = instanceID or instanceName
    if identity == nil or identity == "" then
        return "party:mythic"
    end
    return "party:" .. tostring(identity)
end

function AutoMarker:SetRoleMarkPromptCycle(token, dismissed)
    self.roleMarkCycleToken = token
    self.roleMarkCycleDismissed = dismissed == true
    if self.db then
        self.db.autoMarkRolePromptCycleToken = token
        self.db.autoMarkRolePromptDismissed = self.roleMarkCycleDismissed
    end
end

function AutoMarker:RefreshRoleMarkPromptCycle(event)
    local token = self:GetRoleMarkDungeonToken()
    local challengeActive = IsChallengeModeActive()
    local newKeyReady = event == "CHALLENGE_MODE_COMPLETED" or event == "CHALLENGE_MODE_RESET"
    if event == "CHALLENGE_MODE_START" then
        challengeActive = true
    elseif newKeyReady then
        challengeActive = false
    end

    if not token then
        self.roleMarkChallengeActive = false
        if self.db.autoMarkRolesDungeonOnly ~= false then
            self:SetRoleMarkPromptCycle(nil, false)
        end
        return nil
    end

    if token ~= self.roleMarkCycleToken then
        self:SetRoleMarkPromptCycle(token, false)
    end
    if newKeyReady then
        self:SetRoleMarkPromptCycle(token, false)
    elseif challengeActive then
        self:SetRoleMarkPromptCycle(token, true)
    end
    self.roleMarkChallengeActive = challengeActive
    return token
end

function AutoMarker:ShouldAutoMarkParty()
    if not self:IsRoleMarkingEnabled() then
        return false
    end
    if not IsInGroup() then
        return false
    end
    if IsInRaid() then
        return false
    end
    if self.db.autoMarkRolesDungeonOnly ~= false then
        if not self:GetRoleMarkDungeonToken() then
            return false
        end
    end
    return true
end

function AutoMarker:FindPartyUnitByGUID(guid)
    if not guid then
        return nil
    end

    if UnitGUID("player") == guid then
        return "player"
    end

    local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
    for i = 1, count do
        local unit = "party" .. i
        if UnitExists(unit) and UnitGUID(unit) == guid then
            return unit
        end
    end

    return nil
end

function AutoMarker:QueueInspectUnit(unit)
    if not self:ShouldAutoMarkParty() then
        return false
    end
    if IsInCombat() then
        self.autoMarkPendingAfterCombat = true
        return false
    end
    if not unit or UnitIsUnit(unit, "player") then
        return false
    end
    if not UnitExists(unit) or not UnitIsPlayer(unit) then
        return false
    end
    if not CanInspect or not CanInspect(unit, false) or not NotifyInspect then
        return false
    end

    local guid = UnitGUID(unit)
    if not guid then
        return false
    end
    if self.inspectSpecCache and self.inspectSpecCache[guid] then
        return false
    end
    if self.inspectQueuedGUIDs and self.inspectQueuedGUIDs[guid] then
        return false
    end
    if self.pendingInspectGUID and self.pendingInspectGUID == guid then
        return false
    end

    table.insert(self.inspectQueue, { unit = unit, guid = guid })
    self.inspectQueuedGUIDs[guid] = true
    self:ProcessInspectQueue()
    return true
end

function AutoMarker:ProcessInspectQueue()
    if PlayerIsInspecting() then
        if not self.inspectWindowTimer then
            self.inspectWindowTimer = C_Timer.NewTicker(1, function()
                if PlayerIsInspecting() then return end
                self.inspectWindowTimer:Cancel()
                self.inspectWindowTimer = nil
                self:ProcessInspectQueue()
            end)
        end
        return false
    end
    if IsInCombat() then
        self.autoMarkPendingAfterCombat = true
        self.inspectClearPending = self.pendingInspectGUID ~= nil or self.inspectClearPending
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
        if entry and entry.guid then
            self.inspectQueuedGUIDs[entry.guid] = nil
        end

        local unit = entry and entry.unit
        local guid = entry and entry.guid
        if guid then
            if not unit or not UnitExists(unit) or UnitGUID(unit) ~= guid then
                unit = self:FindPartyUnitByGUID(guid)
            end
            if unit and UnitExists(unit) and UnitGUID(unit) == guid and CanInspect and CanInspect(unit, false) then
                self.pendingInspectGUID = guid
                self.pendingInspectUnit = unit
                local okNotify = pcall(NotifyInspect, unit)
                if okNotify then
                    return true
                end
                self.pendingInspectGUID = nil
                self.pendingInspectUnit = nil
                self.autoMarkPendingAfterCombat = true
                return false
            end
        end
    end
end

function AutoMarker:OnInspectReady(_, guid)
    -- INSPECT_READY also fires for the player's own inspects. Only react to
    -- the one this module asked for, or it would wipe the open Inspect window.
    if not guid or guid ~= self.pendingInspectGUID then
        return
    end
    if IsInCombat() then
        self.pendingInspectGUID = nil
        self.pendingInspectUnit = nil
        self.inspectClearPending = true
        self.autoMarkPendingAfterCombat = true
        return
    end

    local unit
    if self.pendingInspectUnit and UnitExists(self.pendingInspectUnit) and UnitGUID(self.pendingInspectUnit) == guid then
        unit = self.pendingInspectUnit
    else
        unit = self:FindPartyUnitByGUID(guid)
    end

    if unit and GetInspectSpecialization then
        local specID = GetInspectSpecialization(unit)
        if specID and specID > 0 then
            self.inspectSpecCache[guid] = specID
            if GetSpecializationRoleByID then
                local specRole = NormalizeRole(GetSpecializationRoleByID(specID))
                if specRole then
                    self.inspectRoleCache[guid] = specRole
                end
            end
        end
    end

    ClearOwnInspect()
    self.pendingInspectGUID = nil
    self.pendingInspectUnit = nil

    self:ProcessInspectQueue()
    self:ScheduleAutoPartyMark(0.05)
end

function AutoMarker:InstallRoleMarkCombatDriver(button)
    if not button or not RegisterStateDriver then
        return false
    end
    RegisterStateDriver(button, "visibility", "[combat] hide; show")
    return true
end

function AutoMarker:SetRoleMarkButtonActive(button, active)
    if not button or IsInCombat() then
        return false
    end
    active = active and true or false
    button.rolePromptVisible = active
    button:SetAlpha(active and 1 or 0)
    button:EnableMouse(active)
    return true
end

function AutoMarker:HandleRoleMarkPostClick()
    if self.layoutModeActive or IsInCombat() then
        return false
    end

    self:SetRoleMarkPromptCycle(self.roleMarkCycleToken or self:GetRoleMarkDungeonToken(), true)
    if self.roleMarkButton then
        self:SetRoleMarkButtonActive(self.roleMarkButton, false)
    end

    local settleDelay = 1
    self.roleMarkSettlingUntil = Now() + settleDelay
    self:ScheduleAutoPartyMark(settleDelay)
    return true
end

function AutoMarker:GetRoleMarkButton()
    if self.roleMarkButton then
        return self.roleMarkButton
    end

    local btn = CreateFrame(
        "Button",
        "RC_RoleMarkButton",
        UIParent,
        "BackdropTemplate,SecureActionButtonTemplate,SecureHandlerStateTemplate"
    )
    if not btn then
        return nil
    end

    btn:SetSize(224, 48)
    btn:SetScale(math.max(0.6, math.min(1.6, tonumber(self.db.autoMarkRoleButtonScale) or 1)))
    if self.db.autoMarkRoleButtonPos then
        btn:SetPoint(unpack(self.db.autoMarkRoleButtonPos))
    else
        btn:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
    btn:SetFrameStrata("DIALOG")
    btn:SetMovable(true)
    if btn.SetClampedToScreen then
        btn:SetClampedToScreen(true)
    end
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetAttribute("type1", "macro")
    btn:SetAttribute("macrotext1", "")
    btn:SetAlpha(0)
    btn:EnableMouse(false)
    self:InstallRoleMarkCombatDriver(btn)
    RC:SkinFrame(btn)
    RC:ApplyThemedPanel(btn, "button", { alpha = 0.96 })

    btn.accent = btn:CreateTexture(nil, "ARTWORK")
    btn.accent:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    btn.accent:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
    btn.accent:SetWidth(3)

    btn.title = btn:CreateFontString(nil, "OVERLAY")
    RC:SetFont(btn.title, 13, "OUTLINE")
    btn.title:SetPoint("TOPLEFT", btn, "TOPLEFT", 12, -8)
    btn.title:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -10, -8)
    btn.title:SetJustifyH("LEFT")

    btn.status = btn:CreateFontString(nil, "OVERLAY")
    RC:SetFont(btn.status, 10, "OUTLINE")
    btn.status:SetPoint("TOPLEFT", btn.title, "BOTTOMLEFT", 0, -3)
    btn.status:SetPoint("TOPRIGHT", btn.title, "BOTTOMRIGHT", 0, -3)
    btn.status:SetJustifyH("LEFT")

    btn:SetScript("OnDragStart", function(frame)
        if RC.IsUILayoutUnlocked and RC:IsUILayoutUnlocked() then
            frame.rcMoving = true
            frame:StartMoving()
        end
    end)
    btn:SetScript("OnDragStop", function(frame)
        if not frame.rcMoving then return end
        frame.rcMoving = nil
        frame:StopMovingOrSizing()
        local point, _, relativePoint, x, y = frame:GetPoint()
        self.db.autoMarkRoleButtonPos = { point, "UIParent", relativePoint, x, y }
    end)
    btn:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L["RaidControl Role Marks"], 1, 1, 1)
        GameTooltip:AddLine(L["One secure click applies the prepared tank and healer marks."], 0.78, 0.84, 0.90, true)
        GameTooltip:AddLine(L["The reminder appears once before the key and stays dismissed until the next key."], 0.65, 0.72, 0.78, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    btn:SetScript("PostClick", function()
        self:HandleRoleMarkPostClick()
    end)

    self.roleMarkButton = btn
    self:RefreshTheme()
    return btn
end

function AutoMarker:ApplyRoleMarkButtonScale(rawScale)
    local scale = math.max(0.6, math.min(1.6, tonumber(rawScale) or 1))
    self.db.autoMarkRoleButtonScale = scale
    local button = self:GetRoleMarkButton()
    if not button then
        return scale
    end
    if RC.SetScalePreserveCenter then
        RC:SetScalePreserveCenter(button, scale, function(frame)
            local point, _, relativePoint, x, y = frame:GetPoint(1)
            self.db.autoMarkRoleButtonPos = { point, "UIParent", relativePoint, x, y }
        end)
    else
        button:SetScale(scale)
    end
    return scale
end

function AutoMarker:ResolveUnitRole(unit)
    local role
    if UnitGroupRolesAssigned then
        local ok, assignedRole = pcall(UnitGroupRolesAssigned, unit)
        if ok then
            role = NormalizeRole(assignedRole)
        end
    end

    -- Assigned party roles are authoritative for a Mythic+ group and avoid
    -- inspecting every member before each key.
    if role then
        return role
    end

    if IsInRaid() and UnitInRaid and GetRaidRosterInfo then
        local raidIndex = UnitInRaid(unit)
        if raidIndex then
            local _, _, _, _, _, _, _, _, _, raidRole = GetRaidRosterInfo(raidIndex)
            role = NormalizeRole(raidRole)
        end
    end

    local guid = UnitGUID(unit)
    if not role and guid and self.inspectRoleCache then
        role = self.inspectRoleCache[guid]
    end

    local specID = nil
    if UnitIsUnit(unit, "player") then
        if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecializationInfo then
            local specIndex = C_SpecializationInfo.GetSpecialization()
            if specIndex then
                specID = C_SpecializationInfo.GetSpecializationInfo(specIndex)
            end
        end
    else
        if guid and self.inspectSpecCache then
            specID = self.inspectSpecCache[guid]
        end

        if (not specID) and GetInspectSpecialization then
            local inspectedSpec = GetInspectSpecialization(unit)
            if inspectedSpec and inspectedSpec > 0 then
                specID = inspectedSpec
                if guid then
                    self.inspectSpecCache[guid] = specID
                end
            elseif not InCombatLockdown() then
                self:QueueInspectUnit(unit)
            end
        end
    end

    if specID and GetSpecializationRoleByID then
        local specRole = NormalizeRole(GetSpecializationRoleByID(specID))
        if specRole == "TANK" or specRole == "HEALER" then
            role = specRole
        elseif not role then
            role = specRole
        end
        if guid and specRole then
            self.inspectRoleCache[guid] = specRole
        end
    end

    if not role and GetPartyAssignment and GetPartyAssignment("MAINTANK", unit) then
        role = "TANK"
    end

    return role
end

function AutoMarker:GetConfiguredRoleIcons()
    local tankIcon = ToRaidIcon(self.db.autoMarkTanksIcon) or DEFAULT_TANK_ICON
    local healerIcon = ToRaidIcon(self.db.autoMarkHealersIcon) or DEFAULT_HEALER_ICON
    if tankIcon == healerIcon then
        healerIcon = tankIcon ~= DEFAULT_HEALER_ICON and DEFAULT_HEALER_ICON or 1
    end
    return tankIcon, healerIcon
end

function AutoMarker:GetPartyUnits()
    local units = { "player" }
    local count = math.max(0, math.min(4, GetNumSubgroupMembers and GetNumSubgroupMembers() or 0))
    for index = 1, count do
        local unit = "party" .. index
        if UnitExists(unit) then
            units[#units + 1] = unit
        end
    end
    return units
end

function AutoMarker:GetUnitRaidTarget(unit)
    if not GetRaidTargetIndex then
        return nil
    end
    local ok, icon = pcall(GetRaidTargetIndex, unit)
    if not ok or IsSecret(icon) then
        return nil
    end
    return ToRaidIcon(icon)
end

function AutoMarker:BuildRoleMarkPlan()
    local plan = {
        active = self:ShouldAutoMarkParty(),
        assignments = {},
        missing = {},
        unresolved = {},
        needsAction = false,
        complete = false,
    }
    if not plan.active then
        return plan
    end

    local markTanks = self.db.autoMarkTanks ~= false
    local markHealers = self.db.autoMarkHealers ~= false
    local tankIcon, healerIcon = self:GetConfiguredRoleIcons()
    local roleUnits = {}
    for _, unit in ipairs(self:GetPartyUnits()) do
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
            local role = self:ResolveUnitRole(unit)
            if (role == "TANK" or role == "HEALER") and not roleUnits[role] then
                roleUnits[role] = unit
            end
        end
    end

    local function AddAssignment(role, enabled, icon, label)
        if not enabled then
            return
        end
        local unit = roleUnits[role]
        if not unit then
            plan.unresolved[#plan.unresolved + 1] = label
            return
        end
        local current = self:GetUnitRaidTarget(unit)
        local assignment = {
            role = role,
            label = label,
            unit = unit,
            icon = icon,
            current = current,
        }
        plan.assignments[#plan.assignments + 1] = assignment
        if current ~= icon then
            plan.missing[#plan.missing + 1] = assignment
        end
    end

    AddAssignment("TANK", markTanks, tankIcon, L["Tank"])
    AddAssignment("HEALER", markHealers, healerIcon, L["Healer"])
    plan.needsAction = #plan.missing > 0
    plan.complete = #plan.missing == 0 and #plan.unresolved == 0
    return plan
end

function AutoMarker:BuildRoleMarkMacro(plan)
    local lines = {}
    for _, assignment in ipairs(plan and plan.missing or {}) do
        local unit = assignment.unit
        if unit == "player" or (type(unit) == "string" and unit:match("^party[1-4]$")) then
            lines[#lines + 1] = string.format("/tm [@%s,exists,nodead] %d", unit, assignment.icon)
        end
        if #lines >= 2 then
            break
        end
    end
    return table.concat(lines, "\n")
end

function AutoMarker:UpdateRoleMarkButtonText(plan)
    local button = self.roleMarkButton
    if not button then
        return
    end
    if self.layoutModeActive then
        button.title:SetText(L["MARK TANK + HEALER"])
        button.status:SetText(L["Secure M+ role-mark reminder"])
        return
    end
    if plan.complete then
        button.title:SetText(L["ROLES MARKED"])
        button.status:SetText(L["Tank and healer marks verified"])
        return
    end
    if plan.needsAction then
        local labels = {}
        for _, assignment in ipairs(plan.missing) do
            labels[#labels + 1] = assignment.label
        end
        button.title:SetText(string.format(L["MARK %s"], table.concat(labels, " + "):upper()))
        button.status:SetText(L["Click once before the key starts"])
        return
    end
    button.title:SetText(L["WAITING FOR ROLES"])
    button.status:SetText(string.format(L["%s role not assigned"], table.concat(plan.unresolved, " + ")))
end

function AutoMarker:ShouldShowRoleMarkButton(plan)
    if IsInCombat() then
        return false
    end
    if self.layoutModeActive then
        return true
    end
    if not plan or plan.active ~= true or plan.needsAction ~= true then
        return false
    end
    if self.roleMarkChallengeActive or self.roleMarkCycleDismissed then
        return false
    end
    return true
end

function AutoMarker:ApplyRoleMarkPlan(plan)
    plan = plan or self:BuildRoleMarkPlan()
    self.lastRolePlan = plan
    if IsInCombat() then
        self.autoMarkPendingAfterCombat = true
        return false
    end

    local shouldShow = self:ShouldShowRoleMarkButton(plan)
    if not self.roleMarkButton and not shouldShow then
        return true
    end

    local button = self:GetRoleMarkButton()
    if not button then
        return false
    end
    local macro = self.layoutModeActive and "" or self:BuildRoleMarkMacro(plan)
    if button.preparedMacro ~= macro then
        button:SetAttribute("type1", "macro")
        button:SetAttribute("macrotext1", macro)
        button.preparedMacro = macro
    end
    self:ApplyRoleMarkButtonScale(self.db.autoMarkRoleButtonScale or 1)
    self:UpdateRoleMarkButtonText(plan)

    local wasShown = button.rolePromptVisible == true
    if wasShown ~= shouldShow then
        self:SetRoleMarkButtonActive(button, shouldShow)
    end
    return true
end

function AutoMarker:EvaluateRoleMarks()
    local plan = self:BuildRoleMarkPlan()
    self:ApplyRoleMarkPlan(plan)
    return plan
end

function AutoMarker:MarkTanksAndHealers(silent)
    local plan = self:EvaluateRoleMarks()
    local markedTanks, markedHealers = 0, 0
    for _, assignment in ipairs(plan.assignments or {}) do
        if assignment.current == assignment.icon then
            if assignment.role == "TANK" then
                markedTanks = markedTanks + 1
            elseif assignment.role == "HEALER" then
                markedHealers = markedHealers + 1
            end
        end
    end
    if not silent and not plan.complete then
        if plan.needsAction then
            RC:Print(L["Click the RaidControl role-mark button to apply the prepared marks."])
        elseif plan.active then
            RC:Print(L["Waiting for the party tank and healer roles to be assigned."])
        end
    end
    return plan.complete == true, markedTanks, markedHealers
end

function AutoMarker:RefreshTheme()
    local button = self.roleMarkButton
    if not button then
        return
    end
    RC:ApplyThemedPanel(button, "button", { alpha = 0.96 })
    local accent = RC.Config.Accent or RC.Config.Selected or { r = 0.10, g = 0.78, b = 0.66, a = 1 }
    local text = RC.Config.WhiteText or RC.Config.Text or { r = 1, g = 1, b = 1, a = 1 }
    local muted = RC.Config.MutedText or text
    button.accent:SetColorTexture(accent.r, accent.g, accent.b, accent.a or 1)
    button.title:SetTextColor(text.r, text.g, text.b, text.a or 1)
    button.status:SetTextColor(muted.r, muted.g, muted.b, muted.a or 1)
end

function AutoMarker:ResetRoleMarkPosition()
    if IsInCombat() then
        RC:Print(L["Role-mark position cannot be reset during combat."])
        return false
    end
    self.db.autoMarkRoleButtonPos = nil
    local button = self:GetRoleMarkButton()
    button:ClearAllPoints()
    button:SetPoint("TOP", UIParent, "TOP", 0, -180)
    return true
end

function AutoMarker:BeginLayoutMode(persistent)
    if IsInCombat() then
        return false
    end
    if persistent then
        CancelTimer(self.rolePreviewTimer)
        self.rolePreviewTimer = nil
    end
    self.roleMarkSettlingUntil = nil
    self.layoutModeActive = true
    self:ApplyRoleMarkPlan(self.lastRolePlan or self:BuildRoleMarkPlan())
    return true
end

function AutoMarker:EndLayoutMode()
    CancelTimer(self.rolePreviewTimer)
    self.rolePreviewTimer = nil
    self.layoutModeActive = false
    self.roleMarkSettlingUntil = nil
    self:ScheduleAutoPartyMark(0)
end

function AutoMarker:PreviewRoleMarkButton()
    if IsInCombat() then
        RC:Print(L["Role-mark preview is unavailable during combat."])
        return false
    end
    local layoutMode = RC:GetModule("LayoutMode", true)
    if layoutMode and layoutMode.IsActive and layoutMode:IsActive() then
        return self:BeginLayoutMode(true)
    end
    CancelTimer(self.rolePreviewTimer)
    self.rolePreviewTimer = nil
    self:BeginLayoutMode()
    if C_Timer and C_Timer.NewTimer then
        self.rolePreviewTimer = C_Timer.NewTimer(15, function()
            self.rolePreviewTimer = nil
            self:EndLayoutMode()
        end)
    end
    return true
end

function AutoMarker:ApplySettings()
    self.db = RC.db.profile
    self:UpdateEvents()
    self:ScheduleAutoPartyMark(0)
end

function AutoMarker:MarkRolesNow()
    return self:MarkTanksAndHealers()
end

-- Compatibility wrappers for older callers.
function AutoMarker:ScanRosterForRoles()
    return self:MarkTanksAndHealers()
end

function AutoMarker:ScheduleAutoPartyMark(delay)
    CancelTimer(self.autoMarkTimer)
    self.autoMarkTimer = nil
    self.autoMarkQueued = true
    local function Run()
        self.autoMarkTimer = nil
        self:RunAutoPartyMark()
    end
    delay = math.max(0, tonumber(delay) or 0)
    if C_Timer and C_Timer.NewTimer then
        self.autoMarkTimer = C_Timer.NewTimer(delay, Run)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(delay, Run)
    else
        Run()
    end
end

function AutoMarker:RunAutoPartyMark()
    self.autoMarkQueued = false
    if IsInCombat() then
        self.autoMarkPendingAfterCombat = true
        return false
    end
    local settleDelay = (self.roleMarkSettlingUntil or 0) - Now()
    if settleDelay > 0 then
        if C_Timer and (C_Timer.NewTimer or C_Timer.After) then
            self:ScheduleAutoPartyMark(settleDelay)
            return false
        end
    end
    self.roleMarkSettlingUntil = nil
    self.autoMarkPendingAfterCombat = false
    self:EvaluateRoleMarks()
    return true
end

function AutoMarker:OnAutoMarkEvent(event)
    self:RefreshRoleMarkPromptCycle(event)
    local delay = event == "PLAYER_ENTERING_WORLD" and 0.8 or 0.1
    if event == "RAID_TARGET_UPDATE" then
        delay = math.max(delay, (self.roleMarkSettlingUntil or 0) - Now())
    end
    self:ScheduleAutoPartyMark(delay)
end

function AutoMarker:OnPlayerRegenEnabled()
    if self.inspectClearPending then
        ClearOwnInspect()
    end
    self.inspectClearPending = nil
    if self.autoMarkPendingAfterCombat then
        self.autoMarkPendingAfterCombat = false
    end
    self:ProcessInspectQueue()
    self:ScheduleAutoPartyMark(0.05)
end

function AutoMarker:UpdateEvents()
    self:UnregisterAllEvents()
    if not self:IsRoleMarkingEnabled() then
        if self.roleMarkButton and not IsInCombat() then
            self:SetRoleMarkButtonActive(self.roleMarkButton, false)
        end
        return
    end

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnAutoMarkEvent")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnAutoMarkEvent")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnAutoMarkEvent")
    self:RegisterEvent("PLAYER_ROLES_ASSIGNED", "OnAutoMarkEvent")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnAutoMarkEvent")
    self:RegisterEvent("RAID_TARGET_UPDATE", "OnAutoMarkEvent")
    self:RegisterEvent("CHALLENGE_MODE_START", "OnAutoMarkEvent")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnAutoMarkEvent")
    self:RegisterEvent("CHALLENGE_MODE_RESET", "OnAutoMarkEvent")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
    self:RegisterEvent("INSPECT_READY", "OnInspectReady")
end
