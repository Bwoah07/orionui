-- Our own edit mode: a grid and a draggable overlay per registered mover.
-- Drag to move (snaps to the grid when enabled), arrow keys nudge the selected mover
-- by 1px (Shift: 10px), right-click resets it. Refuses to open in combat.
local _, ns = ...

local L = ns.L
local EditMode = { overlays = {} }
ns.EditMode = EditMode

local root, grid, selected

local function Snap(v, size)
    return math.floor(v / size + 0.5) * size
end

local function BuildGrid()
    grid = grid or {}
    for _, t in ipairs(grid) do t:Hide() end
    local size = ns.Movers.module.db.gridSize
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local n = 0
    local function Line(vertical, offset, center)
        n = n + 1
        local t = grid[n] or root:CreateTexture(nil, "BACKGROUND")
        grid[n] = t
        t:ClearAllPoints()
        if center then t:SetColorTexture(ns.Theme:Accent()) t:SetAlpha(0.5)
        else t:SetColorTexture(1, 1, 1, 0.07) t:SetAlpha(1) end
        if vertical then
            t:SetSize(1, h)
            t:SetPoint("CENTER", root, "CENTER", offset, 0)
        else
            t:SetSize(w, 1)
            t:SetPoint("CENTER", root, "CENTER", 0, offset)
        end
        t:Show()
    end
    for x = 0, w / 2, size do
        Line(true, x, x == 0)
        if x > 0 then Line(true, -x) end
    end
    for y = 0, h / 2, size do
        Line(false, y, y == 0)
        if y > 0 then Line(false, -y) end
    end
end

local function Select(overlay)
    selected = overlay
    local r, g, b = ns.Theme:Accent()
    for _, o in pairs(EditMode.overlays) do
        local on = o == overlay
        o.bg:SetColorTexture(r, g, b, on and 0.45 or 0.25)
    end
end

local function OverlayFor(mover)
    local o = EditMode.overlays[mover.key]
    if o then return o end
    o = CreateFrame("Button", nil, root)
    o:SetFrameStrata("TOOLTIP")
    o:SetMovable(true)
    o:RegisterForDrag("LeftButton")
    o:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    o.bg = o:CreateTexture(nil, "BACKGROUND")
    o.bg:SetAllPoints()
    ns.Theme:Skin(o, { 0, 0, 0, 0 })
    o.text = ns.Theme:Text(o, 11)
    o.text:SetPoint("CENTER")
    o.text:SetJustifyH("CENTER")
    o.mover = mover
    o:SetScript("OnDragStart", function(self) Select(self) self:StartMoving() end)
    o:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local x, y = cx - ux, cy - uy
        local db = ns.Movers.module.db
        if db.snap and not IsShiftKeyDown() then x, y = Snap(x, db.gridSize), Snap(y, db.gridSize) end
        ns.Movers:Save(mover.key, x, y)
        EditMode:Place(self)
    end)
    o:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ns.Movers:Reset(mover.key)
            EditMode:Place(self)
        end
        Select(self)
    end)
    EditMode.overlays[mover.key] = o
    return o
end

-- Puts an overlay exactly over its frame (or at the saved spot if the frame is hidden).
function EditMode:Place(o)
    local f = o.mover.getFrame()
    local w, h = 120, 30
    if f and f:GetWidth() > 0 then w, h = f:GetWidth() * f:GetEffectiveScale() / UIParent:GetEffectiveScale(), f:GetHeight() * f:GetEffectiveScale() / UIParent:GetEffectiveScale() end
    local p = ns.Movers.module.db.positions[o.mover.key] or o.mover.default
    o:ClearAllPoints()
    o:SetSize(math.max(w, 40), math.max(h, 16))
    o:SetPoint("CENTER", UIParent, "CENTER", p.x or 0, p.y or 0)
    o.text:SetText(o.mover.label)
end

local function Nudge(dx, dy)
    if not selected then return end
    local key = selected.mover.key
    local p = ns.Movers.module.db.positions[key] or selected.mover.default
    ns.Movers:Save(key, (p.x or 0) + dx, (p.y or 0) + dy)
    EditMode:Place(selected)
end

local function Create()
    root = CreateFrame("Frame", "OrionUIEditMode", UIParent) -- global name: Esc closes via UISpecialFrames
    root:SetAllPoints()
    root:SetFrameStrata("FULLSCREEN")
    root:EnableKeyboard(true)
    root:SetPropagateKeyboardInput(true)
    tinsert(UISpecialFrames, "OrionUIEditMode")
    local shade = root:CreateTexture(nil, "BACKGROUND", nil, -8)
    shade:SetAllPoints()
    shade:SetColorTexture(0, 0, 0, 0.35)

    local bar = CreateFrame("Frame", nil, root)
    bar:SetSize(420, 40)
    bar:SetPoint("TOP", 0, -40)
    ns.Theme:Skin(bar, ns.Theme.colors.bg)
    local hint = ns.Theme:Text(bar, 11, ns.Theme.colors.muted)
    hint:SetPoint("LEFT", 10, 0)
    hint:SetText(L["Drag to move. Arrows nudge, right-click resets, Shift ignores the grid."])
    hint:SetWidth(300)
    local done = ns.Theme:Button(bar, L["Done"], 80, 24)
    done:SetPoint("RIGHT", -8, 0)
    done:SetScript("OnClick", function() EditMode:Toggle(false) end)

    root:SetScript("OnKeyDown", function(self, key)
        local step = IsShiftKeyDown() and 10 or 1
        local moves = { UP = { 0, step }, DOWN = { 0, -step }, LEFT = { -step, 0 }, RIGHT = { step, 0 } }
        local m = moves[key]
        -- Only swallow arrow keys while something is selected; everything else passes through.
        self:SetPropagateKeyboardInput(not (m and selected))
        if m and selected then Nudge(m[1], m[2]) end
    end)
    root:SetScript("OnHide", function()
        for _, o in pairs(EditMode.overlays) do o:Hide() end
        selected = nil
    end)
    root:Hide()
end

function EditMode:Toggle(show)
    if show == nil then show = not (root and root:IsShown()) end
    if show and InCombatLockdown() then
        ns.Print(L.COMBAT_REFUSED)
        return
    end
    if not root then Create() end
    if not show then
        root:Hide()
        ns.Events:Fire("OUI_EDIT_MODE", false)
        -- Bring the options back if edit mode was opened from them.
        if self.reopenOptions then
            self.reopenOptions = nil
            ns.Options:Open()
        end
        return
    end
    -- The options window would sit on top of the frames being moved.
    if OrionUIOptions and OrionUIOptions:IsShown() then
        OrionUIOptions:Hide()
        self.reopenOptions = true
    end
    root:Show()
    BuildGrid()
    if #ns.Movers.list == 0 then ns.Print(L["Nothing to move yet."]) end
    for _, mover in ipairs(ns.Movers.list) do
        -- Frames attached to a Cooldown Manager row move with the row, not on their own.
        if not (mover.attached and mover.attached()) then
            local o = OverlayFor(mover)
            self:Place(o)
            o:Show()
        end
    end
    Select(nil)
    -- Other movable things (the built-in RaidControl's own layout mode) follow ours.
    ns.Events:Fire("OUI_EDIT_MODE", true)
end

-- Leave edit mode when combat starts; SetPropagateKeyboardInput is protected in combat.
ns.Events:On("PLAYER_REGEN_DISABLED", EditMode, function()
    if root and root:IsShown() then root:Hide() end
end)
EditMode.name = "EditMode"
