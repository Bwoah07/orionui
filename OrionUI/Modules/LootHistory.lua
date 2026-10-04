-- Loot history: small cards that pop up for what you loot and fade out: the name, what it is
-- under it, x4 on the right, bigger for better items (Stig, 2026-10-04: no list window, just these).
--
-- Where lines come from (checked in wow-ui-source and EllesmereUI's source, 2026-10-04):
--   * Items: CHAT_MSG_LOOT, matched against Blizzard's own "You receive loot/item" strings, so
--     only your loot counts and it covers the loot window, personal boss loot, chests and won rolls.
--     The first version cached loot slots on LOOT_OPENED, which saw nothing with EllesmereUI's
--     Quick Loot on: it loots on LOOT_READY, before LOOT_OPENED.
--   * Currencies: CHAT_MSG_CURRENCY, same way.
--   * Money: PLAYER_MONEY gains (exact copper from GetMoney) that come with loot: while loot is
--     open (from LOOT_READY), just after it closes, or next to a CHAT_MSG_MONEY. Vendor, quest
--     and mail gold are left out.
-- Chat text is not NeverSecret in 12.x; a secret line is skipped.
local _, ns = ...

local L = ns.L
local S = ns.Schema
local Theme = ns.Theme

local GetTime = GetTime
local floor = math.floor

local MONEY_WINDOW = 1.5 -- seconds a money gain and a loot event may be apart

local MIN_QUALITY = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4 }

local M = ns.Modules:New("LootHistory", {
    category = "qol", label = L["Loot history"], order = 7,
    desc = L["Small cards that pop up for what you loot and fade out: the name, what it is under it, bigger for better items. Preview with /oui lootfeed."],
    profileKey = "layout",
    schema = S.Table{ fields = {
        -- Lines
        feedDuration = S.Number{ section = L["Lines"], default = 6, min = 2, max = 30, step = 1, label = L["Seconds each line stays"], order = 2 },
        feedLines = S.Number{ section = L["Lines"], default = 6, min = 1, max = 12, step = 1, label = L["Lines at most"], order = 3 },
        feedWidth = S.Number{ section = L["Lines"], default = 300, min = 160, max = 500, step = 2, label = L["Width"], order = 4 },
        fontSize = S.Number{ section = L["Lines"], default = 12, min = 8, max = 18, step = 1, label = L["Text size"], order = 5 },
        feedGrowUp = S.Bool{ section = L["Lines"], default = true, label = L["New lines at the bottom, older ones move up"], order = 6 },
        smallCommon = S.Bool{ section = L["Lines"], default = true, label = L["Small, faded lines for grey and white items"], order = 7 },
        bigEpic = S.Bool{ section = L["Lines"], default = true, label = L["Big card with a glow for epic and better"], order = 8 },
        epicSound = S.Bool{ section = L["Lines"], default = true, label = L["Play a sound for epic and better"], order = 9 },
        -- What counts
        minQuality = S.Enum{ section = L["What it shows"], default = "poor", values = { "poor", "common", "uncommon", "rare", "epic" },
            valueLabels = { poor = L["Everything"], common = L["Common and better"], uncommon = L["Uncommon and better"],
                rare = L["Rare and better"], epic = L["Epic and better"] },
            label = L["Items"], order = 10 },
        money = S.Bool{ section = L["What it shows"], default = true, label = L["Money"], order = 11 },
        currency = S.Bool{ section = L["What it shows"], default = true, label = L["Currencies"], order = 12 },
    } },
    options = function(self)
        return {
            { type = "Header", label = L["Preview"] },
            { type = "Button", label = L["Preview loot lines"], style = "accent", func = function() self:Preview() end },
        }
    end,
})

local lootOpen, closedAt, moneyMsgAt = false, 0, 0
local lastMoney, pendingMoney, pendingAt = nil, 0, 0
local anchor, pool, active = nil, {}, {}
local editing = false

local function Plain(v, fallback) return ns.Secret.Plain(v, fallback) end

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

---------------------------------------------------------------------------
-- Reading loot messages
---------------------------------------------------------------------------

-- Blizzard format string -> Lua pattern ("You receive loot: %s." -> "^You receive loot: (.+)%.$").
local function ToPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
    p = p:gsub("([%^%$%(%)%.%[%]%*%+%-%?%%])", "%%%1")
    p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end

-- Multiple-count patterns first, so "x4" isn't swallowed by the single-item pattern.
local ITEM_PATTERNS, CURRENCY_PATTERNS
local function BuildPatterns()
    ITEM_PATTERNS, CURRENCY_PATTERNS = {}, {}
    for _, key in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
        local p = ToPattern(_G[key])
        if p then ITEM_PATTERNS[#ITEM_PATTERNS + 1] = p end
    end
    for _, key in ipairs({ "CURRENCY_GAINED_MULTIPLE", "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED" }) do
        local p = ToPattern(_G[key])
        if p then CURRENCY_PATTERNS[#CURRENCY_PATTERNS + 1] = p end
    end
end

-- link, count from a message, or nil when it isn't one of ours.
local function Match(text, patterns)
    if ns.Secret.Is(text) or type(text) ~= "string" then return nil end
    for _, p in ipairs(patterns) do
        local link, count = text:match(p)
        if link then return link, tonumber(count) or 1 end
    end
end

---------------------------------------------------------------------------
-- Lines (Stig picked these on 2026-10-04): a dark card per loot with the name on top in its
-- quality colour (no brackets) and a small grey line under it saying what it is ("ilvl 678 ·
-- Chest", "Trade Goods", "Quest item"). Size follows quality:
--   small  grey and white: one line, faded, no sub line
--   normal green, blue, currencies, money: the two-line card
--   big    epic and better: taller, bigger name, travelling glow, a short sound
-- More of the same item (or more gold) while its card is up adds to that card.
---------------------------------------------------------------------------

local TIER_SMALL, TIER_NORMAL, TIER_BIG = 1, 2, 3

local function Tier(e)
    local db = M.db
    if e.copper or e.currency then return TIER_NORMAL end
    local q = Plain(e.quality, 1) or 1
    if q >= 4 and db.bigEpic then return TIER_BIG end
    if q <= 1 and db.smallCommon then return TIER_SMALL end
    return TIER_NORMAL
end

-- Height, name size, sub size for a tier.
local function Metrics(tier)
    local fs = M.db.fontSize
    if tier == TIER_SMALL then return fs + 10, fs - 1, nil end
    if tier == TIER_BIG then return fs * 2 + 22, fs + 2, fs - 1 end
    return fs * 2 + 14, fs, fs - 2
end

local function NewLine()
    local line = CreateFrame("Frame", nil, anchor)
    Theme:Skin(line, { 0.067, 0.067, 0.082, 0.9 }, Theme.colors.border)
    line.wash = line:CreateTexture(nil, "BACKGROUND", nil, 1)
    line.wash:SetPoint("TOPLEFT", 1, -1)
    line.wash:SetPoint("BOTTOMRIGHT", -1, 1)
    line.wash:SetColorTexture(1, 1, 1, 1)
    line.strip = line:CreateTexture(nil, "BORDER")
    line.strip:SetPoint("TOPLEFT", 1, -1)
    line.strip:SetPoint("BOTTOMLEFT", 1, 1)
    line.strip:SetWidth(2)
    line.iconBox = CreateFrame("Frame", nil, line)
    line.iconBox:SetPoint("LEFT", 6, 0)
    Theme:Skin(line.iconBox, { 0, 0, 0, 1 }, Theme.colors.border)
    line.icon = line.iconBox:CreateTexture(nil, "ARTWORK")
    line.icon:SetPoint("TOPLEFT", 1, -1)
    line.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    line.glow = ns.PixelGlow:New(line, { lines = 8, thickness = 1, period = 5, pad = 1 })
    line.text = Theme:Text(line, 12)
    line.text:SetWordWrap(false)
    line.sub = Theme:Text(line, 10, Theme.colors.muted)
    line.sub:SetWordWrap(false)
    line.count = Theme:Text(line, 12)
    line.count:SetPoint("RIGHT", -8, 0)
    line.count:SetJustifyH("RIGHT")
    -- In: slide 12px from the left while fading in. Out: fade.
    line.fadeIn = line:CreateAnimationGroup()
    local t0 = line.fadeIn:CreateAnimation("Translation")
    t0:SetOffset(-12, 0); t0:SetDuration(0); t0:SetOrder(1)
    local t1 = line.fadeIn:CreateAnimation("Translation")
    t1:SetOffset(12, 0); t1:SetDuration(0.2); t1:SetOrder(2); t1:SetSmoothing("OUT")
    local a = line.fadeIn:CreateAnimation("Alpha")
    a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.18); a:SetOrder(2)
    -- Bump: the count pops when more of the same is looted.
    line.bump = line.count:CreateAnimationGroup()
    local s = line.bump:CreateAnimation("Scale")
    s:SetScaleFrom(1.4, 1.4); s:SetScaleTo(1, 1); s:SetDuration(0.2); s:SetSmoothing("OUT")
    line.fadeOut = line:CreateAnimationGroup()
    local b = line.fadeOut:CreateAnimation("Alpha")
    b:SetFromAlpha(1); b:SetToAlpha(0); b:SetDuration(0.5)
    line.fadeOut:SetScript("OnFinished", function() M:RemoveLine(line) end)
    return line
end

local function GetLine()
    for _, line in ipairs(pool) do
        if not line.inUse then return line end
    end
    local line = NewLine()
    pool[#pool + 1] = line
    return line
end

-- Fonts, positions and the card's size for its tier and current text. Cards are as wide as
-- their text (big cards at least 260px so they stand out), capped at the width setting.
local function Fit(line)
    local db = M.db
    local h, nameSize, subSize = Metrics(line.tier)
    local font = Theme:Font()
    line.text:SetFont(font, nameSize, "")
    line.count:SetFont(font, nameSize, "OUTLINE")
    local icon = h - 8
    line.iconBox:SetSize(icon, icon)
    local left = 6 + icon + 8
    local countW = line.count:IsShown() and (line.count:GetUnboundedStringWidth() + 12) or 0
    local maxText = math.max(40, db.feedWidth - left - 10 - countW)
    local textW = line.text:GetUnboundedStringWidth()
    local hasSub = subSize and line.sub:GetText() and line.sub:GetText() ~= ""
    line.text:ClearAllPoints()
    line.sub:ClearAllPoints()
    if hasSub then
        line.sub:SetFont(font, subSize, "")
        line.sub:Show()
        textW = math.max(textW, line.sub:GetUnboundedStringWidth())
        line.text:SetPoint("BOTTOMLEFT", line, "LEFT", left, 1)
        line.sub:SetPoint("TOPLEFT", line, "LEFT", left, -2)
    else
        line.sub:Hide()
        line.text:SetPoint("LEFT", left, 0)
    end
    textW = math.min(textW + 2, maxText)
    line.text:SetWidth(textW)
    line.sub:SetWidth(textW)
    local w = left + textW + 10 + countW
    if line.tier == TIER_BIG then w = math.max(w, 260) end
    line:SetSize(math.min(db.feedWidth, w), h)
end

function M:Layout()
    local db = self.db
    anchor:SetSize(db.feedWidth, (Metrics(TIER_NORMAL)))
    local y = 0
    for i = #active, 1, -1 do -- newest sits on the anchor
        local line = active[i]
        line:ClearAllPoints()
        if db.feedGrowUp then
            line:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, y)
        else
            line:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -y)
        end
        y = y + line:GetHeight() + 3
    end
end

function M:RemoveLine(line)
    if line.timer then line.timer:Cancel(); line.timer = nil end
    line.fadeOut:Stop()
    line.glow:Stop()
    line:Hide()
    line.inUse, line.key = false, nil
    for i, l in ipairs(active) do
        if l == line then table.remove(active, i) break end
    end
    self:Layout()
end

local function StartTimer(line, sticky)
    if line.timer then line.timer:Cancel(); line.timer = nil end
    line.fadeOut:Stop()
    line:SetAlpha(1)
    if sticky then return end
    -- Big drops stay a little longer.
    local duration = M.db.feedDuration + (line.tier == TIER_BIG and 4 or 0)
    line.timer = C_Timer.NewTimer(duration, function()
        line.timer = nil
        line.fadeOut:Play()
    end)
end

local function FindLine(key)
    for _, line in ipairs(active) do
        if line.key == key then return line end
    end
end

-- Paints the name and count of a line from its entry.
local function PaintText(line)
    local e = line.entry
    if e.copper then
        line.text:SetText(MoneyText(e.copper, (select(2, Metrics(line.tier)))))
        line.count:Hide()
    else
        line.text:SetText(e.name)
        line.count:SetText("x" .. e.count)
        line.count:SetShown(e.count > 1)
    end
    line.sub:SetText(e.sub or "")
    Fit(line)
end

local function EpicSound(quality)
    if not M.db.epicSound or not SOUNDKIT then return end
    local id = (Plain(quality, 4) or 4) >= 5 and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or SOUNDKIT.UI_EPICLOOT_TOAST
    if id then PlaySound(id) end
end

-- e = { key, icon, name (coloured), sub, count, quality, currency, r, g, b } or { key = "money", copper, ... }.
function M:Show(e, sticky)
    if not anchor then return end
    local line = FindLine(e.key)
    if line then
        if e.copper then
            line.entry.copper = line.entry.copper + e.copper
        else
            line.entry.count = line.entry.count + (e.count or 1)
        end
        PaintText(line)
        line.bump:Play()
        StartTimer(line, sticky)
        return
    end
    local db = self.db
    while #active >= db.feedLines do self:RemoveLine(active[1]) end
    line = GetLine()
    line.inUse, line.key = true, e.key
    line.tier = Tier(e)
    line.entry = { copper = e.copper, name = e.name, sub = e.sub, count = e.count or 1 }
    local r, g, b = e.r, e.g, e.b
    local small, big = line.tier == TIER_SMALL, line.tier == TIER_BIG
    line.icon:SetTexture(e.icon or 134400)
    Theme:SetBorderColor(line.iconBox, r, g, b, 1)
    line.strip:SetColorTexture(r, g, b, 1)
    line.strip:SetWidth(big and 3 or 2)
    line.wash:SetGradient("HORIZONTAL", CreateColor(r, g, b, big and 0.3 or small and 0.08 or 0.18), CreateColor(r, g, b, 0))
    line._ouiBg:SetAlpha(small and 0.6 or 1)
    line.count:SetTextColor(1, 1, 1)
    PaintText(line)
    if big then line.glow:Start(r, g, b, 0.9) else line.glow:Stop() end
    active[#active + 1] = line
    self:Layout()
    line:Show()
    line.fadeIn:Play()
    StartTimer(line, sticky)
    if big and not sticky then EpicSound(e.quality) end
end

-- "[Name]" -> "Name": the brackets read as clutter on a card (Stig, 2026-10-04). It stays a link.
local function NoBrackets(link) return (link:gsub("|h%[(.-)%]|h", "|h%1|h")) end

-- The grey line: "ilvl 678 · Chest" for gear, "Quest item", else the item's type ("Trade Goods").
local QUEST_CLASS = Enum.ItemClass and Enum.ItemClass.Questitem or 12
local function ItemSub(link, classID, itemType, itemSubType, equipLoc)
    if classID == QUEST_CLASS then return L["Quest item"] end
    if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" then
        local ilvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
        local slot = _G[equipLoc]
        if ilvl and slot then return string.format(L["ilvl %d · %s"], ilvl, slot) end
        if ilvl then return string.format(L["ilvl %d"], ilvl) end
        return slot
    end
    if itemSubType and itemSubType ~= "" and itemSubType ~= itemType then return itemSubType end
    return itemType
end

function M:ShowItem(link, count, sticky)
    local itemID, itemType, itemSubType, equipLoc, icon, classID = C_Item.GetItemInfoInstant(link)
    local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
    if (Plain(quality, 1) or 1) < (MIN_QUALITY[self.db.minQuality] or 0) then return end
    local r, g, b = QualityColor(quality)
    self:Show({ key = itemID and ("item:" .. itemID) or link, icon = icon, name = NoBrackets(link), sub = ItemSub(link, classID, itemType, itemSubType, equipLoc),
        count = count, quality = quality, r = r, g = g, b = b }, sticky)
end

function M:ShowCurrency(link, count, sticky)
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
    local quality = info and info.quality
    local r, g, b = QualityColor(quality)
    self:Show({ key = link:match("currency:(%d+)") or link, icon = info and info.iconFileID, name = NoBrackets(link), sub = L["Currency"], currency = true,
        count = count, quality = quality, r = r, g = g, b = b }, sticky)
end

function M:ShowMoney(copper, sticky)
    if not self.db.money then return end
    self:Show({ key = "money", icon = 133784, copper = copper, sub = L["Money"], r = 1, g = 0.82, b = 0.3 }, sticky)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function OnLoot(_, _, text)
    local link, count = Match(text, ITEM_PATTERNS)
    if link then M:ShowItem(link, count) end
end

local function OnCurrency(_, _, text)
    if not M.db.currency then return end
    local link, count = Match(text, CURRENCY_PATTERNS)
    if link then M:ShowCurrency(link, count) end
end

local function MoneyFromLoot(now)
    return lootOpen or now - closedAt < MONEY_WINDOW or now - moneyMsgAt < MONEY_WINDOW
end

local function OnMoney()
    local money = GetMoney()
    local delta = lastMoney and (money - lastMoney) or 0
    lastMoney = money
    if delta <= 0 then return end
    local now = GetTime()
    if MoneyFromLoot(now) then
        M:ShowMoney(delta)
    else
        -- The money message may come right after the gold itself.
        pendingMoney, pendingAt = delta, now
    end
end

local function OnMoneyMessage()
    local now = GetTime()
    moneyMsgAt = now
    if pendingMoney > 0 and now - pendingAt < MONEY_WINDOW then M:ShowMoney(pendingMoney) end
    pendingMoney = 0
end

local function OnLootReady() lootOpen = true end
local function OnLootClosed() lootOpen = false; closedAt = GetTime() end

---------------------------------------------------------------------------
-- Preview, lifecycle
---------------------------------------------------------------------------

local function ClearLines()
    for i = #active, 1, -1 do M:RemoveLine(active[i]) end
end

function M:Preview(sticky)
    if not anchor then return end
    ClearLines()
    local function Fake(name, quality, icon, sub, count, currency)
        local r, g, b = QualityColor(quality)
        local text = string.format("|cff%02x%02x%02x%s|r", floor(r * 255), floor(g * 255), floor(b * 255), name)
        self:Show({ key = name, icon = icon, name = text, sub = sub, count = count, quality = quality, currency = currency,
            r = r, g = g, b = b }, sticky)
    end
    Fake("Stringy Wolf Meat", 1, 133970, nil, 4)
    Fake("Rending Fang", 0, 133723)
    Fake("Shimmering Riftdust", 2, 134939, "Enchanting", 6)
    Fake("Valorstones", 3, 5868902, L["Currency"], 25, true)
    self:ShowMoney(102500, sticky)
    Fake("Starforged Cleaver of Orion", 4, 135349, "ilvl 691 · Two-Hand")
end

function M:Refresh()
    if not anchor then return end
    for _, line in ipairs(active) do PaintText(line) end
    self:Layout()
end

function M:OnEnable()
    if not anchor then
        anchor = CreateFrame("Frame", nil, UIParent)
        anchor:SetFrameStrata("MEDIUM")
        anchor:SetSize(self.db.feedWidth, (Metrics(TIER_NORMAL)))
        ns.Movers:Register("LootFeed", { label = L["Loot history"], getFrame = function() return anchor end, default = { x = 420, y = -160 } })
    end
    if not ITEM_PATTERNS then BuildPatterns() end
    lastMoney = GetMoney()
    ns.Events:On("CHAT_MSG_LOOT", self, OnLoot)
    ns.Events:On("CHAT_MSG_CURRENCY", self, OnCurrency)
    ns.Events:On("CHAT_MSG_MONEY", self, OnMoneyMessage)
    ns.Events:On("PLAYER_MONEY", self, OnMoney)
    ns.Events:On("LOOT_READY", self, OnLootReady)
    ns.Events:On("LOOT_OPENED", self, OnLootReady)
    ns.Events:On("LOOT_CLOSED", self, OnLootClosed)
    ns.Events:On("OUI_EDIT_MODE", self, function(_, _, shown)
        editing = shown and true or false
        ClearLines()
        if editing then self:Preview(true) end
    end)
    self:Refresh()
end

function M:OnDisable()
    editing, lootOpen = false, false
    if anchor then ClearLines() end
end

ns.Slash:Register("lootfeed", function() M:Preview() end, "preview the loot lines")
