-- Boiling Point indicator for Blood DK (our own design, CLAUDE.md §8.3): a thin bar in
-- the resource-bar style, or a plain icon with a countdown swipe.
--
-- How the talent works (Warcraft Wiki, 12.x): Heart Strike can empower your next Blood
-- Boil for 15 seconds; the empowered Blood Boil deals more damage and echoes 3 seconds
-- later. So there are two phases to show:
--   1. proc: from the Blood Boil highlight until you cast it (or 15s pass): "use it"
--   2. echo: 3 seconds after casting the empowered Blood Boil
--
-- Signals, readable in combat in the open world (verified 2026-09-30): the game's Blood
-- Boil highlight (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE, spell 50842) and our own
-- Blood Boil cast (UNIT_SPELLCAST_SUCCEEDED). The buff itself can't be tracked (the CDM
-- doesn't list it either). If casts turn secret in an instance, the echo phase is skipped.
local _, ns = ...

local L = ns.L

local BLOOD_BOIL = 50842
local ECHO = 3 -- seconds, from the talent text
local TICK = 0.05

local BP = { name = "BoilingPoint", phase = nil } -- nil | "proc" | "echo"
ns.BoilingPoint = BP

local frame, fill, icon, cd, pulse, label, ticker

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
    label = frame:CreateFontString(nil, "OVERLAY")
    label:SetPoint("BOTTOM", frame, "TOP", 0, 2)
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

function BP:Draw()
    if not frame or not self.phase then return end
    local db = DB()
    local left = Remaining()
    if db.style == "bar" then
        fill:SetWidth(math.max(0.01, (frame:GetWidth() - 2) * left / PhaseLength()))
    end
    if db.showTime then
        label:SetText((self.phase == "echo" and L["Echo"] .. " " or "") .. ("%.1f"):format(left))
    else
        label:SetText(self.phase == "echo" and L["Echo"] or "")
    end
end

function BP:Refresh()
    if not frame then return end
    local db = DB()
    local r, g, b = ns.Theme:Accent()
    label:SetFont(ns.Theme:Font(), 11, "OUTLINE")
    if db.style == "icon" then
        local s = math.max(16, db.height * 4)
        frame:SetSize(s, s)
        fill:Hide()
        icon:Show()
        cd:Show()
        ns.Theme:SetBorderColor(frame, r, g, b, 1)
    else
        frame:SetSize(db.width, db.height)
        fill:Show()
        icon:Hide()
        cd:Hide()
        ns.Theme:SetBorderColor(frame, 0, 0, 0, 1)
    end
    -- The echo phase is drawn dimmer: the button press is done, the damage is coming.
    if self.phase == "echo" then fill:SetColorTexture(r * 0.5, g * 0.5, b * 0.5) else fill:SetColorTexture(r, g, b) end
    local show = db.show and self.phase ~= nil and (self.phase ~= "echo" or db.echo)
    frame:SetShown(show)
    if show and db.pulse and self.phase == "proc" then
        if not pulse:IsPlaying() then pulse:Play() end
    elseif pulse:IsPlaying() then
        pulse:Stop()
        frame:SetAlpha(1)
    end
    self:Draw()
end

local function OnGlow(_, event, spellID)
    if ns.Secret.Is(spellID) or spellID ~= BLOOD_BOIL then return end
    if event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW" then
        if BP.phase ~= "proc" then
            if DB().sound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
            SetPhase("proc")
        end
    elseif BP.phase == "proc" then
        SetPhase(nil) -- highlight gone without our cast: proc expired or was used up elsewhere
    end
end

-- Casting the empowered Blood Boil starts the echo countdown. The cast event arrives
-- just before the highlight goes away (seen in game).
local function OnCast(_, _, _, _, spellID)
    if ns.Secret.Is(spellID) or spellID ~= BLOOD_BOIL then return end
    if BP.phase == "proc" then SetPhase("echo") end
end

function BP:Enable()
    Create()
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", self, OnGlow)
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", self, OnGlow)
    ns.Events:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, self, OnCast)
    self:Refresh()
end

function BP:Disable()
    ns.Events:OffAll(self)
    StopTicker()
    self.phase, self.startedAt = nil, nil
    if frame then
        if pulse:IsPlaying() then pulse:Stop() end
        frame:Hide()
    end
end
