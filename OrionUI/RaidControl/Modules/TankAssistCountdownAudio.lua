local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local TankAssist = RC:GetModule("TankAssist", true)

if not TankAssist or not TankAssist.UpdateAlertHUDTimer or not TankAssist.ShowMechanicCountdown then
    return
end

local LegacyUpdateAlertHUDTimer = TankAssist.UpdateAlertHUDTimer
local LegacyShowMechanicCountdown = TankAssist.ShowMechanicCountdown
local LegacyStopAlertHUDTimer = TankAssist.StopAlertHUDTimer

local function PlayCountdownTick(self, category)
    local sound, channel = self:GetWarningSoundSettings(category)
    if sound == "none" then
        return
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, channel)
    end
end

function TankAssist:ShowMechanicCountdown(unit, spellID)
    self.alertHUDCountdownLast = nil
    return LegacyShowMechanicCountdown(self, unit, spellID)
end

function TankAssist:StopAlertHUDTimer(clearText)
    self.alertHUDCountdownLast = nil
    return LegacyStopAlertHUDTimer(self, clearText)
end

function TankAssist:UpdateAlertHUDTimer(elapsed)
    LegacyUpdateAlertHUDTimer(self, elapsed)

    -- Audio remains available with a text-only or hidden warning display. The
    -- HUD's independent timer driver keeps this sample current in either mode.
    if self.alertHUDTimerMode ~= "mechanic" then
        return
    end

    local category = self.alertHUDTimerCategory or self.alertHUDCategory or "taunt"
    local enabled, countdownSeconds = self:GetCountdownSettings(category)
    if not enabled then
        return
    end

    -- LegacyUpdateAlertHUDTimer sampled the live timer once this frame and
    -- stored it on the TankAssist object.  Use that exact same sample for the
    -- spoken countdown so bar, number, and audio stay frame-synchronized.
    local remaining = self.alertHUDTimerRemaining
    if type(remaining) ~= "number" and self.GetAlertHUDTimerState then
        local _, sampledRemaining = self:GetAlertHUDTimerState()
        remaining = sampledRemaining
    end
    remaining = tonumber(remaining) or 0

    if remaining > 0 and remaining <= countdownSeconds then
        local second = math.max(1, math.min(countdownSeconds, math.ceil(remaining)))

        -- The configured final seconds use whole numbers. The sound fires only
        -- once per number, using the matching warning category's sound channel.
        if self.frame and self.frame.timerText then
            self.frame.timerText:SetText(tostring(second))
        end

        if self.alertHUDCountdownLast ~= second then
            self.alertHUDCountdownLast = second
            PlayCountdownTick(self, category)
        end
    elseif remaining > countdownSeconds then
        self.alertHUDCountdownLast = nil
    end
end
