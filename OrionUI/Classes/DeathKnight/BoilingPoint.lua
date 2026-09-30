-- Boiling Point indicator for Blood DK (design from Stig's reference, CLAUDE.md §8.3).
--
-- The talent (Warcraft Wiki, 12.x): Heart Strike can empower your next Blood Boil for
-- 15 seconds; the empowered Blood Boil deals more damage and echoes 3 seconds later.
--
-- What the bar shows:
--   RED, draining over 15s    a proc is up: cast Blood Boil
--   BLUE, draining over 3s    you cast the empowered Blood Boil: the echo is coming
--   GLOW (thin gold)          a new proc rolled while the bar is blue: react and cast
--                             Blood Boil again. That rolled proc also keeps the blue
--                             bar going when the current echo lands (chaining).
-- (Colours swapped at Stig's request 2026-09-30; both are settings.)
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
local GLOW_PAD = 2   -- glow outline sits this far outside the bar
local GLOW_WIDTH = 1 -- thin, per Stig

local BP = { name = "BoilingPoint" }
ns.BoilingPoint = BP

-- Plain state, all ours.
local procUp, procSince, procHiddenAt = false, 0, -math.huge
local echoUntil = 0
local queued = 0 -- echo windows banked by procs that rolled while an echo was running
local MAX_QUEUE = 3
local snapNext = false -- next paint starts a fresh window: jump to full, no easing

local frame, bar, icon, glow, glowAnim, ticker

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
    -- Glow: a thin outline just outside the bar's border, pulsing gently. Drawn around the bar,
    -- never behind it, so nothing bleeds through the empty part of the bar.
    glow = CreateFrame("Frame", nil, frame)
    glow:SetPoint("TOPLEFT", -GLOW_PAD, GLOW_PAD)
    glow:SetPoint("BOTTOMRIGHT", GLOW_PAD, -GLOW_PAD)
    glow.edges = {}
    for i = 1, 4 do glow.edges[i] = glow:CreateTexture(nil, "OVERLAY") end
    local e = glow.edges
    e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(GLOW_WIDTH)
    e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(GLOW_WIDTH)
    e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(GLOW_WIDTH)
    e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(GLOW_WIDTH)
    glow:Hide()
    glowAnim = glow:CreateAnimationGroup()
    glowAnim:SetLooping("BOUNCE")
    local a = glowAnim:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.45)

    -- Opaque background + 1px black border + one flat fill: nothing else.
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.05, 1)
    bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(C_Spell.GetSpellTexture(BLOOD_BOIL))
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
        for i = 1, 4 do glow.edges[i]:SetColorTexture(color[1], color[2], color[3], 1) end
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
    -- CHAINING: a proc that rolled during the echo keeps the bar going. When the running
    -- echo lands, the banked one continues straight on (from the old end time, so the
    -- windows join up) instead of the bar disappearing.
    if echoUntil <= now and queued > 0 then
        queued = queued - 1
        echoUntil = (now - echoUntil > ECHO) and (now + ECHO) or (echoUntil + ECHO)
        snapNext = true
    end
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
    if phase ~= lastPhase or snapNext or not SMOOTH then
        snapNext = false
        bar:SetValue(value, SNAP)
    else
        bar:SetValue(value, SMOOTH)
    end
    lastPhase = phase
    -- Glow only when a proc rolls while the echo is running: the proc colour already says
    -- "cast Blood Boil", the glow says "another one is ready, cast again".
    SetGlow(db.glow and procUp and phase == "echo", db.glowColor)
    frame:Show()
    if not ticker then ticker = C_Timer.NewTicker(TICK, function() BP:Render() end) end
end

function BP:Refresh()
    if not frame then return end
    local db = DB()
    if db.style == "icon" then
        local s = math.max(16, db.height * 2)
        frame:SetSize(s, s)
        bar:Hide()
        icon:Show()
    else
        frame:SetSize(db.width, db.height)
        bar:Show()
        icon:Hide()
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
        -- that must not hand out a fresh 15 seconds or bank a second echo.
        procUp, procSince = true, GetTime()
        if echoUntil > GetTime() then queued = math.min(queued + 1, MAX_QUEUE) end
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
        -- A new empowered cast restarts the echo; the proc it spent was the banked one.
        echoUntil, queued, snapNext = now + ECHO, 0, true
        BP:Render()
    end
end

local function OnEnteringWorld()
    -- Loading screens end any echo; the highlight may survive, so ask the game directly.
    echoUntil, queued = 0, 0
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
    procUp, echoUntil, queued, lastPhase = false, 0, 0, nil
    if frame then
        SetGlow(false)
        frame:Hide()
    end
end

-- For tests.
function BP:State() return procUp, echoUntil end
