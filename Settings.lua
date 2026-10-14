-- RaidControl settings window, opened with /rc, a right-click on the launcher tab, the Escape
-- menu button, or Options > AddOns > RaidControl. Built from RaidControl's own themed window
-- and widgets (Media.lua: CreatePanel, RC_Tab, RC_CheckBox, RC_Slider, RC_Dropdown, ...), so it
-- looks like the launcher. Rows read and write RC.db.profile directly; every change re-applies
-- the launcher, menu, action strip and tank assist.
local _, ns = ...
local RC = ns.RC
local L = RC.L
local AceGUI = LibStub("AceGUI-3.0")

local Settings = RC:NewModule("Settings")

local WINDOW_WIDTH, WINDOW_HEIGHT = 760, 580
local HEADER_HEIGHT = 46
local SIDEBAR_WIDTH = 176
local PAD = 12

local function Profile() return RC.db.profile end
local function Default(key) return RC.db.defaults.profile[key] end
local function Value(key)
    local v = Profile()[key]
    if v == nil then v = Default(key) end
    return v
end

local function Call(obj, fn, ...)
    if obj and type(obj[fn]) == "function" then
        local ok, err = pcall(obj[fn], obj, ...)
        if not ok then geterrorhandler()(err) end
    end
end

-- Re-applies everything the window can change (scales, visibility, buttons, theme).
local function Changed()
    local p = Profile()
    local legacy = p.launcherScale or p.scale or 1
    Call(RC, "ApplyTheme", p.theme or "Starforge", false)
    Call(RC, "ApplyTopBarScale", p.topBarScale or legacy)
    Call(RC, "ApplyMenuScale", p.menuScale or legacy)
    Call(RC, "ApplyInterfaceVisibility")
    Call(RC, "RefreshLayout")
    Call(RC, "RefreshTheme", false)
    Call(RC, "UpdateCycleKeybinds")
    local control = RC:GetModule("Control", true)
    Call(control, "RefreshButtonVisibility")
    Call(control, "RefreshModifierAttributes")
    Call(RC:GetModule("Markers", true), "RefreshModifierAttributes")
    local strip = RC:GetModule("ActionStrip", true)
    Call(strip, "RefreshButtonVisibility")
    Call(strip, "UpdateVisibility")
    Call(strip, "UpdateScale", p.actionStripScale or 1)
    Call(strip, "RefreshModifierAttributes")
    local tank = RC:GetModule("TankAssist", true)
    Call(tank, "ApplyEnabledState")
    Call(tank, "RefreshRuntimeSettings")
    Call(tank, "ApplyFrameSettings")
end

local function RunSlash(args)
    local handler = SlashCmdList and SlashCmdList["ACECONSOLE_RC"]
    if handler then handler(args) end
end

-- ---------------------------------------------------------------------------
-- Page data. Row kinds: toggle (default), slider, dropdown, color, input, button, text.
-- `invert` shows the opposite of a "hide..." setting; `restyle` rebuilds the window
-- after the change (theme and accent colour).
-- ---------------------------------------------------------------------------
local MODIFIERS = { SHIFT = L["Shift"], CTRL = L["Ctrl"], ALT = L["Alt"] }
local MODIFIER_ORDER = { "SHIFT", "CTRL", "ALT" }

local function ThemeValues()
    local values, order = {}, {}
    for _, key in ipairs(RC.ThemeOrder or {}) do
        local def = RC.ThemeDefinitions and RC.ThemeDefinitions[key]
        values[key] = def and def.label or key
        order[#order + 1] = key
    end
    return values, order
end

local PAGES = {
    { key = "launcher", label = L["Launcher"], sections = {
        { L["Launcher"], {
            { "hideTopBar", L["Show the launcher bar"], invert = true },
            { "hideLauncherWhenSolo", L["Hide it when I'm not in a group"] },
            { "hideBlizzardRaidControl", L["Hide Blizzard's raid manager"] },
            { "topBarScale", L["Launcher size"], kind = "slider", min = 0.5, max = 2, step = 0.05 },
            { "menuScale", L["Menu size"], kind = "slider", min = 0.5, max = 2, step = 0.05 },
        } },
        { L["Menu buttons"], {
            { "showReadyButton", L["Ready check"] },
            { "showPullButton", L["Pull timer"] },
            { "showConvertButton", L["Convert party / raid"] },
            { "showDifficultyButton", L["Difficulty"] },
            { "showInviteButton", L["Guild invite"] },
            { "showClearButton", L["Clear markers"] },
            { "showDisbandButton", L["Disband group"] },
            { "showScreenshotButton", L["Screenshot"] },
            { "hideRoles", L["Show tank / healer / DPS counts"], invert = true },
        } },
        { L["Pull timer"], {
            { "pullTimerDuration", L["Pull timer length (seconds)"], kind = "slider", min = 3, max = 30, step = 1 },
            { "pullTimerAddon", L["Send the pull timer through"], kind = "dropdown",
              values = { auto = L["Automatic"], bigwigs = "BigWigs", dbm = "DBM", ert = "MRT", none = L["Blizzard only"] },
              order = { "auto", "bigwigs", "dbm", "ert", "none" } },
        } },
    } },
    { key = "markers", label = L["Markers"], sections = {
        { L["Markers"], {
            { "hideMarkers", L["Show marker buttons"], invert = true },
            { "showDropdownMarkers", L["Markers in the drop-down menu"] },
            { "enableTargetMarkers", L["Click marks your target"] },
            { "enableWorldMarkers", L["Modifier-click places a world marker"] },
            { "worldMarkerModifier", L["World marker modifier"], kind = "dropdown", values = MODIFIERS, order = MODIFIER_ORDER },
            { "cycleMarkerModifier", L["Cycle keybind modifier"], kind = "dropdown", values = MODIFIERS, order = MODIFIER_ORDER },
        } },
    } },
    { key = "strip", label = L["Action strip"], sections = {
        { L["Action strip"], {
            { kind = "text", L["A slim row of raid buttons you can place anywhere. Move it with /rc layout."] },
            { "showActionStrip", L["Show the action strip"] },
            { "showActionStripMarkers", L["Include marker buttons"] },
            { "actionStripMouseover", L["Only show it on mouseover"] },
            { "actionStripScale", L["Size"], kind = "slider", min = 0.5, max = 2, step = 0.05 },
        } },
        { L["Buttons"], {
            { "actionStripShowReady", L["Ready check"] },
            { "actionStripShowPull", L["Pull timer"] },
            { "actionStripShowConvert", L["Convert party / raid"] },
            { "actionStripShowDifficulty", L["Difficulty"] },
            { "actionStripShowInvite", L["Guild invite"] },
            { "actionStripShowClearTarget", L["Clear target markers"] },
            { "actionStripShowClearWorld", L["Clear world markers"] },
            { "actionStripShowDisband", L["Disband group"] },
            { "actionStripShowScreenshot", L["Screenshot"] },
        } },
    } },
    { key = "tank", label = L["Tank assist"], sections = {
        { L["Tank assist"], {
            { kind = "text", L["Taunt swap and movement calls for tanks in boss fights. Move the alert and the bars with /rc layout."] },
            { "enableTankAssist", L["Enable tank assist"] },
            { "tankAssistTanksOnly", L["Only when I'm a tank"] },
            { "tankAssistEncounterOnly", L["Only during boss fights"] },
            { "tankAssistEnableDungeonBusters", L["Include dungeon tank busters"] },
            { "tankAssistCoTankName", L["Co-tank name (empty = automatic)"], kind = "input" },
        } },
        { L["Calls"], {
            { "tankAssistTauntEnabled", L["Taunt swaps"] },
            { "tankAssistMovementEnabled", L["Movement"] },
            { "tankAssistMovementLeadSeconds", L["Movement call this early (seconds)"], kind = "slider", min = 1, max = 15, step = 0.5 },
            { "tankAssistAlertCooldown", L["Don't repeat a call within (seconds)"], kind = "slider", min = 0, max = 20, step = 1 },
            { "tankAssistSoundEnabled", L["Play sounds"] },
            { "tankAssistTtsVolume", L["Voice volume"], kind = "slider", min = 0, max = 100, step = 5 },
        } },
        { L["Alert text (when it's time to act)"], {
            { "tankAssistShowVisual", L["Show the alert"] },
            { "tankAssistShowDetail", L["Show the small line under it"] },
            { "tankAssistAlertFontSize", L["Text size"], kind = "slider", min = 14, max = 56, step = 1 },
            { "tankAssistDetailFontSize", L["Small line size"], kind = "slider", min = 9, max = 24, step = 1 },
            { "tankAssistVisualDuration", L["Stays up for (seconds)"], kind = "slider", min = 1, max = 6, step = 0.5 },
            { "tankAssistDisplayStyle", L["Background"], kind = "dropdown",
              values = { text = L["None (text only)"], panel = L["Dark box with a thin border"] }, order = { "text", "panel" } },
        } },
        { L["Countdown bars"], {
            { "tankAssistShowTimerBars", L["Show countdown bars"] },
            { "tankAssistTimerTaunt", L["Bars for taunts"] },
            { "tankAssistTimerMovement", L["Bars for movement"] },
            { "tankAssistTimerHorizon", L["Show a bar this early (seconds)"], kind = "slider", min = 5, max = 120, step = 5 },
            { "tankAssistTimerMaxBars", L["Most bars at once"], kind = "slider", min = 1, max = 6, step = 1 },
            { "tankAssistTimerWidth", L["Bar width"], kind = "slider", min = 160, max = 700, step = 10 },
            { "tankAssistTimerHeight", L["Bar height"], kind = "slider", min = 14, max = 40, step = 1 },
            { "tankAssistTimerGrowth", L["New bars go"], kind = "dropdown",
              values = { DOWN = L["Below"], UP = L["Above"] }, order = { "DOWN", "UP" } },
        } },
        { L["Size and colours"], {
            { "tankAssistFrameScale", L["Overall size"], kind = "slider", min = 0.5, max = 2, step = 0.05 },
            { "tankAssistTauntColor", L["Taunt colour"], kind = "color" },
            { "tankAssistMovementColor", L["Movement colour"], kind = "color" },
            { kind = "button", L["Show a preview"], func = function()
                local tank = RC:GetModule("TankAssist", true)
                if tank and tank.PreviewLayout then tank:PreviewLayout(false) end
            end },
        } },
    } },
    { key = "look", label = L["Look"], sections = {
        { L["Look"], {
            { "theme", L["Theme"], kind = "dropdown", values = ThemeValues, restyle = true },
            { "useClassColor", L["Use my class colour as the accent"], restyle = true },
            { "accentColor", L["Accent colour"], kind = "color", restyle = true },
        } },
        { L["Position"], {
            { kind = "button", L["Move frames"], func = function() RunSlash("layout") end },
            { kind = "button", L["Reset launcher"], func = function() RunSlash("reset") end },
            { kind = "button", L["Reload UI"], func = ReloadUI },
            { kind = "text", L["Most changes show right away; a few need a /reload."] },
        } },
    } },
}

-- ---------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------
-- Sliders fire on every drag step; re-apply once things settle instead of on every tick.
local pending, pendingRestyle = false, false
local function AfterSet(row)
    pendingRestyle = pendingRestyle or row.restyle
    if pending then return end
    pending = true
    C_Timer.After(0.15, function()
        pending = false
        Changed()
        if pendingRestyle then
            pendingRestyle = false
            Settings:Restyle()
        end
    end)
end

local function BuildRow(container, row)
    local kind = row.kind or "toggle"
    local key, label = row[1], row[2]
    local widget

    if kind == "text" then
        widget = AceGUI:Create("Label")
        widget:SetText(row[1])
        widget:SetFullWidth(true)
        if widget.label then
            RC:SetFont(widget.label, 11, "")
            widget.label:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 1)
        end
    elseif kind == "button" then
        widget = AceGUI:Create("RC_Button")
        widget:SetText(row[1])
        widget:SetRelativeWidth(0.32)
        widget:SetCallback("OnClick", function() row.func() end)
    elseif kind == "toggle" then
        widget = AceGUI:Create("RC_CheckBox")
        widget:SetLabel(label)
        widget:SetRelativeWidth(0.5)
        local v = Value(key) and true or false
        if row.invert then v = not v end
        widget:SetValue(v)
        widget:SetCallback("OnValueChanged", function(_, _, value)
            value = value and true or false
            if row.invert then value = not value end
            Profile()[key] = value
            AfterSet(row)
        end)
    elseif kind == "slider" then
        widget = AceGUI:Create("RC_Slider")
        widget:SetLabel(label)
        widget:SetSliderValues(row.min, row.max, row.step)
        widget:SetValue(tonumber(Value(key)) or row.min)
        widget:SetRelativeWidth(0.5)
        widget:SetCallback("OnValueChanged", function(_, _, value)
            Profile()[key] = value
            AfterSet(row)
        end)
    elseif kind == "dropdown" then
        widget = AceGUI:Create("RC_Dropdown")
        widget:SetLabel(label)
        local values, order = row.values, row.order
        if type(values) == "function" then values, order = values() end
        widget:SetList(values, order)
        widget:SetValue(Value(key))
        widget:SetRelativeWidth(0.5)
        widget:SetCallback("OnValueChanged", function(_, _, value)
            Profile()[key] = value
            AfterSet(row)
        end)
    elseif kind == "color" then
        widget = AceGUI:Create("RC_ColorSwatch")
        widget:SetLabel(label)
        local c = Value(key) or {}
        widget:SetColor(c.r or 1, c.g or 1, c.b or 1)
        widget:SetRelativeWidth(0.5)
        widget:SetCallback("OnValueChanged", function(_, _, r, g, b)
            Profile()[key] = { r = r, g = g, b = b, a = 1 }
            AfterSet(row)
        end)
    elseif kind == "input" then
        widget = AceGUI:Create("RC_EditBox")
        widget:SetLabel(label)
        widget:SetText(tostring(Value(key) or ""))
        widget:SetRelativeWidth(0.5)
        widget:SetCallback("OnEnterPressed", function(_, _, text)
            Profile()[key] = strtrim(text or "")
            AfterSet(row)
        end)
    end
    if widget then container:AddChild(widget) end
end

local function Spacer(container, height)
    local gap = AceGUI:Create("SimpleGroup")
    gap:SetFullWidth(true)
    gap:SetHeight(height)
    container:AddChild(gap)
end

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------
function Settings:CreateWindow()
    if self.frame then return self.frame end

    local frame = RC:CreatePanel("RaidControlSettingsFrame", UIParent, WINDOW_WIDTH, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:Hide()
    self.frame = frame

    local header = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER_HEIGHT)
    RC:SkinFrame(header)
    RC:ApplyThemedHeader(header)
    header:EnableMouse(false)
    self.header = header

    local title = header:CreateFontString(nil, "OVERLAY")
    RC:SetFont(title, 16, "OUTLINE")
    title:SetPoint("LEFT", PAD + 4, 0)
    title:SetText("RaidControl")
    RC:SetTextColor(title, "title")
    self.title = title

    local version = header:CreateFontString(nil, "OVERLAY")
    RC:SetFont(version, 10, "")
    version:SetPoint("LEFT", title, "RIGHT", 8, -1)
    version:SetText(RC.version and ("v" .. RC.version) or "")
    self.versionText = version

    local close = RC:CreateCloseButton(header, 22)
    close:SetPoint("RIGHT", -PAD, 0)
    close:SetScript("OnClick", function() frame:Hide() end)

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR_WIDTH)
    RC:SkinFrame(sidebar)
    RC:ApplyThemedSidebar(sidebar)
    self.sidebar = sidebar

    self.tabs = {}
    for i, page in ipairs(PAGES) do
        local tab = AceGUI:Create("RC_Tab")
        tab:SetTabStyle("sidebar")
        tab:SetText(page.label)
        tab.frame:SetParent(sidebar)
        tab.frame:ClearAllPoints()
        tab.frame:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -10 - (i - 1) * 38)
        tab:SetWidth(SIDEBAR_WIDTH - 16)
        tab:SetHeight(34)
        tab.frame:Show()
        tab:SetCallback("OnClick", function() Settings:SelectPage(page.key) end)
        self.tabs[page.key] = tab
    end

    local content = AceGUI:Create("RC_ScrollFrame")
    content:SetLayout("Flow")
    content.frame:SetParent(frame)
    content.frame:ClearAllPoints()
    content.frame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", PAD, -PAD)
    content.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    content:SetWidth(WINDOW_WIDTH - SIDEBAR_WIDTH - PAD * 2 - 2)
    content:SetHeight(WINDOW_HEIGHT - HEADER_HEIGHT - PAD * 2 - 2)
    content.frame:Show()
    self.content = content

    frame:HookScript("OnHide", function()
        local tank = RC:GetModule("TankAssist", true)
        if tank and tank._tankTimerPreviewActive and tank.HidePreview then tank:HidePreview() end
    end)
    return frame
end

function Settings:SelectPage(key)
    local page
    for _, p in ipairs(PAGES) do
        if p.key == key then page = p end
    end
    page = page or PAGES[1]
    self.selected = page.key
    for k, tab in pairs(self.tabs) do tab:SetSelected(k == page.key) end

    local content = self.content
    content:ReleaseChildren()
    for i, section in ipairs(page.sections) do
        if i > 1 then Spacer(content, 10) end
        local heading = AceGUI:Create("RC_Header")
        heading:SetText(section[1])
        heading:SetFullWidth(true)
        content:AddChild(heading)
        for _, row in ipairs(section[2]) do BuildRow(content, row) end
    end
    content:DoLayout()
    if content.SetScroll then content:SetScroll(0) end
end

-- Theme or accent changed: recolour the window and rebuild the page so every widget picks
-- up the new colours.
function Settings:Restyle()
    if not self.frame then return end
    RC:ApplyThemedWindow(self.frame, "window")
    RC:ApplyThemedHeader(self.header)
    RC:ApplyThemedSidebar(self.sidebar)
    RC:SetTextColor(self.title, "title")
    for _, tab in pairs(self.tabs) do tab:RefreshTheme() end
    if self.content.RefreshTheme then self.content:RefreshTheme() end
    if self.frame:IsShown() then self:SelectPage(self.selected) end
end

function Settings:Open(pageKey)
    if InCombatLockdown and InCombatLockdown() then
        RC:Print(L["RaidControl settings are unavailable during combat."])
        return false
    end
    local frame = self:CreateWindow()
    if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
    frame:Show()
    frame:Raise()
    self:SelectPage(pageKey or self.selected or "launcher")
    return true
end

function Settings:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
        return false
    end
    return self:Open()
end

-- Called by LayoutMode when edit mode turns on or off.
function Settings:RefreshLayoutModeControls() end
function Settings:SelectTab(key) if self.frame and self.frame:IsShown() then self:SelectPage(key) end end

-- Options > AddOns > RaidControl: a small page with a button that opens the window.
function Settings:OnInitialize()
    if not (Settings and _G.Settings and _G.Settings.RegisterCanvasLayoutCategory) then return end
    local panel = CreateFrame("Frame")
    panel:Hide()
    local text = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetText("RaidControl")
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(200, 26)
    open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
    open:SetText(L["Open settings"])
    open:SetScript("OnClick", function() Settings:Open() end)
    local ok, category = pcall(_G.Settings.RegisterCanvasLayoutCategory, panel, "RaidControl")
    if ok and category then
        pcall(_G.Settings.RegisterAddOnCategory, category)
    end
end
