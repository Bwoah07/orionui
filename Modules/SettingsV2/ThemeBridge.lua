local _, ns = ...
local RC = ns.RC

RC.SettingsV2 = RC.SettingsV2 or {}
local V2 = RC.SettingsV2

V2.ThemeBridge = V2.ThemeBridge or {}

local function ClearFrameArtifacts(artifacts)
    if not artifacts then
        return
    end

    for _, artifact in pairs(artifacts) do
        if artifact then
            if artifact.SetText then
                artifact:SetText("")
            end
            if artifact.Hide then
                artifact:Hide()
            end
            if artifact.ClearAllPoints then
                artifact:ClearAllPoints()
            end
        end
    end
end

function V2:ResetSimpleGroupWidget(group)
    if not group then
        return
    end

    group._rcV2Released = true
    group._rcV2LayoutToken = (group._rcV2LayoutToken or 0) + 1
    group._rcV2LayoutRunner = nil
    group.checkbox = nil
    group.buttons = nil
    group.actionButtons = nil
    group.RefreshTheme = nil
    group.OnRelease = nil

    local frame = group.frame
    if frame then
        if frame.Hide then
            frame:Hide()
        end
        if frame.ClearAllPoints then
            frame:ClearAllPoints()
        end
        ClearFrameArtifacts(frame._rcV2Rows)
        ClearFrameArtifacts(frame._rcManualArtifacts)
        ClearFrameArtifacts({
            frame._rcV2Accent,
            frame._rcV2TopRule,
            frame._rcV2Title,
            frame._rcV2Detail,
            frame._rcSectionTopLine,
            frame._rcSectionTitle,
            frame._rcSectionDetail,
        })
        frame._rcV2Rows = {}
        frame._rcV2RowData = {}
        frame._rcManualArtifacts = nil
        frame._rcV2HasDescription = nil

        if frame._rcV2HasBaseOnSizeChanged then
            frame:SetScript("OnSizeChanged", frame._rcV2BaseOnSizeChanged)
        end
        frame._rcV2ComposedLayout = nil
    end
end

function V2:SetSimpleGroupLayout(group, layoutFunc)
    local frame = group and group.frame
    if not frame or not layoutFunc then
        return nil
    end

    if not frame._rcV2HasBaseOnSizeChanged then
        frame._rcV2BaseOnSizeChanged = frame:GetScript("OnSizeChanged")
        frame._rcV2HasBaseOnSizeChanged = true
    end

    group._rcV2Released = false
    group._rcV2LayoutToken = (group._rcV2LayoutToken or 0) + 1
    local token = group._rcV2LayoutToken

    local function RunLayout()
        if group._rcV2Released or group._rcV2LayoutToken ~= token then
            return
        end
        layoutFunc()
    end

    frame._rcV2ComposedLayout = RunLayout
    group._rcV2LayoutRunner = RunLayout
    frame:SetScript("OnSizeChanged", function(self, ...)
        if self._rcV2BaseOnSizeChanged then
            self._rcV2BaseOnSizeChanged(self, ...)
        end
        RunLayout()
    end)

    return RunLayout
end

local function SetTextureColor(texture, color, alpha)
    if texture and color then
        texture:SetColorTexture(color.r, color.g, color.b, alpha or color.a or 1)
    end
end

local function SetHorizontalGradient(texture, color, leftAlpha, rightAlpha)
    if not texture or not color then
        return
    end
    if texture.SetGradient and CreateColor then
        texture:SetGradient(
            "HORIZONTAL",
            CreateColor(color.r, color.g, color.b, leftAlpha or 0),
            CreateColor(color.r, color.g, color.b, rightAlpha or 0)
        )
    else
        texture:SetColorTexture(color.r, color.g, color.b, math.max(leftAlpha or 0, rightAlpha or 0))
    end
end

local function RefreshAceWidgetTree(widget, seen)
    if not widget or seen[widget] then
        return
    end
    seen[widget] = true

    if widget.RefreshTheme then
        widget:RefreshTheme()
    end

    for _, child in ipairs(widget.children or {}) do
        RefreshAceWidgetTree(child, seen)
    end
end

function V2.ThemeBridge:RefreshVisibleWidgets(settings)
    local shell = settings and settings.v2Shell
    if not shell then
        return
    end

    local seen = {}
    RefreshAceWidgetTree(shell.sidebarContainer, seen)
    RefreshAceWidgetTree(shell.contentContainer, seen)
    RefreshAceWidgetTree(shell.scrollWidget, seen)
    RefreshAceWidgetTree(settings.activeSubTabRow, seen)

    if V2.Sections and V2.Sections.Refresh then
        V2.Sections:Refresh(shell.scrollWidget or settings.scroll)
    end
end

function V2.ThemeBridge:Apply(settings)
    local shell = settings and settings.v2Shell
    if not shell then
        return
    end

    if V2.Layout then
        V2.Layout:Apply(shell)
    end

    RC:ApplyThemedWindow(shell.frame, "window")
    RC:ApplyThemedHeader(shell.header)
    RC:ApplyThemedSidebar(shell.sidebar)
    local workspace = RC:GetModule("Workspace", true)
    if shell.frame.rcWorkspaceHosted and workspace and workspace.ApplyPageToolbar then
        workspace:ApplyPageToolbar(shell.footer)
    else
        RC:ApplyThemedFooter(shell.footer)
    end
    RC:ApplyThemedPanel(shell.contentFrame, "content", {
        role = "Color",
        borderAlpha = 0,
    })

    shell.frame:SetBackdropColor(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, 0.20)
    shell.header:SetBackdropColor(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0.18)
    shell.sidebar:SetBackdropColor(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0.30)
    shell.contentFrame:SetBackdropColor(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, 0.10)
    shell.footer:SetBackdropColor(RC.Config.HeaderBg.r, RC.Config.HeaderBg.g, RC.Config.HeaderBg.b, 0.38)
    if shell.frame.rcWorkspaceHosted and workspace and workspace.ApplyHostedPageRoot then
        workspace:ApplyHostedPageRoot(shell.frame)
    end

    if shell.headerAccent then
        shell.headerAccent:Hide()
    end
    if shell.headerGlow then
        SetHorizontalGradient(shell.headerGlow, RC.Config.Accent, 0.10, 0.78)
        shell.headerGlow:Show()
    end
    if shell.headerGlowSoft then
        SetHorizontalGradient(shell.headerGlowSoft, RC.Config.Accent, 0, 0.14)
        shell.headerGlowSoft:Show()
    end
    if shell.brandRule then
        SetTextureColor(shell.brandRule, RC.Config.Accent, 0.26)
        shell.brandRule:Show()
    end
    SetTextureColor(shell.headerSeparator, RC.Config.SeparatorColor, 0.08)
    SetTextureColor(shell.sidebarSeparatorTexture, RC.Config.SeparatorColor, 0.10)
    SetTextureColor(shell.topTabsBg, RC.Config.TabBg, 0.28)
    SetTextureColor(shell.topTabsLine, RC.Config.SeparatorColor, 0.08)
    SetTextureColor(shell.footerLine, RC.Config.SeparatorColor, 0.10)

    if shell.title then
        RC:SetFont(shell.title, 30, "OUTLINE")
        shell.title:SetTextColor(RC.Config.HeaderText.r, RC.Config.HeaderText.g, RC.Config.HeaderText.b, RC.Config.HeaderText.a or 1)
    end
    if shell.description then
        RC:SetFont(shell.description, 12, "")
        shell.description:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.82)
    end
    if shell.brand then
        RC:SetFont(shell.brand, 22, "OUTLINE")
        shell.brand:SetTextColor(RC.Config.HeaderText.r, RC.Config.HeaderText.g, RC.Config.HeaderText.b, RC.Config.HeaderText.a or 1)
    end
    if shell.tagline then
        RC:SetFont(shell.tagline, 9, "OUTLINE")
        shell.tagline:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC:IsShadowsteelTheme() and 0.70 or 0.82)
    end
    if shell.sectionLabel then
        RC:SetFont(shell.sectionLabel, 10, "OUTLINE")
        shell.sectionLabel:SetTextColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.90)
    end
    if shell.logoMark then
        shell.logoMark:SetBackdropColor(0, 0, 0, 0)
        shell.logoMark:SetBackdropBorderColor(0, 0, 0, 0)
    end
    if shell.logoMarkText then
        RC:SetFont(shell.logoMarkText, 15, "OUTLINE")
        shell.logoMarkText:SetTextColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
    end
    if shell.logoMarkTexture then
        shell.logoMarkTexture:SetVertexColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
    end
    if shell.versionText then
        shell.versionText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.70)
    end
    if shell.scaleSlider and shell.scaleSlider.RefreshTheme then
        shell.scaleSlider:RefreshTheme()
    end

    if shell.reloadButton then
        shell.reloadButton:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, 0.46)
        shell.reloadButton:SetBackdropBorderColor(RC:GetControlBorderColor())
        if shell.reloadButton.Text then
            shell.reloadButton.Text:SetTextColor(RC:GetButtonTextColor())
        end
    end

    if shell.layoutButton then
        shell.layoutButton:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, 0.46)
        shell.layoutButton:SetBackdropBorderColor(RC:GetControlBorderColor())
        if shell.layoutButton.Text then
            shell.layoutButton.Text:SetTextColor(RC:GetButtonTextColor())
        end
    end

    if shell.doneButton then
        shell.doneButton:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, 0.40)
        shell.doneButton:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.92)
        shell.doneButton.Text:SetTextColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
    end

    for _, tab in pairs(settings.tabs or {}) do
        if tab and tab.RefreshTheme then
            tab:RefreshTheme()
        end
    end

    self:RefreshVisibleWidgets(settings)
end
