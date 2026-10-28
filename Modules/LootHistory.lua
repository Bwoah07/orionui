local _, ns = ...
local RC = ns.RC
local L = RC.L
local Kit = ns.LootKit

-- Loot history: cards that pop up for what you loot and fade out: the name, what it is under it,
-- x4 and its auction value on the right, taller for epic and better, prices on mouseover. More of
-- the same item (or more gold) while its card is up adds to that card. Ported from OrionUI.
--
-- Where lines come from:
--   * Items: CHAT_MSG_LOOT, matched against Blizzard's own "You receive loot/item" strings, so
--     only your loot counts and it covers the loot window, personal boss loot, chests and won
--     rolls. Reading chat messages also works when loot is taken before the loot window opens.
--   * Currencies: CHAT_MSG_CURRENCY, same way.
--   * Money: PLAYER_MONEY gains (exact copper from GetMoney) that come with loot: while loot is
--     open (from LOOT_READY), just after it closes, or next to a CHAT_MSG_MONEY. Vendor, quest
--     and mail gold are left out.
-- Chat text is not NeverSecret in 12.x; a secret line is skipped.
-- RC_LOOT_ITEM / RC_LOOT_MONEY go out for every loot, whatever the card filters say, so the loot
-- appraiser (Modules/LootAppraiser.lua) counts everything.

local GetTime = GetTime
local floor = math.floor

local MONEY_WINDOW = 1.5 -- seconds a money gain and a loot event may be apart

local MIN_QUALITY = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4 }

local M = RC:NewModule("LootHistory")

local DEFAULTS = {
    lootHistoryEnabled = true,
    lootHistoryDuration = 6,
    lootHistoryLines = 6,
    lootHistoryWidth = 280,
    lootHistoryFontSize = 12,
    lootHistoryGrowUp = true,
    lootHistoryBigEpic = true,
    lootHistoryEpicSound = true,
    lootHistoryMinQuality = "poor",
    lootHistoryMoney = true,
    lootHistoryCurrency = true,
    lootHistoryShowValue = true,
    lootHistoryPriceSource = "auto",
    lootHistoryValuableGold = 500,
    lootHistoryValuableSound = "auction",
    lootHistoryTooltip = true,
}
M.DEFAULTS = DEFAULTS
local db = Kit.Settings(DEFAULTS)

local lootOpen, closedAt, moneyMsgAt = false, 0, 0
local lastMoney, pendingMoney, pendingAt = nil, 0, 0
local anchor, pool, active = nil, {}, {}
local editing = false

local Plain = Kit.Plain
local QualityColor = Kit.QualityColor
local MoneyText = Kit.MoneyText
local ShortMoney = Kit.ShortMoney
local NoBrackets = Kit.NoBrackets

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
    if Kit.IsSecret(text) or type(text) ~= "string" then return nil end
    for _, p in ipairs(patterns) do
        local link, count = text:match(p)
        if link then return link, tonumber(count) or 1 end
    end
end

---------------------------------------------------------------------------
-- Cards (Stig, 2026-10-04): the same width for everything. Name on top in its quality colour
-- (no brackets), a small grey line under it saying what it is ("ilvl 678 · Chest", "Trade
-- Goods"). Right side: x4 on top, the stack's value under it. Epic and better: taller card,
-- bigger name, travelling glow, a short sound. More of the same item (or more gold) while its
-- card is up adds to that card. Hovering an item card shows its tooltip plus every price we
-- found, and keeps the card up.
---------------------------------------------------------------------------

local TIER_NORMAL, TIER_BIG = 1, 2

local function Tier(e)
    if e.copper or e.currency then return TIER_NORMAL end
    if (Plain(e.quality, 1) or 1) >= 4 and db.lootHistoryBigEpic then return TIER_BIG end
    return TIER_NORMAL
end

-- Height, name size, sub size for a tier.
local function Metrics(tier)
    local fs = db.lootHistoryFontSize
    if tier == TIER_BIG then return fs * 2 + 24, fs + 2, fs - 1 end
    return fs * 2 + 14, fs, fs - 2
end

local StartTimer -- defined below; hover pauses and restarts it

local function CardOnEnter(line)
    if not line.entry or not line.entry.link then return end
    if line.timer then line.timer:Cancel(); line.timer = nil end
    line.fadeOut:Stop()
    line:SetAlpha(1)
    Kit.PriceTooltip(line, line.entry.link, line.entry.count, L)
end

local function CardOnLeave(line)
    GameTooltip:Hide()
    if line.inUse then StartTimer(line, line.sticky) end
end

local function NewLine()
    local line = CreateFrame("Frame", nil, anchor)
    Kit.Skin(line, { 0.067, 0.067, 0.082, 0.92 }, Kit.colors.border)
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
    Kit.Skin(line.iconBox, { 0, 0, 0, 1 }, Kit.colors.border)
    line.icon = line.iconBox:CreateTexture(nil, "ARTWORK")
    line.icon:SetPoint("TOPLEFT", 1, -1)
    line.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    line.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    line.glow = Kit.Glow(line, { lines = 8, thickness = 1, period = 5, pad = 1 })
    line.text = Kit.Text(line, 12)
    line.text:SetWordWrap(false)
    line.sub = Kit.Text(line, 10, Kit.colors.muted)
    line.sub:SetWordWrap(false)
    line.count = Kit.Text(line, 12)
    line.count:SetJustifyH("RIGHT")
    line.value = Kit.Text(line, 10)
    line.value:SetJustifyH("RIGHT")
    line:SetScript("OnEnter", CardOnEnter)
    line:SetScript("OnLeave", CardOnLeave)
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

-- Fonts, positions and size for the card's tier and current text. Width is the setting for all.
local function Fit(line)
        local h, nameSize, subSize = Metrics(line.tier)
    local font = Kit.Font()
    line.text:SetFont(font, nameSize, "")
    line.sub:SetFont(font, subSize, "")
    line.count:SetFont(font, nameSize, "OUTLINE")
    line.value:SetFont(font, subSize, "")
    local icon = h - 8
    line.iconBox:SetSize(icon, icon)
    line:SetSize(db.lootHistoryWidth, h)
    local left = 6 + icon + 8
    local hasSub = (line.sub:GetText() or "") ~= ""
    line.text:ClearAllPoints()
    line.sub:ClearAllPoints()
    line.count:ClearAllPoints()
    line.value:ClearAllPoints()
    if hasSub or line.value:IsShown() then
        line.text:SetPoint("BOTTOMLEFT", line, "LEFT", left, 1)
        line.sub:SetPoint("TOPLEFT", line, "LEFT", left, -2)
        line.count:SetPoint("BOTTOMRIGHT", line, "RIGHT", -8, 1)
        line.value:SetPoint("TOPRIGHT", line, "RIGHT", -8, -2)
    else
        line.text:SetPoint("LEFT", left, 0)
        line.count:SetPoint("RIGHT", -8, 0)
    end
    line.sub:SetShown(hasSub)
    local countW = line.count:IsShown() and (line.count:GetUnboundedStringWidth() + 10) or 0
    local valueW = line.value:IsShown() and (line.value:GetUnboundedStringWidth() + 10) or 0
    line.text:SetWidth(math.max(40, db.lootHistoryWidth - left - 8 - countW))
    line.sub:SetWidth(math.max(40, db.lootHistoryWidth - left - 8 - valueW))
end

function M:Layout()
        anchor:SetSize(db.lootHistoryWidth, (Metrics(TIER_NORMAL)))
    local y = 0
    for i = #active, 1, -1 do -- newest sits on the anchor
        local line = active[i]
        line:ClearAllPoints()
        if db.lootHistoryGrowUp then
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
    if GameTooltip:IsOwned(line) then GameTooltip:Hide() end
    line:Hide()
    line.inUse, line.key, line.entry = false, nil, nil
    for i, l in ipairs(active) do
        if l == line then table.remove(active, i) break end
    end
    self:Layout()
end

StartTimer = function(line, sticky)
    if line.timer then line.timer:Cancel(); line.timer = nil end
    line.fadeOut:Stop()
    line:SetAlpha(1)
    line.sticky = sticky
    if sticky or line:IsMouseOver() and line:IsMouseEnabled() then return end
    -- Big drops stay a little longer.
    local duration = db.lootHistoryDuration + (line.tier == TIER_BIG and 4 or 0)
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

-- Paints the name, count and value of a card from its entry.
local function PaintText(line)
    local e = line.entry
    local _, nameSize, subSize = Metrics(line.tier)
    if e.copper then
        line.text:SetText(MoneyText(e.copper, nameSize))
        line.count:Hide()
    else
        line.text:SetText(e.name)
        line.count:SetText("x" .. e.count)
        line.count:SetShown(e.count > 1)
    end
    line.sub:SetText(e.sub or "")
    if e.unit and db.lootHistoryShowValue then
        line.value:SetText(ShortMoney(e.unit * e.count, subSize))
        if e.vendor then
            line.value:SetTextColor(0.55, 0.55, 0.6)
        elseif e.pinged then
            line.value:SetTextColor(1, 0.82, 0.3)
        else
            line.value:SetTextColor(1, 1, 1)
        end
        line.value:Show()
    else
        line.value:Hide()
    end
    Fit(line)
end

-- Sound kits checked in wow-ui-source SoundKitConstants.lua (2026-10-04).
local VALUABLE_SOUNDS = { auction = "AUCTION_WINDOW_OPEN", coins = "LOOT_WINDOW_COIN_SOUND", epic = "UI_EPICLOOT_TOAST" }

-- Loot worth the set amount on the auction house (vendor prices don't count): a ping and a gold
-- glow, once per card, also when a stack grows past it (Stig, 2026-10-04).
local function CheckValuable(line, sticky)
    local e = line.entry
    if e.pinged or not e.unit or e.vendor or db.lootHistoryValuableGold <= 0 then return end
    if e.unit * e.count < db.lootHistoryValuableGold * 10000 then return end
    e.pinged = true
    line.glow:Start(1, 0.82, 0.3, 1)
    line.value:SetTextColor(1, 0.82, 0.3)
    local id = SOUNDKIT and SOUNDKIT[VALUABLE_SOUNDS[db.lootHistoryValuableSound] or "AUCTION_WINDOW_OPEN"]
    if id and not sticky then PlaySound(id) end
end

local function EpicSound(quality)
    if not db.lootHistoryEpicSound or not SOUNDKIT then return end
    local id = (Plain(quality, 4) or 4) >= 5 and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or SOUNDKIT.UI_EPICLOOT_TOAST
    if id then PlaySound(id) end
end

-- e = { key, link, icon, name (coloured), sub, count, quality, currency, unit, vendor, r, g, b }
--  or { key = "money", copper, ... }.
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
        CheckValuable(line, sticky)
        StartTimer(line, sticky)
        return
    end
        while #active >= db.lootHistoryLines do self:RemoveLine(active[1]) end
    line = GetLine()
    line.inUse, line.key = true, e.key
    line.tier = Tier(e)
    line.entry = { copper = e.copper, link = e.link, name = e.name, sub = e.sub, count = e.count or 1, unit = e.unit, vendor = e.vendor }
    local r, g, b = e.r, e.g, e.b
    local big = line.tier == TIER_BIG
    line.icon:SetTexture(e.icon or 134400)
    Kit.SetBorderColor(line.iconBox, r, g, b, 1)
    line.strip:SetColorTexture(r, g, b, 1)
    line.strip:SetWidth(big and 3 or 2)
    line.wash:SetGradient("HORIZONTAL", CreateColor(r, g, b, big and 0.3 or 0.18), CreateColor(r, g, b, 0))
    line.count:SetTextColor(1, 1, 1)
    line:EnableMouse(db.lootHistoryTooltip and e.link ~= nil)
    PaintText(line)
    if big then line.glow:Start(r, g, b, 0.9) else line.glow:Stop() end
    active[#active + 1] = line
    self:Layout()
    line:Show()
    line.fadeIn:Play()
    StartTimer(line, sticky)
    if big and not sticky then EpicSound(e.quality) end
    CheckValuable(line, sticky)
end

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
    if (Plain(quality, 1) or 1) < (MIN_QUALITY[db.lootHistoryMinQuality] or 0) then return end
    local r, g, b = QualityColor(quality)
    local unit, vendor = Kit.CardPrice(link)
    self:Show({ key = itemID and ("item:" .. itemID) or link, link = link, icon = icon, name = NoBrackets(link),
        sub = ItemSub(link, classID, itemType, itemSubType, equipLoc), count = count, quality = quality,
        unit = unit, vendor = vendor, r = r, g = g, b = b }, sticky)
end

function M:ShowCurrency(link, count, sticky)
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
    local quality = info and info.quality
    local r, g, b = QualityColor(quality)
    self:Show({ key = link:match("currency:(%d+)") or link, icon = info and info.iconFileID, name = NoBrackets(link),
        sub = L["Currency"], currency = true, count = count, quality = quality, r = r, g = g, b = b }, sticky)
end

function M:ShowMoney(copper, sticky)
    if not db.lootHistoryMoney then return end
    self:Show({ key = "money", icon = 133784, copper = copper, sub = L["Money"], r = 1, g = 0.82, b = 0.3 }, sticky)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

-- RC_LOOT_ITEM / RC_LOOT_MONEY go out for every loot, whatever the card filters say, so the
-- loot appraiser (Modules/LootAppraiser.lua) counts everything.
local function OnLoot(_, _, text)
    local link, count = Match(text, ITEM_PATTERNS)
    if not link then return end
    Kit.Fire("RC_LOOT_ITEM", link, count)
    M:ShowItem(link, count)
end

local function OnCurrency(_, _, text)
    if not db.lootHistoryCurrency then return end
    local link, count = Match(text, CURRENCY_PATTERNS)
    if link then M:ShowCurrency(link, count) end
end

local function MoneyFromLoot(now)
    return lootOpen or now - closedAt < MONEY_WINDOW or now - moneyMsgAt < MONEY_WINDOW
end

local function LootedMoney(copper)
    Kit.Fire("RC_LOOT_MONEY", copper)
    M:ShowMoney(copper)
end

local function OnMoney()
    local money = GetMoney()
    local delta = lastMoney and (money - lastMoney) or 0
    lastMoney = money
    if delta <= 0 then return end
    local now = GetTime()
    if MoneyFromLoot(now) then
        LootedMoney(delta)
    else
        -- The money message may come right after the gold itself.
        pendingMoney, pendingAt = delta, now
    end
end

local function OnMoneyMessage()
    local now = GetTime()
    moneyMsgAt = now
    if pendingMoney > 0 and now - pendingAt < MONEY_WINDOW then LootedMoney(pendingMoney) end
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
    if not self.active then
        RC:Print(L["Loot history is switched off (Interface > Loot History)."])
        return
    end
    ClearLines()
    local function Fake(name, quality, icon, sub, count, unit, vendor, currency)
        local r, g, b = QualityColor(quality)
        local text = string.format("|cff%02x%02x%02x%s|r", floor(r * 255), floor(g * 255), floor(b * 255), name)
        self:Show({ key = name, icon = icon, name = text, sub = sub, count = count, quality = quality, currency = currency,
            unit = unit, vendor = vendor, r = r, g = g, b = b }, sticky)
    end
    Fake("Rending Fang", 0, 133723, "Junk", 1, 1250, true)
    Fake("Stringy Wolf Meat", 1, 133970, "Cooking", 4, 4200)
    Fake("Shimmering Riftdust", 2, 134939, "Enchanting", 6, 185000)
    Fake("Valorstones", 3, 5868902, L["Currency"], 25, nil, nil, true)
    self:ShowMoney(102500, sticky)
    Fake("Starforged Cleaver", 4, 135349, "ilvl 691 · Two-Hand", 1, 48500000)
end

function M:Refresh()
    local want = db.lootHistoryEnabled == true
    if want and not self.active then
        self:Activate()
    elseif not want and self.active then
        self:Deactivate()
    end
    if not anchor then return end
    anchor:SetSize(db.lootHistoryWidth, (Metrics(TIER_NORMAL)))
    for _, line in ipairs(active) do PaintText(line) end
    self:Layout()
end

function M:Activate()
    if not anchor then
        anchor = Kit.Anchor("lootHistoryPos", { "CENTER", "UIParent", "CENTER", 420, -160 })
        anchor:SetFrameStrata("MEDIUM")
        anchor:SetSize(db.lootHistoryWidth, (Metrics(TIER_NORMAL)))
        self.anchor = anchor
    end
    self.active = true
    if not ITEM_PATTERNS then BuildPatterns() end
    lastMoney = GetMoney()
    Kit.On("CHAT_MSG_LOOT", self, OnLoot)
    Kit.On("CHAT_MSG_CURRENCY", self, OnCurrency)
    Kit.On("CHAT_MSG_MONEY", self, OnMoneyMessage)
    Kit.On("PLAYER_MONEY", self, OnMoney)
    Kit.On("LOOT_READY", self, OnLootReady)
    Kit.On("LOOT_OPENED", self, OnLootReady)
    Kit.On("LOOT_CLOSED", self, OnLootClosed)
end

function M:Deactivate()
    self.active = false
    Kit.Off(self)
    editing, lootOpen = false, false
    if anchor then ClearLines() end
end

-- Layout mode (/rc layout): sample cards to drag; the drag lands on the newest card's spot.
function M:BeginLayoutMode()
    if not self.active then return end
    editing = true
    ClearLines()
    self:Preview(true)
    for _, line in ipairs(active) do line:EnableMouse(false) end
    Kit.ShowHandle(anchor, true)
end

function M:EndLayoutMode()
    if not editing then return end
    editing = false
    Kit.ShowHandle(anchor, false)
    ClearLines()
end

function M:ResetPosition()
    if anchor then anchor:ResetPosition() end
end

function M:OnEnable()
    self:Refresh()
end

function M:OnDisable()
    if self.active then self:Deactivate() end
end
