-- Loot history: small lines that pop up for what you loot ("Looted [Sword]", "Looted [Cloth] x4",
-- "Looted 10g 3s") and fade out (Stig, 2026-10-04: no list window, just the lines).
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

local LINE_H = 20
local MONEY_WINDOW = 1.5 -- seconds a money gain and a loot event may be apart

local MIN_QUALITY = { poor = 0, common = 1, uncommon = 2, rare = 3, epic = 4 }

local M = ns.Modules:New("LootHistory", {
    category = "qol", label = L["Loot history"], order = 7,
    desc = L["Small lines that pop up for what you loot (Looted [Sword], Looted 10g) and fade out. Preview with /oui lootfeed."],
    profileKey = "layout",
    schema = S.Table{ fields = {
        -- Lines
        feedDuration = S.Number{ section = L["Lines"], default = 6, min = 2, max = 30, step = 1, label = L["Seconds each line stays"], order = 2 },
        feedLines = S.Number{ section = L["Lines"], default = 6, min = 1, max = 12, step = 1, label = L["Lines at most"], order = 3 },
        feedWidth = S.Number{ section = L["Lines"], default = 300, min = 160, max = 500, step = 2, label = L["Width"], order = 4 },
        fontSize = S.Number{ section = L["Lines"], default = 12, min = 8, max = 18, step = 1, label = L["Text size"], order = 5 },
        feedGrowUp = S.Bool{ section = L["Lines"], default = true, label = L["New lines at the bottom, older ones move up"], order = 6 },
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
-- Lines
---------------------------------------------------------------------------

local function NewLine()
    local line = CreateFrame("Frame", nil, anchor)
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
    line.text = line:CreateFontString(nil, "OVERLAY")
    line.text:SetPoint("LEFT", line.iconBox, "RIGHT", 6, 0)
    line.text:SetPoint("RIGHT", -4, 0)
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(false)
    line.fadeIn = line:CreateAnimationGroup()
    local a = line.fadeIn:CreateAnimation("Alpha")
    a:SetFromAlpha(0); a:SetToAlpha(1); a:SetDuration(0.15)
    line.fadeOut = line:CreateAnimationGroup()
    local b = line.fadeOut:CreateAnimation("Alpha")
    b:SetFromAlpha(1); b:SetToAlpha(0); b:SetDuration(0.6)
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

function M:Layout()
    local db = self.db
    anchor:SetSize(db.feedWidth, LINE_H)
    local n = #active
    for i, line in ipairs(active) do
        line:ClearAllPoints()
        line:SetSize(db.feedWidth, LINE_H)
        local fromNewest = n - i -- active is oldest first; the newest sits on the anchor
        if db.feedGrowUp then
            line:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, fromNewest * (LINE_H + 2))
        else
            line:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -fromNewest * (LINE_H + 2))
        end
    end
end

function M:RemoveLine(line)
    if line.timer then line.timer:Cancel(); line.timer = nil end
    line.fadeOut:Stop()
    line:Hide()
    line.inUse = false
    for i, l in ipairs(active) do
        if l == line then table.remove(active, i) break end
    end
    self:Layout()
end

-- Shows one line. text is already coloured; r, g, b colour the icon border and side strip.
function M:Show(icon, text, r, g, b, sticky)
    if not anchor then return end
    local db = self.db
    while #active >= db.feedLines do self:RemoveLine(active[1]) end
    local line = GetLine()
    line.inUse = true
    line.text:SetFont(Theme:Font(), db.fontSize, "OUTLINE")
    line.text:SetText(text)
    line.icon:SetTexture(icon or 134400)
    Theme:SetBorderColor(line.iconBox, r, g, b, 1)
    line.strip:SetColorTexture(r, g, b, 1)
    active[#active + 1] = line
    self:Layout()
    line:SetAlpha(1)
    line:Show()
    line.fadeIn:Play()
    if not sticky then
        line.timer = C_Timer.NewTimer(db.feedDuration, function()
            line.timer = nil
            line.fadeOut:Play()
        end)
    end
end

local function Looted(what) return string.format(L["Looted %s"], what) end

local function CountSuffix(count) return (count and count > 1) and ("|cffffffff x" .. count .. "|r") or "" end

function M:ShowItem(link, count, sticky)
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
    local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
    if (Plain(quality, 1) or 1) < (MIN_QUALITY[self.db.minQuality] or 0) then return end
    local r, g, b = QualityColor(quality)
    self:Show(icon, Looted(link .. CountSuffix(count)), r, g, b, sticky)
end

function M:ShowCurrency(link, count, sticky)
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
    local r, g, b = QualityColor(info and info.quality)
    self:Show(info and info.iconFileID, Looted(link .. CountSuffix(count)), r, g, b, sticky)
end

function M:ShowMoney(copper, sticky)
    if not self.db.money then return end
    self:Show(133784, Looted(MoneyText(copper, self.db.fontSize)), 1, 0.85, 0.35, sticky)
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
    local function Fake(name, quality, icon, count)
        local r, g, b = QualityColor(quality)
        local text = string.format("|cff%02x%02x%02x[%s]|r", floor(r * 255), floor(g * 255), floor(b * 255), name)
        self:Show(icon, Looted(text .. CountSuffix(count)), r, g, b, sticky)
    end
    Fake("Starforged Cleaver of Orion", 4, 135349)
    Fake("Runecloth", 1, 132903, 4)
    Fake("Valorstones", 3, 5868902, 25)
    self:Show(133784, Looted(MoneyText(102500, self.db.fontSize)), 1, 0.85, 0.35, sticky)
end

function M:Refresh()
    if not anchor then return end
    for _, line in ipairs(active) do line.text:SetFont(Theme:Font(), self.db.fontSize, "OUTLINE") end
    self:Layout()
end

function M:OnEnable()
    if not anchor then
        anchor = CreateFrame("Frame", nil, UIParent)
        anchor:SetFrameStrata("MEDIUM")
        anchor:SetSize(self.db.feedWidth, LINE_H)
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
