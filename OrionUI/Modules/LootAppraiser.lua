-- Loot appraiser: a window (/oui appraiser, /oui la) with everything looted since the last reset,
-- what it is worth on your realm's auction house, gold looted, and gold per hour (Stig, 2026-10-05).
-- Three layouts (Stig, same day): Classic (list on top, labelled totals under it, in the spirit of
-- the old Loot Appraiser addon; our own layout and code), Compact (only the totals, small enough to
-- sit in a corner) and Cards (stat boxes plus a big list). Escape never closes it.
--
-- Loot comes from Loot history's OUI_LOOT_ITEM / OUI_LOOT_MONEY messages (Modules/LootHistory.lua),
-- so Loot history has to be on. Prices come from ns.LootPrices: TSM / Auctionator when installed,
-- the vendor price otherwise (shown grey). Prices are read when the window paints, not stored, so
-- they always follow the latest scan. The session lives in OrionUICharDB and survives reloads.
local _, ns = ...

local L = ns.L
local S = ns.Schema
local Theme = ns.Theme

local time = time
local floor, max = math.floor, math.max

local CARD_ROW_H, SMALL_ROW_H, LINE_H = 26, 18, 17
local SIZES = {
    cards   = { w = 480, h = 520 },
    classic = { w = 340, h = 440 },
    compact = { w = 230 },
}

local M = ns.Modules:New("LootAppraiser", {
    category = "loot", label = L["Loot appraiser"], order = 8,
    desc = L["A window with everything you looted since the last reset and what it is worth on the auction house. Open it with /oui appraiser (or /oui la). Needs Loot history on; prices from TradeSkillMaster or Auctionator."],
    profileKey = "layout",
    schema = S.Table{ fields = {
        -- Look
        layout = S.Enum{ section = L["Look"], default = "classic", values = { "classic", "compact", "cards" },
            valueLabels = { classic = L["Classic: list with totals under it"], compact = L["Compact: totals only"],
                cards = L["Cards: big list with stat boxes"] },
            label = L["Layout"], order = 0 },
        theme = S.Enum{ section = L["Look"], default = "orion", values = { "orion", "gold", "midnight", "emerald", "glass" },
            valueLabels = { orion = L["OrionUI (dark, blue)"], gold = L["Gold"], midnight = L["Midnight (navy, violet)"],
                emerald = L["Emerald"], glass = L["Glass (see-through, white)"] },
            label = L["Theme"], order = 1 },
        opacity = S.Number{ section = L["Look"], default = 0.95, min = 0.2, max = 1, step = 0.05, label = L["Background opacity"], order = 2 },
        scale = S.Number{ section = L["Look"], default = 1, min = 0.6, max = 1.6, step = 0.05, label = L["Window scale"], order = 3 },
        lock = S.Bool{ section = L["Look"], default = false, label = L["Lock the window in place"], order = 4 },
        -- List
        minValue = S.Number{ section = L["List"], default = 0, min = 0, max = 10000, step = 5, label = L["Only list items worth at least (gold, 0 = all)"], order = 10,
            desc = L["Value of the whole stack. Hidden items still count in the totals."] },
        hideJunk = S.Bool{ section = L["List"], default = false, label = L["Leave grey items out of the list"], order = 11 },
    } },
    options = function(self)
        return {
            { type = "Header", label = L["Window"] },
            { type = "Button", label = L["Open loot appraiser"], style = "accent", func = function() self:Toggle(true) end },
        }
    end,
})

local win
local cardRows, smallRows = {}, {}
local ticker
local loading, pendingClose = false, false

local function P() return ns.LootPrices end

-- Themes: background, stat boxes, border, accent (nil = OrionUI's accent). Opacity scales the
-- background and the boxes.
local THEMES = {
    orion    = { bg = { 0.067, 0.067, 0.082 }, card = { 0.094, 0.094, 0.114 }, border = { 0, 0, 0 } },
    gold     = { bg = { 0.07, 0.06, 0.04 }, card = { 0.11, 0.095, 0.06 }, border = { 0.28, 0.22, 0.08 }, accent = { 1, 0.78, 0.3 } },
    midnight = { bg = { 0.04, 0.05, 0.10 }, card = { 0.07, 0.08, 0.16 }, border = { 0.13, 0.15, 0.3 }, accent = { 0.6, 0.5, 1 } },
    emerald  = { bg = { 0.035, 0.07, 0.055 }, card = { 0.055, 0.11, 0.085 }, border = { 0.08, 0.22, 0.15 }, accent = { 0.3, 0.88, 0.58 } },
    glass    = { bg = { 0, 0, 0 }, card = { 1, 1, 1 }, cardAlpha = 0.05, bgAlpha = 0.55, border = { 1, 1, 1, 0.1 }, accent = { 1, 1, 1 } },
}

local function ThemeData()
    local t = THEMES[M.db.theme] or THEMES.orion
    local ar, ag, ab
    if t.accent then ar, ag, ab = t.accent[1], t.accent[2], t.accent[3] else ar, ag, ab = Theme:Accent() end
    return t, ar, ag, ab
end

local function Layout() return SIZES[M.db.layout] and M.db.layout or "classic" end

-- Window state per character, kept apart from the session so Reset doesn't move the window.
local function WinState()
    local char = ns.DB.char
    char.lootAppraiserWindow = char.lootAppraiserWindow or {}
    return char.lootAppraiserWindow
end

local function Session()
    local char = ns.DB.char
    local s = char.lootAppraiser
    if not s then
        s = { started = time(), money = 0, items = {}, seq = 0 }
        char.lootAppraiser = s
    end
    return s
end

local function Duration(seconds)
    seconds = max(0, seconds)
    local h, m = floor(seconds / 3600), floor(seconds % 3600 / 60)
    if h > 0 then return string.format(L["%dh %02dm"], h, m) end
    return string.format(L["%dm"], m)
end

local function NoBrackets(link) return (link:gsub("|h%[(.-)%]|h", "|h%1|h")) end

---------------------------------------------------------------------------
-- Recording
---------------------------------------------------------------------------

local function OnItem(_, _, link, count)
    if type(link) ~= "string" then return end
    local itemID = C_Item.GetItemInfoInstant(link)
    local key = itemID or link
    local s = Session()
    s.seq = (s.seq or 0) + 1
    local e = s.items[key]
    if e then
        e.count = e.count + (count or 1)
        e.last = s.seq
    else
        s.items[key] = { link = link, count = count or 1, last = s.seq }
    end
    if win and win:IsShown() then M:Fill() end
end

local function OnMoney(_, _, copper)
    if type(copper) ~= "number" then return end
    local s = Session()
    s.money = s.money + copper
    if win and win:IsShown() then M:Fill() end
end

function M:Reset()
    ns.DB.char.lootAppraiser = nil
    if win and win:IsShown() then self:Fill() end
end

---------------------------------------------------------------------------
-- Pieces
---------------------------------------------------------------------------

local function ItemTooltip(owner, link, qty)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link)
    local prices = P().All(link)
    if #prices > 0 then
        local _, r, g, b = ThemeData()
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["%s value (x%d)"], ns.NAME, qty), r, g, b)
        for _, p in ipairs(prices) do
            GameTooltip:AddDoubleLine(p.label, P().MoneyText(p.copper * qty, 12) .. "  |cff8a8a99("
                .. P().MoneyText(p.copper, 10) .. ")|r", 0.8, 0.8, 0.85, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function RowOnEnter(row)
    row.hl:Show()
    if row.link then ItemTooltip(row, row.link, row.qty) end
end

local function RowOnLeave(row)
    row.hl:Hide()
    GameTooltip:Hide()
end

local function RowOnClick(row)
    if row.link and IsModifiedClick() then HandleModifiedItemClick(row.link) end
end

local function IconBox(parent, size)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(size, size)
    Theme:Skin(box, { 0, 0, 0, 1 }, Theme.colors.border)
    box.tex = box:CreateTexture(nil, "ARTWORK")
    box.tex:SetPoint("TOPLEFT", 1, -1)
    box.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    box.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return box
end

local function BaseRow(height, zebra)
    local row = CreateFrame("Button", nil, win.list)
    row:SetHeight(height)
    if zebra then
        local z = row:CreateTexture(nil, "BACKGROUND")
        z:SetAllPoints()
        z:SetColorTexture(1, 1, 1, 0.025)
    end
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.06)
    row.hl:Hide()
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:SetScript("OnClick", RowOnClick)
    return row
end

-- Cards layout: icon, name, x12, unit price, stack value.
local function CardRow(i)
    local row = cardRows[i]
    if row then return row end
    row = BaseRow(CARD_ROW_H, i % 2 == 0)
    row.iconBox = IconBox(row, CARD_ROW_H - 6)
    row.iconBox:SetPoint("LEFT", 4, 0)
    row.total = Theme:Text(row, 12)
    row.total:SetPoint("RIGHT", -6, 0)
    row.total:SetJustifyH("RIGHT")
    row.total:SetWidth(96)
    row.unit = Theme:Text(row, 10, Theme.colors.muted)
    row.unit:SetPoint("RIGHT", row.total, "LEFT", -6, 0)
    row.unit:SetJustifyH("RIGHT")
    row.unit:SetWidth(84)
    row.count = Theme:Text(row, 11, Theme.colors.muted)
    row.count:SetPoint("RIGHT", row.unit, "LEFT", -6, 0)
    row.count:SetJustifyH("RIGHT")
    row.count:SetWidth(40)
    row.name = Theme:Text(row, 12)
    row.name:SetPoint("LEFT", row.iconBox, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
    row.name:SetWordWrap(false)
    cardRows[i] = row
    return row
end

-- Classic layout: small icon, "12x Name", stack value on the right.
local function SmallRow(i)
    local row = smallRows[i]
    if row then return row end
    row = BaseRow(SMALL_ROW_H, i % 2 == 0)
    row.iconBox = IconBox(row, SMALL_ROW_H - 4)
    row.iconBox:SetPoint("LEFT", 2, 0)
    row.total = Theme:Text(row, 11)
    row.total:SetPoint("RIGHT", -4, 0)
    row.total:SetJustifyH("RIGHT")
    row.total:SetWidth(84)
    row.name = Theme:Text(row, 11)
    row.name:SetPoint("LEFT", row.iconBox, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.total, "LEFT", -4, 0)
    row.name:SetWordWrap(false)
    smallRows[i] = row
    return row
end

local function StatBox(parent, label)
    local box = CreateFrame("Frame", nil, parent)
    Theme:Skin(box, Theme.colors.card, Theme.colors.border)
    box.label = Theme:Text(box, 10, Theme.colors.muted)
    box.label:SetPoint("TOPLEFT", 8, -7)
    box.label:SetText(label)
    box.value = Theme:Text(box, 14)
    box.value:SetPoint("BOTTOMLEFT", 8, 7)
    box.value:SetPoint("RIGHT", -6, 0)
    box.value:SetWordWrap(false)
    return box
end

-- A block of "label ........ value" lines (Classic and Compact).
local SUMMARY = {
    classic = { "time", "money", "items", "vendor", "total", "hour", "count" },
    compact = { "time", "money", "items", "total", "hour" },
}
local SUMMARY_LABELS = {
    time = L["Session"], money = L["Gold looted"], items = L["Item value (AH)"], vendor = L["Vendor value"],
    total = L["Total"], hour = L["Per hour"], count = L["Items looted"],
}

local function SummaryLine(key)
    local line = win.summary[key]
    if line then return line end
    line = CreateFrame("Frame", nil, win)
    line:SetHeight(LINE_H)
    line.label = Theme:Text(line, 11, Theme.colors.muted)
    line.label:SetPoint("LEFT", 0, 0)
    line.label:SetText(SUMMARY_LABELS[key])
    line.value = Theme:Text(line, 12)
    line.value:SetPoint("RIGHT", 0, 0)
    line.value:SetJustifyH("RIGHT")
    win.summary[key] = line
    return line
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

-- Prices are looked up now, so the list follows the latest TSM / Auctionator data.
-- Returns the shown list plus totals over everything (hidden rows still count in the totals).
local function Entries(order)
    local s, list = Session(), {}
    local ah, vendorTotal, hidden, count = 0, 0, 0, 0
    local minCopper = M.db.minValue * 10000
    for _, e in pairs(s.items) do
        local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(e.link)
        quality = ns.Secret.Plain(quality, 1) or 1
        local unit, vendor = P().Card(e.link)
        local total = (unit or 0) * e.count
        count = count + e.count
        if vendor then vendorTotal = vendorTotal + total else ah = ah + total end
        if (M.db.hideJunk and quality == 0) or total < minCopper then
            hidden = hidden + 1
        else
            list[#list + 1] = { link = e.link, count = e.count, quality = quality, unit = unit, vendor = vendor,
                total = total, last = e.last or 0 }
        end
    end
    if order == "recent" then
        table.sort(list, function(a, b) return a.last > b.last end)
    else
        table.sort(list, function(a, b)
            if a.total ~= b.total then return a.total > b.total end
            return a.count > b.count
        end)
    end
    return list, { ah = ah, vendor = vendorTotal, hidden = hidden, count = count }
end

local function Dash() return "|cff666670-|r" end

---------------------------------------------------------------------------
-- Painting
---------------------------------------------------------------------------

local function PaintCardRows(list)
    for i, e in ipairs(list) do
        local row = CardRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -(i - 1) * CARD_ROW_H)
        row:SetPoint("RIGHT", win.list, "RIGHT", 0, 0)
        row.link, row.qty = e.link, e.count
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(e.link)
        row.iconBox.tex:SetTexture(icon or 134400)
        Theme:SetBorderColor(row.iconBox, P().QualityColor(e.quality))
        row.name:SetText(NoBrackets(e.link))
        row.count:SetText("x" .. e.count)
        if e.unit then
            row.unit:SetText(P().MoneyText(e.unit, 10))
            row.total:SetText(P().MoneyText(e.total, 12))
            if e.vendor then row.total:SetTextColor(0.55, 0.55, 0.6) else row.total:SetTextColor(1, 1, 1) end
        else
            row.unit:SetText("")
            row.total:SetText(Dash())
        end
        row:Show()
    end
    for i = #list + 1, #cardRows do cardRows[i]:Hide() end
    return #list * CARD_ROW_H
end

local function PaintSmallRows(list)
    for i, e in ipairs(list) do
        local row = SmallRow(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -(i - 1) * SMALL_ROW_H)
        row:SetPoint("RIGHT", win.list, "RIGHT", 0, 0)
        row.link, row.qty = e.link, e.count
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(e.link)
        row.iconBox.tex:SetTexture(icon or 134400)
        Theme:SetBorderColor(row.iconBox, P().QualityColor(e.quality))
        row.name:SetText("|cff9a9aa5" .. e.count .. "x|r " .. NoBrackets(e.link))
        if e.unit then
            row.total:SetText(P().MoneyText(e.total, 11))
            if e.vendor then row.total:SetTextColor(0.55, 0.55, 0.6) else row.total:SetTextColor(1, 1, 1) end
        else
            row.total:SetText(Dash())
        end
        row:Show()
    end
    for i = #list + 1, #smallRows do smallRows[i]:Hide() end
    return #list * SMALL_ROW_H
end

function M:Fill()
    if not win then return end
    local layout = Layout()
    local s = Session()
    local list, t = Entries(layout == "classic" and "recent" or "value")
    local seconds = time() - s.started
    local total = s.money + t.ah + t.vendor
    local perHour = seconds >= 60 and floor(total * 3600 / seconds / 10000) * 10000 or nil

    if layout == "cards" then
        for _, row in ipairs(smallRows) do row:Hide() end
        win.list:SetHeight(max(1, PaintCardRows(list)))
        win.stats.money.value:SetText(P().MoneyText(s.money, 13))
        win.stats.items.value:SetText(P().MoneyText(t.ah, 13))
        win.stats.total.value:SetText(P().MoneyText(total, 13))
        win.stats.hour.value:SetText(perHour and P().MoneyText(perHour, 13) or Dash())
    elseif layout == "classic" then
        for _, row in ipairs(cardRows) do row:Hide() end
        win.list:SetHeight(max(1, PaintSmallRows(list)))
    else
        for _, row in ipairs(cardRows) do row:Hide() end
        for _, row in ipairs(smallRows) do row:Hide() end
    end

    if layout ~= "compact" then
        win.empty:SetShown(#list == 0)
        win.scroll:UpdateThumb()
    end

    if win.summaryShown then
        local values = {
            time = Duration(seconds),
            money = P().MoneyText(s.money, 12),
            items = P().MoneyText(t.ah, 12),
            vendor = P().MoneyText(t.vendor, 12),
            total = P().MoneyText(total, 12),
            hour = perHour and P().MoneyText(perHour, 12) or Dash(),
            count = tostring(t.count),
        }
        for key, line in pairs(win.summary) do line.value:SetText(values[key] or "") end
    end

    win.hint:SetText(string.format(L["Since %s · %s · prices: %s"], date("%d.%m %H:%M", s.started), Duration(seconds),
        P().SourceLabel()))
    local notes = {}
    if layout == "cards" and t.vendor > 0 then
        notes[#notes + 1] = string.format(L["Vendor value (grey, not in Item value): %s"], P().MoneyText(t.vendor, 11))
    end
    if t.hidden > 0 then notes[#notes + 1] = string.format(L["%d hidden by filters"], t.hidden) end
    win.note:SetText(table.concat(notes, "  ·  "))
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

-- Colours and opacity from the chosen theme.
function M:ApplyTheme()
    if not win then return end
    local t, r, g, b = ThemeData()
    local a = self.db.opacity
    local bgA = (t.bgAlpha or 1) * a
    local cardA = (t.cardAlpha or 1) * math.min(1, a + 0.05)
    Theme:Skin(win, { t.bg[1], t.bg[2], t.bg[3], bgA }, t.border)
    for _, box in pairs(win.stats) do Theme:Skin(box, { t.card[1], t.card[2], t.card[3], cardA }, t.border) end
    win.title:SetTextColor(r, g, b)
    win.stats.total.value:SetTextColor(r, g, b)
    if win.summary.total then win.summary.total.value:SetTextColor(r, g, b) end
    win.line:SetColorTexture(r, g, b, 0.8)
    win.line2:SetColorTexture(r, g, b, 0.35)
    win:SetMovable(not self.db.lock)
end

-- Places every piece for the chosen layout and hides the rest.
function M:ApplyLayout()
    if not win then return end
    local layout = Layout()
    local size = SIZES[layout]
    local compact = layout == "compact"
    local cards = layout == "cards"

    win.title:ClearAllPoints()
    win.title:SetPoint("TOPLEFT", compact and 10 or 14, compact and -8 or -12)
    win.title:SetFont(Theme:Font(), compact and 12 or 15, "")
    win.close:ClearAllPoints()
    win.close:SetPoint("TOPRIGHT", compact and -2 or -8, compact and -2 or -8)
    win.hint:SetShown(not compact)

    for _, box in pairs(win.stats) do box:SetShown(cards) end
    win.line:SetShown(not compact)
    win.line:ClearAllPoints()
    local listTop = cards and -106 or -46
    win.line:SetPoint("TOPLEFT", 14, listTop)
    win.line:SetPoint("TOPRIGHT", -14, listTop)

    -- List
    local showList = not compact
    win.scroll:SetShown(showList)
    win.scroll.track:SetShown(showList)
    win.empty:SetShown(false)
    win.scroll:ClearAllPoints()
    if showList then
        win.scroll:SetPoint("TOPLEFT", 14, listTop - 6)
    end

    -- Summary lines
    local keys = SUMMARY[layout]
    for _, line in pairs(win.summary) do line:Hide() end
    win.line2:Hide()
    win.summaryShown = keys ~= nil
    local height
    if cards then
        win.scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -26, 46)
        height = size.h
    elseif layout == "classic" then
        local summaryH = #keys * LINE_H
        local bottom = 44 -- reset button row
        win.scroll:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -26, bottom + summaryH + 14)
        win.line2:ClearAllPoints()
        win.line2:SetPoint("BOTTOMLEFT", 14, bottom + summaryH + 6)
        win.line2:SetPoint("BOTTOMRIGHT", -14, bottom + summaryH + 6)
        win.line2:Show()
        for i, key in ipairs(keys) do
            local line = SummaryLine(key)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 14, bottom + summaryH - (i - 1) * LINE_H)
            line:SetPoint("RIGHT", win, "RIGHT", -14, 0)
            line:Show()
        end
        height = size.h
    else
        for i, key in ipairs(keys) do
            local line = SummaryLine(key)
            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", win, "TOPLEFT", 10, -26 - (i - 1) * LINE_H)
            line:SetPoint("RIGHT", win, "RIGHT", -10, 0)
            line:Show()
        end
        height = 26 + #keys * LINE_H + 8
    end
    win.empty:ClearAllPoints()
    win.empty:SetPoint("TOP", win.scroll, "TOP", 0, -30)
    win.note:SetShown(not compact)
    win.reset:SetShown(not compact)
    win:SetSize(size.w, height)
    win.list:SetWidth(size.w - 40)
    self:ApplyTheme()
end

local function Create()
    -- No global name and not in UISpecialFrames: Escape must not close it, it stays up while you
    -- farm (Stig, 2026-10-05). Only x and /oui la close it.
    win = CreateFrame("Frame", nil, UIParent)
    win:SetSize(SIZES.classic.w, SIZES.classic.h)
    local pos = WinState().pos
    if pos then
        win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        win:SetPoint("CENTER", 240, 0)
    end
    win:SetFrameStrata("MEDIUM")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) if self:IsMovable() then self:StartMoving() end end)
    win:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Saved by the top-left corner, so switching layouts keeps the window where it is.
        local left, top = self:GetLeft(), self:GetTop()
        if left and top then
            WinState().pos = { "TOPLEFT", "BOTTOMLEFT", floor(left + 0.5), floor(top + 0.5) }
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", WinState().pos[3], WinState().pos[4])
        end
    end)
    win:Hide()
    Theme:Skin(win, Theme.colors.bg, Theme.colors.border)
    Theme:Shadow(win, 10)

    win.title = Theme:Text(win, 15)
    win.title:SetText(L["Loot appraiser"])
    win.hint = Theme:Text(win, 10, Theme.colors.muted)
    win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -4)
    win.hint:SetPoint("RIGHT", -40, 0)
    win.hint:SetWordWrap(false)
    win.close = Theme:TextButton(win, "x", 14)
    win.close:SetScript("OnClick", function() win:Hide() end)

    -- Cards: four stat boxes in a row.
    win.stats = {}
    local w = SIZES.cards.w
    local gap, boxW = 6, (w - 28 - 3 * 6) / 4
    local defs = { { "money", L["Gold looted"] }, { "items", L["Item value (AH)"] }, { "total", L["Total"] }, { "hour", L["Per hour"] } }
    for i, d in ipairs(defs) do
        local box = StatBox(win, d[2])
        box:SetSize(boxW, 44)
        box:SetPoint("TOPLEFT", 14 + (i - 1) * (boxW + gap), -52)
        win.stats[d[1]] = box
    end

    win.line = win:CreateTexture(nil, "BORDER")
    win.line:SetHeight(1)
    win.line2 = win:CreateTexture(nil, "BORDER")
    win.line2:SetHeight(1)

    win.scroll = Theme:Scroll(win)
    win.list = CreateFrame("Frame", nil, win.scroll)
    win.list:SetSize(SIZES.classic.w - 40, 1)
    win.scroll:SetScrollChild(win.list)
    win.scroll:SetScript("OnSizeChanged", function(self, sw)
        win.list:SetWidth(sw)
        self:UpdateThumb()
    end)
    win.empty = Theme:Text(win, 12, Theme.colors.muted)
    win.empty:SetText(L["Nothing looted since the last reset."])

    win.summary = {}

    win.note = Theme:Text(win, 10, Theme.colors.muted)
    win.note:SetPoint("BOTTOMLEFT", 14, 16)
    win.note:SetPoint("RIGHT", -110, 0)
    win.note:SetWordWrap(false)

    -- Reset asks twice: the session can't be brought back.
    win.reset = Theme:Button(win, L["Reset"], 90, 22)
    win.reset:SetPoint("BOTTOMRIGHT", -14, 12)
    win.reset:SetScript("OnClick", function(self)
        if self.armed then
            self.armed = nil
            self:SetText(L["Reset"])
            M:Reset()
        else
            self.armed = true
            self:SetText(L["Click again"])
            C_Timer.After(3, function()
                if self.armed then self.armed = nil; self:SetText(L["Reset"]) end
            end)
        end
    end)

    win:SetScript("OnShow", function()
        pendingClose = false
        WinState().open = true
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(15, function() M:Fill() end) -- time and per hour move on
    end)
    -- Belt and braces from when Escape could still close it (that is most likely what closed it
    -- on zoning, Stig 2026-10-05): a hide around a loading screen doesn't count as "closed", and
    -- the window opens again after it.
    win:SetScript("OnHide", function()
        if ticker then ticker:Cancel(); ticker = nil end
        pendingClose = true
        C_Timer.After(0.5, function()
            if pendingClose and not loading then WinState().open = false end
            pendingClose = false
        end)
    end)
end

function M:Toggle(show)
    if not ns.LootPrices then return end
    if not win then Create() end
    if show == nil then show = not win:IsShown() end
    if show then
        win:SetScale(self.db.scale)
        self:ApplyLayout()
        win:Show()
        self:Fill()
        if win.scroll:IsShown() then win.scroll:ScrollTo(0) end
    else
        win:Hide()
    end
end

function M:Refresh()
    if win then
        win:SetScale(self.db.scale)
        self:ApplyLayout()
        if win:IsShown() then self:Fill() end
    end
end

-- Opens the window again after a loading screen or a reload if it was open before.
local function Restore()
    loading = false
    if WinState().open and not (win and win:IsShown()) then M:Toggle(true) end
end

function M:OnEnable()
    ns.Events:On("OUI_LOOT_ITEM", self, OnItem)
    ns.Events:On("OUI_LOOT_MONEY", self, OnMoney)
    ns.Events:On("LOADING_SCREEN_ENABLED", self, function() loading = true end)
    ns.Events:On("LOADING_SCREEN_DISABLED", self, Restore)
    ns.Events:On("PLAYER_ENTERING_WORLD", self, Restore)
end

function M:OnDisable()
    if win then win:Hide() end
end

local function Open(args)
    if not M:IsEnabled() then
        print(ns.NAME .. ": " .. L["Loot appraiser is switched off (Loot → Loot appraiser)."])
        return
    end
    if args and args[1] == "reset" then
        M:Reset()
        print(ns.NAME .. ": " .. L["Loot appraiser session reset."])
        return
    end
    M:Toggle()
end
ns.Slash:Register("appraiser", Open, "loot appraiser window (add 'reset' to start over)")
ns.Slash:Register("la", Open, "loot appraiser window (add 'reset' to start over)")
