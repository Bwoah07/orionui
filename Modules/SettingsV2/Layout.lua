local _, ns = ...
local RC = ns.RC

RC.SettingsV2 = RC.SettingsV2 or {}
local V2 = RC.SettingsV2

V2.Layout = V2.Layout or {}

-- Sidebar stack, top to bottom: brand, quick actions, search, the SETTINGS
-- caption and the page list. Each block is placed from the one above it, so
-- adding or removing a quick action keeps the spacing intact.
local SIDEBAR_BRAND_HEIGHT = 96
local QUICK_ACTION_HEIGHT = 40
local SIDEBAR_SEARCH_GAP = 10
local SIDEBAR_SEARCH_HEIGHT = 30
local SIDEBAR_CAPTION_GAP = 10
local SIDEBAR_CAPTION_HEIGHT = 18

local function GetSidebarStack(shell)
    local actionCount = shell.quickActions and #shell.quickActions or 0
    local searchTop = SIDEBAR_BRAND_HEIGHT + (actionCount * QUICK_ACTION_HEIGHT) + SIDEBAR_SEARCH_GAP
    local captionTop = searchTop + SIDEBAR_SEARCH_HEIGHT + SIDEBAR_CAPTION_GAP
    return {
        searchTop = searchTop,
        captionTop = captionTop,
        navTop = captionTop + SIDEBAR_CAPTION_HEIGHT,
    }
end

local function Metric(key, fallback)
    return RC:GetThemeLayout(key, fallback)
end

function V2.Layout:GetMetrics()
    return {
        width = Metric("settingsWidth", 980),
        height = Metric("settingsHeight", 640),
        sidebarWidth = Metric("sidebarWidth", 260),
        headerHeight = Metric("headerHeight", 108),
        footerHeight = Metric("footerHeight", 60),
        tabBarHeight = Metric("tabBarHeight", 38),
        contentPaddingX = Metric("contentPaddingX", 18),
        contentPaddingY = Metric("contentPaddingY", 18),
        scrollbarOuterInset = Metric("settingsScrollbarOuterInset", 8),
        panelPadding = Metric("panelPadding", 16),
        controlHeight = Metric("controlHeight", 24),
        buttonHeight = Metric("buttonHeight", 30),
        sidebarFullHeight = Metric("sidebarFullHeight", true),
        headerContentOnly = Metric("headerContentOnly", true),
        footerContentOnly = Metric("footerContentOnly", true),
    }
end

function V2.Layout:GetContentWidth()
    local m = self:GetMetrics()
    return math.max(520, m.width - m.sidebarWidth - (m.contentPaddingX * 2) - 16)
end

function V2.Layout:Apply(shell)
    if not shell or not shell.frame then
        return
    end

    local m = self:GetMetrics()
    local frame = shell.frame
    frame:SetSize(m.width, m.height)

    for _, region in ipairs({
        shell.header,
        shell.sidebar,
        shell.topTabs,
        shell.contentFrame,
        shell.scroll,
        shell.footer,
        shell.sidebarNav,
        shell.searchBox,
        shell.pageSearchBox,
        shell.sidebarSeparator,
        shell.headerSeparatorFrame,
        shell.logoMark,
        shell.dragHandle,
        shell.externalPageLayer,
    }) do
        if region and region.ClearAllPoints then
            region:ClearAllPoints()
        end
    end

    if m.sidebarFullHeight then
        shell.sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
        shell.sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    else
        shell.sidebar:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(m.headerHeight + 1))
        shell.sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, m.footerHeight + 1)
    end
    shell.sidebar:SetWidth(m.sidebarWidth)

    if m.headerContentOnly then
        shell.header:SetPoint("TOPLEFT", shell.sidebar, "TOPRIGHT", 0, 0)
    else
        shell.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    end
    shell.header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    shell.header:SetHeight(m.headerHeight)

    if m.footerContentOnly then
        shell.footer:SetPoint("BOTTOMLEFT", shell.sidebar, "BOTTOMRIGHT", 0, 1)
    else
        shell.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 1)
    end
    shell.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    shell.footer:SetHeight(m.footerHeight)

    if m.headerContentOnly then
        shell.contentFrame:SetPoint("TOPLEFT", shell.header, "BOTTOMLEFT", 0, 0)
    elseif m.sidebarFullHeight then
        shell.contentFrame:SetPoint("TOPLEFT", shell.sidebar, "TOPRIGHT", 0, -m.headerHeight)
    else
        shell.contentFrame:SetPoint("TOPLEFT", shell.sidebar, "TOPRIGHT", 0, 0)
    end
    shell.contentFrame:SetPoint("BOTTOMRIGHT", shell.footer, "TOPRIGHT", 0, 0)

    shell.topTabs:SetPoint("TOPLEFT", shell.contentFrame, "TOPLEFT", 0, 0)
    shell.topTabs:SetPoint("TOPRIGHT", shell.contentFrame, "TOPRIGHT", 0, 0)
    shell.topTabs:SetHeight(m.tabBarHeight)

    shell.scroll:SetPoint("TOPLEFT", shell.contentFrame, "TOPLEFT", m.contentPaddingX, -(m.tabBarHeight + m.contentPaddingY))
    shell.scroll:SetPoint("BOTTOMRIGHT", shell.contentFrame, "BOTTOMRIGHT", -m.scrollbarOuterInset, m.contentPaddingY)

    if shell.externalPageLayer then
        shell.externalPageLayer:SetAllPoints(shell.contentFrame)
    end

    local stack = GetSidebarStack(shell)
    local navBottomInset = m.sidebarFullHeight and (m.footerHeight + 8) or m.panelPadding
    shell.sidebarNav:SetPoint("TOPLEFT", shell.sidebar, "TOPLEFT", m.panelPadding, -stack.navTop)
    shell.sidebarNav:SetPoint("BOTTOMRIGHT", shell.sidebar, "BOTTOMRIGHT", -m.panelPadding, navBottomInset)

    for index, action in ipairs(shell.quickActions or {}) do
        local top = SIDEBAR_BRAND_HEIGHT + ((index - 1) * QUICK_ACTION_HEIGHT)
        action:ClearAllPoints()
        action:SetPoint("TOPLEFT", shell.sidebar, "TOPLEFT", 0, -top)
        action:SetPoint("TOPRIGHT", shell.sidebar, "TOPRIGHT", 0, -top)
        action:SetHeight(QUICK_ACTION_HEIGHT)
    end

    if shell.sidebarSeparator then
        shell.sidebarSeparator:SetWidth(1)
        shell.sidebarSeparator:SetPoint("TOPLEFT", shell.sidebar, "TOPRIGHT", 0, 0)
        shell.sidebarSeparator:SetPoint("BOTTOMLEFT", shell.sidebar, "BOTTOMRIGHT", 0, 0)
    end

    if shell.headerSeparatorFrame then
        shell.headerSeparatorFrame:SetHeight(1)
        shell.headerSeparatorFrame:SetPoint("BOTTOMLEFT", shell.header, "BOTTOMLEFT", 0, 0)
        shell.headerSeparatorFrame:SetPoint("BOTTOMRIGHT", shell.header, "BOTTOMRIGHT", 0, 0)
    end

    if shell.title then
        shell.title:ClearAllPoints()
        shell.title:SetPoint("TOPLEFT", shell.header, "TOPLEFT", 38, -26)
        shell.title:SetPoint("RIGHT", shell.header, "RIGHT", -76, 0)
    end

    if shell.description then
        shell.description:ClearAllPoints()
        shell.description:SetPoint("TOPLEFT", shell.title, "BOTTOMLEFT", 2, -7)
        shell.description:SetPoint("RIGHT", shell.header, "RIGHT", -90, 0)
    end

    if shell.logoMark then
        shell.logoMark:ClearAllPoints()
        shell.logoMark:SetPoint("TOPLEFT", shell.sidebar, "TOPLEFT", 20, -18)
        shell.logoMark:SetSize(46, 46)
    end

    if shell.brand then
        shell.brand:ClearAllPoints()
        shell.brand:SetPoint("TOPLEFT", shell.logoMark or shell.sidebar, shell.logoMark and "TOPRIGHT" or "TOPLEFT", shell.logoMark and 12 or 22, shell.logoMark and -3 or -22)
        shell.brand:SetPoint("RIGHT", shell.sidebar, "RIGHT", -18, 0)
    end

    if shell.tagline then
        shell.tagline:ClearAllPoints()
        shell.tagline:SetPoint("TOPLEFT", shell.brand, "BOTTOMLEFT", 1, -5)
        shell.tagline:SetPoint("RIGHT", shell.sidebar, "RIGHT", -18, 0)
    end

    if shell.sectionLabel then
        shell.sectionLabel:ClearAllPoints()
        shell.sectionLabel:SetPoint("TOPLEFT", shell.sidebar, "TOPLEFT", m.panelPadding + 2, -stack.captionTop)
    end

    if shell.searchBox then
        shell.searchBox:ClearAllPoints()
        shell.searchBox:SetPoint("TOPLEFT", shell.sidebar, "TOPLEFT", m.panelPadding, -stack.searchTop)
        shell.searchBox:SetPoint("TOPRIGHT", shell.sidebar, "TOPRIGHT", -m.panelPadding, -stack.searchTop)
        shell.searchBox:SetHeight(SIDEBAR_SEARCH_HEIGHT)
    end

    if shell.versionText then
        shell.versionText:ClearAllPoints()
        shell.versionText:SetPoint("BOTTOMLEFT", shell.sidebar, "BOTTOMLEFT", m.panelPadding + 2, 18)
    end

    if shell.closeButton then
        local closeSize = 30
        shell.closeButton:ClearAllPoints()
        shell.closeButton:SetPoint("TOPRIGHT", shell.header, "TOPRIGHT", -18, -18)
        shell.closeButton:SetSize(closeSize, closeSize)
        if shell.closeButton.Icon then
            shell.closeButton.Icon:SetSize(math.max(11, closeSize - 12), math.max(11, closeSize - 12))
        end
    end

    if shell.scaleLabel then
        shell.scaleLabel:ClearAllPoints()
    end

    if shell.pageSearchBox then
        shell.pageSearchBox:ClearAllPoints()
        shell.pageSearchBox:SetPoint("RIGHT", shell.topTabs, "RIGHT", -38, 0)
        shell.pageSearchBox:SetSize(236, 28)
    end

    if shell.dragHandle then
        shell.dragHandle:ClearAllPoints()
        shell.dragHandle:SetAllPoints(shell.header)
    end
    if shell.scaleSlider then
        shell.scaleSlider:ClearAllPoints()
    end
    if shell.scaleLabel then
        if shell.reloadButton then
            shell.scaleLabel:SetPoint("LEFT", shell.reloadButton, "RIGHT", 16, 0)
        else
            shell.scaleLabel:SetPoint("RIGHT", shell.scaleSlider, "LEFT", -8, 0)
        end
    end
    if shell.scaleSlider then
        if shell.scaleLabel and shell.reloadButton then
            shell.scaleSlider:SetPoint("LEFT", shell.scaleLabel, "RIGHT", 8, 0)
        else
            shell.scaleSlider:SetPoint("RIGHT", shell.closeButton, "LEFT", -12, 0)
        end
    end

    if shell.reloadButton then
        shell.reloadButton:ClearAllPoints()
        shell.reloadButton:SetSize(150, math.max(34, m.buttonHeight))
        shell.reloadButton:SetPoint("BOTTOMLEFT", shell.footer, "BOTTOMLEFT", 38, math.max(6, math.floor((m.footerHeight - m.buttonHeight) / 2)))
    end
    if shell.layoutButton then
        shell.layoutButton:ClearAllPoints()
        shell.layoutButton:SetSize(150, math.max(34, m.buttonHeight))
        shell.layoutButton:SetPoint("LEFT", shell.reloadButton, "RIGHT", 18, 0)
    end
    if shell.doneButton then
        shell.doneButton:ClearAllPoints()
        shell.doneButton:SetSize(160, math.max(34, m.buttonHeight))
        shell.doneButton:SetPoint("BOTTOMRIGHT", shell.footer, "BOTTOMRIGHT", -24, math.max(6, math.floor((m.footerHeight - m.buttonHeight) / 2)))
    end

    if shell.contentContainer and shell.contentContainer.frame then
        shell.contentContainer.frame:ClearAllPoints()
        shell.contentContainer.frame:SetAllPoints(shell.scroll)
    end
end
