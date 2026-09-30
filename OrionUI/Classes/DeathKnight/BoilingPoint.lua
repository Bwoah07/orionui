-- Boiling Point indicator for Blood DK (design from Stig's reference, CLAUDE.md §8.3): a
-- compact bar (or an icon) that
--   * turns BLUE and glows when Boiling Point procs: react and cast Blood Boil,
--   * turns RED after you cast the empowered Blood Boil, counting down the echo.
--
-- How the talent works (Warcraft Wiki, 12.x): Heart Strike can empower your next Blood
-- Boil for 15 seconds; the empowered Blood Boil deals more damage and echoes 3 seconds
-- later.
--
-- Signals, readable in combat in the open world (verified 2026-09-30): the game's Blood
-- Boil highlight (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW, spell 50842) and our own Blood Boil
-- cast (UNIT_SPELLCAST_SUCCEEDED). The buff itself can't be tracked (the Cooldown Manager
-- doesn't offer it). The highlight blinks off and on during the buff, so only its
-- appearance counts. If casts turn secret in an instance, the red echo phase is skipped.
local _, ns = ...

local L = ns.L

local BLOOD_BOIL = 50842
local ECHO = 3 -- seconds, from the talent text
local TICK = 0.05
local GLOW_PAD = 4

local BP = { name = "BoilingPoint", phase = nil } -- nil | "proc" | "echo"
ns.BoilingPoint = BP

local frame, bg, fill, icon, cd, glow, glowAnim, label, ticker

local function DB() return ns.BloodDK.db.boilingPoint end

local function Create()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    -- Glow sits behind the bar, a few pixels larger, pulsing while the proc is up.
    glow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    glow:SetPoint("TOPLEFT", -GLOW_PAD, GLOW_PAD)
    glow:SetPoint("BOTTOMRIGHT", GLOW_PAD, -GLOW_PAD)
    glow:SetBlendMode("ADD")
    glow:Hide()
    glowAnim = glow:CreateAnimationGroup()
    glowAnim:SetLooping("BOUNCE")
    local a = glowAnim:CreateAnimation("Alpha")
    a:SetFromAlpha(0.9)
    a:SetToAlpha(0.2)
    a:SetDuration(0.35)
    bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)
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
    label = frame:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    frame.edge = CreateFrame("Frame", nil, frame)
    frame.edge:SetAllPoints()
    ns.Theme:Skin(frame.edge, { 0, 0, 0, 0 })
    frame:Hide()
    ns.Movers:Register("BloodBoilingPoint", {
        label = L["Boiling Point"], getFrame = function() return frame end, default = { x = 0, y = -160 },
    })
end

local function PhaseLength()
    return BP.phase == "echo" and ECHO or DB().window
end

local function Remaining()
    if not BP.startedAt then return 0 end
    return math.max(0, BP.startedAt + PhaseLength() - GetTime())
end

local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end

local function PhaseColor()
    local db = DB()
    return BP.phase == "echo" and db.echoColor or db.procColor
end

local function SetGlow(on)
    if on then
        local c = PhaseColor()
        glow:SetColorTexture(c[1], c[2], c[3], 1)
        glow:Show()
        if not glowAnim:IsPlaying() then glowAnim:Play() end
    else
        if glowAnim:IsPlaying() then glowAnim:Stop() end
        glow:Hide()
    end
end

function BP:Draw()
    if not frame or not self.phase then return end
    local db = DB()
    local left = Remaining()
    if db.style == "bar" then
        fill:SetWidth(math.max(0.01, (frame:GetWidth() - 2) * left / PhaseLength()))
    end
    label:SetText(db.showTime and ("%.1f"):format(left) or "")
end

local function SetPhase(phase)
    BP.phase = phase
    BP.startedAt = phase and GetTime() or nil
    StopTicker()
    if phase then
        cd:SetCooldown(BP.startedAt, PhaseLength())
        -- Drains the bar and ends the phase; runs only while something is shown.
        ticker = C_Timer.NewTicker(TICK, function()
            if Remaining() <= 0 then SetPhase(nil) else BP:Draw() end
        end)
    else
        cd:Clear()
    end
    BP:Refresh()
end

function BP:Refresh()
    if not frame then return end
    local db = DB()
    label:SetFont(ns.Theme:Font(), math.max(9, math.floor(db.height * 0.6)), "OUTLINE")
    if db.style == "icon" then
        local s = math.max(16, db.height * 2)
        frame:SetSize(s, s)
        fill:Hide()
        icon:Show()
        cd:Show()
        label:Hide()
    else
        frame:SetSize(db.width, db.height)
        fill:Show()
        icon:Hide()
        cd:Hide()
        label:Show()
    end
    local c = PhaseColor()
    fill:SetColorTexture(c[1], c[2], c[3], 1)
    ns.Theme:SetBorderColor(frame.edge, 0, 0, 0, 1)
    local show = db.show and self.phase ~= nil and (self.phase ~= "echo" or db.echo)
    frame:SetShown(show)
    SetGlow(show and db.glow and self.phase == "proc")
    self:Draw()
end

-- Only the highlight appearing counts: it starts the proc window, or restarts it when a
-- new Heart Strike roll refreshes the buff.
local function OnGlow(_, _, spellID)
    if ns.Secret.Is(spellID) or spellID ~= BLOOD_BOIL then return end
    if BP.phase ~= "proc" and DB().sound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
    SetPhase("proc")
end

-- Casting the empowered Blood Boil turns the bar red for the echo.
local function OnCast(_, _, _, _, spellID)
    if ns.Secret.Is(spellID) or spellID ~= BLOOD_BOIL then return end
    if BP.phase == "proc" then SetPhase("echo") end
end

function BP:Enable()
    Create()
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", self, OnGlow)
    ns.Events:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, self, OnCast)
    self:Refresh()
end

function BP:Disable()
    ns.Events:OffAll(self)
    StopTicker()
    self.phase, self.startedAt = nil, nil
    if frame then
        SetGlow(false)
        frame:Hide()
    end
end
