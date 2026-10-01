-- PixelGlow: thin lines with gaps that travel around a frame's edge, the look EllesmereUI's
-- Cooldown Manager uses for its glows (Stig, 2026-10-01). Our own implementation.
--
--   local g = ns.PixelGlow:New(frame, { lines = 8, thickness = 1, period = 4, pad = 2 })
--   g:Start(r, g, b)   g:Stop()
--
-- Each line is two textures so it can bend around a corner. The OnUpdate runs only while
-- the glow is shown.
local _, ns = ...

local PixelGlow = {}
ns.PixelGlow = PixelGlow

local Glow = {}
Glow.__index = Glow

-- Places texture `tex` on the edge segment [a, b] of the perimeter (0 = top-left, clockwise).
local function PlaceSpan(tex, host, w, h, th, a, b)
    tex:ClearAllPoints()
    if a < w then -- top edge, left -> right
        tex:SetPoint("TOPLEFT", host, "TOPLEFT", a, 0)
        tex:SetSize(b - a, th)
    elseif a < w + h then -- right edge, top -> bottom
        tex:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -(a - w))
        tex:SetSize(th, b - a)
    elseif a < 2 * w + h then -- bottom edge, right -> left
        tex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(a - w - h), 0)
        tex:SetSize(b - a, th)
    else -- left edge, bottom -> top
        tex:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, a - 2 * w - h)
        tex:SetSize(th, b - a)
    end
    tex:Show()
end

-- Splits [s, s + len) at corners and the wrap point; uses at most two textures.
local function PlaceLine(line, host, w, h, th, s, len)
    local p = 2 * (w + h)
    local corners = { w, w + h, 2 * w + h, p }
    s = s % p
    local e = s + len
    local cut
    for _, c in ipairs(corners) do
        if s < c then cut = c break end
    end
    if e <= cut then
        PlaceSpan(line[1], host, w, h, th, s, e)
        line[2]:Hide()
    else
        PlaceSpan(line[1], host, w, h, th, s, cut)
        local rest = math.min(e - cut, len) -- a line is never longer than one edge's worth
        local s2 = cut % p
        local nextCut = s2 < w and w or s2 < w + h and w + h or s2 < 2 * w + h and 2 * w + h or p
        PlaceSpan(line[2], host, w, h, th, s2, math.min(s2 + rest, nextCut))
    end
end

function PixelGlow:New(target, opts)
    opts = opts or {}
    local pad = opts.pad or 2
    local host = CreateFrame("Frame", nil, target)
    host:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
    host:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
    host:SetFrameLevel(target:GetFrameLevel() + 5)
    host:Hide()
    local self = setmetatable({
        host = host, n = opts.lines or 8, th = opts.thickness or 1, period = opts.period or 4, lines = {},
    }, Glow)
    for i = 1, self.n do
        self.lines[i] = { host:CreateTexture(nil, "OVERLAY"), host:CreateTexture(nil, "OVERLAY") }
    end
    local elapsed = 0
    host:SetScript("OnUpdate", function(_, dt)
        elapsed = (elapsed + dt) % self.period
        self:Paint(elapsed / self.period)
    end)
    return self
end

function Glow:Paint(phase)
    local w, h = self.host:GetSize()
    if not w or w <= 0 or h <= 0 then return end
    local p = 2 * (w + h)
    local step = p / self.n
    local len = math.min(step * 0.5, w, h) -- half line, half gap
    for i, line in ipairs(self.lines) do
        PlaceLine(line, self.host, w, h, self.th, phase * p + (i - 1) * step, len)
    end
end

function Glow:Start(r, g, b, a)
    for _, line in ipairs(self.lines) do
        line[1]:SetColorTexture(r, g, b, a or 1)
        line[2]:SetColorTexture(r, g, b, a or 1)
    end
    if not self.host:IsShown() then
        self.host:Show()
        self:Paint(0)
    end
end

function Glow:Stop()
    self.host:Hide()
end
