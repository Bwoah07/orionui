local _, ns = ...
local RC = ns.RC
local AceGUI = LibStub("AceGUI-3.0")

RC.SettingsV2 = RC.SettingsV2 or {}
local V2 = RC.SettingsV2

V2.Sections = V2.Sections or {}
V2.Sections.Active = V2.Sections.Active or setmetatable({}, { __mode = "k" })

local function ContentWidth(sectionFrame)
    local width = sectionFrame and sectionFrame:GetWidth()
    if not width or width < 100 then
        width = (V2.Layout and V2.Layout:GetContentWidth()) or 640
    end
    return width
end

local function SectionHeaderMetrics(hasDescription)
    local titleSize = RC:GetThemeLayout("sectionHeaderFont", 11)
    local detailSize = RC:GetThemeLayout("sectionDescriptionFont", 9)
    local topPad = 6
    local titleHeight = math.max(14, titleSize + 3)
    local detailHeight = hasDescription and math.max(12, detailSize + 4) or 0
    local descriptionGap = hasDescription and (RC:IsShadowsteelTheme() and 2 or 3) or 0
    local rowGap = 10
    local headerHeight = topPad + titleHeight + descriptionGap + detailHeight + rowGap

    return {
        topPad = topPad,
        titleSize = titleSize,
        titleHeight = titleHeight,
        detailSize = detailSize,
        detailHeight = detailHeight,
        descriptionGap = descriptionGap,
        headerHeight = headerHeight,
    }
end

local function SectionBaseHeight(hasDescription)
    local token = hasDescription and RC:GetThemeLayout("sectionBaseWithDescription", 58) or RC:GetThemeLayout("sectionBase", 42)
    local metrics = SectionHeaderMetrics(hasDescription)
    return math.max(token, metrics.headerHeight)
end

local function SectionBottomPad()
    local token = RC:GetThemeLayout("sectionBottomPad", 8)
    return math.max(3, token - (RC:IsShadowsteelTheme() and 5 or 6))
end

local function HideArtifacts(artifacts)
    if not artifacts then
        return
    end
    for _, artifact in ipairs(artifacts) do
        if artifact and artifact.Hide then
            artifact:Hide()
        end
        if artifact and artifact.ClearAllPoints then
            artifact:ClearAllPoints()
        end
    end
end

local function HoverAlpha()
    return RC:IsShadowsteelTheme() and 0.05 or 0.065
end

local function ApplyRowHoverTheme(record)
    local accent = RC.Config.Accent or RC.Config.SectionAccent
    record.hover:SetColorTexture(accent.r, accent.g, accent.b, HoverAlpha())
    record.marker:SetColorTexture(accent.r, accent.g, accent.b, 0.85)
end

local function SetRowHighlight(record, shown)
    record.hover:SetShown(shown)
    record.marker:SetShown(shown)
end

local function PollRowHover(hotspot)
    if not hotspot:IsMouseOver() then
        hotspot:SetScript("OnUpdate", nil)
        SetRowHighlight(hotspot.record, false)
    end
end

local function EnterRow(record)
    ApplyRowHoverTheme(record)
    SetRowHighlight(record, true)
    record.hotspot:SetScript("OnUpdate", nil)
    if record.tooltip and V2.Tooltips then
        V2.Tooltips:Show(record.hotspot, record.title, record.tooltip)
    end
end

local function LeaveRow(record)
    if V2.Tooltips then
        V2.Tooltips:Hide(record.hotspot)
    end
    -- The pointer may have moved onto the row's own control (a slider or an
    -- input), which sits above the hotspot. Keep the highlight until it leaves
    -- the row entirely.
    if record.hotspot:IsMouseOver() then
        record.hotspot:SetScript("OnUpdate", PollRowHover)
    else
        SetRowHighlight(record, false)
    end
end

-- Row chrome (background, divider, hover highlight and the hover hotspot) is
-- pooled on the section frame and reused by index, so rebuilding a page does
-- not create new textures and frames every time.
local function AcquireRowRecord(frame, index)
    frame._rcV2RowPool = frame._rcV2RowPool or {}
    local record = frame._rcV2RowPool[index]
    if not record then
        record = {
            bg = frame:CreateTexture(nil, "BACKGROUND", nil, -2),
            divider = frame:CreateTexture(nil, "BACKGROUND", nil, -1),
            hover = frame:CreateTexture(nil, "BORDER", nil, 1),
            marker = frame:CreateTexture(nil, "BORDER", nil, 2),
            hotspot = CreateFrame("Frame", nil, frame),
            token = 0,
        }
        record.divider:SetHeight(1)
        record.marker:SetWidth(2)
        record.hotspot.record = record
        record.hotspot:EnableMouse(true)
        if record.hotspot.SetMouseClickEnabled then
            -- Hover only: clicks fall through to whatever sits underneath.
            record.hotspot:SetMouseClickEnabled(false)
        end
        record.hotspot:SetScript("OnEnter", function(self)
            EnterRow(self.record)
        end)
        record.hotspot:SetScript("OnLeave", function(self)
            LeaveRow(self.record)
        end)
        record.hotspot:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            if V2.Tooltips then
                V2.Tooltips:Hide(self)
            end
        end)
        frame._rcV2RowPool[index] = record
    end

    -- Section resets clear every artifact's anchors, so re-anchor on reuse.
    record.hover:ClearAllPoints()
    record.hover:SetAllPoints(record.bg)
    record.marker:ClearAllPoints()
    record.marker:SetPoint("TOPLEFT", record.bg, "TOPLEFT", 0, 0)
    record.marker:SetPoint("BOTTOMLEFT", record.bg, "BOTTOMLEFT", 0, 0)
    record.hotspot:ClearAllPoints()
    record.hotspot:SetAllPoints(record.bg)

    record.token = record.token + 1
    record.tooltip = nil
    record.title = nil
    record.hotspot:SetScript("OnUpdate", nil)
    record.hotspot:SetFrameLevel(frame:GetFrameLevel() + 2)
    SetRowHighlight(record, false)
    return record
end

local function ClearPooledSectionFrame(frame)
    if not frame then
        return
    end
    HideArtifacts(frame._rcV2Rows)
    HideArtifacts(frame._rcManualArtifacts)
    HideArtifacts({
        frame._rcSectionTopLine,
        frame._rcSectionTitle,
        frame._rcSectionDetail,
        frame._rcV2ColumnRule,
    })
    if frame._rcSectionTitle then
        frame._rcSectionTitle:SetText("")
    end
    if frame._rcSectionDetail then
        frame._rcSectionDetail:SetText("")
    end
    frame._rcV2Rows = {}
    frame._rcV2RowData = {}
    frame._rcManualArtifacts = nil
end

local function ApplySectionFrameTheme(frame, state)
    if not frame then
        return
    end

    RC:ApplyThemedSection(frame)
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)

    local padX = (state and state.padX) or RC:GetThemeLayout("sectionPadX", 16)
    local padRight = (state and state.padRight) or RC:GetThemeLayout("settingsContentRightInset", padX)
    if frame._rcV2Accent then
        frame._rcV2Accent:SetColorTexture(RC.Config.SectionAccent.r, RC.Config.SectionAccent.g, RC.Config.SectionAccent.b, 0)
        frame._rcV2Accent:Hide()
    end
    if frame._rcV2TopRule then
        frame._rcV2TopRule:Hide()
    end
    if frame._rcV2ColumnRule then
        frame._rcV2ColumnRule:ClearAllPoints()
        local centerOffset = math.floor((padX - padRight) / 2)
        frame._rcV2ColumnRule:SetPoint("TOP", frame, "TOP", centerOffset, -SectionBaseHeight(frame._rcV2HasDescription))
        frame._rcV2ColumnRule:SetPoint("BOTTOM", frame, "BOTTOM", centerOffset, SectionBottomPad())
        frame._rcV2ColumnRule:SetColorTexture(
            RC.Config.SeparatorColor.r,
            RC.Config.SeparatorColor.g,
            RC.Config.SeparatorColor.b,
            0.07
        )
        -- Only draw the column divider once a section actually has
        -- side-by-side rows; it must not cut through full-width rows.
        frame._rcV2ColumnRule:SetShown(state and state.columns == 2 and state.hasHalfRows == true)
    end
    local metrics = SectionHeaderMetrics(frame._rcV2HasDescription)
    if frame._rcV2Title then
        RC:SetFont(frame._rcV2Title, metrics.titleSize, "OUTLINE")
        frame._rcV2Title:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.68)
    end
    if frame._rcV2Detail then
        RC:SetFont(frame._rcV2Detail, metrics.detailSize, "OUTLINE")
        frame._rcV2Detail:SetTextColor(
            RC.Config.MutedText.r,
            RC.Config.MutedText.g,
            RC.Config.MutedText.b,
            0.62
        )
    end

    for _, row in ipairs(frame._rcV2RowData or {}) do
        if row.bg then
            if row.style == "toolbar" then
                row.bg:SetColorTexture(
                    RC.Config.SurfaceBg.r,
                    RC.Config.SurfaceBg.g,
                    RC.Config.SurfaceBg.b,
                    RC:IsShadowsteelTheme() and 0.34 or 0.42
                )
            else
                RC:ApplyThemedSettingsRow(row.bg, row.index or 1)
                row.bg:SetAlpha(1)
            end
            row.bg:Show()
        end
        if row.record then
            ApplyRowHoverTheme(row.record)
        end
        if row.divider then
            row.divider:SetColorTexture(
                RC.Config.SeparatorColor.r,
                RC.Config.SeparatorColor.g,
                RC.Config.SeparatorColor.b,
                math.min(RC:GetThemeLayout("rowSeparatorAlpha", 0.055), RC.Config.SeparatorColor.a or 0.055)
            )
            row.divider:Show()
        end
    end
end

function V2.Sections:CreateSection(container, title, description)
    local section = AceGUI:Create("SimpleGroup")
    if V2.ResetSimpleGroupWidget then
        V2:ResetSimpleGroupWidget(section)
        section._rcV2Released = false
    end
    ClearPooledSectionFrame(section.frame)
    section:SetFullWidth(true)
    section:SetLayout("Manual")
    local hasDescription = description and description ~= ""
    local metrics = SectionHeaderMetrics(hasDescription)
    section:SetHeight(SectionBaseHeight(hasDescription))
    container:AddChild(section)

    RC:SkinFrame(section.frame, nil, true)
    section.frame._rcV2HasDescription = hasDescription and true or false

    local accent = section.frame._rcV2Accent or section.frame:CreateTexture(nil, "ARTWORK")
    section.frame._rcV2Accent = accent
    accent:ClearAllPoints()
    accent:SetPoint("TOPLEFT", section.frame, "TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", section.frame, "BOTTOMLEFT", 0, 0)
    accent:SetWidth(1)
    accent:SetColorTexture(RC.Config.SectionAccent.r, RC.Config.SectionAccent.g, RC.Config.SectionAccent.b, 0)
    accent:Hide()

    local topRule = section.frame._rcV2TopRule or section.frame:CreateTexture(nil, "ARTWORK")
    section.frame._rcV2TopRule = topRule
    topRule:ClearAllPoints()
    topRule:SetPoint("TOPLEFT", section.frame, "TOPLEFT", RC:GetThemeLayout("sectionPadX", 16), -1)
    topRule:SetPoint("TOPRIGHT", section.frame, "TOPRIGHT", -RC:GetThemeLayout("sectionPadX", 16), -1)
    topRule:SetHeight(1)
    topRule:SetColorTexture(0, 0, 0, 0)
    topRule:Hide()

    local columnRule = section.frame._rcV2ColumnRule or section.frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    section.frame._rcV2ColumnRule = columnRule
    columnRule:ClearAllPoints()
    columnRule:SetPoint("TOP", section.frame, "TOP", 0, -SectionBaseHeight(hasDescription))
    columnRule:SetPoint("BOTTOM", section.frame, "BOTTOM", 0, SectionBottomPad())
    columnRule:SetWidth(1)

    local titleText = section.frame._rcV2Title or section.frame:CreateFontString(nil, "OVERLAY")
    section.frame._rcV2Title = titleText
    RC:SetFont(titleText, metrics.titleSize, "OUTLINE")
    titleText:ClearAllPoints()
    titleText:SetPoint("TOPLEFT", section.frame, "TOPLEFT", RC:GetThemeLayout("sectionPadX", 16), -metrics.topPad)
    titleText:SetPoint("TOPRIGHT", section.frame, "TOPRIGHT", -RC:GetThemeLayout("sectionPadX", 16), -metrics.topPad)
    titleText:SetHeight(metrics.titleHeight)
    titleText:SetJustifyH("LEFT")
    titleText:SetText(string.upper(title or ""))
    titleText:Show()
    titleText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.68)

    local detailText = section.frame._rcV2Detail or section.frame:CreateFontString(nil, "OVERLAY")
    section.frame._rcV2Detail = detailText
    if hasDescription then
        RC:SetFont(detailText, metrics.detailSize, "OUTLINE")
        detailText:ClearAllPoints()
        detailText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -metrics.descriptionGap)
        detailText:SetPoint("TOPRIGHT", titleText, "BOTTOMRIGHT", 0, -metrics.descriptionGap)
        detailText:SetHeight(metrics.detailHeight)
        detailText:SetJustifyH("LEFT")
        if detailText.SetWordWrap then
            detailText:SetWordWrap(false)
        end
        detailText:SetText(description)
        detailText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.62)
        detailText:Show()
    else
        detailText:SetText("")
        detailText:Hide()
    end

    local baseHeight = SectionBaseHeight(hasDescription)
    local sectionWidth = ContentWidth(section.frame)
    local requestedColumns = RC:GetThemeLayout("settingsColumns", 2)
    local columns = requestedColumns == 2 and sectionWidth >= 720 and 2 or 1
    self.Active[container] = {
        section = section,
        baseHeight = baseHeight,
        nextY = baseHeight,
        rowIndex = 0,
        padX = RC:GetThemeLayout("sectionPadX", 16),
        padRight = RC:GetThemeLayout("settingsContentRightInset", RC:GetThemeLayout("sectionPadX", 16)),
        columns = columns,
        columnGap = RC:GetThemeLayout("settingsColumnGap", 14),
    }
    section:SetHeight(baseHeight + SectionBottomPad())
    ApplySectionFrameTheme(section.frame, self.Active[container])
    function section:OnRelease()
        if V2.ResetSimpleGroupWidget then
            V2:ResetSimpleGroupWidget(self)
        end
    end
    return section
end

function V2.Sections:AddWidget(container, widget, width, height, options)
    options = options or {}
    local state = self.Active[container]
    if not state or not state.section then
        container:AddChild(widget)
        return widget
    end

    local section = state.section
    local rowHeight = math.max(height or RC:GetThemeLayout("settingsRowHeight", 42), RC:GetThemeLayout("compactRowHeight", 34))
    local contentWidth = math.max(120, ContentWidth(section.frame) - state.padX - state.padRight)
    local useFullWidth = options.fullWidth or state.columns ~= 2
    if not useFullWidth and not state.hasHalfRows then
        state.hasHalfRows = true
        if section.frame._rcV2ColumnRule then
            section.frame._rcV2ColumnRule:Show()
        end
    end
    local columnGap = state.columnGap or 14
    local cellWidth = useFullWidth and contentWidth or math.floor((contentWidth - columnGap) / 2)
    local widgetWidth = math.min(width or cellWidth, cellWidth)
    if useFullWidth then
        widgetWidth = contentWidth
    end
    local widgetX = 0
    if options.align == "right" then
        widgetX = cellWidth - widgetWidth
    elseif options.align == "center" then
        widgetX = math.floor((cellWidth - widgetWidth) / 2)
    elseif options.offsetX then
        widgetX = math.max(0, math.min(options.offsetX, cellWidth - widgetWidth))
    end

    state.rowIndex = state.rowIndex + 1
    local rowTop
    local column = 1
    if useFullWidth then
        state.pendingColumn = nil
        rowTop = state.nextY
        state.nextY = state.nextY + rowHeight
    elseif state.pendingColumn then
        column = 2
        rowTop = state.pendingColumn.top
        state.nextY = rowTop + math.max(state.pendingColumn.height, rowHeight)
        state.pendingColumn = nil
    else
        rowTop = state.nextY
        state.pendingColumn = { top = rowTop, height = rowHeight }
        state.nextY = rowTop + rowHeight
    end
    local cellX = column == 2 and (cellWidth + columnGap) or 0
    local record = AcquireRowRecord(section.frame, #section.frame._rcV2RowData + 1)
    local rowBg = record.bg
    rowBg:ClearAllPoints()
    rowBg:SetPoint("TOPLEFT", section.frame, "TOPLEFT", state.padX + cellX + (options.compactRow and widgetX or 0), -rowTop)
    if options.compactRow then
        rowBg:SetWidth(widgetWidth)
    else
        rowBg:SetWidth(cellWidth)
    end
    rowBg:SetHeight(math.max(1, rowHeight - 1))
    if options.rowStyle == "toolbar" then
        rowBg:SetColorTexture(
            RC.Config.SurfaceBg.r,
            RC.Config.SurfaceBg.g,
            RC.Config.SurfaceBg.b,
            RC:IsShadowsteelTheme() and 0.34 or 0.42
        )
    else
        RC:ApplyThemedSettingsRow(rowBg, state.rowIndex)
        rowBg:SetAlpha(1)
    end
    rowBg:Show()
    table.insert(section.frame._rcV2Rows, rowBg)

    local divider = record.divider
    divider:ClearAllPoints()
    divider:SetPoint("BOTTOMLEFT", rowBg, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", rowBg, "BOTTOMRIGHT", 0, 0)
    divider:SetColorTexture(
        RC.Config.SeparatorColor.r,
        RC.Config.SeparatorColor.g,
        RC.Config.SeparatorColor.b,
        math.min(RC:GetThemeLayout("rowSeparatorAlpha", 0.055), RC.Config.SeparatorColor.a or 0.055)
    )
    divider:Show()
    table.insert(section.frame._rcV2Rows, divider)

    -- Toolbars are groups of buttons, not a single setting, so they get no
    -- row highlight.
    record.title = options.tooltipTitle
    record.tooltip = options.tooltip
    record.hotspot:SetShown(options.rowStyle ~= "toolbar")
    table.insert(section.frame._rcV2Rows, record.hover)
    table.insert(section.frame._rcV2Rows, record.marker)
    table.insert(section.frame._rcV2Rows, record.hotspot)
    table.insert(section.frame._rcV2RowData, {
        bg = rowBg,
        divider = divider,
        record = record,
        index = state.rowIndex,
        style = options.rowStyle,
    })

    section:AddChild(widget)
    widget:SetWidth(widgetWidth)
    widget:SetHeight(rowHeight)
    if widget.frame then
        local x = state.padX + cellX + widgetX
        widget.frame:ClearAllPoints()
        widget.frame:SetParent(section.frame)
        widget.frame:SetFrameStrata(section.frame:GetFrameStrata())
        widget.frame:SetFrameLevel(section.frame:GetFrameLevel() + 8)
        widget.frame:SetPoint("TOPLEFT", section.frame, "TOPLEFT", x, -rowTop)
        widget.frame:SetSize(widgetWidth, rowHeight)
        widget.frame:Show()
    end
    -- Grid widgets lay out their label and control in RefreshTheme, which
    -- last ran in OnAcquire before the grid flag and final size were set.
    if widget._rcSettingsGrid and widget.RefreshTheme then
        widget:RefreshTheme()
    end

    section:SetHeight(state.nextY + SectionBottomPad())
    widget._rcV2RowRecord = record
    widget._rcV2RowToken = record.token
    return widget
end

-- Controls that take the mouse over their whole row (checkboxes, color
-- swatches) cover the hotspot, so they report hover through their own frame.
-- The hook is installed once per pooled frame and ignores the widget once it
-- has been released or moved to another row.
function V2.Sections:BindRowHover(widget, rowWidget)
    rowWidget = rowWidget or widget
    local frame = widget and widget.frame
    local record = rowWidget and rowWidget._rcV2RowRecord
    if not frame or not record or not frame.HookScript then
        return
    end

    widget._rcV2HoverRecord = record
    widget._rcV2HoverToken = rowWidget._rcV2RowToken
    if frame._rcV2HoverHooked then
        return
    end
    frame._rcV2HoverHooked = true

    local function CurrentRecord()
        local current = widget._rcSettingsGrid and widget._rcV2HoverRecord
        if current and current.token == widget._rcV2HoverToken then
            return current
        end
        return nil
    end
    frame:HookScript("OnEnter", function()
        local current = CurrentRecord()
        if current then
            EnterRow(current)
        end
    end)
    frame:HookScript("OnLeave", function()
        local current = CurrentRecord()
        if current then
            LeaveRow(current)
        end
    end)
end

function V2.Sections:ClearContainer(container)
    if container then
        self.Active[container] = nil
    end
end

function V2.Sections:Refresh(container)
    if container then
        local state = self.Active[container]
        if state and state.section then
            ApplySectionFrameTheme(state.section.frame, state)
        end
        return
    end

    for _, state in pairs(self.Active) do
        if state and state.section then
            ApplySectionFrameTheme(state.section.frame, state)
        end
    end
end
