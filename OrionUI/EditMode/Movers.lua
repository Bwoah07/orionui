-- Movable-frame registry and our edit mode (CLAUDE.md §9.2). Positions live in the
-- layout profile (module "EditMode"), stored as CENTER offsets from UIParent's centre.
--
-- When EllesmereUI is loaded, every mover is also registered with EUI's Unlock Mode
-- (EllesmereUI:RegisterUnlockElements, which has no caller whitelist - checked in
-- EUI_UnlockMode.lua on 2026-09-29), so users can place our frames alongside EUI's.
--
--   ns.Movers:Register("BoneShield", { label = "Bone Shield", getFrame = fn,
--       default = { x = 0, y = -180 } })
local _, ns = ...

local L = ns.L
local S = ns.Schema

local Movers = { list = {}, byKey = {} }
ns.Movers = Movers

local M = ns.Modules:New("EditMode", {
    category = "general", label = L["Edit mode"], order = 90,
    profileKey = "layout",
    schema = S.Table{ fields = {
        enabled = S.Bool{ default = true, hidden = true }, -- edit mode can't be switched off
        snap =S.Bool{ default = true, label = L["Snap to grid while dragging"], order = 1 },
        gridSize = S.Number{ default = 16, min = 4, max = 64, step = 4, label = L["Grid size"], order = 2 },
        positions = S.Map{ hidden = true, of = S.Table{ fields = {
            x = S.Number{ default = 0 }, y = S.Number{ default = 0 },
        } } },
    } },
    options = function()
        return { { type = "Button", label = L["Open edit mode"], func = function() ns.EditMode:Toggle() end } }
    end,
})
Movers.module = M

---------------------------------------------------------------------------
-- Positions
---------------------------------------------------------------------------

local function Saved(key)
    return M.db and M.db.positions[key]
end

local function Position(mover)
    local p = Saved(mover.key) or mover.default
    return p.x or 0, p.y or 0
end

function Movers:Apply(mover)
    local f = mover.getFrame()
    if not f then return end
    local x, y = Position(mover)
    ns.Combat:Defer("mover:" .. mover.key, function()
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end)
end

function Movers:ApplyAll()
    for _, mover in ipairs(self.list) do self:Apply(mover) end
end

-- Frame centre -> offset from UIParent centre in UIParent units.
local function CenterOffset(f)
    local cx, cy = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local ratio = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return cx * ratio - ux, cy * ratio - uy
end

function Movers:Save(key, x, y)
    M.db.positions[key] = { x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    local mover = self.byKey[key]
    if mover then self:Apply(mover) end
end

function Movers:Reset(key)
    M.db.positions[key] = nil
    local mover = self.byKey[key]
    if mover then self:Apply(mover) end
end

---------------------------------------------------------------------------
-- Registration (+ EllesmereUI Unlock Mode)
---------------------------------------------------------------------------

local function RegisterWithEUI(mover)
    if not (EllesmereUI and EllesmereUI.RegisterUnlockElements) then return end
    local euiKey = "OrionUI_" .. mover.key
    EllesmereUI:RegisterUnlockElements({ {
        key = euiKey,
        label = mover.label,
        group = ns.NAME,
        getFrame = function() return mover.getFrame() end,
        getSize = function()
            local f = mover.getFrame()
            if f then return f:GetWidth(), f:GetHeight() end
            return 100, 30
        end,
        -- EUI passes (key, point, relPoint, x, y, ...); we always store CENTER offsets.
        savePosition = function()
            local f = mover.getFrame()
            if f and f:GetCenter() then Movers:Save(mover.key, CenterOffset(f)) end
        end,
        loadPosition = function()
            local x, y = Position(mover)
            return { point = "CENTER", relPoint = "CENTER", x = x, y = y }
        end,
        clearPosition = function() Movers:Reset(mover.key) end,
        applyPosition = function() Movers:Apply(mover) end,
    } }, ns.ADDON_NAME)
end

function Movers:Register(key, spec)
    assert(not self.byKey[key], "mover already registered: " .. key)
    local mover = {
        key = key,
        label = spec.label or key,
        getFrame = spec.getFrame or function() return spec.frame end,
        default = spec.default or { x = 0, y = 0 },
    }
    self.list[#self.list + 1] = mover
    self.byKey[key] = mover
    if M.db then self:Apply(mover) end
    RegisterWithEUI(mover)
    return mover
end

function M:OnProfileChanged() Movers:ApplyAll() end
function M:OnInitialize() Movers:ApplyAll() end
