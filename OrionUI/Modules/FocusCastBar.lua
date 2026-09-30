-- Focus cast bar: what your focus target is casting, coloured by whether you can kick it.
--
-- Colours, in order of priority:
--   important cast (the game's own "lethal if not interrupted" flag) -> important colour + glow
--   can't be interrupted                                              -> locked colour + shield
--   interruptible and your interrupt is ready                         -> kick colour
--   interruptible but your interrupt is on cooldown                   -> kick-not-ready colour
--
-- 12.x rules (CLAUDE.md §4): UnitCastingInfo/UnitChannelInfo are SecretWhenUnitSpellCastRestricted,
-- so in combat the name, icon, times, notInterruptible and spell ID can be secret, and so can
-- C_Spell.IsSpellImportant's answer. We never read them in Lua: name/icon/target go straight into
-- SetText/SetTexture, the bar runs on the engine's duration objects (SetTimerDuration), and the
-- secret booleans only ever reach SetVertexColorFromBoolean / SetAlphaFromBoolean. Existence is
-- tested with type(), which is safe on secrets. Our own interrupt's readiness IS readable
-- (isActive, verified 2026-09-29), so the kick-ready choice is made in Lua.
local _, ns = ...

local L = ns.L
local S = ns.Schema

local UNIT = "focus"

local M = ns.Modules:New("FocusCastBar", {
    category = "qol", label = L["Focus cast bar"], order = 2,
    desc = L["A cast bar for your focus target: kick-ready colour, can't-interrupt shield, important-cast highlight and the cast's target."],
    profileKey = "layout",
    schema = S.Table{ fields = {
        width = S.Number{ section = L["Bar"], default = 260, min = 100, max = 600, step = 2, label = L["Width"], order = 1 },
        height = S.Number{ section = L["Bar"], default = 22, min = 10, max = 60, step = 1, label = L["Height"], order = 2 },
        showIcon = S.Bool{ section = L["Bar"], default = true, label = L["Show spell icon"], order = 3 },
        showTimer = S.Bool{ section = L["Bar"], default = true, label = L["Show time left"], order = 4 },
        showTarget = S.Bool{ section = L["Details"], default = true, label = L["Show who the cast is aimed at"], order = 5 },
        targetClassColor = S.Bool{ section = L["Details"], default = true, label = L["Class colour for the cast's target"], order = 6 },
        showShield = S.Bool{ section = L["Details"], default = true, label = L["Shield icon on casts you can't interrupt"], order = 7 },
        fontSize = S.Number{ section = L["Bar"], default = 12, min = 8, max = 24, step = 1, label = L["Text size"], order = 4.5 },
        texture = S.String{ default = "Orion Flat", hidden = true },
        kickTint = S.Bool{ section = L["Colours"], default = true, label = L["Different colour while my interrupt is on cooldown"], order = 10 },
        kickColor = S.Color{ section = L["Colours"], default = { 0.95, 0.65, 0.15, 1 }, label = L["Interruptible, kick ready"], order = 11 },
        kickNotReadyColor = S.Color{ section = L["Colours"], default = { 0.65, 0.45, 0.8, 1 }, label = L["Interruptible, kick on cooldown"], order = 12 },
        lockedColor = S.Color{ section = L["Colours"], default = { 0.55, 0.55, 0.6, 1 }, label = L["Can't be interrupted"], order = 13 },
        importantColorOn = S.Bool{ section = L["Important casts"], default = true, label = L["Important casts get their own colour"], order = 14 },
        importantColor = S.Color{ section = L["Important casts"], default = { 0.9, 0.15, 0.2, 1 }, label = L["Important cast"], order = 15 },
        importantGlow = S.Bool{ section = L["Important casts"], default = true, label = L["Glow around important casts"], order = 16 },
        glowColor = S.Color{ section = L["Important casts"], default = { 1, 0.25, 0.25, 1 }, label = L["Glow colour"], order = 17 },
        interruptedColor = S.Color{ section = L["Colours"], default = { 0.85, 0.2, 0.2, 1 }, label = L["Interrupted"], order = 13.5 },
    } },
    options = function(self)
        return {
            { type = "Header", label = L["Texture and preview"] },
            { type = "Dropdown", label = L["Bar texture"],
              values = function()
                  local list = {}
                  for _, name in ipairs(ns.Media:List("statusbar")) do list[#list + 1] = { value = name, text = name } end
                  return list
              end,
              get = function() return self.db.texture end,
              set = function(v) self.db.texture = v; if self.enabled then self:Refresh() end end },
            { type = "Button", label = L["Preview"], func = function() self:Preview() end },
        }
    end,
})

local f, sb, icon, nameText, targetText, timerText, flash, shield, importantFill, glow
local ticker, hideTimer, durObj
local previewing = false
local lastNotInterruptible, lastImportant -- kept (maybe secret) for repaints when our kick changes
local kickSpell

local function Color(c) return CreateColor(c[1], c[2], c[3], c[4] or 1) end

---------------------------------------------------------------------------
-- Our interrupt
---------------------------------------------------------------------------

local function Knows(id)
    if IsPlayerSpell and IsPlayerSpell(id) then return true end
    if C_SpellBook.IsSpellKnown(id) then return true end
    return Enum.SpellBookSpellBank and C_SpellBook.IsSpellKnown(id, Enum.SpellBookSpellBank.Pet) or false
end

local function FindKick()
    kickSpell = nil
    for _, id in ipairs(ns.Data.Interrupts[ns.Player.class] or {}) do
        if Knows(id) then kickSpell = id return end
    end
end

-- true / false; unknown readiness counts as ready (don't show "on cooldown" on a guess).
local function KickReady()
    if not kickSpell then return true end
    return ns.Readiness:IsReady(kickSpell) ~= false
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function MakeGlow(parent)
    local g = CreateFrame("Frame", nil, parent)
    g:SetPoint("TOPLEFT", -2, 2)
    g:SetPoint("BOTTOMRIGHT", 2, -2)
    g.pulse = CreateFrame("Frame", nil, g)
    g.pulse:SetAllPoints()
    g.edges = {}
    for i = 1, 4 do g.edges[i] = g.pulse:CreateTexture(nil, "OVERLAY") end
    local e = g.edges
    e[1]:SetPoint("TOPLEFT"); e[1]:SetPoint("TOPRIGHT"); e[1]:SetHeight(2)
    e[2]:SetPoint("BOTTOMLEFT"); e[2]:SetPoint("BOTTOMRIGHT"); e[2]:SetHeight(2)
    e[3]:SetPoint("TOPLEFT"); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetWidth(2)
    e[4]:SetPoint("TOPRIGHT"); e[4]:SetPoint("BOTTOMRIGHT"); e[4]:SetWidth(2)
    local ag = g.pulse:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetDuration(0.45)
    g.anim = ag
    g:Hide()
    return g
end

local function EnsureFrame()
    if f then return end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("MEDIUM")
    ns.Theme:Skin(f, { 0.05, 0.05, 0.06, 0.85 }, { 0, 0, 0, 1 })
    icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    sb = CreateFrame("StatusBar", nil, f)
    sb:SetMinMaxValues(0, 1)
    -- Important-cast colour as an overlay on the filled part, shown by the engine from the
    -- (maybe secret) important flag. It sits over the kick/locked colour.
    importantFill = sb:CreateTexture(nil, "ARTWORK", nil, 2)
    importantFill:SetAllPoints(sb:GetStatusBarTexture())
    shield = sb:CreateTexture(nil, "OVERLAY", nil, 3)
    shield:SetAtlas("nameplates-InterruptShield")
    nameText = sb:CreateFontString(nil, "OVERLAY")
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    targetText = sb:CreateFontString(nil, "OVERLAY")
    targetText:SetJustifyH("RIGHT")
    targetText:SetWordWrap(false)
    timerText = sb:CreateFontString(nil, "OVERLAY")
    timerText:SetJustifyH("RIGHT")
    flash = sb:CreateTexture(nil, "OVERLAY", nil, 7)
    flash:SetAllPoints()
    flash:Hide()
    glow = MakeGlow(f)
    f:Hide()
    ns.Movers:Register("FocusCastBar", {
        label = L["Focus cast bar"], getFrame = function() return f end, default = { x = 0, y = -160 },
    })
end

function M:Refresh()
    if not f then return end
    local db = self.db
    f:SetSize(db.width, db.height)
    local inner = db.height - 2
    icon:SetSize(inner, inner)
    icon:SetShown(db.showIcon)
    sb:ClearAllPoints()
    sb:SetPoint("BOTTOMRIGHT", -1, 1)
    sb:SetPoint("TOPLEFT", db.showIcon and (inner + 2) or 1, -1)
    sb:SetStatusBarTexture(ns.Media:Fetch("statusbar", db.texture))
    importantFill:SetAllPoints(sb:GetStatusBarTexture())
    importantFill:SetTexture(ns.Media:Fetch("statusbar", db.texture))
    local ic = db.importantColor
    importantFill:SetVertexColor(ic[1], ic[2], ic[3], ic[4] or 1)
    for _, fs in ipairs({ nameText, targetText, timerText }) do
        fs:SetFont(ns.Theme:Font(), db.fontSize, "OUTLINE")
    end
    local s = inner + 4
    shield:SetSize(s * 0.8, s)
    shield:ClearAllPoints()
    shield:SetPoint("CENTER", sb, "LEFT", 0, 0)
    timerText:ClearAllPoints()
    timerText:SetPoint("RIGHT", -4, 0)
    timerText:SetShown(db.showTimer)
    targetText:ClearAllPoints()
    targetText:SetPoint("RIGHT", db.showTimer and timerText or sb, db.showTimer and "LEFT" or "RIGHT", -6, 0)
    targetText:SetWidth(db.width * 0.35)
    targetText:SetShown(db.showTarget)
    nameText:ClearAllPoints()
    nameText:SetPoint("LEFT", 4, 0)
    nameText:SetPoint("RIGHT", db.showTarget and targetText or (db.showTimer and timerText or sb),
        (db.showTarget or db.showTimer) and "LEFT" or "RIGHT", -4, 0)
    local c = db.interruptedColor
    flash:SetColorTexture(c[1], c[2], c[3], 1)
    local g = db.glowColor
    for i = 1, 4 do glow.edges[i]:SetColorTexture(g[1], g[2], g[3], g[4] or 1) end
end

---------------------------------------------------------------------------
-- Painting (all secret-safe)
---------------------------------------------------------------------------

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

local function Tick()
    if durObj and M.db.showTimer then
        timerText:SetFormattedText("%.1f", durObj:GetRemainingDuration())
    end
end

local function Hide()
    StopTicker()
    durObj, lastNotInterruptible, lastImportant = nil, nil, nil
    glow.anim:Stop()
    glow:Hide()
    if f and not previewing then f:Hide() end
end

-- Base colour: locked vs kick (ready / not ready). notInterruptible may be secret.
local function PaintInterruptible(notInterruptible)
    local db = M.db
    local kick = (db.kickTint and not KickReady()) and db.kickNotReadyColor or db.kickColor
    local tex = sb:GetStatusBarTexture()
    if type(notInterruptible) == "nil" then
        tex:SetVertexColor(kick[1], kick[2], kick[3], kick[4] or 1)
        shield:SetAlpha(0)
    else
        tex:SetVertexColorFromBoolean(notInterruptible, Color(db.lockedColor), Color(kick))
        if db.showShield then shield:SetAlphaFromBoolean(notInterruptible, 1, 0) else shield:SetAlpha(0) end
    end
end

-- Important overlay and glow. important may be secret.
local function PaintImportant(important)
    local db = M.db
    if type(important) == "nil" then
        importantFill:SetAlpha(0)
        glow.anim:Stop()
        glow:Hide()
        return
    end
    if db.importantColorOn then importantFill:SetAlphaFromBoolean(important, 1, 0) else importantFill:SetAlpha(0) end
    if db.importantGlow then
        glow:Show()
        glow:SetAlphaFromBoolean(important, 1, 0) -- the pulse always runs; only its alpha knows the answer
        if not glow.anim:IsPlaying() then glow.anim:Play() end
    else
        glow.anim:Stop()
        glow:Hide()
    end
end

local function PaintTarget()
    if not M.db.showTarget then return end
    targetText:SetText("")
    if not (UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(UNIT)) then return end
    local name = UnitSpellTargetName and UnitSpellTargetName(UNIT)
    if type(name) == "nil" then return end
    targetText:SetText(name)
    targetText:SetTextColor(1, 1, 1, 1)
    if M.db.targetClassColor and UnitSpellTargetClass and C_ClassColor then
        local class = UnitSpellTargetClass(UNIT)
        if type(class) ~= "nil" then
            local col = C_ClassColor.GetClassColor(class)
            if col and not ns.Secret.Is(col) then targetText:SetTextColor(col:GetRGB()) end
        end
    end
end

local function IsImportant(spellID)
    if not (C_Spell.IsSpellImportant and type(spellID) ~= "nil") then return nil end
    return C_Spell.IsSpellImportant(spellID)
end

-- Reads the focus's current cast or channel and arms the bar, or hides it.
local function Update()
    if not f or previewing then return end
    if hideTimer then return end -- showing "Interrupted"
    local name, _, tex, _, _, _, _, notInterruptible, spellID = UnitCastingInfo(UNIT)
    local dur, direction
    if type(name) ~= "nil" then
        dur = UnitCastingDuration(UNIT)
        direction = Enum.StatusBarTimerDirection.ElapsedTime
    else
        local isEmpowered
        name, _, tex, _, _, _, notInterruptible, spellID, isEmpowered = UnitChannelInfo(UNIT)
        if type(name) == "nil" then Hide() return end
        if isEmpowered and UnitEmpoweredChannelDuration then
            dur = UnitEmpoweredChannelDuration(UNIT, true)
            direction = Enum.StatusBarTimerDirection.ElapsedTime -- empowers build up
        else
            dur = UnitChannelDuration(UNIT)
            direction = Enum.StatusBarTimerDirection.RemainingTime -- channels drain
        end
    end
    if not dur then Hide() return end
    durObj = dur
    flash:Hide()
    nameText:SetText(name)
    icon:SetTexture(tex)
    sb:SetTimerDuration(dur, Enum.StatusBarInterpolation.Immediate, direction)
    lastNotInterruptible, lastImportant = notInterruptible, IsImportant(spellID)
    PaintInterruptible(lastNotInterruptible)
    PaintImportant(lastImportant)
    PaintTarget()
    timerText:SetText("")
    f:Show()
    if not ticker then ticker = C_Timer.NewTicker(0.1, Tick) end
    Tick()
end

-- Our interrupt came off (or went on) cooldown mid-cast: repaint the base colour only.
local function RepaintKick()
    if f and f:IsShown() and durObj and not previewing then PaintInterruptible(lastNotInterruptible) end
end

local function Interrupted()
    if not (f and f:IsShown()) or previewing then return end
    StopTicker()
    durObj = nil
    glow.anim:Stop()
    glow:Hide()
    importantFill:SetAlpha(0)
    shield:SetAlpha(0)
    flash:Show()
    nameText:SetText(L["Interrupted"])
    targetText:SetText("")
    timerText:SetText("")
    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer(0.8, function()
        hideTimer = nil
        flash:Hide()
        Update()
    end)
end

-- Fake important cast so the bar can be placed and styled without a focus target.
function M:Preview()
    EnsureFrame()
    self:Refresh()
    previewing = true
    StopTicker()
    flash:Hide()
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0.6)
    PaintInterruptible(false)
    PaintImportant(true)
    nameText:SetText(L["Focus cast bar"])
    targetText:SetText(UnitName("player"))
    icon:SetTexture(136243) -- generic spell book icon
    timerText:SetText("1.2")
    f:Show()
    self:After(5, function()
        previewing = false
        Update()
    end)
end

local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE", "UNIT_SPELLCAST_EMPOWER_STOP",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE", "UNIT_SPELLCAST_SUCCEEDED",
}

function M:OnEnable()
    EnsureFrame()
    self:Refresh()
    FindKick()
    -- Payloads are ignored (they can be secret); every event just re-reads the unit.
    for _, ev in ipairs(CAST_EVENTS) do
        ns.Events:OnUnit(ev, { UNIT }, self, function() Update() end)
    end
    ns.Events:OnUnit("UNIT_SPELLCAST_INTERRUPTED", { UNIT }, self, function() Interrupted() end)
    ns.Events:On("PLAYER_FOCUS_CHANGED", self, function()
        if hideTimer then hideTimer:Cancel(); hideTimer = nil end
        Update()
    end)
    ns.Events:On("SPELL_UPDATE_COOLDOWN", self, RepaintKick)
    ns.Events:On("OUI_SPEC_CHANGED", self, FindKick)
    ns.Events:On("SPELLS_CHANGED", self, FindKick)
    Update()
end

function M:OnDisable()
    StopTicker()
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    previewing = false
    if glow then glow.anim:Stop(); glow:Hide() end
    if f then f:Hide() end
end

ns.FocusCastBarKick = function() return kickSpell end -- for /oui check interrupts
