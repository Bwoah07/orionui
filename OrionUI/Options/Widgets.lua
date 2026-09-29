-- Widget factory for the options window (CLAUDE.md §9.1). Every widget is a row frame
-- with a fixed height, created from a spec:
--   { label, desc, get = fn() -> value, set = fn(value), disabled = fn() -> bool, ... }
-- and exposes :Refresh() to re-read get(). Styling comes from ns.Theme.
local _, ns = ...

local T -- ns.Theme, resolved on first use (Theme loads earlier in the TOC)
local Widgets = {}
ns.Widgets = Widgets

local function Theme() T = T or ns.Theme return T end

local function Row(parent, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height)
    return row
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

local function SetDim(row, dim)
    row:SetAlpha(dim and 0.45 or 1)
end

---------------------------------------------------------------------------

function Widgets.Header(parent, spec)
    local row = Row(parent, 30)
    local text = Theme():Text(row, 14)
    text:SetPoint("BOTTOMLEFT", 0, 6)
    text:SetText(spec.label)
    local line = row:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    function row:Refresh()
        local r, g, b = Theme():Accent()
        line:SetColorTexture(r, g, b, 0.6)
    end
    return row
end

function Widgets.Description(parent, spec)
    local text = Theme():Text(parent, 12, Theme().colors.muted)
    local row = Row(parent, 20)
    text:SetParent(row)
    text:SetPoint("TOPLEFT")
    text:SetPoint("RIGHT")
    text:SetText(spec.label)
    function row:Refresh()
        self:SetHeight(math.max(16, text:GetStringHeight() + 6))
    end
    return row
end

function Widgets.Toggle(parent, spec)
    local row = Row(parent, 26)
    local box = CreateFrame("Button", nil, row)
    box:SetSize(16, 16)
    box:SetPoint("LEFT", 0, 0)
    Theme():Skin(box, Theme().colors.control)
    local check = box:CreateTexture(nil, "ARTWORK")
    check:SetPoint("TOPLEFT", 3, -3)
    check:SetPoint("BOTTOMRIGHT", -3, 3)
    local label = Theme():Text(row, 12)
    label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    label:SetText(spec.label)
    -- The whole row is clickable, not only the box.
    local hit = CreateFrame("Button", nil, row)
    hit:SetPoint("TOPLEFT", box)
    hit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 4, -4)
    hit:SetScript("OnClick", function()
        if IsDisabled(spec) then return end
        spec.set(not spec.get())
        row:Refresh()
    end)
    Tooltip(hit, spec)
    function row:Refresh()
        check:SetColorTexture(Theme():Accent())
        check:SetShown(spec.get() == true)
        SetDim(row, IsDisabled(spec))
    end
    return row
end

-- spec: min, max, step, fmt (e.g. "%.1f")
function Widgets.Slider(parent, spec)
    local row = Row(parent, 42)
    local label = Theme():Text(row, 12)
    label:SetPoint("TOPLEFT")
    label:SetText(spec.label)
    local valueText = Theme():Text(row, 12, Theme().colors.muted)
    valueText:SetPoint("TOPRIGHT")
    valueText:SetJustifyH("RIGHT")

    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint("TOPLEFT", 0, -20)
    slider:SetPoint("TOPRIGHT", 0, -20)
    slider:SetHeight(14)
    Theme():Skin(slider, Theme().colors.control)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(8, 14)
    slider:SetThumbTexture(thumb)
    slider:SetMinMaxValues(spec.min or 0, spec.max or 100)
    slider:SetValueStep(spec.step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(true)

    local fmt = spec.fmt or ((spec.step or 1) < 1 and "%.1f" or "%d")
    local updating = false
    slider:SetScript("OnValueChanged", function(_, value)
        valueText:SetText(fmt:format(value))
        if updating or IsDisabled(spec) then return end
        spec.set(value)
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        self:SetValue(self:GetValue() + delta * (spec.step or 1))
    end)
    Tooltip(slider, spec)
    function row:Refresh()
        updating = true
        slider:SetValue(spec.get() or spec.min or 0)
        valueText:SetText(fmt:format(slider:GetValue()))
        updating = false
        thumb:SetColorTexture(Theme():Accent())
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
    Theme():Skin(popup, Theme().colors.bg)
    popup.buttons = {}
    popup:Hide()
    popup:SetScript("OnHide", function(self) self.owner = nil end)
    return popup
end

-- spec.values: array of values or of { value = , text = }; or a function returning that.
function Widgets.Dropdown(parent, spec)
    local row = Row(parent, 46)
    local label = Theme():Text(row, 12)
    label:SetPoint("TOPLEFT")
    label:SetText(spec.label)
    local button = Theme():Button(row, "", 200, 22)
    button:SetPoint("TOPLEFT", 0, -18)
    button:SetPoint("RIGHT")
    button.label:ClearAllPoints()
    button.label:SetPoint("LEFT", 8, 0)
    button.label:SetPoint("RIGHT", -20, 0)
    button.label:SetJustifyH("LEFT")
    local arrow = Theme():Text(button, 12, Theme().colors.muted)
    arrow:SetPoint("RIGHT", -8, 0)
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
        local choices = Choices()
        for i, c in ipairs(choices) do
            local b = p.buttons[i]
            if not b then
                b = Theme():Button(p, "", 100, 20)
                Theme():Skin(b, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
                b.label:ClearAllPoints()
                b.label:SetPoint("LEFT", 8, 0)
                p.buttons[i] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 20)
            b:SetPoint("RIGHT", -1, 0)
            b:SetText(c.text)
            b:SetScript("OnClick", function()
                spec.set(c.value)
                p:Hide()
                row:Refresh()
            end)
            b:Show()
        end
        for i = #choices + 1, #p.buttons do p.buttons[i]:Hide() end
        p:SetSize(button:GetWidth(), #choices * 20 + 2)
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
    local row = Row(parent, 26)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(28, 16)
    swatch:SetPoint("LEFT")
    Theme():Skin(swatch, { 1, 1, 1, 1 })
    local label = Theme():Text(row, 12)
    label:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    label:SetText(spec.label)
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
    local row = Row(parent, 46)
    local label = Theme():Text(row, 12)
    label:SetPoint("TOPLEFT")
    label:SetText(spec.label)
    local box = CreateFrame("EditBox", nil, row)
    box:SetPoint("TOPLEFT", 0, -18)
    box:SetPoint("RIGHT")
    box:SetHeight(22)
    box:SetAutoFocus(false)
    box:SetFont(Theme():Font(), 12, "")
    box:SetTextInsets(6, 6, 0, 0)
    Theme():Skin(box, Theme().colors.control)
    local function Commit(self)
        if not IsDisabled(spec) then spec.set(self:GetText()) end
        self:ClearFocus()
        row:Refresh()
    end
    box:SetScript("OnEnterPressed", Commit)
    box:SetScript("OnEditFocusLost", Commit)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() row:Refresh() end)
    Tooltip(box, spec)
    function row:Refresh()
        if not box:HasFocus() then box:SetText(spec.get() or "") end
        SetDim(row, IsDisabled(spec))
    end
    return row
end

-- A row of buttons. spec.buttons = { { label, func, disabled = fn } ... }
function Widgets.ButtonBar(parent, spec)
    local row = Row(parent, 28)
    local x, buttons = 0, {}
    for i, b in ipairs(spec.buttons) do
        local btn = Theme():Button(row, b.label, b.width or 110, 22)
        btn:SetPoint("LEFT", x, 0)
        btn:SetScript("OnClick", function() if not (b.disabled and b.disabled()) then b.func() end end)
        x = x + (b.width or 110) + 6
        buttons[i] = btn
    end
    function row:Refresh()
        for i, b in ipairs(spec.buttons) do buttons[i]:SetAlpha(b.disabled and b.disabled() and 0.45 or 1) end
    end
    return row
end

-- Text plus one button; spec.text() returns the line or nil (row shows spec.empty).
function Widgets.ActionRow(parent, spec)
    local row = Row(parent, 26)
    local btn = Theme():Button(row, spec.buttonLabel, 90, 20)
    btn:SetPoint("RIGHT")
    local text = Theme():Text(row, 12)
    text:SetPoint("LEFT")
    text:SetPoint("RIGHT", btn, "LEFT", -8, 0)
    text:SetWordWrap(false)
    btn:SetScript("OnClick", function() if spec.text() then spec.func() end end)
    function row:Refresh()
        local t = spec.text()
        text:SetText(t or spec.empty or "")
        text:SetTextColor(unpack(t and Theme().colors.text or Theme().colors.muted))
        btn:SetShown(t ~= nil)
    end
    return row
end

-- spec: label, func, width
function Widgets.Button(parent, spec)
    local row = Row(parent, 28)
    local b = Theme():Button(row, spec.label, spec.width or 160, 22)
    b:SetPoint("LEFT")
    b:SetScript("OnClick", function() if not IsDisabled(spec) then spec.func() end end)
    Tooltip(b, spec)
    function row:Refresh() SetDim(row, IsDisabled(spec)) end
    return row
end
