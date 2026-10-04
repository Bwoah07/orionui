-- Loot history: a short feed of what you just looted ("+ [Item] x2", "+ 24g 61s") that fades out,
-- plus a window with this character's recent loot (/oui loothistory).
--
-- Where entries come from (checked in wow-ui-source, 2026-10-04; none of these are marked secret):
--   * Loot window: LOOT_OPENED caches every slot (GetLootSlotInfo / GetLootSlotLink), and
--     LOOT_SLOT_CLEARED for a cached slot means it went into your bags. Works with or without
--     OrionUI's own loot window and with auto loot.
--   * Money: PLAYER_MONEY gains while loot is open (or just after it closes, auto loot) are
--     looted money. Other gains (vendor, quests, mail) are left out on purpose.
--   * Loot that skips the window: SHOW_LOOT_TOAST (personal boss loot, chests) and
--     LOOT_ITEM_ROLL_WON (rolls you won). The same link twice within a few seconds counts once.
-- No chat parsing: chat text can be secret in restricted content.
local _, ns = ...

local L = ns.L
local S = ns.Schema
local Theme = ns.Theme

local GetTime, time = GetTime, time
local floor, max = math.floor, math.max

local LINE_H = 20
local DEDUPE = 4 -- seconds
local MONEY_AFTER_CLOSE = 1.5

local MIN_QUALITY = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4 }

local M = ns.Modules:New("LootHistory", {
    category = "qol", label = L["Loot history"], order = 7,
    desc = L["A short feed of what you loot, and a list of this character's recent loot. Open the list with /oui loothistory."],
    profileKey = "layout",
    schema = S.Table{ fields = {
        -- Feed
        feed = S.Bool{ section = L["Feed"], default = true, label = L["Show looted items as a short feed"], order = 1 },
        feedDuration = S.Number{ section = L["Feed"], default = 6, min = 2, max = 30, step = 1, label = L["Seconds each line stays"], order = 2 },
        feedLines = S.Number{ section = L["Feed"], default = 6, min = 1, max = 12, step = 1, label = L["Lines at most"], order = 3 },
        feedWidth = S.Number{ section = L["Feed"], default = 300, min = 160, max = 500, step = 2, label = L["Width"], order = 4 },
        fontSize = S.Number{ section = L["Feed"], default = 12, min = 8, max = 18, step = 1, label = L["Text size"], order = 5 },
        feedGrowUp = S.Bool{ section = L["Feed"], default = true, label = L["New lines at the bottom, older ones move up"], order = 6 },
        -- What counts
        minQuality = S.Enum{ section = L["What it shows"], default = "poor", values = { "poor", "common", "uncommon", "rare", "epic" },
            valueLabels = { poor = L["Everything"], common = L["Common and better"], uncommon = L["Uncommon and better"],
                rare = L["Rare and better"], epic = L["Epic and better"] },
            label = L["Items"], order = 10 },
        money = S.Bool{ section = L["What it shows"], default = true, label = L["Money"], order = 11 },
        currency = S.Bool{ section = L["What it shows"], default = true, label = L["Currencies"], order = 12 },
        keep = S.Number{ section = L["What it shows"], default = 300, min = 50, max = 1000, step = 50, label = L["Entries kept in the list"], order = 13 },
    } },
    options = function(self)
        return {
            { type = "Header", label = L["History"] },
            { type = "Button", label = L["Open loot history"], style = "accent", func = function() self:ToggleWindow(true) end },
            { type = "Button", label = L["Preview feed"], func = function() self:Preview() end },
        }
    end,
})

local cache = {}        -- loot slot -> entry, while loot is open
local lootOpen, closedAt = false, 0
local lastMoney
local recent = {}       -- link -> GetTime() of the last entry, for dedupe
local sessionMoney = 0
local feedAnchor, feedLines = nil, {}
local activeLines = {}
local win
local editing = false

---------------------------------------------------------------------------
-- Entries
---------------------------------------------------------------------------

local function Plain(v, fallback) return ns.Secret.Plain(v, fallback) end

local function History()
    local char = ns.DB.char
    char.lootHistory = char.lootHistory or {}
    return char.lootHistory
end

local function QualityColor(q)
    q = Plain(q, 1)
    if type(q) ~= "number" then q = 1 end
    local data = ColorManager and ColorManager.GetColorDataForItemQuality and ColorManager.GetColorDataForItemQuality(q)
    if data then
        if data.color then return data.color:GetRGB() end
        if data.r then return data.r, data.g, data.b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function MoneyText(copper, size)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper, size or 12)
    end
    return GetMoneyString(copper)
end

-- Fills icon / quality / kind from a link (item or currency).
local function FromLink(link, count)
    if type(link) ~= "string" or ns.Secret.Is(link) then return nil end
    local e = { link = link, count = count or 1, kind = "item" }
    if link:find("|Hcurrency:") then
        e.kind = "currency"
        local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
        if info then e.icon, e.quality, e.name = info.iconFileID, info.quality, info.name end
    else
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
        e.icon = icon
        e.quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
    end
    return e
end

local function Wanted(e)
    local db = M.db
    if e.kind == "money" then return db.money end
    if e.kind == "currency" then return db.currency end
    return (Plain(e.quality, 1) or 1) >= (MIN_QUALITY[db.minQuality] or 0)
end

function M:Add(e, silent)
    if not e then return end
    if e.link then
        local now = GetTime()
        if recent[e.link] and now - recent[e.link] < DEDUPE then return end
        recent[e.link] = now
    end
    if e.kind == "money" then sessionMoney = sessionMoney + e.copper end
    e.t = time()
    local list = History()
    list[#list + 1] = e
    local keep = self.db.keep
    while #list > keep do table.remove(list, 1) end
    if not silent and Wanted(e) then self:Feed(e) end
    if win and win:IsShown() then self:FillWindow() end
end

---------------------------------------------------------------------------
-- Capture
---------------------------------------------------------------------------

local function CacheSlot(slot)
    cache[slot] = nil
    local slotType = GetLootSlotType(slot)
    if slotType ~= Enum.LootSlotType.Item and slotType ~= Enum.LootSlotType.Currency then return end -- money goes by PLAYER_MONEY
    local texture, name, quantity, _, quality = GetLootSlotInfo(slot)
    if ns.Secret.Is(name) or not name then return end
    local link = Plain(GetLootSlotLink(slot), nil)
    cache[slot] = {
        kind = slotType == Enum.LootSlotType.Currency and "currency" or "item",
        link = link, name = name, icon = Plain(texture, nil), quality = Plain(quality, 1), count = Plain(quantity, 1),
    }
end

local function OnLootOpened()
    lootOpen = true
    wipe(cache)
    for slot = 1, GetNumLootItems() do CacheSlot(slot) end
end

local function OnSlotChanged(_, _, slot) if lootOpen then CacheSlot(slot) end end

local function OnSlotCleared(_, _, slot)
    local e = cache[slot]
    cache[slot] = nil
    if e then M:Add(e) end
end

local function OnLootClosed()
    lootOpen = false
    closedAt = GetTime()
    wipe(cache)
end

local function OnMoney()
    local now = GetMoney()
    local delta = lastMoney and (now - lastMoney) or 0
    lastMoney = now
    if delta > 0 and (lootOpen or GetTime() - closedAt < MONEY_AFTER_CLOSE) then
        M:Add({ kind = "money", copper = delta })
    end
end

local function OnLootToast(_, _, typeIdentifier, link, quantity)
    if typeIdentifier == "item" or typeIdentifier == "currency" then
        M:Add(FromLink(link, Plain(quantity, 1)))
    elseif typeIdentifier == "money" and not lootOpen then
        -- Already counted by PLAYER_MONEY when it arrives through an open loot window.
        local copper = Plain(quantity, 0)
        if type(copper) == "number" and copper > 0 then M:Add({ kind = "money", copper = copper }) end
    end
end

local function OnRollWon(_, _, link, quantity)
    M:Add(FromLink(link, Plain(quantity, 1)))
end

---------------------------------------------------------------------------
-- Feed
---------------------------------------------------------------------------

local function EntryText(e, size)
    local count = Plain(e.count, 1)
    local suffix = (type(count) == "number" and count > 1) and (" x" .. count) or ""
    if e.kind == "money" then return MoneyText(e.copper, size) end
    if e.link then return e.link .. suffix end
    local r, g, b = QualityColor(e.quality)
    return string.format("|cff%02x%02x%02x%s|r%s", floor(r * 255), floor(g * 255), floor(b * 255), e.name or "?", suffix)
end

local function EntryIcon(e)
    if e.kind == "money" then return 133784 end -- coin pile
    return e.icon or 134400 -- question mark
end

local function NewLine()
    local line = CreateFrame("Frame", nil, feedAnchor)
    line.bg = line:CreateTexture(nil, "BACKGROUND")
    line.bg:SetAllPoints()
    line.bg:SetColorTexture(1, 1, 1, 1)
    line.bg:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.7), CreateColor(0, 0, 0, 0))
    line.strip = line:CreateTexture(nil, "BORDER")
    line.strip:SetPoint("TOPLEFT")
    line.strip:SetPoint("BOTTOMLEFT")
    line.strip:SetWidth(2)
    line.iconBox = CreateFrame("Frame", nil, line)
    line.iconBox:SetSize(LINE_H - 2, LINE_H - 2)
    line.iconBox:SetPoint("LEFT", 5, 0)
    Theme:Skin(line.iconBox, { 0, 0, 0, 1 }, Theme.colors.border)
    line.icon = line.iconBox:CreateTexture(nil, "ARTWORK")
    line.icon:SetPoint("TOPLEFT", 1, -1)
    line.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    line.plus = line:CreateFontString(nil, "OVERLAY")
    line.plus:SetPoint("LEFT", line.iconBox, "RIGHT", 5, 0)
    line.text = line:CreateFontString(nil, "OVERLAY")
    line.text:SetPoint("LEFT", line.plus, "RIGHT", 3, 0)
    line.text:SetPoint("RIGHT", -4, 0)
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(false)
    line.anim = line:CreateAnimationGroup()
    local fadeIn = line.anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.15); fadeIn:SetOrder(1)
    line.fadeOut = line:CreateAnimationGroup()
    local out = line.fadeOut:CreateAnimation("Alpha")
    out:SetFromAlpha(1); out:SetToAlpha(0); out:SetDuration(0.6)
    line.fadeOut:SetScript("OnFinished", function() M:RemoveLine(line) end)
    return line
end

local function GetLine()
    for _, line in ipairs(feedLines) do
        if not line.inUse then return line end
    end
    local line = NewLine()
    feedLines[#feedLines + 1] = line
    return line
end

function M:LayoutFeed()
    local db = self.db
    feedAnchor:SetSize(db.feedWidth, LINE_H)
    local n = #activeLines
    for i, line in ipairs(activeLines) do
        line:ClearAllPoints()
        line:SetSize(db.feedWidth, LINE_H)
        -- activeLines is oldest first; the newest sits on the anchor.
        local fromNewest = n - i
        if db.feedGrowUp then
            line:SetPoint("BOTTOMLEFT", feedAnchor, "BOTTOMLEFT", 0, fromNewest * (LINE_H + 2))
        else
            line:SetPoint("TOPLEFT", feedAnchor, "TOPLEFT", 0, -fromNewest * (LINE_H + 2))
        end
    end
end

function M:RemoveLine(line)
    if line.timer then line.timer:Cancel(); line.timer = nil end
    line.fadeOut:Stop()
    line:Hide()
    line.inUse = false
    for i, l in ipairs(activeLines) do
        if l == line then table.remove(activeLines, i) break end
    end
    self:LayoutFeed()
end

function M:Feed(e, sticky)
    local db = self.db
    if not db.feed or not feedAnchor then return end
    while #activeLines >= db.feedLines do self:RemoveLine(activeLines[1]) end
    local line = GetLine()
    line.inUse = true
    local font = Theme:Font()
    line.plus:SetFont(font, db.fontSize, "OUTLINE")
    line.text:SetFont(font, db.fontSize, "OUTLINE")
    local r, g, b = QualityColor(e.kind == "money" and 1 or e.quality)
    if e.kind == "money" then r, g, b = 1, 0.85, 0.35 end
    line.plus:SetText("+")
    line.plus:SetTextColor(Theme:Accent())
    line.text:SetText(EntryText(e, db.fontSize))
    line.icon:SetTexture(EntryIcon(e))
    Theme:SetBorderColor(line.iconBox, r, g, b, 1)
    line.strip:SetColorTexture(r, g, b, 1)
    activeLines[#activeLines + 1] = line
    self:LayoutFeed()
    line:SetAlpha(1)
    line:Show()
    line.anim:Play()
    if not sticky then
        line.timer = C_Timer.NewTimer(db.feedDuration, function()
            line.timer = nil
            line.fadeOut:Play()
        end)
    end
end

local FAKE = {
    { kind = "item", name = "Starforged Cleaver of Orion", quality = 4, icon = 135349 },
    { kind = "item", name = "Shimmering Riftdust", quality = 2, icon = 134939, count = 14 },
    { kind = "currency", name = "Valorstones", quality = 3, icon = 5868902, count = 25 },
    { kind = "money", copper = 246135 },
}

local function ClearFeed()
    for i = #activeLines, 1, -1 do M:RemoveLine(activeLines[i]) end
end

function M:Preview(sticky)
    if not feedAnchor then return end
    ClearFeed()
    for _, e in ipairs(FAKE) do self:Feed(e, sticky) end
end

---------------------------------------------------------------------------
-- History window
---------------------------------------------------------------------------

local ROW_H = 24
local rowPool = {}

local function RowOnEnter(row)
    row.hl:Show()
    if row.link then
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(row.link)
        GameTooltip:Show()
    end
end

local function RowOnLeave(row)
    row.hl:Hide()
    GameTooltip:Hide()
end

local function HistoryRow(i)
    local row = rowPool[i]
    if row then return row end
    row = CreateFrame("Button", nil, win.list)
    row:SetHeight(ROW_H)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.05)
    row.hl:Hide()
    row.time = Theme:Text(row, 10, Theme.colors.faint)
    row.time:SetPoint("LEFT", 4, 0)
    row.time:SetWidth(52)
    row.iconBox = CreateFrame("Frame", nil, row)
    row.iconBox:SetSize(ROW_H - 4, ROW_H - 4)
    row.iconBox:SetPoint("LEFT", 58, 0)
    Theme:Skin(row.iconBox, { 0, 0, 0, 1 }, Theme.colors.border)
    row.icon = row.iconBox:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.text = Theme:Text(row, 12)
    row.text:SetPoint("LEFT", row.iconBox, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetWordWrap(false)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick() then HandleModifiedItemClick(self.link) end
    end)
    rowPool[i] = row
    return row
end

local function DayKey(t) return date("%Y-%m-%d", t) end

function M:FillWindow()
    local list = History()
    local today = DayKey(time())
    local n = 0
    for i = #list, 1, -1 do -- newest first
        local e = list[i]
        n = n + 1
        local row = HistoryRow(n)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -(n - 1) * ROW_H)
        row:SetPoint("RIGHT", win.list, "RIGHT", 0, 0)
        row.time:SetText(date(DayKey(e.t) == today and "%H:%M" or "%d.%m", e.t))
        row.icon:SetTexture(EntryIcon(e))
        local r, g, b = QualityColor(e.kind == "money" and 1 or e.quality)
        if e.kind == "money" then r, g, b = 1, 0.85, 0.35 end
        Theme:SetBorderColor(row.iconBox, r, g, b, 1)
        row.text:SetText(EntryText(e, 12))
        row.link = e.link
        row:Show()
    end
    for i = n + 1, #rowPool do rowPool[i]:Hide() end
    win.list:SetHeight(max(1, n * ROW_H))
    win.empty:SetShown(n == 0)
    win.scroll:UpdateThumb()
    win.total:SetText(L["Money looted this session: "] .. MoneyText(sessionMoney, 11))
end

local function EnsureWindow()
    if win then return end
    win = CreateFrame("Frame", "OrionUILootHistory", UIParent) -- global name: Esc closes via UISpecialFrames
    win:SetSize(420, 460)
    win:SetPoint("CENTER", 260, 0)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    tinsert(UISpecialFrames, "OrionUILootHistory")
    Theme:Skin(win, Theme.colors.bg, Theme.colors.border)
    Theme:Shadow(win)

    local r, g, b = Theme:Accent()
    win.title = Theme:Text(win, 14)
    win.title:SetPoint("TOPLEFT", 12, -10)
    win.title:SetTextColor(r, g, b)
    win.title:SetText(L["Loot history"])
    win.hint = Theme:Text(win, 10, Theme.colors.muted)
    win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -3)
    win.hint:SetText(L["This character, newest first. Shift-click an item to link it."])
    local close = Theme:TextButton(win, "x", 16)
    close:SetPoint("TOPRIGHT", -8, -6)
    close:SetScript("OnClick", function() win:Hide() end)
    local line = win:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", 1, -46)
    line:SetPoint("TOPRIGHT", -1, -46)
    line:SetHeight(1)
    line:SetColorTexture(r, g, b, 0.8)

    win.scroll = Theme:Scroll(win)
    win.scroll:SetPoint("TOPLEFT", 8, -52)
    win.scroll:SetPoint("BOTTOMRIGHT", -20, 40)
    win.list = CreateFrame("Frame", nil, win.scroll)
    win.list:SetWidth(392)
    win.list:SetHeight(1)
    win.scroll:SetScrollChild(win.list)
    win.scroll:SetScript("OnSizeChanged", function(self, w)
        win.list:SetWidth(w)
        self:UpdateThumb()
    end)
    win.empty = Theme:Text(win, 12, Theme.colors.muted)
    win.empty:SetPoint("TOP", 0, -80)
    win.empty:SetText(L["Nothing looted yet."])

    win.total = Theme:Text(win, 11, Theme.colors.muted)
    win.total:SetPoint("BOTTOMLEFT", 12, 14)
    local clear = Theme:Button(win, L["Clear"], 70, 20)
    clear:SetPoint("BOTTOMRIGHT", -10, 10)
    clear:SetScript("OnClick", function()
        wipe(History())
        sessionMoney = 0
        M:FillWindow()
    end)
end

function M:ToggleWindow(show)
    EnsureWindow()
    if show == nil then show = not win:IsShown() end
    if show then
        win:Show()
        self:FillWindow()
        win.scroll:ScrollTo(0)
    else
        win:Hide()
    end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function M:Refresh()
    if not feedAnchor then return end
    for _, line in ipairs(activeLines) do
        line.plus:SetFont(Theme:Font(), self.db.fontSize, "OUTLINE")
        line.text:SetFont(Theme:Font(), self.db.fontSize, "OUTLINE")
    end
    self:LayoutFeed()
    local list = History()
    while #list > self.db.keep do table.remove(list, 1) end
end

function M:OnEnable()
    if not feedAnchor then
        feedAnchor = CreateFrame("Frame", nil, UIParent)
        feedAnchor:SetSize(self.db.feedWidth, LINE_H)
        feedAnchor:SetFrameStrata("MEDIUM")
        ns.Movers:Register("LootFeed", { label = L["Loot feed"], getFrame = function() return feedAnchor end, default = { x = 420, y = -160 } })
    end
    lastMoney = GetMoney()
    ns.Events:On("LOOT_OPENED", self, OnLootOpened)
    ns.Events:On("LOOT_SLOT_CHANGED", self, OnSlotChanged)
    ns.Events:On("LOOT_SLOT_CLEARED", self, OnSlotCleared)
    ns.Events:On("LOOT_CLOSED", self, OnLootClosed)
    ns.Events:On("PLAYER_MONEY", self, OnMoney)
    ns.Events:On("SHOW_LOOT_TOAST", self, OnLootToast)
    ns.Events:On("LOOT_ITEM_ROLL_WON", self, OnRollWon)
    ns.Events:On("OUI_EDIT_MODE", self, function(_, _, shown)
        editing = shown and true or false
        ClearFeed()
        if editing then self:Preview(true) end
    end)
    self:Refresh()
end

function M:OnDisable()
    editing, lootOpen = false, false
    wipe(cache)
    if feedAnchor then ClearFeed() end
    if win then win:Hide() end
end

ns.Slash:Register("loothistory", function() M:ToggleWindow() end, "show this character's recent loot")
