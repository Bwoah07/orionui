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
-- Lines: a small dark card per loot. Quality strip and wash on the left, icon with a quality
-- border (travelling glow from epic), "Looted" in grey, the name in its quality colour without
-- brackets, the count on the right. The same item (or more gold) while its line is up adds to
-- that line instead of stacking a new one. Cards size to their text.
---------------------------------------------------------------------------

local function LineHeight() return M.db.fontSize + 14 end

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
    line.glow = ns.PixelGlow:New(line.iconBox, { lines = 5, thickness = 1, period = 3.5, pad = 1 })
    line.label = Theme:Text(line, 11, Theme.colors.muted)
    line.label:SetPoint("LEFT", line.iconBox, "RIGHT", 7, 0)
    line.label:SetWordWrap(false)
    line.text = Theme:Text(line, 12)
    line.text:SetPoint("LEFT", line.label, "RIGHT", 4, 0)
    line.text:SetWordWrap(false)
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

-- Fonts, sizes and the card's width for its current text.
local function Fit(line)
    local db = M.db
    local h = LineHeight()
    local font = Theme:Font()
    line.label:SetFont(font, db.fontSize - 1, "")
    line.text:SetFont(font, db.fontSize, "")
    line.count:SetFont(font, db.fontSize, "OUTLINE")
    line.iconBox:SetSize(h - 6, h - 6)
    local labelW = line.label:GetUnboundedStringWidth()
    local countW = line.count:IsShown() and (line.count:GetUnboundedStringWidth() + 10) or 0
    local fixed = 6 + (h - 6) + 7 + labelW + 4 + 10 + countW
    line.text:SetWidth(math.min(line.text:GetUnboundedStringWidth() + 2, math.max(40, db.feedWidth - fixed)))
    line:SetSize(math.min(db.feedWidth, fixed + line.text:GetWidth()), h)
end

function M:Layout()
    local db = self.db
    local h = LineHeight()
    anchor:SetSize(db.feedWidth, h)
    local n = #active
    for i, line in ipairs(active) do
        line:ClearAllPoints()
        local fromNewest = n - i -- active is oldest first; the newest sits on the anchor
        if db.feedGrowUp then
            line:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 0, fromNewest * (h + 3))
        else
            line:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -fromNewest * (h + 3))
        end
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
    line.timer = C_Timer.NewTimer(M.db.feedDuration, function()
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
        line.text:SetText(MoneyText(e.copper, M.db.fontSize))
        line.count:Hide()
    else
        line.text:SetText(e.name)
        line.count:SetText("x" .. e.count)
        line.count:SetShown(e.count > 1)
    end
    Fit(line)
end

-- e = { key, icon, name (coloured), count, quality, r, g, b } or { key = "money", copper, ... }.
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
    line.entry = { copper = e.copper, name = e.name, count = e.count or 1 }
    local r, g, b = e.r, e.g, e.b
    line.icon:SetTexture(e.icon or 134400)
    line.label:SetText(L["Looted"])
    Theme:SetBorderColor(line.iconBox, r, g, b, 1)
    line.strip:SetColorTexture(r, g, b, 1)
    line.wash:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.18), CreateColor(r, g, b, 0))
    line.count:SetTextColor(1, 1, 1)
    PaintText(line)
    if (Plain(e.quality, 0) or 0) >= 4 then line.glow:Start(r, g, b, 0.9) else line.glow:Stop() end
    active[#active + 1] = line
    self:Layout()
    line:Show()
    line.fadeIn:Play()
    StartTimer(line, sticky)
end

-- "[Name]" -> "Name": the brackets read as clutter on a card (Stig, 2026-10-04). It stays a link.
local function NoBrackets(link) return (link:gsub("|h%[(.-)%]|h", "|h%1|h")) end

function M:ShowItem(link, count, sticky)
    local _, _, _, _, icon = C_Item.GetItemInfoInstant(link)
    local quality = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(link)
    if (Plain(quality, 1) or 1) < (MIN_QUALITY[self.db.minQuality] or 0) then return end
    local r, g, b = QualityColor(quality)
    self:Show({ key = link, icon = icon, name = NoBrackets(link), count = count, quality = quality, r = r, g = g, b = b }, sticky)
end

function M:ShowCurrency(link, count, sticky)
    local info = C_CurrencyInfo.GetCurrencyInfoFromLink(link)
    local quality = info and info.quality
    local r, g, b = QualityColor(quality)
    self:Show({ key = link, icon = info and info.iconFileID, name = NoBrackets(link), count = count, quality = quality, r = r, g = g, b = b }, sticky)
end

function M:ShowMoney(copper, sticky)
    if not self.db.money then return end
    self:Show({ key = "money", icon = 133784, copper = copper, r = 1, g = 0.82, b = 0.3 }, sticky)
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
        local text = string.format("|cff%02x%02x%02x%s|r", floor(r * 255), floor(g * 255), floor(b * 255), name)
        self:Show({ key = name, icon = icon, name = text, count = count, quality = quality, r = r, g = g, b = b }, sticky)
    end
    Fake("Starforged Cleaver of Orion", 4, 135349)
    Fake("Stringy Wolf Meat", 1, 133970, 4)
    Fake("Valorstones", 3, 5868902, 25)
    self:ShowMoney(102500, sticky)
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
        anchor:SetSize(self.db.feedWidth, LineHeight())
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
