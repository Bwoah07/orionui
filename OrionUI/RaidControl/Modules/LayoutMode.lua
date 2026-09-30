local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
---@class LayoutMode : AceModule, AceEvent-3.0
local LayoutMode = RC:NewModule("LayoutMode", "AceEvent-3.0")

local PREVIEW_MODULES = {
    "ReadyTracker",
    "NoteReminders",
    "TankAssist",
    "AutoMarker",
    "RaidLeadTools",
}

local GAME_MENU_VISUAL_INSET = 2

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function PlayMenuSound()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION then
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
    end
end

function LayoutMode:OnEnable()
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RestoreInterruptedLayout()
    self:InstallGameMenuHook()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            LayoutMode:InstallEllesmereGameMenuButton()
        end)
    end
end

local function IsEllesmereAvailable()
    if _G.EllesmereUI_GameMenuButton then
        return true
    end
    return C_AddOns
        and C_AddOns.IsAddOnLoaded
        and C_AddOns.IsAddOnLoaded("EllesmereUI") == true
end

function LayoutMode:ADDON_LOADED(_, addonName)
    if addonName == "Blizzard_GameMenu" or addonName == "EllesmereUI" then
        self:InstallGameMenuHook()
        self:InstallEllesmereGameMenuButton()
    end
end

function LayoutMode:PLAYER_LOGIN()
    self:InstallGameMenuHook()
    self:InstallEllesmereGameMenuButton()
end

function LayoutMode:PLAYER_REGEN_ENABLED()
    if self.pendingDisable then
        self.pendingDisable = nil
        self:SetActive(false, true)
    end
    if self.pendingGameMenuInstall then
        self.pendingGameMenuInstall = nil
        self:InstallEllesmereGameMenuButton()
    end
end

function LayoutMode:IsActive()
    return self.active == true
end

function LayoutMode:NotifyStateChanged()
    local settings = RC:GetModule("Settings", true)
    if settings and settings.RefreshLayoutModeControls then
        local ok, err = pcall(settings.RefreshLayoutModeControls, settings, self:IsActive())
        if not ok and not self.settingsRefreshErrorShown then
            self.settingsRefreshErrorShown = true
            RC:Print(string.format(L["Could not refresh the Edit Mode control in Settings: %s"], tostring(err)))
        end
    end
    local workspace = RC:GetModule("Workspace", true)
    if workspace and workspace.NotifyLayoutStateChanged then
        workspace:NotifyLayoutStateChanged()
    end
end

function LayoutMode:OpenSettings()
    local workspace = RC:GetModule("Workspace", true)
    if workspace and workspace.Open then
        return workspace:Open("settings")
    end
    local settings = RC:GetModule("Settings", true)
    if settings and settings.Open then
        return settings:Open()
    end
    return false
end

function LayoutMode:CloseGameMenu(frame)
    if frame and HideUIPanel then
        HideUIPanel(frame)
    elseif frame and frame.CloseMenu then
        frame:CloseMenu()
    elseif frame and frame.Hide then
        frame:Hide()
    end
end

function LayoutMode:OpenSettingsFromGameMenu(frame)
    if IsInCombat() then
        RC:Print(L["RaidControl settings are unavailable during combat."])
        return false
    end
    PlayMenuSound()
    self:CloseGameMenu(frame)
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not IsInCombat() then
                LayoutMode:OpenSettings()
            end
        end)
    else
        self:OpenSettings()
    end
    return true
end

function LayoutMode:AddGameMenuButtons(frame)
    if not frame or type(frame.AddButton) ~= "function" or frame._raidControlAddingButtons then
        return false
    end
    if frame._raidControlButtonsAdded then
        return true
    end
    if IsEllesmereAvailable() then
        if _G.EllesmereUI_GameMenuButton then
            return self:InstallEllesmereGameMenuButton(frame)
        end
        self.pendingGameMenuInstall = true
        return false
    end

    frame._raidControlAddingButtons = true
    local closeIndex = math.max(1, (tonumber(frame.nextLayoutIndex) or 2) - 1)
    local closeButton
    local pool = frame.buttonPool
    if pool and type(pool.EnumerateActive) == "function" then
        for button in pool:EnumerateActive() do
            if button and button.layoutIndex == closeIndex then
                closeButton = button
                break
            end
        end
    end

    if frame.AddSection then frame:AddSection(14) end
    local settingsButton = frame:AddButton("RaidControl", function()
        self:OpenSettingsFromGameMenu(frame)
    end)

    -- Blizzard builds Return to Game last. Keep that familiar final position.
    if closeButton and settingsButton then
        local sectionSpacing = closeButton.topPadding or 20
        settingsButton.layoutIndex = closeIndex
        settingsButton.topPadding = sectionSpacing
        closeButton.layoutIndex = closeIndex + 1
        closeButton.topPadding = 20
        frame.nextLayoutIndex = math.max(tonumber(frame.nextLayoutIndex) or 1, closeIndex + 2)
        if frame.MarkDirty then
            frame:MarkDirty()
        end
    end
    frame._raidControlButtonsAdded = true
    frame._raidControlAddingButtons = nil
    return true
end

local function GetRaidControlBrandText()
    local accent = RC.Config and RC.Config.Accent or { r = 0.05, g = 0.82, b = 0.62 }
    local prefix = string.format(
        "|cff%02x%02x%02x",
        math.floor((accent.r or 0.05) * 255 + 0.5),
        math.floor((accent.g or 0.82) * 255 + 0.5),
        math.floor((accent.b or 0.62) * 255 + 0.5)
    )
    return prefix .. "Raid|r|cffffffffControl|r"
end

local function SetGameMenuButtonText(button)
    if not button then
        return
    end
    local text = GetRaidControlBrandText()
    if button.Text and button.Text.SetText then
        button.Text:SetText(text)
    elseif button.SetText then
        button:SetText(text)
    end
end

function LayoutMode:SkinEllesmereGameMenuButton(button)
    if not button or button._raidControlMenuSkin then
        return
    end

    if button.CreateTexture then
        local background = button:CreateTexture(nil, "BACKGROUND")
        background:SetPoint("TOPLEFT", button, "TOPLEFT", GAME_MENU_VISUAL_INSET + 1, -(GAME_MENU_VISUAL_INSET + 1))
        background:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -(GAME_MENU_VISUAL_INSET + 1), GAME_MENU_VISUAL_INSET + 1)

        local function CreateBorderLine()
            return button:CreateTexture(nil, "BORDER")
        end

        local top = CreateBorderLine()
        top:SetPoint("TOPLEFT", button, "TOPLEFT", GAME_MENU_VISUAL_INSET, -GAME_MENU_VISUAL_INSET)
        top:SetPoint("TOPRIGHT", button, "TOPRIGHT", -GAME_MENU_VISUAL_INSET, -GAME_MENU_VISUAL_INSET)
        top:SetHeight(1)

        local bottom = CreateBorderLine()
        bottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", GAME_MENU_VISUAL_INSET, GAME_MENU_VISUAL_INSET)
        bottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -GAME_MENU_VISUAL_INSET, GAME_MENU_VISUAL_INSET)
        bottom:SetHeight(1)

        local left = CreateBorderLine()
        left:SetPoint("TOPLEFT", button, "TOPLEFT", GAME_MENU_VISUAL_INSET, -GAME_MENU_VISUAL_INSET)
        left:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", GAME_MENU_VISUAL_INSET, GAME_MENU_VISUAL_INSET)
        left:SetWidth(1)

        local right = CreateBorderLine()
        right:SetPoint("TOPRIGHT", button, "TOPRIGHT", -GAME_MENU_VISUAL_INSET, -GAME_MENU_VISUAL_INSET)
        right:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -GAME_MENU_VISUAL_INSET, GAME_MENU_VISUAL_INSET)
        right:SetWidth(1)

        button._raidControlMenuBackground = background
        button._raidControlMenuBorders = { top, bottom, left, right }
    end

    if not button.Text and button.CreateFontString then
        button.Text = button:CreateFontString(nil, "OVERLAY")
        button.Text:SetPoint("CENTER")
    end
    if button.Text then
        RC:SetFont(button.Text, 13, "")
    end

    local function RefreshVisual(hovered)
        local background = button._raidControlMenuBackground
        local backgroundColor = hovered and RC.Config.ButtonHover or RC.Config.ButtonBg
        if background and backgroundColor then
            background:SetColorTexture(backgroundColor.r, backgroundColor.g, backgroundColor.b, backgroundColor.a or 1)
        end
        local borderColor = hovered and RC.Config.AccentHover or RC.Config.InputBorder
        for _, border in ipairs(button._raidControlMenuBorders or {}) do
            border:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, hovered and 1 or (borderColor.a or 0.88))
        end
    end

    button:SetScript("OnEnter", function()
        RefreshVisual(true)
    end)
    button:SetScript("OnLeave", function()
        RefreshVisual(false)
    end)
    button.RefreshTheme = function()
        if button.Text then
            RC:SetFont(button.Text, 13, "")
        end
        RefreshVisual(false)
        SetGameMenuButtonText(button)
    end
    if RC.RegisterThemeWidget then
        RC:RegisterThemeWidget(button)
    end
    RefreshVisual(false)
    SetGameMenuButtonText(button)
    button._raidControlMenuSkin = true
end

function LayoutMode:LayoutEllesmereGameMenuButton(frame)
    if IsInCombat() or not frame or not frame:IsShown() then
        return
    end
    local button = self.ellesmereGameMenuButton
    local ellesmereButton = _G.EllesmereUI_GameMenuButton
    if not button or not ellesmereButton or not ellesmereButton:IsShown() then
        if button then button:Hide() end
        return
    end

    local anchor = _G.EllesmereUI_UnlockMenuButton
    if not anchor or not anchor:IsShown() then
        anchor = ellesmereButton
    end
    local width, height = anchor:GetWidth(), anchor:GetHeight()
    width = width and width > 0 and width or 200
    height = height and height > 0 and height or 35
    button:SetSize(width, height)
    SetGameMenuButtonText(button)
    button:ClearAllPoints()
    button:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
    button:Show()

    local anchorBottom = anchor:GetBottom()
    local extraHeight = height + 5
    if anchorBottom and frame.buttonPool and frame.buttonPool.EnumerateActive then
        for menuButton in frame.buttonPool:EnumerateActive() do
            local top = menuButton:GetTop()
            if top and top < anchorBottom + 2 then
                local point, relativeTo, relativePoint, x, y = menuButton:GetPoint(1)
                if point then
                    menuButton:ClearAllPoints()
                    menuButton:SetPoint(point, relativeTo, relativePoint, x, (y or 0) - extraHeight)
                end
            end
        end
    end
    frame:SetHeight(frame:GetHeight() + extraHeight)
end

function LayoutMode:InstallEllesmereGameMenuButton(frame)
    if self.ellesmereGameMenuHooked then
        return true
    end
    if IsInCombat() then
        self.pendingGameMenuInstall = true
        return false
    end
    frame = frame or _G.GameMenuFrame
    local ellesmereButton = _G.EllesmereUI_GameMenuButton
    if not frame or not ellesmereButton or frame._raidControlButtonsAdded then
        return false
    end

    local button = CreateFrame("Button", "RaidControl_GameMenuButton", frame)
    button:SetSize(200, 35)
    SetGameMenuButtonText(button)
    button:EnableMouse(true)
    if button.Enable then button:Enable() end
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function()
        LayoutMode:OpenSettingsFromGameMenu(frame)
    end)
    self.ellesmereGameMenuButton = button
    self:SkinEllesmereGameMenuButton(button)

    hooksecurefunc(frame, "Layout", function()
        if IsInCombat() then return end
        LayoutMode._gameMenuLayoutSerial = (LayoutMode._gameMenuLayoutSerial or 0) + 1
        local serial = LayoutMode._gameMenuLayoutSerial
        C_Timer.After(0, function()
            if serial == LayoutMode._gameMenuLayoutSerial and not IsInCombat() then
                LayoutMode:LayoutEllesmereGameMenuButton(frame)
            end
        end)
    end)
    self.ellesmereGameMenuHooked = true
    return true
end

function LayoutMode:InstallGameMenuHook()
    if self.gameMenuHooked or type(hooksecurefunc) ~= "function" then
        return self.gameMenuHooked == true
    end

    local target = _G.GameMenuFrameMixin
    if type(target) ~= "table" or type(target.InitButtons) ~= "function" then
        target = _G.GameMenuFrame
    end
    if type(target) ~= "table" or type(target.InitButtons) ~= "function" then
        return false
    end

    hooksecurefunc(target, "InitButtons", function(frame)
        if _G.GameMenuFrame and frame ~= _G.GameMenuFrame then
            return
        end
        local ok, err = pcall(LayoutMode.AddGameMenuButtons, LayoutMode, frame)
        if not ok then
            frame._raidControlAddingButtons = nil
            if not LayoutMode.gameMenuErrorShown then
                LayoutMode.gameMenuErrorShown = true
                RC:Print(string.format(L["Could not add RaidControl to the Escape menu: %s"], tostring(err)))
            end
        end
    end)
    self.gameMenuHooked = true
    self:InstallEllesmereGameMenuButton(_G.GameMenuFrame)
    return true
end

function LayoutMode:GetBossViewerState()
    local bossNotes = RC:GetModule("BossNotes", true)
    if not bossNotes or not bossNotes.GetViewerSettings then
        return bossNotes, nil, false
    end
    local settings = bossNotes:GetViewerSettings()
    local shown = bossNotes.IsBossNoteViewerActuallyShown and bossNotes:IsBossNoteViewerActuallyShown() or false
    return bossNotes, settings and settings.locked ~= false, shown
end

function LayoutMode:ApplyFrameLocks(locked)
    local profile = RC.db and RC.db.profile
    if not profile then
        return false
    end
    locked = locked and true or false
    RC:SetFrameLock(locked)
    profile.lockActionStrip = locked
    profile.noteRemindersLocked = locked
    profile.tankAssistFramesLocked = locked

    local bossNotes = RC:GetModule("BossNotes", true)
    if bossNotes and bossNotes.SetBossNoteViewerLocked then
        bossNotes:SetBossNoteViewerLocked(locked)
    end
    local reminders = RC:GetModule("NoteReminders", true)
    if reminders and reminders.ApplySettings then
        reminders:ApplySettings()
    end
    local tankAssist = RC:GetModule("TankAssist", true)
    if tankAssist and tankAssist.ApplyFrameSettings then
        tankAssist:ApplyFrameSettings()
    end
    return true
end

function LayoutMode:SetAllFrameLocks(locked)
    if IsInCombat() then
        RC:Print(L["Edit Mode lock changes are unavailable during combat."])
        return false
    end
    if locked then
        if self:IsActive() then
            return self:SetActive(false)
        end
        return self:ApplyFrameLocks(true)
    end
    return self:SetActive(true)
end

function LayoutMode:RestoreInterruptedLayout()
    local profile = RC.db and RC.db.profile
    local restore = profile and profile.layoutModeRestore
    if type(restore) ~= "table" then
        return false
    end

    profile.layoutModeRestore = nil
    self:ApplyFrameLocks(true)

    local bossNotes = RC:GetModule("BossNotes", true)
    if bossNotes and bossNotes.SetBossNoteViewerLocked then
        bossNotes:SetBossNoteViewerLocked(restore.bossViewerLocked ~= false)
    end
    if bossNotes and bossNotes.SetBossNoteViewerShown then
        bossNotes:SetBossNoteViewerShown(restore.bossViewerShown == true, "layout-mode-recovery")
    end
    if RC.ApplyInterfaceVisibility then
        RC:ApplyInterfaceVisibility()
    end
    if RC.SetMenuOpen then
        RC:SetMenuOpen(false, true)
    end
    self.active = false
    self.pendingDisable = nil
    self.previewsActive = nil
    self.showAllPreviews = nil
    self:ShowToolbar(false)
    self:UpdateFrameTags()
    self:NotifyStateChanged()
    return true
end

function LayoutMode:CaptureState()
    local bossNotes, bossLocked, bossShown = self:GetBossViewerState()
    local actionStrip = RC:GetModule("ActionStrip", true)
    return {
        bossNotes = bossNotes,
        bossViewerLocked = bossLocked,
        bossViewerShown = bossShown,
        menuOpen = RC.IsMenuOpen == true,
        topBarShown = RC.TopBar and RC.TopBar.IsShown and RC.TopBar:IsShown() or false,
        actionStripShown = actionStrip and actionStrip.frame and actionStrip.frame.IsShown
            and actionStrip.frame:IsShown() or false,
    }
end

function LayoutMode:RunModulePreviewMethod(methodName)
    local allSucceeded = true
    self.previewErrors = self.previewErrors or {}
    for _, moduleName in ipairs(PREVIEW_MODULES) do
        local module = RC:GetModule(moduleName, true)
        local callback = module and module[methodName]
        if callback then
            local persistent = methodName == "BeginLayoutMode"
                and (moduleName == "AutoMarker" or moduleName == "RaidLeadTools")
            local ok, err = pcall(callback, module, persistent and true or nil)
            if not ok then
                allSucceeded = false
                local errorKey = moduleName .. ":" .. methodName
                if not self.previewErrors[errorKey] then
                    self.previewErrors[errorKey] = true
                    RC:Print(string.format(L["%s Edit Mode preview failed: %s"], moduleName, tostring(err)))
                end
            end
        end
    end
    return allSucceeded
end

function LayoutMode:BeginModulePreviews()
    if self.previewsActive then
        return true
    end
    self.previewsActive = true
    return self:RunModulePreviewMethod("BeginLayoutMode")
end

function LayoutMode:EndModulePreviews()
    if not self.previewsActive then
        return true
    end
    self.previewsActive = nil
    return self:RunModulePreviewMethod("EndLayoutMode")
end

function LayoutMode:RestoreWorkingVisibility()
    local previous = self.previous or {}
    if RC.TopBar and RC.TopBar.SetShown then
        RC.TopBar:SetShown(previous.topBarShown == true)
    end
    if RC.SetMenuOpen then
        RC:SetMenuOpen(previous.menuOpen == true, true)
    end
    local actionStrip = RC:GetModule("ActionStrip", true)
    if actionStrip and actionStrip.frame and actionStrip.frame.SetShown then
        actionStrip.frame:SetShown(previous.actionStripShown == true)
    end
    local bossNotes = previous.bossNotes or RC:GetModule("BossNotes", true)
    if bossNotes and bossNotes.SetBossNoteViewerShown then
        bossNotes:SetBossNoteViewerShown(previous.bossViewerShown == true, "layout-preview-visibility")
    end
end

function LayoutMode:SetAllPreviewsShown(shown)
    if not self:IsActive() then
        return false
    end
    if IsInCombat() then
        -- The launcher and action strip are secure; showing them is blocked.
        RC:Print(L["Preview visibility can't change during combat."])
        return false
    end
    shown = shown and true or false
    if shown == (self.showAllPreviews == true) then
        return true
    end
    self.showAllPreviews = shown and true or nil
    if shown then
        if RC.TopBar then
            RC.TopBar:Show()
        end
        if RC.SetMenuOpen then
            RC:SetMenuOpen(true, true)
        end
        local actionStrip = RC:GetModule("ActionStrip", true)
        if actionStrip and actionStrip.frame then
            actionStrip.frame:Show()
        end
        local bossNotes = self.previous and self.previous.bossNotes or RC:GetModule("BossNotes", true)
        if bossNotes and bossNotes.SetBossNoteViewerShown then
            bossNotes:SetBossNoteViewerShown(true, "layout-preview-all")
        end
        self:BeginModulePreviews()
    else
        self:EndModulePreviews()
        self:RestoreWorkingVisibility()
    end
    self:RefreshToolbar()
    self:UpdateFrameTags()
    return true
end

function LayoutMode:CreateToolbar()
    if self.toolbar or not CreateFrame then
        return self.toolbar
    end
    local frame = CreateFrame("Frame", "RC_LayoutModeToolbar", UIParent, "BackdropTemplate")
    frame:SetSize(424, 48)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -86)
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(1200)
    if frame.SetToplevel then
        frame:SetToplevel(true)
    end
    RC:SkinFrame(frame)
    RC:ApplyThemedWindow(frame, "window")

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    RC:SetFont(frame.title, 11, "OUTLINE")
    frame.title:SetPoint("LEFT", frame, "LEFT", 12, 0)
    frame.title:SetText(L["RAIDCONTROL EDIT MODE"])
    RC:SetTextColor(frame.title, "title")

    frame.preview = RC:CreateStandardButton(nil, frame, 96, 24)
    frame.preview:SetPoint("RIGHT", frame, "RIGHT", -112, 0)
    frame.preview.Text:SetText(L["Show All"])
    frame.preview:SetScript("OnClick", function()
        self:SetAllPreviewsShown(not self.showAllPreviews)
    end)

    frame.lock = RC:CreateStandardButton(nil, frame, 96, 24)
    frame.lock:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    frame.lock.Text:SetText(L["Save & Lock"])
    frame.lock:SetScript("OnClick", function()
        self:SetActive(false)
    end)

    frame:EnableMouse(true)
    frame:SetScript("OnMouseUp", function(owner, mouseButton)
        if mouseButton ~= "RightButton" then
            return
        end
        local workspace = RC:GetModule("Workspace", true)
        if workspace and workspace.OpenSettingsFromRightClick then
            workspace:OpenSettingsFromRightClick()
        end
    end)

    function frame:RefreshTheme()
        RC:ApplyThemedWindow(self, "window")
    end
    RC:RegisterThemeWidget(frame)
    frame:Hide()
    self.toolbar = frame
    return frame
end

function LayoutMode:RefreshToolbar()
    local toolbar = self.toolbar
    if not toolbar then
        return
    end
    if toolbar.preview and toolbar.preview.Text then
        toolbar.preview.Text:SetText(self.showAllPreviews and L["Visible Only"] or L["Show All"])
    end
end

function LayoutMode:ShowToolbar(shown)
    local toolbar = self:CreateToolbar()
    if toolbar then
        self:RefreshToolbar()
        toolbar:SetShown(shown and true or false)
    end
end

function LayoutMode:ShowFrameTag(frame, label)
    if not frame or not CreateFrame then
        return
    end
    self.frameTags = self.frameTags or setmetatable({}, { __mode = "k" })
    local tag = self.frameTags[frame]
    if not tag then
        -- A frame that clips its children (the launcher dropdown) would cut
        -- off a tag that sits above it, so that tag hangs from UIParent.
        local clips = frame.DoesClipChildren and frame:DoesClipChildren()
        tag = CreateFrame("Frame", nil, clips and UIParent or frame, "BackdropTemplate")
        if clips and frame.GetFrameStrata then
            tag:SetFrameStrata(frame:GetFrameStrata())
        end
        tag:SetSize(112, 18)
        tag:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 4)
        tag:SetFrameLevel((frame:GetFrameLevel() or 1) + 50)
        tag:EnableMouse(false)
        RC:SkinFrame(tag)
        RC:ApplyThemedPanel(tag, "header")
        tag.text = tag:CreateFontString(nil, "OVERLAY")
        RC:SetFont(tag.text, 9, "OUTLINE")
        tag.text:SetPoint("CENTER")
        RC:SetTextColor(tag.text, "title")
        function tag:RefreshTheme()
            RC:ApplyThemedPanel(self, "header")
        end
        RC:RegisterThemeWidget(tag)
        self.frameTags[frame] = tag
    end
    tag.text:SetText(label)
    tag:Show()
end

function LayoutMode:UpdateFrameTags()
    for _, tag in pairs(self.frameTags or {}) do
        tag:Hide()
    end
    if not self:IsActive() then
        return
    end

    local actionStrip = RC:GetModule("ActionStrip", true)
    local bossNotes = RC:GetModule("BossNotes", true)
    local reminders = RC:GetModule("NoteReminders", true)
    local tankAssist = RC:GetModule("TankAssist", true)
    local autoMarker = RC:GetModule("AutoMarker", true)
    local leadTools = RC:GetModule("RaidLeadTools", true)
    local readyTracker = RC:GetModule("ReadyTracker", true)
    -- The open dropdown covers (and hides) the launcher tab, so tag whichever is visible.
    local menuOpen = RC.Menu and RC.Menu.IsShown and RC.Menu:IsShown()
    self:ShowFrameTag(menuOpen and RC.Menu or RC.TopBar, L["Launcher + Dropdown"])
    self:ShowFrameTag(actionStrip and actionStrip.frame, L["Action Strip"])
    self:ShowFrameTag(bossNotes and bossNotes._viewer, L["Boss Note"])
    self:ShowFrameTag(reminders and reminders.frame, L["Note Reminders"])
    self:ShowFrameTag(tankAssist and tankAssist.frame, L["Tank Alert"])
    self:ShowFrameTag(tankAssist and tankAssist.timerFrame, L["Tank Timers"])
    self:ShowFrameTag(autoMarker and autoMarker.roleMarkButton, L["Role Marks"])
    self:ShowFrameTag(leadTools and leadTools.healerManaFrame, L["Healer Mana"])
    self:ShowFrameTag(leadTools and leadTools.bresFrame, L["Battle Res"])
    self:ShowFrameTag(readyTracker and readyTracker.frame, L["Ready Check"])
end

function LayoutMode:Begin()
    if IsInCombat() then
        RC:Print(L["Edit Mode is unavailable during combat."])
        return false
    end
    if not RC.db or not RC.db.profile then
        return false
    end

    local raidDemo = RC:GetModule("RaidDemo", true)
    if raidDemo and raidDemo.IsActive and raidDemo:IsActive() then
        raidDemo:Stop(true)
    end

    self.previous = self:CaptureState()
    self.active = true
    self.showAllPreviews = nil
    local profile = RC.db.profile
    profile.layoutModeRestore = {
        bossViewerLocked = self.previous.bossViewerLocked ~= false,
        bossViewerShown = self.previous.bossViewerShown == true,
        menuOpen = self.previous.menuOpen == true,
    }
    self:ApplyFrameLocks(false)
    self:RestoreWorkingVisibility()
    self:SetAllPreviewsShown(true)

    self:ShowToolbar(true)
    self:UpdateFrameTags()
    self:NotifyStateChanged()
    return true
end

function LayoutMode:Finish(fromCombatQueue)
    if not self:IsActive() then
        return true
    end
    if IsInCombat() and not fromCombatQueue then
        self.pendingDisable = true
        RC:Print(L["Edit Mode will save and lock when combat ends."])
        return false
    end

    local previous = self.previous or {}
    local profile = RC.db and RC.db.profile
    self.active = false
    self.pendingDisable = nil
    if profile then
        profile.layoutModeRestore = nil
        self:ApplyFrameLocks(true)
    end

    local bossNotes = previous.bossNotes or RC:GetModule("BossNotes", true)
    if bossNotes and bossNotes.SetBossNoteViewerLocked then
        bossNotes:SetBossNoteViewerLocked(previous.bossViewerLocked ~= false)
    end
    if bossNotes and bossNotes.SetBossNoteViewerShown then
        bossNotes:SetBossNoteViewerShown(previous.bossViewerShown == true, "layout-mode-restore")
    end

    self:EndModulePreviews()
    self.showAllPreviews = nil
    local actionStrip = RC:GetModule("ActionStrip", true)
    if actionStrip and actionStrip.UpdateVisibility then
        actionStrip:UpdateVisibility()
    end
    if RC.ApplyInterfaceVisibility then
        RC:ApplyInterfaceVisibility()
    end
    if RC.SetMenuOpen then
        RC:SetMenuOpen(previous.menuOpen == true and profile and not profile.hideMenu, true)
    end
    self:ShowToolbar(false)
    self:UpdateFrameTags()
    self.previous = nil
    self:NotifyStateChanged()
    return true
end

function LayoutMode:SetActive(active, fromCombatQueue)
    active = active and true or false
    if active == self:IsActive() then
        return true
    end
    if active then
        return self:Begin()
    end
    return self:Finish(fromCombatQueue)
end

function LayoutMode:Toggle()
    return self:SetActive(not self:IsActive())
end
