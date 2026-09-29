-- Widget factory for the options window (CLAUDE.md §9.1). Every widget is a row frame
-- with a fixed height, created from a spec:
--   { label, desc, get = fn() -> value, set = fn(value), disabled = fn() -> bool, ... }
-- and exposes :Refresh() to re-read get(). Rows are "label left, control right";
-- the window groups them into cards. Styling comes from ns.Theme.
local _, ns = ...

local Widgets = { ROW = 36, CONTROL_W = 220 }
ns.Widgets = Widgets

local function T() return ns.Theme end

local function Row(parent, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height or Widgets.ROW)
    return row
end

-- Label on the left, vertically centred; desc (if any) shows as a tooltip on the row.
local function Label(row, spec)
    local label = T():Text(row, 13)
    label:SetPoint("LEFT", 0, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -(Widgets.CONTROL_W + 16), 0)
    label:SetWordWrap(false)
    label:SetText(spec.label or "")
    return label
end

local function Tooltip(owner, spec)
    if not spec.desc then return end
    owner:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(spec.label or "", 1, 1, 1)
        GameTooltip:AddLine(spec.desc, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function IsDisabled(spec) return spec.disabled and spec.disabled() or false end
local function SetDim(row, dim) row:SetAlpha(dim and 0.4 or 1) end

---------------------------------------------------------------------------

-- Section title (the window turns these into card headings; this is the fallback).
function Widgets.Header(parent, spec)
    local row = Row(parent, 28)
    local text = T():Text(row, 11, T().colors.muted)
    text:SetPoint("BOTTOMLEFT", 0, 6)
    text:SetText((spec.label or ""):upper())
    function row:Refresh() end
    return row
end

function Widgets.Description(parent, spec)
    local row = Row(parent, 20)
    local text = T():Text(row, 12, T().colors.muted)
    text:SetPoint("TOPLEFT", 0, -4)
    text:SetPoint("RIGHT")
    text:SetText(spec.label)
    function row:Refresh()
        self:SetHeight(math.max(20, text:GetStringHeight() + 10))
    end
    return row
end

-- On/off switch: pill track, sliding knob, accent when on. Whole row is clickable.
function Widgets.Toggle(parent, spec)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(Widgets.ROW)
    Label(row, spec)
    local track = CreateFrame("Frame", nil, row)
    track:SetSize(34, 18)
    track:SetPoint("RIGHT", 0, 0)
    T():Skin(track, T().colors.control)
    local knob = track:CreateTexture(nil, "ARTWORK")
    knob:SetSize(12, 12)
    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetPoint("TOPLEFT", -8, 0)
    hl:SetPoint("BOTTOMRIGHT", 8, 0)
    hl:SetColorTexture(1, 1, 1, 0.025)
    hl:Hide()
    row:SetScript("OnEnter", function() hl:Show() end)
    row:SetScript("OnLeave", function() hl:Hide() end)
    row:SetScript("OnClick", function()
        if IsDisabled(spec) then return end
        spec.set(not spec.get())
        row:Refresh()
    end)
    Tooltip(row, spec)
    function row:Refresh()
        local on = spec.get() == true
        local r, g, b = T():Accent()
        knob:ClearAllPoints()
        if on then
            T():Skin(track, { r, g, b, 1 }, { r * 0.6, g * 0.6, b * 0.6, 1 })
            knob:SetPoint("RIGHT", -3, 0)
            knob:SetColorTexture(T():OnAccent())
        else
            T():Skin(track, T().colors.control)
            knob:SetPoint("LEFT", 3, 0)
            knob:SetColorTexture(0.55, 0.55, 0.6, 1)
        end
        SetDim(row, IsDisabled(spec))
    end
    return row
end

-- spec: min, max, step, fmt (e.g. "%.1f"). Accent fill up to the value.
function Widgets.Slider(parent, spec)
    local row = Row(parent)
    Label(row, spec)
    local valueText = T():Text(row, 12, T().colors.muted)
    valueText:SetPoint("RIGHT", 0, 0)
    valueText:SetWidth(40)
    valueText:SetJustifyH("RIGHT")

    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(Widgets.CONTROL_W - 48, 16)
    slider:SetPoint("RIGHT", valueText, "LEFT", -8, 0)
    local bar = slider:CreateTexture(nil, "BACKGROUND")
    bar:SetHeight(4)
    bar:SetPoint("LEFT")
    bar:SetPoint("RIGHT")
    bar:SetColorTexture(unpack(T().colors.control))
    local fill = slider:CreateTexture(nil, "BORDER")
    fill:SetHeight(4)
    fill:SetPoint("LEFT", bar, "LEFT")
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    thumb:SetColorTexture(1, 1, 1, 1)
    slider:SetThumbTexture(thumb)
    -- Dark outline so the thumb stays visible on a light accent fill.
    local outline = slider:CreateTexture(nil, "ARTWORK")
    outline:SetColorTexture(0, 0, 0, 1)
    outline:SetPoint("TOPLEFT", thumb, "TOPLEFT", -1, 1)
    outline:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 1, -1)
    local lo, hi = spec.min or 0, spec.max or 100
    slider:SetMinMaxValues(lo, hi)
    slider:SetValueStep(spec.step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)

    local fmt = spec.fmt or ((spec.step or 1) < 1 and "%.1f" or "%d")
    local updating = false
    local function Show(value)
        valueText:SetText(fmt:format(value))
        local w = slider:GetWidth() * (hi > lo and (value - lo) / (hi - lo) or 0)
        fill:SetWidth(math.max(1, w))
    end
    slider:SetScript("OnValueChanged", function(_, value)
        Show(value)
        if updating or IsDisabled(spec) then return end
        spec.set(value)
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * (spec.step or 1))
    end)
    Tooltip(slider, spec)
    function row:Refresh()
        updating = true
        slider:SetValue(spec.get() or lo)
        updating = false
        Show(slider:GetValue())
        fill:SetColorTexture(T():Accent())
        slider:SetEnabled(not IsDisabled(spec))
        SetDim(row, IsDisabled(spec))
    end
    return row
end

-- One shared popup list for all dropdowns.
local popup
local function Popup()
    if popup then return popup end
    popup = CreateFrame("Frame", nil, UIParent)
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:EnableMouse(true)
    T():Skin(popup, T().colors.bg)
    popup.buttons = {}
    popup:Hide()
    popup:SetScript("OnHide", function(self) self.owner = nil end)
    return popup
end

local function DropButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.06)
    b.hl:Hide()
    b.label = T():Text(b, 12)
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetPoint("RIGHT", -10, 0)
    b.label:SetWordWrap(false)
    b:SetScript("OnEnter", function(self) self.hl:Show() end)
    b:SetScript("OnLeave", function(self) self.hl:Hide() end)
    return b
end

-- spec.values: array of values or of { value = , text = }; or a function returning that.
function Widgets.Dropdown(parent, spec)
    local row = Row(parent)
    Label(row, spec)
    local button = T():Button(row, "", Widgets.CONTROL_W, 24)
    button:SetPoint("RIGHT")
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 10, 0)
    button.label:SetPoint("RIGHT", -22, 0)
    button.label:SetJustifyH("LEFT")
    button.label:SetWordWrap(false)
    local arrow = T():Text(button, 10, T().colors.muted)
    arrow:SetPoint("RIGHT", -9, 0)
    arrow:SetText("v")
    Tooltip(button, spec)

    local function Choices()
        local vals = type(spec.values) == "function" and spec.values() or spec.values or {}
        local out = {}
        for i, v in ipairs(vals) do
            if type(v) == "table" then out[i] = v else out[i] = { value = v, text = tostring(v) } end
        end
        return out
    end

    button:SetScript("OnClick", function()
        if IsDisabled(spec) then return end
        local p = Popup()
        if p:IsShown() and p.owner == button then p:Hide() return end
        p.owner = button
        local choices, current = Choices(), spec.get()
        local r, g, b = T():Accent()
        for i, c in ipairs(choices) do
            local btn = p.buttons[i] or DropButton(p)
            p.buttons[i] = btn
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", 1, -4 - (i - 1) * 22)
            btn:SetPoint("RIGHT", -1, 0)
            btn.label:SetText(c.text)
            if c.value == current then btn.label:SetTextColor(r, g, b) else btn.label:SetTextColor(unpack(T().colors.text)) end
            btn:SetScript("OnClick", function()
                p:Hide()
                spec.set(c.value)
                row:Refresh()
            end)
            btn:Show()
        end
        for i = #choices + 1, #p.buttons do p.buttons[i]:Hide() end
        p:SetSize(button:GetWidth(), math.max(1, #choices) * 22 + 8)
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
        p:Show()
    end)

    function row:Refresh()
        local current = spec.get()
        local text = tostring(current)
        for _, c in ipairs(Choices()) do
            if c.value == current then text = c.text end
        end
        button:SetText(text)
        SetDim(row, IsDisabled(spec))
    end
    return row
end

-- Colour as { r, g, b, a }. spec.hasAlpha shows the opacity slider.
function Widgets.Color(parent, spec)
    local row = Row(parent)
    Label(row, spec)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(40, 20)
    swatch:SetPoint("RIGHT")
    T():Skin(swatch, { 1, 1, 1, 1 })
    swatch:SetScript("OnEnter", function(self) T():SetBorderColor(self, 1, 1, 1, 0.8) end)
    swatch:SetScript("OnLeave", function(self) T():SetBorderColor(self, 0, 0, 0, 1) end)
    Tooltip(swatch, spec)

    swatch:SetScript("OnClick", function()
        if IsDisabled(spec) then return end
        local c = spec.get()
        local function Apply()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = spec.hasAlpha and ColorPickerFrame:GetColorAlpha() or (c[4] or 1)
            spec.set({ r, g, b, a })
            row:Refresh()
        end
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3], opacity = c[4] or 1, hasOpacity = spec.hasAlpha,
            swatchFunc = Apply, opacityFunc = Apply,
            cancelFunc = function()
                local r, g, b, a = ColorPickerFrame:GetPreviousValues()
                spec.set({ r, g, b, a or c[4] or 1 })
                row:Refresh()
            end,
        })
    end)
    function row:Refresh()
        local c = spec.get()
        swatch._ouiBg:SetColorTexture(c[1], c[2], c[3], 1)
        SetDim(row, IsDisabled(spec))
    end
    return row
end

-- Single-line text; commits on Enter or focus loss.
function Widgets.Input(parent, spec)
    local row = Row(parent)
    Label(row, spec)
    local box = CreateFrame("EditBox", nil, row)
    box:SetSize(Widgets.CONTROL_W, 24)
    box:SetPoint("RIGHT")
    box:SetAutoFocus(false)
    box:SetFont(T():Font(), 12, "")
    box:SetTextInsets(8, 8, 0, 0)
    T():Skin(box, T().colors.control)
    local function Commit(self)
        if not IsDisabled(spec) then spec.set(self:GetText()) end
        self:ClearFocus()
        row:Refresh()
    end
    box:SetScript("OnEnterPressed", Commit)
    box:SetScript("OnEditFocusLost", Commit)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() row:Refresh() end)
    box:SetScript("OnEditFocusGained", function(self) T():SetBorderColor(self, T():Accent()) end)
    box:HookScript("OnEditFocusLost", function(self) T():SetBorderColor(self, 0, 0, 0, 1) end)
    Tooltip(box, spec)
    function row:Refresh()
        if not box:HasFocus() then box:SetText(spec.get() or "") end
        SetDim(row, IsDisabled(spec))
    end
    return row
end

-- A row of buttons. spec.buttons = { { label, func, disabled = fn, width, style } ... }
function Widgets.ButtonBar(parent, spec)
    local row = Row(parent)
    local x, buttons = 0, {}
    for i, b in ipairs(spec.buttons) do
        local btn = T():Button(row, b.label, b.width or 96, 24, b.style)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() if not (b.disabled and b.disabled()) then b.func() end end)
        x = x + (b.width or 96) + 6
        buttons[i] = btn
    end
    function row:Refresh()
        for i, b in ipairs(spec.buttons) do buttons[i]:SetAlpha(b.disabled and b.disabled() and 0.4 or 1) end
    end
    return row
end

-- Text plus one button; spec.text() returns the line or nil (row shows spec.empty).
function Widgets.ActionRow(parent, spec)
    local row = Row(parent, 32)
    local btn = T():Button(row, spec.buttonLabel, 84, 22)
    btn:SetPoint("RIGHT")
    local text = T():Text(row, 12)
    text:SetPoint("LEFT")
    text:SetPoint("RIGHT", btn, "LEFT", -10, 0)
    text:SetWordWrap(false)
    btn:SetScript("OnClick", function() if spec.text() then spec.func() end end)
    function row:Refresh()
        local t = spec.text()
        text:SetText(t or spec.empty or "")
        text:SetTextColor(unpack(t and T().colors.text or T().colors.faint))
        btn:SetShown(t ~= nil)
    end
    return row
end

-- spec: label, func, width, style ("accent" for the main action)
function Widgets.Button(parent, spec)
    local row = Row(parent)
    local b = T():Button(row, spec.label, spec.width or 160, 24, spec.style)
    b:SetPoint("LEFT")
    b:SetScript("OnClick", function() if not IsDisabled(spec) then spec.func() end end)
    Tooltip(b, spec)
    function row:Refresh() SetDim(row, IsDisabled(spec)) end
    return row
end
