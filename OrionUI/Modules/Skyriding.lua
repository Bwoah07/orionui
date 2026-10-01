-- Skyriding display: vigor and Second Wind as segmented bars, plus a speed bar, in OrionUI's
-- look (flat fill, dark background, 1px border, our accent, EUI's font). Blizzard's own vigor
-- display is faded out while ours shows.
--
-- Where the numbers come from (checked in wow-ui-source and EllesmereUI's source, 2026-10-01):
--   vigor        = charges of Skyward Ascent (C_Spell.GetSpellCharges(372610)), 6 at max
--   Second Wind  = charges of Second Wind (425782), 3 at max; nil when not learned
--   speed        = C_PlayerInfo.GetGlidingInfo() -> isGliding, canGlide, forwardSpeed. Not secret.
--                  forwardSpeed / 7 (base run speed) * 100 = percent of run speed.
--   on a skyriding mount = canGlide (also true for Soar and similar glide forms)
--
-- 12.x rules (CLAUDE.md §4): GetSpellCharges is SecretWhenCooldownsRestricted. maxCharges and
-- isActive are NeverSecret, the rest can be secret (combat). When currentCharges is secret we
-- can't pick which pip is full, so the row switches to one engine-filled bar with dividers
-- (StatusBar:SetValue accepts secrets) until the value is readable again.
--
-- Blizzard's vigor widget sits in UIWidgetPowerBarContainerFrame (the power-bar widget set it
-- arms on mounting). We only ever change that frame's alpha, and only while the player can glide,
-- so other power-bar widgets (encounters, zones) are never touched. [VERIFY in game]
local _, ns = ...

local L = ns.L
local S = ns.Schema

local GetTime = GetTime
local floor, max, min = math.floor, math.max, math.min

local SKYWARD_ASCENT = 372610
local SECOND_WIND = 425782
local BASE_RUN_SPEED = 7 -- yards per second at 100% speed
local TICK = 0.05
local RECHARGE_ALPHA = 0.45 -- the segment that is filling up is drawn see-through

local M = ns.Modules:New("Skyriding", {
    category = "qol", label = L["Skyriding"], order = 5,
    desc = L["Vigor and Second Wind as segmented bars plus a speed bar while you are on a skyriding mount. Hides Blizzard's vigor display while it shows."],
    profileKey = "layout",
    schema = S.Table{ fields = {
        -- When it shows
        showWhen = S.Enum{ section = L["When it shows"], default = "mounted", values = { "mounted", "flying" },
            valueLabels = { mounted = L["On a skyriding mount"], flying = L["Only while flying"] },
            label = L["Show"], order = 1 },
        hideInCombat = S.Bool{ section = L["When it shows"], default = false, label = L["Hide in combat"], order = 2 },
        hideBlizzard = S.Bool{ section = L["When it shows"], default = true, label = L["Hide Blizzard's vigor display while this shows"], order = 3 },
        -- Position
        cdmSpot = S.Bool{ section = L["Position"], default = true, label = L["Take the Cooldown Manager's place and width"], order = 5,
            desc = L["Sits where the essential cooldowns row is (it hides while you skyride) and matches its width. Switch off to place it yourself in /oui edit."] },
        -- Size
        width = S.Number{ section = L["Size"], default = 240, min = 100, max = 500, step = 2, label = L["Width (when placed yourself)"], order = 10 },
        vigorHeight = S.Number{ section = L["Size"], default = 12, min = 4, max = 40, step = 1, label = L["Vigor height"], order = 11 },
        secondWindHeight = S.Number{ section = L["Size"], default = 6, min = 2, max = 30, step = 1, label = L["Second Wind height"], order = 12 },
        speedHeight = S.Number{ section = L["Size"], default = 14, min = 4, max = 40, step = 1, label = L["Speed height"], order = 13 },
        segmentGap = S.Number{ section = L["Size"], default = 2, min = 0, max = 10, step = 1, label = L["Gap between segments"], order = 14 },
        rowGap = S.Number{ section = L["Size"], default = 2, min = 0, max = 20, step = 1, label = L["Gap between bars"], order = 15 },
        -- Speed
        showSpeed = S.Bool{ section = L["Speed"], default = true, label = L["Show speed bar"], order = 20 },
        showSpeedText = S.Bool{ section = L["Speed"], default = true, label = L["Show speed as a number"], order = 21 },
        fontSize = S.Number{ section = L["Speed"], default = 11, min = 7, max = 24, step = 1, label = L["Text size"], order = 22 },
        maxSpeed = S.Number{ section = L["Speed"], default = 1200, min = 400, max = 2000, step = 50, label = L["Full bar at (% of run speed)"], order = 23 },
        fastAt = S.Number{ section = L["Speed"], default = 790, min = 100, max = 2000, step = 10, label = L["Fast colour from (% of run speed)"], order = 24,
            desc = L["Around this speed the game grants Thrill of the Skies, which makes vigor recharge faster. A thin tick marks it on the bar."] },
        -- Bars
        showSecondWind = S.Bool{ section = L["Bars"], default = true, label = L["Show Second Wind"], order = 30 },
        vigorColor = S.Color{ section = L["Colours"], default = { 0.15, 0.45, 0.85, 1 }, label = L["Vigor"], order = 40 },
        secondWindColor = S.Color{ section = L["Colours"], default = { 0.85, 0.7, 0.2, 1 }, label = L["Second Wind"], order = 42 },
        speedColor = S.Color{ section = L["Colours"], default = { 0.55, 0.6, 0.7, 1 }, label = L["Speed"], order = 43 },
        fastColor = S.Color{ section = L["Colours"], default = { 0.3, 0.8, 0.95, 1 }, label = L["Speed, fast"], order = 44 },
        texture = S.String{ default = "Orion Flat", hidden = true },
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

local BG = { 0.05, 0.05, 0.06, 0.85 }
local BORDER = { 0, 0, 0, 1 }

local root, speedRow, vigorRow, windRow
local ticker
local previewing, editing = false, false
local hidBlizzard = false
local lastSpeedPct = -1
local curWidth, lastCDMWidth -- width taken from the cooldowns row (nil = our own setting)

local function Width() return curWidth or M.db.width end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------

local function Texture() return ns.Media:Fetch("statusbar", M.db.texture) end

local function NewBar(parent)
    local sb = CreateFrame("StatusBar", nil, parent)
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    return sb
end

-- A segmented row: one skinned box per segment, each with its own bar. `whole` is the
-- secret-value fallback: one bar across the row with dividers drawn over it.
local function NewRow()
    local row = CreateFrame("Frame", nil, root)
    row.segs = {}
    row.count = 0
    row.whole = CreateFrame("Frame", nil, row)
    row.whole:SetAllPoints()
    ns.Theme:Skin(row.whole, BG, BORDER)
    row.whole.bar = NewBar(row.whole)
    row.whole.bar:SetPoint("TOPLEFT", 1, -1)
    row.whole.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    row.whole.dividers = {}
    row.whole:Hide()
    return row
end

local function Segment(row, i)
    local seg = row.segs[i]
    if seg then return seg end
    seg = CreateFrame("Frame", nil, row)
    ns.Theme:Skin(seg, BG, BORDER)
    seg.bar = NewBar(seg)
    seg.bar:SetPoint("TOPLEFT", 1, -1)
    seg.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    row.segs[i] = seg
    return seg
end

-- Lays out `n` segments across the row's width.
local function LayoutRow(row, n, height)
    local db = M.db
    row.count = n
    row:SetSize(Width(), height)
    local gap = db.segmentGap
    local w = n > 0 and (Width() - gap * (n - 1)) / n or Width()
    local tex = Texture()
    for i = 1, max(n, #row.segs) do
        local seg = Segment(row, i)
        if i <= n then
            seg:ClearAllPoints()
            seg:SetSize(w, height)
            seg:SetPoint("LEFT", row, "LEFT", (i - 1) * (w + gap), 0)
            seg.bar:SetStatusBarTexture(tex)
            seg:Show()
        else
            seg:Hide()
        end
    end
    local whole = row.whole
    whole.bar:SetStatusBarTexture(tex)
    whole.bar:SetMinMaxValues(0, max(n, 1))
    for i = 1, max(n - 1, #whole.dividers) do
        local d = whole.dividers[i]
        if not d then
            d = whole.bar:CreateTexture(nil, "OVERLAY")
            d:SetColorTexture(BORDER[1], BORDER[2], BORDER[3], 1)
            whole.dividers[i] = d
        end
        if i < n then
            d:ClearAllPoints()
            d:SetSize(max(gap, 1), height)
            d:SetPoint("CENTER", row, "LEFT", i * (w + gap) - gap / 2, 0)
            d:Show()
        else
            d:Hide()
        end
    end
end

local function EnsureFrames()
    if root then return end
    root = CreateFrame("Frame", nil, UIParent)
    root:SetFrameStrata("MEDIUM")
    root:Hide()

    speedRow = CreateFrame("Frame", nil, root)
    ns.Theme:Skin(speedRow, BG, BORDER)
    speedRow.bar = NewBar(speedRow)
    speedRow.bar:SetPoint("TOPLEFT", 1, -1)
    speedRow.bar:SetPoint("BOTTOMRIGHT", -1, 1)
    speedRow.tick = speedRow.bar:CreateTexture(nil, "OVERLAY")
    speedRow.tick:SetColorTexture(1, 1, 1, 0.6)
    speedRow.text = speedRow.bar:CreateFontString(nil, "OVERLAY")
    speedRow.text:SetPoint("CENTER")

    vigorRow = NewRow()
    windRow = NewRow()

    M.mover = ns.Movers:Register("Skyriding", {
        label = L["Skyriding"], getFrame = function() return root end, default = { x = 0, y = -220 },
        attached = function() return M.db.cdmSpot and ns.CDMAnchor:Row("cooldowns") ~= nil end,
        detach = function() M.db.cdmSpot = false; M:Refresh() end,
    })
end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

local function SetColor(bar, c, alpha)
    bar:SetStatusBarColor(c[1], c[2], c[3], alpha or c[4] or 1)
end

-- Readable charges: full segments, one partly filled while it recharges, the rest empty.
local function PaintSegments(row, cur, progress, color)
    row.whole:Hide()
    for i = 1, row.count do
        local seg = row.segs[i]
        seg:Show()
        if i <= cur then
            seg.bar:SetValue(1)
            SetColor(seg.bar, color)
        elseif i == cur + 1 then
            seg.bar:SetValue(progress)
            SetColor(seg.bar, color, RECHARGE_ALPHA)
        else
            seg.bar:SetValue(0)
        end
    end
end

-- Secret charges: the engine fills one bar from the value we can't read.
local function PaintWhole(row, cur, color)
    for i = 1, row.count do row.segs[i]:Hide() end
    row.whole:Show()
    SetColor(row.whole.bar, color)
    row.whole.bar:SetValue(cur)
end

-- -> current (maybe secret), max, recharge progress 0..1 (0 when unknown), secret?
local function ReadCharges(spell)
    local info = C_Spell.GetSpellCharges(spell)
    if not info then return nil end
    local cur = info.currentCharges
    if ns.Secret.Is(cur) then return cur, info.maxCharges, 0, true end
    local progress = 0
    local start, dur = info.cooldownStartTime, info.cooldownDuration
    if info.isActive and not ns.Secret.Is(start) and not ns.Secret.Is(dur) and dur and dur > 0 then
        progress = max(0, min(1, (GetTime() - start) / dur))
    end
    return cur, info.maxCharges, progress, false
end

-- -> true while anything is still recharging (keeps the ticker alive).
local function PaintChargeRow(row, spell, color, height)
    local cur, maxC, progress, secret = ReadCharges(spell)
    if not cur or not maxC or maxC < 1 then
        row:Hide()
        return false
    end
    if row.count ~= maxC then LayoutRow(row, maxC, height) end
    row:Show()
    if secret then
        PaintWhole(row, cur, color)
        return true -- keep checking; it turns readable again after combat
    end
    PaintSegments(row, cur, progress, color)
    return cur < maxC
end

local function PaintSpeed(pct)
    local db = M.db
    local frac = db.maxSpeed > 0 and max(0, min(1, pct / db.maxSpeed)) or 0
    speedRow.bar:SetValue(frac, Enum.StatusBarInterpolation.ExponentialEaseOut)
    SetColor(speedRow.bar, pct >= db.fastAt and db.fastColor or db.speedColor)
    local shown = floor(pct + 0.5)
    if db.showSpeedText and shown ~= lastSpeedPct then
        speedRow.text:SetFormattedText("%d%%", shown)
    end
    lastSpeedPct = shown
end

-- One pass over everything; -> true while the ticker is still needed.
local function Paint()
    local db = M.db
    local busy = false
    if db.showSpeed then
        local isGliding, _, forward = C_PlayerInfo.GetGlidingInfo()
        local pct = isGliding and (forward or 0) / BASE_RUN_SPEED * 100 or 0
        PaintSpeed(pct)
        busy = busy or isGliding
    end
    busy = PaintChargeRow(vigorRow, SKYWARD_ASCENT, db.vigorColor, db.vigorHeight) or busy
    if db.showSecondWind then
        busy = PaintChargeRow(windRow, SECOND_WIND, db.secondWindColor, db.secondWindHeight) or busy
    else
        windRow:Hide()
    end
    return busy
end

local function StopTicker()
    if ticker then ticker:Cancel(); ticker = nil end
end

local function OnTick()
    if previewing or editing then return end
    if not Paint() then StopTicker() end
end

local function StartTicker()
    if not ticker then ticker = C_Timer.NewTicker(TICK, function() ns.SafeCall(M.name, OnTick) end) end
end

---------------------------------------------------------------------------
-- Stacking the rows
---------------------------------------------------------------------------

-- Speed on top, vigor, then Second Wind. Hidden rows take no space.
local function Stack()
    local db = M.db
    local rows = {}
    if db.showSpeed then rows[#rows + 1] = speedRow end
    rows[#rows + 1] = vigorRow
    if db.showSecondWind and windRow:IsShown() then rows[#rows + 1] = windRow end
    local h = 0
    for i, row in ipairs(rows) do
        row:ClearAllPoints()
        row:SetPoint("TOP", root, "TOP", 0, -h)
        h = h + row:GetHeight() + (i < #rows and db.rowGap or 0)
    end
    speedRow:SetShown(db.showSpeed)
    root:SetSize(Width(), max(h, 1))
end

---------------------------------------------------------------------------
-- The Cooldown Manager's spot
---------------------------------------------------------------------------

-- EUI hides the essential cooldowns row while skyriding (Stig, 2026-10-01). A hidden frame keeps
-- its place, so we centre on it; its width is remembered from the last time it measured, in case
-- a hidden row reports no size. -> the row, or nil when we place ourselves.
local function MeasureCDM()
    curWidth = nil
    if not M.db.cdmSpot then return nil end
    local row = ns.CDMAnchor:Row("cooldowns")
    if not row then return nil end
    local w = (row:GetWidth() or 0) * row:GetEffectiveScale() / root:GetEffectiveScale()
    if w > 20 then lastCDMWidth = floor(w + 0.5) end
    curWidth = lastCDMWidth
    return row
end

local function Position(row)
    if row then
        root:ClearAllPoints()
        root:SetPoint("CENTER", row, "CENTER", 0, 0)
    elseif M.mover then
        ns.Movers:Apply(M.mover)
    end
end

local function Layout()
    local db = M.db
    speedRow:SetSize(Width(), db.speedHeight)
    speedRow.bar:SetStatusBarTexture(Texture())
    speedRow.text:SetFont(ns.Theme:Font(), db.fontSize, "OUTLINE")
    speedRow.text:SetShown(db.showSpeedText)
    local tick = db.maxSpeed > 0 and min(1, db.fastAt / db.maxSpeed) or 0
    speedRow.tick:ClearAllPoints()
    speedRow.tick:SetSize(1, db.speedHeight - 2)
    speedRow.tick:SetPoint("LEFT", speedRow.bar, "LEFT", tick * (Width() - 2), 0)
    speedRow.tick:SetShown(tick > 0 and tick < 1)
    LayoutRow(vigorRow, vigorRow.count > 0 and vigorRow.count or 6, db.vigorHeight)
    LayoutRow(windRow, windRow.count > 0 and windRow.count or 3, db.secondWindHeight)
    lastSpeedPct = -1
    Stack() -- sizes the frame even while hidden, so edit mode outlines it correctly
end

function M:Refresh()
    if not root then return end
    Position(MeasureCDM())
    Layout()
    if previewing or editing then self:ShowFake() else self:Update() end
end

---------------------------------------------------------------------------
-- Blizzard's vigor display
---------------------------------------------------------------------------

local function BlizzardFrame() return _G.UIWidgetPowerBarContainerFrame end

local function SetBlizzardHidden(hide)
    local f = BlizzardFrame()
    if not f then return end
    if hide and not hidBlizzard then
        f:SetAlpha(0)
        hidBlizzard = true
    elseif not hide and hidBlizzard then
        f:SetAlpha(1)
        hidBlizzard = false
    end
end

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------

local function Wanted()
    local db = M.db
    local isGliding, canGlide = C_PlayerInfo.GetGlidingInfo()
    if not canGlide then return false end
    if db.showWhen == "flying" and not isGliding then return false end
    if db.hideInCombat and UnitAffectingCombat("player") then return false end
    return true
end

function M:Update()
    if not root or previewing or editing then return end
    local db = self.db
    local _, canGlide = C_PlayerInfo.GetGlidingInfo()
    local show = Wanted()
    -- Measured every time (also while hidden) so the row's width is known before it hides.
    local before = Width()
    Position(MeasureCDM())
    if Width() ~= before then Layout() end
    -- Blizzard's display stays hidden for the whole time on the mount, so it doesn't pop up
    -- between flights when ours is set to "only while flying".
    SetBlizzardHidden(db.hideBlizzard and canGlide == true)
    if not show then
        StopTicker()
        root:Hide()
        return
    end
    root:Show()
    if Paint() then StartTicker() end
    Stack()
end

---------------------------------------------------------------------------
-- Preview and edit mode
---------------------------------------------------------------------------

-- Fake numbers so the bars can be placed and styled on the ground.
function M:ShowFake()
    local db = self.db
    if vigorRow.count ~= 6 then LayoutRow(vigorRow, 6, db.vigorHeight) end
    if windRow.count ~= 3 then LayoutRow(windRow, 3, db.secondWindHeight) end
    vigorRow:Show()
    PaintSegments(vigorRow, 4, 0.6, db.vigorColor)
    windRow:SetShown(db.showSecondWind)
    PaintSegments(windRow, 2, 0.3, db.secondWindColor)
    lastSpeedPct = -1
    PaintSpeed(830)
    Stack()
    root:Show()
end

function M:Preview()
    EnsureFrames()
    previewing = true
    StopTicker()
    self:Refresh()
    if self.previewTimer then self.previewTimer:Cancel() end
    self.previewTimer = self:After(6, function()
        self.previewTimer = nil
        previewing = false
        self:Refresh()
    end)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

local function OnCharges() if root and root:IsShown() and not previewing and not editing then M:Update() end end

function M:OnEnable()
    EnsureFrames()
    self:Refresh()
    local update = function() self:Update() end
    ns.Events:On("PLAYER_ENTERING_WORLD", self, update)
    ns.Events:On("PLAYER_CAN_GLIDE_CHANGED", self, update)
    ns.Events:On("PLAYER_IS_GLIDING_CHANGED", self, update)
    ns.Events:On("PLAYER_MOUNT_DISPLAY_CHANGED", self, update)
    ns.Events:On("PLAYER_REGEN_DISABLED", self, update)
    ns.Events:On("PLAYER_REGEN_ENABLED", self, update)
    ns.Events:On("SPELL_UPDATE_CHARGES", self, OnCharges)
    ns.Events:On("OUI_EDIT_MODE", self, function(_, _, shown)
        editing = shown and true or false
        StopTicker()
        self:Refresh()
    end)
    self:Update()
end

function M:OnDisable()
    StopTicker()
    previewing, editing = false, false
    SetBlizzardHidden(false)
    if root then root:Hide() end
end
