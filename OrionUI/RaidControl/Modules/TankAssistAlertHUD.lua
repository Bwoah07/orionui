local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local TankAssist = RC:GetModule("TankAssist", true)

if not TankAssist then
    return
end

local LegacyAlert = TankAssist.Alert
local LegacyPreviewLayout = TankAssist.PreviewLayout
local LegacyEndLayoutMode = TankAssist.EndLayoutMode
local ALERT_DEFAULT_POS = { "CENTER", "UIParent", "CENTER", 0, 155 }
local TIMER_DEFAULT_POS = { "CENTER", "UIParent", "CENTER", 0, 55 }
local HUD_HEIGHT = 76
local TIMER_BAR_LIMIT = 6

local MOVEMENT_TIMER_LABELS = {
    ["sszorak-center"] = "BOSS TO CENTER",
    ["sszorak-clean-slice"] = "BOSS TO CLEAN SLICE",
    ["sszorak-crosswinds"] = "SET BOSS · CROSSWINDS",
    ["nekzali-coffins"] = "MOVE TO COFFINS",
    ["nymrissa-gap"] = "MOVE TO SAFE GAP",
    ["explorers-mushrooms"] = "MOVE TO MUSHROOMS",
    ["vashnik-fountains"] = "MOVE TO NEXT FOUNTAINS",
    ["ulatek-platform"] = "BOSS TO JUMP EDGE",
}

local BORDER = { 0, 0, 0, 1 }
local BAR_BG = { 0.05, 0.055, 0.065 }

-- The rule data writes titles as "ACTION — CONTEXT". The flash shows only the
-- action big and the context small; bars use one short line.
local function SplitTitle(title)
    title = tostring(title or "")
    local main, sub = title:match("^(.-)%s+—%s+(.+)$")
    if main and main ~= "" then
        return main, sub
    end
    return title, nil
end

local function BarText(text)
    text = string.upper(tostring(text or ""))
    text = text:gsub("^WAIT%s+—%s+", "")
    return (text:gsub("%s+—%s+", " · "))
end

-- 1px black frame drawn with four textures (no backdrop template needed).
local function AddBorder(frame)
    local edges = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
        edges[i] = t
    end
    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
    edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
    edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
    return edges
end

local function ValueIsAccessible(value)
    if value == nil then
        return false
    end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        if ok and secret then
            return false
        end
    end
    if canaccessvalue then
        local ok, accessible = pcall(canaccessvalue, value)
        if ok and accessible == false then
            return false
        end
    end
    return true
end

local function SafeNumber(value)
    if not ValueIsAccessible(value) then
        return nil
    end
    local ok, number = pcall(tonumber, value)
    return ok and number or nil
end

local function Profile()
    return RC.db and RC.db.profile or {}
end

-- The 2026-10 restyle (flat bars, short action text) only reads right with the
-- new sizes, so looks saved by the old RaidControl settings are dropped once.
local OLD_STYLE_KEYS = {
    "tankAssistDisplayStyle",
    "tankAssistAlertWidth",
    "tankAssistDetailFontSize",
    "tankAssistShowIcon",
    "tankAssistShowDetail",
    "tankAssistTextAlign",
    "tankAssistBackgroundAlpha",
    "tankAssistTimerWidth",
    "tankAssistTimerHeight",
    "tankAssistTimerFontSize",
    "tankAssistTimerSpacing",
    "tankAssistTimerBackgroundAlpha",
    "tankAssistTimerShowIcon",
}

local function DropOldStyle()
    local profile = RC.db and RC.db.profile
    if not profile or profile.tankAssistStyleVersion == 2 then
        return
    end
    for _, key in ipairs(OLD_STYLE_KEYS) do
        profile[key] = nil
    end
    profile.tankAssistStyleVersion = 2
end

local function Clamp(value, low, high, fallback)
    value = tonumber(value) or fallback
    return math.max(low, math.min(high, value))
end

local function GetCategoryColor(category, title)
    local profile = Profile()
    if TankAssist.GetWarningCategory then
        category = TankAssist:GetWarningCategory(category, nil, title)
    end
    local key = category == "movement" and "tankAssistMovementColor"
        or (category == "defensive" and "tankAssistDefensiveColor" or "tankAssistTauntColor")
    local fallback = category == "movement" and { r = 0.20, g = 0.80, b = 1.00 }
        or (category == "defensive" and { r = 1.00, g = 0.75, b = 0.20 }
            or { r = 1.00, g = 0.35, b = 0.20 })
    local color = profile[key]
    if type(color) ~= "table" then
        color = fallback
    end
    return tonumber(color.r) or fallback.r, tonumber(color.g) or fallback.g, tonumber(color.b) or fallback.b
end

local function FormatRemaining(remaining)
    if remaining >= 10 then
        return string.format("%.0f", remaining)
    end
    return string.format("%.1f", remaining)
end

function TankAssist:EnsureTankAssistHUDDriver()
    if self.alertHUDDriver or not CreateFrame then
        return
    end
    local driver = CreateFrame("Frame")
    driver._timerAccumulator = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        if self.alertHUDTimerMode then
            self:UpdateAlertHUDTimer(elapsed)
        end
        driver._timerAccumulator = driver._timerAccumulator + (tonumber(elapsed) or 0)
        if driver._timerAccumulator >= 0.10 then
            driver._timerAccumulator = 0
            if self.UpdateUpcomingTimerBars then
                self:UpdateUpcomingTimerBars(false)
            end
        end
    end)
    driver:Show()
    self.alertHUDDriver = driver
end

function TankAssist:CreateStatusFrame()
    if self.statusFrame then
        self.statusFrame:Hide()
        self.statusFrame = nil
    end
end

function TankAssist:RefreshStatus()
    if self.statusFrame then
        self.statusFrame:Hide()
    end
end

function TankAssist:ApplyAlertHUDColor(title, category)
    if not self.frame then
        return
    end
    category = category or self.alertHUDCategory
    local r, g, b = GetCategoryColor(category, title or (self.frame.title and self.frame.title:GetText()))
    if self.frame.title then
        self.frame.title:SetTextColor(r, g, b, 1)
    end
    if self.frame.accent then
        self.frame.accent:SetColorTexture(r, g, b, 1)
    end
    if self.frame.timerBar then
        self.frame.timerBar:SetStatusBarColor(r, g, b, 1)
    end
    if self.frame.timerText then
        self.frame.timerText:SetTextColor(1, 1, 1, 1)
    end
end

-- Puts "ACTION — CONTEXT" on the flash as a big action and a small context line.
-- Description paragraphs are never shown: the bars carry the context.
function TankAssist:SetAlertHUDText(title)
    if not self.frame then
        return
    end
    local main, sub = SplitTitle(title or "TAUNT NOW")
    self.frame.title:SetText(main)
    self.frame.detail:SetText(sub or "")
    if self.frame.body then
        self.frame.body:SetAlpha(1)
    end
end

function TankAssist:CreateAlertFrame()
    if self.frame or not CreateFrame then
        return
    end

    DropOldStyle()
    local frame = CreateFrame("Frame", "RaidControlTankAssistAlert", UIParent)
    frame:SetSize(360, HUD_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(600)
    frame:Hide()
    frame._raidControlFloatingTankHUD = true

    -- Everything visible sits on body so the flash can fade out without
    -- fighting the user's frame alpha, which ApplySingleFrameSettings sets on frame.
    local body = CreateFrame("Frame", nil, frame)
    body:SetAllPoints(frame)
    frame.body = body

    local panelBg = body:CreateTexture(nil, "BACKGROUND")
    panelBg:SetAllPoints(body)
    panelBg:SetColorTexture(BAR_BG[1], BAR_BG[2], BAR_BG[3], 0.85)
    frame.panelBg = panelBg
    frame.border = AddBorder(body)

    local accent = body:CreateTexture(nil, "ARTWORK")
    accent:SetWidth(2)
    accent:SetPoint("TOPLEFT", body, "TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 1, 1)
    frame.accent = accent

    local iconShadow = body:CreateTexture(nil, "BACKGROUND", nil, 1)
    iconShadow:SetColorTexture(0, 0, 0, 1)
    frame.iconShadow = iconShadow

    local icon = body:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconShadow, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconShadow, "BOTTOMRIGHT", -1, 1)
    frame.icon = icon

    local title = body:CreateFontString(nil, "OVERLAY")
    RC:SetFont(title, 28, "OUTLINE")
    title:SetShadowColor(0, 0, 0, 0.9)
    title:SetShadowOffset(1, -1)
    title:SetWordWrap(false)
    title:SetText("TAUNT NOW")
    frame.title = title

    -- Small context line under the action ("IKU / NAMA"), never a paragraph.
    local detail = body:CreateFontString(nil, "OVERLAY")
    RC:SetFont(detail, 13, "OUTLINE")
    detail:SetTextColor(0.85, 0.87, 0.9, 1)
    detail:SetShadowColor(0, 0, 0, 0.9)
    detail:SetShadowOffset(1, -1)
    detail:SetWordWrap(false)
    detail:SetText("")
    frame.detail = detail

    local timerText = body:CreateFontString(nil, "OVERLAY")
    RC:SetFont(timerText, 18, "OUTLINE")
    timerText:SetJustifyH("RIGHT")
    timerText:SetText("")
    frame.timerText = timerText

    local timerBg = CreateFrame("StatusBar", nil, body)
    timerBg:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    timerBg:SetStatusBarColor(0, 0, 0, 0.6)
    timerBg:SetMinMaxValues(0, 1)
    timerBg:SetValue(1)
    frame.timerBg = timerBg

    local timerBar = CreateFrame("StatusBar", nil, body)
    timerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    timerBar:SetMinMaxValues(0, 1)
    timerBar:SetValue(1)
    frame.timerBar = timerBar

    local timerSpark = body:CreateTexture(nil, "OVERLAY")
    timerSpark:SetSize(1, 5)
    timerSpark:SetColorTexture(1, 1, 1, 0.9)
    timerSpark:Hide()
    frame.timerSpark = timerSpark

    local countdownMarker = body:CreateTexture(nil, "OVERLAY")
    countdownMarker:SetSize(1, 5)
    countdownMarker:SetColorTexture(1, 1, 1, 0.5)
    countdownMarker:Hide()
    frame.countdownMarker = countdownMarker

    self.frame = frame
    if self.ConfigureMovableFrame then
        self:ConfigureMovableFrame(frame, "tankAssistAlertPos", ALERT_DEFAULT_POS)
    end
    self:EnsureTankAssistHUDDriver()
    self:ApplyTankAssistVisualSettings()
    self:ApplyAlertIcon()
    self:ApplyAlertHUDColor("TAUNT NOW", "taunt")
end

function TankAssist:ApplyTankAssistVisualSettings()
    local profile, frame = Profile(), self.frame
    if frame and frame._raidControlFloatingTankHUD then
        local width = Clamp(profile.tankAssistAlertWidth, 200, 800, 360)
        local titleSize = Clamp(profile.tankAssistAlertFontSize, 14, 56, 28)
        local subSize = Clamp(profile.tankAssistDetailFontSize, 9, 24, 13)
        -- "panel" = dark box with a thin border; "text" (default) = text only.
        local panel = profile.tankAssistDisplayStyle == "panel"
        local showIcon = panel and profile.tankAssistShowIcon == true
        local subText = frame.detail:GetText()
        local showSub = profile.tankAssistShowDetail ~= false and subText ~= nil and subText ~= ""
        local showTimer = profile.tankAssistShowTimer ~= false
            and (self.alertHUDTimerMode == "mechanic" or self._tankTimerPreviewActive)
        local align = profile.tankAssistTextAlign == "LEFT" and "LEFT" or "CENTER"
        local pad = panel and 8 or 2
        local iconSize = titleSize + (showSub and subSize + 4 or 0)
        local startX = showIcon and (pad + iconSize + 8) or pad
        local rightPad = showTimer and 52 or pad

        RC:SetFont(frame.title, titleSize, "OUTLINE")
        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", startX, -pad)
        frame.title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -rightPad, -pad)
        frame.title:SetHeight(titleSize + 4)
        frame.title:SetJustifyH(align)

        RC:SetFont(frame.detail, subSize, "OUTLINE")
        frame.detail:ClearAllPoints()
        frame.detail:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, 0)
        frame.detail:SetPoint("TOPRIGHT", frame.title, "BOTTOMRIGHT", 0, 0)
        frame.detail:SetHeight(subSize + 4)
        frame.detail:SetJustifyH(align)
        frame.detail:SetShown(showSub)

        local showBar = showTimer
        local barHeight = 3
        local height = pad * 2 + titleSize + 4 + (showSub and subSize + 4 or 0) + (showBar and barHeight + 4 or 0)
        frame:SetSize(width, height)
        frame.panelBg:SetShown(panel)
        frame.panelBg:SetColorTexture(BAR_BG[1], BAR_BG[2], BAR_BG[3], Clamp(profile.tankAssistBackgroundAlpha, 0, 1, 0.85))
        for _, edge in ipairs(frame.border) do
            edge:SetShown(panel)
        end
        frame.accent:SetShown(panel)
        frame.iconShadow:SetShown(showIcon)
        frame.icon:SetShown(showIcon)
        frame.iconShadow:ClearAllPoints()
        frame.iconShadow:SetPoint("TOPLEFT", frame, "TOPLEFT", pad, -pad)
        frame.iconShadow:SetSize(iconSize, iconSize)
        frame.timerText:ClearAllPoints()
        frame.timerText:SetPoint("RIGHT", frame.title, "RIGHT", rightPad - pad, 0)
        frame.timerText:SetShown(showTimer)

        local timerWidth = width - startX - pad
        for _, bar in ipairs({ frame.timerBg, frame.timerBar }) do
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", startX, pad)
            bar:SetSize(timerWidth, barHeight)
            bar:SetShown(showBar)
        end
        if not showBar then
            frame.timerSpark:Hide()
            frame.countdownMarker:Hide()
        end
        frame._timerPixelWidth = timerWidth
        self:ApplySingleFrameSettings(frame)
        if not self._tankTimerPreviewActive and (profile.tankAssistShowVisual == false
            or not self:IsWarningEnabled(self.alertHUDCategory or "taunt")) then
            frame:Hide()
        end
    end
    if self.timerFrame then self:ApplyUpcomingTimerAppearance() end
end

function TankAssist:RefreshTheme()
    if self.frame and self.frame._raidControlFloatingTankHUD then
        if self.frame.detail then
            self.frame.detail:SetTextColor(0.85, 0.87, 0.9, 1)
        end
        self:ApplyAlertHUDColor(nil, self.alertHUDCategory)
    end
    self:ApplyTankAssistVisualSettings()
end

function TankAssist:StopAlertHUDTimer(clearText)
    self.alertHUDTimerMode = nil
    self.alertHUDTimerStart = nil
    self.alertHUDTimerEnd = nil
    self.alertHUDTimerDuration = nil
    self.alertHUDTimelineEventID = nil
    self.alertHUDTimerRemaining = nil
    self.alertHUDTimerProgress = nil
    self.alertHUDTimerCategory = nil
    self.alertHUDMechanicKey = nil
    if self.frame and self.frame.timerBar then
        self.frame.timerBar:SetMinMaxValues(0, 1)
        self.frame.timerBar:SetValue(0)
    end
    if self.frame and self.frame.timerSpark then
        self.frame.timerSpark:Hide()
    end
    if self.frame and self.frame.countdownMarker then
        self.frame.countdownMarker:Hide()
    end
    if clearText ~= false and self.frame and self.frame.timerText then
        self.frame.timerText:SetText("")
    end
end

function TankAssist:GetAlertHUDTimerState(now)
    if not self.alertHUDTimerMode then
        return nil
    end

    if self.alertHUDTimerMode == "timeline" and self.alertHUDTimelineEventID
        and C_EncounterTimeline and type(C_EncounterTimeline.GetEventTimeRemaining) == "function"
    then
        local ok, rawRemaining = pcall(C_EncounterTimeline.GetEventTimeRemaining, self.alertHUDTimelineEventID)
        local remaining = ok and SafeNumber(rawRemaining) or nil
        if remaining then
            local duration = math.max(0.001, SafeNumber(self.alertHUDTimerDuration) or remaining)
            if remaining > duration then
                duration = remaining
                self.alertHUDTimerDuration = duration
            end
            return duration, math.max(0, remaining), math.max(0, math.min(1, remaining / duration))
        end
    end

    now = now or (GetTime and GetTime() or 0)
    local startTime = self.alertHUDTimerStart or now
    local endTime = self.alertHUDTimerEnd or now
    local duration = math.max(0.001, endTime - startTime)
    local remaining = math.max(0, endTime - now)
    local progress = math.max(0, math.min(1, remaining / duration))
    return duration, remaining, progress
end

function TankAssist:UpdateAlertHUDTimer()
    if not self.alertHUDTimerMode then
        return
    end

    local duration, remaining, progress = self:GetAlertHUDTimerState()
    if not duration then
        return
    end
    self.alertHUDTimerRemaining = remaining
    self.alertHUDTimerProgress = progress

    local profile = Profile()
    if not self:IsEnabled() or (self.alertHUDTimerMode == "mechanic"
        and (not self:ShouldRun() or profile.tankAssistUseCastRules == false
            or not self:IsWarningEnabled(self.alertHUDTimerCategory or "taunt")
            or not self:IsRuleEnabled(self.activeRule))) then
        self:StopAlertHUDTimer()
        if self.frame then self.frame:Hide() end
        return
    end
    local showVisualTimer = profile.tankAssistShowVisual ~= false and profile.tankAssistShowTimer ~= false
    local frame = self.frame
    if frame and frame:IsShown() and showVisualTimer then
        frame.timerBar:SetMinMaxValues(0, duration)
        frame.timerBar:SetValue(remaining)

        if frame.timerSpark and profile.tankAssistDisplayStyle ~= "text" then
            local fill = frame.timerBar:GetStatusBarTexture()
            frame.timerSpark:ClearAllPoints()
            frame.timerSpark:SetPoint("CENTER", fill, "RIGHT", 0, 0)
            frame.timerSpark:SetShown(remaining > 0.02)
        end

        if frame.countdownMarker then
            local countdownEnabled, countdownSeconds = self:GetCountdownSettings(self.alertHUDTimerCategory or self.alertHUDCategory or "taunt")
            local showMarker = profile.tankAssistDisplayStyle ~= "text" and countdownEnabled
                and self.alertHUDTimerMode == "mechanic" and duration > countdownSeconds + 0.05
            frame.countdownMarker:SetShown(showMarker)
            if showMarker then
                local timerWidth = frame._timerPixelWidth or frame.timerBar:GetWidth() or 100
                local x = timerWidth * math.min(1, countdownSeconds / duration)
                frame.countdownMarker:ClearAllPoints()
                frame.countdownMarker:SetPoint("CENTER", frame.timerBar, "LEFT", x, 0)
            end
        end

        if self.alertHUDTimerMode == "mechanic" then
            frame.timerText:SetText(string.format("%.1f", remaining))
        elseif self.alertHUDTimerMode == "timeline" then
            frame.timerText:SetText(FormatRemaining(remaining))
        else
            frame.timerText:SetText("")
        end
    elseif frame then
        frame.timerBar:Hide()
        frame.timerBg:Hide()
        frame.timerText:Hide()
        frame.timerSpark:Hide()
        frame.countdownMarker:Hide()
    end

    -- The action flash fades out over its last moments instead of popping off.
    if frame and frame.body then
        frame.body:SetAlpha(self.alertHUDTimerMode == "visual" and math.min(1, remaining / 0.35) or 1)
    end

    if remaining <= 0 then
        if self.alertHUDMechanicKey and self.activeHUDMechanics then
            self.activeHUDMechanics[self.alertHUDMechanicKey] = nil
        end
        self:StopAlertHUDTimer()
        if self.hideTimer then self.hideTimer:Cancel(); self.hideTimer = nil end
        if frame then frame:Hide() end
        self:RestoreActiveMechanic()
    end
end

function TankAssist:StartVisualAlertHUDTimer()
    local profile = Profile()
    if profile.tankAssistShowVisual == false then
        return
    end
    local duration = Clamp(profile.tankAssistVisualDuration, 1, 15, 2.5)
    local now = GetTime and GetTime() or 0
    self.alertHUDTimerMode = "visual"
    self.alertHUDTimerStart = now
    self.alertHUDTimerEnd = now + math.max(0.1, duration)
    self.alertHUDTimerDuration = duration
    self.alertHUDTimelineEventID = nil
    self.alertHUDMechanicKey = nil
    self.alertHUDTimerCategory = self.alertHUDCategory
    self:EnsureTankAssistHUDDriver()
end

function TankAssist:ShowMechanicCountdown(unit, spellID)
    -- Compatibility stub. Restricted Midnight maps use the encounter timeline
    -- and explicit resolution windows instead of protected enemy spell IDs.
    return false
end

function TankAssist:GetTimelineRemaining(eventID, fallback)
    if eventID and C_EncounterTimeline and type(C_EncounterTimeline.GetEventTimeRemaining) == "function" then
        local ok, rawRemaining = pcall(C_EncounterTimeline.GetEventTimeRemaining, eventID)
        local remaining = ok and SafeNumber(rawRemaining) or nil
        if remaining then
            return remaining
        end
    end
    return SafeNumber(fallback)
end

function TankAssist:ShowTimelineMechanicCountdown(tracked)
    -- Future mechanics belong to the timer stack, leaving urgent warnings free.
    if not tracked then return false end
    if not tracked._hudExpectedEnd and SafeNumber(tracked.duration) then
        tracked._hudExpectedEnd = GetTime() + tracked.duration
    end
    self:EnsureTankAssistHUDDriver()
    self:UpdateUpcomingTimerBars(true)
    return true
end

-- An active window ("wait, taunt after X") is a countdown to the moment to act,
-- so it lives in the bar stack. The big text is kept for the act itself
-- (TAUNT NOW), and only stands in here when bars for this kind are turned off.
function TankAssist:ActiveWindowUsesBar(record)
    local profile = Profile()
    if profile.tankAssistShowTimerBars == false or profile.tankAssistUseCastRules == false then
        return false
    end
    if record.category == "movement" then return profile.tankAssistTimerMovement ~= false end
    if record.category == "defensive" then return profile.tankAssistTimerDefensive ~= false end
    return profile.tankAssistTimerTaunt ~= false
end

-- "HOLD BOSS", "WAIT", "STAY BY MUSHROOM" describe a state to keep, so the bar
-- is enough. Anything else ("RUN OUT", "AIM WATER JET", "JUMP") is something to
-- do right now and also gets the short flash.
local PASSIVE_WORDS = { WAIT = true, HOLD = true, STAY = true, KEEP = true }

local function IsPassiveTitle(title)
    local first = string.upper(tostring(title or "")):match("^(%a+)")
    return first == nil or PASSIVE_WORDS[first] == true
end

-- Short action text with no sound and no repeat guard; Alert() is the path
-- with sounds. Used when an active window opens with something to do now.
function TankAssist:FlashAlertHUD(title, category)
    local profile = Profile()
    if profile.tankAssistShowVisual == false then
        return
    end
    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end
    self:CreateAlertFrame()
    if not self.frame then
        return
    end
    self.alertHUDCategory = category
    self:ApplyAlertIcon(self.activeRule)
    self:SetAlertHUDText(title)
    self:StartVisualAlertHUDTimer()
    self:ApplyTankAssistVisualSettings()
    self:ApplyAlertHUDColor(title, category)
    self.frame:Show()
end

function TankAssist:DisplayActiveMechanic(record)
    local profile = Profile()
    if self:ActiveWindowUsesBar(record) then
        self:UpdateUpcomingTimerBars(true)
        return
    end
    self.alertHUDCategory = record.category
    self.alertHUDTimerCategory = record.category
    self.alertHUDMechanicKey = record.key
    self.alertHUDTimerMode = "mechanic"
    self.alertHUDTimelineEventID = nil
    self.alertHUDTimerDuration = record.duration
    self.alertHUDTimerStart = record.endTime - record.duration
    self.alertHUDTimerEnd = record.endTime
    self.alertHUDCountdownLast = nil
    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end
    if profile.tankAssistShowVisual ~= false then
        self:CreateAlertFrame()
        self:ApplyAlertIcon(self.activeRule)
        self:SetAlertHUDText(record.title)
        self:ApplyTankAssistVisualSettings()
        self:ApplyAlertHUDColor(record.title, record.category)
        self.frame:Show()
    elseif self.frame then
        self.frame:Hide()
    end
end

function TankAssist:RestoreActiveMechanic()
    if not self:ShouldRun() or not self.activeRule or not self:IsRuleEnabled(self.activeRule) then return end
    local now, nextRecord = GetTime(), nil
    for key, record in pairs(self.activeHUDMechanics or {}) do
        if record.endTime <= now or not self:IsWarningEnabled(record.category) then
            self.activeHUDMechanics[key] = nil
        elseif not nextRecord or record.endTime < nextRecord.endTime then
            nextRecord = record
        end
    end
    if nextRecord then self:DisplayActiveMechanic(nextRecord) end
end

function TankAssist:ShowActiveMechanicCountdown(tracked, duration, title, detail, category)
    duration = SafeNumber(duration)
    if not duration or duration <= 0 then return false end
    category = self:GetWarningCategory(category, nil, title)
    -- The active window ends at the verified swap point for tank mechanics.
    local timerCategory = tracked and tracked.kind == "tank" and "taunt" or category
    if not self:IsWarningEnabled(timerCategory) then return false end
    local now = GetTime()
    local key = tracked and tracked.eventID or (tostring(title) .. ":" .. now)
    local label = tostring(tracked and tracked.label or "MECHANIC")
    local record = {
        key = key, tracked = tracked, category = timerCategory,
        duration = duration, endTime = now + duration,
        title = title or ("HOLD — " .. string.upper(label)),
        label = BarText(title or ((timerCategory == "movement" and "MOVE — " or "TAUNT — ") .. label)),
        active = true,
    }
    self.activeHUDMechanics = self.activeHUDMechanics or {}
    self.activeHUDMechanics[key] = record
    self:DisplayActiveMechanic(record)
    if self:ActiveWindowUsesBar(record) and not IsPassiveTitle(record.title) then
        self:FlashAlertHUD(record.title, category)
    end
    self:EnsureTankAssistHUDDriver()
    self:UpdateUpcomingTimerBars(true)
    return true
end

function TankAssist:ClearTimelineCountdown(eventID, hideFrame)
    if self.alertHUDTimerMode ~= "timeline" then
        return
    end
    if eventID and self.alertHUDTimelineEventID and eventID ~= self.alertHUDTimelineEventID then
        return
    end
    self:StopAlertHUDTimer()
    if hideFrame and self.frame then
        self.frame:Hide()
    end
end

function TankAssist:ClearMechanicCountdown(hideFrame, eventID)
    if self.activeHUDMechanics then
        if eventID then self.activeHUDMechanics[eventID] = nil
        else self.activeHUDMechanics = {} end
    end
    if self.alertHUDTimerMode ~= "mechanic" then
        return
    end
    if eventID and self.alertHUDMechanicKey ~= eventID then return end
    self:StopAlertHUDTimer()
    if self.frame then self.frame:Hide() end
    self:UpdateUpcomingTimerBars(true)
end

-- ---------------------------------------------------------------------------
-- Upcoming personal tank timer bars
-- ---------------------------------------------------------------------------

function TankAssist:CreateUpcomingTimerBar(parent, index)
    local bar = CreateFrame("Frame", nil, parent)
    bar.index = index

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bar.bg = bg

    local progress = CreateFrame("StatusBar", nil, bar)
    progress:SetPoint("TOPLEFT", bar, "TOPLEFT", 1, -1)
    progress:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 1)
    progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    progress:SetMinMaxValues(0, 1)
    progress:SetValue(1)
    bar.progress = progress
    bar.border = AddBorder(bar)

    -- Icon sits outside the bar on the left, like a BigWigs bar, with its own border.
    local iconHolder = CreateFrame("Frame", nil, bar)
    iconHolder:SetPoint("TOPRIGHT", bar, "TOPLEFT", -2, 0)
    iconHolder:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", -2, 0)
    local iconBg = iconHolder:CreateTexture(nil, "BACKGROUND")
    iconBg:SetAllPoints(iconHolder)
    iconBg:SetColorTexture(0, 0, 0, 1)
    local icon = iconHolder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", -1, 1)
    bar.iconHolder = iconHolder
    bar.icon = icon

    local label = progress:CreateFontString(nil, "OVERLAY")
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
    bar.label = label

    local seconds = progress:CreateFontString(nil, "OVERLAY")
    seconds:SetJustifyH("RIGHT")
    seconds:SetShadowColor(0, 0, 0, 1)
    seconds:SetShadowOffset(1, -1)
    bar.seconds = seconds

    bar:Hide()
    return bar
end

function TankAssist:CreateTimerFrame()
    if self.timerFrame or not CreateFrame then
        return
    end
    DropOldStyle()
    local frame = CreateFrame("Frame", "RaidControlTankAssistTimers", UIParent)
    frame:SetSize(280, 20)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(580)
    frame:Hide()
    frame._raidControlTankTimers = true
    frame.bars = {}
    for i = 1, TIMER_BAR_LIMIT do
        frame.bars[i] = self:CreateUpcomingTimerBar(frame, i)
    end
    self.timerFrame = frame
    if self.ConfigureMovableFrame then
        self:ConfigureMovableFrame(frame, "tankAssistTimerPos", TIMER_DEFAULT_POS)
    end
    self:EnsureTankAssistHUDDriver()
    self:ApplySingleFrameSettings(frame)
    self:ApplyUpcomingTimerAppearance()
end

function TankAssist:ApplyUpcomingTimerAppearance()
    local frame = self.timerFrame
    if not frame then
        return
    end
    local profile = Profile()
    local width = Clamp(profile.tankAssistTimerWidth, 160, 700, 280)
    local height = Clamp(profile.tankAssistTimerHeight, 14, 64, 20)
    local spacing = Clamp(profile.tankAssistTimerSpacing, 0, 20, 2)
    local fontSize = Clamp(profile.tankAssistTimerFontSize, 8, 24, 12)
    local maxBars = math.floor(Clamp(profile.tankAssistTimerMaxBars, 1, TIMER_BAR_LIMIT, 3))
    local growth = profile.tankAssistTimerGrowth == "UP" and "UP" or "DOWN"
    local totalHeight = (height * maxBars) + (spacing * math.max(0, maxBars - 1))
    local showIcon = profile.tankAssistTimerShowIcon == true
    frame:SetSize(width, totalHeight)

    for i, bar in ipairs(frame.bars) do
        bar:SetSize(width, height)
        bar:ClearAllPoints()
        if growth == "UP" then
            bar:SetPoint("BOTTOM", frame, "BOTTOM", 0, (i - 1) * (height + spacing))
        else
            bar:SetPoint("TOP", frame, "TOP", 0, -((i - 1) * (height + spacing)))
        end
        local backgroundAlpha = Clamp(profile.tankAssistTimerBackgroundAlpha, 0, 1, 0.8)
        bar.bg:SetColorTexture(BAR_BG[1], BAR_BG[2], BAR_BG[3], backgroundAlpha)

        bar.iconHolder:SetWidth(height)
        bar.iconHolder:SetShown(showIcon)
        bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        RC:SetFont(bar.label, fontSize, "OUTLINE")
        bar.label:ClearAllPoints()
        bar.label:SetPoint("LEFT", bar, "LEFT", 6, 0)
        bar.label:SetPoint("RIGHT", bar, "RIGHT", profile.tankAssistTimerShowSeconds ~= false and -44 or -6, 0)
        bar.label:SetShown(profile.tankAssistTimerShowLabel ~= false)

        RC:SetFont(bar.seconds, fontSize, "OUTLINE")
        bar.seconds:ClearAllPoints()
        bar.seconds:SetPoint("RIGHT", bar, "RIGHT", -6, 0)
        bar.seconds:SetShown(profile.tankAssistTimerShowSeconds ~= false)
    end
end

function TankAssist:GetTrackedPersonalCategory(tracked)
    if not tracked then
        return nil, nil
    end
    if tracked.kind == "movement" then
        local personal = self.ShouldShowUpcomingMovement and self:ShouldShowUpcomingMovement(tracked) or false
        return personal and "movement" or nil, nil
    end

    if tracked.everyoneTitle then
        if self.IsPlayerTank and self:IsPlayerTank() ~= true then
            return nil, nil
        end
        local category = self:GetWarningCategory(nil, tracked.spoken, tracked.everyoneTitle)
        return category, nil
    end

    local owner
    if self.GetTrackedOwner then
        owner = self:GetTrackedOwner(tracked, self.activeRule)
    end
    if tracked.action == "defensive" then
        local everyTank = tracked.everyTank and (not self.IsPlayerTank or self:IsPlayerTank() == true)
        return (owner == "player" or everyTank) and "defensive" or nil, owner
    end
    if tracked.crossSwap then
        local tank = not self.IsPlayerTank or self:IsPlayerTank()
        return tank and "taunt" or nil, owner
    end
    if owner ~= "player" and owner ~= "cotank" then
        return nil, owner
    end

    -- For the tank currently taking a buster, the immediate personal job is
    -- mitigation. For the off-tank, the immediate job is the later taunt.
    if owner == "player" and tracked.defensive ~= false then
        return "defensive", owner
    end
    return "taunt", owner
end

function TankAssist:IsTrackedPersonalAction(tracked, category)
    local personalCategory, owner = self:GetTrackedPersonalCategory(tracked)
    if not personalCategory then
        return false, owner
    end
    if category and category ~= personalCategory then
        return false, owner
    end
    return true, owner
end

function TankAssist:GetUpcomingTimerEntry(tracked)
    if not tracked or (tracked.kind ~= "tank" and tracked.kind ~= "movement") then
        return nil
    end
    local profile = Profile()
    local category, owner = self:GetTrackedPersonalCategory(tracked)
    if not category then
        -- Multi-boss ambiguity and co-tank-only defensives stay silent.
        return nil
    end
    if self.IsWarningEnabled and not self:IsWarningEnabled(category) then
        -- A player tanking a swap+buster may still want the future swap bar even
        -- when defensive warnings are disabled, so fall back to taunt if valid.
        if category == "defensive" and tracked.action ~= "defensive"
            and self:IsWarningEnabled("taunt")
        then
            category = "taunt"
        else
            return nil
        end
    end
    if category == "taunt" and profile.tankAssistTimerTaunt == false then
        return nil
    elseif category == "defensive" and profile.tankAssistTimerDefensive == false then
        if tracked.action ~= "defensive" and profile.tankAssistTimerTaunt ~= false
            and (not self.IsWarningEnabled or self:IsWarningEnabled("taunt"))
        then
            category = "taunt"
        else
            return nil
        end
    elseif category == "movement" and profile.tankAssistTimerMovement == false then
        return nil
    end

    local fallback = tracked._hudExpectedEnd and (tracked._hudExpectedEnd - GetTime()) or nil
    local remaining = self:GetTimelineRemaining(tracked.eventID, fallback)
    if not remaining or remaining <= 0 then
        return nil
    end

    -- One short line: what to do, then the mechanic. The colour says the kind.
    local name = tostring(tracked.label or "MECHANIC")
    local label
    if tracked.everyoneTitle then
        label = tracked.everyoneTitle
    elseif category == "movement" then
        label = MOVEMENT_TIMER_LABELS[tracked.action] or tracked.previewTitle or tracked.preMoveTitle
            or ("MOVE — " .. name)
    elseif category == "defensive" then
        label = "DEFENSIVE — " .. name
    elseif tracked.crossSwap then
        local _, targetName = self.GetCrossSwapTarget and self:GetCrossSwapTarget()
        label = targetName and ("TAUNT " .. targetName .. " — " .. name) or ("CROSS-TAUNT — " .. name)
    elseif owner == "cotank" then
        label = "TAUNT — " .. name
    elseif owner == "player" then
        label = "SWAP — " .. name
    else
        label = "TANK HIT — " .. name
    end
    label = BarText(label)

    return {
        tracked = tracked,
        category = category,
        owner = owner,
        remaining = remaining,
        duration = math.max(remaining, SafeNumber(tracked.duration) or remaining),
        label = label,
    }
end

function TankAssist:RenderUpcomingTimerEntry(bar, entry)
    local profile = Profile()
    local r, g, b = GetCategoryColor(entry.category, entry.label)
    -- Active windows (the mechanic is happening, act when it runs out) are drawn
    -- solid; mechanics that haven't started yet are drawn dimmer.
    bar.progress:SetStatusBarColor(r, g, b, entry.active and 0.95 or 0.6)
    bar.progress:SetMinMaxValues(0, math.max(0.001, entry.duration))
    bar.progress:SetValue(entry.remaining)
    bar.label:SetText(entry.label)
    bar.label:SetTextColor(1, 1, 1, 1)
    bar.seconds:SetText(FormatRemaining(entry.remaining))
    bar.seconds:SetTextColor(1, 1, 1, 1)

    local showIcon = profile.tankAssistTimerShowIcon == true
    local iconData = showIcon and self.GetRuleIconData and self:GetRuleIconData(self.activeRule) or nil
    if iconData then
        bar.icon:SetTexture(iconData.texture)
        if iconData.texCoord then
            bar.icon:SetTexCoord(iconData.texCoord[1], iconData.texCoord[2], iconData.texCoord[3], iconData.texCoord[4])
        else
            bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    bar.iconHolder:SetShown(showIcon and iconData ~= nil)
    bar.label:SetShown(profile.tankAssistTimerShowLabel ~= false)
    bar.seconds:SetShown(profile.tankAssistTimerShowSeconds ~= false)
    bar:Show()
end

function TankAssist:RenderUpcomingTimerPreview()
    self:CreateTimerFrame()
    if not self.timerFrame then
        return
    end
    self:ApplyUpcomingTimerAppearance()
    local examples = {
        { category = "taunt", remaining = 2.2, duration = 6, label = "TAUNT AFTER WATER JET", active = true },
        { category = "defensive", remaining = 6.0, duration = 12, label = "DEFENSIVE · MOTHER'S WRATH" },
        { category = "movement", remaining = 14.0, duration = 20, label = "BOSS TO JUMP EDGE" },
    }
    local maxBars = math.floor(Clamp(Profile().tankAssistTimerMaxBars, 1, TIMER_BAR_LIMIT, 3))
    for i, bar in ipairs(self.timerFrame.bars) do
        if i <= math.min(maxBars, #examples) then
            self:RenderUpcomingTimerEntry(bar, examples[i])
        else
            bar:Hide()
        end
    end
    self.timerFrame:Show()
end

function TankAssist:UpdateUpcomingTimerBars(force)
    local profile = Profile()
    if self._tankTimerPreviewActive then
        local now = GetTime and GetTime() or 0
        if not self._tankTimerPreviewExpires or now < self._tankTimerPreviewExpires then
            self:RenderUpcomingTimerPreview()
            return
        end
        self._tankTimerPreviewActive = nil
        self._tankTimerPreviewExpires = nil
    end

    if profile.tankAssistShowTimerBars == false or profile.tankAssistUseCastRules == false
        or not self.activeEncounter or not self.timelineEvents or not self:IsRuleEnabled(self.activeRule)
        or (self.ShouldRun and not self:ShouldRun())
    then
        if self.timerFrame then
            self.timerFrame:Hide()
        end
        return
    end

    local horizon = Clamp(profile.tankAssistTimerHorizon, 5, 120, 30)
    local entries = {}
    for _, tracked in pairs(self.timelineEvents) do
        local entry = self:GetUpcomingTimerEntry(tracked)
        if entry and entry.remaining <= horizon then
            entries[#entries + 1] = entry
        end
    end
    local now = GetTime()
    for key, record in pairs(self.activeHUDMechanics or {}) do
        local remaining = record.endTime - now
        local categoryVisible = record.category == "movement" and profile.tankAssistTimerMovement ~= false
            or record.category == "taunt" and profile.tankAssistTimerTaunt ~= false
            or record.category == "defensive" and profile.tankAssistTimerDefensive ~= false
        if remaining <= 0 then
            self.activeHUDMechanics[key] = nil
        elseif remaining <= horizon and categoryVisible and self:IsWarningEnabled(record.category) then
            entries[#entries + 1] = { category = record.category, label = record.label,
                remaining = remaining, duration = record.duration, active = true }
        end
    end
    table.sort(entries, function(a, b)
        if a.remaining == b.remaining then
            return tostring(a.label) < tostring(b.label)
        end
        return a.remaining < b.remaining
    end)

    local maxBars = math.floor(Clamp(profile.tankAssistTimerMaxBars, 1, TIMER_BAR_LIMIT, 3))
    if #entries == 0 then
        if self.timerFrame then
            self.timerFrame:Hide()
        end
        return
    end

    self:CreateTimerFrame()
    self:ApplyUpcomingTimerAppearance()
    if self.ApplySingleFrameSettings then
        self:ApplySingleFrameSettings(self.timerFrame)
    end
    for i, bar in ipairs(self.timerFrame.bars) do
        if i <= math.min(maxBars, #entries) then
            self:RenderUpcomingTimerEntry(bar, entries[i])
        else
            bar:Hide()
        end
    end
    self.timerFrame:Show()
end

-- ---------------------------------------------------------------------------
-- Timeline wrappers: reuse the sanitized tracked records from TankAssist.lua.
-- ---------------------------------------------------------------------------

local LegacyTimelineAdded = TankAssist.ENCOUNTER_TIMELINE_EVENT_ADDED
local LegacyTimelineStateChanged = TankAssist.ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED
local LegacyTimelineRemoved = TankAssist.ENCOUNTER_TIMELINE_EVENT_REMOVED

function TankAssist:ENCOUNTER_TIMELINE_EVENT_ADDED(event, eventInfo, deferred)
    if LegacyTimelineAdded then
        LegacyTimelineAdded(self, event, eventInfo, deferred)
    end
    if type(eventInfo) ~= "table" or not self.timelineEvents then
        return
    end
    local ok, rawID = pcall(function() return eventInfo.id end)
    if not ok or not ValueIsAccessible(rawID) then
        return
    end
    local eventID = tonumber(rawID)
    local tracked = eventID and self.timelineEvents[eventID] or nil
    if tracked then
        self:ShowTimelineMechanicCountdown(tracked)
    end
    self:UpdateUpcomingTimerBars(true)
end

function TankAssist:ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED(event, eventID)
    if not ValueIsAccessible(eventID) then
        if LegacyTimelineStateChanged then
            return LegacyTimelineStateChanged(self, event, eventID)
        end
        return
    end
    eventID = SafeNumber(eventID)
    local timelineState
    if eventID and C_EncounterTimeline and type(C_EncounterTimeline.GetEventState) == "function" then
        local ok, rawState = pcall(C_EncounterTimeline.GetEventState, eventID)
        timelineState = ok and SafeNumber(rawState) or nil
    end
    if eventID and (timelineState == 2 or timelineState == 3)
        and self.alertHUDTimerMode == "timeline" and self.alertHUDTimelineEventID == eventID
    then
        self:ClearTimelineCountdown(eventID, true)
    end
    local result
    if LegacyTimelineStateChanged then
        result = LegacyTimelineStateChanged(self, event, eventID)
    end
    self:UpdateUpcomingTimerBars(true)
    return result
end

function TankAssist:ENCOUNTER_TIMELINE_EVENT_REMOVED(event, eventID)
    if not ValueIsAccessible(eventID) then
        if LegacyTimelineRemoved then
            return LegacyTimelineRemoved(self, event, eventID)
        end
        return
    end
    eventID = SafeNumber(eventID)
    if eventID and self.alertHUDTimerMode == "timeline" and self.alertHUDTimelineEventID == eventID then
        self:ClearTimelineCountdown(eventID, true)
    end
    local result
    if LegacyTimelineRemoved then
        result = LegacyTimelineRemoved(self, event, eventID)
    end
    self:UpdateUpcomingTimerBars(true)
    return result
end

function TankAssist:Alert(title, detail, spokenText, key, playSound, rule, category)
    category = self:GetWarningCategory(category, spokenText, title)
    local shown = LegacyAlert(self, title, detail, spokenText, key, playSound, rule, category)
    if shown then
        self.alertHUDCategory = category
        if self.frame and self.frame:IsShown() then
            self:SetAlertHUDText(title)
            self:StartVisualAlertHUDTimer()
            self:ApplyTankAssistVisualSettings()
            self:ApplyAlertHUDColor(title, category)
        end
    end
    return shown
end

function TankAssist:HidePreview()
    self._tankTimerPreviewActive = nil
    self._tankTimerPreviewExpires = nil
    if self.layoutPreviewTimer then
        self.layoutPreviewTimer:Cancel()
        self.layoutPreviewTimer = nil
    end
    if self.frame and not self.activeEncounter then
        self.frame:Hide()
    end
    if self.timerFrame and not self.activeEncounter then
        self.timerFrame:Hide()
    else
        self:UpdateUpcomingTimerBars(true)
    end
end

if LegacyPreviewLayout then
    function TankAssist:PreviewLayout(persistent)
        local function ShowPreviewNow()
            LegacyPreviewLayout(self, persistent)
            if self.frame and self.frame._raidControlFloatingTankHUD then
                self.alertHUDCategory = "taunt"
                self:SetAlertHUDText("TAUNT NOW")
                if self.frame.body then self.frame.body:SetAlpha(1) end
                self:ApplyTankAssistVisualSettings()
                self:ApplyAlertHUDColor("TAUNT NOW", "taunt")
                self.frame:Show()
                local previewDuration = 6
                local previewRemaining = 3
                if self.frame.timerBar and Profile().tankAssistShowTimer ~= false then
                    self.frame.timerBar:SetMinMaxValues(0, previewDuration)
                    self.frame.timerBar:SetValue(previewRemaining)
                    self.frame.timerBar:Show()
                    self.frame.timerBg:Show()
                end
                if self.frame.timerText and Profile().tankAssistShowTimer ~= false then
                    self.frame.timerText:SetText("3")
                    self.frame.timerText:Show()
                end
            end

            self._tankTimerPreviewActive = true
            self._tankTimerPreviewExpires = persistent and nil or ((GetTime and GetTime() or 0) + 15)
            self:RenderUpcomingTimerPreview()
        end

        -- Like the warning test buttons, defer until the settings click/reflow has
        -- completed so a same-frame layout refresh cannot erase the preview.
        if C_Timer and C_Timer.After then
            C_Timer.After(0, ShowPreviewNow)
            return true
        end
        ShowPreviewNow()
        return true
    end
end

if LegacyEndLayoutMode then
    function TankAssist:EndLayoutMode()
        self._tankTimerPreviewActive = nil
        self._tankTimerPreviewExpires = nil
        local result = LegacyEndLayoutMode(self)
        self:UpdateUpcomingTimerBars(true)
        return result
    end
end
