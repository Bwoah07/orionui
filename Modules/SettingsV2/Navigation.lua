local _, ns = ...
local RC = ns.RC
local AceGUI = LibStub("AceGUI-3.0")
local L = RC.L

RC.SettingsV2 = RC.SettingsV2 or {}
local V2 = RC.SettingsV2

V2.Navigation = V2.Navigation or {}

function V2.Navigation:BuildSidebar(settings, pages)
    if not settings or not settings.sidebarContainer then
        return
    end
    pages = pages or (V2.Constants and V2.Constants:GetPages(settings)) or {}

    if settings.sidebarContainer.ReleaseChildren then
        settings.sidebarContainer:ReleaseChildren()
    end
    settings.sidebarContainer:SetLayout("List")

    settings.tabs = {}
    for _, tabInfo in ipairs(pages) do
        if not tabInfo.hidden then -- pages with their own top tab (Tank) stay out of the sidebar
            local tab = AceGUI:Create("RC_Tab")
            tab:SetText(tabInfo.label)
            if tab.SetTabStyle then
                tab:SetTabStyle("sidebar")
            end
            if tab.SetHovered then
                tab:SetHovered(false)
            end
            if tab.SetSelected then
                tab:SetSelected(tabInfo.key == settings.selectedTab)
            end
            tab:SetFullWidth(true)
            tab:SetHeight(RC:GetThemeLayout("navItemHeight", 40))
            tab:SetCallback("OnClick", function()
                local workspace = RC:GetModule("Workspace", true)
                if workspace and workspace.Open and workspace.activeKey ~= "settings" then
                    workspace:Open("settings")
                end
                if settings.ClearSearch then
                    settings:ClearSearch(false)
                end
                settings:SelectTab(tabInfo.key)
            end)
            settings.sidebarContainer:AddChild(tab)
            settings.tabs[tabInfo.key] = tab
        end
    end
    if settings.sidebarContainer.DoLayout then
        settings.sidebarContainer:DoLayout()
    end
end

function V2.Navigation:UpdateHeader(settings, tabInfo)
    local shell = settings and settings.v2Shell
    if not shell then
        return
    end
    if shell.title then
        shell.title:SetText((tabInfo and tabInfo.label) or L["Settings"])
    end
    if shell.description then
        shell.description:SetText((tabInfo and tabInfo.description) or "")
    end
end

function V2.Navigation:DrawTopTabs(settings, container, tabGroupKey, tabs, defaultKey)
    if V2.Sections and V2.Sections.Active then
        V2.Sections.Active[container] = nil
    end

    settings.subTabState = settings.subTabState or {}
    local selected = settings.subTabState[tabGroupKey] or defaultKey
    local selectedIsValid = false
    for _, tabInfo in ipairs(tabs or {}) do
        if tabInfo.key == selected then
            selectedIsValid = true
            break
        end
    end
    if not selectedIsValid then
        selected = defaultKey or (tabs and tabs[1] and tabs[1].key)
    end
    settings.subTabState[tabGroupKey] = selected

    local shell = settings.v2Shell
    if not shell or not shell.topTabs then
        return selected
    end

    if settings.activeSubTabRow then
        settings.activeSubTabRow:Release()
        settings.activeSubTabRow = nil
    end

    local row = AceGUI:Create("SimpleGroup")
    if V2.ResetSimpleGroupWidget then
        V2:ResetSimpleGroupWidget(row)
    end
    row:SetFullWidth(true)
    row:SetLayout("Manual")
    row:SetHeight(RC:GetThemeLayout("tabBarHeight", 38))
    row.frame:SetParent(shell.topTabs)
    row.frame:SetAllPoints(shell.topTabs)
    row.frame:SetFrameStrata(settings.frame:GetFrameStrata())
    row.frame:SetFrameLevel(shell.topTabs:GetFrameLevel() + 1)
    row.frame:Show()
    settings.activeSubTabRow = row
    shell.topTabs:Show()

    function row:OnRelease()
        if V2.ResetSimpleGroupWidget then
            V2:ResetSimpleGroupWidget(self)
        end
    end

    local tabWidgets = {}
    local function LayoutTabRow()
        local rowWidth = row.frame and row.frame:GetWidth() or (V2.Layout and V2.Layout:GetContentWidth()) or 640
        if not rowWidth or rowWidth < 10 then
            rowWidth = 640
        end
        local leftInset = RC:GetThemeLayout("contentPaddingX", 38)
        local searchReserve = shell.pageSearchBox and 292 or leftInset
        local available = math.max(160, rowWidth - leftInset - searchReserve)
        local count = math.max(#tabWidgets, 1)
        local preferredTotal = 0
        for _, tab in ipairs(tabWidgets) do
            preferredTotal = preferredTotal + (tab._rcPreferredWidth or 70)
        end
        local baseWidth = preferredTotal > available and math.floor(available / count) or nil
        local x = leftInset
        local tabHeight = RC:GetThemeLayout("tabHeight", 36)
        for index, tab in ipairs(tabWidgets) do
            local width = baseWidth or (tab._rcPreferredWidth or 84)
            if baseWidth and index == count then
                width = math.max(1, leftInset + available - x)
            end
            tab:SetWidth(width)
            tab:SetHeight(tabHeight)
            tab.frame:ClearAllPoints()
            tab.frame:SetPoint("TOPLEFT", row.frame, "TOPLEFT", x, 0)
            tab.frame:SetSize(width, tabHeight)
            x = x + width + 6
        end
    end

    for _, tabInfo in ipairs(tabs or {}) do
        local tab = AceGUI:Create("RC_Tab")
        tab:SetText(tabInfo.label)
        tab._rcPreferredWidth = math.max(82, math.min(148, 38 + (#tostring(tabInfo.label or "") * 7)))
        if tab.SetTabStyle then
            tab:SetTabStyle("top")
        end
        tab:SetWidth(120)
        tab:SetHeight(RC:GetThemeLayout("tabHeight", 36))
        tab:SetSelected(tabInfo.key == selected)
        tab:SetCallback("OnClick", function()
            settings.subTabState[tabGroupKey] = tabInfo.key
            if settings.scrollStatusByTab then
                settings.scrollStatusByTab[tabGroupKey] = { scrollvalue = 0, offset = 0 }
            end
            settings:SelectTab(tabGroupKey)
        end)
        row:AddChild(tab)
        table.insert(tabWidgets, tab)
    end

    local runLayout
    if V2.SetSimpleGroupLayout then
        runLayout = V2:SetSimpleGroupLayout(row, LayoutTabRow)
    end
    runLayout = runLayout or LayoutTabRow
    runLayout()
    C_Timer.After(0, runLayout)

    return selected
end
