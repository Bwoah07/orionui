local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
---@class ActionStrip : AceModule, AceEvent-3.0
local ActionStrip = RC:NewModule("ActionStrip", "AceEvent-3.0")

local ACTION_W = 54
local ACTION_H = 22
local ACTION_SPACING = 4
local MARKER_W = 24
local MARKER_H = 26
local MARKER_SPACING = 0
local MARKER_ICON_SIZE = 24
local PAD = 5
local ROW_SPACING = 4

local function ClampNumber(value, minValue, maxValue, fallback)
    local number = tonumber(value) or fallback or minValue
    if number < minValue then
        return minValue
    elseif number > maxValue then
        return maxValue
    end
    return number
end

local function NormalizeLayout(layout)
    if layout ~= "two_rows" and layout ~= "markers_row" then
        return "single"
    end
    return layout
end

local function NormalizeMarkerPosition(position)
    if position ~= "last" then
        return "first"
    end
    return "last"
end

local function NormalizeModifier(modifier)
    modifier = tostring(modifier or "SHIFT"):upper()
    if modifier ~= "CTRL" and modifier ~= "ALT" then
        modifier = "SHIFT"
    end
    return modifier
end

local function BuildTargetClearMacro()
    return string.format("%s 0", _G.SLASH_TARGET_MARKER1 or "/tm")
end

local function BuildWorldClearMacro()
    return string.format("%s 0", _G.SLASH_CLEAR_WORLD_MARKER1 or "/cwm")
end

local function ApplyWorldMarkerModifier(btn, markerIndex)
    if not btn then
        return
    end
    local profile = RC.db and RC.db.profile or {}
    local modifier = NormalizeModifier(profile.worldMarkerModifier)
    RC:ConfigureMarkerActionButton(btn, markerIndex, profile.enableTargetMarkers ~= false, profile.enableWorldMarkers ~= false, modifier)
end

local function RegisterSecureClicks(btn)
    btn:RegisterForClicks("AnyDown")
    btn:SetAttribute("useOnKeyDown", true)
end

function ActionStrip:OnInitialize()
    self.db = RC.db.profile
end

function ActionStrip:OnEnable()
    self:CreateStripFrame()
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
    self:RegisterEvent("PLAYER_DIFFICULTY_CHANGED", "UpdateDifficultyLabel")
    self:UpdateVisibility()
end

function ActionStrip:OnPlayerRegenEnabled()
    if self.pendingScale then
        local scale = self.pendingScale
        self.pendingScale = nil
        self:UpdateScale(scale)
    end
    if self.pendingRefresh then
        self.pendingRefresh = nil
        self:RefreshButtonVisibility()
    end
    if self.pendingVisibility then
        self.pendingVisibility = nil
        self:UpdateVisibility()
    end
end

-- ============================================================================
-- PULL BUTTON STATE HELPERS
-- ============================================================================

function ActionStrip:RefreshPullButton()
    if not self.pullBtn or not self.pullBtn.textIcon then return end
    local Control = RC:GetModule("Control", true)
    if Control and Control.pullActive then
        self.pullBtn.textIcon:SetText(L["Cancel"])
        self.pullBtn.customBg = true
        self.pullBtn:SetBackdropColor(0.6, 0.15, 0.15, 0.9)
        self.pullBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
    else
        self.pullBtn.textIcon:SetText(L["Pull"])
        self.pullBtn.customBg = nil
        self.pullBtn:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
        self.pullBtn:SetBackdropBorderColor(RC:GetControlBorderColor())
    end
end

function ActionStrip:UpdateDifficultyLabel()
    if not self.diffBtn or not self.diffBtn.textIcon then return end
    local Control = RC:GetModule("Control", true)
    if Control and Control.GetDifficultyLabel then
        self.diffBtn.textIcon:SetText(Control:GetDifficultyLabel())
    else
        self.diffBtn.textIcon:SetText(L["Diff"])
    end
end

-- ============================================================================
-- MOUSEOVER FADE LOGIC
-- ============================================================================

local function Strip_OnEnter()
    if ActionStrip.frame then
        ActionStrip.frame:SetAlpha(1)
    end
end

local function Strip_OnLeave()
    if ActionStrip.frame and RC.db.profile.actionStripMouseover then
        if not ActionStrip.frame:IsMouseOver() then
            ActionStrip.frame:SetAlpha(0)
        end
    end
end

function ActionStrip:RefreshMouseoverFade()
    if not self.frame then return end
    if self.db.actionStripMouseover then
        if not self.frame:IsMouseOver() then
            self.frame:SetAlpha(0)
        else
            self.frame:SetAlpha(1)
        end
    else
        self.frame:SetAlpha(1)
    end
end

-- ============================================================================
-- FRAME CONSTRUCTION
-- ============================================================================

local function RestoreButton(btn)
    local br, bg, bb = RC:GetBorderColor()
    btn:SetBackdropBorderColor(br, bg, bb, 0.06)
    if not btn.customBg then
        btn:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
    end
    if btn.textIcon then
        btn.textIcon:SetTextColor(RC:GetButtonTextColor())
    end
end

local function ApplyActionButtonScripts(btn, text, onEnterExtra, onLeaveExtra)
    btn:SetScript("OnEnter", function()
        Strip_OnEnter()
        btn:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.48)
        if not btn.customBg then
            btn:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
        end
        text:SetTextColor(1, 1, 1)
        if onEnterExtra then
            onEnterExtra()
        end
    end)
    btn:SetScript("OnLeave", function()
        if onLeaveExtra then
            onLeaveExtra()
        end
        RestoreButton(btn)
        Strip_OnLeave()
    end)
    btn:SetScript("OnMouseDown", function()
        if not btn.customBg then
            btn:SetBackdropColor(RC.Config.ButtonPressed.r, RC.Config.ButtonPressed.g, RC.Config.ButtonPressed.b, 1)
        end
    end)
    btn:SetScript("OnMouseUp", function()
        if btn.customBg then return end
        if btn:IsMouseOver() then
            btn:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
        else
            btn:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
        end
    end)
end

function ActionStrip:CreateActionButton(label, onClick)
    local btn = CreateFrame("Button", nil, self.frame, "BackdropTemplate")
    btn.rcBorderMinAlpha = 0.06
    btn:SetSize(self:GetActionButtonSize())
    RC:SkinFrame(btn)
    RC:SetFrameThemeRole(btn, "ButtonBg")
    btn:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
    btn:SetBackdropBorderColor(RC:GetControlBorderColor())

    local text = btn:CreateFontString(nil, "OVERLAY")
    RC:SetFont(text, 11, "OUTLINE")
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    text:SetText(label)
    text:SetTextColor(RC:GetButtonTextColor())
    RC:RegisterTextColor(text, "button")
    btn.textIcon = text

    btn:SetScript("OnClick", onClick)
    ApplyActionButtonScripts(btn, text)
    RestoreButton(btn)
    table.insert(self.buttons, btn)
    return btn
end

function ActionStrip:CreateSecureActionButton(label, macroText, tooltipTitle, tooltipText)
    local btn = CreateFrame("Button", nil, self.frame, "SecureActionButtonTemplate,BackdropTemplate")
    btn.rcBorderMinAlpha = 0.06
    btn:SetSize(self:GetActionButtonSize())
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("useOnKeyDown", false)
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", macroText)
    btn:SetAttribute("type1", "macro")
    btn:SetAttribute("macrotext1", macroText)
    RC:SkinFrame(btn)
    RC:SetFrameThemeRole(btn, "ButtonBg")
    btn:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
    btn:SetBackdropBorderColor(RC:GetControlBorderColor())

    local text = btn:CreateFontString(nil, "OVERLAY")
    RC:SetFont(text, 11, "OUTLINE")
    text:SetPoint("CENTER", btn, "CENTER", 0, 0)
    text:SetText(label)
    text:SetTextColor(RC:GetButtonTextColor())
    RC:RegisterTextColor(text, "button")
    btn.textIcon = text

    ApplyActionButtonScripts(btn, text, function()
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine(tooltipTitle or label, 1, 1, 1)
        if tooltipText then
            GameTooltip:AddLine(tooltipText, 0.75, 0.75, 0.75, true)
        end
        GameTooltip:Show()
    end, function()
        GameTooltip:Hide()
    end)
    RestoreButton(btn)
    table.insert(self.buttons, btn)
    return btn
end

function ActionStrip:CreateMarkerButtons()
    local markerIcons = {
        [8] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
        [7] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7",
        [6] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6",
        [5] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5",
        [4] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4",
        [3] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3",
        [2] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2",
        [1] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1",
    }

    for i = 8, 1, -1 do
        local btn = CreateFrame("Button", "RC_ActionStripMarkerBtn" .. i, self.frame, "SecureActionButtonTemplate,BackdropTemplate")
        btn.rcBorderMinAlpha = 0
        btn:SetSize(self:GetMarkerButtonSize())
        RegisterSecureClicks(btn)
        ApplyWorldMarkerModifier(btn, i)
        RC:SkinFrame(btn)
        RC:SetFrameThemeRole(btn, "ButtonBg", 0.32)
        btn:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, 0.32)
        btn:SetBackdropBorderColor(1, 1, 1, 0)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("CENTER")
        tex:SetSize(self:GetMarkerIconSize(), self:GetMarkerIconSize())
        tex:SetTexture(markerIcons[i])
        btn.icon = tex
        btn.markerIndex = i

        btn:SetScript("OnEnter", function(self)
            Strip_OnEnter()
            self.icon:SetVertexColor(1.3, 1.3, 1.3, 1)
            self:SetBackdropColor(1, 1, 1, 0.07)
            self:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.46)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(L["Click: Target marker"], 0.8, 0.8, 0.8)
            GameTooltip:AddLine(L["Right-click: Clear target marker"], 0.8, 0.8, 0.8)
            GameTooltip:AddLine(string.format(L["%s+Click: Place world marker"], self.worldMarkerModifier or "SHIFT"), RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b)
            GameTooltip:AddLine(string.format(L["%s+Right-click: Clear world marker"], self.worldMarkerModifier or "SHIFT"), RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            self.icon:SetVertexColor(1, 1, 1, 1)
            self:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, 0.32)
            self:SetBackdropBorderColor(1, 1, 1, 0)
            GameTooltip:Hide()
            Strip_OnLeave()
        end)

        table.insert(self.markerButtons, btn)
    end
end

function ActionStrip:GetActionButtonSize()
    local width = ClampNumber(self.db.actionStripButtonWidth, 42, 90, ACTION_W)
    local height = ClampNumber(self.db.actionStripButtonHeight, 18, 34, ACTION_H)
    return width, height
end

function ActionStrip:GetMarkerIconSize()
    return ClampNumber(self.db.actionStripMarkerSize, 18, 34, MARKER_ICON_SIZE)
end

function ActionStrip:GetMarkerButtonSize()
    local size = self:GetMarkerIconSize()
    return size, math.max(size, ClampNumber(self.db.actionStripButtonHeight, 18, 34, ACTION_H))
end

function ActionStrip:SavePosition()
    if not self.frame then return end
    local point, _, relPoint, x, y = self.frame:GetPoint()
    self.db.actionStripPos = { point, "UIParent", relPoint, x, y }
end

function ActionStrip:UpdateScale(scale)
    if not self.frame then
        return scale
    end
    local snapped = ClampNumber(scale, 0.50, 2.00, 1.00)
    self.db.actionStripScale = snapped
    if InCombatLockdown and InCombatLockdown() then
        self.pendingScale = snapped
        return snapped
    end

    if RC.SetScalePreserveCenter then
        RC:SetScalePreserveCenter(self.frame, snapped, function()
            self:SavePosition()
        end)
    else
        self.frame:SetScale(snapped)
    end
    return snapped
end

function ActionStrip:RefreshModifierAttributes()
    if InCombatLockdown and InCombatLockdown() then
        -- Secure attributes are locked; RC re-applies every surface after combat.
        RC.MarkerModifierRefreshPending = true
        return
    end
    for _, btn in ipairs(self.markerButtons or {}) do
        if btn and btn.markerIndex then
            ApplyWorldMarkerModifier(btn, btn.markerIndex)
        end
    end
end

function ActionStrip:CreateStripFrame()
    local totalWidth = (8 * MARKER_W) + (7 * MARKER_SPACING) + 10 + (6 * ACTION_W) + (5 * ACTION_SPACING) + (PAD * 2)
    local frame = CreateFrame("Frame", "RC_ActionStrip", UIParent, "BackdropTemplate")
    frame.rcBorderMinAlpha = 0.07
    frame:SetSize(totalWidth, 30)
    RC:SkinFrame(frame)
    frame.rcUseHeaderBg = true
    RC:SetFrameThemeRole(frame, "HeaderBg")
    frame:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, math.max(0.10, RC.Config.Border.a or 0))
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetFrameStrata("HIGH")
    frame:SetScale(ClampNumber(self.db.actionStripScale, 0.50, 2.00, 1.00))

    local wash = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    wash:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    wash:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    frame.finishWash = wash

    local innerTop = frame:CreateTexture(nil, "ARTWORK")
    innerTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    innerTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    innerTop:SetHeight(1)
    innerTop:SetColorTexture(1, 1, 1, 0.06)
    frame.finishInnerTop = innerTop

    local accentLine = frame:CreateTexture(nil, "OVERLAY")
    accentLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -5)
    accentLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 5)
    accentLine:SetWidth(2)
    frame.finishAccent = accentLine

    if self.db.actionStripPos then
        frame:SetPoint(unpack(self.db.actionStripPos))
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, -50)
    end

    frame:SetScript("OnDragStart", function(f)
        if RC.IsUILayoutUnlocked and RC:IsUILayoutUnlocked() then
            f.rcMoving = true
            f:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(f)
        if not f.rcMoving then return end
        f.rcMoving = nil
        f:StopMovingOrSizing()
        self:SavePosition()
    end)
    frame:HookScript("OnEnter", Strip_OnEnter)
    frame:HookScript("OnLeave", Strip_OnLeave)

    self.frame = frame
    self.buttons = {}
    self.actionButtons = {}
    self.markerButtons = {}

    self:CreateMarkerButtons()

    self.readyBtn = self:CreateActionButton(L["Ready"], function()
        local Control = RC:GetModule("Control", true)
        if Control then Control:DoReadyCheck() end
    end)

    self.pullBtn = self:CreateActionButton(L["Pull"], function()
        local Control = RC:GetModule("Control", true)
        if not Control then return end
        if Control.pullActive then
            Control:EndPull()
        else
            Control:BeginPull(RC.db.profile.pullTimerDuration)
        end
    end)
    self.pullBtn:SetScript("OnEnter", function()
        Strip_OnEnter()
        local Control = RC:GetModule("Control", true)
        if Control and Control.pullActive then
            self.pullBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
            self.pullBtn:SetBackdropColor(0.75, 0.2, 0.2, 1)
            self.pullBtn.textIcon:SetTextColor(1, 1, 1)
        else
            self.pullBtn:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
            self.pullBtn:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
            self.pullBtn.textIcon:SetTextColor(1, 1, 1)
        end
    end)
    self.pullBtn:SetScript("OnLeave", function()
        self:RefreshPullButton()
        self.pullBtn.textIcon:SetTextColor(RC:GetButtonTextColor())
        Strip_OnLeave()
    end)

    self.convertBtn = self:CreateActionButton(L["Conv"], function()
        local Control = RC:GetModule("Control", true)
        if Control then Control:ToggleRaidConversion() end
    end)

    self.diffBtn = self:CreateActionButton(L["Diff"], function()
        local Control = RC:GetModule("Control", true)
        if Control then Control:ToggleDifficultyMenu(self.diffBtn) end
    end)

    self.inviteBtn = self:CreateActionButton(L["Inv"], function()
        local Control = RC:GetModule("Control", true)
        if Control then Control:InviteGuildBySelectedRanks() end
    end)

    self.clearTargetBtn = self:CreateSecureActionButton(
        L["TClr"],
        BuildTargetClearMacro(),
        L["Clear Target Marker"],
        L["Clears the marker from your current target."]
    )

    self.clearWorldBtn = self:CreateSecureActionButton(
        L["WClr"],
        BuildWorldClearMacro(),
        L["Clear World Markers"],
        L["Clears all world markers/flares."]
    )
    self.clearTargetBtn:Hide()
    self.clearWorldBtn:Hide()

    self.disbandBtn = self:CreateActionButton(L["Disb"], function()
        local Control = RC:GetModule("Control", true)
        if Control then Control:ConfirmDisband() end
    end)

    self.screenshotBtn = self:CreateActionButton(L["Shot"], function()
        local ScreenshotModule = RC:GetModule("Screenshot", true)
        if ScreenshotModule and ScreenshotModule.Take then
            ScreenshotModule:Take()
        end
    end)

    self.actionButtons = {
        { button = self.readyBtn, key = "actionStripShowReady" },
        { button = self.pullBtn, key = "actionStripShowPull" },
        { button = self.convertBtn, key = "actionStripShowConvert" },
        { button = self.diffBtn, key = "actionStripShowDifficulty" },
        { button = self.inviteBtn, key = "actionStripShowInvite" },
        { button = self.disbandBtn, key = "actionStripShowDisband" },
        { button = self.screenshotBtn, key = "actionStripShowScreenshot" },
    }

    self:UpdateDifficultyLabel()
    self:RefreshPullButton()
    self:RefreshButtonVisibility()
    self:RefreshTheme()
end

function ActionStrip:RefreshTheme()
    if not self.frame then return end

    RC:SetFrameThemeRole(self.frame, "HeaderBg")
    self.frame:SetBackdropBorderColor(
        RC.Config.Border.r,
        RC.Config.Border.g,
        RC.Config.Border.b,
        math.max(0.10, RC.Config.Border.a or 0)
    )

    if self.frame.finishWash then
        self.frame.finishWash:SetColorTexture(0, 0, 0, 0)
    end
    if self.frame.finishInnerTop then
        self.frame.finishInnerTop:SetColorTexture(1, 1, 1, 0.06)
    end
    if self.frame.finishAccent then
        self.frame.finishAccent:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.78)
    end

    for _, btn in ipairs(self.buttons or {}) do
        RestoreButton(btn)
    end
    for _, btn in ipairs(self.markerButtons or {}) do
        btn:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, 0.32)
        btn:SetBackdropBorderColor(1, 1, 1, 0)
    end
    self:RefreshPullButton()
end

function ActionStrip:RefreshButtonVisibility()
    if not self.frame then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingRefresh = true
        return
    end

    local showMarkers
    if self.db.showActionStripMarkers ~= nil then
        showMarkers = self.db.showActionStripMarkers ~= false
    else
        showMarkers = not self.db.hideMarkers
    end
    if self.clearTargetBtn then self.clearTargetBtn:Hide() end
    if self.clearWorldBtn then self.clearWorldBtn:Hide() end

    local actionW, actionH = self:GetActionButtonSize()
    local markerW, markerH = self:GetMarkerButtonSize()
    local markerIconSize = self:GetMarkerIconSize()
    local rowHeight = math.max(actionH, markerH)
    local layout = NormalizeLayout(self.db.actionStripLayout)
    local markerPosition = NormalizeMarkerPosition(self.db.actionStripMarkerPosition)

    local markerItems = {}
    for _, btn in ipairs(self.markerButtons or {}) do
        btn:ClearAllPoints()
        btn:SetSize(markerW, markerH)
        if btn.icon then
            btn.icon:SetSize(markerIconSize, markerIconSize)
        end
        if showMarkers then
            table.insert(markerItems, { button = btn, width = markerW, height = markerH, spacing = MARKER_SPACING })
        end
    end

    local actionItems = {}
    for _, entry in ipairs(self.actionButtons or {}) do
        local btn = entry.button
        btn:ClearAllPoints()
        btn:SetSize(actionW, actionH)
        if not (entry.key and self.db[entry.key] == false) then
            table.insert(actionItems, { button = btn, width = actionW, height = actionH, spacing = ACTION_SPACING })
        end
    end

    for _, btn in ipairs(self.markerButtons or {}) do btn:Hide() end
    for _, entry in ipairs(self.actionButtons or {}) do entry.button:Hide() end

    local rows = {}
    local function AddRow(items)
        if #items > 0 then
            table.insert(rows, items)
        end
    end

    local function CopyItems(source)
        local copy = {}
        for _, item in ipairs(source) do
            table.insert(copy, {
                button = item.button,
                width = item.width,
                height = item.height,
                spacing = item.spacing,
            })
        end
        return copy
    end

    local function AppendItems(target, source, extraGapBefore)
        if extraGapBefore and #target > 0 and #source > 0 then
            target[#target].spacing = ACTION_SPACING + 6
        end
        for _, item in ipairs(source) do
            table.insert(target, {
                button = item.button,
                width = item.width,
                height = item.height,
                spacing = item.spacing,
            })
        end
    end

    local function BuildCombinedRow(first, second)
        local row = {}
        AppendItems(row, first)
        AppendItems(row, second, true)
        return row
    end

    local function RowWidth(row)
        local width = 0
        for index, item in ipairs(row or {}) do
            local spacing = index < #row and (item.spacing or ACTION_SPACING) or 0
            width = width + item.width + spacing
        end
        return width
    end

    local combined = {}
    if markerPosition == "first" then
        AppendItems(combined, markerItems)
        AppendItems(combined, actionItems, true)
    else
        AppendItems(combined, actionItems)
        AppendItems(combined, markerItems, true)
    end

    if layout == "markers_row" and #markerItems > 0 and #actionItems > 0 then
        if markerPosition == "first" then
            AddRow(markerItems)
            AddRow(actionItems)
        else
            AddRow(actionItems)
            AddRow(markerItems)
        end
    elseif layout == "two_rows" and #combined > 2 then
        if #markerItems > 0 and #actionItems > 0 then
            local bestFirst, bestSecond, bestDelta
            for splitIndex = 0, #actionItems do
                local before, after = {}, {}
                for index, item in ipairs(actionItems) do
                    table.insert(index <= splitIndex and before or after, item)
                end

                local firstRow
                local secondRow
                if markerPosition == "first" then
                    firstRow = BuildCombinedRow(markerItems, before)
                    secondRow = CopyItems(after)
                else
                    firstRow = CopyItems(before)
                    secondRow = BuildCombinedRow(after, markerItems)
                end

                if #firstRow > 0 and #secondRow > 0 then
                    local delta = math.abs(RowWidth(firstRow) - RowWidth(secondRow))
                    if not bestDelta or delta < bestDelta then
                        bestDelta = delta
                        bestFirst = firstRow
                        bestSecond = secondRow
                    end
                end
            end
            AddRow(bestFirst or combined)
            AddRow(bestSecond or {})
        else
            local firstCount = math.ceil(#combined / 2)
            local firstRow, secondRow = {}, {}
            for index, item in ipairs(combined) do
                table.insert(index <= firstCount and firstRow or secondRow, item)
            end
            AddRow(firstRow)
            AddRow(secondRow)
        end
    else
        AddRow(combined)
    end

    local maxWidth = 0
    for rowIndex, row in ipairs(rows) do
        local rowWidth = 0
        for itemIndex, item in ipairs(row) do
            local spacing = itemIndex < #row and (item.spacing or ACTION_SPACING) or 0
            rowWidth = rowWidth + item.width + spacing
        end
        maxWidth = math.max(maxWidth, rowWidth)

        local x = PAD
        local y = -PAD - ((rowIndex - 1) * (rowHeight + ROW_SPACING))
        for itemIndex, item in ipairs(row) do
            item.button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", x, y - ((rowHeight - item.height) / 2))
            item.button:Show()
            x = x + item.width + (itemIndex < #row and (item.spacing or ACTION_SPACING) or 0)
        end
    end

    if #rows == 0 then
        self.frame:SetSize(30, 30)
    else
        self.frame:SetSize(math.max(maxWidth + (PAD * 2), 30), (rowHeight * #rows) + (ROW_SPACING * (#rows - 1)) + (PAD * 2))
    end
end

function ActionStrip:UpdateVisibility()
    if not self.frame then return end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingVisibility = true
        return
    end

    self:RefreshButtonVisibility()
    if self.db.showActionStrip and not self.pendingRefresh then
        self.frame:Show()
        self:RefreshMouseoverFade()
    else
        self.frame:Hide()
    end
end
