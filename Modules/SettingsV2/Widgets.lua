local _, ns = ...
local RC = ns.RC
local AceGUI = LibStub("AceGUI-3.0")
local L = RC.L

RC.SettingsV2 = RC.SettingsV2 or {}
local V2 = RC.SettingsV2

V2.Widgets = V2.Widgets or {}

local function FullRowWidth()
    return (V2.Layout and V2.Layout:GetContentWidth()) or 640
end

local function GridRowWidth()
    return math.min(FullRowWidth(), RC:IsShadowsteelTheme() and 620 or 680)
end

local function GridControlX(rowWidth)
    rowWidth = rowWidth or GridRowWidth()
    local labelWidth = math.floor(rowWidth * RC:GetThemeLayout("labelColumnWidth", 0.46))
    return labelWidth + (RC:IsShadowsteelTheme() and 8 or 10)
end

local function GridControlWidth(rowWidth)
    rowWidth = rowWidth or GridRowWidth()
    return math.max(180, rowWidth - GridControlX(rowWidth) - 14)
end

local function UseSettingsGrid(widget)
    if widget then
        widget._rcSettingsGrid = true
    end
    return widget
end

-- Row options shared by every labelled setting: the label doubles as the
-- tooltip title, and the help text comes from the tooltip table.
local function LabelledRow(label, options)
    options = options or {}
    options.tooltipTitle = label
    options.tooltip = V2.Tooltips and V2.Tooltips:Get(label) or nil
    return options
end

local function ToggleRowHeight()
    local rowHeight = RC:GetThemeLayout("settingsRowHeight", RC:GetThemeLayout("rowHeight", 42))
    if RC:IsModernTheme() then
        return math.max(RC:GetThemeLayout("compactRowHeight", 34), rowHeight - (RC:IsShadowsteelTheme() and 0 or 4))
    end
    return rowHeight
end

local function ButtonRowHeight()
    local buttonHeight = RC:GetThemeLayout("buttonHeight", 30)
    return math.max(buttonHeight + (RC:IsShadowsteelTheme() and 4 or 6), RC:GetThemeLayout("compactRowHeight", 34))
end

local function SliderRowHeight()
    if RC:IsModernTheme() then
        return RC:GetThemeLayout("settingsRowHeight", 42)
    end
    return RC:GetThemeLayout("settingsRowHeight", RC:GetThemeLayout("rowHeight", 42))
end

-- Left edge shared by row labels and label-less controls such as buttons,
-- so everything in a column starts on the same line.
local ROW_INSET = 14

-- Wide enough for the label at the settings font size, never narrower than
-- the standard button.
local function ActionButtonWidth(text)
    local base = RC:IsShadowsteelTheme() and 126 or 142
    return math.max(base, #tostring(text or "") * 7 + 34)
end

local function CreateActionButton(action, fallbackText)
    if not action then
        return nil
    end

    local button = AceGUI:Create("RC_Button")
    local text = action.text or fallbackText or L["Action"]
    button:SetText(text)
    button:SetWidth(action.width or ActionButtonWidth(text))
    button:SetHeight(RC:GetThemeLayout("buttonHeight", 30))
    button._rcActionWidth = action.width or ActionButtonWidth(text)
    if button.SetDanger then
        button:SetDanger(action.isDanger and true or false)
    end
    button:SetCallback("OnClick", function()
        if action.onClick then
            action.onClick()
        end
    end)
    return button
end

local function SetComposedRowLayout(group, layoutFunc)
    local frame = group and group.frame
    if not frame or not layoutFunc then
        return nil
    end

    if V2.SetSimpleGroupLayout then
        return V2:SetSimpleGroupLayout(group, layoutFunc)
    end

    if not frame._rcV2HasBaseOnSizeChanged then
        frame._rcV2BaseOnSizeChanged = frame:GetScript("OnSizeChanged")
        frame._rcV2HasBaseOnSizeChanged = true
    end
    frame:SetScript("OnSizeChanged", function(self, ...)
        if self._rcV2BaseOnSizeChanged then
            self._rcV2BaseOnSizeChanged(self, ...)
        end
        layoutFunc()
    end)
    return layoutFunc
end

function V2.Widgets:AddToggleRow(container, label, getValue, setValue, onChanged)
    local checkbox = UseSettingsGrid(AceGUI:Create("RC_CheckBox"))
    local rowHeight = ToggleRowHeight()
    local rowWidth = GridRowWidth()
    checkbox:SetLabel(label)
    checkbox:SetFullWidth(false)
    checkbox:SetWidth(rowWidth)
    checkbox:SetHeight(rowHeight)
    checkbox:SetValue(getValue() and true or false)
    checkbox:SetCallback("OnValueChanged", function(_, _, value)
        local checked = value and true or false
        setValue(checked)
        if onChanged then
            onChanged(checked)
        end
    end)
    V2.Sections:AddWidget(container, checkbox, rowWidth, rowHeight, LabelledRow(label))
    V2.Sections:BindRowHover(checkbox)
    return checkbox
end

function V2.Widgets:AddCheckbox(container, label, getValue, setValue, onChanged)
    return self:AddToggleRow(container, label, getValue, setValue, onChanged)
end

function V2.Widgets:AddButtonRow(container, text, onClick, isDanger)
    local button = UseSettingsGrid(AceGUI:Create("RC_Button"))
    local buttonHeight = RC:GetThemeLayout("buttonHeight", 30)
    local rowHeight = ButtonRowHeight()
    local buttonWidth = ActionButtonWidth(text)
    button:SetText(text)
    button:SetFullWidth(false)
    button:SetWidth(buttonWidth)
    button:SetHeight(buttonHeight)
    if button.SetDanger then
        button:SetDanger(isDanger and true or false)
    end
    button:SetCallback("OnClick", function()
        onClick()
    end)
    return V2.Sections:AddWidget(container, button, buttonWidth, rowHeight, { offsetX = ROW_INSET, rowStyle = "action" })
end

function V2.Widgets:AddButton(container, text, onClick, isDanger)
    return self:AddButtonRow(container, text, onClick, isDanger)
end

function V2.Widgets:AddToggleActionRow(container, label, getValue, setValue, onChanged, actions)
    actions = actions or {}

    local row = AceGUI:Create("SimpleGroup")
    if V2.ResetSimpleGroupWidget then
        V2:ResetSimpleGroupWidget(row)
    end
    local rowHeight = ToggleRowHeight()
    local buttonHeight = RC:GetThemeLayout("buttonHeight", 30)
    local gap = RC:IsShadowsteelTheme() and 8 or 10
    local baseRowWidth = GridRowWidth()
    row:SetFullWidth(false)
    row:SetWidth(baseRowWidth)
    row:SetHeight(rowHeight)
    row:SetLayout("Manual")
    row.actionButtons = {}

    local checkbox = UseSettingsGrid(AceGUI:Create("RC_CheckBox"))
    checkbox:SetLabel(label)
    checkbox:SetFullWidth(false)
    checkbox:SetWidth(baseRowWidth)
    checkbox:SetHeight(rowHeight)
    checkbox:SetValue(getValue() and true or false)
    checkbox:SetCallback("OnValueChanged", function(_, _, value)
        local checked = value and true or false
        setValue(checked)
        if onChanged then
            onChanged(checked)
        end
    end)
    row:AddChild(checkbox)
    row.checkbox = checkbox

    for _, action in ipairs(actions) do
        if action and action.text and action.onClick then
            local button = CreateActionButton(action)
            if button then
                button:SetHeight(buttonHeight)
                row:AddChild(button)
                table.insert(row.actionButtons, button)
            end
        end
    end

    local function LayoutRow()
        local width = row.frame and row.frame:GetWidth() or baseRowWidth
        if not width or width < 100 then
            width = baseRowWidth
        end

        local actionWidth = 0
        for index, button in ipairs(row.actionButtons) do
            actionWidth = actionWidth + (button._rcActionWidth or ActionButtonWidth(button.text and button.text:GetText()))
            if index > 1 then
                actionWidth = actionWidth + gap
            end
        end

        local checkboxWidth = math.min(baseRowWidth, width)
        if actionWidth > 0 then
            checkboxWidth = math.max(260, math.min(baseRowWidth, width - actionWidth - gap))
        end

        checkbox:SetWidth(checkboxWidth)
        checkbox:SetHeight(rowHeight)
        if checkbox.frame then
            checkbox.frame:ClearAllPoints()
            checkbox.frame:SetPoint("LEFT", row.frame, "LEFT", 0, 0)
            checkbox.frame:SetSize(checkboxWidth, rowHeight)
        end
        if checkbox.RefreshTheme then
            checkbox:RefreshTheme()
        end

        local x = checkboxWidth + gap
        for _, button in ipairs(row.actionButtons) do
            local buttonWidth = button._rcActionWidth or ActionButtonWidth()
            button:SetWidth(buttonWidth)
            button:SetHeight(buttonHeight)
            if button.frame then
                button.frame:ClearAllPoints()
                button.frame:SetPoint("LEFT", row.frame, "LEFT", x, 0)
                button.frame:SetSize(buttonWidth, buttonHeight)
            end
            x = x + buttonWidth + gap
        end
    end

    local runLayout
    function row:RefreshTheme()
        if self.checkbox and self.checkbox.RefreshTheme then
            self.checkbox:RefreshTheme()
        end
        for _, button in ipairs(self.actionButtons or {}) do
            if button.RefreshTheme then
                button:RefreshTheme()
            end
        end
        (runLayout or LayoutRow)()
    end

    function row:OnRelease()
        if V2.ResetSimpleGroupWidget then
            V2:ResetSimpleGroupWidget(self)
        end
    end

    runLayout = SetComposedRowLayout(row, LayoutRow) or LayoutRow
    local actionWidth = 0
    for index, button in ipairs(row.actionButtons) do
        actionWidth = actionWidth + (button._rcActionWidth or ActionButtonWidth(button.text and button.text:GetText()))
        if index > 1 then
            actionWidth = actionWidth + gap
        end
    end
    local composedWidth = math.min(FullRowWidth(), baseRowWidth + (actionWidth > 0 and (gap + actionWidth) or 0))
    V2.Sections:AddWidget(container, row, composedWidth, rowHeight, LabelledRow(label, { rowStyle = "toggleAction", fullWidth = true }))
    V2.Sections:BindRowHover(checkbox, row)
    runLayout()
    C_Timer.After(0, runLayout)
    return row
end

function V2.Widgets:AddActionToolbar(container, actions, options)
    if type(actions) ~= "table" or #actions == 0 then
        return nil
    end

    options = options or {}
    local toolbar = AceGUI:Create("SimpleGroup")
    if V2.ResetSimpleGroupWidget then
        V2:ResetSimpleGroupWidget(toolbar)
    end
    local buttonHeight = RC:GetThemeLayout("buttonHeight", 30)
    local rowHeight = ButtonRowHeight()
    local gap = RC:IsShadowsteelTheme() and 6 or 8
    local rowWidth = GridRowWidth()
    toolbar:SetFullWidth(false)
    toolbar:SetWidth(rowWidth)
    toolbar:SetHeight(rowHeight)
    toolbar:SetLayout("Manual")
    toolbar.buttons = {}

    for _, action in ipairs(actions) do
        if action and action.text and action.onClick then
            local button = AceGUI:Create("RC_Button")
            local onClick = action.onClick
            local width = action.width or ActionButtonWidth(action.text)
            button:SetText(action.text)
            button:SetWidth(width)
            button:SetHeight(buttonHeight)
            button._rcToolbarWidth = width
            if button.SetDanger then
                button:SetDanger(action.isDanger and true or false)
            end
            button:SetCallback("OnClick", function()
                onClick()
            end)
            toolbar:AddChild(button)
            table.insert(toolbar.buttons, button)
        end
    end

    local toolbarWidth = rowWidth
    if options.compact then
        toolbarWidth = 0
        for index, button in ipairs(toolbar.buttons) do
            toolbarWidth = toolbarWidth + (button._rcToolbarWidth or 120)
            if index > 1 then
                toolbarWidth = toolbarWidth + gap
            end
        end
        toolbarWidth = math.min(rowWidth, math.max(toolbarWidth, 1))
        toolbar:SetWidth(toolbarWidth)
    end

    local function LayoutToolbar()
        local width = toolbar.frame and toolbar.frame:GetWidth() or rowWidth
        local total = 0
        for index, button in ipairs(toolbar.buttons) do
            total = total + (button._rcToolbarWidth or 120)
            if index > 1 then
                total = total + gap
            end
        end

        -- Toolbars start on the label line like every other row. A compact
        -- toolbar sized exactly to its buttons has no room for the inset, but
        -- one stretched to the full row (fullWidth) must line up with labels.
        local tight = options.compact and width <= total + ROW_INSET
        local x = tight and 0 or ROW_INSET
        if options.align == "center" then
            x = math.max(0, math.floor((width - total) / 2))
        elseif options.align == "right" then
            x = math.max(0, width - total - (tight and 0 or ROW_INSET))
        end
        for _, button in ipairs(toolbar.buttons) do
            local buttonWidth = button._rcToolbarWidth or 120
            button.frame:ClearAllPoints()
            button.frame:SetPoint("LEFT", toolbar.frame, "LEFT", x, 0)
            button.frame:SetSize(buttonWidth, buttonHeight)
            x = x + buttonWidth + gap
        end
    end

    local runLayout = SetComposedRowLayout(toolbar, LayoutToolbar) or LayoutToolbar
    function toolbar:OnRelease()
        if V2.ResetSimpleGroupWidget then
            V2:ResetSimpleGroupWidget(self)
        end
    end
    V2.Sections:AddWidget(container, toolbar, toolbarWidth, rowHeight, {
        rowStyle = "toolbar",
        compactRow = options.compact,
        fullWidth = true,
    })
    runLayout()
    C_Timer.After(0, runLayout)
    return toolbar
end

function V2.Widgets:AddSliderRow(container, label, minValue, maxValue, stepValue, getValue, setValue, onMouseUp, deferUntilMouseUp)
    local slider = UseSettingsGrid(AceGUI:Create("RC_Slider"))
    local rowHeight = SliderRowHeight()
    local rowWidth = GridRowWidth()
    slider:SetLabel(label)
    slider:SetFullWidth(false)
    slider:SetWidth(rowWidth)
    slider:SetHeight(rowHeight)
    slider:SetSliderValues(minValue, maxValue, stepValue)
    slider:SetValue(getValue() or minValue)
    local pendingValue = getValue() or minValue
    slider:SetCallback("OnValueChanged", function(_, _, value)
        pendingValue = value
        if not deferUntilMouseUp then
            setValue(value)
        end
    end)
    slider:SetCallback("OnMouseUp", function(_, _, value)
        value = value or pendingValue or getValue() or minValue
        if deferUntilMouseUp then
            setValue(value)
        end
        if onMouseUp then
            onMouseUp(value)
        end
    end)
    return V2.Sections:AddWidget(container, slider, rowWidth, rowHeight, LabelledRow(label, { rowStyle = "slider" }))
end

function V2.Widgets:AddSlider(container, label, minValue, maxValue, stepValue, getValue, setValue, onMouseUp, deferUntilMouseUp)
    return self:AddSliderRow(container, label, minValue, maxValue, stepValue, getValue, setValue, onMouseUp, deferUntilMouseUp)
end

function V2.Widgets:AddPercentSlider(container, label, minPercent, maxPercent, stepPercent, getPercent, setPercent, onApplied)
    return self:AddSlider(
        container,
        label,
        minPercent,
        maxPercent,
        stepPercent,
        function()
            return math.floor(((getPercent and getPercent()) or minPercent) + 0.5)
        end,
        function(value)
            if setPercent then
                setPercent(value)
            end
        end,
        function(value)
            if onApplied then
                onApplied(value)
            end
        end,
        true
    )
end

function V2.Widgets:AddScaleControl(container, label, minValue, maxValue, stepValue, defaultValue, getValue, setValue, onChanged)
    return self:AddSlider(
        container,
        label,
        minValue,
        maxValue,
        stepValue,
        function()
            return (getValue and getValue()) or defaultValue or minValue
        end,
        function(value)
            if setValue then
                local applied = setValue(value)
                if type(applied) == "number" then
                    value = applied
                end
            end
            if onChanged then
                onChanged(value)
            end
        end,
        nil,
        false
    )
end

function V2.Widgets:AddDropdownRow(container, label, list, getValue, setValue, onChanged, order)
    local dropdown = UseSettingsGrid(AceGUI:Create("RC_Dropdown"))
    local rowHeight = RC:GetThemeLayout("settingsRowHeight", RC:GetThemeLayout("rowHeight", 42))
    local rowWidth = GridRowWidth()
    dropdown:SetLabel(label)
    dropdown:SetFullWidth(false)
    dropdown:SetWidth(rowWidth)
    dropdown:SetList(list, order)
    dropdown:SetValue(getValue())
    dropdown:SetCallback("OnValueChanged", function(_, _, key)
        setValue(key)
        if onChanged then
            onChanged(key)
        end
    end)
    return V2.Sections:AddWidget(container, dropdown, rowWidth, rowHeight, LabelledRow(label))
end

function V2.Widgets:AddDropdown(container, label, list, getValue, setValue, onChanged, order)
    return self:AddDropdownRow(container, label, list, getValue, setValue, onChanged, order)
end

function V2.Widgets:AddSearchableDropdown(container, labelText, list, getValue, setValue, onChanged, order, placeholderText)
    local row = AceGUI:Create("SimpleGroup")
    if V2.ResetSimpleGroupWidget then
        V2:ResetSimpleGroupWidget(row)
    end
    local rowWidth = GridRowWidth()
    local rowHeight = 72
    local controlX = GridControlX(rowWidth)
    local controlWidth = GridControlWidth(rowWidth)
    row:SetFullWidth(false)
    row:SetWidth(rowWidth)
    row:SetHeight(rowHeight)
    row:SetLayout("Manual")

    local frame = row.frame
    local label = frame._rcSoundSearchLabel or frame:CreateFontString(nil, "OVERLAY")
    frame._rcSoundSearchLabel = label
    RC:SetFont(label, 12, "OUTLINE")
    label:ClearAllPoints()
    label:SetPoint("LEFT", frame, "LEFT", 14, 0)
    label:SetPoint("RIGHT", frame, "LEFT", controlX - 8, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText or L["Sound"])
    label:Show()

    local searchBox = frame._rcSoundSearchBox
    if not searchBox then
        searchBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
        frame._rcSoundSearchBox = searchBox
        searchBox:SetAutoFocus(false)
        searchBox:SetMaxLetters(80)
        searchBox:SetFont(RC:GetFont(), 10, "")
        searchBox:SetTextInsets(8, 26, 0, 0)
        RC:SkinFrame(searchBox)
        RC:SetFrameThemeRole(searchBox, "InputBg")
        RC:RegisterFontString(searchBox, 10, "OUTLINE")

        local placeholder = searchBox:CreateFontString(nil, "OVERLAY")
        frame._rcSoundSearchPlaceholder = placeholder
        RC:SetFont(placeholder, 10, "")
        placeholder:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
        placeholder:SetPoint("RIGHT", searchBox, "RIGHT", -26, 0)
        placeholder:SetJustifyH("LEFT")

        local clearButton = RC:CreateCloseButton(searchBox, 14)
        frame._rcSoundSearchClearButton = clearButton

        function searchBox:RefreshTheme()
            RC:SetFrameThemeRole(self, "InputBg")
            self:SetBackdropBorderColor(
                RC.Config.InputBorder.r,
                RC.Config.InputBorder.g,
                RC.Config.InputBorder.b,
                math.max(0.20, RC.Config.InputBorder.a or 0)
            )
            local textR, textG, textB = RC:GetGeneralTextColor()
            self:SetTextColor(textR, textG, textB, 1)
            placeholder:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.72)
        end
        RC:RegisterThemeWidget(searchBox)
    end

    local placeholder = frame._rcSoundSearchPlaceholder
    local clearButton = frame._rcSoundSearchClearButton
    searchBox:SetScript("OnTextChanged", nil)
    searchBox:SetScript("OnEditFocusGained", nil)
    searchBox:SetScript("OnEditFocusLost", nil)
    searchBox:SetScript("OnEscapePressed", nil)
    searchBox:SetScript("OnEnterPressed", nil)
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", controlX, -4)
    searchBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -4)
    searchBox:SetHeight(26)
    searchBox:SetText("")
    searchBox:Show()
    placeholder:ClearAllPoints()
    placeholder:SetPoint("LEFT", searchBox, "LEFT", 8, 0)
    placeholder:SetPoint("RIGHT", searchBox, "RIGHT", -26, 0)
    placeholder:SetText(placeholderText or L["Search sounds..."])
    placeholder:Show()
    clearButton:ClearAllPoints()
    clearButton:SetPoint("RIGHT", searchBox, "RIGHT", -6, 0)
    clearButton:SetFrameLevel(searchBox:GetFrameLevel() + 2)
    clearButton:Hide()
    searchBox:RefreshTheme()

    local dropdown = UseSettingsGrid(AceGUI:Create("RC_Dropdown"))
    dropdown:SetLabel("")
    dropdown:SetCompactLayout(true)
    dropdown:SetFullWidth(false)
    dropdown:SetWidth(controlWidth)
    dropdown:SetHeight(30)
    dropdown:SetList(list, order)
    dropdown:SetValue(getValue())
    dropdown:SetCallback("OnValueChanged", function(_, _, key)
        setValue(key)
        if onChanged then
            onChanged(key)
        end
    end)
    row:AddChild(dropdown)

    local function RefreshSearchChrome()
        local hasText = searchBox:GetText() ~= ""
        placeholder:SetShown(not hasText and not searchBox:HasFocus())
        clearButton:SetShown(hasText)
    end

    local function ApplyFilter()
        local filteredList, filteredOrder = list, order
        if V2.Search and V2.Search.FilterOptions then
            filteredList, filteredOrder = V2.Search:FilterOptions(list, order, searchBox:GetText())
        end
        if dropdown.pullout and dropdown.pullout:IsShown() then
            dropdown.pullout:Hide()
        end
        dropdown:SetList(filteredList, filteredOrder)
        if next(filteredList) == nil then
            dropdown.text:SetText(L["No sounds found"])
        else
            local selected = getValue()
            dropdown.text:SetText(list[selected] or selected or L["Select..."])
        end
        RefreshSearchChrome()
    end

    searchBox:SetScript("OnTextChanged", ApplyFilter)
    searchBox:SetScript("OnEditFocusGained", RefreshSearchChrome)
    searchBox:SetScript("OnEditFocusLost", RefreshSearchChrome)
    searchBox:SetScript("OnEscapePressed", function(self)
        if self:GetText() ~= "" then
            self:SetText("")
        else
            self:ClearFocus()
        end
    end)
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if dropdown.button and dropdown.button.Click then
            dropdown.button:Click()
        end
    end)
    clearButton:SetScript("OnClick", function()
        searchBox:SetText("")
        searchBox:SetFocus()
    end)

    local function LayoutRow()
        local width = frame:GetWidth()
        if not width or width < 100 then
            width = rowWidth
        end
        -- This row spans both columns, but its controls should start where
        -- the left column's dropdowns and sliders do, not at a split of the
        -- full width (which pushed them ~130px right of their neighbours).
        local columnGap = RC:GetThemeLayout("settingsColumnGap", 14)
        local cellWidth = math.floor((width - columnGap) / 2)
        local labelWidth = math.floor(cellWidth * RC:GetThemeLayout("labelColumnWidth", 0.46))
        labelWidth = math.max(92, math.min(labelWidth, cellWidth - 180))
        controlX = labelWidth + (RC:IsShadowsteelTheme() and 8 or 10)
        label:ClearAllPoints()
        label:SetPoint("LEFT", frame, "LEFT", 14, 0)
        label:SetPoint("RIGHT", frame, "LEFT", labelWidth - 8, 0)
        searchBox:ClearAllPoints()
        searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", controlX, -4)
        searchBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -4)
        local dynamicControlWidth = math.max(180, width - controlX - 14)
        dropdown:SetWidth(dynamicControlWidth)
        dropdown:SetHeight(30)
        dropdown.frame:ClearAllPoints()
        dropdown.frame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", controlX, 4)
        dropdown.frame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 4)
        dropdown.frame:SetHeight(30)
    end

    local runLayout = SetComposedRowLayout(row, LayoutRow) or LayoutRow
    frame._rcManualArtifacts = { label, searchBox, placeholder, clearButton }
    function row:RefreshTheme()
        RC:SetFont(label, 12, "OUTLINE")
        label:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, 1)
        searchBox:RefreshTheme()
        if dropdown.RefreshTheme then
            dropdown:RefreshTheme()
        end
        runLayout()
    end
    function row:OnRelease()
        searchBox:ClearFocus()
        if V2.ResetSimpleGroupWidget then
            V2:ResetSimpleGroupWidget(self)
        end
    end

    row:RefreshTheme()
    V2.Sections:AddWidget(container, row, rowWidth, rowHeight, LabelledRow(labelText, { rowStyle = "searchableDropdown", fullWidth = true }))
    runLayout()
    C_Timer.After(0, runLayout)
    return row
end

function V2.Widgets:AddEditBox(container, label, getValue, setValue, onEnterPressed)
    local editbox = UseSettingsGrid(AceGUI:Create("RC_EditBox"))
    local rowHeight = RC:GetThemeLayout("settingsRowHeight", RC:GetThemeLayout("rowHeight", 42))
    local rowWidth = GridRowWidth()
    editbox:SetLabel(label)
    editbox:SetFullWidth(false)
    editbox:SetWidth(rowWidth)
    editbox:SetText(getValue() or "")
    editbox:SetCallback("OnEnterPressed", function(_, _, text)
        local value = text or ""
        setValue(value)
        if onEnterPressed then
            onEnterPressed(value)
        end
    end)
    return V2.Sections:AddWidget(container, editbox, rowWidth, rowHeight, LabelledRow(label))
end

-- A full-width text row with the label above the box, for long values such
-- as profile strings. The value is stored as it is typed, so a paste is
-- never lost when the next click lands on a button.
function V2.Widgets:AddTextField(container, label, getValue, setValue)
    local editbox = AceGUI:Create("RC_EditBox")
    local rowHeight = 64
    local rowWidth = FullRowWidth()
    editbox:SetLabel(label)
    editbox:SetFullWidth(false)
    editbox:SetWidth(rowWidth)
    editbox:SetHeight(rowHeight)
    editbox:SetStackedLayout(true)
    editbox:SetSelectAllOnFocus(true)
    editbox:SetText(getValue() or "")
    editbox:SetCallback("OnTextChanged", function(_, _, text)
        setValue(text or "")
    end)
    editbox:SetCallback("OnEnterPressed", function(_, _, text)
        setValue(text or "")
    end)
    return V2.Sections:AddWidget(container, editbox, rowWidth, rowHeight, LabelledRow(label, { fullWidth = true }))
end

function V2.Widgets:AddColorSwatchRow(container, label, getRGB, setRGB)
    local swatch = UseSettingsGrid(AceGUI:Create("RC_ColorSwatch"))
    local rowHeight = RC:GetThemeLayout("settingsRowHeight", RC:GetThemeLayout("rowHeight", 42))
    local rowWidth = GridRowWidth()
    swatch:SetLabel(label)
    swatch:SetFullWidth(false)
    swatch:SetWidth(rowWidth)
    local r, g, b = getRGB()
    swatch:SetColor(r or 1, g or 1, b or 1)
    swatch:SetCallback("OnValueChanged", function(_, _, nr, ng, nb)
        setRGB(nr, ng, nb)
    end)
    V2.Sections:AddWidget(container, swatch, rowWidth, rowHeight, LabelledRow(label))
    V2.Sections:BindRowHover(swatch)
    return swatch
end

function V2.Widgets:AddColorSwatch(container, label, getRGB, setRGB)
    return self:AddColorSwatchRow(container, label, getRGB, setRGB)
end

function V2.Widgets:AddErrorLabel(container, text)
    local label = AceGUI:Create("Label")
    label:SetText(text or L["Unknown settings error"])
    label:SetFullWidth(true)
    label:SetHeight(60)
    if label.label then
        label.label:SetTextColor(RC.Config.ErrorColor.r, RC.Config.ErrorColor.g, RC.Config.ErrorColor.b, 1)
        label.label:SetJustifyH("LEFT")
    end
    return V2.Sections:AddWidget(container, label, FullRowWidth(), 60, { fullWidth = true })
end
