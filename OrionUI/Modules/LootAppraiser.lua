-- Loot appraiser: a window (/oui appraiser, /oui la) with everything looted since the last reset,
-- what it is worth on your realm's auction house, gold looted, and gold per hour (Stig, 2026-10-05).
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

local ROW_H = 26
local WIDTH, HEIGHT = 480, 520

local M = ns.Modules:New("LootAppraiser", {
    category = "qol", label = L["Loot appraiser"], order = 8,
    desc = L["A window with everything you looted since the last reset and what it is worth on the auction house. Open it with /oui appraiser (or /oui la). Needs Loot history on; prices from TradeSkillMaster or Auctionator."],
    profileKey = "layout",
    schema = S.Table{ fields = {
        scale = S.Number{ default = 1, min = 0.6, max = 1.6, step = 0.05, label = L["Window scale"], order = 1 },
        hideJunk = S.Bool{ default = false, label = L["Leave grey items out of the list"], order = 2 },
    } },
    options = function(self)
        return {
            { type = "Header", label = L["Window"] },
            { type = "Button", label = L["Open loot appraiser"], style = "accent", func = function() self:Toggle(true) end },
        }
    end,
})

local win, rows = nil, {}
local ticker

local function P() return ns.LootPrices end

local function Session()
    local char = ns.DB.char
    local s = char.lootAppraiser
    if not s then
        s = { started = time(), money = 0, items = {} }
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
    local e = s.items[key]
    if e then
        e.count = e.count + (count or 1)
    else
        s.items[key] = { link = link, count = count or 1 }
    end
    if win and win:IsShown() then M:Fill() end
end

local function OnMoney(_, _, copper)
    if type(copper) ~= "number" then return end
    local s = Session()
    s.money = s.money + copper
    if win and win:IsShown() then M:Fill() end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

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

local function RowOnEnter(row)
    row.hl:Show()
    if not row.link then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(row.link)
    local prices = P().All(row.link)
    if #prices > 0 then
        local r, g, b = Theme:Accent()
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["%s value (x%d)"], ns.NAME, row.qty), r, g, b)
        for _, p in ipairs(prices) do
            GameTooltip:AddDoubleLine(p.label, P().MoneyText(p.copper * row.qty, 12) .. "  |cff8a8a99("
                .. P().MoneyText(p.copper, 10) .. ")|r", 0.8, 0.8, 0.85, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function RowOnLeave(row)
    row.hl:Hide()
    GameTooltip:Hide()
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, win.list)
    row:SetHeight(ROW_H)
    if i % 2 == 0 then
        row.zebra = row:CreateTexture(nil, "BACKGROUND")
        row.zebra:SetAllPoints()
        row.zebra:SetColorTexture(1, 1, 1, 0.02)
    end
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.05)
    row.hl:Hide()
    row.iconBox = CreateFrame("Frame", nil, row)
    row.iconBox:SetSize(ROW_H - 6, ROW_H - 6)
    row.iconBox:SetPoint("LEFT", 4, 0)
    Theme:Skin(row.iconBox, { 0, 0, 0, 1 }, Theme.colors.border)
    row.icon = row.iconBox:CreateTexture(nil, "ARTWORK")
    row.icon:SetPoint("TOPLEFT", 1, -1)
    row.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick() then HandleModifiedItemClick(self.link) end
    end)
    rows[i] = row
    return row
end

-- Prices are looked up now, so the list follows the latest TSM / Auctionator data.
local function Entries()
    local s, list = Session(), {}
    for _, e in pairs(s.items) do
        local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(e.link)
        quality = ns.Secret.Plain(quality, 1) or 1
        if not (M.db.hideJunk and quality == 0) then
            local unit, vendor = P().Card(e.link)
            list[#list + 1] = { link = e.link, count = e.count, quality = quality, unit = unit, vendor = vendor,
                total = (unit or 0) * e.count }
        end
    end
    table.sort(list, function(a, b)
        if a.total ~= b.total then return a.total > b.total end
        return a.count > b.count
    end)
    return list
end

function M:Fill()
    if not win then return end
    local s = Session()
    local list = Entries()
    local ah, vendorTotal = 0, 0
    for i, e in ipairs(list) do
        if e.vendor then vendorTotal = vendorTotal + e.total else ah = ah + e.total end
        local row = Row(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", win.list, "TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", win.list, "RIGHT", 0, 0)
        row.link, row.qty = e.link, e.count
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(e.link)
        row.icon:SetTexture(icon or 134400)
        Theme:SetBorderColor(row.iconBox, P().QualityColor(e.quality))
        row.name:SetText(NoBrackets(e.link))
        row.count:SetText("x" .. e.count)
        if e.unit then
            row.unit:SetText(P().MoneyText(e.unit, 10))
            row.total:SetText(P().MoneyText(e.total, 12))
            if e.vendor then row.total:SetTextColor(0.55, 0.55, 0.6) else row.total:SetTextColor(1, 1, 1) end
        else
            row.unit:SetText("")
            row.total:SetText("|cff666670-|r")
        end
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    win.list:SetHeight(max(1, #list * ROW_H))
    win.empty:SetShown(#list == 0)
    win.scroll:UpdateThumb()

    local seconds = time() - s.started
    local total = s.money + ah + vendorTotal
    win.stats.money.value:SetText(P().MoneyText(s.money, 13))
    win.stats.items.value:SetText(P().MoneyText(ah, 13))
    win.stats.total.value:SetText(P().MoneyText(total, 13))
    local perHour = seconds >= 60 and floor(total * 3600 / seconds) or 0
    win.stats.hour.value:SetText(seconds >= 60 and P().MoneyText(floor(perHour / 10000) * 10000, 13) or "|cff666670-|r")
    win.hint:SetText(string.format(L["Since %s · %s · prices: %s"], date("%d.%m %H:%M", s.started), Duration(seconds),
        P().SourceLabel()))
    win.vendorNote:SetText(vendorTotal > 0 and string.format(L["Vendor value (grey, not in Item value): %s"],
        P().MoneyText(vendorTotal, 11)) or "")
end

local function Create()
    win = CreateFrame("Frame", "OrionUILootAppraiser", UIParent) -- global name: Esc closes via UISpecialFrames
    win:SetSize(WIDTH, HEIGHT)
    win:SetPoint("CENTER", 240, 0)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:Hide()
    tinsert(UISpecialFrames, "OrionUILootAppraiser")
    Theme:Skin(win, Theme.colors.bg, Theme.colors.border)
    Theme:Shadow(win)

    local r, g, b = Theme:Accent()
    win.title = Theme:Text(win, 15)
    win.title:SetPoint("TOPLEFT", 14, -12)
    win.title:SetTextColor(r, g, b)
    win.title:SetText(L["Loot appraiser"])
    win.hint = Theme:Text(win, 10, Theme.colors.muted)
    win.hint:SetPoint("TOPLEFT", win.title, "BOTTOMLEFT", 0, -4)
    win.hint:SetPoint("RIGHT", -40, 0)
    win.hint:SetWordWrap(false)
    local close = Theme:TextButton(win, "x", 16)
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() win:Hide() end)

    -- Four stat boxes in a row.
    win.stats = {}
    local gap, boxW = 6, (WIDTH - 28 - 3 * 6) / 4
    local defs = { { "money", L["Gold looted"] }, { "items", L["Item value (AH)"] }, { "total", L["Total"] }, { "hour", L["Per hour"] } }
    for i, d in ipairs(defs) do
        local box = StatBox(win, d[2])
        box:SetSize(boxW, 44)
        box:SetPoint("TOPLEFT", 14 + (i - 1) * (boxW + gap), -52)
        win.stats[d[1]] = box
    end
    win.stats.total.value:SetTextColor(r, g, b)

    local line = win:CreateTexture(nil, "BORDER")
    line:SetPoint("TOPLEFT", 14, -106)
    line:SetPoint("TOPRIGHT", -14, -106)
    line:SetHeight(1)
    line:SetColorTexture(r, g, b, 0.8)

    win.scroll = Theme:Scroll(win)
    win.scroll:SetPoint("TOPLEFT", 14, -112)
    win.scroll:SetPoint("BOTTOMRIGHT", -26, 46)
    win.list = CreateFrame("Frame", nil, win.scroll)
    win.list:SetSize(WIDTH - 40, 1)
    win.scroll:SetScrollChild(win.list)
    win.scroll:SetScript("OnSizeChanged", function(self, w)
        win.list:SetWidth(w)
        self:UpdateThumb()
    end)
    win.empty = Theme:Text(win, 12, Theme.colors.muted)
    win.empty:SetPoint("TOP", 0, -150)
    win.empty:SetText(L["Nothing looted since the last reset."])

    win.vendorNote = Theme:Text(win, 10, Theme.colors.muted)
    win.vendorNote:SetPoint("BOTTOMLEFT", 14, 16)

    -- Reset asks twice: the session can't be brought back.
    local reset = Theme:Button(win, L["Reset"], 90, 22)
    reset:SetPoint("BOTTOMRIGHT", -14, 12)
    reset:SetScript("OnClick", function(self)
        if self.armed then
            self.armed = nil
            self:SetText(L["Reset"])
            ns.DB.char.lootAppraiser = nil
            M:Fill()
        else
            self.armed = true
            self:SetText(L["Click again"])
            C_Timer.After(3, function()
                if self.armed then self.armed = nil; self:SetText(L["Reset"]) end
            end)
        end
    end)

    win:SetScript("OnShow", function()
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(15, function() M:Fill() end) -- time and per hour move on
    end)
    win:SetScript("OnHide", function()
        if ticker then ticker:Cancel(); ticker = nil end
    end)
end

function M:Toggle(show)
    if not ns.LootPrices then return end
    if not win then Create() end
    if show == nil then show = not win:IsShown() end
    if show then
        win:SetScale(self.db.scale)
        win:Show()
        self:Fill()
        win.scroll:ScrollTo(0)
    else
        win:Hide()
    end
end

function M:Refresh()
    if win then
        win:SetScale(self.db.scale)
        if win:IsShown() then self:Fill() end
    end
end

function M:OnEnable()
    ns.Events:On("OUI_LOOT_ITEM", self, OnItem)
    ns.Events:On("OUI_LOOT_MONEY", self, OnMoney)
end

function M:OnDisable()
    if win then win:Hide() end
end

local function Open()
    if M:IsEnabled() then M:Toggle() else print(ns.NAME .. ": " .. L["Loot appraiser is switched off (Interface → Loot appraiser)."]) end
end
ns.Slash:Register("appraiser", Open, "loot appraiser window")
ns.Slash:Register("la", Open, "loot appraiser window")
