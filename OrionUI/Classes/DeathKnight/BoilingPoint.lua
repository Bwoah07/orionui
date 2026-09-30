-- Boiling Point indicator for Blood DK (design from Stig's reference, CLAUDE.md §8.3).
--
-- The talent (Warcraft Wiki, 12.x): Heart Strike can empower your next Blood Boil for
-- 15 seconds; the empowered Blood Boil deals more damage and echoes 3 seconds later.
--
-- What the bar shows:
--   BLUE, draining over 15s   a proc is up: cast Blood Boil
--   RED, draining over 3s     you cast the empowered Blood Boil: the echo is coming
--   GLOW                      a proc is up and castable (also while red: a new proc
--                             rolled during the echo, react and cast again)
--
-- Signals (readable in combat, verified 2026-09-30): the game's Blood Boil highlight
-- (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE) and our own Blood Boil cast
-- (UNIT_SPELLCAST_SUCCEEDED). The buff can't be tracked (the Cooldown Manager doesn't
-- offer it), so the highlight IS the proc: it appearing starts a proc, it going away ends
-- it. The highlight can go away a moment BEFORE the cast event arrives, so a Blood Boil
-- cast shortly after the highlight went out still counts as empowered (CAST_GRACE).
-- Spell IDs are compared through C_Spell.GetBaseSpell so an override of Blood Boil still
-- matches.
-- Design ideas (echo-first priority, cast grace, glow-on-banked-proc) were informed by how
-- other packs behave; the code here is ours.
local _, ns = ...

local L = ns.L

local BLOOD_BOIL = 50842
local ECHO = 3          -- seconds, from the talent text
local CAST_GRACE = 1    -- seconds after the highlight goes out that a cast still counts
local TICK = 0.1
local GLOW_PAD = 4

local BP = { name = "BoilingPoint" }
ns.BoilingPoint = BP

-- Plain state, all ours.
local procUp, procSince, procHiddenAt = false, 0, -math.huge
local echoUntil = 0

local frame, bar, icon, cd, glow, glowAnim, label, ticker

local function DB() return ns.BloodDK.db.boilingPoint end

local SMOOTH = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.ExponentialEaseOut
local SNAP = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate

local function IsBloodBoil(spellID)
    if ns.Secret.Is(spellID) or type(spellID) ~= "number" then return false end
    if spellID == BLOOD_BOIL then return true end
    local base = C_Spell.GetBaseSpell and C_Spell.GetBaseSpell(spellID)
    return not ns.Secret.Is(base) and base == BLOOD_BOIL
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function Create()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    glow = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    glow:SetPoint("TOPLEFT", -GLOW_PAD, GLOW_PAD)
    glow:SetPoint("BOTTOMRIGHT", GLOW_PAD, -GLOW_PAD)
    glow:SetBlendMode("ADD")
    glow:Hide()
    glowAnim = glow:CreateAnimationGroup()
    glowAnim:SetLooping("BOUNCE")
    local a = glowAnim:CreateAnimation("Alpha")
    a:SetFromAlpha(0.95)
    a:SetToAlpha(0.2)
    a:SetDuration(0.35)

    local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.85)
    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture(ns.Media:Fetch("statusbar"))
    bar:SetMinMaxValues(0, 1)
    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(C_Spell.GetSpellTexture(BLOOD_BOIL))
    cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetReverse(true)
    label = bar:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER")
    frame.edge = CreateFrame("Frame", nil, frame)
    frame.edge:SetAllPoints()
    ns.Theme:Skin(frame.edge, { 0, 0, 0, 0 })
    frame:Hide()
    ns.Movers:Register("BloodBoilingPoint", {
        label = L["Boiling Point"], getFrame = function() return frame end, default = { x = 0, y = -160 },
    })
end

local function SetGlow(on, color)
    if on then
        glow:SetColorTexture(color[1], color[2], color[3], 1)
        glow:Show()
        if not glowAnim:IsPlaying() then glowAnim:Play() end
    else
        if glowAnim:IsPlaying() then glowAnim:Stop() end
        glow:Hide()
    end
end

---------------------------------------------------------------------------
-- What to show right now
---------------------------------------------------------------------------

-- -> phase ("echo" | "proc" | nil), seconds left, phase length
local function Current()
    local now, db = GetTime(), DB()
    if db.echo and echoUntil > now then return "echo", echoUntil - now, ECHO end
    if procUp then
        local left = procSince + db.window - now
        if left > 0 then return "proc", left, db.window end
    end
end

local lastPhase
local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end

function BP:Render()
    if not frame then return end
    local db = DB()
    local phase, left, total = Current()
    if not (db.show and phase) then
        SetGlow(false)
        frame:Hide()
        lastPhase = nil
        StopTicker()
        return
    end
    local color = phase == "echo" and db.echoColor or db.procColor
    bar:SetStatusBarColor(color[1], color[2], color[3], 1)
    -- A new phase snaps full; within a phase the engine eases between our ticks.
    local value = left / total
    if phase ~= lastPhase or not SMOOTH then
        bar:SetValue(value, SNAP)
        cd:SetCooldown(GetTime() - (total - left), total)
    else
        bar:SetValue(value, SMOOTH)
    end
    lastPhase = phase
    label:SetText(db.showTime and ("%.1f"):format(left) or "")
    -- Glow = a proc you can act on: the blue phase, or a new proc banked during the echo.
    SetGlow(db.glow and procUp, db.procColor)
    frame:Show()
    if not ticker then ticker = C_Timer.NewTicker(TICK, function() BP:Render() end) end
end

function BP:Refresh()
    if not frame then return end
    local db = DB()
    label:SetFont(ns.Theme:Font(), math.max(9, math.floor(db.height * 0.6)), "OUTLINE")
    if db.style == "icon" then
        local s = math.max(16, db.height * 2)
        frame:SetSize(s, s)
        bar:Hide()
        icon:Show()
        cd:Show()
    else
        frame:SetSize(db.width, db.height)
        bar:Show()
        icon:Hide()
        cd:Hide()
    end
    ns.Theme:SetBorderColor(frame.edge, 0, 0, 0, 1)
    lastPhase = nil
    self:Render()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function OnGlowShow(_, _, spellID)
    if not IsBloodBoil(spellID) then return end
    if not procUp then
        -- Rising edge only: the overlay re-announces an alert that never went away, and
        -- that must not hand out a fresh 15 seconds.
        procUp, procSince = true, GetTime()
        if DB().sound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
    end
    BP:Render()
end

local function OnGlowHide(_, _, spellID)
    if not IsBloodBoil(spellID) then return end
    procUp, procHiddenAt = false, GetTime()
    BP:Render()
end

local function OnCast(_, _, _, _, spellID)
    if not IsBloodBoil(spellID) then return end
    local now = GetTime()
    if procUp or now - procHiddenAt <= CAST_GRACE then
        echoUntil = now + ECHO
        BP:Render()
    end
end

local function OnEnteringWorld()
    -- Loading screens end any echo; the highlight may survive, so ask the game directly.
    echoUntil = 0
    local up = C_SpellActivationOverlay and C_SpellActivationOverlay.IsSpellOverlayed
        and C_SpellActivationOverlay.IsSpellOverlayed(BLOOD_BOIL)
    procUp = ns.Secret.Bool(up) == true
    if procUp then procSince = GetTime() end -- remaining time unknown: show a full window
    BP:Render()
end

function BP:Enable()
    Create()
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", self, OnGlowShow)
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", self, OnGlowHide)
    ns.Events:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, self, OnCast)
    ns.Events:On("PLAYER_ENTERING_WORLD", self, OnEnteringWorld)
    self:Refresh()
end

function BP:Disable()
    ns.Events:OffAll(self)
    StopTicker()
    procUp, echoUntil, lastPhase = false, 0, nil
    if frame then
        SetGlow(false)
        frame:Hide()
    end
end

-- For tests.
function BP:State() return procUp, echoUntil end
