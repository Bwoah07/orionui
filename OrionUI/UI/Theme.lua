-- Look & feel for our windows (CLAUDE.md §9.1, §13). Reads EllesmereUI's accent colour
-- and font live when EUI is loaded so our options look native next to it; falls back
-- to our own palette otherwise. Flat panels, 1px black borders, one accent colour.
local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- Fallback palette (used without EUI).
local ACCENT = { r = 0.62, g = 0.48, b = 1.0 }
Theme.colors = {
    bg      = { 0.05, 0.05, 0.07, 0.97 },
    panel   = { 0.09, 0.09, 0.11, 1 },
    control = { 0.13, 0.13, 0.16, 1 },
    hover   = { 1, 1, 1, 0.06 },
    border  = { 0, 0, 0, 1 },
    text    = { 0.92, 0.92, 0.94, 1 },
    muted   = { 0.58, 0.58, 0.64, 1 },
    danger  = { 0.9, 0.3, 0.3, 1 },
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
    fs:SetShadowColor(0, 0, 0, 0.8)
    local c = color or self.colors.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end

-- Flat background plus 1px border drawn with textures (no templates needed).
function Theme:Skin(frame, bg, border)
    bg = bg or self.colors.panel
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
    frame._ouiBg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
    for i = 1, 4 do frame._ouiBorder[i]:SetColorTexture(border[1], border[2], border[3], border[4] or 1) end
end

function Theme:SetBorderColor(frame, r, g, b, a)
    if not frame._ouiBorder then return end
    for i = 1, 4 do frame._ouiBorder[i]:SetColorTexture(r, g, b, a or 1) end
end

-- Flat button with hover highlight and accent border on hover.
function Theme:Button(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height or 22)
    self:Skin(b, self.colors.control)
    b.label = self:Text(b, 12)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetText(text or "")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b:SetScript("OnEnter", function(self) Theme:SetBorderColor(self, Theme:Accent()) end)
    b:SetScript("OnLeave", function(self) Theme:SetBorderColor(self, 0, 0, 0, 1) end)
    function b:SetText(t) self.label:SetText(t) end
    return b
end
