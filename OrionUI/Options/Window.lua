-- The options window (CLAUDE.md §9.1): sidebar grouped by category, pages built from
-- module schemas, hand-written pages for complex editors, and a search box across all
-- option labels. Pages are laid out as a title plus cards of "label | control" rows.
-- Created lazily on first open.
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
local WIDTH, HEIGHT, SIDEBAR, TITLEBAR = 900, 600, 200, 52
local PAD, CARD_GAP = 16, 20

local frame, current

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
            local h = T:Text(container, 11, T.colors.muted)
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
    btn:SetSize(SIDEBAR - 16, 28)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.mark = btn:CreateTexture(nil, "ARTWORK")
    btn.mark:SetPoint("TOPLEFT")
    btn.mark:SetPoint("BOTTOMLEFT")
    btn.mark:SetWidth(2)
    btn.label = T:Text(btn, 13)
    btn.label:SetPoint("LEFT", 14, 0)
    btn:SetScript("OnEnter", function(self) if not self.selected then self.bg:SetColorTexture(1, 1, 1, 0.04) end end)
    btn:SetScript("OnLeave", function(self) if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end end)
    return btn
end

function Options:RefreshSidebar()
    local T, bar = ns.Theme, frame.sidebar
    for _, b in ipairs(bar.buttons) do b:Hide() end
    for _, h in ipairs(bar.headers) do h:Hide() end
    local byCat, y, nb, nh = Entries(), 14, 0, 0
    local r, g, b = T:Accent()
    local searching = frame.search:GetText() ~= ""
    for _, cat in ipairs(CATEGORIES) do
        local list = byCat[cat.key]
        if list and #list > 0 then
            -- A category holding one page of the same name needs no heading.
            if not (#list == 1 and list[1].label == cat.label) then
                nh = nh + 1
                local h = bar.headers[nh] or T:Text(bar, 10, T.colors.faint)
                bar.headers[nh] = h
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", 22, -y)
                h:SetText(cat.label:upper())
                h:Show()
                y = y + 20
            end
            for _, e in ipairs(list) do
                nb = nb + 1
                local btn = bar.buttons[nb] or SidebarButton(bar)
                bar.buttons[nb] = btn
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", 8, -y)
                btn.label:SetText(e.label)
                btn.selected = e.id == current and not searching
                btn.mark:SetColorTexture(r, g, b, 1)
                btn.mark:SetShown(btn.selected)
                if btn.selected then
                    btn.bg:SetColorTexture(r, g, b, 0.12)
                    btn.label:SetTextColor(unpack(T.colors.text))
                else
                    btn.bg:SetColorTexture(0, 0, 0, 0)
                    btn.label:SetTextColor(unpack(T.colors.muted))
                end
                btn:SetScript("OnClick", function()
                    frame.search:SetText("")
                    Options:Show(e.id)
                end)
                btn:Show()
                y = y + 30
            end
            y = y + 14
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

    local searchBox = CreateFrame("EditBox", nil, titleBar)
    searchBox:SetSize(240, 26)
    searchBox:SetPoint("RIGHT", close, "LEFT", -12, -1)
    searchBox:SetAutoFocus(false)
    searchBox:SetFont(T:Font(), 12, "")
    searchBox:SetTextInsets(10, 10, 0, 0)
    T:Skin(searchBox, T.colors.sidebar)
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
    sidebar.buttons, sidebar.headers = {}, {}
    frame.sidebar = sidebar

    -- Content
    local scroll = T:Scroll(frame)
    scroll:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 28, -24)
    scroll:SetPoint("BOTTOMRIGHT", -30, 20)
    frame.contentWidth = WIDTH - SIDEBAR - 28 - 30 - 2
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
