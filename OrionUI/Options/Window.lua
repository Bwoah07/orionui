-- The options window (CLAUDE.md §9.1): sidebar grouped by category, pages built from
-- module schemas, hand-written pages for complex editors, and a search box across all
-- option labels. Created lazily on first open.
local _, ns = ...

local L = ns.L
local Options = { pages = {} }
ns.Options = Options

local CATEGORIES = {
    { key = "general",   label = L["General"] },
    { key = "reminders", label = L["Reminders"] },
    { key = "tank",      label = L["Tank"] },
    { key = "qol",       label = L["Quality of life"] },
    { key = "profiles",  label = L["Profiles"] },
}
local WIDTH, HEIGHT, SIDEBAR = 860, 580, 190
local ROW_GAP = 6

local frame, current

-- Hand-written page: { category, label, order, build(container, addRows, width) -> height,
-- refresh(container) optional }. addRows(specs, y) lays out standard widgets.
function Options:RegisterPage(id, page)
    page.id = id
    self.pages[id] = page
end

---------------------------------------------------------------------------
-- Page content. Every page is built once into its own container and afterwards only
-- refreshed: WoW never frees frames, so rebuilding on every visit would leak.
---------------------------------------------------------------------------

local cache = {} -- id -> { container, rows }

-- Lays out widget specs top to bottom in `container`; returns the y after the last row.
local function AddRows(container, rows, specs, y)
    for _, spec in ipairs(specs) do
        local ctor = ns.Widgets[spec.type]
        if ctor then
            local row = ctor(container, spec)
            row.spec = spec
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetWidth(frame.contentWidth)
            row:Refresh()
            row.homeY = y
            rows[#rows + 1] = row
            y = y + row:GetHeight() + ROW_GAP
        end
    end
    return y
end

local function NewContainer()
    local c = CreateFrame("Frame", nil, frame.scroll)
    c:SetSize(frame.contentWidth, 1)
    c:Hide()
    return c
end

local function ModuleSpecs(M)
    local specs = { { type = "Header", label = M.label } }
    for _, s in ipairs(ns.OptionsBuilder:Specs(M)) do specs[#specs + 1] = s end
    if M.profileKey then
        specs[#specs + 1] = { type = "Button", label = L["Reset this module"], func = function()
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
    entry.container:SetHeight(math.max(height or 1, 1))
    cache[id] = entry
    return entry
end

-- Search borrows matching rows from module pages and puts them back afterwards.
local search = { rows = {} }

local function ReturnSearchRows()
    for _, row in ipairs(search.rows) do
        row:SetParent(row.home)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -row.homeY)
    end
    wipe(search.rows)
end

local function ShowSearch(query)
    search.container = search.container or NewContainer()
    local c = search.container
    if not search.title then
        search.title = ns.Theme:Text(c, 14)
        search.title:SetPoint("TOPLEFT")
    end
    query = query:lower()
    local y = 26
    for _, M in ns.Modules:Iterate() do
        local entry = (M.profileKey or M.options) and Build(M.name)
        for _, row in ipairs(entry and entry.rows or {}) do
            local label = row.spec.label
            if row.spec.type ~= "Header" and type(label) == "string" and label:lower():find(query, 1, true) then
                row.home = entry.container
                row:SetParent(c)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 0, -y)
                row:Refresh()
                search.rows[#search.rows + 1] = row
                y = y + row:GetHeight() + ROW_GAP
            end
        end
    end
    search.title:SetText(#search.rows > 0 and (L["Search"] .. ": " .. query) or L["Nothing matches."])
    c:SetHeight(y)
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
    frame.scroll:SetVerticalScroll(0)
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
        if M.profileKey or M.options then
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
    local btn = T:Button(bar, "", SIDEBAR - 12, 24)
    T:Skin(btn, { 0, 0, 0, 0 }, { 0, 0, 0, 0 })
    btn:SetScript("OnEnter", nil) -- no accent border on sidebar entries
    btn:SetScript("OnLeave", nil)
    btn.label:ClearAllPoints()
    btn.label:SetPoint("LEFT", 14, 0)
    btn.mark = btn:CreateTexture(nil, "OVERLAY")
    btn.mark:SetPoint("TOPLEFT")
    btn.mark:SetPoint("BOTTOMLEFT")
    btn.mark:SetWidth(3)
    return btn
end

function Options:RefreshSidebar()
    local T, bar = ns.Theme, frame.sidebar
    for _, b in ipairs(bar.buttons) do b:Hide() end
    for _, h in ipairs(bar.headers) do h:Hide() end
    local byCat, y, nb, nh = Entries(), 10, 0, 0
    local r, g, b = T:Accent()
    local searching = frame.search:GetText() ~= ""
    for _, cat in ipairs(CATEGORIES) do
        local list = byCat[cat.key]
        if list and #list > 0 then
            nh = nh + 1
            local h = bar.headers[nh] or T:Text(bar, 11, T.colors.muted)
            bar.headers[nh] = h
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 14, -y)
            h:SetText(cat.label:upper())
            h:Show()
            y = y + 18
            for _, e in ipairs(list) do
                nb = nb + 1
                local btn = bar.buttons[nb] or SidebarButton(bar)
                bar.buttons[nb] = btn
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", 6, -y)
                btn:SetText(e.label)
                local selected = e.id == current and not searching
                btn.mark:SetColorTexture(r, g, b, 1)
                btn.mark:SetShown(selected)
                btn.label:SetTextColor(unpack(selected and T.colors.text or T.colors.muted))
                btn:SetScript("OnClick", function()
                    frame.search:SetText("")
                    Options:Show(e.id)
                end)
                btn:Show()
                y = y + 26
            end
            y = y + 10
        end
    end
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
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "OrionUIOptions")
    T:Skin(frame, T.colors.bg)

    local title = T:Text(frame, 16)
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(ns.NAME)
    local version = T:Text(frame, 11, T.colors.muted)
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
    version:SetText(ns.IS_DEV and "dev" or ns.VERSION)
    frame.accentLine = frame:CreateTexture(nil, "ARTWORK")
    frame.accentLine:SetHeight(1)
    frame.accentLine:SetPoint("TOPLEFT", 1, -44)
    frame.accentLine:SetPoint("TOPRIGHT", -1, -44)

    local close = T:Button(frame, "X", 24, 24)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() frame:Hide() end)

    local searchBox = CreateFrame("EditBox", nil, frame)
    searchBox:SetSize(220, 22)
    searchBox:SetPoint("RIGHT", close, "LEFT", -10, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetFont(T:Font(), 12, "")
    searchBox:SetTextInsets(8, 8, 0, 0)
    T:Skin(searchBox, T.colors.control)
    searchBox.placeholder = T:Text(searchBox, 12, T.colors.muted)
    searchBox.placeholder:SetPoint("LEFT", 8, 0)
    searchBox.placeholder:SetText(L["Search options"])
    searchBox:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "")
        if self.timer then self.timer:Cancel() end
        self.timer = C_Timer.NewTimer(0.2, function() Options:Show(current) end)
    end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
    frame.search = searchBox

    local sidebar = CreateFrame("Frame", nil, frame)
    sidebar:SetPoint("TOPLEFT", 1, -45)
    sidebar:SetPoint("BOTTOMLEFT", 1, 1)
    sidebar:SetWidth(SIDEBAR)
    T:Skin(sidebar, T.colors.panel, { 0, 0, 0, 0 })
    sidebar.buttons, sidebar.headers = {}, {}
    frame.sidebar = sidebar

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 20, -14)
    scroll:SetPoint("BOTTOMRIGHT", -30, 14)
    frame.contentWidth = WIDTH - SIDEBAR - 20 - 30 - 14
    frame.scroll = scroll

    frame:SetScript("OnShow", function() frame.accentLine:SetColorTexture(T:Accent()) end)
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
