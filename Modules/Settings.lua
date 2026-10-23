local _, ns = ...
local RC = ns.RC
---@class Settings : AceModule
---@field frame Frame
---@field tabs table<string, any>
---@field selectedTab string
---@field sidebarContainer any
---@field contentContainer any
---@field scroll any
local Settings = RC:NewModule("Settings")
local AceGUI = LibStub("AceGUI-3.0")
local L = RC.L

-- AceGUI is dynamic; LuaLS does not know our custom widget fields.
---@diagnostic disable: undefined-field, invisible, param-type-mismatch

local NAV_TABS = {
    { key = "interface", label = L["Interface"], glyph = "UI", description = L["Visibility, dropdown controls, and the action strip"] },
    -- Tank has its own top tab (Workspace "tank"), so it stays out of the sidebar.
    { key = "tank", label = L["Tank"], glyph = "TK", description = L["Personal warnings, upcoming mechanics, sounds, and boss rules"], hidden = true },
    { key = "ready", label = L["Ready Check"], glyph = "RC", description = L["Ready responses, preparation issues and consumables in one view."] },
    { key = "screenshot", label = L["Screenshots"], glyph = "SS", description = L["Capture quality, format, render scale, and resolution"] },
    { key = "appearance", label = L["Look & Feel"], glyph = "AP", description = L["Theme, surfaces, fonts, scaling, and profiles"] },
}

local THEME_PRESETS = {
    {
        key = "Shadowsteel",
        label = L["Shadowsteel"],
        description = L["Compact charcoal panels, black borders, blue values, and restrained selected states."],
    },
    {
        key = "Starforge",
        label = L["Starforge"],
        description = L["Premium dark surfaces, soft separators, and restrained teal polish."],
    },
}

local function ApplyThemePreset(preset)
    if not preset or not RC.ApplyThemePreset then
        return
    end
    RC:ApplyThemePreset(preset.key, true)
end

-- =============================================================================
-- UI HELPERS
-- =============================================================================

local function GetSettingsV2()
    return RC.SettingsV2
end

local function AddSpacer(container, height)
    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    local resolvedHeight = height or 12
    if RC:IsModernTheme() then
        resolvedHeight = math.min(resolvedHeight, 4)
    end
    spacer:SetHeight(resolvedHeight)
    container:AddChild(spacer)
    return spacer
end

-- Every settings control is built by the SettingsV2 widget system, which the
-- TOC loads before this file. These locals keep the page builders short.
local SettingsV2 = RC.SettingsV2
local Widgets = SettingsV2.Widgets

local function AddSection(container, title, description)
    return SettingsV2.Sections:CreateSection(container, title, description)
end

local function AddCheckbox(container, label, getValue, setValue, onChanged)
    return Widgets:AddCheckbox(container, label, getValue, setValue, onChanged)
end

local function AddButton(container, text, onClick, isDanger)
    return Widgets:AddButton(container, text, onClick, isDanger)
end

local function AddActionToolbar(container, actions, options)
    return Widgets:AddActionToolbar(container, actions, options)
end

local function AddToggleActionRow(container, label, getValue, setValue, onChanged, actions)
    return Widgets:AddToggleActionRow(container, label, getValue, setValue, onChanged, actions)
end

local function AddSlider(container, label, minValue, maxValue, stepValue, getValue, setValue, onMouseUp, deferUntilMouseUp)
    return Widgets:AddSlider(container, label, minValue, maxValue, stepValue, getValue, setValue, onMouseUp, deferUntilMouseUp)
end

local function AddPercentSlider(container, label, minPercent, maxPercent, stepPercent, getPercent, setPercent, onApplied)
    return Widgets:AddPercentSlider(container, label, minPercent, maxPercent, stepPercent, getPercent, setPercent, onApplied)
end

-- Like AddPercentSlider, but applies the value while the slider is dragged.
local function AddLivePercentSlider(container, label, minPercent, maxPercent, stepPercent, getPercent, setPercent, onApplied)
    return AddSlider(
        container,
        label,
        minPercent,
        maxPercent,
        stepPercent,
        function()
            return math.floor(((getPercent and getPercent()) or minPercent) + 0.5)
        end,
        function(value)
            if setPercent then
                setPercent(value)
            end
            if onApplied then
                onApplied(value)
            end
        end,
        nil,
        false
    )
end

local function AddDropdown(container, label, list, getValue, setValue, onChanged, order)
    return Widgets:AddDropdown(container, label, list, getValue, setValue, onChanged, order)
end

local function AddSoundDropdown(container, label, list, getValue, setValue, onChanged, order)
    return Widgets:AddSearchableDropdown(container, label, list, getValue, setValue, onChanged, order, L["Search sounds..."])
end

local function AddEditBox(container, label, getValue, setValue, onEnterPressed)
    return Widgets:AddEditBox(container, label, getValue, setValue, onEnterPressed)
end

local function AddColorSwatch(container, label, getRGB, setRGB)
    return Widgets:AddColorSwatch(container, label, getRGB, setRGB)
end

local function AddErrorLabel(container, text)
    return Widgets:AddErrorLabel(container, text)
end

local PROFILE_TRANSFER_MAGIC = "RAIDCONTROL_PROFILE_V1:"
local PROFILE_TRANSFER_SCHEMA = 1
local IMPORTABLE_PROFILE_KEYS = {}

local function AllowProfileKeys(...)
    for i = 1, select("#", ...) do
        IMPORTABLE_PROFILE_KEYS[select(i, ...)] = true
    end
end

AllowProfileKeys(
    "minimap", "pos", "alpha", "scale", "launcherScale", "topBarScale", "menuScale", "fontName", "workspaceScale", "workspacePos", "settingsScale", "raidSplitPos", "theme",
    "titleTextColor", "buttonTextColor", "generalTextColor", "borderColor", "backgroundColor",
    "headerColor", "surfaceColor", "controlColor", "accentColor", "useClassColor",
    "hideTopBar", "hideMenu", "hideLauncherWhenSolo", "hideBlizzardRaidControl", "lockFrames"
)

AllowProfileKeys(
    "pullTimerDuration", "pullTimerAddon", "hideMarkers", "showDropdownMarkers",
    "showActionStripMarkers", "hideRoles", "enableTargetMarkers", "enableWorldMarkers",
    "enableShiftWorldMarkers", "worldMarkerModifier", "showPullButton", "showReadyButton",
    "showConvertButton", "showDifficultyButton", "showInviteButton", "showClearButton",
    "showDisbandButton", "showScreenshotButton"
)

AllowProfileKeys(
    "showActionStrip", "actionStripPos", "actionStripShowReady", "actionStripShowPull",
    "actionStripShowConvert", "actionStripShowDifficulty", "actionStripShowInvite",
    "actionStripShowClearTarget", "actionStripShowClearWorld", "actionStripShowDisband",
    "actionStripShowScreenshot", "actionStripLayout",
    "actionStripMarkerPosition", "actionStripScale", "actionStripButtonWidth",
    "actionStripButtonHeight", "actionStripMarkerSize", "actionStripMouseover", "lockActionStrip"
)

AllowProfileKeys(
    "screenshotRenderScale", "screenshotSizePreset", "screenshotSizeOverride",
    "screenshotFormat", "screenshotQuality", "screenshotApplyMaxGraphics",
    "screenshotHideUI", "screenshotDelay", "screenshotConfirmHighQuality"
)

AllowProfileKeys(
    "raidSplitScale", "bossNotesManagerScale", "raidSplitTooltipName", "raidSplitTooltipLevel", "raidSplitTooltipRole",
    "raidSplitTooltipSpec", "smartSplitMonk", "smartSplitDH", "smartSplitHealers",
    "smartSplitTanks", "smartSplitBalanceDPS", "smartSplitKeepSelfG1",
    "smartSplitTwoWayOddEven", "raidSplitGuildRankVisibility", "savedLayouts",
    "bossNotesViewer"
)

AllowProfileKeys(
    "enableAutoAssist", "autoAssistOfficers", "autoAssistMinRank", "autoAssistRankName",
    "autoAssistList", "enableAutoInvite", "autoInviteKeyword",
    "inviteRestriction", "autoConvertKeywordInvites"
)

AllowProfileKeys(
    "enableCombatLogger", "combatLogPrompt", "combatLogDecisions", "logRaid", "logParty",
    "logArena", "logBG", "enableAutoRepair", "useGuildRepair", "enableAutoSellJunk",
    "enableSynergyAnalyzer", "enableKeySync"
)

AllowProfileKeys(
    "enableRaidLeadTools", "enableBattleResTracker", "showBattleResFrame", "battleResShowIcon",
    "battleResShowLabel", "battleResShowCount", "battleResShowMax", "battleResShowTimer",
    "battleResTimerFormat", "battleResShowCooldownSwipe", "battleResShowRecent",
    "battleResRecentCount", "battleResRecentDuration", "battleResLabel", "battleResIcon",
    "battleResIconSize", "battleResFontSize", "battleResTimerFontSize", "battleResScale",
    "battleResAlpha", "battleResPos", "battleResStyle", "battleResWidth", "battleResPadding",
    "battleResGap", "battleResBackgroundAlpha", "battleResBorderAlpha",
    "battleResShowRechargeBar", "battleResRechargeBarHeight", "battleResReadyColor",
    "battleResRechargeColor", "battleResEmptyColor", "battleResTimerColor"
)

AllowProfileKeys(
    "showHealerManaFrame", "healerManaVisibility", "healerManaEnableInRaid", "healerManaEnableInDungeons",
    "healerManaOnlyIfPlayerIsHealer", "healerManaMaxHealers", "healerManaScale",
    "healerManaAlpha", "healerManaNameFontSize", "healerManaManaFontSize", "healerManaFontSize",
    "healerManaLowThreshold", "healerManaShowSolo", "healerManaShowTitle",
    "healerManaShowBackground", "healerManaShowBars", "healerManaShowStateTags",
    "healerManaShowDrinking", "healerManaStatusSound",
    "healerManaClassColorNames", "healerManaShowSpecIcon", "healerManaWidth",
    "healerManaFrameWidth", "healerManaIconSize", "healerManaRowSpacing",
    "healerManaGrowDirection", "healerManaNameYOffset", "healerManaManaYOffset",
    "healerManaManaColor", "healerManaUpdateInterval", "healerManaUseFrameFallback",
    "healerManaPos", "healerManaStyle", "healerManaTitle", "healerManaPadding",
    "healerManaBackgroundAlpha", "healerManaBorderAlpha", "healerManaRowAlpha",
    "healerManaBarAlpha", "healerManaBarHeight", "healerManaLowColor",
    "healerManaDrinkingColor", "healerManaAvoidTopUI"
)

AllowProfileKeys(
    "enableWhoPulled", "whoPulledChatPrint", "enableRaidNotes", "raidNoteText",
    "raidNoteChannel", "enableDurabilityComm", "durabilityReadyCheckRequest",
    "durabilityWarnThreshold"
)

AllowProfileKeys(
    "enableNoteReminders", "noteRemindersAutoLoad", "noteRemindersUsePersonal",
    "noteRemindersShowAllShared", "noteRemindersShowBars", "noteRemindersShowIcons",
    "noteRemindersShowNameplates", "noteRemindersLocked", "nsrtShareOnReadyCheck",
    "noteReminderTTS", "noteReminderSound", "noteReminderSoundChannel",
    "noteReminderTtsVolume", "noteReminderTtsVoiceID", "noteReminderLeadTime",
    "noteReminderMaxVisible", "noteReminderScale", "noteReminderWidth",
    "noteReminderRowHeight", "noteReminderIconSize", "noteReminderAlpha",
    "noteReminderBackgroundAlpha", "noteReminderPos", "noteReminderNameplateSize",
    "noteReminderNameplateOffsetX", "noteReminderNameplateOffsetY",
    "noteReminderNameplateShowLabel"
)

AllowProfileKeys(
    "enableTankAssist", "tankAssistCoTankName", "tankAssistSound", "tankAssistSoundChannel",
    "tankAssistCustomSoundFile", "tankAssistTtsVolume", "tankAssistTtsVoiceID",
    "tankAssistAlertIcon", "tankAssistSelectedBoss", "tankAssistBossOverrides",
    "tankAssistAlertCooldown", "tankAssistDefensiveLeadSeconds", "tankAssistMovementLeadSeconds", "tankAssistEnableDungeonBusters",
    "tankAssistVisualDuration", "tankAssistShowVisual",
    "tankAssistShowStatus", "tankAssistFramesLocked", "tankAssistFrameScale",
    "tankAssistFrameAlpha", "tankAssistAlertPos", "tankAssistStatusPos",
    "tankAssistTanksOnly", "tankAssistEncounterOnly", "tankAssistUseAuraRules",
    "tankAssistUseCastRules", "tankAssistSmartPolarity", "tankAssistAnnounceRule",
    "tankAssistSoundEnabled", "tankAssistDisplayStyle", "tankAssistAlertWidth",
    "tankAssistAlertFontSize", "tankAssistDetailFontSize", "tankAssistShowDetail",
    "tankAssistShowIcon", "tankAssistShowTimer", "tankAssistTextAlign", "tankAssistBackgroundAlpha",
    "tankAssistTauntColor", "tankAssistDefensiveColor", "tankAssistMovementColor",
    "tankAssistShowTimerBars", "tankAssistTimerWidth", "tankAssistTimerHeight",
    "tankAssistTimerFontSize", "tankAssistTimerMaxBars", "tankAssistTimerHorizon",
    "tankAssistTimerGrowth", "tankAssistTimerSpacing", "tankAssistTimerBackgroundAlpha",
    "tankAssistTimerShowIcon", "tankAssistTimerShowLabel", "tankAssistTimerShowSeconds",
    "tankAssistTimerTaunt", "tankAssistTimerDefensive", "tankAssistTimerMovement", "tankAssistTimerPos",
    "tankAssistTauntEnabled", "tankAssistDefensiveEnabled", "tankAssistMovementEnabled",
    "tankAssistTauntSound", "tankAssistDefensiveSound", "tankAssistMovementSound",
    "tankAssistTauntCustomSoundFile", "tankAssistDefensiveCustomSoundFile", "tankAssistMovementCustomSoundFile",
    "tankAssistTauntSoundChannel", "tankAssistDefensiveSoundChannel", "tankAssistMovementSoundChannel",
    "tankAssistTauntCountdownEnabled", "tankAssistDefensiveCountdownEnabled", "tankAssistMovementCountdownEnabled",
    "tankAssistTauntCountdownSeconds", "tankAssistDefensiveCountdownSeconds", "tankAssistMovementCountdownSeconds"
)

AllowProfileKeys(
    "autoMarkTanks", "autoMarkTanksIcon", "autoMarkHealers", "autoMarkHealersIcon",
    "autoMarkRolesDungeonOnly", "autoMarkRoleButtonScale",
    "autoMarkRoleButtonPos",
    "cycleMarkerModifier", "enableConsumableChecker", "whisperSlackers",
    "reportToChat", "enableReadyTracker", "announceReadySlackers", "useCustomReadyCheck",
    "readyTrackerMissingOnly", "readyTrackerWhisperMissing", "readyTrackerScale",
    "readyTrackerAlpha", "readyTrackerAutoCloseSeconds", "readyTrackerPos",
    "guildInviteRankVisibility"
)

local function CopyPlainTable(source, seen)
    if type(source) ~= "table" then
        return source
    end
    seen = seen or {}
    if seen[source] then
        return seen[source]
    end
    local copy = {}
    seen[source] = copy
    for key, value in pairs(source) do
        if type(value) ~= "function" and type(value) ~= "userdata" and type(value) ~= "thread" then
            copy[CopyPlainTable(key, seen)] = CopyPlainTable(value, seen)
        end
    end
    return copy
end

local function TrimProfileTransferText(text)
    if type(text) ~= "string" then
        return ""
    end
    if strtrim then
        return strtrim(text)
    end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function GetRaidControlVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata("Raidcontrol", "Version") or "unknown"
    end
    if GetAddOnMetadata then
        return GetAddOnMetadata("Raidcontrol", "Version") or "unknown"
    end
    return "unknown"
end

local function SafeCopyProfileValue(value, seen)
    local valueType = type(value)
    if valueType == "function" or valueType == "userdata" or valueType == "thread" then
        return nil, L["Profile contains unsupported data."]
    end
    if valueType ~= "table" then
        return value
    end

    seen = seen or {}
    if seen[value] then
        return nil, L["Profile contains recursive table data."]
    end
    seen[value] = true

    local copy = {}
    for key, childValue in pairs(value) do
        local copiedKey, keyError = SafeCopyProfileValue(key, seen)
        if keyError then
            seen[value] = nil
            return nil, L["Profile contains unsupported table keys."]
        end
        local copiedValue, valueError = SafeCopyProfileValue(childValue, seen)
        if valueError then
            seen[value] = nil
            return nil, valueError
        end
        copy[copiedKey] = copiedValue
    end

    seen[value] = nil
    return copy
end

local BOSS_NOTES_VIEWER_TRANSFER_KEYS = {
    style = true,
    scale = true,
    backgroundAlpha = true,
    borderAlpha = true,
    timerAlertBorder = true,
    timerPassedHide = true,
    fontSize = true,
    width = true,
    height = true,
    textColor = true,
    backgroundColor = true,
    borderColor = true,
}

local function CopyBossNotesViewerSettings(source, rejectUnknown)
    if type(source) ~= "table" then
        return nil, L["Boss Note viewer settings must be a table."]
    end
    local copy = {}
    for key, value in pairs(source) do
        if not BOSS_NOTES_VIEWER_TRANSFER_KEYS[key] then
            if rejectUnknown then
                return nil, string.format(L["Boss Note viewer setting '%s' is not transferable."], tostring(key))
            end
        else
            local copiedValue, copyError = SafeCopyProfileValue(value)
            if copyError then
                return nil, copyError
            end
            copy[key] = copiedValue
        end
    end
    return copy
end

local function BuildProfileTransferTable()
    local exportProfile = {}
    for key in pairs(IMPORTABLE_PROFILE_KEYS) do
        local value = RC.db.profile[key]
        if value ~= nil then
            local copiedValue, copyError = SafeCopyProfileValue(value)
            if copyError then
                return nil, string.format(L["Could not export setting '%s': %s"], key, copyError)
            end
            exportProfile[key] = copiedValue
        end
    end
    local bossNotes = RC.db.profile.bossNotes
    if type(bossNotes) == "table" and type(bossNotes.viewer) == "table" then
        local viewerSettings, viewerError = CopyBossNotesViewerSettings(bossNotes.viewer, false)
        if not viewerSettings then
            return nil, viewerError
        end
        exportProfile.bossNotesViewer = viewerSettings
    end
    return exportProfile
end

local function ValidateProfileTransferPayload(payload)
    if type(payload) ~= "table" then
        return nil, L["That does not look like a RaidControl profile string."]
    end
    if payload.type ~= "RaidControlProfile" then
        return nil, L["That profile string has the wrong profile type."]
    end
    if payload.schema ~= PROFILE_TRANSFER_SCHEMA then
        return nil, L["That profile string uses an unsupported schema."]
    end
    if type(payload.profile) ~= "table" then
        return nil, L["That profile string is missing profile data."]
    end

    local importedProfile = {}
    for key, value in pairs(payload.profile) do
        if type(key) ~= "string" then
            return nil, L["That profile contains an unsupported setting key."]
        end
        if not IMPORTABLE_PROFILE_KEYS[key] then
            return nil, string.format(L["That profile contains unsupported setting '%s'."], key)
        end
        local copiedValue, copyError
        if key == "bossNotesViewer" then
            copiedValue, copyError = CopyBossNotesViewerSettings(value, true)
        else
            copiedValue, copyError = SafeCopyProfileValue(value)
        end
        if copyError then
            return nil, copyError
        end
        importedProfile[key] = copiedValue
    end

    return importedProfile
end

local function ApplyImportedProfile(importedProfile)
    for key in pairs(IMPORTABLE_PROFILE_KEYS) do
        if key ~= "bossNotesViewer" then
            RC.db.profile[key] = nil
        end
    end
    for key, value in pairs(importedProfile) do
        if key ~= "bossNotesViewer" then
            RC.db.profile[key] = CopyPlainTable(value)
        end
    end

    -- Older exports had one sound for every tank instruction. Preserve that
    -- choice when the import does not supply the new category settings.
    for _, prefix in ipairs({ "tankAssistTaunt", "tankAssistDefensive", "tankAssistMovement" }) do
        if importedProfile[prefix .. "Sound"] == nil and importedProfile.tankAssistSound ~= nil then
            RC.db.profile[prefix .. "Sound"] = importedProfile.tankAssistSound
        end
        if importedProfile[prefix .. "CustomSoundFile"] == nil and importedProfile.tankAssistCustomSoundFile ~= nil then
            RC.db.profile[prefix .. "CustomSoundFile"] = importedProfile.tankAssistCustomSoundFile
        end
        if importedProfile[prefix .. "SoundChannel"] == nil then
            RC.db.profile[prefix .. "SoundChannel"] = "inherit"
        end
    end
    if importedProfile.tankAssistShowTimerBars == nil and importedProfile.tankAssistShowVisual == false then
        RC.db.profile.tankAssistShowTimerBars = false
    end

    local importedViewer = importedProfile.bossNotesViewer
    if type(importedViewer) == "table" then
        RC.db.profile.bossNotes = type(RC.db.profile.bossNotes) == "table" and RC.db.profile.bossNotes or {}
        local viewer = RC.db.profile.bossNotes.viewer
        viewer = type(viewer) == "table" and viewer or {}
        RC.db.profile.bossNotes.viewer = viewer
        for key, value in pairs(importedViewer) do
            if BOSS_NOTES_VIEWER_TRANSFER_KEYS[key] then
                viewer[key] = CopyPlainTable(value)
            end
        end
    end
end

local function RefreshAfterProfileImport(settings)
    if RC.ApplyTheme then RC:ApplyTheme(RC.db.profile.theme or "Starforge", false) end
    local legacyLauncherScale = RC.db.profile.launcherScale or RC.db.profile.scale or 1
    if RC.ApplyTopBarScale then
        RC:ApplyTopBarScale(RC.db.profile.topBarScale or legacyLauncherScale)
    end
    if RC.ApplyMenuScale then
        RC:ApplyMenuScale(RC.db.profile.menuScale or legacyLauncherScale)
    end
    if RC.ApplyInterfaceVisibility then RC:ApplyInterfaceVisibility() end
    if RC.RefreshLayout then RC:RefreshLayout() end
    if RC.UpdateAllFonts then RC:UpdateAllFonts() end
    if RC.UpdateAllBackdrops then RC:UpdateAllBackdrops() end
    if RC.UpdateAllBorders then RC:UpdateAllBorders() end
    if RC.UpdateAllTextColors then RC:UpdateAllTextColors() end
    if RC.RefreshTheme then RC:RefreshTheme(false) end
    local workspace = RC:GetModule("Workspace", true)
    if workspace and workspace.SetScale then
        workspace:SetScale(RC.db.profile.workspaceScale or RC.db.profile.settingsScale or 1)
        if workspace.RestoreHostPosition then
            workspace:RestoreHostPosition()
        end
    end
    local bossNotes = RC:GetModule("BossNotes", true)
    if bossNotes and bossNotes._viewer and bossNotes.RefreshViewer then
        bossNotes:RefreshViewer()
    end
    if bossNotes and bossNotes._popup and bossNotes._RefreshPopup then
        bossNotes:_RefreshPopup(false)
    end
    local actionStrip = RC:GetModule("ActionStrip", true)
    if actionStrip and actionStrip.UpdateVisibility then
        actionStrip:UpdateVisibility()
    end
    if actionStrip and actionStrip.UpdateScale then
        actionStrip:UpdateScale(RC.db.profile.actionStripScale or 1)
    end
    local tankAssist = RC:GetModule("TankAssist", true)
    if tankAssist then
        if tankAssist.HidePreview then tankAssist:HidePreview() end
        if tankAssist.frame then tankAssist.frame._rcPositionReady = nil end
        if tankAssist.timerFrame then tankAssist.timerFrame._rcPositionReady = nil end
        if tankAssist.statusFrame then tankAssist.statusFrame._rcPositionReady = nil end
        if tankAssist.ApplyEnabledState then tankAssist:ApplyEnabledState() end
        if tankAssist.RefreshRuntimeSettings then tankAssist:RefreshRuntimeSettings() end
        if tankAssist.ApplyFrameSettings then tankAssist:ApplyFrameSettings() end
    end
    if settings and settings.frame and settings.frame:IsShown() then
        settings:SelectTab(settings.selectedTab or "appearance")
    end
end

local function CreateHeaderScaleSlider(parent, options)
    local minScale = options.minScale or 0.50
    local maxScale = options.maxScale or 2.00
    local stepScale = options.stepScale or 0.05
    local defaultScale = options.defaultScale or 1.00
    local applyScale = options.applyScale
    local getScale = options.getScale
    local tooltipTitle = options.tooltipTitle or L["Scale"]
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
        control:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, RC.Config.InputBg.a or 0.98)
        control:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))

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
        minus:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
        minus:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))

        local minusText = minus:CreateFontString(nil, "OVERLAY")
        RC:SetFont(minusText, 12, "OUTLINE")
        minusText:SetPoint("CENTER")
        minusText:SetText("-")

        local plus = CreateFrame("Button", nil, control, "BackdropTemplate")
        plus:SetSize(20, 16)
        plus:SetPoint("RIGHT", control, "RIGHT", -2, 0)
        RC:SkinFrame(plus)
        plus:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
        plus:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))

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

        local function StyleStepButton(button, hovered, pressed)
            local bg = pressed and RC.Config.ButtonPressed or (hovered and RC.Config.ButtonHover or RC.Config.ButtonBg)
            button:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
            if hovered or pressed then
                button:SetBackdropBorderColor(RC.Config.InputFocus.r, RC.Config.InputFocus.g, RC.Config.InputFocus.b, RC.Config.InputFocus.a or 1)
            else
                button:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))
            end
        end
        for _, stepButton in ipairs({ minus, plus }) do
            stepButton:SetScript("OnEnter", function(button) StyleStepButton(button, true) end)
            stepButton:SetScript("OnLeave", function(button) StyleStepButton(button, false) end)
            stepButton:SetScript("OnMouseDown", function(button) StyleStepButton(button, true, true) end)
            stepButton:SetScript("OnMouseUp", function(button) StyleStepButton(button, button:IsMouseOver()) end)
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
            GameTooltip:AddLine(L["Click +/- or mouse wheel. Click value to type. Right-click resets."], 0.75, 0.75, 0.75, true)
            GameTooltip:AddLine(L["Enter applies. Escape cancels."], 0.62, 0.62, 0.62, true)
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
            control:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, RC.Config.InputBg.a or 0.98)
            control:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))
            valueEdit:SetBackdropColor(RC.Config.InputBg.r, RC.Config.InputBg.g, RC.Config.InputBg.b, RC.Config.InputBg.a or 0.98)
            valueEdit:SetBackdropBorderColor(RC.Config.InputBorder.r, RC.Config.InputBorder.g, RC.Config.InputBorder.b, math.max(0.10, RC.Config.InputBorder.a or 0))
            valueText:SetTextColor(RC.Config.SectionAccent.r, RC.Config.SectionAccent.g, RC.Config.SectionAccent.b, 1)
            StyleStepButton(minus, false)
            StyleStepButton(plus, false)
        end

        control:RefreshFromDB()
        control:RefreshTheme()
        return control
    end

end

local function ApplySettingsFrameScale(settings, newScale)
    if not settings or not settings.frame then
        return
    end

    local frame = settings.frame
    local applied = tonumber(newScale) or 1
    if applied < 0.50 then
        applied = 0.50
    elseif applied > 2.00 then
        applied = 2.00
    end
    RC.db.profile.settingsScale = applied

    RC:SetScalePreserveCenter(frame, applied)

    if settings.headerScaleSlider and settings.headerScaleSlider.RefreshFromDB then
        settings.headerScaleSlider:RefreshFromDB(applied)
    end
end

local function DrawSubTabs(settings, container, tabGroupKey, tabs, defaultKey)
    return SettingsV2.Navigation:DrawTopTabs(settings, container, tabGroupKey, tabs, defaultKey)
end

function Settings:OnInitialize() end

function Settings:OnEnable() end

function Settings:RecordError(message)
    local detail = tostring(message or L["Unknown settings error"])
    self.lastError = detail
    self.settingsRecoveryErrorCount = (self.settingsRecoveryErrorCount or 0) + 1
    if RC.db and RC.db.global then
        RC.db.global.lastSettingsError = {
            message = detail,
            timestamp = time and time() or 0,
        }
    end
    if self.lastErrorNotification ~= detail then
        self.lastErrorNotification = detail
        RC:ShowError(L["RaidControl Settings could not finish loading; the error was saved for diagnostics."])
    end
    if self.frame and self.frame.CreateFontString then
        if not self.errorBanner then
            local host = CreateFrame("Frame", nil, self.frame)
            host:SetFrameLevel(self.frame:GetFrameLevel() + 80)
            host:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 300, -106)
            host:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -42, -106)
            host:SetHeight(48)
            local banner = host:CreateFontString(nil, "OVERLAY")
            RC:SetFont(banner, 12, "OUTLINE")
            banner:SetAllPoints()
            banner:SetJustifyH("LEFT")
            banner:SetJustifyV("TOP")
            banner:SetTextColor(1, 0.32, 0.26, 1)
            self.errorBannerFrame = host
            self.errorBanner = banner
        end
        self.errorBanner:SetText(string.format(L["Settings recovery: %s"], detail))
        self.errorBannerFrame:Show()
    end
end

local function GetWorkspaceScale()
    local workspace = RC:GetModule("Workspace", true)
    if workspace and workspace.GetScale then
        return workspace:GetScale()
    end
    return RC.db.profile.workspaceScale or RC.db.profile.settingsScale or 1
end

local function ApplyWorkspaceScale(settings, newScale)
    local workspace = RC:GetModule("Workspace", true)
    if workspace and workspace.SetScale then
        return workspace:SetScale(newScale)
    end
    ApplySettingsFrameScale(settings, newScale)
    return RC.db.profile.settingsScale or 1
end

function Settings:RunStage(label, callback)
    local ok, result = pcall(callback)
    if not ok then
        self:RecordError(tostring(label) .. ": " .. tostring(result))
        return false
    end
    return true, result
end

-- =============================================================================
-- WINDOW
-- =============================================================================

function Settings:RefreshLayoutModeControls(active)
    local layoutMode = RC:GetModule("LayoutMode", true)
    if active == nil then
        active = layoutMode and layoutMode.IsActive and layoutMode:IsActive() or false
    end
    local actionText = active and L["Save & Lock UI"] or L["Unlock UI"]
    if self.layoutModeButton and self.layoutModeButton.Text then
        self.layoutModeButton.Text:SetText(actionText)
    end
    if self.layoutModeActionButton and self.layoutModeActionButton.SetText then
        self.layoutModeActionButton:SetText(active and L["Lock UI and Finish Layout"] or L["Unlock and Move UI"])
    end
    if self.layoutLockCheckbox and self.layoutLockCheckbox.SetValue then
        self.layoutLockCheckbox:SetValue(not active)
    end
end

function Settings:HideForLayoutMode()
    if not self.frame then
        return
    end
    self.frame:Hide()
end

function Settings:ToggleLayoutModeFromSettings()
    local layoutMode = RC:GetModule("LayoutMode", true)
    if not layoutMode or not layoutMode.Toggle then
        return false
    end
    local wasActive = layoutMode:IsActive()
    local changed = layoutMode:Toggle()
    self:RefreshLayoutModeControls(layoutMode:IsActive())
    if changed and not wasActive and layoutMode:IsActive() then
        self:HideForLayoutMode()
    end
    return changed
end

function Settings:SetLayoutLockedFromSettings(locked)
    local layoutMode = RC:GetModule("LayoutMode", true)
    if not layoutMode or not layoutMode.SetAllFrameLocks then
        RC:SetFrameLock(true)
        RC.db.profile.lockActionStrip = true
        return false
    end
    local wasActive = layoutMode:IsActive()
    local changed = layoutMode:SetAllFrameLocks(locked)
    self:RefreshLayoutModeControls(layoutMode:IsActive())
    if changed and not locked and not wasActive and layoutMode:IsActive() then
        self:HideForLayoutMode()
    end
    return changed
end

function Settings:Open()
    if InCombatLockdown and InCombatLockdown() then
        self.openPending = true
        if not self.combatOpenNotified then
            self.combatOpenNotified = true
            RC:ShowError(L["RaidControl Settings will open when combat ends."])
        end
        return false
    end

    self.openPending = nil
    if not self.frame then
        if not self.createAttempted then
            self.createAttempted = true
            self:CreateWindow()
        end
    end
    if not self.frame then
        return false
    end

    self:RefreshLayoutModeControls()
    self.frame:Show()
    local workspace = RC:GetModule("Workspace", true)
    if self.frame.rcWorkspaceHosted and workspace and workspace.host and workspace.host.Raise then
        workspace.host:Raise()
    else
        self.frame:Raise()
    end
    return true
end

function Settings:ApplyLayoutTheme()
    local v2 = GetSettingsV2()
    if not self.v2Shell or not v2 or not v2.Layout then
        return
    end

    local layoutStyle = "theme-" .. (RC:GetThemeStyle() or "starforge")
    v2.Layout:Apply(self.v2Shell)

    if self.appliedLayoutStyle ~= layoutStyle then
        self.appliedLayoutStyle = layoutStyle
        if self.scrollStatusByTab and self.selectedTab then
            self.scrollStatusByTab[self.selectedTab] = { scrollvalue = 0, offset = 0 }
        end
        if self.sidebarContainer then
            self:BuildSidebarTabs()
        end
    end
end

function Settings:RefreshTheme(staticOnly)
    if not self.frame then
        return
    end

    local v2 = GetSettingsV2()
    if self.v2Shell and v2 and v2.ThemeBridge then
        self:ApplyLayoutTheme()
        v2.ThemeBridge:Apply(self)
        if not staticOnly and self.frame:IsShown() and not self.themeRefreshPending then
            self.themeRefreshPending = true
            C_Timer.After(0, function()
                self.themeRefreshPending = nil
                if self.frame and self.frame:IsShown() then
                    self:SelectTab(self.selectedTab or "appearance")
                end
            end)
        end
        return
    end

    self:ApplyLayoutTheme()

    RC:ApplyThemedWindow(self.frame, "window")

    if self.themeHeader then
        RC:ApplyThemedHeader(self.themeHeader)
    end
    if self.themeSidebar then
        RC:ApplyThemedSidebar(self.themeSidebar)
    end
    if self.themeContentShell then
        RC:ApplyThemedPanel(self.themeContentShell, "content", {
            role = "Color",
            borderAlpha = 0,
        })
    end
    if self.modernFooter then
        RC:ApplyThemedFooter(self.modernFooter)
    end

    local accent = RC.Config.Accent
    if self.themeHeaderWash then
        self.themeHeaderWash:Hide()
    end
    if self.themeHeaderAccent then
        self.themeHeaderAccent:SetWidth(3)
        self.themeHeaderAccent:SetColorTexture(accent.r, accent.g, accent.b, 1)
        self.themeHeaderAccent:Show()
    end
    if self.themeHeaderSeparator then
        if RC:IsModernTheme() then
            self.themeHeaderSeparator:SetColorTexture(
                RC.Config.SeparatorColor.r,
                RC.Config.SeparatorColor.g,
                RC.Config.SeparatorColor.b,
                math.min(0.38, RC.Config.SeparatorColor.a or 0.30)
            )
        else
            self.themeHeaderSeparator:SetColorTexture(accent.r, accent.g, accent.b, 0.9)
        end
    end
    if self.themeSidebarSeparator then
        if RC:IsModernTheme() then
            self.themeSidebarSeparator:SetColorTexture(
                RC.Config.SeparatorColor.r,
                RC.Config.SeparatorColor.g,
                RC.Config.SeparatorColor.b,
                math.min(0.38, RC.Config.SeparatorColor.a or 0.30)
            )
        else
            self.themeSidebarSeparator:SetColorTexture(accent.r, accent.g, accent.b, 0.75)
        end
    end
    if self.modernTitleRule then
        self.modernTitleRule:SetColorTexture(RC.Config.SectionAccent.r, RC.Config.SectionAccent.g, RC.Config.SectionAccent.b, 0.92)
    end
    if self.modernHeaderBeam then
        self.modernHeaderBeam:SetColorTexture(RC.Config.SectionAccent.r, RC.Config.SectionAccent.g, RC.Config.SectionAccent.b, RC:IsShadowsteelTheme() and 0.34 or 0.78)
    end
    if self.modernContentWatermark then
        self.modernContentWatermark:SetVertexColor(accent.r, accent.g, accent.b, 0.018)
    end
    if self.settingsInnerHighlight then
        self.settingsInnerHighlight:SetColorTexture(1, 1, 1, 0.07)
    end
    if self.modernPanelSheen then
        self.modernPanelSheen:SetColorTexture(1, 1, 1, 1)
        if self.modernPanelSheen.SetGradient and CreateColor then
            self.modernPanelSheen:SetGradient(
                "VERTICAL",
                CreateColor(0, 0, 0, 0.055),
                CreateColor(1, 1, 1, 0.012)
            )
        else
            self.modernPanelSheen:SetAlpha(0.025)
        end
    end
    if self.contentVignette then
        self.contentVignette:SetColorTexture(0, 0, 0, 1)
        if self.contentVignette.SetGradient and CreateColor then
            self.contentVignette:SetGradient(
                "VERTICAL",
                CreateColor(0, 0, 0, 0.08),
                CreateColor(0, 0, 0, 0.01)
            )
        else
            self.contentVignette:SetAlpha(0.06)
        end
    end
    if self.modernDoneButton then
        if RC:IsShadowsteelTheme() then
            self.modernDoneButton:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a or 1)
            self.modernDoneButton:SetBackdropBorderColor(RC.Config.NavSelectedBorder.r, RC.Config.NavSelectedBorder.g, RC.Config.NavSelectedBorder.b, 0.82)
            self.modernDoneButton.Text:SetTextColor(RC.Config.NavSelectedText.r, RC.Config.NavSelectedText.g, RC.Config.NavSelectedText.b, 1)
        else
            self.modernDoneButton:SetBackdropColor(accent.r, accent.g, accent.b, 0.94)
            self.modernDoneButton:SetBackdropBorderColor(accent.r, accent.g, accent.b, 1)
            self.modernDoneButton.Text:SetTextColor(0.02, 0.08, 0.07, 1)
        end
    end
    if self.modernHeaderGlow then
        self.modernHeaderGlow:SetColorTexture(accent.r, accent.g, accent.b, 1)
        if self.modernHeaderGlow.SetGradient and CreateColor then
            self.modernHeaderGlow:SetGradient(
                "HORIZONTAL",
                CreateColor(accent.r, accent.g, accent.b, 0.10),
                CreateColor(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0)
            )
        end
    end
    if self.modernSidebarGlow then
        self.modernSidebarGlow:SetColorTexture(accent.r, accent.g, accent.b, 1)
        if self.modernSidebarGlow.SetGradient and CreateColor then
            self.modernSidebarGlow:SetGradient(
                "VERTICAL",
                CreateColor(accent.r, accent.g, accent.b, 0.09),
                CreateColor(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0)
            )
        end
    end
    if self.modernTabBarBg then
        self.modernTabBarBg:SetColorTexture(
            RC.Config.TabBg.r,
            RC.Config.TabBg.g,
            RC.Config.TabBg.b,
            RC.Config.TabBg.a or 0.55
        )
    end
    if self.modernTabBarLine then
        self.modernTabBarLine:SetColorTexture(
            RC.Config.SeparatorColor.r,
            RC.Config.SeparatorColor.g,
            RC.Config.SeparatorColor.b,
            math.min(0.42, RC.Config.SeparatorColor.a or 0.35)
        )
    end
    if self.modernFooterLine then
        self.modernFooterLine:SetColorTexture(
            RC.Config.SeparatorColor.r,
            RC.Config.SeparatorColor.g,
            RC.Config.SeparatorColor.b,
            math.min(0.42, RC.Config.SeparatorColor.a or 0.35)
        )
    end
    if self.headerPageSubtitle then
        self.headerPageSubtitle:SetTextColor(accent.r, accent.g, accent.b, 1)
    end
    if self.modernPageTitle then
        RC:SetFont(self.modernPageTitle, 15, "OUTLINE")
        self.modernPageTitle:SetTextColor(RC.Config.HeaderText.r, RC.Config.HeaderText.g, RC.Config.HeaderText.b, RC.Config.HeaderText.a or 1)
    end
    if self.modernPageDescription then
        RC:SetFont(self.modernPageDescription, 9, "")
        self.modernPageDescription:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 0.72)
    end
    if self.sidebarBrand then
        RC:SetFont(self.sidebarBrand, RC:IsShadowsteelTheme() and 16 or 18, "OUTLINE")
        self.sidebarBrand:SetTextColor(RC.Config.HeaderText.r, RC.Config.HeaderText.g, RC.Config.HeaderText.b, RC.Config.HeaderText.a or 1)
    end
    if self.sidebarTagline then
        RC:SetFont(self.sidebarTagline, 9, "OUTLINE")
        self.sidebarTagline:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC:IsShadowsteelTheme() and 0.70 or 0.82)
    end
    if self.sidebarSectionLabel then
        RC:SetFont(self.sidebarSectionLabel, RC:IsShadowsteelTheme() and 10 or 11, "OUTLINE")
        self.sidebarSectionLabel:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC:IsShadowsteelTheme() and 0.62 or 0.72)
    end
    if self.sidebarVersionText then
        self.sidebarVersionText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.70)
    end
    if self.headerScaleSlider and self.headerScaleSlider.RefreshTheme then
        self.headerScaleSlider:RefreshTheme()
    end

    for _, tab in pairs(self.tabs or {}) do
        if tab and tab.RefreshTheme then
            tab:RefreshTheme()
        end
    end

    if self.frame and self.frame.rcWorkspaceHosted then
        self.frame:SetBackdropColor(0, 0, 0, 0)
        self.frame:SetBackdropBorderColor(0, 0, 0, 0)
    end

    if not staticOnly and self.frame:IsShown() and not self.themeRefreshPending then
        self.themeRefreshPending = true
        C_Timer.After(0, function()
            self.themeRefreshPending = nil
            if self.frame and self.frame:IsShown() then
                self:SelectTab(self.selectedTab or "appearance")
            end
        end)
    end
end

function Settings:QueueThemePickerRefresh()
    if self.themePickerRefreshTimer then
        self.themePickerRefreshTimer:Cancel()
    end
    self.themePickerRefreshTimer = C_Timer.NewTimer(0.25, function()
        self.themePickerRefreshTimer = nil
        if RC.ColorPickerFrame and RC.ColorPickerFrame:IsShown() then
            self:QueueThemePickerRefresh()
        elseif self.frame and self.frame:IsShown() then
            self:SelectTab("appearance")
        end
    end)
end

function Settings:CreateWindow()
    local v2 = GetSettingsV2()
    if not v2 or not v2.Shell then
        return
    end

    self.navTabs = NAV_TABS

    local ok, shellOrErr = pcall(function()
        return v2.Shell:Create(self, {
            createScaleSlider = function(header, closeButton, level)
                local slider = CreateHeaderScaleSlider(header, {
                    point = { "RIGHT", closeButton, "LEFT", -12, 0 },
                    width = 118,
                    height = 22,
                    frameStrata = self.frame and self.frame:GetFrameStrata() or "FULLSCREEN_DIALOG",
                    frameLevel = level,
                    tooltipTitle = L["Workspace Panels Scale"],
                    minScale = 0.50,
                    maxScale = 2.00,
                    stepScale = 0.01,
                    defaultScale = 1.00,
                    mrtLike = true,
                    getScale = function()
                        return GetWorkspaceScale()
                    end,
                    applyScale = function(value)
                        ApplyWorkspaceScale(self, value)
                    end,
                })

                local label = header:CreateFontString(nil, "OVERLAY")
                RC:SetFont(label, 10, "OUTLINE")
                label:SetPoint("RIGHT", slider, "LEFT", -8, 0)
                label:SetText(L["Scale"])
                label:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 1)
                slider:Hide()
                label:Hide()
                return slider, label
            end,
        })
    end)
    if not ok or not shellOrErr or not shellOrErr.frame then
        self:RecordError("Settings shell: " .. tostring(shellOrErr))
        return
    end

    local shell = shellOrErr

    local frame = shell.frame

    self.tabs = {}
    local recoveryErrorsBefore = self.settingsRecoveryErrorCount or 0
    local layoutOk = self:RunStage("Settings layout", function()
        self:ApplyLayoutTheme()
    end)
    if not layoutOk then
        self:RunStage("Fallback sidebar", function()
            self:BuildFallbackSidebarTabs()
        end)
    end
    self:RunStage("Settings theme", function()
        self:RefreshTheme(true)
    end)

    self:RunStage("Settings window hooks", function()
        frame:HookScript("OnShow", function()
            if frame.rcWorkspaceChromeOnly then
                return
            end
            local workspace = RC:GetModule("Workspace", true)
            if frame.rcWorkspaceHosted and workspace and workspace.host and workspace.host.Raise then
                workspace.host:Raise()
            else
                frame:Raise()
            end
            if Settings.headerScaleSlider then
                Settings.headerScaleSlider:RefreshFromDB()
            end
            Settings:RunStage("Settings page refresh", function()
                Settings:SelectTab(Settings.selectedTab or "interface")
            end)
        end)
        frame:HookScript("OnHide", function()
            if Settings.headerScaleSlider then
                Settings.headerScaleSlider:Hide()
            end
            if Settings.headerScaleLabel then
                Settings.headerScaleLabel:Hide()
            end
            if RC.ColorPickerFrame and RC.ColorPickerFrame:IsShown() then
                RC.ColorPickerFrame:Hide()
            end
        end)
    end)

    self:RunStage("Workspace chrome", function()
        local workspace = RC:GetModule("Workspace", true)
        if workspace and workspace.RegisterWindow then
            local entry = workspace:RegisterWindow("settings", frame, {
                chromeParent = shell.header,
                placeChrome = function(bar)
                    bar:ClearAllPoints()
                    bar:SetPoint("CENTER", shell.header, "CENTER", 0, 0)
                end,
                applyScale = function(value)
                    ApplySettingsFrameScale(self, value)
                end,
                pageRoot = frame,
                legacyChrome = { shell.header },
                onHosted = function()
                    shell.header:Show()
                    shell.footer:Show()
                    frame:SetBackdropBorderColor(0, 0, 0, 0)
                    if workspace.AdoptSettingsShell then
                        workspace:AdoptSettingsShell(shell, frame)
                    end
                end,
                rightClickTargets = { shell.header },
                reset = function()
                    frame:ClearAllPoints()
                    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                end,
            })
            shell.workspaceBar = not frame.rcWorkspaceHosted and entry and entry.bar or nil
            Settings.workspaceBar = entry and entry.bar or nil
            if shell.layoutButton then
                shell.layoutButton:Show()
            end
            if self.headerScaleSlider then
                self.headerScaleSlider:Hide()
            end
            if self.headerScaleLabel then
                self.headerScaleLabel:Hide()
            end
            Settings:ApplyLayoutTheme()
        end
    end)

    self:RunStage("Settings header controls", function()
        if self.headerScaleSlider then
            self.headerScaleSlider:Hide()
        end
        if self.headerScaleLabel then
            self.headerScaleLabel:Hide()
        end
    end)

    local pageOk, pageBuilt = self:RunStage("Initial settings page", function()
        return self:SelectTab("interface")
    end)
    if pageOk and pageBuilt ~= false
        and (self.settingsRecoveryErrorCount or 0) == recoveryErrorsBefore
        and self.errorBannerFrame
    then
        self.errorBannerFrame:Hide()
    end
end

-- =============================================================================
-- SIDEBAR TABS
-- =============================================================================

function Settings:BuildSidebarTabs()
    return SettingsV2.Navigation:BuildSidebar(self, NAV_TABS)
end

function Settings:BuildFallbackSidebarTabs()
    local parent = self.v2Shell and self.v2Shell.sidebarNav
    if not parent then
        return false
    end
    if self.sidebarContainer and self.sidebarContainer.ReleaseChildren then
        self.sidebarContainer:ReleaseChildren()
    end
    for _, button in ipairs(self.fallbackSidebarButtons or {}) do
        button:Hide()
    end
    self.fallbackSidebarButtons = {}
    self.tabs = {}

    local previous
    for _, tabInfo in ipairs(NAV_TABS) do
        local button = RC:CreateStandardButton(nil, parent, 180, 32)
        button.frame = button
        button.customBg = true
        button.Text:SetText(tabInfo.label)
        button:SetFrameLevel(parent:GetFrameLevel() + 2)
        button:SetPoint("TOPLEFT", previous or parent, previous and "BOTTOMLEFT" or "TOPLEFT", 0, previous and -4 or 0)
        button:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
        function button:SetSelected(selected)
            local bg = selected and RC.Config.TabSelectedBg or RC.Config.TabBg
            self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 0.7)
            self.Text:SetTextColor(selected and 1 or 0.78, selected and 1 or 0.82, selected and 1 or 0.86, 1)
        end
        button:SetScript("OnClick", function()
            self:ClearSearch(false)
            self:SelectTab(tabInfo.key)
        end)
        button:SetSelected(tabInfo.key == (self.selectedTab or "interface"))
        self.tabs[tabInfo.key] = button
        self.fallbackSidebarButtons[#self.fallbackSidebarButtons + 1] = button
        previous = button
    end
    return true
end

function Settings:ClearSearch(restorePage)
    self.searchGeneration = (self.searchGeneration or 0) + 1
    self.searchQuery = ""
    self.searchDisplayQuery = ""
    self.searchResults = {}

    if self.searchBox and self.searchBox.GetText and self.searchBox:GetText() ~= "" then
        self.searchTextGuard = true
        self.searchBox:SetText("")
        self.searchTextGuard = nil
    end
    if self.searchPlaceholder and self.searchPlaceholder.SetShown then
        local hasFocus = self.searchBox and self.searchBox.HasFocus and self.searchBox:HasFocus()
        self.searchPlaceholder:SetShown(not hasFocus)
    end
    if self.searchClearButton and self.searchClearButton.Hide then
        self.searchClearButton:Hide()
    end

    if restorePage and self.selectedTab == "search" then
        local returnPage = self.searchReturnTab
        if not returnPage or returnPage == "search" then
            returnPage = "interface"
        end
        self:SelectTab(returnPage)
    end
end

function Settings:OpenDestination(page, subTab)
    page = page or "interface"
    self:ClearSearch(false)
    if subTab then
        self.subTabState = self.subTabState or {}
        self.subTabState[page] = subTab
    end
    self.scrollStatusByTab = self.scrollStatusByTab or {}
    self.scrollStatusByTab[page] = { scrollvalue = 0, offset = 0 }
    return self:SelectTab(page)
end

function Settings:HandleSearchChanged(query)
    local search = GetSettingsV2() and GetSettingsV2().Search
    if not search or not search.Find then
        return
    end

    local normalized = search:Normalize(query)
    local displayQuery = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    self.searchGeneration = (self.searchGeneration or 0) + 1
    local generation = self.searchGeneration
    if normalized == "" then
        self.searchQuery = ""
        self.searchDisplayQuery = ""
        self.searchResults = {}
        if self.selectedTab == "search" then
            local returnPage = self.searchReturnTab
            if not returnPage or returnPage == "search" then
                returnPage = "interface"
            end
            self:SelectTab(returnPage)
        end
        return
    end

    if self.selectedTab ~= "search" then
        self.searchReturnTab = self.selectedTab or "interface"
    end
    self.searchQuery = normalized
    self.searchDisplayQuery = displayQuery

    local function ApplySearch()
        if Settings.searchGeneration ~= generation or Settings.searchQuery ~= normalized then
            return
        end
        Settings.searchResults = search:Find(normalized, 30)
        Settings:SelectTab("search")
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.08, ApplySearch)
    else
        ApplySearch()
    end
end

function Settings:OpenFirstSearchResult()
    local search = GetSettingsV2() and GetSettingsV2().Search
    local results = self.searchResults
    if search and self.searchQuery and self.searchQuery ~= "" then
        results = search:Find(self.searchQuery, 30)
        self.searchResults = results
    end
    local first = results and results[1]
    if first then
        return self:OpenDestination(first.page, first.tab)
    end
    return false
end

function Settings:GetTabInfo(key)
    if key == "search" then
        local count = #(self.searchResults or {})
                return {
            key = "search",
            label = L["Search"],
            description = string.format(count == 1 and L["%d match for \"%s\""] or L["%d matches for \"%s\""], count, self.searchDisplayQuery or self.searchQuery or ""),
        }
    end
    for _, tab in ipairs(NAV_TABS) do
        if tab.key == key then
            return tab
        end
    end
    return { key = key, label = L["Settings"], description = "" }
end

function Settings:SelectTab(key)
    local isValidKey = key == "search" and self.searchQuery and self.searchQuery ~= ""
    for _, tab in ipairs(NAV_TABS) do
        if tab.key == key then
            isValidKey = true
            break
        end
    end
    if not isValidKey then
        key = "interface"
    end

    self.selectedTab = key
    local workspace = RC:GetModule("Workspace", true)
    if workspace and workspace.RefreshChrome then
        workspace:RefreshChrome()
    end
    self.layoutModeActionButton = nil
    self.layoutLockCheckbox = nil
    local tabInfo = self:GetTabInfo(key)
    local v2 = GetSettingsV2()
    local useV2Scroll = self.v2Shell and v2 and v2.Shell and v2.Shell.CreateScroll
    if v2 and v2.Navigation and v2.Navigation.UpdateHeader then
        v2.Navigation:UpdateHeader(self, tabInfo)
    end

    if (not useV2Scroll) and self.activeSubTabRow then
        self.activeSubTabRow:Release()
        self.activeSubTabRow = nil
    end
    if (not useV2Scroll) and self.modernTabBar then
        self.modernTabBar:Hide()
    end

    if self.headerPageSubtitle then
        self.headerPageSubtitle:SetText(tabInfo.label or L["Settings"])
    end
    if self.modernPageTitle then
        self.modernPageTitle:SetText(tabInfo.label or L["Settings"])
    end
    if self.modernPageDescription then
        self.modernPageDescription:SetText(tabInfo.description or "")
    end

    for tabKey, tab in pairs(self.tabs or {}) do
        local selected = tabKey == key
        if tab and tab.SetHovered then
            local isMouseOver = tab.frame and tab.frame.IsMouseOver and tab.frame:IsMouseOver()
            tab:SetHovered((not selected) and isMouseOver)
        end
        if tab and tab.SetSelected then
            tab:SetSelected(selected)
        end
    end

    if self.scroll then
        if v2 and v2.Sections and v2.Sections.Active then
            v2.Sections.Active[self.scroll] = nil
        end
    end

    if (not useV2Scroll) and self.contentContainer and self.contentContainer.ReleaseChildren then
        self.contentContainer:ReleaseChildren()
    end

    local scroll
    if useV2Scroll then
        scroll = v2.Shell:CreateScroll(self, key)
    else
        scroll = AceGUI:Create("RC_ScrollFrame")
        scroll:SetFullWidth(true)
        scroll:SetFullHeight(true)
        scroll:SetLayout("Flow")
        if scroll.frame then
            scroll.frame:SetClipsChildren(true)
        end
        if scroll.content then
            scroll.content:SetClipsChildren(true)
        end
        self.scroll = scroll
        self.scrollStatusByTab = self.scrollStatusByTab or {}
        self.scrollStatusByTab[key] = self.scrollStatusByTab[key] or { scrollvalue = 0, offset = 0 }
        if scroll.SetStatusTable then
            scroll:SetStatusTable(self.scrollStatusByTab[key])
        end
        self.contentContainer:AddChild(scroll)
    end
    if not scroll then
        self:RecordError("Failed to create the settings scroll frame.")
        return false
    end
    if v2 and v2.Sections and v2.Sections.Active then
        v2.Sections.Active[scroll] = nil
    end
    local buildToken = self.v2ContentBuildToken

    AddSpacer(scroll, 2)

    local ok, err = pcall(function()
        if key == "search" then
            self:BuildSearchResults(scroll)
        elseif key == "interface" then
            self:BuildGeneral(scroll)
        elseif key == "screenshot" then
            self:BuildScreenshot(scroll)
        elseif key == "appearance" then
            self:BuildAppearance(scroll)
        elseif key == "markers" then
            self:BuildMarkers(scroll)
        elseif key == "ready" then
            self:BuildReadyCheck(scroll)
        elseif key == "tank" then
            self:BuildRaidTools(scroll, "tank")
        end
    end)

    if not ok then
        AddSpacer(scroll, 8)
        AddErrorLabel(scroll, string.format(L["Settings build error: %s"], tostring(err)))
        self:RecordError("Settings page: " .. tostring(err))
    end

    C_Timer.After(0, function()
        if buildToken and self.v2ContentBuildToken ~= buildToken then
            return
        end
        if self.scroll and self.scroll ~= scroll then
            return
        end
        if scroll.DoLayout then
            scroll:DoLayout()
        end
        if scroll.FixScroll then
            scroll:FixScroll()
        end
        local status = self.scrollStatusByTab and self.scrollStatusByTab[key]
        if status and scroll.SetScroll then
            scroll:SetScroll(status.scrollvalue or 0)
            if scroll.FixScroll then
                scroll:FixScroll()
            end
        end
        if v2 and v2.ThemeBridge and v2.ThemeBridge.RefreshVisibleWidgets then
            v2.ThemeBridge:RefreshVisibleWidgets(self)
        end
    end)
    return ok
end

-- =============================================================================
-- TAB BUILDERS
-- =============================================================================

function Settings:BuildSearchResults(container)
    -- The page search box lives in the sub-tab bar. Page rebuilds hide that
    -- bar, so keep it visible here or the box vanishes mid-typing.
    local shell = self.v2Shell
    if shell and shell.topTabs then
        shell.topTabs:Show()
    end
    local results = self.searchResults or {}
    local displayQuery = self.searchDisplayQuery or self.searchQuery or ""
    local description
    if #results == 0 then
        description = string.format(L["No settings match \"%s\". Try a shorter word."], displayQuery)
    elseif #results == 1 then
        description = L["1 match. Click it or press Enter to open the setting."]
    else
        description = string.format(L["%d matches for \"%s\". Press Enter to open the first one."], #results, displayQuery)
    end
    AddSection(container, L["Search Results"], description)

    if #results == 0 then
        AddActionToolbar(container, {
            {
                text = L["Back to Interface"],
                width = 198,
                onClick = function()
                    self:OpenDestination("interface")
                end,
            },
            {
                text = L["Browse Tank Assist"],
                width = 198,
                onClick = function()
                    self:OpenDestination("tank", "overview")
                end,
            },
        }, { align = "left" })
        return
    end

    for _, result in ipairs(results) do
        local selectedResult = result
        AddActionToolbar(container, {
            {
                text = L[selectedResult.label] .. "  -  " .. L[selectedResult.path],
                width = 620,
                onClick = function()
                    self:OpenDestination(selectedResult.page, selectedResult.tab)
                end,
            },
        }, { align = "left" })
    end
end

function Settings:BuildGeneral(container)
    local function RefreshActionSurfaces()
        local control = RC:GetModule("Control", true)
        if control and control.RefreshButtonVisibility then
            control:RefreshButtonVisibility()
        end
        if RC.RefreshLayout then
            RC:RefreshLayout()
        end
        local actionStrip = RC:GetModule("ActionStrip", true)
        if actionStrip and actionStrip.RefreshButtonVisibility then
            actionStrip:RefreshButtonVisibility()
        end
        if actionStrip and actionStrip.UpdateVisibility then
            actionStrip:UpdateVisibility()
        end
        if actionStrip and actionStrip.RefreshModifierAttributes then
            actionStrip:RefreshModifierAttributes()
        end
        local markers = RC:GetModule("Markers", true)
        if markers and markers.RefreshModifierAttributes then
            markers:RefreshModifierAttributes()
        end
        if RC.UpdateCycleKeybinds then
            RC:UpdateCycleKeybinds()
        end
    end

    local subTab = DrawSubTabs(self, container, "interface", {
        { key = "layout", label = L["General"] },
        { key = "buttons", label = L["Dropdown"] },
        { key = "action_strip", label = L["Action Strip"] },
        { key = "marks", label = L["Role Marks"] },
    }, "layout")

    if subTab == "marks" then
        local autoMarker = RC:GetModule("AutoMarker", true)
        local markerOptions = {
            [1] = L["Star"],
            [2] = L["Circle"],
            [3] = L["Diamond"],
            [4] = L["Triangle"],
            [5] = L["Moon"],
            [6] = L["Square"],
            [7] = L["Cross"],
            [8] = L["Skull"],
        }
        local markerOrder = { 1, 2, 3, 4, 5, 6, 7, 8 }
        local function RefreshAutoMarker()
            if autoMarker and autoMarker.ApplySettings then
                autoMarker:ApplySettings()
            end
        end

        AddSection(container, L["Mythic+ Role Marks"], L["One secure tank and healer reminder before each key."])

        AddCheckbox(
            container,
            L["Mark Tank"],
            function() return RC.db.profile.autoMarkTanks ~= false end,
            function(value) RC.db.profile.autoMarkTanks = value end,
            RefreshAutoMarker
        )

        -- Tank and healer can't share a marker; when one pick bumps the other,
        -- update the other dropdown so it never shows a stale icon.
        local tankMarkerDropdown, healerMarkerDropdown
        tankMarkerDropdown = AddDropdown(
            container,
            L["Tank Marker"],
            markerOptions,
            function() return tonumber(RC.db.profile.autoMarkTanksIcon) or 6 end,
            function(value)
                value = tonumber(value) or 6
                RC.db.profile.autoMarkTanksIcon = value
                if tonumber(RC.db.profile.autoMarkHealersIcon) == value then
                    RC.db.profile.autoMarkHealersIcon = value == 2 and 1 or 2
                    if healerMarkerDropdown and healerMarkerDropdown.SetValue then
                        healerMarkerDropdown:SetValue(RC.db.profile.autoMarkHealersIcon)
                    end
                end
            end,
            RefreshAutoMarker,
            markerOrder
        )

        AddCheckbox(
            container,
            L["Mark Healer"],
            function() return RC.db.profile.autoMarkHealers ~= false end,
            function(value) RC.db.profile.autoMarkHealers = value end,
            RefreshAutoMarker
        )

        healerMarkerDropdown = AddDropdown(
            container,
            L["Healer Marker"],
            markerOptions,
            function() return tonumber(RC.db.profile.autoMarkHealersIcon) or 2 end,
            function(value)
                value = tonumber(value) or 2
                RC.db.profile.autoMarkHealersIcon = value
                if tonumber(RC.db.profile.autoMarkTanksIcon) == value then
                    RC.db.profile.autoMarkTanksIcon = value == 6 and 1 or 6
                    if tankMarkerDropdown and tankMarkerDropdown.SetValue then
                        tankMarkerDropdown:SetValue(RC.db.profile.autoMarkTanksIcon)
                    end
                end
            end,
            RefreshAutoMarker,
            markerOrder
        )

        AddCheckbox(
            container,
            L["Only in Mythic Dungeons"],
            function() return RC.db.profile.autoMarkRolesDungeonOnly ~= false end,
            function(value) RC.db.profile.autoMarkRolesDungeonOnly = value end,
            RefreshAutoMarker
        )

        AddSlider(
            container,
            L["Reminder Scale"],
            60, 160, 1,
            function() return math.floor((RC.db.profile.autoMarkRoleButtonScale or 1) * 100 + 0.5) end,
            function(value)
                RC.db.profile.autoMarkRoleButtonScale = value / 100
                if autoMarker and autoMarker.ApplyRoleMarkButtonScale then
                    autoMarker:ApplyRoleMarkButtonScale(value / 100)
                end
            end,
            RefreshAutoMarker
        )

        AddActionToolbar(container, {
            {
                text = L["Check Now"],
                onClick = function()
                    if autoMarker and autoMarker.MarkRolesNow then
                        autoMarker:MarkRolesNow()
                    end
                end,
            },
            {
                text = L["Preview Button"],
                onClick = function()
                    if autoMarker and autoMarker.PreviewRoleMarkButton then
                        autoMarker:PreviewRoleMarkButton()
                    end
                end,
            },
            {
                text = L["Reset Position"],
                onClick = function()
                    if autoMarker and autoMarker.ResetRoleMarkPosition then
                        autoMarker:ResetRoleMarkPosition()
                    end
                end,
            },
        })
        return
    end


    if subTab == "layout" then
        AddSection(container, L["Interface"], L["Main visibility and frame behavior."])

        AddCheckbox(
            container,
            L["Show Top Bar and Dropdown"],
            function()
                return not RC.db.profile.hideTopBar and not RC.db.profile.hideMenu
            end,
            function(value)
                RC.db.profile.hideTopBar = not value
                RC.db.profile.hideMenu = not value
            end,
            function()
                if RC.ApplyInterfaceVisibility then
                    RC:ApplyInterfaceVisibility()
                end
            end
        )

        AddCheckbox(
            container,
            L["Hide Top Bar and Dropdown While Solo"],
            function() return RC.db.profile.hideLauncherWhenSolo == true end,
            function(value) RC.db.profile.hideLauncherWhenSolo = value end,
            function()
                if RC.ApplyInterfaceVisibility then
                    RC:ApplyInterfaceVisibility()
                end
            end
        )

        AddCheckbox(
            container,
            L["Show Blizzard Raid Tools"],
            function() return RC.db.profile.hideBlizzardRaidControl ~= true end,
            function(value)
                RC.db.profile.hideBlizzardRaidControl = not value
            end,
            function()
                if RC.ApplyBlizzardRaidControlVisibility then
                    RC:ApplyBlizzardRaidControlVisibility()
                end
            end
        )

        AddSpacer(container, 10)
        AddSection(container, L["Marker Clicks"], L["How the marker icons behave, in the dropdown and on the action strip alike."])

        AddCheckbox(
            container,
            L["Enable Target Marker Clicks"],
            function() return RC.db.profile.enableTargetMarkers ~= false end,
            function(value) RC.db.profile.enableTargetMarkers = value end,
            RefreshActionSurfaces
        )

        AddCheckbox(
            container,
            L["Enable World Marker Modifier Clicks"],
            function() return RC.db.profile.enableWorldMarkers ~= false end,
            function(value) RC.db.profile.enableWorldMarkers = value end,
            RefreshActionSurfaces
        )

        AddDropdown(
            container,
            L["World Marker Modifier"],
            {
                SHIFT = L["Shift"],
                CTRL = L["Ctrl"],
                ALT = L["Alt"],
            },
            function() return RC.db.profile.worldMarkerModifier or "SHIFT" end,
            function(value)
                RC.db.profile.worldMarkerModifier = value or "SHIFT"
                RC.db.profile.cycleMarkerModifier = value or "SHIFT"
            end,
            RefreshActionSurfaces
        )

        self.layoutLockCheckbox = nil
        self.layoutModeActionButton = nil
        self:RefreshLayoutModeControls()

    elseif subTab == "buttons" then
        AddSection(container, L["Dropdown Buttons"], L["Pick which actions show in the dropdown. Action Strip has separate controls on its own tab."])

        local buttonOptions = {
            { label = L["Ready Check"], key = "showReadyButton" },
            { label = L["Pull Timer"], key = "showPullButton" },
            { label = L["Convert Group"], key = "showConvertButton" },
            { label = L["Difficulty"], key = "showDifficultyButton" },
            { label = L["Invite Guild"], key = "showInviteButton" },
            { label = L["Disband"], key = "showDisbandButton" },
            { label = L["Screenshot"], key = "showScreenshotButton" },
        }

        for _, option in ipairs(buttonOptions) do
            AddCheckbox(
                container,
                option.label,
                function() return RC.db.profile[option.key] ~= false end,
                function(value)
                    RC.db.profile[option.key] = value and true or false
                end,
                RefreshActionSurfaces
            )
        end

        AddSpacer(container, 10)
        AddSection(container, L["Dropdown Markers"], L["Show or hide the marker row in the dropdown. Click behavior is on the General tab."])

        AddCheckbox(
            container,
            L["Dropdown Marker Icons"],
            function()
                if RC.db.profile.showDropdownMarkers ~= nil then
                    return RC.db.profile.showDropdownMarkers ~= false
                end
                return not RC.db.profile.hideMarkers
            end,
            function(value)
                RC.db.profile.showDropdownMarkers = value and true or false
            end,
            RefreshActionSurfaces
        )

        AddSpacer(container, 10)
        AddSection(container, L["Role Display"], L["Role-count display under the dropdown actions."])

        AddCheckbox(
            container,
            L["Show Role Counts in Dropdown"],
            function() return not RC.db.profile.hideRoles end,
            function(value)
                RC.db.profile.hideRoles = not value
                RC:RefreshLayout()
            end
        )
    else
        AddSection(container, L["Action Strip"], L["Quick action bar visibility and mouseover behavior."])

        AddCheckbox(
            container,
            L["Enable Action Strip"],
            function() return RC.db.profile.showActionStrip end,
            function(value) RC.db.profile.showActionStrip = value end,
            function()
                local actionStrip = RC:GetModule("ActionStrip", true)
                if actionStrip and actionStrip.UpdateVisibility then
                    actionStrip:UpdateVisibility()
                end
            end
        )

        AddCheckbox(
            container,
            L["Show on Mouseover Only"],
            function() return RC.db.profile.actionStripMouseover end,
            function(value) RC.db.profile.actionStripMouseover = value end,
            function()
                local actionStrip = RC:GetModule("ActionStrip", true)
                if actionStrip and actionStrip.RefreshMouseoverFade then
                    actionStrip:RefreshMouseoverFade()
                end
            end
        )

        AddSpacer(container, 10)
        AddSection(container, L["Action Strip Layout"], L["Control marker order, row style, and compact sizing."])

        AddLivePercentSlider(
            container,
            L["Action Strip Scale (%)"],
            50,
            200,
            1,
            function() return (RC.db.profile.actionStripScale or 1) * 100 end,
            function(value)
                local actionStrip = RC:GetModule("ActionStrip", true)
                if actionStrip and actionStrip.UpdateScale then
                    RC.db.profile.actionStripScale = actionStrip:UpdateScale(value / 100) or (value / 100)
                else
                    RC.db.profile.actionStripScale = value / 100
                end
            end
        )

        AddDropdown(
            container,
            L["Layout"],
            {
                single = L["Single Line"],
                two_rows = L["Balanced 2 Lines"],
                markers_row = L["Markers Separate Row"],
            },
            function() return RC.db.profile.actionStripLayout or "single" end,
            function(value)
                RC.db.profile.actionStripLayout = value or "single"
            end,
            RefreshActionSurfaces
        )

        AddDropdown(
            container,
            L["Marker Position"],
            {
                first = L["Markers First"],
                last = L["Markers Last"],
            },
            function() return RC.db.profile.actionStripMarkerPosition or "first" end,
            function(value)
                RC.db.profile.actionStripMarkerPosition = value or "first"
            end,
            RefreshActionSurfaces
        )

        AddSlider(
            container,
            L["Button Width"],
            42,
            90,
            1,
            function() return RC.db.profile.actionStripButtonWidth or 54 end,
            function(value)
                RC.db.profile.actionStripButtonWidth = math.floor((tonumber(value) or 54) + 0.5)
                RefreshActionSurfaces()
            end,
            RefreshActionSurfaces
        )

        AddSlider(
            container,
            L["Button Height"],
            18,
            34,
            1,
            function() return RC.db.profile.actionStripButtonHeight or 22 end,
            function(value)
                RC.db.profile.actionStripButtonHeight = math.floor((tonumber(value) or 22) + 0.5)
                RefreshActionSurfaces()
            end,
            RefreshActionSurfaces
        )

        AddSlider(
            container,
            L["Marker Size"],
            18,
            34,
            1,
            function() return RC.db.profile.actionStripMarkerSize or 24 end,
            function(value)
                RC.db.profile.actionStripMarkerSize = math.floor((tonumber(value) or 24) + 0.5)
                RefreshActionSurfaces()
            end,
            RefreshActionSurfaces
        )

        AddSpacer(container, 10)
        AddSection(container, L["Action Strip Buttons"], L["Choose exactly which buttons appear on the strip. These do not affect the dropdown."])

        local stripOptions = {
            { label = L["Ready Check"], key = "actionStripShowReady" },
            { label = L["Pull Timer"], key = "actionStripShowPull" },
            { label = L["Convert Group"], key = "actionStripShowConvert" },
            { label = L["Difficulty"], key = "actionStripShowDifficulty" },
            { label = L["Invite Guild"], key = "actionStripShowInvite" },
            { label = L["Disband"], key = "actionStripShowDisband" },
            { label = L["Screenshot"], key = "actionStripShowScreenshot" },
        }

        for _, option in ipairs(stripOptions) do
            AddCheckbox(
                container,
                option.label,
                function() return RC.db.profile[option.key] ~= false end,
                function(value)
                    RC.db.profile[option.key] = value and true or false
                end,
                RefreshActionSurfaces
            )
        end

        AddButton(container, L["Show All Strip Buttons"], function()
            RC.db.profile.showActionStrip = true
            RC.db.profile.showActionStripMarkers = true
            for _, option in ipairs(stripOptions) do
                RC.db.profile[option.key] = true
            end
            RefreshActionSurfaces()
            self:SelectTab("interface")
        end)

        AddButton(container, L["Hide All Strip Buttons"], function()
            for _, option in ipairs(stripOptions) do
                RC.db.profile[option.key] = false
            end
            RefreshActionSurfaces()
            self:SelectTab("interface")
        end, true)

        AddSpacer(container, 10)
        AddSection(container, L["Action Strip Markers"], L["Show or hide the marker icons on the action strip. Click behavior is on the General tab."])

        AddCheckbox(
            container,
            L["Show Marker Icons"],
            function()
                if RC.db.profile.showActionStripMarkers ~= nil then
                    return RC.db.profile.showActionStripMarkers ~= false
                end
                return not RC.db.profile.hideMarkers
            end,
            function(value)
                RC.db.profile.showActionStripMarkers = value and true or false
            end,
            RefreshActionSurfaces
        )

        AddButton(container, L["Marker Bar Preset"], function()
            RC.db.profile.showActionStrip = true
            RC.db.profile.showActionStripMarkers = true
            RC.db.profile.actionStripShowReady = false
            RC.db.profile.actionStripShowPull = false
            RC.db.profile.actionStripShowConvert = false
            RC.db.profile.actionStripShowDifficulty = false
            RC.db.profile.actionStripShowInvite = false
            RC.db.profile.actionStripShowDisband = false
            RC.db.profile.actionStripShowScreenshot = false
            RefreshActionSurfaces()
            self:SelectTab("interface")
        end)

    end
end

function Settings:BuildScreenshot(container)
    local subTab = DrawSubTabs(self, container, "screenshot", {
        { key = "quality", label = L["Quality"] },
        { key = "resolution", label = L["Resolution"] },
    }, "quality")

    if subTab == "quality" then
    AddSection(container, L["Screenshot Quality"], L["Configure the Shot button and its high-quality capture warning."])

    AddCheckbox(
        container,
        L["Confirm High Quality Screenshot"],
        function() return RC.db.profile.screenshotConfirmHighQuality ~= false end,
        function(value) RC.db.profile.screenshotConfirmHighQuality = value end
    )

    AddCheckbox(
        container,
        L["Apply Max Graphics"],
        function() return RC.db.profile.screenshotApplyMaxGraphics ~= false end,
        function(value) RC.db.profile.screenshotApplyMaxGraphics = value end
    )

    AddCheckbox(
        container,
        L["Hide UI During Screenshot"],
        function() return RC.db.profile.screenshotHideUI ~= false end,
        function(value) RC.db.profile.screenshotHideUI = value end
    )

    AddDropdown(
        container,
        L["Screenshot Format"],
        {
            jpg = "JPG",
            tga = "TGA",
        },
        function() return RC.db.profile.screenshotFormat or "jpg" end,
        function(value) RC.db.profile.screenshotFormat = value or "jpg" end
    )

    AddSlider(
        container,
        L["Screenshot Quality"],
        1, 10, 1,
        function() return RC.db.profile.screenshotQuality or 10 end,
        function(value) RC.db.profile.screenshotQuality = value end
    )

    AddSlider(
        container,
        L["Render Scale"],
        50, 300, 10,
        function() return math.floor((RC.db.profile.screenshotRenderScale or 2) * 100 + 0.5) end,
        function(value) RC.db.profile.screenshotRenderScale = value / 100 end
    )

    AddSlider(
        container,
        L["Screenshot Delay"],
        1, 50, 1,
        function() return math.floor((RC.db.profile.screenshotDelay or 1) * 10 + 0.5) end,
        function(value) RC.db.profile.screenshotDelay = value / 10 end
    )
        return
    end

    AddSection(container, L["Screenshot Size"], L["Choose the saved resolution preset or type a custom override."])

    -- The preset, the button and the override box all change the same size;
    -- keep the other two controls showing what was actually saved.
    local sizePresetDropdown, sizeOverrideBox
    local function RefreshSizeControls()
        if sizePresetDropdown and sizePresetDropdown.SetValue then
            sizePresetDropdown:SetValue(RC.db.profile.screenshotSizePreset or "3840x2160")
        end
        if sizeOverrideBox and sizeOverrideBox.SetText then
            sizeOverrideBox:SetText(RC.db.profile.screenshotSizeOverride or "3840x2160")
        end
    end

    sizePresetDropdown = AddDropdown(
        container,
        L["Screenshot Size Preset"],
        {
            ["1920x1080"] = L["1080p - 1920x1080"],
            ["2560x1440"] = L["1440p - 2560x1440"],
            ["3440x1440"] = L["Ultrawide - 3440x1440"],
            ["3840x2160"] = L["4K - 3840x2160"],
            ["5120x2880"] = L["5K - 5120x2880"],
            current = L["Current Resolution"],
            custom = L["Custom"],
        },
        function() return RC.db.profile.screenshotSizePreset or "3840x2160" end,
        function(value)
            local screenshot = RC:GetModule("Screenshot", true)
            if screenshot and screenshot.SetSizePreset and value ~= "custom" then
                screenshot:SetSizePreset(value)
            else
                RC.db.profile.screenshotSizePreset = "custom"
            end
        end,
        function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0, RefreshSizeControls)
            else
                RefreshSizeControls()
            end
        end
    )

    AddButton(container, L["Use Current Resolution"], function()
        local screenshot = RC:GetModule("Screenshot", true)
        if screenshot and screenshot.GetCurrentResolutionString then
            local current = screenshot:GetCurrentResolutionString()
            if current then
                RC.db.profile.screenshotSizePreset = "current"
                RC.db.profile.screenshotSizeOverride = current
                RC:Print(string.format(L["Screenshot size set to current resolution: %s"], current))
                RefreshSizeControls()
            else
                RC:ShowError(L["Could not detect current resolution."])
            end
        end
    end)

    sizeOverrideBox = AddEditBox(
        container,
        L["Screenshot Size Override"],
        function() return RC.db.profile.screenshotSizeOverride or "3840x2160" end,
        function(value)
            value = tostring(value or "")
            RC.db.profile.screenshotSizeOverride = value ~= "" and value or "3840x2160"
            RC.db.profile.screenshotSizePreset = "custom"
            if sizePresetDropdown and sizePresetDropdown.SetValue then
                sizePresetDropdown:SetValue("custom")
            end
        end
    )
end

function Settings:BuildAppearance(container)
    local subTab = DrawSubTabs(self, container, "appearance", {
        { key = "theme", label = L["Theme"] },
        { key = "surfaces", label = L["Surfaces"] },
        { key = "text", label = L["Fonts"] },
        { key = "scaling", label = L["Scaling"] },
        { key = "profiles", label = L["Profiles"] },
    }, "theme")

    if subTab == "theme" then
        AddSection(container, L["Theme Presets"], L["Instant polished palettes for the control panel."])

        local presetActions = {}
        for _, preset in ipairs(THEME_PRESETS) do
            local selectedPreset = preset
            table.insert(presetActions, {
                text = selectedPreset.label,
                width = RC:IsShadowsteelTheme() and 118 or 132,
                onClick = function()
                    ApplyThemePreset(selectedPreset)
                end,
            })
        end
        AddActionToolbar(container, presetActions, { align = "left", compact = true })

        AddSpacer(container, 8)
        AddSection(container, L["Theme Accent"], L["Choose a custom accent or follow the player's class color."])

        AddCheckbox(
            container,
            L["Use Player Class Color"],
            function() return RC.db.profile.useClassColor and true or false end,
            function(value) RC.db.profile.useClassColor = value and true or false end,
            function()
                RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
            end
        )

        AddColorSwatch(
            container,
            L["Custom Accent Color"],
            function()
                local color = RC.db.profile.accentColor or { r = 0.10, g = 0.78, b = 0.66 }
                return color.r, color.g, color.b
            end,
            function(r, g, b)
                RC.db.profile.accentColor = { r = r, g = g, b = b, a = 1 }
                RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
                self:QueueThemePickerRefresh()
            end
        )

    elseif subTab == "surfaces" then
        AddSection(container, L["Surface Colors"], L["Set every major interface layer independently."])

        AddColorSwatch(
            container,
            L["Main Panel Color"],
            function()
                local r, g, b = RC:GetBackgroundColor()
                return r, g, b
            end,
            function(r, g, b)
                local current = RC.db.profile.backgroundColor or { a = 0.98 }
                RC.db.profile.backgroundColor = { r = r, g = g, b = b, a = current.a or 0.98 }
                RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
                self:QueueThemePickerRefresh()
            end
        )

        AddColorSwatch(
            container,
            L["Header / Sidebar Color"],
            function()
                local color = RC.db.profile.headerColor or RC.Config.HeaderBg
                return color.r, color.g, color.b
            end,
            function(r, g, b)
                local current = RC.db.profile.headerColor or { a = 0.98 }
                RC.db.profile.headerColor = { r = r, g = g, b = b, a = current.a or 0.98 }
                RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
                self:QueueThemePickerRefresh()
            end
        )

        AddColorSwatch(
            container,
            L["Section / Row Color"],
            function()
                local color = RC.db.profile.surfaceColor or RC.Config.SurfaceBg
                return color.r, color.g, color.b
            end,
            function(r, g, b)
                local current = RC.db.profile.surfaceColor or { a = 0.62 }
                RC.db.profile.surfaceColor = { r = r, g = g, b = b, a = current.a or 0.62 }
                RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
                self:QueueThemePickerRefresh()
            end
        )

        AddColorSwatch(
            container,
            L["Controls / Inputs Color"],
            function()
                local color = RC.db.profile.controlColor or RC.Config.ButtonBg
                return color.r, color.g, color.b
            end,
            function(r, g, b)
                local current = RC.db.profile.controlColor or { a = 0.90 }
                RC.db.profile.controlColor = { r = r, g = g, b = b, a = current.a or 0.90 }
                RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
                self:QueueThemePickerRefresh()
            end
        )

        AddColorSwatch(
            container,
            L["Border Color"],
            function()
                local r, g, b = RC:GetBorderColor()
                return r, g, b
            end,
            function(r, g, b)
                local current = RC.db.profile.borderColor or { a = 0.82 }
                RC.db.profile.borderColor = { r = r, g = g, b = b, a = current.a or 0.82 }
                RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
                self:QueueThemePickerRefresh()
            end
        )

        AddSpacer(container, 12)
        AddSection(container, L["Surface Opacity"], L["Make each interface layer solid or see-through."])

        local theme = RC:GetThemeDefinition(RC.db.profile.theme)
        local themeColors = theme and theme.colors or {}
        local surfaceDefaults = {
            backgroundColor = themeColors.background or { r = 0.050, g = 0.070, b = 0.090 },
            headerColor = themeColors.header or { r = 0.035, g = 0.052, b = 0.068 },
            surfaceColor = themeColors.surface or { r = 0.061, g = 0.095, b = 0.120 },
            controlColor = themeColors.control or { r = 0.075, g = 0.113, b = 0.141 },
            borderColor = themeColors.border or { r = 0.105, g = 0.145, b = 0.170 },
        }

        local function AddSurfaceOpacity(label, key, fallback)
            AddPercentSlider(
                container,
                label,
                key == "borderColor" and 1 or 10, 100, 5,
                function()
                    local color = RC.db.profile[key]
                    return ((color and color.a) or fallback) * 100
                end,
                function(value)
                    local defaults = surfaceDefaults[key] or { r = 0.12, g = 0.12, b = 0.12 }
                    local current = RC.db.profile[key] or {
                        r = defaults.r,
                        g = defaults.g,
                        b = defaults.b,
                    }
                    current.a = value / 100
                    RC.db.profile[key] = current
                end,
                function()
                    RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
                end
            )
        end

        AddSurfaceOpacity(L["Main Panel Opacity (%)"], "backgroundColor", 0.98)
        AddSurfaceOpacity(L["Header / Sidebar Opacity (%)"], "headerColor", 0.98)
        AddSurfaceOpacity(L["Section / Row Opacity (%)"], "surfaceColor", 0.62)
        AddSurfaceOpacity(L["Controls / Inputs Opacity (%)"], "controlColor", 0.90)
        AddSurfaceOpacity(L["Border Opacity (%)"], "borderColor", 0.82)

    elseif subTab == "text" then
        AddSection(container, L["Fonts"], L["Select the font used across RaidControl."])

        local fontList = {}
        local LSM = LibStub("LibSharedMedia-3.0")
        for _, name in ipairs(LSM:List("font")) do
            fontList[name] = name
        end

        AddDropdown(
            container,
            L["Global Font"],
            fontList,
            function() return RC.db.profile.fontName end,
            function(value) RC.db.profile.fontName = value end,
            function()
                RC:UpdateAllFonts()
            end
        )

        AddSpacer(container, 12)
        AddSection(container, L["Text Colors"], L["Tune headings, controls, and general labels."])

        AddColorSwatch(
            container,
            L["Title Text Color"],
            function()
                local r, g, b = RC:GetTitleColor()
                return r, g, b
            end,
            function(r, g, b)
                RC.db.profile.titleTextColor = { r = r, g = g, b = b }
                RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
                self:QueueThemePickerRefresh()
            end
        )

        AddColorSwatch(
            container,
            L["Button Text Color"],
            function()
                local r, g, b = RC:GetButtonTextColor()
                return r, g, b
            end,
            function(r, g, b)
                RC.db.profile.buttonTextColor = { r = r, g = g, b = b }
                RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
                self:QueueThemePickerRefresh()
            end
        )

        AddColorSwatch(
            container,
            L["General Text Color"],
            function()
                local r, g, b = RC:GetGeneralTextColor()
                return r, g, b
            end,
            function(r, g, b)
                RC.db.profile.generalTextColor = { r = r, g = g, b = b }
                RC:ApplyTheme(RC.db.profile.theme or "Starforge", true, false)
                self:QueueThemePickerRefresh()
            end
        )
    elseif subTab == "scaling" then
        AddSection(container, L["Scale and Opacity"], L["Keep frame positions stable while scaling."])

        AddPercentSlider(
            container,
            L["Menu Alpha (%)"],
            10, 100, 5,
            function() return (RC.db.profile.alpha or 1) * 100 end,
            function(value) RC.db.profile.alpha = value / 100 end,
            function(value)
                local alpha = value / 100
                if RC.Menu then RC.Menu:SetAlpha(RC.IsMenuOpen and alpha or 0) end
                if RC.TopBar then RC.TopBar:SetAlpha(alpha) end
            end
        )

        AddLivePercentSlider(
            container,
            L["Top Tab Scale (%)"],
            50, 200, 1,
            function() return (RC.db.profile.topBarScale or RC.db.profile.launcherScale or RC.db.profile.scale or 1) * 100 end,
            function(value)
                local scale = value / 100
                RC.db.profile.topBarScale = scale
                RC.db.profile.launcherScale = scale
                RC.db.profile.scale = scale -- keep legacy key in sync
            end,
            function(value)
                RC:ApplyTopBarScale(value / 100)
            end
        )

        AddLivePercentSlider(
            container,
            L["Dropdown Panel Scale (%)"],
            50, 200, 1,
            function() return (RC.db.profile.menuScale or RC.db.profile.launcherScale or RC.db.profile.scale or 1) * 100 end,
            function(value)
                RC.db.profile.menuScale = value / 100
            end,
            function(value)
                RC:ApplyMenuScale(value / 100)
            end
        )

        AddLivePercentSlider(
            container,
            L["Settings Window Scale (%)"],
            50, 200, 1,
            function() return GetWorkspaceScale() * 100 end,
            function(value) RC.db.profile.workspaceScale = value / 100 end,
            function(value)
                ApplyWorkspaceScale(self, value / 100)
            end
        )

    else
        AddSection(container, L["Profile Transfer"], L["Export or import the current RaidControl profile as a text string."])

        AddButton(container, L["Export Current Profile"], function()
            local serializer = LibStub("AceSerializer-3.0", true)
            if not serializer then
                RC:ShowError(L["AceSerializer is unavailable."])
                return
            end
            local exportProfile, exportError = BuildProfileTransferTable()
            if not exportProfile then
                RC:ShowError(exportError or L["Unable to export RaidControl profile."])
                return
            end
            local payload = {
                type = "RaidControlProfile",
                schema = PROFILE_TRANSFER_SCHEMA,
                version = GetRaidControlVersion(),
                interface = RC.SUPPORTED_INTERFACE,
                profile = exportProfile,
            }
            self.profileTransferString = PROFILE_TRANSFER_MAGIC .. serializer:Serialize(payload)
            RC:Print(L["Profile string exported. Copy it from the field below."])
            self:SelectTab("appearance")
        end)

        AddButton(container, L["Import Into Current Profile"], function()
            local serializer = LibStub("AceSerializer-3.0", true)
            if not serializer then
                RC:ShowError(L["AceSerializer is unavailable."])
                return
            end
            local text = TrimProfileTransferText(self.profileTransferString)
            if text:sub(1, #PROFILE_TRANSFER_MAGIC) ~= PROFILE_TRANSFER_MAGIC then
                RC:ShowError(L["That does not look like a RaidControl profile string."])
                return
            end
            local serializedPayload = text:sub(#PROFILE_TRANSFER_MAGIC + 1)
            if serializedPayload == "" then
                RC:ShowError(L["That profile string is empty."])
                return
            end
            local ok, payload = serializer:Deserialize(serializedPayload)
            if not ok then
                RC:ShowError(L["That profile string could not be decoded."])
                return
            end
            local importedProfile, importError = ValidateProfileTransferPayload(payload)
            if not importedProfile then
                RC:ShowError(importError or L["That profile string is not supported."])
                return
            end
            ApplyImportedProfile(importedProfile)
            RC.db.profile.theme = RC.db.profile.theme or "Starforge"
            RefreshAfterProfileImport(self)
            RC:Print(L["Imported RaidControl profile into the current profile."])
        end)

        Widgets:AddTextField(
            container,
            L["Profile String"],
            function() return self.profileTransferString or "" end,
            function(value) self.profileTransferString = value end
        )
    end
end

function Settings:BuildMarkers(container)
    AddSection(container, L["Markers Moved"], L["Marker controls now live beside the surfaces they affect."])
    AddActionToolbar(container, {
        {
            text = L["Dropdown Buttons"],
            onClick = function()
                self.subTabState = self.subTabState or {}
                self.subTabState.interface = "buttons"
                self:SelectTab("interface")
            end,
        },
        {
            text = L["Action Strip"],
            onClick = function()
                self.subTabState = self.subTabState or {}
                self.subTabState.interface = "action_strip"
                self:SelectTab("interface")
            end,
        },
    })
end

function Settings:BuildTankSettings(container, subTab)
    local tankAssist = RC:GetModule("TankAssist", true)
    local profile = RC.db.profile

    local function RefreshAppearance()
        if tankAssist and tankAssist.ApplyFrameSettings then
            tankAssist:ApplyFrameSettings()
        end
    end

    local function RefreshRuntime()
        if tankAssist and tankAssist.RefreshRuntimeSettings then
            tankAssist:RefreshRuntimeSettings()
        end
        RefreshAppearance()
    end

    local function RebuildPage()
        local function Rebuild()
            if self.selectedTab == "tank" then
                self:SelectTab("tank")
            end
        end
        if C_Timer and C_Timer.After then
            C_Timer.After(0, Rebuild)
        else
            Rebuild()
        end
    end

    local function Read(key, fallback)
        local value = profile[key]
        if value == nil then
            return fallback
        end
        return value
    end

    local function Toggle(label, key, fallback, refresh)
        AddCheckbox(container, label,
            function() return Read(key, fallback) end,
            function(value) profile[key] = value end,
            refresh or RefreshAppearance)
    end

    local function Number(label, key, fallback, low, high, step, refresh)
        AddSlider(container, label, low, high, step,
            function() return tonumber(Read(key, fallback)) or fallback end,
            function(value) profile[key] = value end,
            refresh or RefreshAppearance)
    end

    local function Percent(label, key, fallback, low, high)
        AddSlider(container, label, low or 0, high or 100, 1,
            function() return math.floor((tonumber(Read(key, fallback)) or fallback) * 100 + 0.5) end,
            function(value) profile[key] = value / 100 end,
            RefreshAppearance)
    end

    local function Choice(label, key, fallback, options, rebuild, order)
        AddDropdown(container, label, options,
            function() return Read(key, fallback) end,
            function(value) profile[key] = value or fallback end,
            function()
                RefreshAppearance()
                if rebuild then RebuildPage() end
            end, order)
    end

    local function Color(label, key, fallback)
        AddColorSwatch(container, label,
            function()
                local color = Read(key, fallback)
                return color.r, color.g, color.b
            end,
            function(r, g, b)
                profile[key] = { r = r, g = g, b = b }
                RefreshAppearance()
            end)
    end

    local iconList = tankAssist and tankAssist.GetIconList and tankAssist:GetIconList() or {
        skull = L["Skull"], cross = L["Cross"], square = L["Square"], moon = L["Moon"],
        triangle = L["Triangle"], diamond = L["Diamond"], circle = L["Circle"], star = L["Star"],
        shield = L["Shield"], warning = L["Warning"],
    }

    if subTab == "bone" then
        local boneShield = RC:GetModule("BoneShield", true)
        local function RefreshBone()
            if boneShield and boneShield.Refresh then boneShield:Refresh() end
        end
        AddSection(container, L["Bone Shield"], L["Blood Death Knight only. Stacks on top, time left in the centre. In combat the count is copied from your Cooldown Manager: keep Bone Shield and Ossuary in its tracked buffs."])
        Toggle(L["Show Bone Shield"], "boneShieldEnabled", true, RefreshBone)
        Number(L["Icon Size"], "boneShieldIconSize", 36, 20, 96, 1, RefreshBone)
        Number(L["Stack Count Size"], "boneShieldFontSize", 18, 8, 40, 1, RefreshBone)
        Toggle(L["Show Time Left"], "boneShieldShowTime", true, RefreshBone)
        AddSlider(container, L["Time Left Size (% of stack count)"], 50, 150, 5,
            function() return math.floor((tonumber(Read("boneShieldTimerScale", 0.9)) or 0.9) * 100 + 0.5) end,
            function(value) profile.boneShieldTimerScale = value / 100 end, RefreshBone)
        local boneFonts = { default = L["Same as RaidControl"] }
        local boneFontOrder = { "default" }
        local LSM = LibStub("LibSharedMedia-3.0")
        for _, name in ipairs(LSM:List("font")) do
            boneFonts[name] = name
            boneFontOrder[#boneFontOrder + 1] = name
        end
        AddDropdown(container, L["Font"], boneFonts,
            function() return Read("boneShieldFont", "default") end,
            function(value) profile.boneShieldFont = value or "default" end,
            RefreshBone, boneFontOrder)
        Toggle(L["Thick Outline"], "boneShieldThickOutline", true, RefreshBone)
        AddSlider(container, L["Darken Icon (%)"], 0, 80, 5,
            function() return math.floor((tonumber(Read("boneShieldDarken", 0.35)) or 0.35) * 100 + 0.5) end,
            function(value) profile.boneShieldDarken = value / 100 end, RefreshBone)
        Toggle(L["Hide Bone Shield and Ossuary in the Cooldown Manager"], "boneShieldHideInCDM", true, RefreshBone)

        AddSection(container, L["Bone Shield Warnings"], L["Below 5 stacks uses Ossuary (up at 5+ stacks), because the game hides the number in combat."])
        Toggle(L["Blink and Warn Below 5 Stacks"], "boneShieldLowWarning", true, RefreshBone)
        Toggle(L["Warn Before It Runs Out"], "boneShieldExpiryWarning", true, RefreshBone)
        Number(L["Highlight at Seconds Left"], "boneShieldGlowAt", 8, 2, 20, 1, RefreshBone)
        Number(L["Sound at Seconds Left (0 = off)"], "boneShieldSoundAt", 5, 0, 15, 1, RefreshBone)
        Toggle(L["Show a Red 0 When It Drops in Combat"], "boneShieldDownWarning", true, RefreshBone)
        Toggle(L["Sound When It Drops"], "boneShieldSoundOnDrop", true, RefreshBone)
        Toggle(L["Sound When It Comes Back"], "boneShieldSoundOnGain", false, RefreshBone)
        AddDropdown(container, L["Warning Sound"], { voice = L["Voice (Text to Speech)"], sound = L["Raid Warning"] },
            function() return Read("boneShieldAlertStyle", "voice") end,
            function(value) profile.boneShieldAlertStyle = value or "voice" end,
            RefreshBone, { "voice", "sound" })
        AddButton(container, L["Test Warning"], function()
            if boneShield and boneShield.Test then boneShield:Test() end
        end)

        AddSection(container, L["Bone Shield Position"], L["Drag it in /rc layout, or stick it to a Cooldown Manager row. Other: type the name of any frame (use /fstack to find it)."])
        AddDropdown(container, L["Attach To"], {
            none = L["Nothing (move it yourself)"], essential = L["Essential cooldowns row"],
            utility = L["Utility cooldowns row"], buffs = L["Buff icons row"], custom = L["Other frame (by name)"],
        }, function() return Read("boneShieldAttach", "none") end,
            function(value) profile.boneShieldAttach = value or "none" end,
            function() RefreshBone() RebuildPage() end, { "none", "essential", "utility", "buffs", "custom" })
        if Read("boneShieldAttach", "none") ~= "none" then
            if Read("boneShieldAttach", "none") == "custom" then
                AddEditBox(container, L["Frame Name"],
                    function() return profile.boneShieldAttachFrame or "" end,
                    function(value)
                        profile.boneShieldAttachFrame = (value or ""):match("^%s*(.-)%s*$")
                        RefreshBone()
                    end)
            end
            AddDropdown(container, L["Side"], { LEFT = L["Left"], RIGHT = L["Right"], ABOVE = L["Above"], BELOW = L["Below"] },
                function() return Read("boneShieldAttachSide", "LEFT") end,
                function(value) profile.boneShieldAttachSide = value or "LEFT" end,
                RefreshBone, { "LEFT", "RIGHT", "ABOVE", "BELOW" })
            Number(L["Gap (pixels)"], "boneShieldAttachGap", 1, -10, 40, 1, RefreshBone)
        end
        AddButton(container, L["Reset Position"], function()
            if boneShield and boneShield.ResetPosition then boneShield:ResetPosition() end
            RebuildPage()
        end)
        return
    end

    if subTab == "overview" then
        AddSection(container, L["Tank Assist"], L["Personal taunt and movement instructions. Set up the basics here; use the tabs above to fine-tune each part."])
        Toggle(L["Enable Tank Assist"], "enableTankAssist", false, function()
            if tankAssist and tankAssist.ApplyEnabledState then
                tankAssist:ApplyEnabledState()
            end
        end)
        Toggle(L["Only Run While Tanking"], "tankAssistTanksOnly", true, RefreshRuntime)
        Toggle(L["Raid Boss Encounters Only"], "tankAssistEncounterOnly", true, RefreshRuntime)
        Toggle(L["Mythic+ Tank-Buster Warnings"], "tankAssistEnableDungeonBusters", true, RefreshRuntime)

        AddSection(container, L["Quick Setup"], L["Choose a starting layout, then customize it in Warnings, Timer Bars, and Sounds. Your individual sound selections are kept."])
        local function Preset(style, sound)
            profile.tankAssistDisplayStyle = style
            profile.tankAssistShowVisual = true
            profile.tankAssistShowTimerBars = style == "panel"
            profile.tankAssistShowDetail = style == "panel"
            profile.tankAssistSoundEnabled = sound
            RefreshRuntime()
            RebuildPage()
        end
        AddActionToolbar(container, {
            { text = L["Clean HUD"], onClick = function() Preset("panel", true) end },
            { text = L["Text + Sound"], onClick = function() Preset("text", true) end },
            { text = L["Silent Text"], onClick = function() Preset("text", false) end },
        })

        AddSection(container, L["Position and Size"], L["Preview the layout, unlock the frames, then drag the warning and timer bars separately. These controls apply to both displays."])
        Toggle(L["Lock Tank Frames"], "tankAssistFramesLocked", true)
        Percent(L["Display Scale (%)"], "tankAssistFrameScale", 1, 50, 200)
        Percent(L["Display Opacity (%)"], "tankAssistFrameAlpha", 1, 20, 100)
        AddActionToolbar(container, {
            { text = L["Preview Layout"], onClick = function()
                if tankAssist and tankAssist.PreviewLayout then tankAssist:PreviewLayout() end
            end },
            { text = L["Hide Preview"], onClick = function()
                if tankAssist and tankAssist.HidePreview then tankAssist:HidePreview() end
            end },
            { text = L["Reset Positions"], onClick = function()
                if tankAssist and tankAssist.ResetFramePositions then tankAssist:ResetFramePositions() end
            end },
        })

        AddSection(container, L["Co-Tank"], L["Automatic detection uses the other tank in your group. Leave the override blank unless you want to track a specific player."])
        AddEditBox(container, L["Co-Tank Name Override"],
            function() return profile.tankAssistCoTankName or "" end,
            function(value)
                profile.tankAssistCoTankName = (value or ""):match("^%s*(.-)%s*$")
                if tankAssist and tankAssist.RefreshCoTank then tankAssist:RefreshCoTank() end
                RefreshRuntime()
            end)
        AddButton(container, L["Detect Co-Tank"], function()
            if tankAssist and tankAssist.RefreshCoTank then
                local _, name = tankAssist:RefreshCoTank()
                RC:Print(string.format(L["Tank Assist co-tank: %s"], name or L["not found"]))
            end
        end)
        return
    end

    if subTab == "warnings" then
        AddSection(container, L["Warning Types"], L["Choose the personal instructions you want. Turning off a type also disables its sound and upcoming timer bars."])
        Toggle(L["Taunt and Swap Warnings"], "tankAssistTauntEnabled", true, RefreshRuntime)
        Toggle(L["Movement Warnings"], "tankAssistMovementEnabled", true, RefreshRuntime)

        AddSection(container, L["On-Screen Warning"], L["Use a compact panel or text only. Sounds and upcoming timer bars have their own tabs and can be enabled independently."])
        Toggle(L["Show On-Screen Warnings"], "tankAssistShowVisual", true)
        Choice(L["Warning Style"], "tankAssistDisplayStyle", "panel", {
            panel = L["Compact Panel"], text = L["Text Only"],
        }, true, { "panel", "text" })
        Choice(L["Text Alignment"], "tankAssistTextAlign", "LEFT", {
            LEFT = L["Left"], CENTER = L["Center"],
        }, false, { "LEFT", "CENTER" })
        Number(L["Warning Width"], "tankAssistAlertWidth", 420, 260, 800, 10)
        Number(L["Warning Text Size"], "tankAssistAlertFontSize", 28, 14, 56, 1)
        Toggle(L["Show Detail Text"], "tankAssistShowDetail", true)
        Number(L["Detail Text Size"], "tankAssistDetailFontSize", 14, 9, 24, 1)
        Toggle(L["Show Mechanic Countdown"], "tankAssistShowTimer", true)
        if Read("tankAssistDisplayStyle", "panel") == "panel" then
            Toggle(L["Show Warning Icon"], "tankAssistShowIcon", true)
            Choice(L["Default Warning Icon"], "tankAssistAlertIcon", "skull", iconList)
            Percent(L["Panel Background Opacity (%)"], "tankAssistBackgroundAlpha", 0.88)
        end
        Number(L["Warning Duration (seconds)"], "tankAssistVisualDuration", 2.5, 1, 15, 0.5)

        AddSection(container, L["Warning Colors"], L["The same colors identify taunts and movement in both warnings and timer bars."])
        Color(L["Taunt / Swap Color"], "tankAssistTauntColor", { r = 1, g = 0.35, b = 0.2 })
        Color(L["Movement Color"], "tankAssistMovementColor", { r = 0.2, g = 0.8, b = 1 })

        AddSection(container, L["Warning Timing"], L["Lead time controls when an instruction appears before a known mechanic. Boss-specific movement requirements are safety minimums, so this setting can warn earlier but never later. Taunt calls still wait for the encounter's safe swap condition."])
        Number(L["Movement Lead (seconds)"], "tankAssistMovementLeadSeconds", 8, 4, 15, 1, RefreshRuntime)
        Number(L["Repeat Lockout (seconds)"], "tankAssistAlertCooldown", 6, 2, 30, 1, RefreshRuntime)

        AddSection(container, L["Try a Warning"], L["Trigger an example with your selected display and sound settings."])
        AddActionToolbar(container, {
            { text = L["Taunt Example"], onClick = function()
                if tankAssist and tankAssist.TestAlert then tankAssist:TestAlert() end
            end },
            { text = L["Movement Example"], onClick = function()
                if tankAssist and tankAssist.TestMovementAlert then tankAssist:TestMovementAlert() end
            end },
        })
        return
    end

    if subTab == "timers" then
        AddSection(container, L["Upcoming Mechanics"], L["Separate personal timer bars show only your upcoming taunts/swaps and movement when the encounter supplies safe timing. Ambiguous ownership stays hidden; follow the actual taunt warning for the final swap."])
        Toggle(L["Show Upcoming Timer Bars"], "tankAssistShowTimerBars", true)
        Toggle(L["Include Taunt / Swap Timers"], "tankAssistTimerTaunt", true)
        Toggle(L["Include Movement Timers"], "tankAssistTimerMovement", true)
        Number(L["Look Ahead (seconds)"], "tankAssistTimerHorizon", 30, 5, 120, 5)
        Number(L["Maximum Visible Bars"], "tankAssistTimerMaxBars", 3, 1, 6, 1)

        AddSection(container, L["Bar Layout"], L["Move the timer stack from Overview > Preview Layout. Scale and overall opacity are shared with the warning display."])
        Number(L["Bar Width"], "tankAssistTimerWidth", 360, 200, 700, 10)
        Number(L["Bar Height"], "tankAssistTimerHeight", 34, 22, 64, 1)
        Number(L["Bar Spacing"], "tankAssistTimerSpacing", 5, 0, 20, 1)
        Choice(L["Stack Direction"], "tankAssistTimerGrowth", "DOWN", {
            DOWN = L["Down"], UP = L["Up"],
        }, false, { "DOWN", "UP" })
        Number(L["Bar Text Size"], "tankAssistTimerFontSize", 15, 10, 24, 1)
        Percent(L["Bar Background Opacity (%)"], "tankAssistTimerBackgroundAlpha", 0.65)

        AddSection(container, L["Bar Content"], L["Keep only the information you want beside each countdown."])
        Toggle(L["Show Mechanic Icons"], "tankAssistTimerShowIcon", true)
        Toggle(L["Show Mechanic Labels"], "tankAssistTimerShowLabel", true)
        Toggle(L["Show Seconds Remaining"], "tankAssistTimerShowSeconds", true)
        AddButton(container, L["Preview Layout"], function()
            if tankAssist and tankAssist.PreviewLayout then tankAssist:PreviewLayout() end
        end)
        return
    end

    if subTab == "sounds" then
        local fallbackSounds = {
            voicepack = L["RaidControl Voice Pack"], custom = L["Custom Sound File"],
            tts = L["Blizzard TTS"], raid = L["Raid Warning"], ready = L["Ready Check"], bell = L["Bell"], none = L["None (Silent)"],
        }
        local fallbackOrder = { "voicepack", "custom", "tts", "raid", "ready", "bell", "none" }
        local soundList, soundOrder
        if tankAssist and tankAssist.GetSoundList then
            soundList, soundOrder = tankAssist:GetSoundList()
        else
            soundList, soundOrder = RC:GetSharedMediaSoundOptions(fallbackSounds, fallbackOrder)
        end
        local categorySounds, categoryOrder = {}, { "inherit" }
        for key, value in pairs(soundList or fallbackSounds) do categorySounds[key] = value end
        categorySounds.inherit = L["Use Shared Sound"]
        for _, key in ipairs(soundOrder or fallbackOrder) do categoryOrder[#categoryOrder + 1] = key end
        local channels = tankAssist and tankAssist.GetSoundChannelList and tankAssist:GetSoundChannelList() or {
            Master = L["Master"], SFX = L["Sound Effects"], Dialog = L["Dialog"], Ambience = L["Ambience"], Music = L["Music"],
        }
        local categoryChannels = { inherit = L["Use Shared Channel"] }
        for key, value in pairs(channels) do categoryChannels[key] = value end
        local channelOrder = { "Master", "SFX", "Dialog", "Ambience", "Music" }
        local categoryChannelOrder = { "inherit", "Master", "SFX", "Dialog", "Ambience", "Music" }

        local function SoundChoice(label, key, fallback, list, order)
            AddSoundDropdown(container, label, list,
                function() return Read(key, fallback) end,
                function(value) profile[key] = value or fallback end,
                RebuildPage, order)
        end
        local function CustomFile(label, key)
            AddEditBox(container, label,
                function() return profile[key] or "" end,
                function(value) profile[key] = (value or ""):match("^%s*(.-)%s*$") end)
        end

        AddSection(container, L["Sound Output"], L["Mute all Tank Assist audio without changing your chosen sounds. Each warning type below can also be set to None for a silent visual warning."])
        Toggle(L["Enable Tank Assist Sounds"], "tankAssistSoundEnabled", true, RefreshRuntime)
        Choice(L["Shared Sound Channel"], "tankAssistSoundChannel", "Master", channels, false, channelOrder)
        Number(L["TTS Volume (%)"], "tankAssistTtsVolume", 100, 0, 100, 5, RefreshRuntime)

        local categories = {
            { key = "taunt", prefix = "tankAssistTaunt", title = L["Taunt and Swap"], fallback = "voicepack" },
            { key = "movement", prefix = "tankAssistMovement", title = L["Movement"], fallback = "tts" },
        }
        for _, info in ipairs(categories) do
            local category = info.key
            local prefix = info.prefix
            AddSection(container, info.title, L["Choose a distinct cue and optional countdown ticks. Countdown timing uses the mechanic's known remaining time."])
            SoundChoice(L["Warning Sound"], prefix .. "Sound", info.fallback, categorySounds, categoryOrder)
            Choice(L["Sound Channel"], prefix .. "SoundChannel", "inherit", categoryChannels, false, categoryChannelOrder)
            if Read(prefix .. "Sound", info.fallback) == "custom" then
                CustomFile(L["Custom Sound File Path"], prefix .. "CustomSoundFile")
            end
            Toggle(L["Countdown Ticks"], prefix .. "CountdownEnabled", true, RefreshRuntime)
            Number(L["Count Down From (seconds)"], prefix .. "CountdownSeconds", 3, 1, 10, 1, RefreshRuntime)
            AddButton(container, string.format(L["Preview %s Sound"], info.title), function()
                if tankAssist and tankAssist.PreviewWarningSound then tankAssist:PreviewWarningSound(category) end
            end)
        end

        AddSection(container, L["Shared Sound"], L["Used only by warning types set to Use Shared Sound. Custom files use an existing WoW sound path, such as Interface\\AddOns\\MySounds\\taunt.ogg."])
        SoundChoice(L["Shared Warning Sound"], "tankAssistSound", "voicepack", soundList or fallbackSounds, soundOrder or fallbackOrder)
        if Read("tankAssistSound", "voicepack") == "custom" then
            CustomFile(L["Shared Custom Sound File Path"], "tankAssistCustomSoundFile")
        end
        return
    end

    AddSection(container, L["Encounter Rules"], L["Choose which supported encounter information Tank Assist uses for your warnings."])
    Toggle(L["Show Safe Stack Advisories"], "tankAssistUseAuraRules", true, RefreshRuntime)
    Toggle(L["Use Encounter Timeline Rules"], "tankAssistUseCastRules", true, RefreshRuntime)

    AddSection(container, L["Boss Overrides"], L["Select a boss to customize its swap instruction and icon. Reset Override restores that boss's supplied settings."])
    local bossList = tankAssist and tankAssist.GetBossList and tankAssist:GetBossList() or {}
    local selectedBoss = profile.tankAssistSelectedBoss or "nekzali"
    local selectedRule = tankAssist and tankAssist.GetRuleByKey and tankAssist:GetRuleByKey(selectedBoss)
    if selectedRule then
        selectedBoss = selectedRule.key
        profile.tankAssistSelectedBoss = selectedBoss
    end
    Choice(L["Boss"], "tankAssistSelectedBoss", selectedBoss, bossList, true)

    if selectedRule and tankAssist and tankAssist.GetRuleConfig then
        local bossConfig = tankAssist:GetRuleConfig(selectedRule)
        local defaultText = tankAssist.GetDefaultAlertText and tankAssist:GetDefaultAlertText(selectedRule)
            or selectedRule.tauntText or "TANK CHECK"
        AddCheckbox(container, L["Enable This Boss"],
            function() return bossConfig.enabled ~= false end,
            function(value) bossConfig.enabled = value end, RefreshRuntime)
        AddDropdown(container, L["Warning Icon"], iconList,
            function() return bossConfig.icon or profile.tankAssistAlertIcon or "skull" end,
            function(value)
                bossConfig.icon = value or profile.tankAssistAlertIcon or "skull"
                if tankAssist.ApplyAlertIcon then tankAssist:ApplyAlertIcon(selectedRule) end
            end)
        AddEditBox(container, L["Custom Swap Text"],
            function() return bossConfig.tauntText or defaultText end,
            function(value)
                value = (value or ""):match("^%s*(.-)%s*$")
                bossConfig.tauntText = value ~= "" and value or nil
            end)
        if selectedRule.swapEvery then
            AddSlider(container, L["Hits Before Swap Check"], 1, 6, 1,
                function() return bossConfig.swapEvery or selectedRule.swapEvery end,
                function(value) bossConfig.swapEvery = value end, RefreshRuntime)
        end
        AddActionToolbar(container, {
            { text = L["Boss Warning Example"], onClick = function()
                if tankAssist.TestAlert then tankAssist:TestAlert(selectedRule.key) end
            end },
            { text = L["Reset Override"], onClick = function()
                profile.tankAssistBossOverrides = profile.tankAssistBossOverrides or {}
                profile.tankAssistBossOverrides[selectedRule.key] = nil
                RefreshRuntime()
                RebuildPage()
            end },
        })
    end
end

function Settings:BuildReadyCheck(container)
    AddSection(container, L["Ready Check"], L["Ready responses, preparation issues, consumables and durability in one view."])

    local readyTracker = RC:GetModule("ReadyTracker", true)

    AddCheckbox(
        container,
        L["Enable Ready Check Tracker"],
        function() return RC.db.profile.enableReadyTracker end,
        function(value)
            RC.db.profile.enableReadyTracker = value
            if not value and readyTracker and readyTracker.HideReadyCheckFrame then
                readyTracker:HideReadyCheckFrame()
            end
        end
    )
    AddCheckbox(
        container,
        L["Announce Slackers"],
        function() return RC.db.profile.announceReadySlackers end,
        function(value) RC.db.profile.announceReadySlackers = value end
    )
    AddCheckbox(
        container,
        L["Whisper Slackers"],
        function() return RC.db.profile.whisperSlackers end,
        function(value) RC.db.profile.whisperSlackers = value end
    )
    AddCheckbox(
        container,
        L["Report to Chat"],
        function() return RC.db.profile.reportToChat end,
        function(value) RC.db.profile.reportToChat = value end
    )
    AddCheckbox(
        container,
        L["Use Custom Ready Check UI"],
        function() return RC.db.profile.useCustomReadyCheck end,
        function(value)
            RC.db.profile.useCustomReadyCheck = value
            if readyTracker and readyTracker.HideBlizzardFrame then
                readyTracker:HideBlizzardFrame()
            end
            if not value and readyTracker and readyTracker.HideReadyCheckFrame then
                readyTracker:HideReadyCheckFrame()
            end
        end
    )
    AddCheckbox(
        container,
        L["Enable Consumable Scans"],
        function() return RC.db.profile.enableConsumableChecker end,
        function(value)
            RC.db.profile.enableConsumableChecker = value
            if readyTracker and readyTracker.ApplySettings then
                readyTracker:ApplySettings()
            end
        end
    )
    AddCheckbox(
        container,
        L["Issues View by Default"],
        function() return RC.db.profile.readyTrackerMissingOnly end,
        function(value)
            RC.db.profile.readyTrackerMissingOnly = value
            if readyTracker and readyTracker.UpdateFrame then
                readyTracker:UpdateFrame()
            end
        end
    )
    AddCheckbox(
        container,
        L["Enable Missing-Consumable Whisper Button"],
        function() return RC.db.profile.readyTrackerWhisperMissing ~= false end,
        function(value)
            RC.db.profile.readyTrackerWhisperMissing = value and true or false
            if readyTracker and readyTracker.ApplySettings then
                readyTracker:ApplySettings()
            end
        end
    )
    AddCheckbox(
        container,
        L["Share Durability with RaidControl Users"],
        function() return RC.db.profile.enableDurabilityComm ~= false end,
        function(value) RC.db.profile.enableDurabilityComm = value and true or false end
    )
    AddCheckbox(
        container,
        L["Ask RaidControl Users for Durability"],
        function() return RC.db.profile.durabilityReadyCheckRequest ~= false end,
        function(value) RC.db.profile.durabilityReadyCheckRequest = value and true or false end
    )

    AddSlider(
        container,
        L["Low Durability Warning (%)"],
        5, 80, 5,
        function() return RC.db.profile.durabilityWarnThreshold or 30 end,
        function(value) RC.db.profile.durabilityWarnThreshold = value end
    )

    AddButton(container, L["Check Durability Now"], function()
        local durability = RC:GetModule("Durability", true)
        if durability and durability.RequestDurability then
            durability:RequestDurability(true)
        end
    end)

    AddSlider(
        container,
        L["Ready Check Scale"],
        70, 150, 1,
        function() return math.floor((RC.db.profile.readyTrackerScale or 1) * 100 + 0.5) end,
        function(value)
            RC.db.profile.readyTrackerScale = value / 100
            if readyTracker and readyTracker.ApplyScale then
                readyTracker:ApplyScale(value / 100)
            elseif readyTracker and readyTracker.ApplySettings then
                readyTracker:ApplySettings()
            end
        end
    )

    AddSlider(
        container,
        L["Ready Check Opacity"],
        45, 100, 5,
        function() return math.floor((RC.db.profile.readyTrackerAlpha or 1) * 100 + 0.5) end,
        function(value)
            RC.db.profile.readyTrackerAlpha = value / 100
            if readyTracker and readyTracker.ApplySettings then readyTracker:ApplySettings() end
        end
    )

    AddSlider(
        container,
        L["Result Auto-Close"],
        0, 30, 1,
        function() return RC.db.profile.readyTrackerAutoCloseSeconds or 8 end,
        function(value) RC.db.profile.readyTrackerAutoCloseSeconds = value end
    )

    AddActionToolbar(container, {
        {
            text = L["Preview & Move"],
            onClick = function()
                if readyTracker and readyTracker.PreviewLayout then
                    readyTracker:PreviewLayout()
                end
            end,
        },
        {
            text = L["Reset Position"],
            onClick = function()
                if readyTracker and readyTracker.ResetPosition then
                    readyTracker:ResetPosition()
                end
            end,
        },
    })
end


function Settings:BuildRaidTools(container, pageKey)
    local tabs = {
        { key = "overview", label = L["Overview"] },
        { key = "warnings", label = L["Warnings"] },
        { key = "timers", label = L["Timer Bars"] },
        { key = "sounds", label = L["Sounds"] },
        { key = "bosses", label = L["Boss Rules"] },
        { key = "bone", label = L["Bone Shield"] },
    }
    local subTab = DrawSubTabs(self, container, "tank", tabs, tabs[1].key)
    self:BuildTankSettings(container, subTab)
end

-- =============================================================================
-- COMPAT HELPERS
-- =============================================================================

function Settings:UpdateScale(scale)
    if not self.frame then
        return
    end
    ApplyWorkspaceScale(self, scale or 1)
end

function Settings:DrawGroup(_, _)
    -- Legacy no-op for older callers.
end
