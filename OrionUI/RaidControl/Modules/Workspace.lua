local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
local Workspace = RC:NewModule("Workspace")

local WINDOW_ORDER = { "settings", "split", "notes" }
local WINDOW_LABELS = {
    settings = L["Settings"],
    split = L["Raid Split"],
    notes = L["Boss Notes"],
}
local WINDOW_DESCRIPTIONS = {
    split = L["Build balanced raid groups and review essential buffs."],
    notes = L["Create, validate, and publish encounter assignments."],
}

local function ClampWorkspaceScale(value)
    value = tonumber(value) or 1
    return math.max(0.50, math.min(2.00, value))
end

local function IsShown(frame)
    return frame and frame.IsShown and frame:IsShown() or false
end

local function SetTooltip(owner, title, body)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:SetText(title, 1, 1, 1)
    if body and body ~= "" then
        GameTooltip:AddLine(body, 0.78, 0.78, 0.78, true)
    end
    GameTooltip:Show()
end

function Workspace:OnEnable()
    self.windows = self.windows or {}
    self.bars = self.bars or {}
    self:CreateHost()
end

function Workspace:GetScale()
    local profile = RC.db and RC.db.profile
    if not profile then
        return 1
    end
    return ClampWorkspaceScale(
        profile.workspaceScale
        or profile.settingsScale
        or profile.raidSplitScale
        or 1
    )
end

function Workspace:ApplyEntryScale(entry, scale)
    if not entry or not entry.frame then
        return
    end
    if entry.options and entry.options.applyScale then
        entry.options.applyScale(scale)
    elseif entry.frame.SetScale then
        entry.frame:SetScale(scale)
    end
end

function Workspace:SetScale(value)
    local scale = ClampWorkspaceScale(value)
    local profile = RC.db and RC.db.profile
    if profile then
        profile.workspaceScale = scale
        profile.settingsScale = scale
        profile.raidSplitScale = scale
        profile.bossNotesManagerScale = scale
    end

    if self.host then
        if RC.SetScalePreserveCenter then
            RC:SetScalePreserveCenter(self.host, scale, function()
                self:SaveHostPosition()
            end)
        else
            self.host:SetScale(scale)
        end
    else
        self.applyingScale = true
        for _, key in ipairs(WINDOW_ORDER) do
            self:ApplyEntryScale(self.windows and self.windows[key], scale)
        end
        self.applyingScale = nil
    end
    return scale
end

function Workspace:SaveHostPosition()
    local host = self.host
    local profile = RC.db and RC.db.profile
    if not host or not profile then
        return
    end
    local point, _, relativePoint, x, y = host:GetPoint(1)
    if point and relativePoint and type(x) == "number" and type(y) == "number" then
        profile.workspacePos = { point, relativePoint, x, y }
    end
end

function Workspace:RestoreHostPosition()
    local host = self.host
    if not host then
        return
    end
    local profile = RC.db and RC.db.profile
    local pos = profile and profile.workspacePos
    host:ClearAllPoints()
    if type(pos) == "table" then
        host:SetPoint(pos[1] or "CENTER", UIParent, pos[2] or pos[1] or "CENTER", pos[3] or 0, pos[4] or 0)
    else
        host:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

function Workspace:RefreshHostTheme()
    local host = self.host
    if not host then
        return
    end
    RC:ApplyThemedWindow(host, "window")
    RC:ApplyThemedHeader(host.header)
    if host.body then
        RC:ApplyThemedPanel(host.body, "content", {
            role = "Color",
            borderAlpha = 0,
        })
    end
    host.headerAccent:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
    host.headerSeparator:SetColorTexture(
        RC.Config.SeparatorColor.r,
        RC.Config.SeparatorColor.g,
        RC.Config.SeparatorColor.b,
        math.max(0.35, RC.Config.SeparatorColor.a or 0)
    )
    host.title:SetTextColor(RC.Config.HeaderText.r, RC.Config.HeaderText.g, RC.Config.HeaderText.b, 1)
    host.subtitle:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.82)
    self:RefreshChrome()
end

function Workspace:ApplyHostedPageRoot(frame)
    if not frame or not frame.SetBackdropColor then
        return
    end
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
end

function Workspace:ApplyPageSection(frame)
    if frame then
        RC:ApplyThemedSection(frame)
    end
end

function Workspace:ApplyPageToolbar(frame)
    if frame then
        RC:ApplyThemedPanel(frame, "actionbar", {
            role = "TabBg",
            borderRole = "SectionBorder",
            borderAlpha = 0,
        })
    end
end

function Workspace:RefreshHeaderActions()
    for key, entry in pairs(self.windows or {}) do
        for _, action in ipairs(entry.headerActions or {}) do
            action:SetShown(key == self.activeKey and IsShown(self.host))
        end
    end
end

function Workspace:RefreshHostHeader()
    local host = self.host
    if not host then
        return
    end
    host.title:SetText(WINDOW_LABELS[self.activeKey] or "RaidControl")
    host.subtitle:SetText(L["RaidControl Workspace"])
    self:RefreshHeaderActions()
end

function Workspace:SetSettingsImmersive(active)
    local host = self.host
    if self.settingsShell then
        active = true
    end
    if not host or host.settingsImmersive == (active and true or false) then
        return
    end
    host.settingsImmersive = active and true or false
    host.header:SetShown(not active)
    host.body:ClearAllPoints()
    if active then
        host.body:SetPoint("TOPLEFT", host, "TOPLEFT", 1, -1)
    else
        host.body:SetPoint("TOPLEFT", host, "TOPLEFT", 1, -53)
    end
    host.body:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -1, 1)
end

function Workspace:RehostEntryInSettingsShell(entry)
    local shell = self.settingsShell
    if not shell or not shell.externalPageLayer or not entry or entry.key == "settings" then
        return false
    end

    local frame = entry.frame
    frame.rcWorkspaceShellPage = true
    frame:SetParent(shell.externalPageLayer)
    frame:ClearAllPoints()
    frame:SetAllPoints(shell.externalPageLayer)
    frame:SetScale(1)
    frame:SetFrameStrata(shell.frame:GetFrameStrata())
    frame:SetFrameLevel(shell.externalPageLayer:GetFrameLevel() + 1)
    if entry.options and entry.options.onShellHosted and not entry.shellHosted then
        entry.shellHosted = true
        entry.options.onShellHosted(shell, entry)
    end
    return true
end

function Workspace:AdoptSettingsShell(shell, frame)
    if not shell or not shell.frame or not shell.externalPageLayer then
        return false
    end
    self.settingsShell = shell
    self.settingsShellFrame = frame or shell.frame
    for key, entry in pairs(self.windows or {}) do
        if key ~= "settings" then
            self:RehostEntryInSettingsShell(entry)
        end
    end
    self:SetSettingsImmersive(true)
    return true
end

function Workspace:EnsureSettingsShell()
    if self.settingsShell and self.settingsShellFrame then
        return true
    end
    local settings = RC:GetModule("Settings", true)
    if not settings then
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    if not settings.frame and settings.CreateWindow then
        settings.createAttempted = true
        local ok = pcall(settings.CreateWindow, settings)
        if not ok then
            return false
        end
    end
    return self.settingsShell ~= nil and self.settingsShellFrame ~= nil
end

function Workspace:ShowSettingsShellChrome()
    local frame = self.settingsShellFrame
    if not frame or IsShown(frame) then
        return frame ~= nil
    end
    self.showingSettingsShellChrome = true
    frame.rcWorkspaceChromeOnly = true
    frame:Show()
    frame.rcWorkspaceChromeOnly = nil
    self.showingSettingsShellChrome = nil
    return true
end

function Workspace:SetShellPage(key)
    local shell = self.settingsShell
    if not shell then
        return
    end
    if shell.SetWorkspacePage then
        shell:SetWorkspacePage(key)
    end
    if key ~= "settings" then
        if shell.title then
            shell.title:SetText(WINDOW_LABELS[key] or "RaidControl")
        end
        if shell.description then
            shell.description:SetText(WINDOW_DESCRIPTIONS[key] or L["RaidControl Workspace"])
        end
    else
        local settings = RC:GetModule("Settings", true)
        local selected = settings and settings.selectedTab
        for _, tabInfo in ipairs(settings and settings.navTabs or {}) do
            if tabInfo.key == selected then
                if shell.title then shell.title:SetText(tabInfo.label or L["Settings"]) end
                if shell.description then shell.description:SetText(tabInfo.description or "") end
                break
            end
        end
    end
end

function Workspace:CreateHost()
    if self.host or not CreateFrame or not UIParent then
        return self.host
    end

    local size = RC.WorkspaceSize or { width = 1180, height = 720 }
    local host = CreateFrame("Frame", "RC_RaidControlWorkspace", UIParent, "BackdropTemplate")
    host:SetSize(size.width, size.height)
    host:SetFrameStrata("FULLSCREEN_DIALOG")
    host:SetFrameLevel(120)
    host:SetMovable(true)
    host:SetClampedToScreen(true)
    host:EnableMouse(true)
    if host.SetToplevel then
        host:SetToplevel(true)
    end
    RC:SkinFrame(host)
    self.host = host
    self:RestoreHostPosition()
    host:SetScale(self:GetScale())

    host.body = CreateFrame("Frame", nil, host, "BackdropTemplate")
    host.body:SetPoint("TOPLEFT", host, "TOPLEFT", 1, -53)
    host.body:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -1, 1)
    host.body:SetFrameLevel(host:GetFrameLevel() + 1)
    RC:SkinFrame(host.body, nil, true)
    host.body:SetBackdropBorderColor(0, 0, 0, 0)

    host.pageLayer = CreateFrame("Frame", nil, host)
    host.pageLayer:SetAllPoints(host)
    host.pageLayer:SetFrameLevel(host:GetFrameLevel() + 2)
    if host.pageLayer.SetClipsChildren then
        host.pageLayer:SetClipsChildren(true)
    end

    host.header = CreateFrame("Frame", nil, host, "BackdropTemplate")
    host.header:SetPoint("TOPLEFT", host, "TOPLEFT", 1, -1)
    host.header:SetPoint("TOPRIGHT", host, "TOPRIGHT", -1, -1)
    host.header:SetHeight(52)
    host.header:SetFrameLevel(host:GetFrameLevel() + 500)
    host.header:EnableMouse(true)
    RC:SkinFrame(host.header, nil, true)

    host.headerAccent = host.header:CreateTexture(nil, "ARTWORK")
    host.headerAccent:SetPoint("TOPLEFT", host.header, "TOPLEFT", 0, 0)
    host.headerAccent:SetPoint("BOTTOMLEFT", host.header, "BOTTOMLEFT", 0, 0)
    host.headerAccent:SetWidth(3)

    host.headerSeparator = host.header:CreateTexture(nil, "ARTWORK")
    host.headerSeparator:SetPoint("BOTTOMLEFT", host.header, "BOTTOMLEFT", 0, 0)
    host.headerSeparator:SetPoint("BOTTOMRIGHT", host.header, "BOTTOMRIGHT", 0, 0)
    host.headerSeparator:SetHeight(1)

    host.title = host.header:CreateFontString(nil, "OVERLAY")
    RC:SetFont(host.title, 15, "OUTLINE")
    host.title:SetPoint("TOPLEFT", host.header, "TOPLEFT", 20, -8)
    host.title:SetPoint("RIGHT", host.header, "LEFT", 280, 0)
    host.title:SetJustifyH("LEFT")

    host.subtitle = host.header:CreateFontString(nil, "OVERLAY")
    RC:SetFont(host.subtitle, 9, "")
    host.subtitle:SetPoint("TOPLEFT", host.title, "BOTTOMLEFT", 0, -3)
    host.subtitle:SetPoint("RIGHT", host.title, "RIGHT", 0, 0)
    host.subtitle:SetJustifyH("LEFT")

    host.closeButton = RC:CreateCloseButton(host.header, 24)
    host.closeButton:SetPoint("RIGHT", host.header, "RIGHT", -10, 0)
    host.closeButton:SetFrameLevel(host.header:GetFrameLevel() + 50)
    host.closeButton:SetScript("OnClick", function()
        self:CloseActiveWindow()
    end)

    host.dragHandle = CreateFrame("Frame", nil, host.header)
    host.dragHandle:SetAllPoints(host.header)
    host.dragHandle:SetFrameLevel(host.header:GetFrameLevel() + 1)
    host.dragHandle:EnableMouse(true)
    host.dragHandle:RegisterForDrag("LeftButton")
    host.dragHandle:SetScript("OnDragStart", function()
        host:StartMoving()
    end)
    host.dragHandle:SetScript("OnDragStop", function()
        host:StopMovingOrSizing()
        self:SaveHostPosition()
    end)
    host.dragHandle:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            self:OpenSettingsFromRightClick()
        end
    end)

    host.workspaceBar = self:CreateChrome("workspace", host, {
        chromeParent = host.header,
        placeChrome = function(bar)
            bar:SetPoint("CENTER", host.header, "CENTER", 0, 0)
        end,
    })

    host:SetScript("OnShow", function()
        self:RefreshHostHeader()
        self:RefreshHostTheme()
        if host.Raise then
            host:Raise()
        end
    end)
    host:SetScript("OnHide", function()
        self:HideContextMenu()
        self:RunSwitch(function()
            for _, entry in pairs(self.windows or {}) do
                if IsShown(entry.frame) then
                    entry.frame:Hide()
                end
            end
        end)
        self.activeKey = nil
        self:RefreshHeaderActions()
    end)

    function host:RefreshTheme()
        Workspace:RefreshHostTheme()
    end
    RC:RegisterThemeWidget(host)
    if RC.RegisterEscapeFrame then
        RC:RegisterEscapeFrame(host, function()
            return self:HandleEscapeKey()
        end)
    end
    host:Hide()
    self:RefreshHostTheme()
    return host
end

function Workspace:IsSwitching()
    return (self.switchDepth or 0) > 0
end

function Workspace:GetLayoutMode()
    return RC:GetModule("LayoutMode", true)
end

function Workspace:IsLayoutActive()
    local layoutMode = self:GetLayoutMode()
    return layoutMode and layoutMode.IsActive and layoutMode:IsActive() or false
end

function Workspace:GetActiveKey()
    if self.host and not IsShown(self.host) then
        return nil
    end
    if self.activeKey and self.windows and IsShown(self.windows[self.activeKey] and self.windows[self.activeKey].frame) then
        return self.activeKey
    end
    for _, key in ipairs(WINDOW_ORDER) do
        local entry = self.windows and self.windows[key]
        if entry and IsShown(entry.frame) then
            self.activeKey = key
            return key
        end
    end
    self.activeKey = nil
    return nil
end

function Workspace:AnyWindowShown(exceptKey)
    if self.host then
        return IsShown(self.host)
    end
    for key, entry in pairs(self.windows or {}) do
        if key ~= exceptKey and IsShown(entry.frame) then
            return true
        end
    end
    return false
end

function Workspace:RunSwitch(callback)
    self.switchDepth = (self.switchDepth or 0) + 1
    local ok, result = pcall(callback)
    self.switchDepth = math.max(0, (self.switchDepth or 1) - 1)
    if not ok then
        local detail = tostring(result)
        self.lastError = detail
        if RC.db and RC.db.global then
            RC.db.global.lastWorkspaceError = {
                message = detail,
                timestamp = time and time() or 0,
            }
        end
        if self.lastErrorNotification ~= detail and RC.ShowError then
            self.lastErrorNotification = detail
            RC:ShowError(L["RaidControl could not switch workspace; the error was saved for diagnostics."])
        end
        return false
    end
    return true, result
end

function Workspace:HideOtherWindows(activeKey)
    for key, entry in pairs(self.windows or {}) do
        local keepShellChrome = self.settingsShell and key == "settings" and activeKey ~= "settings"
        if key ~= activeKey and not keepShellChrome and IsShown(entry.frame) then
            entry.frame:Hide()
        end
    end
end

function Workspace:ShowPage(key)
    local entry = self.windows and self.windows[key]
    if not entry then
        return false
    end
    if self.settingsShell and key ~= "settings" then
        self:ShowSettingsShellChrome()
    end
    self:HideOtherWindows(key)
    self.activeKey = key
    self:SetSettingsImmersive(self.settingsShell ~= nil or key == "settings")
    if not IsShown(entry.frame) then
        entry.frame:Show()
    end
    if self.host and not IsShown(self.host) then
        self.host:Show()
    end
    self:SetShellPage(key)
    self:RefreshHostHeader()
    self:RefreshChrome()
    if entry.options and entry.options.onActivated then
        entry.options.onActivated(self.host, entry)
    end
    return true
end

function Workspace:HandleWindowShown(key)
    if key == "settings" and self.showingSettingsShellChrome then
        return
    end
    if not self:IsSwitching() then
        self:RunSwitch(function()
            self:HideOtherWindows(key)
        end)
    end
    self.activeKey = key
    if self.settingsShell and key ~= "settings" then
        self:ShowSettingsShellChrome()
    end
    self:SetSettingsImmersive(self.settingsShell ~= nil or key == "settings")
    if self.host and not IsShown(self.host) then
        self.host:Show()
    end
    self:HideContextMenu()
    self:SetShellPage(key)
    self:RefreshHostHeader()
    self:RefreshChrome()
end

function Workspace:HandleWindowHidden(key, frame)
    self:HideContextMenu()
    if self.host then
        if self:IsSwitching() then
            return
        end
        if key == "settings" and self.settingsShellFrame == frame and self.activeKey ~= "settings" then
            if IsShown(self.host) then
                self.host:Hide()
            end
            return
        end
        if self.activeKey == key then
            self.activeKey = nil
            if IsShown(self.host) then
                self.host:Hide()
            end
        end
        self:RefreshHostHeader()
        self:RefreshChrome()
        return
    end
    if self.activeKey == key then
        self.activeKey = nil
    end
    self:GetActiveKey()
    self:RefreshChrome()
end

function Workspace:Open(key)
    if not WINDOW_LABELS[key] then
        return false
    end

    -- OrionUI: no settings shell any more; pages open in the plain workspace host.

    local ok, opened = self:RunSwitch(function()
        local result
        if key == "settings" then
            local settings = RC:GetModule("Settings", true)
            if settings and settings.Open then
                result = settings:Open()
            else
                return false
            end
        elseif key == "split" then
            local raidSplit = RC:GetModule("RaidSplit", true)
            if raidSplit and raidSplit.Open then
                result = raidSplit:Open()
            elseif raidSplit and raidSplit.Toggle then
                result = raidSplit:Toggle()
            else
                return false
            end
        elseif key == "notes" then
            local bossNotes = RC:GetModule("BossNotes", true)
            if bossNotes and bossNotes.Open then
                result = bossNotes:Open()
            else
                return false
            end
        end
        if result == false then
            return false
        end
        return true
    end)
    if ok and opened ~= false then
        opened = self:ShowPage(key)
        self:RefreshChrome()
    end
    return ok and opened ~= false
end

function Workspace:OpenSettingsSection(section)
    if not self:Open("settings") then
        return false
    end
    local settings = RC:GetModule("Settings", true)
    if settings and settings.SelectTab then
        settings:SelectTab(section or "interface")
    end
    return true
end

function Workspace:OpenSettingsFromRightClick()
    self:HideContextMenu()
    return self:Open("settings")
end

function Workspace:CloseActiveWindow()
    if self.host and IsShown(self.host) then
        self.host:Hide()
        return true
    end
    local key = self:GetActiveKey()
    local entry = key and self.windows and self.windows[key]
    if entry and IsShown(entry.frame) then
        entry.frame:Hide()
        return true
    end
    return false
end

function Workspace:HandleEscapeKey()
    local key = self:GetActiveKey()
    local entry = key and self.windows and self.windows[key]
    local onEscape = entry and entry.options and entry.options.onEscape
    if onEscape then
        local ok, handled = pcall(onEscape, self.host, entry)
        if ok and handled then
            return true
        end
    end
    return self:CloseActiveWindow()
end

function Workspace:HideActiveForLayoutMode()
    if self.host and IsShown(self.host) then
        self.host:Hide()
        return
    end
    local key = self:GetActiveKey()
    local entry = key and self.windows and self.windows[key]
    local frame = entry and entry.frame
    if not IsShown(frame) then
        return
    end
    frame:Hide()
end

function Workspace:SetLayoutActive(active)
    local layoutMode = self:GetLayoutMode()
    if not layoutMode or not layoutMode.SetActive then
        return false
    end
    local changed = layoutMode:SetActive(active and true or false)
    self:RefreshChrome()
    if changed and active and layoutMode:IsActive() then
        self:HideActiveForLayoutMode()
    end
    return changed
end

function Workspace:ToggleLayoutMode()
    return self:SetLayoutActive(not self:IsLayoutActive())
end

function Workspace:ResetActiveWindow()
    if self.host then
        if RC.db and RC.db.profile then
            RC.db.profile.workspacePos = nil
        end
        self:RestoreHostPosition()
        return true
    end
    local key = self.contextKey or self:GetActiveKey()
    local entry = key and self.windows and self.windows[key]
    if entry and entry.options and entry.options.reset then
        entry.options.reset()
        return true
    end
    return false
end

function Workspace:ApplyTheme(themeName)
    self:HideContextMenu()
    if InCombatLockdown and InCombatLockdown() then
        RC:Print(L["Workspace theme changes are unavailable during combat."])
        return false
    end
    if RC.ApplyThemePreset then
        RC:ApplyThemePreset(themeName, true)
    elseif RC.ApplyTheme then
        RC:ApplyTheme(themeName, true, true)
    end
    self:RefreshHostTheme()
    self:RefreshChrome()
    return true
end

local function ApplyButtonVisual(button, selected, hovered, disabled)
    if not button or not button.SetBackdropColor then
        return
    end
    if disabled then
        local bg = RC.Config.ButtonDisabled
        button:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 0.55)
        button:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, RC.Config.Border.a or 0.08)
        if button.Text then
            button.Text:SetTextColor(RC.Config.DisabledText.r, RC.Config.DisabledText.g, RC.Config.DisabledText.b, RC.Config.DisabledText.a or 1)
        end
    elseif selected then
        local bg = RC.Config.TabSelectedBg
        local border = RC.Config.NavSelectedBorder
        button:SetBackdropColor(bg.r, bg.g, bg.b, math.max(0.72, bg.a or 0.72))
        button:SetBackdropBorderColor(border.r, border.g, border.b, border.a or 0.72)
        if button.Text then
            button.Text:SetTextColor(RC.Config.TabSelectedText.r, RC.Config.TabSelectedText.g, RC.Config.TabSelectedText.b, RC.Config.TabSelectedText.a or 1)
        end
    elseif hovered then
        local bg = RC.Config.TabHover
        button:SetBackdropColor(bg.r, bg.g, bg.b, math.max(0.12, bg.a or 0.12))
        button:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.46)
        if button.Text then
            button.Text:SetTextColor(1, 1, 1, 0.96)
        end
    else
        local bg = button.rcWorkspaceTab and RC.Config.TabBg or RC.Config.ButtonBg
        button:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 0.72)
        local r, g, b, a = RC:GetControlBorderColor()
        button:SetBackdropBorderColor(r, g, b, a)
        if button.Text then
            local tr, tg, tb = RC:GetButtonTextColor()
            button.Text:SetTextColor(tr, tg, tb, 0.88)
        end
    end
end

function Workspace:CreateChromeButton(parent, width, text, onClick, tooltipTitle, tooltipBody)
    local button = RC:CreateStandardButton(nil, parent, width, 28)
    button.customBg = true
    button.Text:SetText(text)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(btn, mouseButton)
        if mouseButton == "RightButton" then
            self:OpenSettingsFromRightClick()
        elseif onClick then
            onClick()
        end
    end)
    button:SetScript("OnEnter", function(btn)
        btn.rcHovered = true
        ApplyButtonVisual(btn, btn.rcSelected, true, btn.rcDisabled)
        if tooltipTitle then
            SetTooltip(btn, tooltipTitle, tooltipBody)
        end
    end)
    button:SetScript("OnLeave", function(btn)
        btn.rcHovered = nil
        ApplyButtonVisual(btn, btn.rcSelected, false, btn.rcDisabled)
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    button:SetScript("OnMouseDown", nil)
    button:SetScript("OnMouseUp", nil)
    return button
end

function Workspace:CreateScaleControl(parent)
    local control = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    control:SetSize(112, 28)
    control:EnableMouse(true)
    control:EnableMouseWheel(true)
    RC:SkinFrame(control)

    local minus = RC:CreateStandardButton(nil, control, 24, 24)
    minus.Text:SetText("-")
    minus:SetPoint("LEFT", control, "LEFT", 2, 0)

    local plus = RC:CreateStandardButton(nil, control, 24, 24)
    plus.Text:SetText("+")
    plus:SetPoint("RIGHT", control, "RIGHT", -2, 0)

    local value = control:CreateFontString(nil, "OVERLAY")
    RC:SetFont(value, 10, "OUTLINE")
    value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    value:SetPoint("RIGHT", plus, "LEFT", -2, 0)
    value:SetJustifyH("CENTER")
    control.Value = value

    local function Step(direction)
        self:SetScale(self:GetScale() + (direction * 0.05))
        self:RefreshChrome()
    end

    minus:SetScript("OnClick", function() Step(-1) end)
    plus:SetScript("OnClick", function() Step(1) end)
    control:SetScript("OnMouseWheel", function(_, delta)
        Step(delta > 0 and 1 or -1)
    end)
    control:SetScript("OnMouseDown", function(_, button)
        if button == "RightButton" then
            self:SetScale(1)
            self:RefreshChrome()
        end
    end)
    control:SetScript("OnEnter", function(owner)
        SetTooltip(owner, L["Workspace Scale"], L["Use +/- or the mouse wheel. Right-click resets all three panels to 100%."])
    end)
    control:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    return control
end

function Workspace:CreateChrome(key, frame, options)
    if not CreateFrame or not frame then
        return nil
    end
    local parent = options.chromeParent or frame
    local bar = CreateFrame("Frame", nil, parent)
    bar.rcWorkspaceKey = key
    bar:SetSize(464, 28)
    bar:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 40)
    bar:EnableMouse(true)

    if options.placeChrome then
        options.placeChrome(bar)
    else
        bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -46, -10)
    end

    local widths = { settings = 82, split = 82, notes = 82 }
    local previous
    bar.workspaceButtons = {}
    for _, windowKey in ipairs(WINDOW_ORDER) do
        local tabKey = windowKey
        local button = self:CreateChromeButton(bar, widths[tabKey], WINDOW_LABELS[tabKey], function()
            self:Open(tabKey)
        end)
        button.rcWorkspaceTab = true
        if previous then
            button:SetPoint("LEFT", previous, "RIGHT", 0, 0)
        else
            button:SetPoint("LEFT", bar, "LEFT", 0, 0)
        end
        bar.workspaceButtons[tabKey] = button
        previous = button
    end

    bar.layoutButton = self:CreateChromeButton(bar, 90, L["Unlock UI"], function()
        self:ToggleLayoutMode()
    end, L["Edit Mode"], L["Unlock all RaidControl HUD elements for positioning, or save and lock them."])
    bar.layoutButton:SetPoint("LEFT", previous, "RIGHT", 8, 0)

    bar.scaleControl = self:CreateScaleControl(bar)
    bar.scaleControl:SetPoint("LEFT", bar.layoutButton, "RIGHT", 8, 0)

    bar:SetScript("OnMouseUp", function(owner, mouseButton)
        if mouseButton == "RightButton" then
            self:OpenSettingsFromRightClick()
        end
    end)

    function bar:RefreshTheme()
        Workspace:RefreshBar(self)
    end
    RC:RegisterThemeWidget(bar)
    self.bars[key] = bar
    self:RefreshBar(bar)
    return bar
end

function Workspace:RefreshBar(bar)
    if not bar then
        return
    end
    local activeKey = self:GetActiveKey()
    for key, button in pairs(bar.workspaceButtons or {}) do
        button.rcSelected = key == activeKey
        ApplyButtonVisual(button, button.rcSelected, button.rcHovered, false)
    end
    local layoutActive = self:IsLayoutActive()
    if bar.layoutButton then
        bar.layoutButton.Text:SetText(layoutActive and L["Save & Lock"] or L["Unlock UI"])
        bar.layoutButton.rcSelected = layoutActive
        ApplyButtonVisual(bar.layoutButton, layoutActive, bar.layoutButton.rcHovered, false)
    end
    if bar.scaleControl then
        RC:ApplyThemedPanel(bar.scaleControl, "input")
        if bar.scaleControl.Value then
            bar.scaleControl.Value:SetText(string.format("%d%%", math.floor((self:GetScale() * 100) + 0.5)))
            bar.scaleControl.Value:SetTextColor(
                RC.Config.Accent.r,
                RC.Config.Accent.g,
                RC.Config.Accent.b,
                1
            )
        end
    end
end

function Workspace:RefreshChrome()
    for _, bar in pairs(self.bars or {}) do
        self:RefreshBar(bar)
    end
    if self.contextMenu and self.contextMenu:IsShown() then
        self:RefreshContextMenu()
    end
end

function Workspace:HookRightClick(target, key)
    if not target or target.rcWorkspaceRightClickHooked then
        return
    end
    target.rcWorkspaceRightClickHooked = true
    if target.EnableMouse then
        target:EnableMouse(true)
    end
    if target.HookScript then
        target:HookScript("OnMouseUp", function(owner, mouseButton)
            if mouseButton == "RightButton" then
                self:OpenSettingsFromRightClick()
            end
        end)
    end
end

function Workspace:RegisterWindow(key, frame, options)
    if not key or not frame then
        return nil
    end
    self.windows = self.windows or {}
    self.bars = self.bars or {}
    options = options or {}
    self:CreateHost()

    local existing = self.windows[key]
    if existing and existing.frame == frame then
        return existing
    end

    local entry = { key = key, frame = frame, options = options }
    self.windows[key] = entry
    frame.rcWorkspaceKey = key
    frame:HookScript("OnShow", function()
        self:HandleWindowShown(key)
    end)
    frame:HookScript("OnHide", function(owner)
        self:HandleWindowHidden(key, owner)
    end)

    if self.host then
        frame.rcWorkspaceHosted = true
        frame.rcWorkspaceHost = self.host
        frame:SetParent(self.host.pageLayer)
        frame:ClearAllPoints()
        frame:SetAllPoints(self.host.pageLayer)
        frame:SetScale(1)
        frame:SetFrameStrata(self.host:GetFrameStrata())
        frame:SetFrameLevel(self.host.pageLayer:GetFrameLevel() + 1)
        if frame.SetMovable then
            frame:SetMovable(false)
        end

        for _, legacyFrame in ipairs(options.legacyChrome or {}) do
            legacyFrame:Hide()
        end

        self:ApplyHostedPageRoot(options.pageRoot or frame)

        entry.headerActions = options.headerActions or {}
        for _, action in ipairs(entry.headerActions) do
            action:SetParent(self.host.header)
            action:SetFrameLevel(self.host.header:GetFrameLevel() + 50)
            action:Hide()
        end
        if options.placeHeaderActions then
            options.placeHeaderActions(self.host.header, self.host.closeButton, self.host.workspaceBar)
        end
        if options.onHosted then
            options.onHosted(self.host, entry)
        end
        if key ~= "settings" and self.settingsShell then
            self:RehostEntryInSettingsShell(entry)
        end
        entry.bar = self.host.workspaceBar
    else
        entry.bar = self:CreateChrome(key, frame, options)
        for _, target in ipairs(options.rightClickTargets or {}) do
            self:HookRightClick(target, key)
        end
        self:ApplyEntryScale(entry, self:GetScale())
    end
    self:RefreshHeaderActions()
    return entry
end

function Workspace:CreateContextMenuRow(menu, text, callback)
    local row = RC:CreateStandardButton(nil, menu, 236, 24)
    row.customBg = true
    row.Text:SetText(text)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", function()
        if not row.rcDisabled and callback then
            callback()
        end
    end)
    row:SetScript("OnEnter", function(btn)
        btn.rcHovered = true
        ApplyButtonVisual(btn, btn.rcSelected, true, btn.rcDisabled)
    end)
    row:SetScript("OnLeave", function(btn)
        btn.rcHovered = nil
        ApplyButtonVisual(btn, btn.rcSelected, false, btn.rcDisabled)
    end)
    row:SetScript("OnMouseDown", nil)
    row:SetScript("OnMouseUp", nil)
    menu.rows[#menu.rows + 1] = row
    return row
end

function Workspace:CreateContextMenu()
    if self.contextMenu or not CreateFrame then
        return self.contextMenu
    end
    local menu = CreateFrame("Frame", "RC_WorkspaceContextMenu", UIParent, "BackdropTemplate")
    menu:SetWidth(252)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(980)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    RC:SkinFrame(menu)
    RC:ApplyThemedWindow(menu, "window")
    menu.rows = {}
    menu.labels = {}
    menu:Hide()

    menu.title = menu:CreateFontString(nil, "OVERLAY")
    RC:SetFont(menu.title, 12, "OUTLINE")
    menu.title:SetPoint("TOPLEFT", menu, "TOPLEFT", 10, -10)
    menu.title:SetText(L["RaidControl Workspace"])
    menu.labels[#menu.labels + 1] = menu.title

    local cursorY = -34
    local function AddSection(text)
        local label = menu:CreateFontString(nil, "OVERLAY")
        RC:SetFont(label, 9, "OUTLINE")
        label:SetPoint("TOPLEFT", menu, "TOPLEFT", 11, cursorY)
        label:SetText(text)
        menu.labels[#menu.labels + 1] = label
        cursorY = cursorY - 16
    end
    local function AddRow(text, callback)
        local row = self:CreateContextMenuRow(menu, text, callback)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 8, cursorY)
        cursorY = cursorY - 27
        return row
    end

    AddSection(L["WORKSPACE"])
    menu.workspaceRows = {}
    for _, key in ipairs(WINDOW_ORDER) do
        local rowKey = key
        menu.workspaceRows[rowKey] = AddRow(WINDOW_LABELS[rowKey], function()
            self:HideContextMenu()
            self:Open(rowKey)
        end)
    end

    AddSection(L["EDIT MODE"])
    menu.layoutRow = AddRow(L["Unlock UI"], function()
        self:HideContextMenu()
        self:ToggleLayoutMode()
    end)

    AddSection(L["STYLE / THEME"])
    menu.themeRows = {}
    for _, themeName in ipairs(RC.ThemeOrder or { "Shadowsteel", "Starforge" }) do
        local selectedTheme = themeName
        menu.themeRows[selectedTheme] = AddRow(selectedTheme, function()
            self:ApplyTheme(selectedTheme)
        end)
    end
    menu.appearanceRow = AddRow(L["Appearance Settings"], function()
        self:HideContextMenu()
        self:OpenSettingsSection("appearance")
    end)

    AddSection(L["WINDOW"])
    menu.resetRow = AddRow(L["Reset Window Position"], function()
        self:HideContextMenu()
        self:ResetActiveWindow()
    end)
    menu.closeRow = AddRow(L["Close Workspace"], function()
        self:HideContextMenu()
        self:CloseActiveWindow()
    end)

    menu:SetHeight(-cursorY + 8)
    menu:SetScript("OnHide", function(owner)
        owner:SetScript("OnUpdate", nil)
    end)

    function menu:RefreshTheme()
        RC:ApplyThemedWindow(self, "window")
        Workspace:RefreshContextMenu()
    end
    RC:RegisterThemeWidget(menu)
    if RC.RegisterEscapeFrame then
        RC:RegisterEscapeFrame(menu)
    end
    self.contextMenu = menu
    return menu
end

function Workspace:RefreshContextMenu()
    local menu = self.contextMenu
    if not menu then
        return
    end
    local activeKey = self:GetActiveKey()
    for key, row in pairs(menu.workspaceRows or {}) do
        row.rcSelected = key == activeKey
        ApplyButtonVisual(row, row.rcSelected, row.rcHovered, false)
    end
    if menu.layoutRow then
        local active = self:IsLayoutActive()
        menu.layoutRow.Text:SetText(active and L["Save & Lock"] or L["Unlock UI"])
        menu.layoutRow.rcSelected = active
        ApplyButtonVisual(menu.layoutRow, active, menu.layoutRow.rcHovered, false)
    end
    local currentTheme = RC.ResolveThemeName and RC:ResolveThemeName(RC.db and RC.db.profile and RC.db.profile.theme) or nil
    local themeDisabled = InCombatLockdown and InCombatLockdown() or false
    for themeName, row in pairs(menu.themeRows or {}) do
        row.rcSelected = themeName == currentTheme
        row.rcDisabled = themeDisabled
        ApplyButtonVisual(row, row.rcSelected, row.rcHovered, row.rcDisabled)
    end
    if menu.appearanceRow then
        ApplyButtonVisual(menu.appearanceRow, false, menu.appearanceRow.rcHovered, false)
    end
    local contextEntry = self.contextKey and self.windows and self.windows[self.contextKey]
    local canReset = contextEntry and contextEntry.options and contextEntry.options.reset
    if menu.resetRow then
        menu.resetRow.rcDisabled = not canReset
        ApplyButtonVisual(menu.resetRow, false, menu.resetRow.rcHovered, menu.resetRow.rcDisabled)
    end
    if menu.closeRow then
        menu.closeRow.rcDisabled = not activeKey
        ApplyButtonVisual(menu.closeRow, false, menu.closeRow.rcHovered, menu.closeRow.rcDisabled)
    end
    for _, label in ipairs(menu.labels or {}) do
        if label == menu.title then
            RC:SetTextColor(label, "title")
        else
            label:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.78)
        end
    end
end

function Workspace:ShowContextMenu(anchor, key)
    local menu = self:CreateContextMenu()
    if not menu then
        return
    end
    self.contextKey = key or self:GetActiveKey()
    self:RefreshContextMenu()
    menu:ClearAllPoints()
    if GetCursorPosition and UIParent and UIParent.GetEffectiveScale then
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x / scale) + 4, (y / scale) - 4)
    elseif anchor then
        menu:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -4)
    else
        menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    menu:Show()
    if menu.Raise then
        menu:Raise()
    end
    menu:SetScript("OnUpdate", function(owner)
        if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) and not owner:IsMouseOver() then
            owner:Hide()
        end
    end)
end

function Workspace:HideContextMenu()
    if self.contextMenu then
        self.contextMenu:Hide()
    end
end

function Workspace:NotifyLayoutStateChanged()
    self:RefreshChrome()
end
