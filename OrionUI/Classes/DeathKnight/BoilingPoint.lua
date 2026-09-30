-- Boiling Point indicator for Blood DK (our own design, CLAUDE.md §8.3): a thin bar in
-- the resource-bar style that drains while the proc lasts, or a plain icon with a
-- countdown swipe, pulsing while Blood Boil is empowered.
--
-- Signal: the game's spell-activation highlight on Blood Boil (SPELL_ACTIVATION_OVERLAY_
-- GLOW_SHOW/HIDE, spell 50842). Its spell ID is readable in combat (verified 2026-09-30).
-- The game doesn't tell us how long the proc lasts, so the countdown uses the `window`
-- setting (an estimate); the highlight going away always hides it, whatever the clock says.
-- No stack counting: the game hides those numbers in combat.
local _, ns = ...

local L = ns.L

local BLOOD_BOIL = 50842
local TICK = 0.05

local BP = { name = "BoilingPoint", active = false }
ns.BoilingPoint = BP

local frame, fill, icon, cd, pulse, ticker

local function DB() return ns.BloodDK.db.boilingPoint end

local function Create()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    ns.Theme:Skin(frame, { 0, 0, 0, 0.55 })
    fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMLEFT", 1, 1)
    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(C_Spell.GetSpellTexture(BLOOD_BOIL))
    cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetHideCountdownNumbers(false)
    pulse = frame:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local a = pulse:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.3)
    frame:Hide()
    ns.Movers:Register("BloodBoilingPoint", {
        label = L["Boiling Point"], getFrame = function() return frame end, default = { x = 0, y = -160 },
    })
end

local function Remaining()
    if not BP.startedAt then return 0 end
    return math.max(0, BP.startedAt + DB().window - GetTime())
end

local function Draw()
    local db = DB()
    if db.style == "bar" then
        local frac = db.window > 0 and Remaining() / db.window or 1
        fill:SetWidth(math.max(0.01, (frame:GetWidth() - 2) * frac))
    end
end

local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end

function BP:Refresh()
    if not frame then return end
    local db = DB()
    local r, g, b = ns.Theme:Accent()
    if db.style == "icon" then
        local s = math.max(16, db.height * 4)
        frame:SetSize(s, s)
        fill:Hide()
        icon:Show()
        cd:Show()
        ns.Theme:SetBorderColor(frame, r, g, b, 1)
    else
        frame:SetSize(db.width, db.height)
        fill:SetColorTexture(r, g, b)
        fill:Show()
        icon:Hide()
        cd:Hide()
        ns.Theme:SetBorderColor(frame, 0, 0, 0, 1)
    end
    local show = db.show and self.active
    frame:SetShown(show)
    if show and db.pulse then
        if not pulse:IsPlaying() then pulse:Play() end
    elseif pulse:IsPlaying() then
        pulse:Stop()
        frame:SetAlpha(1)
    end
    Draw()
end

local function OnGlow(_, event, spellID)
    if ns.Secret.Is(spellID) or spellID ~= BLOOD_BOIL then return end
    local on = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
    if on and not BP.active then
        if DB().sound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
        BP.startedAt = GetTime()
        cd:SetCooldown(BP.startedAt, DB().window)
        StopTicker()
        -- Drains the bar; runs only while the proc is up.
        ticker = C_Timer.NewTicker(TICK, function() Draw() end)
    elseif not on then
        BP.startedAt = nil
        StopTicker()
        cd:Clear()
    end
    BP.active = on
    BP:Refresh()
end

function BP:Enable()
    Create()
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", self, OnGlow)
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", self, OnGlow)
    self:Refresh()
end

function BP:Disable()
    ns.Events:OffAll(self)
    StopTicker()
    self.active, self.startedAt = false, nil
    if frame then
        if pulse:IsPlaying() then pulse:Stop() end
        frame:Hide()
    end
end
