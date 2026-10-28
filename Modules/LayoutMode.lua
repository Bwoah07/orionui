local _, ns = ...
local RC = ns.RC
local L = RC.L
---@class LayoutMode : AceModule, AceEvent-3.0
local LayoutMode = RC:NewModule("LayoutMode", "AceEvent-3.0")

local PREVIEW_MODULES = {
    "ReadyTracker",
    "NoteReminders",
    "TankAssist",
    "BoneShield",
    "Loot",
    "LootHistory",
    "AutoMarker",
    "RaidLeadTools",
}

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
end

function LayoutMode:ADDON_LOADED(_, addonName)
    if addonName == "Blizzard_GameMenu" then
        self:InstallGameMenuHook()
    end
end

function LayoutMode:PLAYER_LOGIN()
    self:InstallGameMenuHook()
end

function LayoutMode:PLAYER_REGEN_ENABLED()
    if self.pendingDisable then
        self.pendingDisable = nil
        self:SetActive(false, true)
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
    C_Timer.After(0, function()
        if not IsInCombat() then LayoutMode:OpenSettings() end
    end)
    return true
end

-- =============================================================================
-- ESCAPE MENU BUTTON
-- A "RaidControl" button in its own block under Options / Shop, styled as a flat dark button with
-- the brand name. It is our own frame (not one of Blizzard's pooled menu buttons), placed after
-- every menu layout: below the last button above AddOns (Shop, or a button another addon put
-- there), with the buttons underneath moved down to make room.
-- =============================================================================

local GAME_MENU_VISUAL_INSET = 2
local GAME_MENU_GAP = 4

local function GetBrandText()
    local accent = RC.Config and RC.Config.Accent or { r = 0.05, g = 0.82, b = 0.62 }
    return string.format("|cff%02x%02x%02xRaid|r|cffffffffControl|r",
        math.floor((accent.r or 0.05) * 255 + 0.5),
        math.floor((accent.g or 0.82) * 255 + 0.5),
        math.floor((accent.b or 0.62) * 255 + 0.5))
end

local function ButtonText(button)
    local ok, text = pcall(function() return button.GetText and button:GetText() end)
    return ok and text or nil
end

function LayoutMode:CreateGameMenuButton(frame)
    if self.gameMenuButton then
        return self.gameMenuButton
    end
    local button = CreateFrame("Button", "RaidControl_GameMenuButton", frame)
    button:SetSize(200, 35)
    button:SetFrameLevel(frame:GetFrameLevel() + 5)
    button:RegisterForClicks("LeftButtonUp")
    button:SetScript("OnClick", function()
        LayoutMode:OpenSettingsFromGameMenu(frame)
    end)

    local inset = GAME_MENU_VISUAL_INSET
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetPoint("TOPLEFT", inset + 1, -(inset + 1))
    background:SetPoint("BOTTOMRIGHT", -(inset + 1), inset + 1)
    local borders = {}
    for i = 1, 4 do borders[i] = button:CreateTexture(nil, "BORDER") end
    borders[1]:SetPoint("TOPLEFT", inset, -inset) borders[1]:SetPoint("TOPRIGHT", -inset, -inset) borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT", inset, inset) borders[2]:SetPoint("BOTTOMRIGHT", -inset, inset) borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT", inset, -inset) borders[3]:SetPoint("BOTTOMLEFT", inset, inset) borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT", -inset, -inset) borders[4]:SetPoint("BOTTOMRIGHT", -inset, inset) borders[4]:SetWidth(1)

    button.Text = button:CreateFontString(nil, "OVERLAY")
    button.Text:SetPoint("CENTER")

    local function Refresh(hovered)
        local bg = hovered and RC.Config.ButtonHover or RC.Config.ButtonBg
        if bg then background:SetColorTexture(bg.r, bg.g, bg.b, bg.a or 1) end
        local border = hovered and RC.Config.AccentHover or RC.Config.InputBorder
        if border then
            for _, line in ipairs(borders) do
                line:SetColorTexture(border.r, border.g, border.b, hovered and 1 or (border.a or 0.88))
            end
        end
        RC:SetFont(button.Text, 13, "")
        button.Text:SetText(GetBrandText())
    end
    button:SetScript("OnEnter", function() Refresh(true) end)
    button:SetScript("OnLeave", function() Refresh(false) end)
    button.RefreshTheme = function() Refresh(false) end
    if RC.RegisterThemeWidget then RC:RegisterThemeWidget(button) end
    Refresh(false)

    self.gameMenuButton = button
    return button
end

function LayoutMode:LayoutGameMenuButton(frame)
    if IsInCombat() or not frame or not frame:IsShown() then
        return
    end
    local button = self:CreateGameMenuButton(frame)
    local pool = frame.buttonPool
    if not pool or type(pool.EnumerateActive) ~= "function" then
        button:Hide()
        return
    end

    -- AddOns starts the block we sit above.
    local addonsLabel = _G.ADDONS or "AddOns"
    local addonsButton
    for menuButton in pool:EnumerateActive() do
        if ButtonText(menuButton) == addonsLabel then
            addonsButton = menuButton
            break
        end
    end
    local addonsTop = addonsButton and addonsButton:GetTop()
    if not addonsTop then
        button:Hide()
        return
    end

    -- Anchor under the lowest shown button above AddOns, Blizzard's or another addon's.
    local pooled = {}
    for menuButton in pool:EnumerateActive() do pooled[menuButton] = true end
    local anchor, anchorBottom
    local function Consider(child)
        if child ~= button and child.IsObjectType and child:IsObjectType("Button") and child:IsShown() then
            local bottom = child:GetBottom()
            if bottom and bottom > addonsTop and (not anchorBottom or bottom < anchorBottom) then
                anchor, anchorBottom = child, bottom
            end
        end
    end
    for menuButton in pool:EnumerateActive() do Consider(menuButton) end
    for _, child in ipairs({ frame:GetChildren() }) do Consider(child) end
    if not anchor then
        button:Hide()
        return
    end

    local width, height = addonsButton:GetWidth(), addonsButton:GetHeight()
    button:SetSize(width and width > 0 and width or 200, height and height > 0 and height or 35)
    -- Under a Blizzard button (Shop) we start a block of our own, spaced like the menu's blocks;
    -- under another addon's button we join its block.
    local gap = GAME_MENU_GAP
    if pooled[anchor] then
        gap = math.max(GAME_MENU_GAP, anchorBottom - addonsTop)
    end
    button:ClearAllPoints()
    button:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
    button:Show()

    local extraHeight = button:GetHeight() + gap
    for menuButton in pool:EnumerateActive() do
        local top = menuButton:GetTop()
        if top and top <= addonsTop + 1 then
            local point, relativeTo, relativePoint, x, y = menuButton:GetPoint(1)
            if point then
                menuButton:ClearAllPoints()
                menuButton:SetPoint(point, relativeTo, relativePoint, x, (y or 0) - extraHeight)
            end
        end
    end
    frame:SetHeight(frame:GetHeight() + extraHeight)
end

function LayoutMode:InstallGameMenuHook()
    if self.gameMenuHooked or type(hooksecurefunc) ~= "function" then
        return self.gameMenuHooked == true
    end
    local frame = _G.GameMenuFrame
    if not frame or type(frame.Layout) ~= "function" then
        return false
    end
    hooksecurefunc(frame, "Layout", function()
        if IsInCombat() then return end
        LayoutMode.gameMenuLayoutSerial = (LayoutMode.gameMenuLayoutSerial or 0) + 1
        local serial = LayoutMode.gameMenuLayoutSerial
        -- Wait two frames so the menu, and any addon that adds its own button after the layout,
        -- has finished before we measure.
        C_Timer.After(0, function() C_Timer.After(0, function()
            if serial ~= LayoutMode.gameMenuLayoutSerial then return end
            local ok, err = pcall(LayoutMode.LayoutGameMenuButton, LayoutMode, frame)
            if not ok and not LayoutMode.gameMenuErrorShown then
                LayoutMode.gameMenuErrorShown = true
                RC:Print(string.format(L["Could not add RaidControl to the Escape menu: %s"], tostring(err)))
            end
        end) end)
    end)
    frame:HookScript("OnHide", function()
        if LayoutMode.gameMenuButton then LayoutMode.gameMenuButton:Hide() end
    end)
    self.gameMenuHooked = true
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
    local boneShield = RC:GetModule("BoneShield", true)
    if boneShield and boneShield.preview then
        self:ShowFrameTag(boneShield.frame, L["Bone Shield"])
    end
    local loot = RC:GetModule("Loot", true)
    if loot and loot.active then
        self:ShowFrameTag(loot.frame, L["Loot window"])
        self:ShowFrameTag(loot.rollAnchor, L["Loot rolls"])
    end
    local lootHistory = RC:GetModule("LootHistory", true)
    if lootHistory and lootHistory.active then
        self:ShowFrameTag(lootHistory.anchor, L["Loot History"])
    end
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
