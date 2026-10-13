local addonName, ns = ...
local RC = ns.RC
local L = RC.L
local Media = RC:NewModule("Media")

-- =============================================================================
-- RAIDCONTROL DESIGN SYSTEM
-- =============================================================================
-- Single source of truth for all visual styles and widget constructors.
-- Every UI element (TopBar, panels, AceGUI widgets) reads from RC.Config.
-- =============================================================================

local function Color(r, g, b, a)
    return { r = r, g = g, b = b, a = a == nil and 1 or a }
end

RC.Config = {
    -- Standard Backdrop (1px border, flat texture)
    Backdrop = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    },
    -- Base colors
    Color          = Color(0.050, 0.070, 0.090, 0.98),
    HeaderBg       = Color(0.035, 0.052, 0.068, 0.98),
    SurfaceBg      = Color(0.061, 0.095, 0.120, 0.62),
    AltRowBg       = Color(0.000, 0.000, 0.000, 0.12),
    ButtonBg       = Color(0.061, 0.095, 0.120, 0.60),
    ButtonPressed  = Color(0.035, 0.060, 0.075, 0.82),
    ButtonHover    = Color(0.084, 0.124, 0.152, 0.70),
    ButtonDisabled = Color(0.050, 0.055, 0.060, 0.55),
    InputBg        = Color(0.020, 0.030, 0.040, 0.25),
    InputBorder    = Color(0.120, 0.170, 0.200, 0.88),
    InputFocus     = Color(0.047, 0.824, 0.616, 0.90),
    Border         = Color(0.105, 0.145, 0.170, 0.82),
    StrongBorder   = Color(0.140, 0.190, 0.220, 0.90),
    SeparatorColor = Color(0.085, 0.120, 0.140, 0.60),
    Accent         = Color(0.047, 0.824, 0.616, 1.00),
    AccentHover    = Color(0.090, 0.900, 0.690, 1.00),
    Selected       = Color(0.047, 0.824, 0.616, 0.82),
    WarningColor   = Color(1.000, 0.820, 0.220, 1.00),
    ErrorColor     = Color(0.750, 0.150, 0.150, 1.00),
    DangerColor    = Color(0.750, 0.150, 0.150, 1.00),
    SuccessColor   = Color(0.350, 1.000, 0.350, 1.00),
    SliderTrack    = Color(1.000, 1.000, 1.000, 0.16),
    SliderFill     = Color(0.047, 0.824, 0.616, 0.75),
    SliderThumb    = Color(0.047, 0.824, 0.616, 0.95),
    DropdownBg     = Color(0.061, 0.095, 0.120, 0.70),
    DropdownBorder = Color(0.120, 0.170, 0.200, 0.88),
    DropdownHover  = Color(1.000, 1.000, 1.000, 0.08),
    DropdownSelected = Color(0.047, 0.824, 0.616, 0.12),
    CheckboxBg     = Color(0.100, 0.120, 0.160, 1.00),
    CheckboxChecked = Color(0.047, 0.824, 0.616, 0.90),
    CheckboxUnchecked = Color(0.267, 0.267, 0.267, 0.65),
    Shadow         = Color(0.000, 0.000, 0.000, 0.45),
    Glow           = Color(0.047, 0.824, 0.616, 0.10),
    Header         = Color(1.000, 1.000, 1.000, 0.92),
    HeaderText     = Color(1.000, 1.000, 1.000, 0.92),
    Text           = Color(1.000, 1.000, 1.000, 0.92),
    DisabledText   = Color(0.420, 0.460, 0.500, 1.00),
    WhiteText      = Color(1.000, 1.000, 1.000, 1.00),
    MutedText      = Color(1.000, 1.000, 1.000, 0.53),
    RowBg          = Color(0.000, 0.000, 0.000, 0.10),
    RowAltBg       = Color(0.000, 0.000, 0.000, 0.18),
    RowHover       = Color(1.000, 1.000, 1.000, 0.06),
    SectionBg      = Color(0.061, 0.095, 0.120, 0.46),
    SectionBorder  = Color(0.085, 0.120, 0.140, 0.60),
    SectionAccent  = Color(0.047, 0.824, 0.616, 0.70),
    NavBg          = Color(0.000, 0.000, 0.000, 0.00),
    NavHover       = Color(1.000, 1.000, 1.000, 0.06),
    NavSelectedBg  = Color(0.047, 0.824, 0.616, 0.10),
    NavSelectedBorder = Color(0.047, 0.824, 0.616, 0.72),
    NavText        = Color(1.000, 1.000, 1.000, 0.53),
    NavSelectedText = Color(1.000, 1.000, 1.000, 0.94),
    TabBg          = Color(0.035, 0.052, 0.068, 0.54),
    TabHover       = Color(1.000, 1.000, 1.000, 0.06),
    TabSelectedBg  = Color(0.061, 0.095, 0.120, 0.74),
    TabSelectedText = Color(1.000, 1.000, 1.000, 0.96),
    ScrollTrack    = Color(1.000, 1.000, 1.000, 0.08),
    ScrollThumb    = Color(0.047, 0.824, 0.616, 0.58),
    -- Role colors (used in tooltips and role displays)
    RoleColors   = {
        TANK   = Color(0.30, 0.60, 1.00, 1.00),
        HEALER = Color(0.30, 0.90, 0.30, 1.00),
        DPS    = Color(0.90, 0.35, 0.35, 1.00),
    },
}

RC.WorkspaceSize = {
    width = 1180,
    height = 720,
}

RC.ThemeOrder = { "Shadowsteel", "Starforge" }

RC.ThemeDefinitions = {
    Shadowsteel = {
        key = "Shadowsteel",
        label = "Shadowsteel",
        style = "shadowsteel",
        colors = {
            background = Color(0.036, 0.046, 0.054, 0.94),
            header = Color(0.026, 0.034, 0.040, 0.88),
            surface = Color(0.065, 0.078, 0.088, 0.58),
            altRow = Color(0.000, 0.000, 0.000, 0.18),
            control = Color(0.075, 0.090, 0.102, 0.90),
            buttonHover = Color(0.130, 0.150, 0.162, 0.74),
            buttonPressed = Color(0.042, 0.115, 0.155, 0.84),
            input = Color(0.018, 0.026, 0.032, 0.72),
            border = Color(0.105, 0.145, 0.170, 0.82),
            strongBorder = Color(0.140, 0.190, 0.220, 0.90),
            separator = Color(0.085, 0.120, 0.140, 0.60),
            accent = Color(0.090, 0.520, 0.820, 1.00),
            accentHover = Color(0.140, 0.620, 0.920, 1.00),
            selected = Color(0.090, 0.520, 0.820, 1.00),
            warning = Color(1.000, 0.820, 0.000, 1.00),
            error = Color(0.750, 0.150, 0.150, 1.00),
            success = Color(0.300, 0.900, 0.300, 1.00),
            sliderTrack = Color(1.000, 1.000, 1.000, 0.14),
            sliderFill = Color(0.090, 0.520, 0.820, 0.90),
            sliderThumb = Color(0.090, 0.520, 0.820, 0.90),
            dropdownBg = Color(0.035, 0.046, 0.054, 0.94),
            dropdownBorder = Color(0.120, 0.170, 0.200, 0.88),
            dropdownHover = Color(1.000, 1.000, 1.000, 0.08),
            dropdownSelected = Color(0.090, 0.520, 0.820, 0.18),
            checkboxBg = Color(0.110, 0.125, 0.135, 0.86),
            checkboxChecked = Color(0.090, 0.520, 0.820, 0.90),
            checkboxUnchecked = Color(0.600, 0.600, 0.600, 0.80),
            inputBorder = Color(0.120, 0.170, 0.200, 0.88),
            inputFocus = Color(0.090, 0.520, 0.820, 1.00),
            shadow = Color(0.000, 0.000, 0.000, 0.55),
            glow = Color(0.090, 0.520, 0.820, 0.06),
            headerText = Color(1.000, 1.000, 1.000, 1.00),
            text = Color(1.000, 1.000, 1.000, 1.00),
            mutedText = Color(0.608, 0.608, 0.608, 1.00),
            disabledText = Color(0.600, 0.600, 0.600, 0.80),
            rowBg = Color(0.000, 0.000, 0.000, 0.10),
            rowAlt = Color(0.000, 0.000, 0.000, 0.20),
            rowHover = Color(1.000, 1.000, 1.000, 0.055),
            sectionBg = Color(0.000, 0.000, 0.000, 0.00),
            sectionBorder = Color(0.085, 0.120, 0.140, 0.60),
            sectionAccent = Color(0.090, 0.520, 0.820, 0.85),
            navBg = Color(0.000, 0.000, 0.000, 0.00),
            navHover = Color(1.000, 1.000, 1.000, 0.045),
            navSelectedBg = Color(0.090, 0.520, 0.820, 0.075),
            navSelectedBorder = Color(0.090, 0.520, 0.820, 0.82),
            navText = Color(0.608, 0.608, 0.608, 0.94),
            navSelectedText = Color(1.000, 1.000, 1.000, 1.00),
            tabBg = Color(0.020, 0.028, 0.034, 0.36),
            tabHover = Color(1.000, 1.000, 1.000, 0.045),
            tabSelectedBg = Color(0.090, 0.520, 0.820, 0.00),
            tabSelectedText = Color(1.000, 1.000, 1.000, 1.00),
            scrollTrack = Color(1.000, 1.000, 1.000, 0.07),
            scrollThumb = Color(0.090, 0.520, 0.820, 0.62),
        },
        layout = {
            shellStyle = "shadowsteel",
            settingsWidth = RC.WorkspaceSize.width,
            settingsHeight = RC.WorkspaceSize.height,
            sidebarWidth = 260,
            headerHeight = 108,
            footerHeight = 60,
            sidebarFullHeight = true,
            headerContentOnly = true,
            footerContentOnly = true,
            rowHeight = 44,
            compactRowHeight = 36,
            settingsRowHeight = 44,
            descriptionRowHeight = 46,
            labelColumnWidth = 0.46,
            controlColumnWidth = 0.54,
            controlAlign = "right",
            settingsColumnGap = 0,
            settingsColumns = 2,
            contentPaddingX = 38,
            contentPaddingY = 24,
            sectionGap = 20,
            sectionPadX = 0,
            sectionBase = 44,
            sectionBaseWithDescription = 60,
            sectionBottomPad = 12,
            sectionAccentWidth = 2,
            rowSeparatorAlpha = 0.055,
            controlHeight = 28,
            buttonHeight = 30,
            dropdownHeight = 28,
            inputHeight = 28,
            sliderHeight = 14,
            sliderTrackHeight = 5,
            sliderThumbWidth = 12,
            sliderThumbHeight = 12,
            sliderValueWidth = 46,
            sliderValueHeight = 28,
            dropdownItemHeight = 28,
            scrollbarWidth = 4,
            scrollbarThumbHeight = 34,
            settingsScrollbarWidth = 8,
            settingsScrollbarGutter = 44,
            settingsScrollbarOuterInset = 8,
            settingsContentRightInset = 32,
            navItemHeight = 40,
            navItemGap = 2,
            navGlyphSize = 26,
            navGlyphFont = 9,
            navLabelFont = 11,
            navTextOffset = 38,
            navSelectedIndicatorStyle = "left-edge",
            tabBarHeight = 44,
            tabHeight = 43,
            tabFont = 14,
            sectionHeaderFont = 12,
            sectionDescriptionFont = 9,
            borderThickness = 1,
            cornerRadius = 1,
            panelPadding = 22,
            panelShadowAlpha = 0.52,
            panelGlowAlpha = 0.00,
            raidSplitHeaderHeight = 44,
            raidSplitActionBarHeight = 38,
            raidSplitPanelPad = 8,
            raidSplitPanelGap = 6,
            launcherWidth = 232,
            launcherHeight = 30,
            menuFooterHeight = 34,
            fontSmall = 10,
            fontNormal = 12,
            fontLarge = 16,
        },
    },
    Starforge = {
        key = "Starforge",
        label = "Starforge",
        style = "starforge",
        colors = {
            background = Color(0.050, 0.070, 0.090, 0.98),
            header = Color(0.035, 0.052, 0.068, 0.98),
            surface = Color(0.061, 0.095, 0.120, 0.62),
            altRow = Color(0.000, 0.000, 0.000, 0.14),
            control = Color(0.075, 0.113, 0.141, 0.90),
            buttonHover = Color(0.090, 0.132, 0.160, 0.72),
            buttonPressed = Color(0.040, 0.070, 0.086, 0.86),
            input = Color(0.020, 0.030, 0.040, 0.25),
            border = Color(0.105, 0.145, 0.170, 0.82),
            strongBorder = Color(0.140, 0.190, 0.220, 0.90),
            separator = Color(0.085, 0.120, 0.140, 0.60),
            accent = Color(12 / 255, 210 / 255, 157 / 255, 1.00),
            accentHover = Color(0.090, 0.900, 0.690, 1.00),
            selected = Color(12 / 255, 210 / 255, 157 / 255, 0.78),
            warning = Color(1.000, 0.820, 0.220, 1.00),
            error = Color(0.750, 0.150, 0.150, 1.00),
            success = Color(0.350, 1.000, 0.350, 1.00),
            sliderTrack = Color(1.000, 1.000, 1.000, 0.16),
            sliderFill = Color(12 / 255, 210 / 255, 157 / 255, 0.75),
            sliderThumb = Color(12 / 255, 210 / 255, 157 / 255, 0.95),
            dropdownBg = Color(0.040, 0.060, 0.078, 0.92),
            dropdownBorder = Color(0.120, 0.170, 0.200, 0.88),
            dropdownHover = Color(1.000, 1.000, 1.000, 0.08),
            dropdownSelected = Color(12 / 255, 210 / 255, 157 / 255, 0.12),
            checkboxBg = Color(0.100, 0.120, 0.160, 1.00),
            checkboxChecked = Color(12 / 255, 210 / 255, 157 / 255, 0.75),
            checkboxUnchecked = Color(0.267, 0.267, 0.267, 0.65),
            inputBorder = Color(0.120, 0.170, 0.200, 0.88),
            inputFocus = Color(12 / 255, 210 / 255, 157 / 255, 0.90),
            shadow = Color(0.000, 0.000, 0.000, 0.45),
            glow = Color(12 / 255, 210 / 255, 157 / 255, 0.10),
            headerText = Color(1.000, 1.000, 1.000, 0.92),
            text = Color(1.000, 1.000, 1.000, 0.92),
            mutedText = Color(1.000, 1.000, 1.000, 0.53),
            disabledText = Color(0.420, 0.460, 0.500, 1.00),
            rowBg = Color(0.000, 0.000, 0.000, 0.10),
            rowAlt = Color(0.000, 0.000, 0.000, 0.20),
            rowHover = Color(1.000, 1.000, 1.000, 0.065),
            sectionBg = Color(0.061, 0.095, 0.120, 0.50),
            sectionBorder = Color(0.085, 0.120, 0.140, 0.60),
            sectionAccent = Color(12 / 255, 210 / 255, 157 / 255, 0.74),
            navBg = Color(0.000, 0.000, 0.000, 0.00),
            navHover = Color(1.000, 1.000, 1.000, 0.055),
            navSelectedBg = Color(12 / 255, 210 / 255, 157 / 255, 0.105),
            navSelectedBorder = Color(12 / 255, 210 / 255, 157 / 255, 0.68),
            navText = Color(1.000, 1.000, 1.000, 0.54),
            navSelectedText = Color(1.000, 1.000, 1.000, 0.96),
            tabBg = Color(0.035, 0.052, 0.068, 0.55),
            tabHover = Color(1.000, 1.000, 1.000, 0.055),
            tabSelectedBg = Color(0.061, 0.095, 0.120, 0.76),
            tabSelectedText = Color(1.000, 1.000, 1.000, 0.98),
            scrollTrack = Color(1.000, 1.000, 1.000, 0.08),
            scrollThumb = Color(12 / 255, 210 / 255, 157 / 255, 0.56),
        },
        layout = {
            shellStyle = "starforge",
            settingsWidth = RC.WorkspaceSize.width,
            settingsHeight = RC.WorkspaceSize.height,
            sidebarWidth = 260,
            headerHeight = 108,
            footerHeight = 60,
            sidebarFullHeight = true,
            headerContentOnly = true,
            footerContentOnly = true,
            rowHeight = 44,
            compactRowHeight = 36,
            settingsRowHeight = 42,
            descriptionRowHeight = 44,
            labelColumnWidth = 0.48,
            controlColumnWidth = 0.52,
            controlAlign = "right",
            settingsColumnGap = 0,
            settingsColumns = 2,
            contentPaddingX = 38,
            contentPaddingY = 24,
            sectionGap = 20,
            sectionPadX = 0,
            sectionBase = 44,
            sectionBaseWithDescription = 60,
            sectionBottomPad = 12,
            sectionAccentWidth = 2,
            rowSeparatorAlpha = 0.08,
            controlHeight = 28,
            buttonHeight = 32,
            dropdownHeight = 30,
            inputHeight = 28,
            sliderHeight = 14,
            sliderTrackHeight = 5,
            sliderThumbWidth = 10,
            sliderThumbHeight = 18,
            sliderValueWidth = 50,
            sliderValueHeight = 24,
            dropdownItemHeight = 28,
            scrollbarWidth = 5,
            scrollbarThumbHeight = 38,
            settingsScrollbarWidth = 8,
            settingsScrollbarGutter = 44,
            settingsScrollbarOuterInset = 8,
            settingsContentRightInset = 32,
            navItemHeight = 40,
            navItemGap = 2,
            navGlyphSize = 26,
            navGlyphFont = 10,
            navLabelFont = 12,
            navTextOffset = 44,
            navSelectedIndicatorStyle = "left-edge",
            tabBarHeight = 44,
            tabHeight = 43,
            tabFont = 14,
            sectionHeaderFont = 12,
            sectionDescriptionFont = 9,
            borderThickness = 1,
            cornerRadius = 4,
            panelPadding = 18,
            panelShadowAlpha = 0.42,
            panelGlowAlpha = 0.10,
            raidSplitHeaderHeight = 54,
            raidSplitActionBarHeight = 46,
            raidSplitPanelPad = 10,
            raidSplitPanelGap = 8,
            launcherWidth = 232,
            launcherHeight = 30,
            menuFooterHeight = 38,
            fontSmall = 10,
            fontNormal = 12,
            fontLarge = 16,
        },
    },
}

RC.ThemeAliases = {
    Modern = "Starforge",
    modern = "Starforge",
    Default = "Starforge",
    default = "Starforge",
    nightglass = "Starforge",
    obsidian = "Starforge",
    violet = "Starforge",
    blood = "Starforge",
}

local function SetConfigColor(target, source)
    target.r = source[1] or source.r or 0
    target.g = source[2] or source.g or 0
    target.b = source[3] or source.b or 0
    target.a = source[4] or source.a or 1
end

local function ShiftColor(color, amount, alpha)
    return {
        math.max(0, math.min(1, (color.r or 0) + amount)),
        math.max(0, math.min(1, (color.g or 0) + amount)),
        math.max(0, math.min(1, (color.b or 0) + amount)),
        alpha or color.a or 1,
    }
end

function RC:GetThemeStyle()
    return self.ActiveThemeStyle or "starforge"
end

function RC:IsModernTheme()
    return self:GetThemeStyle() ~= "classic"
end

function RC:IsShadowsteelTheme()
    return self:GetThemeStyle() == "shadowsteel"
end

function RC:IsStarforgeTheme()
    return self:GetThemeStyle() == "starforge"
end

function RC:ResolveThemeName(themeName)
    local profile = self.db and self.db.profile
    local resolved = themeName
    if type(resolved) ~= "string" or resolved == "" then
        resolved = profile and profile.theme or "Starforge"
    end
    resolved = self.ThemeAliases[resolved] or resolved
    if not (self.ThemeDefinitions and self.ThemeDefinitions[resolved]) then
        resolved = "Starforge"
    end
    return resolved
end

function RC:GetThemeDefinition(themeName)
    local resolved = self:ResolveThemeName(themeName)
    return self.ThemeDefinitions[resolved], resolved
end

function RC:GetThemeLayout(key, fallback)
    local layout = self.ActiveThemeLayout
    if not layout then
        local theme = self:GetThemeDefinition(self.db and self.db.profile and self.db.profile.theme)
        layout = theme and theme.layout or nil
    end
    if not key then
        return layout or {}
    end
    return (layout and layout[key]) or fallback
end

function RC:GetPlayerClassColor()
    local _, classFile = UnitClass("player")
    local color = classFile and (
        (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFile])
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
    )
    if color then
        return color.r or 1, color.g or 1, color.b or 1
    end
    return 0.10, 0.78, 0.66
end

function RC:ApplyTheme(themeName, refresh, rebuildSettings)
    local profile = self.db and self.db.profile
    if not profile then
        return
    end

    local theme, resolvedName = self:GetThemeDefinition(themeName)
    theme = theme or self.ThemeDefinitions.Starforge
    local colors = theme.colors or {}
    profile.theme = resolvedName or theme.key or "Starforge"
    self.ActiveThemeName = profile.theme
    self.ActiveThemeStyle = theme.style or "starforge"
    self.ActiveThemeLayout = theme.layout or {}

    local background = profile.backgroundColor or colors.background or self.Config.Color
    local header = profile.headerColor or colors.header or self.Config.HeaderBg
    local surface = profile.surfaceColor or colors.surface or self.Config.SurfaceBg
    local control = profile.controlColor or colors.control or self.Config.ButtonBg
    local border = profile.borderColor or colors.border or self.Config.Border
    local accent = profile.accentColor or colors.accent or self.Config.Accent
    if profile.useClassColor then
        local r, g, b = self:GetPlayerClassColor()
        accent = { r = r, g = g, b = b, a = 1 }
    end
    local function WithAlpha(color, alpha)
        return { r = color.r, g = color.g, b = color.b, a = alpha or color.a or 1 }
    end
    if self:IsModernTheme() then
        border = WithAlpha(border, math.min(0.18, border.a or 0.18))
    end
    local selected = colors.selected or accent
    local sliderFill = colors.sliderFill or accent
    local sliderThumb = colors.sliderThumb or selected
    local dropdownSelected = colors.dropdownSelected or selected
    local checkboxChecked = colors.checkboxChecked or selected
    local inputFocus = WithAlpha(accent, colors.inputFocus and colors.inputFocus.a or 1)
    local sectionAccent = colors.sectionAccent or accent
    local navSelectedBorder = colors.navSelectedBorder or selected
    local scrollThumb = colors.scrollThumb or self.Config.ScrollThumb
    if self.ActiveThemeStyle == "starforge" then
        selected = WithAlpha(accent, colors.selected and colors.selected.a or 0.78)
        sliderFill = WithAlpha(accent, colors.sliderFill and colors.sliderFill.a or 0.75)
        sliderThumb = WithAlpha(accent, colors.sliderThumb and colors.sliderThumb.a or 0.95)
        dropdownSelected = WithAlpha(accent, colors.dropdownSelected and colors.dropdownSelected.a or 0.12)
        checkboxChecked = WithAlpha(accent, colors.checkboxChecked and colors.checkboxChecked.a or 0.75)
        sectionAccent = WithAlpha(accent, colors.sectionAccent and colors.sectionAccent.a or 0.74)
        navSelectedBorder = WithAlpha(accent, colors.navSelectedBorder and colors.navSelectedBorder.a or 0.68)
        scrollThumb = WithAlpha(accent, colors.scrollThumb and colors.scrollThumb.a or 0.56)
    end

    SetConfigColor(self.Config.Color, background)
    SetConfigColor(self.Config.HeaderBg, header)
    SetConfigColor(self.Config.SurfaceBg, surface)
    SetConfigColor(self.Config.AltRowBg, colors.altRow or surface)
    SetConfigColor(self.Config.ButtonBg, control)
    SetConfigColor(self.Config.ButtonPressed, colors.buttonPressed or ShiftColor(control, -0.025, math.min(1, (control.a or 0.84) + 0.06)))
    SetConfigColor(self.Config.ButtonHover, colors.buttonHover or ShiftColor(control, 0.040, math.min(1, (control.a or 0.84) + 0.08)))
    SetConfigColor(self.Config.ButtonDisabled, colors.buttonDisabled or ShiftColor(control, -0.030, 0.45))
    SetConfigColor(self.Config.InputBg, colors.input or ShiftColor(control, -0.045, control.a or 0.90))
    SetConfigColor(self.Config.Border, border)
    SetConfigColor(self.Config.StrongBorder, colors.strongBorder or border)
    SetConfigColor(self.Config.SeparatorColor, colors.separator or border)
    SetConfigColor(self.Config.Accent, accent)
    SetConfigColor(self.Config.AccentHover, colors.accentHover or ShiftColor(accent, 0.055, accent.a or 1))
    SetConfigColor(self.Config.Selected, selected)
    SetConfigColor(self.Config.WarningColor, colors.warning or self.Config.WarningColor)
    SetConfigColor(self.Config.ErrorColor, colors.error or self.Config.ErrorColor)
    SetConfigColor(self.Config.DangerColor, colors.error or self.Config.DangerColor)
    SetConfigColor(self.Config.SuccessColor, colors.success or self.Config.SuccessColor)
    SetConfigColor(self.Config.SliderTrack, colors.sliderTrack or self.Config.SliderTrack)
    SetConfigColor(self.Config.SliderFill, sliderFill)
    SetConfigColor(self.Config.SliderThumb, sliderThumb)
    SetConfigColor(self.Config.DropdownBg, colors.dropdownBg or control)
    SetConfigColor(self.Config.DropdownBorder, colors.dropdownBorder or border)
    SetConfigColor(self.Config.DropdownHover, colors.dropdownHover or self.Config.ButtonHover)
    SetConfigColor(self.Config.DropdownSelected, dropdownSelected)
    SetConfigColor(self.Config.CheckboxBg, colors.checkboxBg or control)
    SetConfigColor(self.Config.CheckboxChecked, checkboxChecked)
    SetConfigColor(self.Config.CheckboxUnchecked, colors.checkboxUnchecked or self.Config.ButtonDisabled)
    SetConfigColor(self.Config.InputBorder, colors.inputBorder or border)
    SetConfigColor(self.Config.InputFocus, inputFocus)
    SetConfigColor(self.Config.Shadow, colors.shadow or self.Config.Shadow)
    SetConfigColor(self.Config.Glow, colors.glow or accent)
    SetConfigColor(self.Config.Header, colors.headerText or self.Config.WhiteText)
    SetConfigColor(self.Config.HeaderText, colors.headerText or self.Config.WhiteText)
    SetConfigColor(self.Config.Text, colors.text or self.Config.WhiteText)
    SetConfigColor(self.Config.WhiteText, colors.text or self.Config.WhiteText)
    SetConfigColor(self.Config.MutedText, colors.mutedText or self.Config.MutedText)
    SetConfigColor(self.Config.DisabledText, colors.disabledText or self.Config.DisabledText)
    SetConfigColor(self.Config.RowBg, colors.rowBg or colors.altRow or self.Config.RowBg)
    SetConfigColor(self.Config.RowAltBg, colors.rowAlt or colors.altRow or self.Config.RowAltBg)
    SetConfigColor(self.Config.RowHover, colors.rowHover or self.Config.ButtonHover)
    SetConfigColor(self.Config.SectionBg, colors.sectionBg or surface)
    SetConfigColor(self.Config.SectionBorder, colors.sectionBorder or border)
    SetConfigColor(self.Config.SectionAccent, sectionAccent)
    SetConfigColor(self.Config.NavBg, colors.navBg or self.Config.NavBg)
    SetConfigColor(self.Config.NavHover, colors.navHover or self.Config.ButtonHover)
    SetConfigColor(self.Config.NavSelectedBg, colors.navSelectedBg or dropdownSelected)
    SetConfigColor(self.Config.NavSelectedBorder, navSelectedBorder)
    SetConfigColor(self.Config.NavText, colors.navText or self.Config.MutedText)
    SetConfigColor(self.Config.NavSelectedText, colors.navSelectedText or self.Config.WhiteText)
    SetConfigColor(self.Config.TabBg, colors.tabBg or header)
    SetConfigColor(self.Config.TabHover, colors.tabHover or self.Config.ButtonHover)
    SetConfigColor(self.Config.TabSelectedBg, colors.tabSelectedBg or surface)
    SetConfigColor(self.Config.TabSelectedText, colors.tabSelectedText or self.Config.WhiteText)
    SetConfigColor(self.Config.ScrollTrack, colors.scrollTrack or self.Config.SliderTrack)
    SetConfigColor(self.Config.ScrollThumb, scrollThumb)

    if refresh ~= false and self.RefreshTheme then
        self:RefreshTheme(rebuildSettings ~= false)
    end
end

function RC:ApplyThemePreset(themeName, rebuildSettings)
    local profile = self.db and self.db.profile
    local theme, resolvedName = self:GetThemeDefinition(themeName)
    local colors = theme and theme.colors
    if not profile or not colors then
        return false
    end
    local function CopyColor(color)
        return color and { r = color.r, g = color.g, b = color.b, a = color.a } or nil
    end
    profile.theme = resolvedName or theme.key or "Starforge"
    profile.useClassColor = false
    profile.backgroundColor = CopyColor(colors.background)
    profile.headerColor = CopyColor(colors.header)
    profile.surfaceColor = CopyColor(colors.surface)
    profile.controlColor = CopyColor(colors.control)
    profile.borderColor = CopyColor(colors.border)
    profile.accentColor = CopyColor(colors.accent)
    self:ApplyTheme(profile.theme, true, rebuildSettings ~= false)
    return true
end

function RC:GetBackgroundColor()
    local c = self.db and self.db.profile and self.db.profile.backgroundColor
    if c then return c.r, c.g, c.b, c.a or 1 end
    return self.Config.Color.r, self.Config.Color.g, self.Config.Color.b, self.Config.Color.a
end

RC.BackdropRegistry = {}

function RC:RegisterBackdrop(frame)
    if not frame then return end
    table.insert(self.BackdropRegistry, frame)
end

function RC:SetFrameThemeRole(frame, role, alpha)
    if not frame then return end
    frame.rcThemeRole = role or "Color"
    frame.rcThemeAlpha = alpha
    local color = self.Config[frame.rcThemeRole]
    if frame.rcThemeRole == "Transparent" then
        frame:SetBackdropColor(0, 0, 0, 0)
    elseif color and frame.SetBackdropColor then
        frame:SetBackdropColor(color.r, color.g, color.b, alpha or color.a or 1)
    end
end

function RC:UpdateAllBackdrops()
    for i = #self.BackdropRegistry, 1, -1 do
        local frame = self.BackdropRegistry[i]
        if frame and frame.bgTexture then
            local role = frame.rcThemeRole or (frame.rcUseHeaderBg and "HeaderBg") or "Color"
            local color = self.Config[role]
            if role == "Transparent" then
                frame.bgTexture:SetColorTexture(0, 0, 0, 0)
            elseif color then
                frame.bgTexture:SetColorTexture(color.r, color.g, color.b, frame.rcThemeAlpha or color.a or 1)
            else
                local r, g, b, a = self:GetBackgroundColor()
                frame.bgTexture:SetColorTexture(r, g, b, a)
            end
        else
            table.remove(self.BackdropRegistry, i)
        end
    end
end

RC.ThemeWidgetRegistry = setmetatable({}, { __mode = "k" })

function RC:RegisterThemeWidget(widget)
    if widget then
        self.ThemeWidgetRegistry[widget] = true
    end
end

function RC:RefreshTheme(rebuildSettings)
    self:UpdateAllBackdrops()
    self:UpdateAllBorders()
    self:UpdateAllTextColors()

    for widget in pairs(self.ThemeWidgetRegistry) do
        if widget and widget.RefreshTheme then
            widget:RefreshTheme()
        end
    end

    if self.RefreshCoreTheme then
        self:RefreshCoreTheme()
    end

    local settings = self.GetModule and self:GetModule("Settings", true)
    if settings and settings.RefreshTheme then
        settings:RefreshTheme(rebuildSettings == false)
    end

    local actionStrip = self.GetModule and self:GetModule("ActionStrip", true)
    if actionStrip and actionStrip.RefreshTheme then
        actionStrip:RefreshTheme()
    end

    local markers = self.GetModule and self:GetModule("Markers", true)
    if markers and markers.RefreshTheme then
        markers:RefreshTheme()
    end

    local raidSplit = self.GetModule and self:GetModule("RaidSplit", true)
    if raidSplit and raidSplit.RefreshTheme then
        raidSplit:RefreshTheme()
    end

    local readyTracker = self.GetModule and self:GetModule("ReadyTracker", true)
    if readyTracker and readyTracker.RefreshTheme then
        readyTracker:RefreshTheme()
    end

    local tankAssist = self.GetModule and self:GetModule("TankAssist", true)
    if tankAssist and tankAssist.RefreshTheme then
        tankAssist:RefreshTheme()
    end

    local autoMarker = self.GetModule and self:GetModule("AutoMarker", true)
    if autoMarker and autoMarker.RefreshTheme then
        autoMarker:RefreshTheme()
    end

    local raidLeadTools = self.GetModule and self:GetModule("RaidLeadTools", true)
    if raidLeadTools and raidLeadTools.RefreshTheme then
        raidLeadTools:RefreshTheme()
    end

    local bossNotes = self.GetModule and self:GetModule("BossNotes", true)
    if bossNotes and bossNotes.RefreshTheme then
        bossNotes:RefreshTheme()
    end

    if self.ColorPickerFrame and self.ColorPickerFrame.RefreshTheme then
        self.ColorPickerFrame:RefreshTheme()
    end
end

-- Dynamic font fetching via LibSharedMedia
local LSM = LibStub("LibSharedMedia-3.0")
LSM:Register("font", "RaidControl", "Interface\\AddOns\\" .. addonName .. "\\Media\\font.ttf")
LSM:Register("font", "Bwoah", "Interface\\AddOns\\" .. addonName .. "\\Media\\font.ttf") -- Legacy saved profiles
LSM:Register("font", "RaidControl Font", "Interface\\AddOns\\" .. addonName .. "\\Media\\font.ttf") -- Legacy saved profiles

function RC:GetFont()
    local fontName = self.db and self.db.profile and self.db.profile.fontName or "RaidControl"
    return LSM:Fetch("font", fontName) or ("Interface\\AddOns\\" .. addonName .. "\\Media\\font.ttf")
end

local SHARED_MEDIA_SOUND_PREFIX = "lsm:"

function RC:GetSharedMediaSoundOptions(baseList, baseOrder)
    local list = {}
    local order = {}
    local seen = {}

    for key, label in pairs(baseList or {}) do
        list[key] = label
    end
    for _, key in ipairs(baseOrder or {}) do
        if list[key] ~= nil and not seen[key] then
            order[#order + 1] = key
            seen[key] = true
        end
    end

    local names = {}
    for _, name in ipairs(LSM:List("sound") or {}) do
        names[#names + 1] = name
    end
    table.sort(names, function(left, right)
        return tostring(left):lower() < tostring(right):lower()
    end)
    for _, name in ipairs(names) do
        local key = SHARED_MEDIA_SOUND_PREFIX .. name
        list[key] = string.format(L["SharedMedia: %s"], name)
        if not seen[key] then
            order[#order + 1] = key
            seen[key] = true
        end
    end

    return list, order
end

function RC:ResolveSharedMediaSound(selection)
    if type(selection) ~= "string" then
        return nil
    end
    local name = selection:match("^" .. SHARED_MEDIA_SOUND_PREFIX .. "(.+)$")
    if not name or name == "" then
        return nil
    end
    return LSM:Fetch("sound", name, true)
end

-- Font registry for live updates when user changes font
-- Keyed by the fontstring so repeated SetFont calls (hover states, pooled
-- widgets) update one entry in place: the newest size always wins and the
-- registry does not grow for the whole session.
RC.FontRegistry = setmetatable({}, { __mode = "k" })

local function NormalizeFontFlags(flags)
    if type(flags) ~= "string" or flags == "" then
        return ""
    end
    local normalized = flags:gsub("OUTLINE", ""):gsub("^,+", ""):gsub(",+$", ""):gsub(",,+", ",")
    return normalized
end

function RC:RegisterFontString(fontString, size, flags)
    if not fontString then return end
    self.FontRegistry[fontString] = { size = size, flags = NormalizeFontFlags(flags) }
end

function RC:SetFont(fontString, size, flags)
    flags = NormalizeFontFlags(flags)
    fontString:SetFont(self:GetFont(), size, flags)
    self:RegisterFontString(fontString, size, flags)
end

function RC:UpdateAllFonts()
    local fontPath = self:GetFont()
    for fontString, entry in pairs(self.FontRegistry) do
        if fontString.SetFont then
            fontString:SetFont(fontPath, entry.size, entry.flags)
        end
    end
end

-- =============================================================================
-- DYNAMIC TEXT COLORS (read from saved DB, fallback to Config defaults)
-- =============================================================================

function RC:GetTitleColor()
    local c = self.db and self.db.profile and self.db.profile.titleTextColor
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function RC:GetButtonTextColor()
    local c = self.db and self.db.profile and self.db.profile.buttonTextColor
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

function RC:GetGeneralTextColor()
    local c = self.db and self.db.profile and self.db.profile.generalTextColor
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

-- Text color registry for live updates, keyed by fontstring (latest role wins).
RC.TextColorRegistry = setmetatable({}, { __mode = "k" })

function RC:RegisterTextColor(fontString, colorType)
    if not fontString then return end
    self.TextColorRegistry[fontString] = colorType
end

function RC:UpdateAllTextColors()
    for fontString, colorType in pairs(self.TextColorRegistry) do
        if fontString.SetTextColor then
            if colorType == "title" then
                fontString:SetTextColor(self:GetTitleColor())
            elseif colorType == "button" then
                fontString:SetTextColor(self:GetButtonTextColor())
            elseif colorType == "general" then
                fontString:SetTextColor(self:GetGeneralTextColor())
            end
        end
    end
end

function RC:SetTextColor(fontString, colorType)
    if not fontString then return end
    if colorType == "title" then
        fontString:SetTextColor(self:GetTitleColor())
    elseif colorType == "button" then
        fontString:SetTextColor(self:GetButtonTextColor())
    elseif colorType == "general" then
        fontString:SetTextColor(self:GetGeneralTextColor())
    else
        fontString:SetTextColor(1, 1, 1) -- White fallback
    end
    self:RegisterTextColor(fontString, colorType)
end

function RC:GetBorderColor()
    local c = self.db and self.db.profile and self.db.profile.borderColor
    if c then return c.r, c.g, c.b, c.a or 1 end
    return self.Config.Border.r, self.Config.Border.g, self.Config.Border.b, self.Config.Border.a
end

function RC:GetControlBorderColor(minimumAlpha)
    local r, g, b, a = self:GetBorderColor()
    return r, g, b, math.max(minimumAlpha or 0.06, a or 0)
end

RC.BorderRegistry = {}

function RC:RegisterBorderColor(frame)
    if not frame then return end
    table.insert(self.BorderRegistry, frame)
end

function RC:UpdateAllBorders()
    local r, g, b, a = self:GetBorderColor()
    -- Update Config for new frames
    self.Config.Border.r = r
    self.Config.Border.g = g
    self.Config.Border.b = b
    self.Config.Border.a = a

    for i = #self.BorderRegistry, 1, -1 do
        local frame = self.BorderRegistry[i]
        if frame and frame.borderTop then
            local frameAlpha = frame.rcBorderAlphaOverride
            if frameAlpha == nil then
                frameAlpha = math.max(frame.rcBorderMinAlpha or 0, a or 0)
            end
            frame.borderTop:SetColorTexture(r, g, b, frameAlpha)
            frame.borderBottom:SetColorTexture(r, g, b, frameAlpha)
            frame.borderLeft:SetColorTexture(r, g, b, frameAlpha)
            frame.borderRight:SetColorTexture(r, g, b, frameAlpha)
        else
            table.remove(self.BorderRegistry, i)
        end
    end
end

-- =============================================================================
-- CUSTOM COLOR PICKER
-- =============================================================================

local function ClampColorChannel(value)
    value = tonumber(value) or 0
    return math.max(0, math.min(1, value))
end

function RC:CreateColorPicker()
    if self.ColorPickerFrame then
        return self.ColorPickerFrame
    end

    local frame = CreateFrame("Frame", "RC_ColorPickerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(360, 258)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(500)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame.rcBorderMinAlpha = 0.15
    self:SkinFrame(frame)
    self:SetFrameThemeRole(frame, "Color")
    frame:Hide()

    if self.RegisterEscapeFrame then
        self:RegisterEscapeFrame(frame)
    end

    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    titleBar:SetHeight(44)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()

    local title = titleBar:CreateFontString(nil, "OVERLAY")
    self:SetFont(title, 14, "OUTLINE")
    title:SetPoint("LEFT", titleBar, "LEFT", 16, 0)
    title:SetText(L["Color Picker"])
    title:SetTextColor(1, 1, 1, 0.92)

    local closeButton = self:CreateCloseButton(titleBar, 22)
    closeButton:SetPoint("RIGHT", titleBar, "RIGHT", -10, 0)

    local accentLine = frame:CreateTexture(nil, "ARTWORK")
    accentLine:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    accentLine:SetHeight(2)

    local oldSwatch = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    oldSwatch:SetSize(38, 38)
    oldSwatch:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -60)
    oldSwatch.rcBorderMinAlpha = 0.20
    self:SkinFrame(oldSwatch)
    local oldColor = oldSwatch:CreateTexture(nil, "ARTWORK")
    oldColor:SetPoint("TOPLEFT", oldSwatch, "TOPLEFT", 2, -2)
    oldColor:SetPoint("BOTTOMRIGHT", oldSwatch, "BOTTOMRIGHT", -2, 2)

    local newSwatch = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    newSwatch:SetSize(38, 38)
    newSwatch:SetPoint("LEFT", oldSwatch, "RIGHT", 8, 0)
    newSwatch.rcBorderMinAlpha = 0.20
    self:SkinFrame(newSwatch)
    local newColor = newSwatch:CreateTexture(nil, "ARTWORK")
    newColor:SetPoint("TOPLEFT", newSwatch, "TOPLEFT", 2, -2)
    newColor:SetPoint("BOTTOMRIGHT", newSwatch, "BOTTOMRIGHT", -2, 2)

    local previewLabel = frame:CreateFontString(nil, "OVERLAY")
    self:SetFont(previewLabel, 10, "OUTLINE")
    previewLabel:SetPoint("LEFT", newSwatch, "RIGHT", 10, 0)
    previewLabel:SetText(L["Previous  /  Current"])
    previewLabel:SetTextColor(1, 1, 1, 0.48)

    frame.values = { r = 1, g = 1, b = 1 }
    frame.sliders = {}
    local channelData = {
        { key = "r", label = L["R"], color = { 0.90, 0.22, 0.22 } },
        { key = "g", label = L["G"], color = { 0.22, 0.78, 0.38 } },
        { key = "b", label = L["B"], color = { 0.28, 0.52, 0.95 } },
    }

    local function UpdatePreview(fireCallback)
        local r = ClampColorChannel(frame.values.r)
        local g = ClampColorChannel(frame.values.g)
        local b = ClampColorChannel(frame.values.b)
        frame.values.r, frame.values.g, frame.values.b = r, g, b
        newColor:SetColorTexture(r, g, b, 1)
        frame.hexBox:SetText(string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)))
        if fireCallback and frame.options and frame.options.onColorChanged then
            frame.options.onColorChanged(r, g, b)
        end
    end

    for index, channel in ipairs(channelData) do
        local y = -112 - ((index - 1) * 38)
        local label = frame:CreateFontString(nil, "OVERLAY")
        self:SetFont(label, 11, "OUTLINE")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, y)
        label:SetSize(20, 20)
        label:SetJustifyH("LEFT")
        label:SetText(channel.label)
        label:SetTextColor(channel.color[1], channel.color[2], channel.color[3], 0.92)

        local slider = CreateFrame("Slider", nil, frame)
        slider:SetOrientation("HORIZONTAL")
        slider:SetMinMaxValues(0, 255)
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
        slider:SetPoint("TOPLEFT", frame, "TOPLEFT", 48, y)
        slider:SetSize(236, 20)

        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetPoint("LEFT", slider, "LEFT", 3, 0)
        track:SetPoint("RIGHT", slider, "RIGHT", -3, 0)
        track:SetHeight(4)
        track:SetColorTexture(channel.color[1], channel.color[2], channel.color[3], 0.34)

        slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb = slider:GetThumbTexture()
        if thumb then
            thumb:SetSize(8, 18)
            thumb:SetVertexColor(1, 1, 1, 0.72)
        end

        local value = frame:CreateFontString(nil, "OVERLAY")
        self:SetFont(value, 11, "OUTLINE")
        value:SetPoint("LEFT", slider, "RIGHT", 12, 0)
        value:SetSize(42, 20)
        value:SetJustifyH("RIGHT")
        value:SetTextColor(1, 1, 1, 0.62)

        slider:SetScript("OnValueChanged", function(_, rawValue)
            rawValue = math.floor((rawValue or 0) + 0.5)
            value:SetText(tostring(rawValue))
            if not frame.updating then
                frame.values[channel.key] = rawValue / 255
                UpdatePreview(true)
            end
        end)

        frame.sliders[channel.key] = { slider = slider, value = value, track = track, thumb = thumb }
    end

    local hexLabel = frame:CreateFontString(nil, "OVERLAY")
    self:SetFont(hexLabel, 10, "OUTLINE")
    hexLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 20)
    hexLabel:SetText("#")
    hexLabel:SetTextColor(1, 1, 1, 0.48)

    local hexBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    hexBox:SetSize(86, 28)
    hexBox:SetPoint("LEFT", hexLabel, "RIGHT", 4, 0)
    hexBox:SetAutoFocus(false)
    hexBox:SetMaxLetters(6)
    hexBox:SetTextInsets(8, 8, 0, 0)
    hexBox:SetJustifyH("CENTER")
    hexBox:SetFont(self:GetFont(), 11, "")
    self:RegisterFontString(hexBox, 11, "")
    hexBox.rcBorderMinAlpha = 0.20
    self:SkinFrame(hexBox)
    self:SetFrameThemeRole(hexBox, "InputBg")
    frame.hexBox = hexBox

    hexBox:SetScript("OnEnterPressed", function(box)
        local hex = (box:GetText() or ""):gsub("#", "")
        if hex:match("^%x%x%x%x%x%x$") then
            frame.values.r = tonumber(hex:sub(1, 2), 16) / 255
            frame.values.g = tonumber(hex:sub(3, 4), 16) / 255
            frame.values.b = tonumber(hex:sub(5, 6), 16) / 255
            frame:SetColor(frame.values.r, frame.values.g, frame.values.b, true)
        else
            UpdatePreview(false)
        end
        box:ClearFocus()
    end)
    hexBox:SetScript("OnEscapePressed", function(box)
        UpdatePreview(false)
        box:ClearFocus()
    end)
    hexBox:SetScript("OnEnter", function(box)
        box:SetBackdropBorderColor(self:GetControlBorderColor(0.30))
    end)
    hexBox:SetScript("OnLeave", function(box)
        box:SetBackdropBorderColor(self:GetControlBorderColor())
    end)

    local cancelButton = self:CreateStandardButton(nil, frame, 92, 28)
    cancelButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -116, 14)
    cancelButton.Text:SetText(L["Cancel"])

    local doneButton = self:CreateStandardButton(nil, frame, 92, 28)
    doneButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
    doneButton.Text:SetText(L["Done"])

    function frame:SetColor(r, g, b, fireCallback)
        self.values.r = ClampColorChannel(r)
        self.values.g = ClampColorChannel(g)
        self.values.b = ClampColorChannel(b)
        self.updating = true
        self.sliders.r.slider:SetValue(self.values.r * 255)
        self.sliders.g.slider:SetValue(self.values.g * 255)
        self.sliders.b.slider:SetValue(self.values.b * 255)
        self.updating = nil
        UpdatePreview(fireCallback)
    end

    function frame:RefreshTheme()
        RC:SetFrameThemeRole(self, "Color")
        self:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, math.max(0.15, RC.Config.Border.a or 0))
        titleBg:SetColorTexture(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, RC.Config.HeaderBg.a or 1)
        accentLine:SetColorTexture(RC.Config.SeparatorColor.r, RC.Config.SeparatorColor.g, RC.Config.SeparatorColor.b, RC:IsShadowsteelTheme() and 0.24 or 0.18)
        oldSwatch:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
        newSwatch:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
        oldSwatch:SetBackdropBorderColor(RC:GetControlBorderColor())
        newSwatch:SetBackdropBorderColor(RC:GetControlBorderColor())
        hexBox:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, RC.Config.InputBg.a or 1)
        hexBox:SetBackdropBorderColor(RC:GetControlBorderColor())
        doneButton:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.82)
        doneButton.Text:SetTextColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
    end

    local function CancelPicker()
        frame.accepted = false
        frame:Hide()
    end

    closeButton:SetScript("OnClick", CancelPicker)
    cancelButton:SetScript("OnClick", CancelPicker)
    doneButton:SetScript("OnClick", function()
        frame.accepted = true
        if frame.options and frame.options.onAccept then
            frame.options.onAccept(frame.values.r, frame.values.g, frame.values.b)
        end
        frame:Hide()
    end)

    frame:SetScript("OnHide", function()
        local options = frame.options
        if options and not frame.accepted and options.onCancel then
            options.onCancel(frame.original.r, frame.original.g, frame.original.b)
        end
        frame.options = nil
        frame.accepted = nil
    end)

    frame.oldColor = oldColor
    frame.newColor = newColor
    frame:RefreshTheme()
    self.ColorPickerFrame = frame
    return frame
end

function RC:ShowColorPicker(options)
    options = options or {}
    local frame = self:CreateColorPicker()
    if frame:IsShown() then
        frame:Hide()
    end

    local r = ClampColorChannel(options.r or 1)
    local g = ClampColorChannel(options.g or 1)
    local b = ClampColorChannel(options.b or 1)
    frame.options = options
    frame.original = { r = r, g = g, b = b }
    frame.accepted = false
    frame.oldColor:SetColorTexture(r, g, b, 1)
    frame:SetColor(r, g, b, false)
    frame:RefreshTheme()
    frame:Show()
    frame:Raise()
end

-- Color Swatch Helper: creates a clickable color swatch + label for settings
function RC:CreateColorSwatch(parent, label, dbKey, colorType)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(250, 24)

    -- Color swatch button
    local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
    swatch:SetSize(20, 20)
    swatch:SetPoint("LEFT", 0, 0)
    RC:SkinFrame(swatch)

    local colorTex = swatch:CreateTexture(nil, "ARTWORK")
    colorTex:SetPoint("TOPLEFT", 1, -1)
    colorTex:SetPoint("BOTTOMRIGHT", -1, 1)
    colorTex:SetColorTexture(1, 1, 1)

    -- Load saved color
    local saved = RC.db.profile[dbKey] or { r = 1, g = 1, b = 1 }
    colorTex:SetVertexColor(saved.r, saved.g, saved.b)

    -- Label text
    local text = row:CreateFontString(nil, "OVERLAY")
    RC:SetFont(text, 11, "OUTLINE")
    text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    text:SetText(label)
    text:SetTextColor(0.9, 0.9, 0.9)

    swatch:SetScript("OnClick", function()
        local current = RC.db.profile[dbKey] or { r = 1, g = 1, b = 1 }
        RC:ShowColorPicker({
            r = current.r,
            g = current.g,
            b = current.b,
            onColorChanged = function(r, g, b)
                RC.db.profile[dbKey] = { r = r, g = g, b = b }
                colorTex:SetVertexColor(r, g, b)
                if colorType == "border" then
                    RC:UpdateAllBorders()
                elseif colorType == "background" then
                    RC:UpdateAllBackdrops()
                else
                    RC:UpdateAllTextColors()
                end
            end,
            onCancel = function(r, g, b)
                RC.db.profile[dbKey] = { r = r, g = g, b = b }
                colorTex:SetVertexColor(r, g, b)
                if colorType == "border" then
                    RC:UpdateAllBorders()
                elseif colorType == "background" then
                    RC:UpdateAllBackdrops()
                else
                    RC:UpdateAllTextColors()
                end
            end,
        })
    end)

    -- Hover on swatch
    swatch:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
    end)
    swatch:SetScript("OnLeave", function(self)
        local br, bg, bb, ba = RC:GetControlBorderColor(0.15)
        self:SetBackdropBorderColor(br, bg, bb, ba)
    end)

    return row
end

-- =============================================================================
-- CORE SKINNING FUNCTIONS
-- =============================================================================

function RC:SkinFrame(frame, _, transparentBg)
    if not frame then return end
    if frame.IsObjectType and frame:IsObjectType("Texture") then return end

    if not frame.rcThemeRole then
        frame.rcThemeRole = transparentBg and "Transparent" or "Color"
    end

    -- Create Background Texture
    if not frame.bgTexture then
        frame.bgTexture = frame:CreateTexture(nil, "BACKGROUND")
        frame.bgTexture:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        frame.bgTexture:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        RC:RegisterBackdrop(frame)
    end

    -- Inject SetBackdropColor Proxy
    frame.SetBackdropColor = function(self, r, g, b, a)
        if self.bgTexture then
            self.bgTexture:SetColorTexture(r, g, b, a)
        end
    end

    if transparentBg then
        frame:SetBackdropColor(0, 0, 0, 0)
    else
        local color = RC.Config[frame.rcThemeRole]
        if color then
            frame:SetBackdropColor(color.r, color.g, color.b, frame.rcThemeAlpha or color.a or 1)
        else
            local r, g, b, a = RC:GetBackgroundColor()
            frame:SetBackdropColor(r, g, b, a)
        end
    end

    -- Create 1px Border Textures (OVERLAY)
    if not frame.borderTop then
        frame.borderTop = frame:CreateTexture(nil, "OVERLAY")
        frame.borderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.borderTop:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, -1)

        frame.borderBottom = frame:CreateTexture(nil, "OVERLAY")
        frame.borderBottom:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 1)
        frame.borderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

        frame.borderLeft = frame:CreateTexture(nil, "OVERLAY")
        frame.borderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.borderLeft:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", 1, 0)

        frame.borderRight = frame:CreateTexture(nil, "OVERLAY")
        frame.borderRight:SetPoint("TOPLEFT", frame, "TOPRIGHT", -1, 0)
        frame.borderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

        RC:RegisterBorderColor(frame)
    end

    -- Inject SetBackdropBorderColor Proxy
    frame.SetBackdropBorderColor = function(self, r, g, b, a)
        if self.borderTop then
            self.borderTop:SetColorTexture(r, g, b, a)
            self.borderBottom:SetColorTexture(r, g, b, a)
            self.borderLeft:SetColorTexture(r, g, b, a)
            self.borderRight:SetColorTexture(r, g, b, a)
        end
    end

    -- Inject SetBackdrop dummy so AceGUI or older code doesn't crash
    frame.SetBackdrop = function() end

    local br, bg, bb, ba = RC:GetBorderColor()
    if frame.rcBorderAlphaOverride ~= nil then
        ba = frame.rcBorderAlphaOverride
    else
        ba = math.max(frame.rcBorderMinAlpha or 0, ba or 0)
    end
    frame:SetBackdropBorderColor(br, bg, bb, ba)
end

-- Accent hover effect for frames with backdrop
function RC:SetModifiedBackdrop(frame)
    if frame.borderTop then
        frame.borderTop:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
        frame.borderBottom:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
        frame.borderLeft:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
        frame.borderRight:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
    end
end

function RC:SetOriginalBackdrop(frame)
    if frame.borderTop then
        local br, bg, bb, ba = RC:GetBorderColor()
        frame.borderTop:SetColorTexture(br, bg, bb, ba)
        frame.borderBottom:SetColorTexture(br, bg, bb, ba)
        frame.borderLeft:SetColorTexture(br, bg, bb, ba)
        frame.borderRight:SetColorTexture(br, bg, bb, ba)
    end
end

local THEMED_PANEL_ROLES = {
    window = "Color",
    panel = "SurfaceBg",
    content = "Color",
    header = "HeaderBg",
    sidebar = "HeaderBg",
    footer = "HeaderBg",
    section = "SectionBg",
    row = "RowBg",
    scroll = "Color",
    actionbar = "TabBg",
    button = "ButtonBg",
    input = "InputBg",
}

local THEMED_PANEL_BORDERS = {
    window = "StrongBorder",
    panel = "SectionBorder",
    content = "Border",
    header = "SeparatorColor",
    sidebar = "SeparatorColor",
    footer = "SeparatorColor",
    section = "SectionBorder",
    row = "SeparatorColor",
    scroll = "SeparatorColor",
    actionbar = "SeparatorColor",
    button = "InputBorder",
    input = "InputBorder",
}

local function ApplyColorTarget(target, color, alpha)
    if not target or not color then
        return
    end
    if target.SetColorTexture then
        target:SetColorTexture(color.r, color.g, color.b, alpha or color.a or 1)
    elseif target.SetBackdropColor then
        target:SetBackdropColor(color.r, color.g, color.b, alpha or color.a or 1)
    end
end

function RC:GetThemedPanelBorderAlpha(kind)
    if kind == "window" then
        return math.max(0.12, self.Config.StrongBorder.a or 0)
    elseif kind == "section" or kind == "panel" then
        return math.max(0.04, self.Config.SectionBorder.a or 0)
    elseif kind == "button" or kind == "input" then
        return math.max(0.08, self.Config.InputBorder.a or 0)
    elseif kind == "row" then
        return self:GetThemeLayout("rowSeparatorAlpha", 0.08)
    end
    return math.max(0.05, self.Config.Border.a or 0)
end

function RC:ApplyThemedPanel(frame, kind, options)
    if not frame then
        return
    end
    kind = kind or "panel"
    options = options or {}
    if not frame.SetBackdropColor then
        self:SkinFrame(frame, nil, options.transparent)
    end

    local role = options.role or THEMED_PANEL_ROLES[kind] or "SurfaceBg"
    local bg = self.Config[role] or self.Config.SurfaceBg
    local alpha = options.alpha
    if alpha == nil then
        alpha = bg and bg.a or 1
    end

    frame.rcThemedPanelKind = kind
    frame.rcBorderAlphaOverride = options.borderAlpha
    self:SetFrameThemeRole(frame, role, alpha)

    local borderRole = options.borderRole or THEMED_PANEL_BORDERS[kind] or "Border"
    local border = self.Config[borderRole] or self.Config.Border
    if frame.SetBackdropBorderColor then
        frame:SetBackdropBorderColor(border.r, border.g, border.b, options.borderAlpha or self:GetThemedPanelBorderAlpha(kind))
    end
end

function RC:ApplyThemedWindow(frame, kind)
    self:ApplyThemedPanel(frame, kind or "window", {
        role = "Color",
        borderRole = "StrongBorder",
        borderAlpha = self:GetThemedPanelBorderAlpha("window"),
    })
end

function RC:ApplyThemedHeader(frame)
    self:ApplyThemedPanel(frame, "header", {
        role = "HeaderBg",
        borderRole = "SeparatorColor",
        borderAlpha = 0,
    })
end

function RC:ApplyThemedSidebar(frame)
    self:ApplyThemedPanel(frame, "sidebar", {
        role = "HeaderBg",
        borderRole = "SeparatorColor",
        borderAlpha = 0,
    })
end

function RC:ApplyThemedFooter(frame)
    self:ApplyThemedPanel(frame, "footer", {
        role = "HeaderBg",
        borderRole = "SeparatorColor",
        borderAlpha = 0,
    })
end

function RC:ApplyThemedSection(frame)
    self:ApplyThemedPanel(frame, "section", {
        role = "SectionBg",
        borderRole = "SectionBorder",
        borderAlpha = self:GetThemedPanelBorderAlpha("section"),
    })
end

function RC:ApplyThemedScrollArea(frame)
    self:ApplyThemedPanel(frame, "scroll", {
        role = "Color",
        borderRole = "SeparatorColor",
        borderAlpha = self:IsShadowsteelTheme() and 1 or math.max(0.04, self.Config.SeparatorColor.a or 0),
    })
end

function RC:ApplyThemedSettingsRow(target, rowIndex, hovered)
    local color
    if hovered then
        color = self.Config.RowHover
    elseif (rowIndex or 1) % 2 == 0 then
        color = self.Config.RowAltBg
    else
        color = self.Config.RowBg
    end
    ApplyColorTarget(target, color, color.a or 0.10)
end

function RC:ApplyThemedNavItem(frame, selected, hovered)
    if not frame or not frame.SetBackdropColor then
        return
    end
    local bg = selected and self.Config.NavSelectedBg or (hovered and self.Config.NavHover or self.Config.NavBg)
    local border = selected and self.Config.NavSelectedBorder or self.Config.Border
    frame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 0)
    frame:SetBackdropBorderColor(border.r, border.g, border.b, selected and (border.a or 0.7) or 0)
end

function RC:ApplyThemedTab(frame, selected, hovered)
    if not frame or not frame.SetBackdropColor then
        return
    end
    local bg = selected and self.Config.TabSelectedBg or (hovered and self.Config.TabHover or self.Config.TabBg)
    frame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 0.55)
    frame:SetBackdropBorderColor(
        self.Config.SectionBorder.r,
        self.Config.SectionBorder.g,
        self.Config.SectionBorder.b,
        selected and math.max(0.08, self.Config.SectionBorder.a or 0) or 0
    )
end

-- =============================================================================
-- PANEL CREATION
-- =============================================================================

function RC:CreatePanel(name, parent, width, height)
    local frame = CreateFrame("Frame", name, parent or UIParent, "BackdropTemplate")
    frame:SetSize(width or 400, height or 300)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetToplevel(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    RC:SkinFrame(frame)
    RC:ApplyThemedWindow(frame, "window")

    -- Drag support – re-anchor to CENTER on drop so later scale changes don't jitter.
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        local cx, cy = frame:GetCenter()
        if cx then
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
        end
    end)

    if name and RC.RegisterEscapeFrame then
        RC:RegisterEscapeFrame(frame)
    end

    return frame
end

-- =============================================================================
-- CLOSE BUTTON (X with hover tint)
-- =============================================================================

function RC:CreateCloseButton(parent, size, frameTemplate)
    local btn = CreateFrame("Button", nil, parent, frameTemplate or "BackdropTemplate")
    btn.rcBorderMinAlpha = 0.15
    local buttonSize = size or 20
    btn:SetSize(buttonSize, buttonSize)
    RC:SkinFrame(btn)
    RC:SetFrameThemeRole(btn, "ButtonBg")
    btn:SetBackdropBorderColor(RC:GetControlBorderColor(0.15))

    local icon = btn:CreateTexture(nil, "OVERLAY")
    local iconSize = math.max(10, buttonSize - 8)
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("CENTER", 0, 0)

    if RC.Icons and RC.Icons.Texture and RC.Icons.WhiteX then
        icon:SetTexture(RC.Icons.Texture)
        icon:SetTexCoord(unpack(RC.Icons.WhiteX))
    else
        icon:SetTexture("Interface\\Buttons\\WHITE8X8")
    end
    icon:SetVertexColor(0.85, 0.85, 0.85, 1)
    btn.Icon = icon

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(RC.Config.ErrorColor.r, RC.Config.ErrorColor.g, RC.Config.ErrorColor.b, 0.72)
        self:SetBackdropBorderColor(RC.Config.ErrorColor.r, RC.Config.ErrorColor.g, RC.Config.ErrorColor.b, 1)
        self.Icon:SetVertexColor(1, 1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
        self:SetBackdropBorderColor(RC:GetControlBorderColor(0.15))
        self.Icon:SetVertexColor(0.85, 0.85, 0.85, 1)
    end)

    return btn
end

-- =============================================================================
-- SCROLLBAR HELPER — thin flat thumb, flush to parent right edge
-- =============================================================================

-- Creates a simple custom scrollbar. Returns the slider frame.
-- parent       : the frame the scrollbar lives inside
-- scrollframe  : the ScrollFrame whose vertical scroll this controls
-- Call RC:UpdateScrollbar(scrollbar, contentH, viewH) to update range.
function RC:CreateScrollbar(parent, scrollframe)
    local sb = CreateFrame("Slider", nil, parent)
    sb:SetWidth(RC:GetThemeLayout("scrollbarWidth", 4))
    sb:SetPoint("TOPRIGHT",    parent, "TOPRIGHT",    -2, -6)
    sb:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -2,  6)
    sb:SetOrientation("VERTICAL")
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:EnableMouse(true)
    sb:EnableMouseWheel(true)

    -- Track background
    local track = sb:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(RC.Config.ScrollTrack.r, RC.Config.ScrollTrack.g, RC.Config.ScrollTrack.b, RC.Config.ScrollTrack.a or 0.08)

    -- Thumb
    sb:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
    local thumb = sb:GetThumbTexture()
    if thumb then
        thumb:SetVertexColor(RC.Config.ScrollThumb.r, RC.Config.ScrollThumb.g, RC.Config.ScrollThumb.b, RC.Config.ScrollThumb.a or 0.56)
        thumb:SetSize(RC:GetThemeLayout("scrollbarWidth", 4), RC:GetThemeLayout("scrollbarThumbHeight", 36))
    end

    -- Hover: brighten thumb
    sb:SetScript("OnEnter", function()
        if thumb then thumb:SetVertexColor(RC.Config.AccentHover.r, RC.Config.AccentHover.g, RC.Config.AccentHover.b, 0.82) end
    end)
    sb:SetScript("OnLeave", function()
        if thumb then thumb:SetVertexColor(RC.Config.ScrollThumb.r, RC.Config.ScrollThumb.g, RC.Config.ScrollThumb.b, RC.Config.ScrollThumb.a or 0.56) end
    end)

    if scrollframe then
        sb:SetScript("OnValueChanged", function(self, val)
            scrollframe:SetVerticalScroll(val)
        end)
        scrollframe:SetScript("OnMouseWheel", function(_, delta)
            local min, max = sb:GetMinMaxValues()
            local cur = sb:GetValue()
            sb:SetValue(math.max(min, math.min(max, cur - delta * 30)))
        end)
    end

    -- Helper to resize range after content changes
    function sb:Update(contentHeight, viewHeight)
        if contentHeight <= viewHeight then
            self:SetValue(0)
            self:Hide()
        else
            self:SetMinMaxValues(0, contentHeight - viewHeight)
            self:Show()
        end
    end

    function sb:RefreshTheme()
        self:SetWidth(RC:GetThemeLayout("scrollbarWidth", 4))
        track:SetColorTexture(RC.Config.ScrollTrack.r, RC.Config.ScrollTrack.g, RC.Config.ScrollTrack.b, RC.Config.ScrollTrack.a or 0.08)
        if thumb then
            thumb:SetVertexColor(RC.Config.ScrollThumb.r, RC.Config.ScrollThumb.g, RC.Config.ScrollThumb.b, RC.Config.ScrollThumb.a or 0.56)
            thumb:SetSize(RC:GetThemeLayout("scrollbarWidth", 4), RC:GetThemeLayout("scrollbarThumbHeight", 36))
        end
    end

    RC:RegisterThemeWidget(sb)
    sb:Hide()
    return sb
end

-- =============================================================================
-- LEGACY BUTTON CREATION (For non-AceGUI contexts)
-- =============================================================================

function RC:CreateButton(name, parent)
    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn.rcBorderMinAlpha = 0.06
    RC:SkinFrame(btn)
    RC:SetFrameThemeRole(btn, "ButtonBg")
    btn:SetBackdropBorderColor(RC:GetControlBorderColor())

    local text = btn:CreateFontString(nil, "OVERLAY")
    RC:SetFont(text, 11, "OUTLINE")
    text:SetPoint("CENTER")
    RC:SetTextColor(text, "button")
    btn.Text = text

    btn:SetScript("OnEnter", function(self)
        RC:SetModifiedBackdrop(self)
        self:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(RC:GetControlBorderColor())
        self:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a)
    end)

    return btn
end

-- Standard Button: flat style with visible background for all modules
function RC:CreateStandardButton(name, parent, width, height)
    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn.rcBorderMinAlpha = 0.06
    btn:SetSize(width or 100, height or 24)

    RC:SkinFrame(btn)
    RC:SetFrameThemeRole(btn, "ButtonBg")
    btn:SetBackdropBorderColor(RC:GetControlBorderColor())

    -- Text (dynamic color from settings, explicit font — never Blizzard defaults)
    local text = btn:CreateFontString(nil, "OVERLAY")
    RC:SetFont(text, 11, "OUTLINE")
    text:SetPoint("CENTER")
    text:SetTextColor(RC:GetButtonTextColor())
    RC:RegisterTextColor(text, "button")
    btn.Text = text

    -- Hover: accent border + lighter background
    -- Guard customBg so special color states (e.g. red Cancel button) are preserved.
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.52)
        if not self.customBg then
            self:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
        end
    end)
    btn:SetScript("OnLeave", function(self)
        local br, bg, bb, ba = RC:GetControlBorderColor()
        self:SetBackdropBorderColor(br, bg, bb, ba)
        -- Restore correct bg (may be overridden for special states like Pull Cancel)
        if not self.customBg then
            self:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a)
        end
    end)

    -- Pressed effect (guard customBg so Cancel button stays red)
    btn:SetScript("OnMouseDown", function(self)
        if not self.customBg then
            self:SetBackdropColor(RC.Config.ButtonPressed.r, RC.Config.ButtonPressed.g, RC.Config.ButtonPressed.b, 1)
        end
    end)
    btn:SetScript("OnMouseUp", function(self)
        if self.customBg then return end
        if self:IsMouseOver() then
            self:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
        else
            self:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a)
        end
    end)

    return btn
end

-- =============================================================================
-- ROLE ICONS
-- =============================================================================

-- Using custom role icon texture: role.png
-- Texture is 1536x1024 with 3 icons in a horizontal row (512x512 each icon area)
-- Icons are centered vertically with white padding above/below
-- Icon area: approximately Y 200-712 (512px height) out of 1024px total
-- Y coords: 200/1024 = 0.195, 712/1024 = 0.695 (but let's use tighter crop)
-- Adjusted to 200-700 for better square crop: 0.195 to 0.684
RC.RoleIcons = {
    Texture = "Interface\\AddOns\\RaidControl\\Media\\role.png",
    -- TexCoord format: left, right, top, bottom
    -- Cropping to the square icon area, removing white padding
    TANK    = { 0.000, 0.333, 0.20, 0.70 }, -- Left third: Shield
    HEALER  = { 0.333, 0.667, 0.20, 0.70 }, -- Middle third: Cross/Plus
    DPS     = { 0.667, 1.000, 0.20, 0.70 }, -- Right third: Sword
}

-- =============================================================================
-- UI ICONS (icons.png - 1536x1024, 2x3 grid)
-- =============================================================================
-- Layout:
-- Row 1: White X | Green Check | Red X
-- Row 2: Yellow ? | Up Arrow    | Down Arrow
RC.Icons = {
    Texture = "Interface\\AddOns\\RaidControl\\Media\\icons.png",
    -- Top row (0-50% height) - each icon is 512x512
    WhiteX       = { 0.000, 0.333, 0.000, 0.500 }, -- White X (close)
    GreenCheck   = { 0.333, 0.667, 0.000, 0.500 }, -- Green checkmark
    RedX         = { 0.667, 1.000, 0.000, 0.500 }, -- Red X (cancel)
    -- Bottom row (50-100% height)
    YellowQuestion = { 0.000, 0.333, 0.500, 1.000 }, -- Yellow question mark
    ArrowUp      = { 0.333, 0.667, 0.500, 1.000 }, -- Up arrow
    ArrowDown    = { 0.667, 1.000, 0.500, 1.000 }, -- Down arrow
}

-- =============================================================================
-- ACEGUI WIDGET REGISTRATION
-- =============================================================================

function RC:RegisterCustomWidgets()
    local AceGUI = LibStub("AceGUI-3.0")

    -- Shared backdrop helper
    local function CreateBackdrop(frame)
        if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
        frame:SetBackdrop(RC.Config.Backdrop)
        frame:SetBackdropColor(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, RC.Config.Color.a)
        frame:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, RC.Config.Border.a or 1)
        if not frame._rcInsetTop then
            local insetTop = frame:CreateTexture(nil, "ARTWORK", nil, 1)
            insetTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
            insetTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
            insetTop:SetHeight(1)
            insetTop:SetColorTexture(1, 1, 1, 0.055)
            frame._rcInsetTop = insetTop

            local insetBottom = frame:CreateTexture(nil, "ARTWORK", nil, 1)
            insetBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
            insetBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
            insetBottom:SetHeight(1)
            insetBottom:SetColorTexture(0, 0, 0, 0.24)
            frame._rcInsetBottom = insetBottom
        end
    end

    -- =========================================================================
    -- RC_Button
    -- =========================================================================
    local function Constructor_Button()
        local frame = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
        frame:Hide()
        frame:EnableMouse(true)
        frame:RegisterForClicks("AnyUp")

        CreateBackdrop(frame)

        local text = frame:CreateFontString(nil, "OVERLAY")
        RC:SetFont(text, 12, "OUTLINE")
        text:SetPoint("TOPLEFT",     4, -4)
        text:SetPoint("BOTTOMRIGHT", -4, 4)
        text:SetJustifyH("CENTER")
        RC:SetTextColor(text, "general")

        -- Bottom accent line (shown on hover)
        local accentLine = frame:CreateTexture(nil, "OVERLAY")
        accentLine:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  1, 1)
        accentLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        accentLine:SetHeight(2)
        accentLine:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
        accentLine:Hide()

        local widget = { frame = frame, type = "RC_Button", text = text, accentLine = accentLine }

        frame:SetScript("OnEnter", function()
            if widget.disabled then
                return
            end
            frame:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, RC:IsShadowsteelTheme() and 0.38 or 0.52)
            frame:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
            accentLine:SetHeight(RC:IsShadowsteelTheme() and 1 or 2)
            accentLine:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, RC:IsShadowsteelTheme() and 0.72 or 1)
            accentLine:Show()
            widget:Fire("OnEnter")
        end)
        frame:SetScript("OnLeave", function()
            local br, bg, bb, ba = RC:GetControlBorderColor()
            frame:SetBackdropBorderColor(br, bg, bb, ba)
            if not widget.danger then
                local bgColor = widget.disabled and RC.Config.ButtonDisabled or RC.Config.ButtonBg
                frame:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
            end
            accentLine:Hide()
            widget:Fire("OnLeave")
        end)
        frame:SetScript("OnMouseDown", function()
            if not widget.disabled then
                frame:SetBackdropColor(RC.Config.ButtonPressed.r, RC.Config.ButtonPressed.g, RC.Config.ButtonPressed.b, 1)
            end
        end)
        frame:SetScript("OnMouseUp", function()
            if not widget.disabled then
                frame:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
            end
        end)
        frame:SetScript("OnClick", function(self, ...)
            widget:Fire("OnClick", ...)
        end)

        function widget:SetDanger(isDanger)
            self.danger = isDanger
            if isDanger then
                frame:SetBackdropColor(RC.Config.DangerColor.r, RC.Config.DangerColor.g, RC.Config.DangerColor.b, 0.7)
            else
                frame:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a)
            end
        end

        function widget:SetRelativeWidth(width)
            self.relWidth = width
            self.width = "relative"
        end

        function widget:SetFullWidth(isFull)
            if isFull then
                self:SetRelativeWidth(1)
            else
                self.relWidth = nil
                if type(self.width) ~= "number" then
                    self.width = nil
                end
            end
        end

        function widget:OnAcquire()
            self._rcSettingsGrid = nil
            self:SetHeight(30)
            self:SetWidth(200)
            self:SetDisabled(false)
            self:SetText("")
            self.danger = false
            self:RefreshTheme()
            self.frame:Show()
        end

        function widget:OnRelease()
            self.frame:Hide()
        end

        function widget:SetText(t)
            self.text:SetText(t)
        end

        function widget:SetDisabled(disabled)
            self.disabled = disabled
            if disabled then
                self.frame:Disable()
                self.text:SetTextColor(RC.Config.DisabledText.r, RC.Config.DisabledText.g, RC.Config.DisabledText.b)
                self.frame:SetBackdropColor(RC.Config.ButtonDisabled.r, RC.Config.ButtonDisabled.g, RC.Config.ButtonDisabled.b, RC.Config.ButtonDisabled.a or 0.45)
                self.frame:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, math.max(0.04, RC.Config.Border.a or 0))
            else
                self.frame:Enable()
                if not self.disabled then
                    self.text:SetTextColor(RC:GetGeneralTextColor())
                end
                self:RefreshTheme()
            end
        end

        function widget:RefreshTheme()
            accentLine:SetHeight(RC:IsShadowsteelTheme() and 1 or 2)
            accentLine:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, RC:IsShadowsteelTheme() and 0.72 or 1)
            local bg = self.disabled and RC.Config.ButtonDisabled or (self.danger and RC.Config.DangerColor or RC.Config.ButtonBg)
            frame:SetBackdropColor(bg.r, bg.g, bg.b, self.danger and 0.70 or (bg.a or 1))
            frame:SetBackdropBorderColor(RC:GetControlBorderColor())
            if not self.disabled then
                self.text:SetTextColor(RC:GetGeneralTextColor())
            end
        end

        function widget:SetParent(parent)
            -- Resolve to the correct WoW frame: prefer .content (AceGUI containers),
            -- then .frame (RC_ widgets), then the raw value (raw WoW frame)
            local parentFrame = (parent and parent.content) or (parent and parent.frame) or parent

            if parentFrame then
                self.frame:SetParent(parentFrame)
                self.frame:SetFrameStrata(parentFrame:GetFrameStrata())
                local baseLevel = parentFrame:GetFrameLevel()
                self.frame:SetFrameLevel(baseLevel + 5)
            end
        end

        RC:RegisterThemeWidget(widget)
        AceGUI:RegisterAsWidget(widget)
        return widget
    end
    AceGUI:RegisterWidgetType("RC_Button", Constructor_Button, 3)

    local function GetSettingsGridSplit(frame, fallbackWidth)
        local width = frame and frame.GetWidth and frame:GetWidth()
        if not width or width < 120 then
            width = tonumber(fallbackWidth) or 220
        end

        local labelWidth = math.floor(width * RC:GetThemeLayout("labelColumnWidth", 0.46))
        local gutter = RC:IsShadowsteelTheme() and 8 or 10
        labelWidth = math.max(92, math.min(labelWidth, width - 180))
        return labelWidth, labelWidth + gutter
    end

    -- =========================================================================
    -- RC_Slider
    -- =========================================================================
    local function Constructor_Slider()
        local frame = CreateFrame("Frame", nil, UIParent)

        -- Compact slider group: label, track, centered value box.
        local label = frame:CreateFontString(nil, "OVERLAY")
        RC:SetFont(label, 11, "OUTLINE")
        label:SetPoint("TOPLEFT")
        label:SetHeight(16)
        label:SetJustifyH("LEFT")
        RC:SetTextColor(label, "title")

        local valueText = frame:CreateFontString(nil, "OVERLAY")
        RC:SetFont(valueText, 11, "OUTLINE")
        valueText:SetPoint("TOPRIGHT")
        valueText:SetHeight(16)
        valueText:SetJustifyH("RIGHT")
        valueText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)
        valueText:Hide()

        -- Slider track (3px flat)
        local slider = CreateFrame("Slider", nil, frame)
        slider:SetOrientation("HORIZONTAL")
        slider:SetHeight(RC:GetThemeLayout("sliderHeight", 14))
        slider:SetHitRectInsets(0, 0, -8, -8)
        slider:SetPoint("TOP", label, "BOTTOM", 0, -8)
        slider:SetPoint("LEFT",  4, 0)
        slider:SetPoint("RIGHT", -4, 0)

        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetHeight(RC:GetThemeLayout("sliderTrackHeight", 4))
        track:SetPoint("LEFT",  slider, "LEFT",  0, 0)
        track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
        track:SetColorTexture(RC.Config.SliderTrack.r, RC.Config.SliderTrack.g, RC.Config.SliderTrack.b, RC.Config.SliderTrack.a or 1)

        local fill = slider:CreateTexture(nil, "ARTWORK")
        fill:SetHeight(RC:GetThemeLayout("sliderTrackHeight", 4))
        fill:SetPoint("LEFT", track, "LEFT", 0, 0)
        fill:SetColorTexture(RC.Config.SliderFill.r, RC.Config.SliderFill.g, RC.Config.SliderFill.b, RC.Config.SliderFill.a or 1)
        fill:SetWidth(0.01)
        fill:Hide()

        slider:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local nativeThumb = slider:GetThumbTexture()
        if nativeThumb then
            nativeThumb:SetAlpha(0)
            nativeThumb:SetSize(1, 1)
        end
        local thumb = slider:CreateTexture(nil, "OVERLAY")
        thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
        thumb:SetVertexColor(RC.Config.SliderThumb.r, RC.Config.SliderThumb.g, RC.Config.SliderThumb.b, RC.Config.SliderThumb.a or 1)
        thumb:SetSize(RC:GetThemeLayout("sliderThumbWidth", 10), RC:GetThemeLayout("sliderThumbHeight", 18))

        local valueBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
        valueBox:SetSize(58, 18)
        valueBox:SetPoint("TOP", slider, "BOTTOM", 0, -5)
        valueBox:SetAutoFocus(false)
        valueBox:SetJustifyH("CENTER")
        valueBox:SetTextInsets(4, 4, 0, 0)
        valueBox:SetFont(RC:GetFont(), 11, "")
        RC:RegisterFontString(valueBox, 11, "OUTLINE")
        RC:SkinFrame(valueBox)
        valueBox:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, RC.Config.InputBg.a or 1)
        valueBox:SetBackdropBorderColor(RC:GetControlBorderColor(0.15))

        local widget = {
            frame     = frame,
            type      = "RC_Slider",
            slider    = slider,
            label     = label,
            valueText = valueText,
            valueBox  = valueBox,
            track     = track,
            fill      = fill,
            thumb     = thumb,
            nativeThumb = nativeThumb,
        }

        local function SnapValue(value)
            value = tonumber(value) or widget.value or widget.min or 0
            if widget.step and widget.step > 0 then
                local minVal = widget.min or 0
                value = math.floor((value - minVal) / widget.step + 0.5) * widget.step + minVal
            end
            if widget.min and value < widget.min then value = widget.min end
            if widget.max and value > widget.max then value = widget.max end
            return value
        end

        local function UpdateValueDisplay()
            local v = widget.value or 0
            local step = widget.step or 1
            local textValue
            if step < 1 then
                textValue = string.format("%.2f", v)
            else
                textValue = tostring(math.floor(v + 0.5))
            end
            valueText:SetText(textValue)
            valueBox:SetText(textValue)
        end

        local function UpdateFill()
            local minVal, maxVal = slider:GetMinMaxValues()
            local range = (maxVal or 0) - (minVal or 0)
            if not fill or range <= 0 then
                if fill then fill:Hide() end
                return
            end
            local pct = ((widget.value or minVal or 0) - (minVal or 0)) / range
            pct = math.max(0, math.min(1, pct))
            local trackWidth = track:GetWidth() or 0
            local x = trackWidth * pct
            if thumb then
                thumb:ClearAllPoints()
                thumb:SetPoint("CENTER", track, "LEFT", x, 0)
                thumb:Show()
            end
            if trackWidth < 4 or pct <= 0.001 then
                fill:SetWidth(0.01)
                fill:Hide()
                return
            end
            fill:SetWidth(math.min(trackWidth, math.max(1, x)))
            fill:Show()
        end

        slider:SetScript("OnValueChanged", function(self, newvalue)
            if self.setup then return end
            newvalue = SnapValue(newvalue)
            widget.value = newvalue
            UpdateValueDisplay()
            UpdateFill()
            widget:Fire("OnValueChanged", newvalue)
        end)

        slider:SetScript("OnSizeChanged", function()
            UpdateFill()
        end)
        slider:SetScript("OnEnter", function()
            widget.hovered = true
            widget:RefreshTheme()
        end)
        slider:SetScript("OnLeave", function()
            widget.hovered = false
            widget.dragging = false
            widget:RefreshTheme()
        end)
        slider:SetScript("OnMouseDown", function(_, button)
            if button == "LeftButton" then
                widget.dragging = true
                widget:RefreshTheme()
            end
        end)
        slider:SetScript("OnMouseUp", function()
            widget.dragging = false
            widget:RefreshTheme()
            widget:Fire("OnMouseUp", widget.value)
        end)

        valueBox:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
        end)
        valueBox:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))
        end)
        valueBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            UpdateValueDisplay()
        end)
        valueBox:SetScript("OnEnterPressed", function(self)
            local newValue = SnapValue(self:GetText())
            widget:SetValue(newValue)
            widget:Fire("OnValueChanged", newValue)
            widget:Fire("OnMouseUp", newValue)
            self:ClearFocus()
        end)

        function widget:SetRelativeWidth(width)
            self.relWidth = width
            self.width = "relative"
        end

        function widget:SetFullWidth(isFull)
            if isFull then
                self:SetRelativeWidth(1)
            else
                self.relWidth = nil
                if type(self.width) ~= "number" then
                    self.width = nil
                end
            end
        end

        function widget:OnAcquire()
            self._rcSettingsGrid = nil
            self:SetWidth(200)
            self:SetHeight(RC:GetThemeLayout("settingsRowHeight", RC:GetThemeLayout("rowHeight", 44)))
            self:SetDisabled(false)
            self:SetSliderValues(0, 100, 1)
            self:SetValue(0)
            self:RefreshTheme()
            self.frame:Show()
        end

        function widget:OnRelease()
            self.frame:Hide()
        end

        function widget:SetLabel(text)
            self.label:SetText(text)
        end

        function widget:SetValue(val)
            self.slider.setup = true
            self.slider:SetValue(val)
            self.value = val
            UpdateValueDisplay()
            UpdateFill()
            self.slider.setup = nil
        end

        function widget:GetValue()
            return self.value
        end

        function widget:SetSliderValues(minVal, maxVal, step)
            self.min   = minVal
            self.max   = maxVal
            self.step  = step
            self.slider:SetMinMaxValues(minVal or 0, maxVal or 100)
            self.slider:SetValueStep(step or 1)
        end

        function widget:SetDisabled(disabled)
            self.disabled = disabled
            if disabled then
                self.slider:EnableMouse(false)
                self.label:SetTextColor(RC.Config.DisabledText.r, RC.Config.DisabledText.g, RC.Config.DisabledText.b)
                self.valueBox:SetTextColor(RC.Config.DisabledText.r, RC.Config.DisabledText.g, RC.Config.DisabledText.b)
                self.valueBox:EnableMouse(false)
                if self.thumb then
                    self.thumb:SetVertexColor(RC.Config.DisabledText.r, RC.Config.DisabledText.g, RC.Config.DisabledText.b, 0.55)
                end
                self:RefreshTheme()
            else
                self.slider:EnableMouse(true)
                self.valueBox:EnableMouse(true)
                RC:SetTextColor(self.label, "general")
                self.valueBox:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 0.88)
                self:RefreshTheme()
            end
        end

        function widget:RefreshTheme()
            self.slider:SetHeight(RC:GetThemeLayout("sliderHeight", 14))
            local trackHeight = RC:GetThemeLayout("sliderTrackHeight", 4)
            self.track:SetHeight(trackHeight)
            self.fill:SetHeight(trackHeight)
            self.track:SetColorTexture(RC.Config.SliderTrack.r, RC.Config.SliderTrack.g, RC.Config.SliderTrack.b, RC.Config.SliderTrack.a or 1)
            local fillAlpha = self.dragging and 0.86 or (self.hovered and 0.78 or (RC:IsShadowsteelTheme() and 0.66 or 0.60))
            self.fill:SetColorTexture(RC.Config.SliderFill.r, RC.Config.SliderFill.g, RC.Config.SliderFill.b, math.min(RC.Config.SliderFill.a or 1, fillAlpha))
            if self.thumb then
                if self.disabled then
                    self.thumb:SetVertexColor(RC.Config.DisabledText.r, RC.Config.DisabledText.g, RC.Config.DisabledText.b, 0.55)
                elseif self.dragging then
                    self.thumb:SetVertexColor(RC.Config.SliderThumb.r, RC.Config.SliderThumb.g, RC.Config.SliderThumb.b, 1)
                elseif self.hovered then
                    self.thumb:SetVertexColor(RC.Config.SliderThumb.r, RC.Config.SliderThumb.g, RC.Config.SliderThumb.b, 0.92)
                else
                    self.thumb:SetVertexColor(RC.Config.SliderThumb.r, RC.Config.SliderThumb.g, RC.Config.SliderThumb.b, RC.Config.SliderThumb.a or 1)
                end
                self.thumb:SetSize(RC:GetThemeLayout("sliderThumbWidth", 10), RC:GetThemeLayout("sliderThumbHeight", 18))
            end
            if self.nativeThumb then
                self.nativeThumb:SetAlpha(0)
                self.nativeThumb:SetSize(1, 1)
            end
            self.valueBox:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, RC.Config.InputBg.a or 1)
            if self.hovered or self.dragging then
                self.valueBox:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC:IsShadowsteelTheme() and 0.58 or 0.42)
            else
                self.valueBox:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))
            end
            self.valueBox:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, self.disabled and 0.48 or 0.88)
            UpdateFill()

            self.label:ClearAllPoints()
            self.slider:ClearAllPoints()
            self.valueBox:ClearAllPoints()
            if RC:IsModernTheme() then
                local labelHeight = RC:IsShadowsteelTheme() and 14 or 15
                local valueWidth = RC:GetThemeLayout("sliderValueWidth", 48)
                local valueHeight = RC:GetThemeLayout("sliderValueHeight", 24)
                self.label:SetHeight(labelHeight)
                if self._rcSettingsGrid then
                    local labelWidth, controlX = GetSettingsGridSplit(self.frame, self.width)
                    local trackTop = RC:IsShadowsteelTheme() and -8 or -10
                    local valueGap = RC:IsShadowsteelTheme() and 8 or 10
                    self.label:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, trackTop)
                    self.label:SetPoint("TOPRIGHT", self.frame, "TOPLEFT", labelWidth - 8, trackTop)
                    self.label:SetJustifyH("LEFT")
                    self.slider:SetPoint("TOPLEFT", self.frame, "TOPLEFT", controlX, trackTop - 1)
                    self.slider:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -(14 + valueWidth + valueGap), trackTop - 1)
                    self.valueBox:SetSize(valueWidth, valueHeight)
                    self.valueBox:SetPoint("LEFT", self.slider, "RIGHT", valueGap, 0)
                else
                    self.label:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 14, -2)
                    self.label:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -14, -2)
                    self.label:SetJustifyH("LEFT")
                    self.slider:SetPoint("TOPLEFT", self.label, "BOTTOMLEFT", 2, RC:IsShadowsteelTheme() and -3 or -4)
                    self.slider:SetPoint("TOPRIGHT", self.label, "BOTTOMRIGHT", -2, RC:IsShadowsteelTheme() and -3 or -4)
                    self.valueBox:SetSize(valueWidth, valueHeight)
                    self.valueBox:SetPoint("TOP", self.slider, "BOTTOM", 0, RC:IsShadowsteelTheme() and -3 or -4)
                end
                C_Timer.After(0, UpdateFill)
            else
                self.label:SetPoint("TOPLEFT")
                self.slider:SetPoint("TOP", self.label, "BOTTOM", 0, -8)
                self.slider:SetPoint("LEFT", 4, 0)
                self.slider:SetPoint("RIGHT", -4, 0)
                self.valueBox:SetSize(58, 18)
                self.valueBox:SetPoint("TOP", self.slider, "BOTTOM", 0, -5)
            end
        end

        slider.obj = widget

        RC:RegisterThemeWidget(widget)
        AceGUI:RegisterAsWidget(widget)
        return widget
    end
    AceGUI:RegisterWidgetType("RC_Slider", Constructor_Slider, 4)

    -- =========================================================================
    -- RC_EditBox
    -- =========================================================================
    local function Constructor_EditBox()
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:Hide()

        local label = frame:CreateFontString(nil, "OVERLAY")
        RC:SetFont(label, 11, "OUTLINE")
        label:SetPoint("TOPLEFT", 0, 0)
        label:SetPoint("TOPRIGHT", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetHeight(16)
        RC:SetTextColor(label, "title")

        local editbox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
        editbox:SetAutoFocus(false)
        editbox:SetFont(RC:GetFont(), 11, "")
        RC:RegisterFontString(editbox, 11, "OUTLINE")
        editbox:SetPoint("TOPLEFT",     label, "BOTTOMLEFT",  0, -3)
        editbox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0,  0)
        editbox:SetTextInsets(8, 8, 0, 0)
        RC:SkinFrame(editbox)
        editbox:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, RC.Config.InputBg.a)

        local widget = {
            frame = frame,
            editbox = editbox,
            label = label,
            type = "RC_EditBox"
        }

        editbox:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
        end)
        editbox:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))
        end)

        -- Text is committed on Enter and when focus moves elsewhere, so an
        -- edit is never lost by clicking away. Escape restores the last
        -- committed text instead.
        local function Commit(self)
            local text = self:GetText()
            if text == widget.committedText then
                return
            end
            widget.committedText = text
            widget:Fire("OnEnterPressed", text)
        end

        editbox:SetScript("OnEnterPressed", function(self)
            Commit(self)
            self:ClearFocus()
        end)

        editbox:SetScript("OnEscapePressed", function(self)
            self:SetText(widget.committedText or "")
            self:ClearFocus()
            widget:Fire("OnEscapePressed")
        end)

        editbox:SetScript("OnEditFocusGained", function(self)
            if widget.selectAllOnFocus then
                self:HighlightText()
            end
        end)

        editbox:SetScript("OnEditFocusLost", function(self)
            self:HighlightText(0, 0)
            -- A page rebuild hides the box while it has focus; committing
            -- then could rebuild the page again mid-release.
            if self:IsVisible() then
                Commit(self)
            end
        end)

        editbox:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                widget:Fire("OnTextChanged", self:GetText())
            end
        end)

        function widget:OnAcquire()
            self._rcSettingsGrid = nil
            self.selectAllOnFocus = nil
            self.stackedLayout = nil
            self.editbox:SetMaxLetters(0)
            self:SetHeight(44)
            self:SetWidth(200)
            self:SetLabel("")
            self:SetText("")
            self:RefreshTheme()
            self.frame:Show()
        end

        -- Selects the whole text when the box is focused, for copy fields.
        function widget:SetSelectAllOnFocus(enabled)
            self.selectAllOnFocus = enabled and true or false
        end

        -- Puts the label above a box that spans the whole row, for long values.
        function widget:SetStackedLayout(enabled)
            self.stackedLayout = enabled and true or false
            self:RefreshTheme()
        end

        function widget:OnRelease()
            self.frame:Hide()
        end

        function widget:SetLabel(text)
            self.label:SetText(text)
        end

        function widget:SetText(text)
            self.committedText = text or ""
            self.editbox:SetText(self.committedText)
            self.editbox:SetCursorPosition(0)
        end

        function widget:GetText()
            return self.editbox:GetText()
        end

        function widget:RefreshTheme()
            self.editbox:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, RC.Config.InputBg.a or 1)
            self.editbox:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))

            self.label:ClearAllPoints()
            self.editbox:ClearAllPoints()
            if self.stackedLayout then
                local inset = RC:IsModernTheme() and 14 or 0
                self.label:SetPoint("TOPLEFT", self.frame, "TOPLEFT", inset, -6)
                self.label:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -inset, -6)
                self.editbox:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", inset, 6)
                self.editbox:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -inset, 6)
                self.editbox:SetHeight(RC:GetThemeLayout("inputHeight", 28))
            elseif RC:IsModernTheme() then
                if self._rcSettingsGrid then
                    local labelWidth, controlX = GetSettingsGridSplit(self.frame, self.width)
                    self.label:SetPoint("LEFT", self.frame, "LEFT", 14, 0)
                    self.label:SetPoint("RIGHT", self.frame, "LEFT", labelWidth - 8, 0)
                    self.editbox:SetPoint("LEFT", self.frame, "LEFT", controlX, 0)
                else
                    self.label:SetPoint("LEFT", self.frame, "LEFT", 14, 0)
                    self.label:SetPoint("RIGHT", self.frame, "CENTER", -8, 0)
                    self.editbox:SetPoint("LEFT", self.frame, "CENTER", 8, 0)
                end
                self.editbox:SetPoint("RIGHT", self.frame, "RIGHT", -14, 0)
                self.editbox:SetHeight(RC:GetThemeLayout("inputHeight", 28))
            else
                self.label:SetPoint("TOPLEFT", 0, 0)
                self.label:SetPoint("TOPRIGHT", 0, 0)
                self.editbox:SetPoint("TOPLEFT", self.label, "BOTTOMLEFT", 0, -3)
                self.editbox:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)
            end
        end

        function widget:SetRelativeWidth(width)
            self.relWidth = width
            self.width = "relative"
        end

        function widget:SetFullWidth(isFull)
            if isFull then
                self:SetRelativeWidth(1)
            else
                self.relWidth = nil
                if type(self.width) ~= "number" then
                    self.width = nil
                end
            end
        end

        function widget:SetParent(parent)
            -- parent is an AceGUI widget, we need parent.frame
            local parentFrame = parent
            if parent and parent.frame then
                parentFrame = parent.frame
            end

            if parentFrame then
                self.frame:SetParent(parentFrame)
                self.frame:SetFrameStrata(parentFrame:GetFrameStrata())
                self.frame:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
            end
        end

        RC:RegisterThemeWidget(widget)
        AceGUI:RegisterAsWidget(widget)
        return widget
    end
    AceGUI:RegisterWidgetType("RC_EditBox", Constructor_EditBox, 2)

    -- =========================================================================
    -- RC_CheckBox
    -- =========================================================================
    local function Constructor_CheckBox()
        local frame = CreateFrame("Button", nil, UIParent)
        frame:EnableMouse(true)

        local rowBg = frame:CreateTexture(nil, "BACKGROUND")
        rowBg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 1)
        rowBg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, -1)
        rowBg:SetColorTexture(RC.Config.RowAltBg.r, RC.Config.RowAltBg.g, RC.Config.RowAltBg.b, RC.Config.RowAltBg.a or 0.18)
        rowBg:Hide()

        local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        box:SetPoint("LEFT", 0, 0)
        box:SetSize(16, 16)
        CreateBackdrop(box)

        -- Check mark (Accent, inset 2px)
        local check = box:CreateTexture(nil, "OVERLAY")
        check:SetTexture("Interface\\Buttons\\WHITE8X8")
        check:SetVertexColor(RC.Config.CheckboxChecked.r, RC.Config.CheckboxChecked.g, RC.Config.CheckboxChecked.b, RC.Config.CheckboxChecked.a or 1)
        check:SetPoint("TOPLEFT",     2, -2)
        check:SetPoint("BOTTOMRIGHT", -2, 2)
        check:Hide()

        local fill = box:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
        fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        fill:SetColorTexture(RC.Config.CheckboxChecked.r, RC.Config.CheckboxChecked.g, RC.Config.CheckboxChecked.b, 0.65)
        fill:Hide()

        -- Label text - anchored to prevent clipping
        local text = frame:CreateFontString(nil, "OVERLAY")
        RC:SetFont(text, 12, "OUTLINE")
        text:SetPoint("LEFT", box, "RIGHT", 10, 0)
        text:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")

        local widget = { frame = frame, type = "RC_CheckBox", check = check, text = text, box = box, rowBg = rowBg, fill = fill }

        -- Hover
        frame:SetScript("OnEnter", function()
            widget.hovered = true
            rowBg:SetColorTexture(RC.Config.RowHover.r, RC.Config.RowHover.g, RC.Config.RowHover.b, RC.Config.RowHover.a or 0.10)
            rowBg:Show()
            box:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
            widget:RefreshTheme()
        end)
        frame:SetScript("OnLeave", function()
            widget.hovered = false
            if widget.value then
                rowBg:Hide()
            else
                rowBg:SetColorTexture(RC.Config.SurfaceBg.r, RC.Config.SurfaceBg.g, RC.Config.SurfaceBg.b, 0.18)
                rowBg:Hide()
            end
            if RC:IsModernTheme() and not RC:IsShadowsteelTheme() then
                widget:RefreshTheme()
            else
                widget:RefreshTheme()
            end
        end)

        frame:SetScript("OnClick", function()
            if not widget.disabled then
                widget:SetValue(not widget.value)
                widget:Fire("OnValueChanged", widget.value)
            end
        end)

        function widget:SetRelativeWidth(width)
            self.relWidth = width
            self.width = "relative"
        end

        function widget:SetFullWidth(isFull)
            if isFull then
                self:SetRelativeWidth(1)
            else
                self.relWidth = nil
                if type(self.width) ~= "number" then
                    self.width = nil
                end
            end
        end

        function widget:OnAcquire()
            self._rcSettingsGrid = nil
            self:SetHeight(30)
            self:SetWidth(220)
            self:SetValue(false)
            self:SetDisabled(false)
            self:RefreshTheme()
            self.frame:Show()
        end

        function widget:OnRelease()
            self.frame:Hide()
        end

        function widget:SetValue(val)
            self.value = val
            if RC:IsModernTheme() then
                self.check:Show()
                self.rowBg:Hide()
                self:RefreshTheme()
            elseif val then
                self.check:Show()
                self.rowBg:Hide()
            else
                self.check:Hide()
                self.rowBg:SetColorTexture(RC.Config.RowAltBg.r, RC.Config.RowAltBg.g, RC.Config.RowAltBg.b, RC.Config.RowAltBg.a or 0.18)
                self.rowBg:Hide()
            end
        end

        function widget:GetValue()
            return self.value
        end

        function widget:SetLabel(t)
            self.text:SetText(t)
        end

        function widget:SetDisabled(disabled)
            self.disabled = disabled
            self:RefreshTheme()
        end

        function widget:RefreshTheme()
            self.rowBg:SetColorTexture(
                RC.Config.RowHover.r,
                RC.Config.RowHover.g,
                RC.Config.RowHover.b,
                RC.Config.RowHover.a or 0.08
            )
            self.box:ClearAllPoints()
            self.text:ClearAllPoints()
            self.check:ClearAllPoints()
            self.fill:ClearAllPoints()
            if RC:IsModernTheme() then
                local toggleWidth = 42
                local toggleHeight = 20
                local knobSize = math.max(10, toggleHeight - 6)
                local active = RC.Config.Accent
                local body = RC.Config.CheckboxBg
                local border = (self.value or self.hovered) and RC.Config.Accent or RC.Config.Border
                self.text:SetPoint("LEFT", self.frame, "LEFT", 14, 0)
                if self._rcSettingsGrid then
                    local labelWidth = GetSettingsGridSplit(self.frame, self.width)
                    self.text:SetPoint("RIGHT", self.frame, "LEFT", labelWidth - 8, 0)
                else
                    self.text:SetPoint("RIGHT", self.frame, "CENTER", -8, 0)
                end
                self.text:SetJustifyH("LEFT")
                self.box:SetPoint("RIGHT", self.frame, "RIGHT", -14, 0)
                self.box:SetSize(toggleWidth, toggleHeight)
                self.fill:SetPoint("TOPLEFT", self.box, "TOPLEFT", 2, -2)
                self.fill:SetPoint("BOTTOMRIGHT", self.box, "BOTTOMRIGHT", -2, 2)
                self.fill:SetColorTexture(
                    active.r,
                    active.g,
                    active.b,
                    self.disabled and 0.12 or (self.value and 0.66 or (self.hovered and 0.14 or 0))
                )
                self.fill:SetShown((self.value or (self.hovered and not self.disabled)) and true or false)
                self.box:SetBackdropColor(
                    body.r,
                    body.g,
                    body.b,
                    self.disabled and 0.46 or (body.a or 0.88)
                )
                self.box:SetBackdropBorderColor(
                    border.r,
                    border.g,
                    border.b,
                    self.disabled and 0.18 or ((self.value or self.hovered) and 0.58 or math.max(0.16, border.a or 0))
                )
                self.check:SetTexture("Interface\\Buttons\\WHITE8X8")
                if self.disabled then
                    self.check:SetVertexColor(RC.Config.DisabledText.r, RC.Config.DisabledText.g, RC.Config.DisabledText.b, 0.56)
                elseif self.value then
                    self.check:SetVertexColor(1, 1, 1, 0.98)
                else
                    self.check:SetVertexColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, self.hovered and 0.62 or 0.42)
                end
                self.check:SetSize(knobSize, knobSize)
                self.check:SetPoint(self.value and "RIGHT" or "LEFT", self.box, self.value and "RIGHT" or "LEFT", self.value and -3 or 3, 0)
                self.check:Show()
            else
                self.fill:Hide()
                self.box:SetPoint("LEFT", self.frame, "LEFT", RC:IsShadowsteelTheme() and 2 or 0, 0)
                self.box:SetSize(16, 16)
                self.box:SetBackdropColor(RC.Config.CheckboxBg.r, RC.Config.CheckboxBg.g, RC.Config.CheckboxBg.b, RC.Config.CheckboxBg.a or 1)
                self.box:SetBackdropBorderColor(
                    self.value and RC.Config.NavSelectedBorder.r or RC.Config.InputBorder.r,
                    self.value and RC.Config.NavSelectedBorder.g or RC.Config.InputBorder.g,
                    self.value and RC.Config.NavSelectedBorder.b or RC.Config.InputBorder.b,
                    self.value and 0.72 or math.max(0.14, RC.Config.InputBorder.a or 0)
                )
                self.text:SetPoint("LEFT", self.box, "RIGHT", 10, 0)
                self.text:SetPoint("RIGHT", self.frame, "RIGHT", -4, 0)
                self.text:SetJustifyH("LEFT")
                self.check:SetTexture("Interface\\Buttons\\WHITE8X8")
                self.check:SetVertexColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, RC.Config.Accent.a or 1)
                local inset = RC:IsShadowsteelTheme() and 4 or 2
                self.check:SetPoint("TOPLEFT", self.box, "TOPLEFT", inset, -inset)
                self.check:SetPoint("BOTTOMRIGHT", self.box, "BOTTOMRIGHT", -inset, inset)
                self.check:SetShown(self.value and true or false)
            end
            if self.disabled then
                self.text:SetTextColor(RC.Config.DisabledText.r, RC.Config.DisabledText.g, RC.Config.DisabledText.b)
                self.box:SetAlpha(0.58)
                self.fill:SetAlpha(0.55)
                self.check:SetAlpha(0.60)
            else
                self.text:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
                self.box:SetAlpha(1)
                self.fill:SetAlpha(1)
                self.check:SetAlpha(1)
            end
        end

        function widget:SetParent(parent)
            -- parent is an AceGUI widget, we need parent.frame
            local parentFrame = parent
            if parent and parent.frame then
                parentFrame = parent.frame
            end

            if parentFrame then
                self.frame:SetParent(parentFrame)
                self.frame:SetFrameStrata(parentFrame:GetFrameStrata())
                self.frame:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
            end
        end

        RC:RegisterThemeWidget(widget)
        AceGUI:RegisterAsWidget(widget)
        return widget
    end
    AceGUI:RegisterWidgetType("RC_CheckBox", Constructor_CheckBox, 3)

    -- =========================================================================
    -- RC_Dropdown
    -- =========================================================================
    RC.ActiveDropdowns = RC.ActiveDropdowns or {}
    local function CloseAllDropdowns(exceptPullout)
        for pullout, _ in pairs(RC.ActiveDropdowns) do
            if pullout ~= exceptPullout then
                pullout:Hide()
            end
        end
    end

    local function Constructor_Dropdown()
        local frame = CreateFrame("Frame", nil, UIParent)

        local box = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        box:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        box:SetHeight(26)
        CreateBackdrop(box)
        box:SetBackdropColor(RC.Config.DropdownBg.r, RC.Config.DropdownBg.g, RC.Config.DropdownBg.b, RC.Config.DropdownBg.a or 1)
        box:SetBackdropBorderColor(RC.Config.DropdownBorder.r, RC.Config.DropdownBorder.g, RC.Config.DropdownBorder.b, math.max(0.20, RC.Config.DropdownBorder.a or 0))

        -- Label
        local label = frame:CreateFontString(nil, "OVERLAY")
        RC:SetFont(label, 12, "OUTLINE")
        label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 4)
        label:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, 4)
        label:SetJustifyH("LEFT")
        label:SetTextColor(RC:GetTitleColor())
        label:SetText("")

        -- Selected Value Text
        local text = box:CreateFontString(nil, "OVERLAY")
        RC:SetFont(text, 11, "OUTLINE")
        text:SetPoint("LEFT", 8, 0)
        text:SetPoint("RIGHT", -24, 0)
        text:SetJustifyH("LEFT")
        text:SetText(L["Select..."])
        text:SetTextColor(1, 1, 1)

        -- Arrow (using icons.png - down arrow when closed)
        local arrow = box:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(14, 14)
        arrow:SetPoint("RIGHT", -8, 0)
        arrow:SetTexture(RC.Icons.Texture)
        arrow:SetTexCoord(unpack(RC.Icons.ArrowDown))
        arrow:SetVertexColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)

        -- Click button
        local button = CreateFrame("Button", nil, box)
        button:SetAllPoints()

        -- Pullout Menu (smart positioning - will open upward if not enough space below)
        local pullout = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        pullout:SetWidth(200)
        pullout:SetFrameStrata("TOOLTIP")
        pullout:SetFrameLevel(900) -- Ensure it floats above clipped settings panels
        CreateBackdrop(pullout)
        pullout:SetBackdropColor(RC.Config.DropdownBg.r, RC.Config.DropdownBg.g, RC.Config.DropdownBg.b, 0.99)
        pullout:SetBackdropBorderColor(RC.Config.DropdownBorder.r, RC.Config.DropdownBorder.g, RC.Config.DropdownBorder.b, math.max(0.20, RC.Config.DropdownBorder.a or 0))
        pullout:Hide()

        local pulloutTop = pullout:CreateTexture(nil, "ARTWORK")
        pulloutTop:SetPoint("TOPLEFT", pullout, "TOPLEFT", 1, -1)
        pulloutTop:SetPoint("TOPRIGHT", pullout, "TOPRIGHT", -1, -1)
        pulloutTop:SetHeight(1)
        pulloutTop:SetColorTexture(1, 1, 1, 0.06)

        -- Smart positioning function
        pullout.PositionSmart = function(self)
            local boxBottom = box:GetBottom()
            local screenHeight = GetScreenHeight()
            local uiScale = UIParent:GetEffectiveScale()
            local spaceBelow = (boxBottom or 0) * uiScale
            local spaceAbove = screenHeight - spaceBelow - (box:GetHeight() or 25) * uiScale
            local maxHeight = math.max(self:GetHeight() or 0, RC:IsModernTheme() and 196 or 160) * uiScale
            self:SetWidth(math.max(box:GetWidth() or 160, 160))

            -- If there is not enough space below the control, open upward while staying attached to the box.
            if spaceBelow < maxHeight and spaceAbove > spaceBelow then
                self:ClearAllPoints()
                self:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 1)
                self:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, 1)
            else
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -1)
                self:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 0, -1)
            end
        end

        -- Do not capture keyboard input here. Keyboard-enabled dropdowns can eat
        -- movement keys (W/A/S/D, arrows, space) while the game world is active.
        pullout:EnableKeyboard(false)
        if pullout.SetPropagateKeyboardInput then
            pullout:SetPropagateKeyboardInput(true)
        end
        pullout:SetScript("OnKeyDown", nil)

        pullout:SetScript("OnHide", function(self)
            RC.ActiveDropdowns[self] = nil
            if self.SetPropagateKeyboardInput then
                self:SetPropagateKeyboardInput(true)
            end
            if self.ArrowDown then self.ArrowDown() end
        end)

        pullout:SetScript("OnShow", function(self)
            if self.SetPropagateKeyboardInput then
                self:SetPropagateKeyboardInput(true)
            end
            if self.ArrowUp then self.ArrowUp() end
        end)

        -- ScrollFrame (content fills pullout minus 5px for scrollbar on right)
        local scrollFrame = CreateFrame("ScrollFrame", nil, pullout)
        scrollFrame:SetPoint("TOPLEFT",     pullout, "TOPLEFT",     0,  -4)
        scrollFrame:SetPoint("BOTTOMRIGHT", pullout, "BOTTOMRIGHT", -6,  4)
        scrollFrame:SetFrameLevel(pullout:GetFrameLevel() + 1)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetSize(180, 1)
        scrollFrame:SetScrollChild(scrollChild)

        -- Thin flush scrollbar on the right edge of pullout.
        -- Use a plain slider so no inherited scroll handlers or artwork exist.
        local scrollBar = CreateFrame("Slider", nil, pullout)
        scrollBar:SetOrientation("VERTICAL")
        scrollBar:SetPoint("TOPRIGHT",    scrollFrame, "TOPRIGHT",    0, 0)
        scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, 0)
        scrollBar:SetMinMaxValues(0, 1)
        scrollBar:SetValueStep(1)
        scrollBar.scrollStep = 22
        scrollBar:SetWidth(RC:GetThemeLayout("scrollbarWidth", 4))

        -- Skin
        local ddScrollTrack = scrollBar:CreateTexture(nil, "BACKGROUND")
        ddScrollTrack:SetAllPoints()
        ddScrollTrack:SetColorTexture(RC.Config.ScrollTrack.r, RC.Config.ScrollTrack.g, RC.Config.ScrollTrack.b, RC.Config.ScrollTrack.a or 0.08)
        scrollBar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local ddThumb = scrollBar:GetThumbTexture()
        if ddThumb then
            ddThumb:SetVertexColor(RC.Config.ScrollThumb.r, RC.Config.ScrollThumb.g, RC.Config.ScrollThumb.b, RC.Config.ScrollThumb.a or 0.56)
            ddThumb:SetSize(RC:GetThemeLayout("scrollbarWidth", 4), 20)
        end
        scrollBar:SetScript("OnEnter", function()
            if ddThumb then ddThumb:SetVertexColor(RC.Config.AccentHover.r, RC.Config.AccentHover.g, RC.Config.AccentHover.b, 0.82) end
        end)
        scrollBar:SetScript("OnLeave", function()
            if ddThumb then ddThumb:SetVertexColor(RC.Config.ScrollThumb.r, RC.Config.ScrollThumb.g, RC.Config.ScrollThumb.b, RC.Config.ScrollThumb.a or 0.56) end
        end)

        scrollFrame:EnableMouseWheel(true)
        scrollFrame:SetScript("OnMouseWheel", function(self, delta)
            local min, max = scrollBar:GetMinMaxValues()
            local current = scrollBar:GetValue()
            local new = current - (delta * scrollBar.scrollStep * 2)
            if new < min then new = min end
            if new > max then new = max end
            scrollBar:SetValue(new)
        end)

        -- Arrow flip functions (using icons.png)
        local function ArrowDown()
            arrow:SetTexture(RC.Icons.Texture)
            arrow:SetTexCoord(unpack(RC.Icons.ArrowDown))
        end
        local function ArrowUp()
            arrow:SetTexture(RC.Icons.Texture)
            arrow:SetTexCoord(unpack(RC.Icons.ArrowUp))
        end

        -- Store references on pullout for OnShow/OnHide
        pullout.ArrowDown = ArrowDown
        pullout.ArrowUp = ArrowUp

        scrollBar:SetScript("OnValueChanged", function(_, val)
            if scrollFrame and scrollFrame.SetVerticalScroll then
                scrollFrame:SetVerticalScroll(val)
            end
        end)
        scrollBar:SetValue(0)

        local widget = {
            frame     = frame,
            box       = box,
            label     = label,
            type      = "RC_Dropdown",
            text      = text,
            arrow     = arrow,
            pullout   = pullout,
            button    = button,
            content   = scrollChild,
            scrollFrame = scrollFrame,
            scrollBar   = scrollBar,
            itemFrames  = {},
            hovered = false,
        }

        local function GetDropdownOptionAccent()
            return RC:IsShadowsteelTheme() and RC.Config.SectionAccent or RC.Config.Selected
        end

        local function ApplyThemeVisual()
            local modern = RC:IsModernTheme()
            local borderAlpha = math.max(0.14, RC.Config.DropdownBorder.a or RC.Config.Border.a or 0)
            local borderR = RC.Config.DropdownBorder.r
            local borderG = RC.Config.DropdownBorder.g
            local borderB = RC.Config.DropdownBorder.b
            local closedBg = RC.Config.DropdownBg
            local openBg = RC.Config.ButtonBg
            local optionAccent = GetDropdownOptionAccent()
            box:SetHeight(modern and RC:GetThemeLayout("dropdownHeight", 30) or 26)
            label:ClearAllPoints()
            box:ClearAllPoints()
            if modern and not widget.compactLayout then
                if widget._rcSettingsGrid then
                    local labelWidth, controlX = GetSettingsGridSplit(frame, widget.width)
                    label:SetPoint("LEFT", frame, "LEFT", 14, 0)
                    label:SetPoint("RIGHT", frame, "LEFT", labelWidth - 8, 0)
                    box:SetPoint("LEFT", frame, "LEFT", controlX, 0)
                else
                    label:SetPoint("LEFT", frame, "LEFT", 14, 0)
                    label:SetPoint("RIGHT", frame, "CENTER", -8, 0)
                    box:SetPoint("LEFT", frame, "CENTER", 8, 0)
                end
                box:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
                box:SetHeight(RC:GetThemeLayout("dropdownHeight", 28))
            else
                box:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
                box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
                label:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 4)
                label:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", 0, 4)
            end
            pullout:SetWidth(math.max(box:GetWidth() or 200, 160))
            scrollChild:SetWidth(math.max((pullout:GetWidth() or 200) - 6, 154))

            if widget.hovered or pullout:IsShown() then
                box:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 0.86)
                box:SetBackdropBorderColor(
                    RC.Config.InputFocus.r,
                    RC.Config.InputFocus.g,
                    RC.Config.InputFocus.b,
                    math.max(0.42, RC.Config.InputFocus.a or borderAlpha)
                )
            else
                box:SetBackdropColor(closedBg.r, closedBg.g, closedBg.b, math.max(0.78, closedBg.a or 0.92))
                box:SetBackdropBorderColor(borderR, borderG, borderB, borderAlpha)
            end

            pullout:SetBackdropColor(
                openBg.r,
                openBg.g,
                openBg.b,
                math.max(0.94, openBg.a or 0.90)
            )
            pullout:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, 0.34)
            pulloutTop:SetColorTexture(
                RC.Config.InputFocus.r,
                RC.Config.InputFocus.g,
                RC.Config.InputFocus.b,
                0.18
            )
            label:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, math.max(0.96, RC.Config.Text.a or 1))
            label:SetAlpha(1)
            text:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, (widget.hovered or pullout:IsShown()) and 1 or 0.94)
            if widget.hovered or pullout:IsShown() then
                arrow:SetVertexColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
            else
                arrow:SetVertexColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 0.54)
            end
            scrollBar:SetWidth(RC:GetThemeLayout("scrollbarWidth", 4))
            ddScrollTrack:SetColorTexture(RC.Config.ScrollTrack.r, RC.Config.ScrollTrack.g, RC.Config.ScrollTrack.b, RC.Config.ScrollTrack.a or 0.08)
            if ddThumb then
                ddThumb:SetVertexColor(RC.Config.ScrollThumb.r, RC.Config.ScrollThumb.g, RC.Config.ScrollThumb.b, RC.Config.ScrollThumb.a or 0.56)
                ddThumb:SetSize(RC:GetThemeLayout("scrollbarWidth", 4), math.max(20, RC:GetThemeLayout("scrollbarThumbHeight", 36) - 12))
            end
            for _, item in ipairs(widget.itemFrames) do
                if item.hoverTex then
                    item.hoverTex:SetColorTexture(RC.Config.DropdownHover.r, RC.Config.DropdownHover.g, RC.Config.DropdownHover.b, RC:IsShadowsteelTheme() and 0.16 or 0.12)
                end
                if item.selectedTex then
                    item.selectedTex:SetColorTexture(RC.Config.DropdownSelected.r, RC.Config.DropdownSelected.g, RC.Config.DropdownSelected.b, RC:IsShadowsteelTheme() and 0.22 or 0.16)
                    item.selectedTex:SetShown(item._key == widget.value)
                end
                if item.selectedMarker then
                    item.selectedMarker:SetColorTexture(optionAccent.r, optionAccent.g, optionAccent.b, optionAccent.a or 1)
                    item.selectedMarker:SetShown(modern and item._key == widget.value)
                end
                if item.valText then
                    if item._key == widget.value then
                        item.valText:SetTextColor(RC.Config.TabSelectedText.r, RC.Config.TabSelectedText.g, RC.Config.TabSelectedText.b, 1)
                    else
                        item.valText:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 0.90)
                    end
                end
            end
        end

        pullout:HookScript("OnShow", ApplyThemeVisual)
        pullout:HookScript("OnHide", ApplyThemeVisual)

        -- Hover
        button:SetScript("OnEnter", function()
            widget.hovered = true
            arrow:SetVertexColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
            ApplyThemeVisual()
        end)
        button:SetScript("OnLeave", function()
            widget.hovered = false
            ApplyThemeVisual()
        end)

        button:SetScript("OnClick", function()
            if pullout:IsShown() then
                pullout:Hide()
            else
                ApplyThemeVisual()
                CloseAllDropdowns(pullout)
                RC.ActiveDropdowns[pullout] = true
                pullout:SetParent(UIParent)
                pullout:SetFrameStrata("TOOLTIP")
                pullout:SetFrameLevel(900)
                pullout:Raise()

                -- Smart positioning based on available screen space
                pullout:PositionSmart()

                -- Sort list keys
                local keys = {}
                if widget.order then
                    for _, key in ipairs(widget.order) do
                        if widget.list and widget.list[key] ~= nil then
                            table.insert(keys, key)
                        end
                    end
                else
                    for k, _ in pairs(widget.list or {}) do
                        table.insert(keys, k)
                    end
                    table.sort(keys, function(a, b)
                        local ta, tb = type(a), type(b)
                        if ta == tb then
                            if ta == "number" then
                                return a < b
                            end
                            return tostring(a) < tostring(b)
                        end
                        if ta == "number" then
                            return true
                        end
                        if tb == "number" then
                            return false
                        end
                        return tostring(a) < tostring(b)
                    end)
                end

                -- Hide old items
                for _, item in ipairs(widget.itemFrames) do
                    item:Hide()
                end

                local itemHeight = RC:IsModernTheme() and RC:GetThemeLayout("dropdownItemHeight", 28) or 22
                local y = RC:IsModernTheme() and -4 or -5
                local itemCount = 0
                local optionAccent = GetDropdownOptionAccent()
                for _, k in ipairs(keys) do
                    local v = widget.list[k]
                    itemCount = itemCount + 1

                    local item = widget.itemFrames[itemCount]
                    if not item then
                        item = CreateFrame("Button", nil, widget.content)
                        item:SetHeight(itemHeight)

                        -- Subtle hover highlight (no per-item border to keep it clean)
                        item.hoverTex = item:CreateTexture(nil, "BACKGROUND")
                        item.hoverTex:SetAllPoints()
                        item.hoverTex:SetColorTexture(RC.Config.DropdownHover.r, RC.Config.DropdownHover.g, RC.Config.DropdownHover.b, RC:IsShadowsteelTheme() and 0.16 or 0.12)
                        item.hoverTex:Hide()

                        item.selectedTex = item:CreateTexture(nil, "BACKGROUND", nil, -1)
                        item.selectedTex:SetAllPoints()
                        item.selectedTex:SetColorTexture(RC.Config.DropdownSelected.r, RC.Config.DropdownSelected.g, RC.Config.DropdownSelected.b, RC:IsShadowsteelTheme() and 0.22 or 0.16)
                        item.selectedTex:Hide()

                        item.selectedMarker = item:CreateTexture(nil, "ARTWORK")
                        item.selectedMarker:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 2)
                        item.selectedMarker:SetPoint("BOTTOMLEFT", item, "BOTTOMLEFT", 0, -2)
                        item.selectedMarker:SetWidth(2)
                        item.selectedMarker:SetColorTexture(optionAccent.r, optionAccent.g, optionAccent.b, optionAccent.a or 1)
                        item.selectedMarker:Hide()

                        local itemText = item:CreateFontString(nil, "OVERLAY")
                        RC:SetFont(itemText, 11, "OUTLINE")
                        itemText:SetPoint("LEFT",  item, "LEFT",  8, 0)
                        itemText:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                        itemText:SetJustifyH("LEFT")
                        itemText:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 0.90)
                        item.valText = itemText

                        table.insert(widget.itemFrames, item)
                    end

                    item:SetHeight(itemHeight)
                    item._key = k
                    item:SetPoint("TOPLEFT", 4, y)
                    item:SetPoint("RIGHT",   -4, 0)
                    item.valText:SetText(v)
                    item.hoverTex:Hide()
                    item.selectedTex:SetShown(k == widget.value)
                    item.selectedMarker:SetShown(RC:IsModernTheme() and k == widget.value)
                    item.valText:ClearAllPoints()
                    item.valText:SetPoint("LEFT", item, "LEFT", RC:IsModernTheme() and 12 or 8, 0)
                    item.valText:SetPoint("RIGHT", item, "RIGHT", -8, 0)

                    item:SetScript("OnEnter", function(self)
                        self.hoverTex:Show()
                        self.valText:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 0.96)
                    end)
                    item:SetScript("OnLeave", function(self)
                        self.hoverTex:Hide()
                        if self._key == widget.value then
                            self.valText:SetTextColor(RC.Config.TabSelectedText.r, RC.Config.TabSelectedText.g, RC.Config.TabSelectedText.b, 1)
                        else
                            self.valText:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 0.90)
                        end
                    end)

                    item:SetScript("OnClick", function()
                        widget.value = k
                        widget:Fire("OnValueChanged", k)
                        text:SetText(v)
                        pullout:Hide()
                    end)

                    item:Show()
                    y = y - itemHeight
                end

                local contentHeight = math.abs(y)
                local maxVisibleHeight = RC:IsModernTheme() and 196 or 160
                widget.content:SetHeight(contentHeight)

                if contentHeight > maxVisibleHeight then
                    pullout:SetHeight(maxVisibleHeight)
                    widget.scrollBar:Show()
                    local maxScroll = contentHeight - maxVisibleHeight + 8
                    widget.scrollBar:SetMinMaxValues(0, maxScroll)
                else
                    pullout:SetHeight(contentHeight + 8)
                    widget.scrollBar:Hide()
                    widget.scrollBar:SetValue(0)
                end

                pullout:SetWidth(math.max(box:GetWidth() or 160, 160))
                -- Content width: full pullout minus 6px for scrollbar gutter (always reserved for consistency)
                widget.content:SetWidth(pullout:GetWidth() - 8)

                ApplyThemeVisual()
                pullout:PositionSmart()
                pullout:Show()
            end
        end)

        function widget:OnAcquire()
            self._rcSettingsGrid = nil
            self:SetHeight(44)
            self:SetWidth(200)
            self.frame:Show()
        end

        function widget:OnRelease()
            self.frame:Hide()
            self.pullout:Hide()
        end

        function widget:SetList(l, order)
            self.list = l
            self.order = order
        end

        function widget:SetValue(val)
            self.value = val
            self.text:SetText(self.list and self.list[val] or val or L["Select..."])
        end

        function widget:SetLabel(txt)
            if self.label then
                self.label:SetText(txt)
            end
        end

        function widget:SetCompactLayout(compact)
            self.compactLayout = compact and true or false
            ApplyThemeVisual()
        end

        function widget:SetDisabled() end

        function widget:RefreshTheme()
            ApplyThemeVisual()
        end

        function widget:SetParent(parent)
            -- parent is an AceGUI widget, we need parent.frame
            local parentFrame = parent
            if parent and parent.frame then
                parentFrame = parent.frame
            end

            if parentFrame then
                self.frame:SetParent(parentFrame)
                self.frame:SetFrameStrata(parentFrame:GetFrameStrata())
                self.frame:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
                self.pullout:SetParent(UIParent)
                self.pullout:SetFrameStrata("TOOLTIP")
                self.pullout:SetFrameLevel(900)
            end
        end

        RC:RegisterThemeWidget(widget)
        ApplyThemeVisual()
        AceGUI:RegisterAsWidget(widget)
        return widget
    end
    AceGUI:RegisterWidgetType("RC_Dropdown", Constructor_Dropdown, 3)


    -- =========================================================================
    -- RC_ScrollFrame
    -- =========================================================================
    -- AceGUI's proven ScrollFrame container behavior with a completely custom,
    -- template-free scrollbar. Keeping AceGUI's container methods intact is
    -- critical: replacing AddChild/DoLayout was the cause of blank settings.
    local function Constructor_RCScrollFrame()
        local function ScrollbarWidth()
            return math.max(8, tonumber(RC:GetThemeLayout("settingsScrollbarWidth", 8)) or 8)
        end

        local function ScrollbarGutter()
            return math.max(ScrollbarWidth() + 6, tonumber(RC:GetThemeLayout("settingsScrollbarGutter", 44)) or 44)
        end

        local function FixScrollOnUpdate(scrollframe)
            scrollframe:SetScript("OnUpdate", nil)
            scrollframe.obj:FixScroll()
        end

        local methods = {
            OnAcquire = function(self)
                self:SetScroll(0)
                self.scrollframe:SetScript("OnUpdate", FixScrollOnUpdate)
            end,

            OnRelease = function(self)
                self.status = nil
                for key in pairs(self.localstatus) do
                    self.localstatus[key] = nil
                end
                self.localstatus.scrollvalue = 0
                self.scrollframe:SetPoint("BOTTOMRIGHT")
                self.scrollbar:Hide()
                self.scrollBarShown = nil
                self.content.height = nil
                self.content.width = nil
                self.content.original_width = nil
            end,

            SetScroll = function(self, value)
                local status = self.status or self.localstatus
                local viewHeight = self.scrollframe:GetHeight()
                local contentHeight = self.content:GetHeight()
                local offset

                if viewHeight > contentHeight then
                    offset = 0
                else
                    offset = math.floor((contentHeight - viewHeight) / 1000 * value)
                end
                self.content:ClearAllPoints()
                self.content:SetPoint("TOPLEFT", 0, offset)
                self.content:SetPoint("TOPRIGHT", 0, offset)
                status.offset = offset
                status.scrollvalue = value
            end,

            MoveScroll = function(self, value)
                local status = self.status or self.localstatus
                local viewHeight = self.scrollframe:GetHeight()
                local contentHeight = self.content:GetHeight()
                if self.scrollBarShown then
                    local difference = contentHeight - viewHeight
                    if difference <= 0 then return end
                    local step = 1000 / (difference / 45)
                    -- WoW mouse wheel: delta > 0 means wheel up, delta < 0 means wheel down.
                    -- Scroll value 0 is the top and 1000 is the bottom, so wheel down must increase it.
                    local nextValue = status.scrollvalue - ((value > 0 and 1 or -1) * step)
                    self.scrollbar:SetValue(math.min(math.max(nextValue, 0), 1000))
                end
            end,

            FixScroll = function(self)
                if self.updateLock then return end
                self.updateLock = true
                local status = self.status or self.localstatus
                local viewHeight = self.scrollframe:GetHeight()
                local contentHeight = self.content:GetHeight()
                local offset = status.offset or 0

                if contentHeight < viewHeight + 2 then
                    if self.scrollBarShown then
                        self.scrollBarShown = nil
                        self.scrollbar:Hide()
                        self.scrollbar:SetValue(0)
                        self.scrollframe:SetPoint("BOTTOMRIGHT")
                        -- The gutter stays reserved (see OnWidthSet), so rows
                        -- keep the same width whether or not the bar shows.
                    end
                else
                    if not self.scrollBarShown then
                        self.scrollBarShown = true
                        self.scrollbar:Show()
                        self.scrollframe:SetPoint("BOTTOMRIGHT")
                        -- Width is unchanged: the gutter is always reserved.
                    end
                    local value = offset / (contentHeight - viewHeight) * 1000
                    value = math.min(value, 1000)
                    self.scrollbar:SetValue(value)
                    self:SetScroll(value)
                    if value < 1000 then
                        self.content:ClearAllPoints()
                        self.content:SetPoint("TOPLEFT", 0, offset)
                        self.content:SetPoint("TOPRIGHT", 0, offset)
                        status.offset = offset
                    end
                end
                self.updateLock = nil
            end,

            LayoutFinished = function(self, _, height)
                self.content:SetHeight((height or 0) + 12)
                self:FixScroll()
                self.scrollframe:SetScript("OnUpdate", FixScrollOnUpdate)
            end,

            SetStatusTable = function(self, status)
                assert(type(status) == "table")
                self.status = status
                if not status.scrollvalue then
                    status.scrollvalue = 0
                end
            end,

            OnWidthSet = function(self, width)
                -- Always reserve the scrollbar gutter. Section rows compute their
                -- geometry once when added, so a gutter that appeared mid-build
                -- left earlier and later rows at different widths.
                self.content.width = width - ScrollbarGutter()
                self.content.original_width = width
            end,

            OnHeightSet = function(self, height)
                self.content.height = height
            end,

            RefreshTheme = function(self)
                local width = ScrollbarWidth()
                self.scrollbar:SetWidth(width)
                self.scrollTrack:SetColorTexture(RC.Config.ScrollTrack.r, RC.Config.ScrollTrack.g, RC.Config.ScrollTrack.b, RC.Config.ScrollTrack.a or 0.08)
                self.scrollThumb:SetVertexColor(RC.Config.ScrollThumb.r, RC.Config.ScrollThumb.g, RC.Config.ScrollThumb.b, RC.Config.ScrollThumb.a or 0.56)
                self.scrollThumb:SetSize(width, RC:GetThemeLayout("scrollbarThumbHeight", 36))
            end,
        }

        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetClipsChildren(true)

        local scrollframe = CreateFrame("ScrollFrame", nil, frame)
        scrollframe:SetPoint("TOPLEFT")
        scrollframe:SetPoint("BOTTOMRIGHT")
        scrollframe:EnableMouseWheel(true)
        scrollframe:SetClipsChildren(true)
        scrollframe:SetScript("OnMouseWheel", function(control, value)
            control.obj:MoveScroll(value)
        end)
        scrollframe:SetScript("OnSizeChanged", function(control)
            control:SetScript("OnUpdate", FixScrollOnUpdate)
        end)

        local scrollbar = CreateFrame("Slider", nil, scrollframe)
        scrollbar:SetOrientation("VERTICAL")
        scrollbar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -6)
        scrollbar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 6)
        scrollbar:SetMinMaxValues(0, 1000)
        scrollbar:SetValueStep(1)
        scrollbar:SetValue(0)
        scrollbar:SetWidth(ScrollbarWidth())
        scrollbar:Hide()

        local track = scrollbar:CreateTexture(nil, "BACKGROUND")
        track:SetAllPoints()
        track:SetColorTexture(RC.Config.ScrollTrack.r, RC.Config.ScrollTrack.g, RC.Config.ScrollTrack.b, RC.Config.ScrollTrack.a or 0.08)

        scrollbar:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
        local thumb = scrollbar:GetThumbTexture()
        thumb:SetVertexColor(RC.Config.ScrollThumb.r, RC.Config.ScrollThumb.g, RC.Config.ScrollThumb.b, RC.Config.ScrollThumb.a or 0.56)
        thumb:SetSize(ScrollbarWidth(), RC:GetThemeLayout("scrollbarThumbHeight", 36))
        scrollbar:SetScript("OnEnter", function()
            thumb:SetVertexColor(RC.Config.AccentHover.r, RC.Config.AccentHover.g, RC.Config.AccentHover.b, 0.82)
        end)
        scrollbar:SetScript("OnLeave", function()
            thumb:SetVertexColor(RC.Config.ScrollThumb.r, RC.Config.ScrollThumb.g, RC.Config.ScrollThumb.b, RC.Config.ScrollThumb.a or 0.56)
        end)

        local content = CreateFrame("Frame", nil, scrollframe)
        content:SetPoint("TOPLEFT")
        content:SetPoint("TOPRIGHT")
        content:SetHeight(400)
        scrollframe:SetScrollChild(content)

        local widget = {
            localstatus = { scrollvalue = 0 },
            scrollframe = scrollframe,
            scrollbar = scrollbar,
            scrollTrack = track,
            scrollThumb = thumb,
            content = content,
            frame = frame,
            type = "RC_ScrollFrame",
        }
        for method, implementation in pairs(methods) do
            widget[method] = implementation
        end
        scrollframe.obj = widget
        scrollbar.obj = widget
        scrollbar:SetScript("OnValueChanged", function(control, value)
            control.obj:SetScroll(value)
        end)

        RC:RegisterThemeWidget(widget)
        return AceGUI:RegisterAsContainer(widget)
    end
    AceGUI:RegisterWidgetType("RC_ScrollFrame", Constructor_RCScrollFrame, 3)

    -- =========================================================================
    -- RC_Header (section header with neutral separator)
    -- =========================================================================
    local function Constructor_Header()
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetHeight(32)

        -- Text label (white — the accent line below is the visual highlight)
        local text = frame:CreateFontString(nil, "OVERLAY")
        RC:SetFont(text, 12, "OUTLINE")
        text:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 8)
        text:SetTextColor(1, 1, 1, 1)

        -- Neutral separator; section emphasis comes from hierarchy, not accent stripes.
        local underline = frame:CreateTexture(nil, "ARTWORK")
        underline:SetHeight(1)
        underline:SetPoint("BOTTOMLEFT", 0, 2)
        underline:SetPoint("BOTTOMRIGHT", 0, 2)
        underline:SetColorTexture(RC.Config.SeparatorColor.r, RC.Config.SeparatorColor.g, RC.Config.SeparatorColor.b, 0.18)

        -- Subtle background fill
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(
            RC.Config.SurfaceBg.r,
            RC.Config.SurfaceBg.g,
            RC.Config.SurfaceBg.b,
            (RC.Config.SurfaceBg.a or 0.62) * 0.45
        )

        local widget = { frame = frame, type = "RC_Header", text = text, underline = underline, bg = bg }

        function widget:OnAcquire()
            self:SetHeight(32)
            self:SetWidth(200)
            self:RefreshTheme()
            self.frame:Show()
        end

        function widget:OnRelease()
            self.frame:Hide()
        end

        function widget:SetText(t)
            self.text:SetText(t)
        end

        function widget:RefreshTheme()
            self.text:SetTextColor(RC.Config.HeaderText.r, RC.Config.HeaderText.g, RC.Config.HeaderText.b, RC.Config.HeaderText.a or 1)
            self.underline:SetHeight(1)
            self.underline:SetColorTexture(
                RC.Config.SeparatorColor.r,
                RC.Config.SeparatorColor.g,
                RC.Config.SeparatorColor.b,
                RC:IsShadowsteelTheme() and 0.22 or 0.16
            )
            self.bg:SetColorTexture(
                RC.Config.SectionBg.r,
                RC.Config.SectionBg.g,
                RC.Config.SectionBg.b,
                (RC.Config.SectionBg.a or 0.62) * (RC:IsShadowsteelTheme() and 0.72 or 0.58)
            )
        end

        function widget:SetRelativeWidth(width)
            self.relWidth = width
            self.width = "relative"
        end

        function widget:SetFullWidth(isFull)
            if isFull then
                self:SetRelativeWidth(1)
            else
                self.relWidth = nil
                if type(self.width) ~= "number" then
                    self.width = nil
                end
            end
        end

        function widget:SetParent(parent)
            local parentFrame = parent
            if parent and parent.frame then
                parentFrame = parent.frame
            end

            if parentFrame then
                self.frame:SetParent(parentFrame)
                self.frame:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
            end
        end

        RC:RegisterThemeWidget(widget)
        widget:RefreshTheme()
        AceGUI:RegisterAsWidget(widget)
        return widget
    end
    AceGUI:RegisterWidgetType("RC_Header", Constructor_Header, 2)

    -- =========================================================================
    -- RC_Tab
    -- =========================================================================
    local function Constructor_Tab()
        local frame = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
        frame:EnableMouse(true)
        CreateBackdrop(frame)
        frame._rcInsetTop:Hide()
        frame._rcInsetBottom:Hide()

        local text = frame:CreateFontString(nil, "OVERLAY")
        RC:SetFont(text, 12, "OUTLINE")
        text:SetPoint("LEFT", 14, 0)
        text:SetPoint("RIGHT", -8, 0)
        text:SetJustifyH("LEFT")
        text:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)

        local navGlyphBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        navGlyphBox:SetSize(28, 28)
        navGlyphBox:SetPoint("LEFT", frame, "LEFT", 12, 0)
        CreateBackdrop(navGlyphBox)
        navGlyphBox:Hide()

        local navGlyph = navGlyphBox:CreateFontString(nil, "OVERLAY")
        RC:SetFont(navGlyph, 11, "OUTLINE")
        navGlyph:SetPoint("CENTER")
        navGlyph:SetTextColor(1, 1, 1, 0.75)

        local accentLine = frame:CreateTexture(nil, "OVERLAY")
        accentLine:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
        accentLine:Hide()

        local selectionGlow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
        selectionGlow:SetAllPoints()
        selectionGlow:Hide()

        local bottomLine = frame:CreateTexture(nil, "ARTWORK")
        bottomLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
        bottomLine:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
        bottomLine:SetHeight(1)
        bottomLine:SetColorTexture(RC.Config.SeparatorColor.r, RC.Config.SeparatorColor.g, RC.Config.SeparatorColor.b, 0.5)

        local selectionTop = frame:CreateTexture(nil, "ARTWORK")
        selectionTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        selectionTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        selectionTop:SetHeight(1)
        selectionTop:Hide()

        local selectionBottom = frame:CreateTexture(nil, "ARTWORK")
        selectionBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        selectionBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        selectionBottom:SetHeight(1)
        selectionBottom:Hide()

        local widget = {
            frame = frame,
            type = "RC_Tab",
            text = text,
            selected = false,
            hovered = false,
            tabStyle = "sidebar",
            accentLine = accentLine,
            selectionGlow = selectionGlow,
            bottomLine = bottomLine,
            navGlyphBox = navGlyphBox,
            navGlyph = navGlyph,
            selectionTop = selectionTop,
            selectionBottom = selectionBottom,
        }

        local function ConfigureAccent()
            accentLine:ClearAllPoints()
            if RC:IsModernTheme() and widget.tabStyle == "top" then
                local textWidth = text.GetStringWidth and text:GetStringWidth() or 36
                accentLine:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
                accentLine:SetWidth(math.max(34, math.ceil(textWidth + 14)))
                accentLine:SetHeight(2)
            else
                accentLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -1)
                accentLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 1)
                accentLine:SetWidth(2)
            end
        end

        local function ApplyVisual()
            ConfigureAccent()
            local activeColor = RC.Config.NavSelectedBorder
            local detailColor = activeColor
            local accentAlpha = widget.tabStyle == "top"
                and (RC:IsShadowsteelTheme() and 0.72 or 0.82)
                or (widget.selected and 0.92 or (widget.hovered and 0.36 or 0))
            accentLine:SetColorTexture(activeColor.r, activeColor.g, activeColor.b, accentAlpha)
            selectionTop:SetColorTexture(detailColor.r, detailColor.g, detailColor.b, RC:IsShadowsteelTheme() and 0.10 or 0.08)
            selectionBottom:SetColorTexture(detailColor.r, detailColor.g, detailColor.b, RC:IsShadowsteelTheme() and 0.08 or 0.04)

            local showGlyph = RC:IsModernTheme() and widget.tabStyle == "sidebar" and widget.navGlyphText
            navGlyphBox:SetShown(showGlyph and true or false)
            if showGlyph then
                local glyphSize = RC:GetThemeLayout("navGlyphSize", 26)
                navGlyphBox:SetSize(glyphSize, glyphSize)
                navGlyphBox:ClearAllPoints()
                navGlyphBox:SetPoint("LEFT", frame, "LEFT", RC:IsShadowsteelTheme() and 8 or 12, 0)
                RC:SetFont(text, RC:GetThemeLayout("navLabelFont", 12), "OUTLINE")
                RC:SetFont(navGlyph, RC:GetThemeLayout("navGlyphFont", 10), "OUTLINE")
                navGlyph:SetText(widget.navGlyphText)
                local glyphBg = widget.selected and RC.Config.NavSelectedBg or (widget.hovered and RC.Config.NavHover or RC.Config.ButtonBg)
                navGlyphBox:SetBackdropColor(glyphBg.r, glyphBg.g, glyphBg.b, glyphBg.a or 1)
                navGlyphBox:SetBackdropBorderColor(
                    (widget.selected or widget.hovered) and activeColor.r or RC.Config.Border.r,
                    (widget.selected or widget.hovered) and activeColor.g or RC.Config.Border.g,
                    (widget.selected or widget.hovered) and activeColor.b or RC.Config.Border.b,
                    widget.selected and (RC:IsShadowsteelTheme() and 0.42 or 0.62) or (widget.hovered and 0.26 or math.max(0.10, RC.Config.Border.a or 0))
                )
                navGlyph:SetTextColor(
                    widget.selected and RC.Config.NavSelectedText.r or RC.Config.NavText.r,
                    widget.selected and RC.Config.NavSelectedText.g or RC.Config.NavText.g,
                    widget.selected and RC.Config.NavSelectedText.b or RC.Config.NavText.b,
                    widget.selected and (RC.Config.NavSelectedText.a or 1) or 0.72
                )
                text:ClearAllPoints()
                text:SetPoint("LEFT", frame, "LEFT", RC:GetThemeLayout("navTextOffset", 48), 0)
                text:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
                text:SetJustifyH("LEFT")
            elseif widget.tabStyle == "sidebar" then
                RC:SetFont(text, RC:GetThemeLayout("navLabelFont", 12), "OUTLINE")
                text:ClearAllPoints()
                text:SetPoint("LEFT", frame, "LEFT", 20, 0)
                text:SetPoint("RIGHT", frame, "RIGHT", -12, 0)
                text:SetJustifyH("LEFT")
            else
                RC:SetFont(text, RC:GetThemeLayout("tabFont", 12), "OUTLINE")
                text:ClearAllPoints()
                text:SetPoint("LEFT", frame, "LEFT", 8, 0)
                text:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
                text:SetJustifyH("CENTER")
            end

            if RC:IsModernTheme() then
                local borderAlpha = 0
                frame:SetBackdropBorderColor(
                    widget.tabStyle == "sidebar" and RC.Config.NavSelectedBorder.r or RC.Config.SectionBorder.r,
                    widget.tabStyle == "sidebar" and RC.Config.NavSelectedBorder.g or RC.Config.SectionBorder.g,
                    widget.tabStyle == "sidebar" and RC.Config.NavSelectedBorder.b or RC.Config.SectionBorder.b,
                    borderAlpha
                )
                bottomLine:SetColorTexture(
                    RC.Config.SeparatorColor.r,
                    RC.Config.SeparatorColor.g,
                    RC.Config.SeparatorColor.b,
                    math.min(0.35, RC.Config.SeparatorColor.a or 0.25)
                )

                if widget.selected then
                    local selectedBg = widget.tabStyle == "sidebar" and RC.Config.NavSelectedBg or RC.Config.TabSelectedBg
                    local selectedAlpha = selectedBg.a or (widget.tabStyle == "sidebar" and 0.18 or 0.30)
                    if widget.tabStyle == "sidebar" and RC:IsShadowsteelTheme() then
                        selectedAlpha = math.min(selectedAlpha, 0.46)
                    elseif widget.tabStyle == "top" then
                        selectedAlpha = 0
                    end
                    frame:SetBackdropColor(
                        selectedBg.r,
                        selectedBg.g,
                        selectedBg.b,
                        selectedAlpha
                    )
                    text:SetTextColor(
                        widget.tabStyle == "sidebar" and RC.Config.NavSelectedText.r or RC.Config.TabSelectedText.r,
                        widget.tabStyle == "sidebar" and RC.Config.NavSelectedText.g or RC.Config.TabSelectedText.g,
                        widget.tabStyle == "sidebar" and RC.Config.NavSelectedText.b or RC.Config.TabSelectedText.b,
                        widget.tabStyle == "sidebar" and (RC.Config.NavSelectedText.a or 1) or (RC.Config.TabSelectedText.a or 1)
                    )
                    if widget.tabStyle == "sidebar" then
                        accentLine:Show()
                        selectionGlow:SetColorTexture(activeColor.r, activeColor.g, activeColor.b, 1)
                        if selectionGlow.SetGradient and CreateColor then
                            selectionGlow:SetGradient(
                                "HORIZONTAL",
                                CreateColor(activeColor.r, activeColor.g, activeColor.b, RC:IsShadowsteelTheme() and 0.035 or 0.08),
                                CreateColor(activeColor.r, activeColor.g, activeColor.b, 0)
                            )
                        else
                            selectionGlow:SetAlpha(RC:IsShadowsteelTheme() and 0.032 or 0.06)
                        end
                        selectionGlow:Show()
                        selectionTop:Hide()
                        selectionBottom:Hide()
                    else
                        accentLine:Show()
                        selectionGlow:Hide()
                        selectionTop:Hide()
                        selectionBottom:Hide()
                    end
                elseif widget.hovered then
                    local hoverBg = widget.tabStyle == "sidebar" and RC.Config.NavHover or RC.Config.TabHover
                    frame:SetBackdropColor(
                        hoverBg.r,
                        hoverBg.g,
                        hoverBg.b,
                        hoverBg.a or 0.08
                    )
                    text:SetTextColor(1, 1, 1, 0.86)
                    selectionGlow:Hide()
                    selectionTop:Hide()
                    selectionBottom:Hide()
                    if widget.tabStyle == "top" then
                        accentLine:SetColorTexture(activeColor.r, activeColor.g, activeColor.b, RC:IsShadowsteelTheme() and 0.24 or 0.22)
                        accentLine:Show()
                    else
                        accentLine:SetColorTexture(activeColor.r, activeColor.g, activeColor.b, 0.36)
                        accentLine:Show()
                    end
                else
                    local baseBg = widget.tabStyle == "sidebar" and RC.Config.NavBg or RC.Config.TabBg
                    frame:SetBackdropColor(baseBg.r, baseBg.g, baseBg.b, baseBg.a or 0)
                    if widget.tabStyle == "sidebar" then
                        text:SetTextColor(RC.Config.NavText.r, RC.Config.NavText.g, RC.Config.NavText.b, RC.Config.NavText.a or 0.56)
                    else
                        text:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 0.56)
                    end
                    selectionGlow:Hide()
                    selectionTop:Hide()
                    selectionBottom:Hide()
                    accentLine:Hide()
                end

                frame:SetBackdropBorderColor(0, 0, 0, 0)
                bottomLine:Hide()
            elseif widget.selected then
                frame:SetBackdropBorderColor(activeColor.r, activeColor.g, activeColor.b, 0.85)
                frame:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, RC.Config.ButtonHover.a or 1)
                text:SetTextColor(1, 1, 1)
                selectionGlow:Hide()
                selectionTop:Hide()
                selectionBottom:Hide()
                accentLine:Show()
                bottomLine:Show()
            elseif widget.hovered then
                frame:SetBackdropBorderColor(activeColor.r, activeColor.g, activeColor.b, 0.45)
                frame:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, RC.Config.ButtonHover.a or 1)
                text:SetTextColor(1, 1, 1)
                selectionGlow:Hide()
                selectionTop:Hide()
                selectionBottom:Hide()
                accentLine:Show()
                bottomLine:Show()
            else
                frame:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, RC.Config.Border.a or 1)
                frame:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
                text:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b)
                selectionGlow:Hide()
                selectionTop:Hide()
                selectionBottom:Hide()
                accentLine:Hide()
                bottomLine:Show()
            end
        end

        frame:SetScript("OnEnter", function()
            widget:SetHovered(true)
        end)

        frame:SetScript("OnLeave", function()
            widget:SetHovered(false)
        end)

        function widget:SetRelativeWidth(width)
            self.relWidth = width
            self.width = "relative"
        end

        function widget:SetFullWidth(isFull)
            if isFull then
                self:SetRelativeWidth(1)
            else
                self.relWidth = nil
                if type(self.width) ~= "number" then
                    self.width = nil
                end
            end
        end

        frame:SetScript("OnClick", function()
            widget:Fire("OnClick")
        end)

        function widget:OnAcquire()
            self.navGlyphText = nil
            self.hovered = false
            self:SetHeight(34)
            self:SetWidth(150)
            self:SetTabStyle("sidebar")
            self:SetSelected(false)
            self.frame:Show()
        end

        function widget:OnRelease()
            self.hovered = false
            self.selected = false
            self.frame:Hide()
        end

        function widget:SetText(t)
            self.text:SetText(t)
        end

        function widget:SetTabStyle(style)
            self.tabStyle = style == "top" and "top" or "sidebar"
            ApplyVisual()
        end

        function widget:SetNavGlyph(glyph)
            self.navGlyphText = glyph
            ApplyVisual()
        end

        function widget:SetSelected(state)
            self.selected = state
            if self.selected then
                self.hovered = false
            end
            ApplyVisual()
        end

        function widget:SetHovered(state)
            self.hovered = state and true or false
            ApplyVisual()
        end

        function widget:RefreshTheme()
            ApplyVisual()
        end

        function widget:SetParent(parent)
            -- parent is an AceGUI widget, we need parent.frame
            local parentFrame = parent
            if parent and parent.frame then
                parentFrame = parent.frame
            end

            if parentFrame then
                self.frame:SetParent(parentFrame)
                -- Set frame level to ensure proper rendering
                self.frame:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
            end
        end

        RC:RegisterThemeWidget(widget)
        AceGUI:RegisterAsWidget(widget)
        return widget
    end
    AceGUI:RegisterWidgetType("RC_Tab", Constructor_Tab, 2)

    -- =========================================================================
    -- RC_ColorSwatch (AceGUI Widget)
    -- =========================================================================
    local function Constructor_ColorSwatch()
        local frame = CreateFrame("Button", nil, UIParent)
        frame:Hide()
        frame:EnableMouse(true)

        -- Swatch Button
        local swatch = CreateFrame("Button", nil, frame, "BackdropTemplate")
        swatch:SetSize(18, 18)
        swatch:SetPoint("LEFT", 0, 0)
        CreateBackdrop(swatch)

        local colorTex = swatch:CreateTexture(nil, "OVERLAY")
        colorTex:SetPoint("TOPLEFT", 3, -3)
        colorTex:SetPoint("BOTTOMRIGHT", -3, 3)
        colorTex:SetColorTexture(1, 1, 1)

        -- Label
        local text = frame:CreateFontString(nil, "OVERLAY")
        RC:SetFont(text, 11, "OUTLINE")
        text:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
        text:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        text:SetJustifyH("LEFT")
        text:SetTextColor(1, 1, 1)

        local widget = {
            frame = frame,
            type = "RC_ColorSwatch",
            text = text,
            swatch = swatch,
            colorTex = colorTex,
            r = 1,
            g = 1,
            b = 1,
            hovered = false
        }

        local function OpenColorPicker()
            local r, g, b = widget.r, widget.g, widget.b
            RC:ShowColorPicker({
                r = r,
                g = g,
                b = b,
                onColorChanged = function(nr, ng, nb)
                    widget:SetColor(nr, ng, nb)
                    widget:Fire("OnValueChanged", nr, ng, nb)
                end,
                onCancel = function(nr, ng, nb)
                    widget:SetColor(nr, ng, nb)
                    widget:Fire("OnValueChanged", nr, ng, nb)
                end,
            })
        end

        local function SetHovered(hovered)
            widget.hovered = hovered and true or false
            widget:RefreshTheme()
        end

        frame:SetScript("OnEnter", function()
            SetHovered(true)
        end)
        frame:SetScript("OnLeave", function()
            SetHovered(false)
        end)
        frame:SetScript("OnMouseDown", function()
            swatch:SetBackdropColor(RC.Config.ButtonPressed.r, RC.Config.ButtonPressed.g, RC.Config.ButtonPressed.b, RC.Config.ButtonPressed.a or 1)
        end)
        frame:SetScript("OnMouseUp", function()
            widget:RefreshTheme()
        end)
        frame:SetScript("OnClick", OpenColorPicker)

        swatch:SetScript("OnEnter", function()
            SetHovered(true)
        end)
        swatch:SetScript("OnLeave", function()
            SetHovered(false)
        end)
        swatch:SetScript("OnMouseDown", function()
            swatch:SetBackdropColor(RC.Config.ButtonPressed.r, RC.Config.ButtonPressed.g, RC.Config.ButtonPressed.b, RC.Config.ButtonPressed.a or 1)
        end)
        swatch:SetScript("OnMouseUp", function()
            widget:RefreshTheme()
        end)
        swatch:SetScript("OnClick", OpenColorPicker)

        function widget:OnAcquire()
            self._rcSettingsGrid = nil
            self:SetHeight(24)
            self:SetWidth(200)
            self:SetColor(1, 1, 1)
            self:SetLabel("")
            self:RefreshTheme()
            self.frame:Show()
        end

        function widget:OnRelease()
            self.frame:Hide()
        end

        function widget:SetLabel(txt)
            self.text:SetText(txt)
        end

        function widget:SetColor(r, g, b)
            self.r, self.g, self.b = r, g, b
            self.colorTex:SetColorTexture(r or 1, g or 1, b or 1, 1)
        end

        function widget:RefreshTheme()
            local bg = self.hovered and RC.Config.ButtonHover or RC.Config.ButtonBg
            self.swatch:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
            if self.hovered then
                self.swatch:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, 0.72)
            else
                self.swatch:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.18, RC.Config.InputBorder.a or 0))
            end
            self.text:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
            self.swatch:ClearAllPoints()
            self.text:ClearAllPoints()
            self.colorTex:ClearAllPoints()
            self.colorTex:SetPoint("TOPLEFT", self.swatch, "TOPLEFT", 3, -3)
            self.colorTex:SetPoint("BOTTOMRIGHT", self.swatch, "BOTTOMRIGHT", -3, 3)
            if RC:IsModernTheme() then
                self.text:SetPoint("LEFT", self.frame, "LEFT", 14, 0)
                if self._rcSettingsGrid then
                    local labelWidth = GetSettingsGridSplit(self.frame, self.width)
                    self.text:SetPoint("RIGHT", self.frame, "LEFT", labelWidth - 8, 0)
                else
                    self.text:SetPoint("RIGHT", self.frame, "CENTER", -8, 0)
                end
                self.swatch:SetSize(50, 22)
                self.swatch:SetPoint("RIGHT", self.frame, "RIGHT", -14, 0)
            else
                self.swatch:SetSize(24, 18)
                self.swatch:SetPoint("LEFT", self.frame, "LEFT", 0, 0)
                self.text:SetPoint("LEFT", self.swatch, "RIGHT", 8, 0)
                self.text:SetPoint("RIGHT", self.frame, "RIGHT", -4, 0)
            end
        end

        function widget:SetParent(parent)
            -- parent is an AceGUI widget, we need parent.frame
            local parentFrame = parent
            if parent and parent.frame then
                parentFrame = parent.frame
            end

            if parentFrame then
                self.frame:SetParent(parentFrame)
                -- Set frame level to ensure proper rendering
                self.frame:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
            end
        end

        RC:RegisterThemeWidget(widget)
        AceGUI:RegisterAsWidget(widget)
        return widget
    end
    AceGUI:RegisterWidgetType("RC_ColorSwatch", Constructor_ColorSwatch, 3)
end

-- Register widgets immediately after Media.lua is loaded (after all functions are defined)
RC:RegisterCustomWidgets()
