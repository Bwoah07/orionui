local _, ns = ...
local RC = ns.RC
local AceGUI = LibStub("AceGUI-3.0")
local L = RC.L

RC.SettingsV2 = RC.SettingsV2 or {}
local V2 = RC.SettingsV2

V2.Shell = V2.Shell or {}

local function SafeSetClipsChildren(frame, enabled)
    if frame and frame.SetClipsChildren then
        frame:SetClipsChildren(enabled)
    end
end

local function CreateSkinnedRegion(parent, level, role)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame.rcBorderAlphaOverride = 0
    frame:SetFrameLevel(level)
    RC:SkinFrame(frame, nil, true)
    RC:SetFrameThemeRole(frame, role or "Color")
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    return frame
end

local function CreateShellFontString(parent, justify, size, flags)
    local text = parent:CreateFontString(nil, "OVERLAY")
    RC:SetFont(text, size or RC:GetThemeLayout("fontNormal", 12), flags or "")
    text:SetJustifyH(justify or "LEFT")
    return text
end

local function CreateSidebarQuickAction(shell, labelText, glyphText, iconIndex, onClick)
    local button = CreateFrame("Button", nil, shell.sidebar)
    button:SetFrameLevel(shell.sidebar:GetFrameLevel() + 18)
    button:EnableMouse(true)

    local hover = button:CreateTexture(nil, "BACKGROUND")
    hover:SetAllPoints()
    hover:Hide()

    local indicator = button:CreateTexture(nil, "ARTWORK")
    indicator:SetPoint("TOPLEFT", button, "TOPLEFT", 0, -4)
    indicator:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 4)
    indicator:SetWidth(2)

    local glyphBox = CreateFrame("Frame", nil, button, "BackdropTemplate")
    glyphBox:SetSize(32, 32)
    glyphBox:SetPoint("LEFT", button, "LEFT", 20, 0)
    RC:SkinFrame(glyphBox, nil, true)
    local glyph = CreateShellFontString(glyphBox, "CENTER", 10, "OUTLINE")
    glyph:SetPoint("CENTER")
    glyph:SetText(glyphText or "")

    local icon = glyphBox:CreateTexture(nil, "ARTWORK")
    icon:SetSize(25, 25)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\AddOns\\RaidControl\\Media\\settings-nav.png")
    local cellWidth = 1 / 5
    local left = ((iconIndex or 1) - 1) * cellWidth
    icon:SetTexCoord(left, left + cellWidth, 0, 1)
    glyph:Hide()

    local label = CreateShellFontString(button, "LEFT", 12, "OUTLINE")
    label:SetPoint("LEFT", glyphBox, "RIGHT", 10, 0)
    label:SetPoint("RIGHT", button, "RIGHT", -28, 0)
    label:SetText(labelText or "")

    local arrow = CreateShellFontString(button, "CENTER", 12, "OUTLINE")
    arrow:SetPoint("RIGHT", button, "RIGHT", -18, 0)
    arrow:SetText(">")

    button.hover = hover
    button.indicator = indicator
    button.glyphBox = glyphBox
    button.glyph = glyph
    button.icon = icon
    button.label = label
    button.arrow = arrow

    function button:RefreshTheme()
        local accent = RC.Config.Accent
        hover:SetColorTexture(accent.r, accent.g, accent.b, 0.075)
        indicator:SetColorTexture(accent.r, accent.g, accent.b, self.selected and 1 or 0.90)
        indicator:SetShown(self.hovered or self.selected or false)
        glyphBox:SetBackdropColor(0, 0, 0, 0)
        glyphBox:SetBackdropBorderColor(0, 0, 0, 0)
        glyph:SetTextColor(accent.r, accent.g, accent.b, self.hovered and 1 or 0.74)
        icon:SetVertexColor(
            (self.hovered or self.selected) and accent.r or RC.Config.MutedText.r,
            (self.hovered or self.selected) and accent.g or RC.Config.MutedText.g,
            (self.hovered or self.selected) and accent.b or RC.Config.MutedText.b,
            (self.hovered or self.selected) and 1 or 0.72
        )
        local emphasized = self.hovered or self.selected
        label:SetTextColor(
            emphasized and RC.Config.HeaderText.r or RC.Config.MutedText.r,
            emphasized and RC.Config.HeaderText.g or RC.Config.MutedText.g,
            emphasized and RC.Config.HeaderText.b or RC.Config.MutedText.b,
            emphasized and 1 or 0.86
        )
        arrow:SetTextColor(accent.r, accent.g, accent.b, emphasized and 0.95 or 0.42)
    end

    function button:SetSelected(selected)
        self.selected = selected and true or false
        self:RefreshTheme()
    end

    button:SetScript("OnEnter", function(self)
        self.hovered = true
        hover:Show()
        self:RefreshTheme()
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered = false
        hover:Hide()
        self:RefreshTheme()
    end)
    button:SetScript("OnClick", function()
        if onClick then
            onClick()
        end
    end)
    RC:RegisterThemeWidget(button)
    button:RefreshTheme()
    return button
end

local function WireAliases(settings, shell)
    settings.frame = shell.frame
    settings.themeHeader = shell.header
    settings.themeSidebar = shell.sidebar
    settings.themeContentShell = shell.contentFrame
    settings.navAnchor = shell.sidebarNav
    settings.contentInset = shell.scroll
    settings.modernTabBar = shell.topTabs
    settings.modernFooter = shell.footer
    settings.modernTabBarBg = shell.topTabsBg
    settings.modernTabBarLine = shell.topTabsLine
    settings.modernFooterLine = shell.footerLine
    settings.themeHeaderAccent = shell.headerAccent
    settings.themeHeaderSeparator = shell.headerSeparator
    settings.themeSidebarSeparatorFrame = shell.sidebarSeparator
    settings.themeSidebarSeparator = shell.sidebarSeparatorTexture
    settings.modernPageTitle = shell.title
    settings.modernPageDescription = shell.description
    settings.sidebarBrand = shell.brand
    settings.sidebarTagline = shell.tagline
    settings.sidebarSectionLabel = shell.sectionLabel
    settings.sidebarVersionText = shell.versionText
    settings.searchBox = shell.searchBox
    settings.searchPlaceholder = shell.searchPlaceholder
    settings.searchClearButton = shell.searchClearButton
    settings.pageSearchBox = shell.pageSearchBox
    settings.pageSearchPlaceholder = shell.pageSearchPlaceholder
    settings.pageSearchClearButton = shell.pageSearchClearButton
    settings.closeButton = shell.closeButton
    settings.headerScaleSlider = shell.scaleSlider
    settings.headerScaleLabel = shell.scaleLabel
    settings.modernReloadButton = shell.reloadButton
    settings.layoutModeButton = shell.layoutButton
    settings.modernDoneButton = shell.doneButton
    settings.sidebarContainer = shell.sidebarContainer
    settings.contentContainer = shell.contentContainer
end

function V2.Shell:Create(settings, options)
    options = options or {}

    if settings and settings.v2Shell and settings.v2Shell.frame then
        return settings.v2Shell
    end

    local frame = RC:CreatePanel(nil, UIParent, RC:GetThemeLayout("settingsWidth", 980), RC:GetThemeLayout("settingsHeight", 640))
    if settings then
        settings.frame = frame
    end
    frame:Hide()
    frame.rcBorderMinAlpha = 0
    frame:SetPoint("CENTER")
    frame:SetScale(RC.db and RC.db.profile and tonumber(RC.db.profile.settingsScale) or 1)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    if RC.RegisterEscapeFrame then
        RC:RegisterEscapeFrame(frame)
    end
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(120)
    SafeSetClipsChildren(frame, true)
    RC:SetFrameThemeRole(frame, "Color")
    frame:SetBackdropBorderColor(0, 0, 0, 0)

    local level = frame:GetFrameLevel()
    local shell = {
        frame = frame,
        header = CreateSkinnedRegion(frame, level + 20, "HeaderBg"),
        sidebar = CreateSkinnedRegion(frame, level + 12, "HeaderBg"),
        contentFrame = CreateSkinnedRegion(frame, level + 8, "Color"),
        topTabs = CreateFrame("Frame", nil, frame),
        scroll = CreateFrame("Frame", nil, frame),
        footer = CreateSkinnedRegion(frame, level + 18, "HeaderBg"),
    }

    shell.backgroundLayer = CreateFrame("Frame", nil, frame)
    shell.backgroundLayer:SetAllPoints(frame)
    shell.backgroundLayer:SetFrameLevel(level + 1)
    shell.backgroundTexture = shell.backgroundLayer:CreateTexture(nil, "BACKGROUND")
    shell.backgroundTexture:SetAllPoints()
    shell.backgroundTexture:SetTexture("Interface\\AddOns\\RaidControl\\Media\\settings-shell.png")
    shell.topTabs:SetFrameLevel(level + 18)
    shell.scroll:SetFrameLevel(level + 9)
    SafeSetClipsChildren(shell.scroll, true)
    SafeSetClipsChildren(shell.contentFrame, true)
    shell.footer:Show()

    shell.headerAccent = shell.header:CreateTexture(nil, "ARTWORK")
    shell.headerAccent:SetPoint("TOPLEFT", shell.header, "TOPLEFT", 0, 0)
    shell.headerAccent:SetPoint("BOTTOMLEFT", shell.header, "BOTTOMLEFT", 0, 0)
    shell.headerAccent:SetWidth(3)

    shell.headerGlow = shell.header:CreateTexture(nil, "ARTWORK")
    shell.headerGlow:SetPoint("BOTTOMLEFT", shell.header, "BOTTOMLEFT", 0, 0)
    shell.headerGlow:SetPoint("BOTTOMRIGHT", shell.header, "BOTTOMRIGHT", 0, 0)
    shell.headerGlow:SetHeight(2)

    shell.headerGlowSoft = shell.header:CreateTexture(nil, "BACKGROUND", nil, 2)
    shell.headerGlowSoft:SetPoint("BOTTOMLEFT", shell.header, "BOTTOMLEFT", 0, 0)
    shell.headerGlowSoft:SetPoint("BOTTOMRIGHT", shell.header, "BOTTOMRIGHT", 0, 0)
    shell.headerGlowSoft:SetHeight(18)

    shell.brandRule = shell.sidebar:CreateTexture(nil, "ARTWORK")
    shell.brandRule:SetPoint("TOPLEFT", shell.sidebar, "TOPLEFT", 18, -78)
    shell.brandRule:SetPoint("TOPRIGHT", shell.sidebar, "TOPRIGHT", -18, -78)
    shell.brandRule:SetHeight(1)

    shell.headerSeparatorFrame = CreateFrame("Frame", nil, frame)
    shell.headerSeparatorFrame:SetFrameLevel(level + 25)
    shell.headerSeparator = shell.headerSeparatorFrame:CreateTexture(nil, "ARTWORK")
    shell.headerSeparator:SetAllPoints()

    shell.sidebarSeparator = CreateFrame("Frame", nil, frame)
    shell.sidebarSeparator:SetFrameLevel(level + 25)
    shell.sidebarSeparatorTexture = shell.sidebarSeparator:CreateTexture(nil, "ARTWORK")
    shell.sidebarSeparatorTexture:SetAllPoints()

    shell.topTabsBg = shell.topTabs:CreateTexture(nil, "BACKGROUND")
    shell.topTabsBg:SetAllPoints()
    shell.topTabsLine = shell.topTabs:CreateTexture(nil, "ARTWORK")
    shell.topTabsLine:SetPoint("BOTTOMLEFT", shell.topTabs, "BOTTOMLEFT", 0, 0)
    shell.topTabsLine:SetPoint("BOTTOMRIGHT", shell.topTabs, "BOTTOMRIGHT", 0, 0)
    shell.topTabsLine:SetHeight(1)

    shell.footerLine = shell.footer:CreateTexture(nil, "ARTWORK")
    shell.footerLine:SetPoint("TOPLEFT", shell.footer, "TOPLEFT", 0, 0)
    shell.footerLine:SetPoint("TOPRIGHT", shell.footer, "TOPRIGHT", 0, 0)
    shell.footerLine:SetHeight(1)

    shell.sidebarNav = CreateFrame("Frame", nil, shell.sidebar)
    shell.sidebarNav:SetFrameLevel(level + 13)

    shell.title = CreateShellFontString(shell.header, "LEFT", 15, "OUTLINE")
    shell.title:SetText(L["Interface"])

    shell.description = CreateShellFontString(shell.header, "LEFT", 9, "")
    shell.description:SetText("")

    shell.logoMark = CreateFrame("Frame", nil, shell.sidebar, "BackdropTemplate")
    shell.logoMark:SetFrameLevel(level + 20)
    RC:SkinFrame(shell.logoMark, nil, true)
    shell.logoMarkText = CreateShellFontString(shell.logoMark, "CENTER", 15, "OUTLINE")
    shell.logoMarkText:SetPoint("CENTER")
    shell.logoMarkText:SetText("RC")
    shell.logoMarkText:Hide()

    shell.logoMarkTexture = shell.logoMark:CreateTexture(nil, "ARTWORK")
    shell.logoMarkTexture:SetPoint("CENTER")
    shell.logoMarkTexture:SetSize(40, 40)
    shell.logoMarkTexture:SetTexture("Interface\\AddOns\\RaidControl\\Media\\settings-nav.png")
    shell.logoMarkTexture:SetTexCoord(4 / 5, 1, 0, 1)

    shell.brand = CreateShellFontString(shell.sidebar, "LEFT", RC:IsShadowsteelTheme() and 18 or 20, "OUTLINE")
    shell.brand:SetText("RaidControl")

    shell.tagline = CreateShellFontString(shell.sidebar, "LEFT", 9, "OUTLINE")
    shell.tagline:SetText(L["RAID LEADERSHIP SUITE"])

    shell.quickActions = {
        CreateSidebarQuickAction(shell, L["Unlock Mode"], "U", 1, function()
            if settings and settings.ToggleLayoutModeFromSettings then
                settings:ToggleLayoutModeFromSettings()
            end
        end),
        CreateSidebarQuickAction(shell, L["Raid Split"], "R", 2, function()
            local workspace = RC:GetModule("Workspace", true)
            if workspace and workspace.Open then
                workspace:Open("split")
            end
        end),
    }
    shell.quickActions[2].workspaceKey = "split"

    shell.sectionLabel = CreateShellFontString(shell.sidebar, "LEFT", RC:IsShadowsteelTheme() and 10 or 11, "OUTLINE")
    shell.sectionLabel:SetText("SETTINGS")

    shell.versionText = CreateShellFontString(shell.sidebar, "CENTER", 9, "OUTLINE")
    shell.versionText:SetText(RC.version and ("v" .. RC.version) or "")

    shell.searchBox = CreateFrame("EditBox", nil, shell.sidebar, "BackdropTemplate")
    shell.searchBox:SetFrameLevel(level + 30)
    shell.searchBox:SetAutoFocus(false)
    shell.searchBox:SetMaxLetters(80)
    shell.searchBox:SetFont(RC:GetFont(), 11, "")
    shell.searchBox:SetTextInsets(9, 28, 0, 0)
    RC:SkinFrame(shell.searchBox)
    RC:SetFrameThemeRole(shell.searchBox, "InputBg")

    shell.searchPlaceholder = CreateShellFontString(shell.searchBox, "LEFT", 10, "")
    shell.searchPlaceholder:SetPoint("LEFT", shell.searchBox, "LEFT", 9, 0)
    shell.searchPlaceholder:SetPoint("RIGHT", shell.searchBox, "RIGHT", -28, 0)
    shell.searchPlaceholder:SetText(L["Search settings..."])

    shell.searchClearButton = RC:CreateCloseButton(shell.searchBox, 14)
    shell.searchClearButton:SetFrameLevel(shell.searchBox:GetFrameLevel() + 2)
    shell.searchClearButton:SetPoint("RIGHT", shell.searchBox, "RIGHT", -6, 0)
    shell.searchClearButton:Hide()

    -- Parented to the window, not the sub-tab bar: page rebuilds hide that bar,
    -- and a hidden parent would take the box (and keyboard focus) with it.
    shell.pageSearchBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    shell.pageSearchBox:SetFrameLevel(shell.topTabs:GetFrameLevel() + 20)
    shell.pageSearchBox:SetAutoFocus(false)
    shell.pageSearchBox:SetMaxLetters(80)
    shell.pageSearchBox:SetFont(RC:GetFont(), 11, "")
    shell.pageSearchBox:SetTextInsets(9, 28, 0, 0)
    RC:SkinFrame(shell.pageSearchBox)
    RC:SetFrameThemeRole(shell.pageSearchBox, "InputBg")

    shell.pageSearchPlaceholder = CreateShellFontString(shell.pageSearchBox, "LEFT", 10, "")
    shell.pageSearchPlaceholder:SetPoint("LEFT", shell.pageSearchBox, "LEFT", 9, 0)
    shell.pageSearchPlaceholder:SetPoint("RIGHT", shell.pageSearchBox, "RIGHT", -28, 0)
    shell.pageSearchPlaceholder:SetText(L["Search settings..."])

    shell.pageSearchClearButton = RC:CreateCloseButton(shell.pageSearchBox, 14)
    shell.pageSearchClearButton:SetFrameLevel(shell.pageSearchBox:GetFrameLevel() + 2)
    shell.pageSearchClearButton:SetPoint("RIGHT", shell.pageSearchBox, "RIGHT", -6, 0)
    shell.pageSearchClearButton:Hide()

    local function RefreshSearchTheme(searchBox, placeholder)
        RC:SetFrameThemeRole(searchBox, "InputBg")
        local border = RC.Config.InputBorder or RC.Config.Border
        if border then
            searchBox:SetBackdropBorderColor(border.r, border.g, border.b, math.max(0.20, border.a or 0))
        end
        local textR, textG, textB = RC:GetGeneralTextColor()
        searchBox:SetTextColor(textR, textG, textB, 1)
        local muted = RC.Config.MutedText
        if muted and placeholder then
            placeholder:SetTextColor(muted.r, muted.g, muted.b, 0.72)
        end
    end

    function shell.searchBox:RefreshTheme()
        RefreshSearchTheme(self, shell.searchPlaceholder)
    end
    function shell.pageSearchBox:RefreshTheme()
        RefreshSearchTheme(self, shell.pageSearchPlaceholder)
    end
    RC:RegisterThemeWidget(shell.searchBox)
    RC:RegisterThemeWidget(shell.pageSearchBox)
    shell.searchBox:RefreshTheme()
    shell.pageSearchBox:RefreshTheme()

    local function RefreshSearchChrome(searchBox, placeholder, clearButton)
        local hasText = searchBox:GetText() ~= ""
        placeholder:SetShown(not hasText and not searchBox:HasFocus())
        clearButton:SetShown(hasText)
    end

    local function HandleSearchChanged(source, placeholder, clearButton)
        RefreshSearchChrome(source, placeholder, clearButton)
        if shell.syncingSearchText then
            return
        end
        local workspace = RC:GetModule("Workspace", true)
        if workspace and workspace.Open and workspace.activeKey and workspace.activeKey ~= "settings" then
            workspace:Open("settings")
        end
        shell.syncingSearchText = true
        local target = source == shell.searchBox and shell.pageSearchBox or shell.searchBox
        if target and target:GetText() ~= source:GetText() then
            target:SetText(source:GetText())
        end
        shell.syncingSearchText = nil
        if settings and settings.HandleSearchChanged and not settings.searchTextGuard then
            settings:HandleSearchChanged(source:GetText())
        end
    end

    local function ConfigureSearchBox(searchBox, placeholder, clearButton)
        searchBox:SetScript("OnEditFocusGained", function(self)
            RefreshSearchChrome(self, placeholder, clearButton)
        end)
        searchBox:SetScript("OnEditFocusLost", function(self)
            RefreshSearchChrome(self, placeholder, clearButton)
        end)
        searchBox:SetScript("OnTextChanged", function(self)
            HandleSearchChanged(self, placeholder, clearButton)
        end)
        searchBox:SetScript("OnEnterPressed", function(self)
            if settings and settings.OpenFirstSearchResult then
                settings:OpenFirstSearchResult()
            end
            self:ClearFocus()
        end)
        searchBox:SetScript("OnEscapePressed", function(self)
            if self:GetText() ~= "" then
                self:SetText("")
            else
                self:ClearFocus()
            end
        end)
        clearButton:SetScript("OnClick", function()
            searchBox:SetText("")
            searchBox:SetFocus()
        end)
    end

    ConfigureSearchBox(shell.searchBox, shell.searchPlaceholder, shell.searchClearButton)
    ConfigureSearchBox(shell.pageSearchBox, shell.pageSearchPlaceholder, shell.pageSearchClearButton)

    shell.dragHandle = CreateFrame("Frame", nil, shell.header)
    shell.dragHandle:SetFrameLevel(shell.header:GetFrameLevel() + 1)
    shell.dragHandle:EnableMouse(true)
    shell.dragHandle:RegisterForDrag("LeftButton")
    shell.dragHandle:SetScript("OnDragStart", function()
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        local target = frame.rcWorkspaceHost or frame
        if target and target.StartMoving then
            target:StartMoving()
        end
    end)
    shell.dragHandle:SetScript("OnDragStop", function()
        local target = frame.rcWorkspaceHost or frame
        if target and target.StopMovingOrSizing then
            target:StopMovingOrSizing()
        end
        local workspace = RC:GetModule("Workspace", true)
        if frame.rcWorkspaceHost and workspace and workspace.SaveHostPosition then
            workspace:SaveHostPosition()
        end
    end)

    shell.closeButton = RC:CreateCloseButton(shell.header, 20)
    shell.closeButton:SetFrameLevel(shell.header:GetFrameLevel() + 30)
    shell.closeButton:SetScript("OnClick", function()
        frame:Hide()
    end)

    if options.createScaleSlider then
        shell.scaleSlider, shell.scaleLabel = options.createScaleSlider(shell.header, shell.closeButton, level + 40)
    end

    shell.reloadButton = RC:CreateStandardButton(nil, shell.footer, 110, 30)
    shell.reloadButton.Text:SetText(L["Reload UI"])
    shell.reloadButton:SetScript("OnClick", ReloadUI)

    shell.layoutButton = RC:CreateStandardButton(nil, shell.footer, 150, 30)
    shell.layoutButton.Text:SetText(L["Unlock UI"])
    shell.layoutButton:SetScript("OnClick", function()
        if settings and settings.ToggleLayoutModeFromSettings then
            settings:ToggleLayoutModeFromSettings()
        end
    end)

    shell.doneButton = RC:CreateStandardButton(nil, shell.footer, 110, 30)
    shell.doneButton.Text:SetText(L["Close"])
    shell.doneButton:SetScript("OnClick", function()
        local workspace = RC:GetModule("Workspace", true)
        if frame.rcWorkspaceHosted and workspace and workspace.CloseActiveWindow then
            workspace:CloseActiveWindow()
        else
            frame:Hide()
        end
    end)

    shell.closeButton:SetScript("OnClick", function()
        local workspace = RC:GetModule("Workspace", true)
        if frame.rcWorkspaceHosted and workspace and workspace.CloseActiveWindow then
            workspace:CloseActiveWindow()
        else
            frame:Hide()
        end
    end)

    shell.sidebarContainer = AceGUI:Create("SimpleGroup")
    shell.sidebarContainer.frame:SetParent(shell.sidebarNav)
    shell.sidebarContainer.frame:SetAllPoints()
    shell.sidebarContainer.frame:SetFrameStrata(frame:GetFrameStrata())
    shell.sidebarContainer.frame:SetFrameLevel(level + 14)
    shell.sidebarContainer:SetLayout("Flow")

    shell.contentContainer = AceGUI:Create("SimpleGroup")
    shell.contentContainer.frame:SetParent(shell.scroll)
    shell.contentContainer.frame:SetAllPoints()
    shell.contentContainer.frame:SetFrameStrata(frame:GetFrameStrata())
    shell.contentContainer.frame:SetFrameLevel(level + 10)
    SafeSetClipsChildren(shell.contentContainer.frame, true)
    shell.contentContainer:SetLayout("Fill")

    shell.externalPageLayer = CreateFrame("Frame", nil, shell.contentFrame)
    shell.externalPageLayer:SetFrameLevel(level + 14)
    SafeSetClipsChildren(shell.externalPageLayer, true)
    shell.externalPageLayer:Hide()

    function shell:SetWorkspacePage(key)
        local settingsActive = key == "settings"
        self.workspacePageKey = key
        self.scroll:SetShown(settingsActive)
        self.externalPageLayer:SetShown(not settingsActive)
        if self.pageSearchBox then
            self.pageSearchBox:SetShown(settingsActive)
        end
        if not settingsActive then
            self.topTabs:Hide()
        elseif settings and settings.activeSubTabRow then
            self.topTabs:Show()
        end
        for _, action in ipairs(self.quickActions or {}) do
            if action.SetSelected then
                action:SetSelected(action.workspaceKey == key)
            end
        end
    end

    settings.v2Shell = shell
    WireAliases(settings, shell)

    if V2.Layout then
        V2.Layout:Apply(shell)
    end
    if V2.ThemeBridge then
        V2.ThemeBridge:Apply(settings)
    end

    return shell
end

function V2.Shell:ClearContent(settings)
    local shell = settings and settings.v2Shell
    if not shell then
        return
    end

    settings.v2ContentBuildToken = (settings.v2ContentBuildToken or 0) + 1

    if V2.Sections and V2.Sections.ClearContainer then
        V2.Sections:ClearContainer(shell.scrollWidget)
        V2.Sections:ClearContainer(settings.scroll)
    end
    if settings.activeSubTabRow then
        settings.activeSubTabRow:Release()
        settings.activeSubTabRow = nil
    end
    if shell.topTabs then
        shell.topTabs:Hide()
    end
    if RC.ActiveDropdowns then
        for pullout in pairs(RC.ActiveDropdowns) do
            if pullout and pullout.Hide then
                pullout:Hide()
            end
        end
    end

    if shell.contentContainer and shell.contentContainer.ReleaseChildren then
        shell.contentContainer:ReleaseChildren()
    end

    shell.scrollWidget = nil
    shell.scrollChild = nil
    settings.scroll = nil
    settings.v2ScrollChild = nil
end

function V2.Shell:CreateScroll(settings, key)
    local shell = settings and settings.v2Shell
    if not shell or not shell.contentContainer then
        return nil
    end

    self:ClearContent(settings)

    local scroll = AceGUI:Create("RC_ScrollFrame")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    scroll:SetLayout("Flow")
    if scroll.frame then
        SafeSetClipsChildren(scroll.frame, true)
    end
    if scroll.content then
        SafeSetClipsChildren(scroll.content, true)
    end

    settings.scrollStatusByTab = settings.scrollStatusByTab or {}
    settings.scrollStatusByTab[key] = settings.scrollStatusByTab[key] or { scrollvalue = 0, offset = 0 }
    if scroll.SetStatusTable then
        scroll:SetStatusTable(settings.scrollStatusByTab[key])
    end

    shell.contentContainer:AddChild(scroll)
    if shell.contentContainer.DoLayout then
        shell.contentContainer:DoLayout()
    end
    shell.scrollWidget = scroll
    shell.scrollChild = scroll.content
    settings.scroll = scroll
    settings.v2ScrollChild = scroll.content
    return scroll
end
