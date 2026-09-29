-- Look & feel for our windows (CLAUDE.md §9.1, §13). Reads EllesmereUI's accent colour
-- and font live when EUI is loaded so our options look native next to it; falls back
-- to our own palette otherwise. Flat opaque panels, 1px borders, one accent colour,
-- soft drop shadow, generous spacing.
local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- Fallback accent (used without EUI).
local ACCENT = { r = 0.62, g = 0.48, b = 1.0 }
Theme.colors = {
    bg       = { 0.067, 0.067, 0.082, 1 },
    sidebar  = { 0.047, 0.047, 0.058, 1 },
    card     = { 0.094, 0.094, 0.114, 1 },
    control  = { 0.145, 0.145, 0.176, 1 },
    controlHi = { 0.19, 0.19, 0.23, 1 },
    border   = { 0, 0, 0, 1 },
    line     = { 1, 1, 1, 0.06 },
    text     = { 0.93, 0.93, 0.95, 1 },
    muted    = { 0.60, 0.60, 0.66, 1 },
    faint    = { 0.40, 0.40, 0.45, 1 },
}

-- EllesmereUI.ELLESMERE_GREEN is updated in place when the EUI theme changes
-- (EllesmereUI_UICore.lua), so reading it each time is always current.
function Theme:Accent()
    local eg = EllesmereUI and EllesmereUI.ELLESMERE_GREEN
    if type(eg) == "table" and type(eg.r) == "number" then return eg.r, eg.g, eg.b end
    return ACCENT.r, ACCENT.g, ACCENT.b
end

function Theme:Font()
    if EllesmereUI and EllesmereUI.GetFontPath then
        local ok, path = ns.SafeCall("Theme", EllesmereUI.GetFontPath)
        if ok and type(path) == "string" then return path end
    end
    return STANDARD_TEXT_FONT
end

-- Styled FontString. size defaults to 12.
function Theme:Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(self:Font(), size or 12, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.6)
    local c = color or self.colors.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end

local function Solid(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end

-- Flat background plus 1px border drawn with textures (no templates needed).
function Theme:Skin(frame, bg, border)
    bg = bg or self.colors.card
    border = border or self.colors.border
    if not frame._ouiBg then
        frame._ouiBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._ouiBg:SetAllPoints()
        frame._ouiBorder = {}
        for i = 1, 4 do frame._ouiBorder[i] = frame:CreateTexture(nil, "BORDER", nil, 7) end
        local b = frame._ouiBorder
        b[1]:SetPoint("TOPLEFT"); b[1]:SetPoint("TOPRIGHT"); b[1]:SetHeight(1)
        b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); b[2]:SetHeight(1)
        b[3]:SetPoint("TOPLEFT"); b[3]:SetPoint("BOTTOMLEFT"); b[3]:SetWidth(1)
        b[4]:SetPoint("TOPRIGHT"); b[4]:SetPoint("BOTTOMRIGHT"); b[4]:SetWidth(1)
    end
    Solid(frame._ouiBg, bg)
    for i = 1, 4 do Solid(frame._ouiBorder[i], border) end
end

function Theme:SetBorderColor(frame, r, g, b, a)
    if not frame._ouiBorder then return end
    for i = 1, 4 do frame._ouiBorder[i]:SetColorTexture(r, g, b, a or 1) end
end

-- Soft shadow around a window: four gradient strips outside its edges.
function Theme:Shadow(frame, size)
    size = size or 14
    local dark, clear = CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0)
    local function Strip(p1, r1, x1, y1, p2, r2, x2, y2, orient, from, to)
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetPoint(p1, frame, r1, x1, y1)
        t:SetPoint(p2, frame, r2, x2, y2)
        t:SetGradient(orient, from, to)
    end
    Strip("TOPLEFT", "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, -size, "VERTICAL", clear, dark)
    Strip("BOTTOMLEFT", "TOPLEFT", 0, 0, "TOPRIGHT", "TOPRIGHT", 0, size, "VERTICAL", dark, clear)
    Strip("TOPLEFT", "TOPRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", size, 0, "HORIZONTAL", dark, clear)
    Strip("TOPRIGHT", "TOPLEFT", 0, 0, "BOTTOMLEFT", "BOTTOMLEFT", -size, 0, "HORIZONTAL", clear, dark)
end

-- Rectangle made of textures on `parent` (for cards behind rows). Returns a handle with
-- :Place(x, y, w, h) and :SetShown(bool).
function Theme:Box(parent, bg, border)
    local box = { bg = parent:CreateTexture(nil, "BACKGROUND", nil, -6), edges = {} }
    Solid(box.bg, bg or self.colors.card)
    for i = 1, 4 do
        box.edges[i] = parent:CreateTexture(nil, "BACKGROUND", nil, -5)
        Solid(box.edges[i], border or self.colors.border)
    end
    function box:Place(x, y, w, h)
        self.bg:ClearAllPoints()
        self.bg:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
        self.bg:SetSize(w, h)
        local e = self.edges
        for i = 1, 4 do e[i]:ClearAllPoints() end
        e[1]:SetPoint("TOPLEFT", self.bg); e[1]:SetPoint("TOPRIGHT", self.bg); e[1]:SetHeight(1)
        e[2]:SetPoint("BOTTOMLEFT", self.bg); e[2]:SetPoint("BOTTOMRIGHT", self.bg); e[2]:SetHeight(1)
        e[3]:SetPoint("TOPLEFT", self.bg); e[3]:SetPoint("BOTTOMLEFT", self.bg); e[3]:SetWidth(1)
        e[4]:SetPoint("TOPRIGHT", self.bg); e[4]:SetPoint("BOTTOMRIGHT", self.bg); e[4]:SetWidth(1)
    end
    function box:SetShown(on)
        self.bg:SetShown(on)
        for i = 1, 4 do self.edges[i]:SetShown(on) end
    end
    return box
end

-- Flat button. style "accent" draws an accent outline and label (primary action).
function Theme:Button(parent, text, width, height, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height or 24)
    self:Skin(b, self.colors.control)
    b.label = self:Text(b, 12)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetText(text or "")
    b.style = style
    function b:ApplyState(hover)
        local r, g, bb = Theme:Accent()
        Solid(self._ouiBg, hover and Theme.colors.controlHi or Theme.colors.control)
        if self.style == "accent" or hover then
            Theme:SetBorderColor(self, r, g, bb, self.style == "accent" and 1 or 0.7)
        else
            Theme:SetBorderColor(self, 0, 0, 0, 1)
        end
        if self.style == "accent" then self.label:SetTextColor(r, g, bb) end
    end
    b:SetScript("OnEnter", function(self) self:ApplyState(true) end)
    b:SetScript("OnLeave", function(self) self:ApplyState(false) end)
    b:ApplyState(false)
    function b:SetText(t) self.label:SetText(t) end
    return b
end

-- Borderless text button (close "x", links).
function Theme:TextButton(parent, text, size)
    local b = CreateFrame("Button", nil, parent)
    b.label = self:Text(b, size or 14, self.colors.muted)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetSize(b.label:GetStringWidth() + 12, (size or 14) + 10)
    b:SetScript("OnEnter", function(self) self.label:SetTextColor(unpack(Theme.colors.text)) end)
    b:SetScript("OnLeave", function(self) self.label:SetTextColor(unpack(Theme.colors.muted)) end)
    return b
end

-- Thin custom scrollbar for a plain ScrollFrame whose child is set later.
-- Mouse wheel scrolls 48px; the thumb can be dragged.
function Theme:Scroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)
    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(4)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 0)
    local trackTex = track:CreateTexture(nil, "BACKGROUND")
    trackTex:SetAllPoints()
    Solid(trackTex, self.colors.line)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(4)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()
    Solid(thumb.tex, self.colors.faint)
    scroll.track, scroll.thumb = track, thumb

    local function Max()
        local child = scroll:GetScrollChild()
        if not child then return 0 end
        return math.max(0, child:GetHeight() - scroll:GetHeight())
    end
    function scroll:UpdateThumb()
        local max, view = Max(), self:GetHeight()
        track:SetShown(max > 0)
        if max <= 0 then return end
        local trackH = track:GetHeight()
        local h = math.max(24, trackH * view / (view + max))
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(trackH - h) * (self:GetVerticalScroll() / max))
    end
    function scroll:ScrollTo(y)
        self:SetVerticalScroll(math.min(math.max(0, y), Max()))
        self:UpdateThumb()
    end
    scroll:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self:GetVerticalScroll() - delta * 48) end)
    scroll:SetScript("OnSizeChanged", function(self) self:UpdateThumb() end)
    thumb:SetScript("OnEnter", function() Solid(thumb.tex, Theme.colors.muted) end)
    thumb:SetScript("OnLeave", function() Solid(thumb.tex, Theme.colors.faint) end)
    -- Dragging uses OnUpdate only while the button is held.
    thumb:SetScript("OnMouseDown", function()
        local _, startY = GetCursorPosition()
        local startScroll = scroll:GetVerticalScroll()
        local scale = track:GetEffectiveScale()
        thumb:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local range = track:GetHeight() - thumb:GetHeight()
            if range <= 0 then return end
            scroll:ScrollTo(startScroll + (startY - y) / scale * Max() / range)
        end)
    end)
    thumb:SetScript("OnMouseUp", function() thumb:SetScript("OnUpdate", nil) end)
    return scroll
end
