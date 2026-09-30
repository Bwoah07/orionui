-- Focus cast bar: what your focus target is casting, with an interrupt colour.
--
-- 12.x rules (CLAUDE.md §4): UnitCastingInfo/UnitChannelInfo are SecretWhenUnitSpellCastRestricted,
-- so in combat the name, icon, times and notInterruptible can all be secret. We never read
-- them in Lua: the name and icon go straight into SetText/SetTexture, the bar is driven by the
-- engine from UnitCastingDuration/UnitChannelDuration duration objects (SetTimerDuration), the
-- timer text from the duration object, and the interrupt colour from SetVertexColorFromBoolean.
-- Existence is tested with type(), which is safe on secrets. isEmpowered is NeverSecret.
local _, ns = ...

local L = ns.L
local S = ns.Schema

local UNIT = "focus"

local M = ns.Modules:New("FocusCastBar", {
    category = "qol", label = L["Focus cast bar"],
    desc = L["A cast bar for your focus target, coloured by whether the cast can be interrupted."],
    profileKey = "layout",
    schema = S.Table{ fields = {
        width = S.Number{ default = 260, min = 100, max = 600, step = 2, label = L["Width"], order = 1 },
        height = S.Number{ default = 22, min = 10, max = 60, step = 1, label = L["Height"], order = 2 },
        showIcon = S.Bool{ default = true, label = L["Show spell icon"], order = 3 },
        showTimer = S.Bool{ default = true, label = L["Show time left"], order = 4 },
        fontSize = S.Number{ default = 12, min = 8, max = 24, step = 1, label = L["Text size"], order = 5 },
        texture = S.String{ default = "Orion Flat", hidden = true },
        kickColor = S.Color{ default = { 0.95, 0.65, 0.15, 1 }, label = L["Interruptible"], order = 10 },
        lockedColor = S.Color{ default = { 0.55, 0.55, 0.6, 1 }, label = L["Can't be interrupted"], order = 11 },
        interruptedColor = S.Color{ default = { 0.85, 0.2, 0.2, 1 }, label = L["Interrupted"], order = 12 },
    } },
    options = function(self)
        return {
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

local f, sb, icon, nameText, timerText, flash
local ticker, hideTimer, durObj
local previewing = false

local function Color(c) return CreateColor(c[1], c[2], c[3], c[4] or 1) end

local function EnsureFrame()
    if f then return end
    f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("MEDIUM")
    ns.Theme:Skin(f, { 0.05, 0.05, 0.06, 0.85 }, { 0, 0, 0, 1 })
    icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    sb = CreateFrame("StatusBar", nil, f)
    sb:SetPoint("BOTTOMRIGHT", -1, 1)
    sb:SetMinMaxValues(0, 1)
    nameText = sb:CreateFontString(nil, "OVERLAY")
    nameText:SetPoint("LEFT", 4, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    timerText = sb:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("RIGHT", -4, 0)
    timerText:SetJustifyH("RIGHT")
    nameText:SetPoint("RIGHT", timerText, "LEFT", -4, 0)
    -- Interrupted flash: a plain overlay, so we never have to take the bar off its engine timer.
    flash = sb:CreateTexture(nil, "ARTWORK", nil, 7)
    flash:SetAllPoints()
    flash:Hide()
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
    for _, fs in ipairs({ nameText, timerText }) do
        fs:SetFont(ns.Theme:Font(), db.fontSize, "OUTLINE")
    end
    timerText:SetShown(db.showTimer)
    local c = db.interruptedColor
    flash:SetColorTexture(c[1], c[2], c[3], 1)
end

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
    durObj = nil
    if f and not previewing then f:Hide() end
end

-- Paints the bar colour from notInterruptible without reading it (it may be secret).
local function PaintInterruptible(notInterruptible)
    local tex = sb:GetStatusBarTexture()
    if type(notInterruptible) == "nil" then
        local c = M.db.kickColor
        tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    else
        tex:SetVertexColorFromBoolean(notInterruptible, Color(M.db.lockedColor), Color(M.db.kickColor))
    end
end

-- Reads the focus's current cast or channel and arms the bar, or hides it.
local function Update()
    if not f or previewing then return end
    if hideTimer then return end -- showing "Interrupted"
    local name, _, tex, _, _, _, _, notInterruptible = UnitCastingInfo(UNIT)
    local dur, direction
    if type(name) ~= "nil" then
        dur = UnitCastingDuration(UNIT)
        direction = Enum.StatusBarTimerDirection.ElapsedTime
    else
        local isEmpowered
        name, _, tex, _, _, _, notInterruptible, _, isEmpowered = UnitChannelInfo(UNIT)
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
    PaintInterruptible(notInterruptible)
    timerText:SetText("")
    f:Show()
    if not ticker then ticker = C_Timer.NewTicker(0.1, Tick) end
    Tick()
end

local function Interrupted()
    if not (f and f:IsShown()) or previewing then return end
    StopTicker()
    durObj = nil
    flash:Show()
    nameText:SetText(L["Interrupted"])
    timerText:SetText("")
    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer(0.8, function()
        hideTimer = nil
        flash:Hide()
        Update()
    end)
end

-- Fake cast so the bar can be placed and styled without a focus target.
function M:Preview()
    EnsureFrame()
    self:Refresh()
    previewing = true
    StopTicker()
    flash:Hide()
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0.6)
    PaintInterruptible(nil)
    nameText:SetText(L["Focus cast bar"])
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
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

function M:OnEnable()
    EnsureFrame()
    self:Refresh()
    -- Payloads are ignored (they can be secret); every event just re-reads the unit.
    for _, ev in ipairs(CAST_EVENTS) do
        ns.Events:OnUnit(ev, { UNIT }, self, function() Update() end)
    end
    ns.Events:OnUnit("UNIT_SPELLCAST_INTERRUPTED", { UNIT }, self, function() Interrupted() end)
    ns.Events:On("PLAYER_FOCUS_CHANGED", self, function()
        if hideTimer then hideTimer:Cancel(); hideTimer = nil end
        Update()
    end)
    Update()
end

function M:OnDisable()
    StopTicker()
    if hideTimer then hideTimer:Cancel(); hideTimer = nil end
    previewing = false
    if f then f:Hide() end
end
