-- CDMAnchor: attach our frames to a Cooldown Manager row so the HUD lines up (CLAUDE.md §9.3,
-- §13: bars and icon rows share exact edges and width).
--
-- EllesmereUI draws each CDM row in a named frame, ECME_CDMBar_<key> (checked in
-- EllesmereUICooldownManager.lua, 2026-09-30); without EUI we fall back to Blizzard's viewer
-- frames. Anchoring plain frames to them is ordinary layout: nothing here is protected.
-- When a row is resized or moved, attached frames follow on their own (anchors), and width
-- matching is redone from the row's OnSizeChanged.
local _, ns = ...

local L = ns.L

local Anchor = { watched = {}, listeners = {} }
ns.CDMAnchor = Anchor

Anchor.ROWS = {
    cooldowns = { "ECME_CDMBar_cooldowns", "EssentialCooldownViewer" },
    utility   = { "ECME_CDMBar_utility", "UtilityCooldownViewer" },
    buffs     = { "ECME_CDMBar_buffs", "BuffIconCooldownViewer" },
    -- EllesmereUI resource bars (EllesmereUIResourceBars.lua, checked 2026-09-30).
    runes     = { "ERB_SecondaryFrame" },
    power     = { "ERB_PrimaryBar" },
}

-- For settings dropdowns.
Anchor.CHOICES = { "none", "cooldowns", "utility", "buffs", "runes", "power" }
Anchor.CHOICE_LABELS = { none = L["Free (move it yourself)"], cooldowns = L["Essential cooldowns row"],
    utility = L["Utility cooldowns row"], buffs = L["Buff icons row"],
    runes = L["Runes / combo points bar"], power = L["Power bar (runic power, rage...)"] }
Anchor.SIDES = { "ABOVE", "BELOW", "LEFT", "RIGHT" }
Anchor.SIDE_LABELS = { ABOVE = L["Above"], BELOW = L["Below"], LEFT = L["Left"], RIGHT = L["Right"] }

function Anchor:Row(key)
    for _, name in ipairs(self.ROWS[key] or {}) do
        local f = _G[name]
        if f and f.GetWidth then return f end
    end
end

-- Width of `row` in `frame`'s units (the two can have different scales).
local function WidthIn(row, frame)
    local w = row:GetWidth() or 0
    local rs, fs = row:GetEffectiveScale(), frame:GetEffectiveScale()
    if fs and fs > 0 then w = w * rs / fs end
    return w
end

local SIDE_POINTS = {
    ABOVE = { "BOTTOM", "TOP", 0, 1 },
    BELOW = { "TOP", "BOTTOM", 0, -1 },
    LEFT  = { "RIGHT", "LEFT", -1, 0 },
    RIGHT = { "LEFT", "RIGHT", 1, 0 },
}

-- Places `frame` against the row. cfg = { attach, attachSide, attachGap, matchWidth }.
-- -> true when attached (the caller then skips its own saved position).
function Anchor:Place(frame, cfg, onResize)
    if not (cfg and cfg.attach and cfg.attach ~= "none") then return false end
    local row = self:Row(cfg.attach)
    if not row then return false end
    local p = SIDE_POINTS[cfg.attachSide] or SIDE_POINTS.ABOVE
    local gap = cfg.attachGap or 1
    frame:ClearAllPoints()
    frame:SetPoint(p[1], row, p[2], p[3] * gap, p[4] * gap)
    if cfg.matchWidth and (cfg.attachSide == "ABOVE" or cfg.attachSide == "BELOW") then
        local w = WidthIn(row, frame)
        if w > 0 then frame:SetWidth(w) end
    end
    if onResize and not self.watched[row] then
        self.watched[row] = true
        row:HookScript("OnSizeChanged", function() Anchor:Changed() end)
    end
    if onResize then self.listeners[frame] = onResize end
    return true
end

function Anchor:Release(frame) self.listeners[frame] = nil end

-- A row changed size: let attached frames redo their width.
function Anchor:Changed()
    ns.Events:Coalesce("cdm-anchor", function()
        for _, fn in pairs(Anchor.listeners) do ns.SafeCall("CDMAnchor", fn) end
    end)
end

-- EllesmereUI builds its rows around login; attached frames retry until they exist.
-- One pending retry per `key`, however often the caller asks.
local pending = {}
function Anchor:WhenReady(key, cfg, fn)
    if pending[key] or not (cfg and cfg.attach and cfg.attach ~= "none") or self:Row(cfg.attach) then return end
    local tries = 0
    pending[key] = C_Timer.NewTicker(1, function()
        tries = tries + 1
        if Anchor:Row(cfg.attach) or tries >= 15 then
            pending[key]:Cancel()
            pending[key] = nil
            ns.SafeCall("CDMAnchor", fn)
        end
    end)
end
