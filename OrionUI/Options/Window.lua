-- The options window (CLAUDE.md §9.1). The sidebar is laid out like EllesmereUI's (Stig, 2026-10-02):
-- tool rows on top (Unlock Mode, Raid Split, Profiles), then the search box, then the settings as
-- accent-coloured group headings with rows under them. Under "OrionUI" each row is a big part
-- (General, Interface, Reminders, Class) whose pages show as tabs along the top; under
-- "Raid Control" every raid tool is its own row. Pages are built from module schemas or are
-- hand-written editors, laid out as a title plus cards of "label | control" rows. A search box
-- works across all option labels. Created lazily on first open.
local _, ns = ...

local L = ns.L
local Options = { pages = {} }
ns.Options = Options

-- perPage: every page of the category gets its own sidebar row instead of a tab.
local GROUPS = {
    { label = ns.NAME, categories = {
        { key = "general",   label = L["General"] },
        { key = "qol",       label = L["Interface"] },
        { key = "reminders", label = L["Reminders"] },
        { key = "tank",      label = L["Class"] },
    } },
    { label = L["Raid Control"], categories = {
        { key = "raid", perPage = true },
    } },
}
-- Rows above the search box: tools that open something, or a page that isn't part of a group.
-- available() hides a row when its tool is missing.
local ACTIONS = {
    { label = L["Unlock Mode"], func = function() ns.EditMode:Toggle(true) end },
    { label = L["Raid Split"], available = function() return ns.RC ~= nil end,
      func = function()
          if InCombatLockdown() then ns.Print(L.COMBAT_REFUSED) return end
          OrionUIOptions:Hide() -- the planner opens where the options window sits
          ns.Slash:Run("split")
      end },
    { label = L["Profiles"], page = "profiles" },
}

local PER_PAGE = {}
for _, group in ipairs(GROUPS) do
    for _, cat in ipairs(group.categories) do PER_PAGE[cat.key] = cat.perPage end
end
local WIDTH, HEIGHT, SIDEBAR, TITLEBAR = 1000, 640, 180, 52
local PAD, CARD_GAP = 16, 20
local TAB_H, TAB_GAP = 30, 4
local ROW_H, ROW_STEP, GROUP_H, GROUP_GAP = 32, 34, 26, 14

local frame, current
local lastInCategory = {} -- category key -> last page shown there (the sidebar reopens it)

-- Hand-written page: { category, label, order, desc, build(container, addRows, width) -> height,
-- refresh(container) optional }. addRows(specs, y) lays out standard widgets and cards.
function Options:RegisterPage(id, page)
    page.id = id
    self.pages[id] = page
end

---------------------------------------------------------------------------
-- Layout: Title / Header (starts a new card) / any widget row (goes in the current card).
-- Every page is built once into its own container and afterwards only refreshed:
-- WoW never frees frames, so rebuilding on every visit would leak.
---------------------------------------------------------------------------

local cache = {} -- id -> { container, rows }

local function Divider(container, y)
    local t = container:CreateTexture(nil, "BORDER")
    t:SetColorTexture(unpack(ns.Theme.colors.line))
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", PAD, -y)
    t:SetPoint("TOPRIGHT", -PAD, -y)
end

local function AddRows(container, rows, specs, y)
    local T, width = ns.Theme, frame.contentWidth
    local cardTop, inCard, rowsInCard = 0, false, 0
    local function Open()
        cardTop, inCard, rowsInCard = y, true, 0
        y = y + 6
    end
    local function Close()
        if not inCard then return end
        y = y + 6
        T:Box(container):Place(0, cardTop, width, y - cardTop)
        inCard = false
        y = y + CARD_GAP
    end
    for _, spec in ipairs(specs) do
        if spec.type == "Title" then
            Close()
            local title = T:Text(container, 20)
            title:SetPoint("TOPLEFT", 0, -y)
            title:SetText(spec.label)
            y = y + 28
            if spec.desc then
                local d = T:Text(container, 12, T.colors.muted)
                d:SetPoint("TOPLEFT", 0, -y)
                d:SetWidth(width)
                d:SetText(spec.desc)
                y = y + d:GetStringHeight() + 6
            end
            y = y + 14
        elseif spec.type == "Footer" then
            -- Quiet text action under the cards (e.g. "Reset this module").
            Close()
            local b = T:TextButton(container, spec.label, 12)
            b:SetPoint("TOPRIGHT", 0, -y + 8)
            b:SetScript("OnClick", spec.func)
            y = y + 24
        elseif spec.type == "Header" then
            Close()
            -- Section headings in OrionUI blue, so each card is easy to find at a glance.
            local r, g, b = T:Accent()
            local h = T:Text(container, 12, { r, g, b, 1 })
            h:SetPoint("TOPLEFT", 2, -y)
            h:SetText(spec.label:upper())
            y = y + 20
            Open()
        else
            local ctor = ns.Widgets[spec.type]
            if ctor then
                if not inCard then Open() end
                if rowsInCard > 0 then Divider(container, y) end
                local row = ctor(container, spec)
                row.spec = spec
                row:SetPoint("TOPLEFT", PAD, -y)
                row:SetWidth(width - 2 * PAD)
                row:Refresh()
                row.homeY = y
                rows[#rows + 1] = row
                rowsInCard = rowsInCard + 1
                y = y + row:GetHeight()
            end
        end
    end
    Close()
    return y
end

local function NewContainer()
    local c = CreateFrame("Frame", nil, frame.scroll)
    c:SetSize(frame.contentWidth, 1)
    c:Hide()
    return c
end

local function ModuleSpecs(M)
    local specs = { { type = "Title", label = M.label, desc = M.desc } }
    local body = ns.OptionsBuilder:Specs(M)
    -- Settings before the first section heading go in a "General" card.
    if body[1] and body[1].type ~= "Header" then specs[#specs + 1] = { type = "Header", label = L["Settings"] } end
    for _, s in ipairs(body) do specs[#specs + 1] = s end
    if M.profileKey then
        specs[#specs + 1] = { type = "Footer", label = L["Reset this module"], func = function()
            ns.Dialog:Confirm(L["Reset all settings of"] .. " " .. M.label .. "?\n" .. L["A backup is made first."], function()
                M:ResetSettings()
                Options:Refresh()
            end)
        end }
    end
    return specs
end

local function Build(id)
    if cache[id] then return cache[id] end
    local page, M = Options.pages[id], ns.Modules:Get(id)
    if not (page or M) then return nil end
    local entry = { container = NewContainer(), rows = {} }
    local height
    if page then
        height = page.build(entry.container, function(specs, y)
            return AddRows(entry.container, entry.rows, specs, y)
        end, frame.contentWidth)
    else
        height = AddRows(entry.container, entry.rows, ModuleSpecs(M), 0)
    end
    entry.container:SetHeight(math.max((height or 0) + 8, 1))
    cache[id] = entry
    return entry
end

-- Search borrows matching rows from module pages and puts them back afterwards.
local search = { rows = {} }

local function ReturnSearchRows()
    for _, row in ipairs(search.rows) do
        row:SetParent(row.home)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", PAD, -row.homeY)
    end
    wipe(search.rows)
end

local function ShowSearch(query)
    local T = ns.Theme
    if not search.container then
        search.container = NewContainer()
        search.title = T:Text(search.container, 20)
        search.title:SetPoint("TOPLEFT")
        search.box = T:Box(search.container)
    end
    local c = search.container
    query = query:lower()
    local y = 48
    for _, M in ns.Modules:Iterate() do
        local entry = (M.profileKey or M.options) and not M.hideInOptions and Build(M.name)
        for _, row in ipairs(entry and entry.rows or {}) do
            local label = row.spec.label
            if row.spec.type ~= "Description" and type(label) == "string" and label:lower():find(query, 1, true) then
                row.home = entry.container
                row:SetParent(c)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", PAD, -y)
                row:Refresh()
                search.rows[#search.rows + 1] = row
                y = y + row:GetHeight()
            end
        end
    end
    local found = #search.rows > 0
    search.title:SetText(found and (L["Results for"] .. " \"" .. query .. "\"") or L["Nothing matches."])
    search.box:SetShown(found)
    if found then search.box:Place(0, 42, frame.contentWidth, y - 42 + 6) end
    c:SetHeight(y + 14)
    return c
end

function Options:Show(target)
    if not frame then self:Create() end
    ReturnSearchRows()
    if frame.shown then frame.shown:Hide() end
    current = target or current or "profiles"
    local container
    local query = frame.search:GetText()
    if query ~= "" then
        container = ShowSearch(query)
    else
        local entry = Build(current)
        if not entry then
            current = "profiles"
            entry = Build(current)
        end
        for _, row in ipairs(entry.rows) do row:Refresh() end
        local page = self.pages[current]
        if page and page.refresh then ns.SafeCall("Options", page.refresh, entry.container) end
        container = entry.container
    end
    frame.scroll:SetScrollChild(container)
    container:Show()
    frame.shown = container
    frame.scroll:ScrollTo(0)
    self:RefreshSidebar()
end

function Options:Refresh()
    if frame and frame:IsShown() then self:Show(current) end
end

---------------------------------------------------------------------------
-- Sidebar
---------------------------------------------------------------------------

local function Entries()
    local byCat = {}
    for _, M in ns.Modules:Iterate() do
        if (M.profileKey or M.options) and not M.hideInOptions then
            byCat[M.category] = byCat[M.category] or {}
            table.insert(byCat[M.category], { id = M.name, label = M.label, order = M.order })
        end
    end
    for id, page in pairs(Options.pages) do
        local cat = page.category or "general"
        byCat[cat] = byCat[cat] or {}
        table.insert(byCat[cat], { id = id, label = page.label, order = page.order or 100 })
    end
    for _, list in pairs(byCat) do
        table.sort(list, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.label < b.label
        end)
    end
    return byCat
end

local function SidebarButton(bar)
    local T = ns.Theme
    local btn = CreateFrame("Button", nil, bar)
    btn:SetSize(SIDEBAR - 16, ROW_H)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.mark = btn:CreateTexture(nil, "ARTWORK")
    btn.mark:SetPoint("TOPLEFT")
    btn.mark:SetPoint("BOTTOMLEFT")
    btn.mark:SetWidth(2)
    btn.label = T:Text(btn, 14)
    btn.label:SetPoint("LEFT", 14, 0)
    btn.label:SetPoint("RIGHT", -6, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetWordWrap(false)
    btn:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(1, 1, 1, 0.04) end end)
    btn:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end end)
    return btn
end

local function CategoryOf(id, byCat)
    for key, list in pairs(byCat) do
        for _, e in ipairs(list) do if e.id == id then return key end end
    end
end

local function StyleRow(btn, selected, r, g, b)
    local T = ns.Theme
    btn.selected = selected
    btn.mark:SetColorTexture(r, g, b, 1)
    btn.mark:SetShown(selected)
    if selected then
        btn.bg:SetColorTexture(r, g, b, 0.12)
        btn.label:SetTextColor(unpack(T.colors.text))
    else
        btn.bg:SetColorTexture(0, 0, 0, 0)
        btn.label:SetTextColor(unpack(T.colors.muted))
    end
end

function Options:RefreshSidebar()
    local T, bar, sb = ns.Theme, frame.sidebar.list, frame.sidebar
    for _, b in ipairs(sb.buttons) do b:Hide() end
    for _, h in ipairs(sb.headers) do h:Hide() end
    local byCat, y, nb, nh = Entries(), 10, 0, 0
    local r, g, b = T:Accent()
    local searching = frame.search:GetText() ~= ""
    local currentCat = CategoryOf(current, byCat)
    local function Row(label, selected, onClick)
        nb = nb + 1
        local btn = sb.buttons[nb] or SidebarButton(bar)
        sb.buttons[nb] = btn
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 8, -y)
        btn.label:SetText(label)
        StyleRow(btn, selected and not searching, r, g, b)
        btn:SetScript("OnClick", function()
            frame.search:SetText("")
            onClick()
        end)
        btn:Show()
        y = y + ROW_STEP
    end
    for _, a in ipairs(sb.actions) do
        StyleRow(a, a.action.page ~= nil and a.action.page == current and not searching, r, g, b)
    end
    for _, group in ipairs(GROUPS) do
        local any = false
        for _, cat in ipairs(group.categories) do
            if byCat[cat.key] and #byCat[cat.key] > 0 then any = true end
        end
        if any then
            -- Group heading in OrionUI blue, like EllesmereUI's "Core Addons".
            if nh > 0 then y = y + GROUP_GAP end
            nh = nh + 1
            local h = sb.headers[nh] or T:Text(bar, 15)
            sb.headers[nh] = h
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 16, -(y + 6))
            h:SetTextColor(r, g, b, 1)
            h:SetText(group.label)
            h:Show()
            y = y + GROUP_H
            for _, cat in ipairs(group.categories) do
                local list = byCat[cat.key]
                if list and #list > 0 then
                    if cat.perPage then
                        for _, e in ipairs(list) do
                            Row(e.label, e.id == current, function() Options:Show(e.id) end)
                        end
                    else
                        Row(cat.label, cat.key == currentCat, function()
                            Options:Show(lastInCategory[cat.key] or list[1].id)
                        end)
                    end
                end
            end
        end
    end
    bar:SetHeight(y + 8)
    sb.scroll:UpdateThumb()
    self:RefreshTabs(byCat, currentCat, searching)
end

---------------------------------------------------------------------------
-- Tabs: the pages of the selected part, along the top of the content area
---------------------------------------------------------------------------

local function TabButton(parent)
    local T = ns.Theme
    local tab = CreateFrame("Button", nil, parent)
    tab:SetHeight(TAB_H)
    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()
    tab.line = tab:CreateTexture(nil, "ARTWORK")
    tab.line:SetPoint("BOTTOMLEFT")
    tab.line:SetPoint("BOTTOMRIGHT")
    tab.line:SetHeight(2)
    tab.label = T:Text(tab, 13)
    tab.label:SetPoint("CENTER", 0, 1)
    tab.label:SetWordWrap(false)
    tab:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(1, 1, 1, 0.04) end end)
    tab:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end end)
    return tab
end

function Options:RefreshTabs(byCat, currentCat, searching)
    local T, strip = ns.Theme, frame.tabs
    for _, t in ipairs(strip.buttons) do t:Hide() end
    local list = not searching and currentCat and not PER_PAGE[currentCat] and byCat[currentCat] or {}
    local r, g, b = T:Accent()
    local x, rowY, width = 0, 0, frame.contentWidth
    for i, e in ipairs(#list > 1 and list or {}) do
        local tab = strip.buttons[i] or TabButton(strip)
        strip.buttons[i] = tab
        tab.label:SetText(e.label)
        local w = math.ceil(tab.label:GetStringWidth()) + 28
        if x > 0 and x + w > width then x, rowY = 0, rowY + TAB_H + TAB_GAP end -- wrap to a new row
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", x, -rowY)
        tab:SetWidth(w)
        tab.selected = e.id == current
        tab.line:SetColorTexture(r, g, b, 1)
        tab.line:SetShown(tab.selected)
        tab.bg:SetColorTexture(r, g, b, tab.selected and 0.10 or 0)
        tab.label:SetTextColor(unpack(tab.selected and T.colors.text or T.colors.muted))
        tab:SetScript("OnClick", function() Options:Show(e.id) end)
        tab:Show()
        x = x + w + TAB_GAP
    end
    local shown = #list > 1
    local h = shown and (rowY + TAB_H) or 0
    strip:SetHeight(math.max(h, 1))
    strip.line:SetShown(shown)
    frame.scroll:ClearAllPoints()
    frame.scroll:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, shown and -20 or 0)
    frame.scroll:SetPoint("BOTTOMRIGHT", -30, 20)
    if currentCat and not searching then lastInCategory[currentCat] = current end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

function Options:Create()
    local T = ns.Theme
    frame = CreateFrame("Frame", "OrionUIOptions", UIParent) -- global name: Esc closes via UISpecialFrames
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "OrionUIOptions")
    T:Skin(frame, T.colors.bg)
    T:Shadow(frame)

    -- Title bar (drag handle)
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT")
    titleBar:SetPoint("TOPRIGHT")
    titleBar:SetHeight(TITLEBAR)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    local line = titleBar:CreateTexture(nil, "BORDER")
    line:SetColorTexture(unpack(T.colors.line))
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", 1, 0)
    line:SetPoint("BOTTOMRIGHT", -1, 0)

    frame.logo = titleBar:CreateTexture(nil, "ARTWORK")
    frame.logo:SetSize(10, 10)
    frame.logo:SetPoint("LEFT", 20, 0)
    local title = T:Text(titleBar, 17)
    title:SetPoint("LEFT", frame.logo, "RIGHT", 10, 0)
    title:SetText(ns.NAME)
    local version = T:Text(titleBar, 11, T.colors.faint)
    version:SetPoint("LEFT", title, "RIGHT", 10, -1)
    version:SetText(ns.IS_DEV and "development build" or ("v" .. ns.VERSION))

    local close = T:TextButton(titleBar, "x", 16)
    close:SetPoint("RIGHT", -12, 1)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Sidebar
    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 1, -(TITLEBAR + 1))
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR)
    local sbg = sidebar:CreateTexture(nil, "BACKGROUND")
    sbg:SetAllPoints()
    sbg:SetColorTexture(unpack(T.colors.sidebar))
    local sline = sidebar:CreateTexture(nil, "BORDER")
    sline:SetColorTexture(unpack(T.colors.line))
    sline:SetWidth(1)
    sline:SetPoint("TOPRIGHT")
    sline:SetPoint("BOTTOMRIGHT")
    sidebar.buttons, sidebar.headers, sidebar.actions = {}, {}, {}

    -- Tool rows, fixed at the top like EUI's Unlock Mode / Global Settings.
    local y = 10
    for _, act in ipairs(ACTIONS) do
        if not act.available or act.available() then
            local btn = SidebarButton(sidebar)
            btn:SetPoint("TOPLEFT", 8, -y)
            btn.label:SetText(act.label)
            btn:SetScript("OnClick", function()
                if act.page then
                    frame.search:SetText("")
                    Options:Show(act.page)
                else
                    act.func()
                end
            end)
            sidebar.actions[#sidebar.actions + 1] = btn
            btn.action = act
            y = y + ROW_STEP
        end
    end

    local searchBox = CreateFrame("EditBox", nil, sidebar)
    searchBox:SetHeight(26)
    searchBox:SetPoint("TOPLEFT", 12, -(y + 8))
    searchBox:SetPoint("TOPRIGHT", -12, -(y + 8))
    searchBox:SetAutoFocus(false)
    searchBox:SetFont(T:Font(), 12, "")
    searchBox:SetTextInsets(10, 10, 0, 0)
    T:Skin(searchBox, T.colors.bg)
    searchBox.placeholder = T:Text(searchBox, 12, T.colors.faint)
    searchBox.placeholder:SetPoint("LEFT", 10, 0)
    searchBox.placeholder:SetText(L["Search settings"])
    searchBox:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "")
        if self.timer then self.timer:Cancel() end
        self.timer = C_Timer.NewTimer(0.2, function() Options:Show(current) end)
    end)
    searchBox:SetScript("OnEditFocusGained", function(self) T:SetBorderColor(self, T:Accent()) end)
    searchBox:SetScript("OnEditFocusLost", function(self) T:SetBorderColor(self, 0, 0, 0, 1) end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    frame.search = searchBox

    -- The settings groups below scroll when there are more rows than fit.
    sidebar.scroll = T:Scroll(sidebar)
    sidebar.scroll:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -12, -6)
    sidebar.scroll:SetPoint("BOTTOMRIGHT", -8, 0)
    sidebar.list = CreateFrame("Frame", nil, sidebar.scroll)
    sidebar.list:SetSize(SIDEBAR - 8, 1)
    sidebar.scroll:SetScrollChild(sidebar.list)
    frame.sidebar = sidebar

    -- Content: tab strip on top, the page scrolls below it.
    frame.contentWidth = WIDTH - SIDEBAR - 28 - 30 - 2
    local tabs = CreateFrame("Frame", nil, frame)
    tabs:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 28, -18)
    tabs:SetWidth(frame.contentWidth)
    tabs:SetHeight(1)
    tabs.buttons = {}
    tabs.line = tabs:CreateTexture(nil, "BORDER")
    tabs.line:SetColorTexture(unpack(T.colors.line))
    tabs.line:SetHeight(1)
    tabs.line:SetPoint("BOTTOMLEFT")
    tabs.line:SetPoint("BOTTOMRIGHT")
    frame.tabs = tabs
    local scroll = T:Scroll(frame)
    scroll:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -20)
    scroll:SetPoint("BOTTOMRIGHT", -30, 20)
    frame.scroll = scroll

    frame:SetScript("OnShow", function()
        frame.logo:SetColorTexture(T:Accent())
    end)
    frame:Hide()
end

function Options:Open(page)
    if not frame then self:Create() end
    frame:Show()
    self:Show(page)
end

function Options:Toggle()
    if frame and frame:IsShown() then frame:Hide() else self:Open() end
end
