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
    ["sszorak-center"] = "MOVE BOSS TO CENTER",
    ["sszorak-clean-slice"] = "MOVE BOSS TO CLEAN SLICE",
    ["sszorak-crosswinds"] = "SET BOSS — CROSSWINDS",
    ["nekzali-coffins"] = "MOVE TOWARD COFFINS",
    ["nymrissa-gap"] = "MOVE TO SAFE GAP",
    ["explorers-mushrooms"] = "MOVE TO MUSHROOMS",
    ["vashnik-fountains"] = "MOVE TO NEXT FOUNTAINS",
    ["ulatek-platform"] = "MOVE BOSS TO JUMP EDGE",
}

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
        self.frame.timerText:SetTextColor(r, g, b, 1)
    end
end

function TankAssist:CreateAlertFrame()
    if self.frame or not CreateFrame then
        return
    end

    local frame = CreateFrame("Frame", "RaidControlTankAssistAlert", UIParent)
    frame:SetSize(420, HUD_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(600)
    frame:Hide()
    frame._raidControlFloatingTankHUD = true

    local panelBg = frame:CreateTexture(nil, "BACKGROUND")
    panelBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    panelBg:SetAllPoints(frame)
    panelBg:SetColorTexture(0.02, 0.025, 0.035, 0.88)
    frame.panelBg = panelBg

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetSize(4, 54)
    accent:SetPoint("LEFT", frame, "LEFT", 4, 0)
    frame.accent = accent

    local iconShadow = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    iconShadow:SetTexture("Interface\\Buttons\\WHITE8X8")
    iconShadow:SetColorTexture(0, 0, 0, 0.55)
    iconShadow:SetSize(50, 50)
    frame.iconShadow = iconShadow

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(42, 42)
    icon:SetPoint("CENTER", iconShadow, "CENTER", 0, 0)
    frame.icon = icon

    local title = frame:CreateFontString(nil, "OVERLAY")
    RC:SetFont(title, 28, "OUTLINE")
    title:SetJustifyH("LEFT")
    title:SetShadowColor(0, 0, 0, 0.95)
    title:SetShadowOffset(2, -2)
    title:SetText("TAUNT NOW")
    frame.title = title

    local detail = frame:CreateFontString(nil, "OVERLAY")
    RC:SetFont(detail, 14, "OUTLINE")
    detail:SetJustifyH("LEFT")
    detail:SetTextColor(0.92, 0.92, 0.92, 1)
    detail:SetShadowColor(0, 0, 0, 0.95)
    detail:SetShadowOffset(1, -1)
    detail:SetText("")
    frame.detail = detail

    local timerText = frame:CreateFontString(nil, "OVERLAY")
    RC:SetFont(timerText, 20, "OUTLINE")
    timerText:SetJustifyH("RIGHT")
    timerText:SetShadowColor(0, 0, 0, 0.95)
    timerText:SetShadowOffset(2, -2)
    timerText:SetText("")
    frame.timerText = timerText

    local timerBg = CreateFrame("StatusBar", nil, frame)
    timerBg:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    timerBg:SetStatusBarColor(0, 0, 0, 0.58)
    timerBg:SetMinMaxValues(0, 1)
    timerBg:SetValue(1)
    frame.timerBg = timerBg

    local timerBar = CreateFrame("StatusBar", nil, frame)
    timerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    timerBar:SetMinMaxValues(0, 1)
    timerBar:SetValue(1)
    frame.timerBar = timerBar

    local timerSpark = frame:CreateTexture(nil, "OVERLAY")
    timerSpark:SetTexture("Interface\\Buttons\\WHITE8X8")
    timerSpark:SetSize(2, 14)
    timerSpark:SetColorTexture(1, 1, 1, 0.90)
    timerSpark:Hide()
    frame.timerSpark = timerSpark

    local countdownMarker = frame:CreateTexture(nil, "OVERLAY")
    countdownMarker:SetTexture("Interface\\Buttons\\WHITE8X8")
    countdownMarker:SetSize(1, 12)
    countdownMarker:SetColorTexture(1, 1, 1, 0.38)
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
        local width = Clamp(profile.tankAssistAlertWidth, 260, 800, 420)
        local titleSize = Clamp(profile.tankAssistAlertFontSize, 14, 56, 28)
        local detailSize = Clamp(profile.tankAssistDetailFontSize, 9, 24, 14)
        local panel = profile.tankAssistDisplayStyle ~= "text"
        local showIcon = panel and profile.tankAssistShowIcon ~= false
        local showDetail = profile.tankAssistShowDetail ~= false
        local showTimer = profile.tankAssistShowTimer ~= false
            and (self.alertHUDTimerMode == "mechanic" or self._tankTimerPreviewActive)
        local align = profile.tankAssistTextAlign == "CENTER" and "CENTER" or "LEFT"
        local startX = showIcon and 76 or 12
        local contentWidth = width - startX - (showTimer and 62 or 12)

        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", startX, -10)
        frame.title:SetWidth(contentWidth)
        frame.title:SetHeight(0)
        frame.title:SetWordWrap(true)
        frame.title:SetJustifyH(align)
        RC:SetFont(frame.title, titleSize, "OUTLINE")
        local titleHeight = math.max(titleSize + 4, math.min(titleSize * 2 + 8, frame.title:GetStringHeight()))
        frame.title:SetHeight(titleHeight)

        frame.detail:ClearAllPoints()
        frame.detail:SetPoint("TOPLEFT", frame, "TOPLEFT", startX, -14 - titleHeight)
        frame.detail:SetWidth(width - startX - 12)
        frame.detail:SetHeight(0)
        frame.detail:SetWordWrap(true)
        frame.detail:SetJustifyH(align)
        RC:SetFont(frame.detail, detailSize, "OUTLINE")
        local detailHeight = showDetail and math.max(detailSize + 3,
            math.min(detailSize * 3 + 6, frame.detail:GetStringHeight())) or 0
        frame.detail:SetHeight(math.max(1, detailHeight))
        frame.detail:SetShown(showDetail)

        local showBar = panel and showTimer
        local height = math.max(showIcon and 74 or 40, titleHeight + detailHeight + 24 + (showBar and 13 or 0))
        frame:SetSize(width, height)
        frame.panelBg:SetShown(panel)
        frame.panelBg:SetColorTexture(0.02, 0.025, 0.035, Clamp(profile.tankAssistBackgroundAlpha, 0, 1, 0.88))
        frame.accent:SetShown(panel)
        frame.accent:SetHeight(height - 16)
        frame.iconShadow:SetShown(showIcon)
        frame.icon:SetShown(showIcon)
        frame.iconShadow:ClearAllPoints()
        frame.iconShadow:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
        frame.timerText:ClearAllPoints()
        frame.timerText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -12)
        frame.timerText:SetShown(showTimer)

        local timerWidth = width - startX - 12
        for _, bar in ipairs({ frame.timerBg, frame.timerBar }) do
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", startX, 8)
            bar:SetSize(timerWidth, 5)
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
            self.frame.detail:SetTextColor(0.92, 0.92, 0.92, 1)
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

function TankAssist:DisplayActiveMechanic(record)
    local profile = Profile()
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
        self.frame.title:SetText(record.title)
        self.frame.detail:SetText(record.detail)
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
        detail = detail or "Keep the current assignment until the timer ends.",
        label = timerCategory == "movement" and ("MOVE IN — " .. label)
            or ("SWAP IN — " .. label),
    }
    self.activeHUDMechanics = self.activeHUDMechanics or {}
    self.activeHUDMechanics[key] = record
    self:DisplayActiveMechanic(record)
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
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetAllPoints(bar)
    bar.bg = bg

    local progress = CreateFrame("StatusBar", nil, bar)
    progress:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    progress:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    progress:SetMinMaxValues(0, 1)
    progress:SetValue(1)
    bar.progress = progress

    local shade = progress:CreateTexture(nil, "ARTWORK", nil, 1)
    shade:SetTexture("Interface\\Buttons\\WHITE8X8")
    shade:SetAllPoints(progress)
    shade:SetColorTexture(0, 0, 0, 0.38)
    bar.shade = shade

    local accent = progress:CreateTexture(nil, "OVERLAY", nil, 1)
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", progress, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", progress, "BOTTOMLEFT", 0, 0)
    bar.accent = accent

    local icon = progress:CreateTexture(nil, "OVERLAY", nil, 2)
    bar.icon = icon

    local label = progress:CreateFontString(nil, "OVERLAY")
    label:SetJustifyH("LEFT")
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
    local frame = CreateFrame("Frame", "RaidControlTankAssistTimers", UIParent)
    frame:SetSize(360, 34)
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
    local width = Clamp(profile.tankAssistTimerWidth, 200, 700, 360)
    local height = Clamp(profile.tankAssistTimerHeight, 22, 64, 34)
    local spacing = Clamp(profile.tankAssistTimerSpacing, 0, 20, 5)
    local fontSize = Clamp(profile.tankAssistTimerFontSize, 10, 24, 15)
    local maxBars = math.floor(Clamp(profile.tankAssistTimerMaxBars, 1, TIMER_BAR_LIMIT, 3))
    local growth = profile.tankAssistTimerGrowth == "UP" and "UP" or "DOWN"
    local totalHeight = (height * maxBars) + (spacing * math.max(0, maxBars - 1))
    frame:SetSize(width, totalHeight)

    for i, bar in ipairs(frame.bars) do
        bar:SetSize(width, height)
        bar:ClearAllPoints()
        if growth == "UP" then
            bar:SetPoint("BOTTOM", frame, "BOTTOM", 0, (i - 1) * (height + spacing))
        else
            bar:SetPoint("TOP", frame, "TOP", 0, -((i - 1) * (height + spacing)))
        end
        local backgroundAlpha = Clamp(profile.tankAssistTimerBackgroundAlpha, 0, 1, 0.65)
        bar.bg:SetColorTexture(0.015, 0.02, 0.03, backgroundAlpha)
        bar.shade:SetColorTexture(0, 0, 0, backgroundAlpha * 0.45)

        local iconSize = math.max(16, height - 8)
        bar.icon:SetSize(iconSize, iconSize)
        bar.icon:ClearAllPoints()
        bar.icon:SetPoint("LEFT", bar, "LEFT", 7, 0)
        bar.icon:SetShown(profile.tankAssistTimerShowIcon ~= false)

        RC:SetFont(bar.label, fontSize, "OUTLINE")
        bar.label:ClearAllPoints()
        bar.label:SetPoint("LEFT", bar, "LEFT", profile.tankAssistTimerShowIcon ~= false and (iconSize + 13) or 9, 0)
        bar.label:SetPoint("RIGHT", bar, "RIGHT", profile.tankAssistTimerShowSeconds ~= false and -54 or -9, 0)
        bar.label:SetShown(profile.tankAssistTimerShowLabel ~= false)

        RC:SetFont(bar.seconds, fontSize, "OUTLINE")
        bar.seconds:ClearAllPoints()
        bar.seconds:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
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
        return owner == "player" and "defensive" or nil, owner
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

    local label
    if tracked.everyoneTitle then
        label = tracked.everyoneTitle
    elseif category == "movement" then
        label = MOVEMENT_TIMER_LABELS[tracked.action] or tracked.previewTitle or tracked.preMoveTitle
            or ("MOVE — " .. tostring(tracked.label or "POSITION"))
    elseif category == "defensive" then
        label = "DEFENSIVE — " .. tostring(tracked.label or "TANK HIT")
    elseif tracked.crossSwap then
        label = "CROSS-TAUNT AFTER — " .. tostring(tracked.label or "MECHANIC")
    elseif owner == "cotank" then
        label = "TAUNT AFTER — " .. tostring(tracked.label or "MECHANIC")
    elseif owner == "player" then
        label = "SWAP AFTER — " .. tostring(tracked.label or "MECHANIC")
    else
        label = "TANK HIT — " .. tostring(tracked.label or "MECHANIC")
    end

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
    bar.progress:SetStatusBarColor(r, g, b, 0.48)
    bar.accent:SetColorTexture(r, g, b, 1)
    bar.progress:SetMinMaxValues(0, math.max(0.001, entry.duration))
    bar.progress:SetValue(entry.remaining)
    bar.label:SetText(entry.label)
    bar.label:SetTextColor(0.96, 0.97, 1, 1)
    bar.seconds:SetText(FormatRemaining(entry.remaining) .. "s")
    bar.seconds:SetTextColor(r, g, b, 1)

    local iconData = self.GetRuleIconData and self:GetRuleIconData(self.activeRule) or nil
    if iconData then
        bar.icon:SetTexture(iconData.texture)
        if iconData.texCoord then
            bar.icon:SetTexCoord(iconData.texCoord[1], iconData.texCoord[2], iconData.texCoord[3], iconData.texCoord[4])
        else
            bar.icon:SetTexCoord(0, 1, 0, 1)
        end
    end
    bar.icon:SetShown(profile.tankAssistTimerShowIcon ~= false)
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
        { category = "movement", remaining = 10.0, duration = 15, label = "MOVE BOSS TO JUMP EDGE" },
        { category = "defensive", remaining = 6.0, duration = 12, label = "DEFENSIVE — MOTHER'S WRATH" },
        { category = "taunt", remaining = 3.0, duration = 10, label = "TAUNT AFTER — WATER JET" },
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
                remaining = remaining, duration = record.duration }
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

function TankAssist:ENCOUNTER_TIMELINE_EVENT_ADDED(event, eventInfo)
    if LegacyTimelineAdded then
        LegacyTimelineAdded(self, event, eventInfo)
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
