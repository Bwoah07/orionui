local _, ns = ...
local RC = ns.RC

-- Shared pieces for the loot modules (Loot.lua, LootHistory.lua, LootAppraiser.lua): the card
-- look, a soft shadow, a travelling glow, settings with defaults, a small event bus (WoW events
-- plus our own RC_LOOT_* messages), auction prices and money text.

local Kit = {}
ns.LootKit = Kit

local floor, min, max = math.floor, math.min, math.max

---------------------------------------------------------------------------
-- Secret values
---------------------------------------------------------------------------

function Kit.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function Kit.Plain(v, fallback)
    if v == nil or Kit.IsSecret(v) then return fallback end
    return v
end

---------------------------------------------------------------------------
-- Settings: RaidControlDB profile keys with defaults; a value of the wrong type reads as the default
---------------------------------------------------------------------------

function Kit.Settings(defaults)
    return setmetatable({}, {
        __index = function(_, key)
            local fallback = defaults[key]
            local profile = RC.db and RC.db.profile
            local value = profile and profile[key]
            if value == nil or (fallback ~= nil and type(value) ~= type(fallback)) then
                return fallback
            end
            return value
        end,
        __newindex = function(_, key, value)
            if RC.db and RC.db.profile then RC.db.profile[key] = value end
        end,
    })
end

---------------------------------------------------------------------------
-- Event bus: Kit.On(event, owner, fn) calls fn(owner, event, ...); Kit.Off(owner) drops all of
-- an owner's handlers. Names starting with RC_ are our own messages, sent with Kit.Fire.
---------------------------------------------------------------------------

local handlers = {}
local busFrame = CreateFrame("Frame")
busFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, h in ipairs(list) do
        local ok, err = pcall(h.fn, h.owner, event, ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end)

function Kit.On(event, owner, fn)
    local list = handlers[event]
    if not list then
        list = {}
        handlers[event] = list
        if event:sub(1, 3) ~= "RC_" then busFrame:RegisterEvent(event) end
    end
    for _, h in ipairs(list) do
        if h.owner == owner then h.fn = fn return end
    end
    list[#list + 1] = { owner = owner, fn = fn }
end

function Kit.Off(owner)
    for event, list in pairs(handlers) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then table.remove(list, i) end
        end
        if #list == 0 then
            handlers[event] = nil
            if event:sub(1, 3) ~= "RC_" then busFrame:UnregisterEvent(event) end
        end
    end
end

function Kit.Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for _, h in ipairs(list) do
        local ok, err = pcall(h.fn, h.owner, event, ...)
        if not ok and geterrorhandler then geterrorhandler()(err) end
    end
end

---------------------------------------------------------------------------
-- Look
---------------------------------------------------------------------------

Kit.colors = {
    bg     = { 0.055, 0.058, 0.072, 0.97 },
    header = { 0.035, 0.037, 0.047, 1 },
    card   = { 0.090, 0.094, 0.114, 1 },
    cardHi = { 0.120, 0.125, 0.150, 1 },
    border = { 0, 0, 0, 1 },
    line   = { 1, 1, 1, 0.06 },
    text   = { 0.94, 0.94, 0.96, 1 },
    muted  = { 0.60, 0.61, 0.67, 1 },
    faint  = { 0.40, 0.40, 0.45, 1 },
    gold   = { 1, 0.82, 0.30, 1 },
}

function Kit.Accent()
    local c = RC.Config and RC.Config.Accent
    if c then return c.r, c.g, c.b end
    return 0.15, 0.45, 0.85
end

function Kit.Font()
    return (RC.GetFont and RC:GetFont()) or STANDARD_TEXT_FONT
end

-- Sets the font directly: RC:SetFont drops OUTLINE, which counts on icons need.
function Kit.SetFont(fs, size, flags)
    fs:SetFont(Kit.Font(), size, flags or "")
end

function Kit.Text(parent, size, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(Kit.Font(), size or 12, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.75)
    local c = color or Kit.colors.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end

local function Solid(tex, c) tex:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
Kit.Solid = Solid

-- Flat background plus a 1px border drawn with textures (no templates).
function Kit.Skin(frame, bg, border)
    bg = bg or Kit.colors.card
    border = border or Kit.colors.border
    if not frame._rcBg then
        frame._rcBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        frame._rcBg:SetAllPoints()
        frame._rcBorder = {}
        for i = 1, 4 do frame._rcBorder[i] = frame:CreateTexture(nil, "BORDER", nil, 7) end
        local b = frame._rcBorder
        b[1]:SetPoint("TOPLEFT"); b[1]:SetPoint("TOPRIGHT"); b[1]:SetHeight(1)
        b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); b[2]:SetHeight(1)
        b[3]:SetPoint("TOPLEFT"); b[3]:SetPoint("BOTTOMLEFT"); b[3]:SetWidth(1)
        b[4]:SetPoint("TOPRIGHT"); b[4]:SetPoint("BOTTOMRIGHT"); b[4]:SetWidth(1)
    end
    Solid(frame._rcBg, bg)
    for i = 1, 4 do Solid(frame._rcBorder[i], border) end
end

function Kit.SetBg(frame, c)
    if frame._rcBg then Solid(frame._rcBg, c) end
end

function Kit.SetBorderColor(frame, r, g, b, a)
    if not frame._rcBorder then return end
    for i = 1, 4 do frame._rcBorder[i]:SetColorTexture(r, g, b, a or 1) end
end

-- Soft shadow around a window: four gradient strips outside its edges.
function Kit.Shadow(frame, size, alpha)
    size = size or 14
    local dark, clear = CreateColor(0, 0, 0, alpha or 0.5), CreateColor(0, 0, 0, 0)
    local function Strip(p1, r1, x1, y1, p2, r2, x2, y2, orient, from, to)
        local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
        t:SetColorTexture(1, 1, 1, 1)
        t:SetPoint(p1, frame, r1, x1, y1)
        t:SetPoint(p2, frame, r2, x2, y2)
        t:SetGradient(orient, from, to)
    end
    Strip("TOPLEFT", "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, -size, "VERTICAL", clear, dark)
    Strip("BOTTOMLEFT", "TOPLEFT", 0, 0, "TOPRIGHT", "TOPRIGHT", 0, size, "VERTICAL", dark, clear)
    Strip("TOPLEFT", "TOPRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", size, 0, "HORIZONTAL", dark, clear)
    Strip("TOPRIGHT", "TOPLEFT", 0, 0, "BOTTOMLEFT", "BOTTOMLEFT", -size, 0, "HORIZONTAL", clear, dark)
end

-- Flat button. style "accent" draws an accent outline and label (primary action).
function Kit.Button(parent, text, width, height, style)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 120, height or 24)
    Kit.Skin(b, Kit.colors.card)
    b.label = Kit.Text(b, 12)
    b.label:SetPoint("CENTER")
    b.label:SetJustifyH("CENTER")
    b.label:SetText(text or "")
    b.style = style
    function b:ApplyState(hover)
        local r, g, bb = Kit.Accent()
        if self.style == "accent" then
            Solid(self._rcBg, { r * (hover and 0.42 or 0.28), g * (hover and 0.42 or 0.28), bb * (hover and 0.42 or 0.28), 1 })
            Kit.SetBorderColor(self, r, g, bb, 1)
            self.label:SetTextColor(1, 1, 1)
        else
            Solid(self._rcBg, hover and Kit.colors.cardHi or Kit.colors.card)
            if hover then Kit.SetBorderColor(self, r, g, bb, 0.7) else Kit.SetBorderColor(self, 0, 0, 0, 1) end
        end
    end
    b:SetScript("OnEnter", function(self) self:ApplyState(true) end)
    b:SetScript("OnLeave", function(self) self:ApplyState(false) end)
    b:ApplyState(false)
    function b:SetText(t) self.label:SetText(t) end
    return b
end

-- Borderless text button (close "x").
function Kit.TextButton(parent, text, size)
    local b = CreateFrame("Button", nil, parent)
    b.label = Kit.Text(b, size or 14, Kit.colors.muted)
    b.label:SetPoint("CENTER")
    b.label:SetText(text)
    b:SetSize(b.label:GetStringWidth() + 12, (size or 14) + 10)
    b:SetScript("OnEnter", function(self) self.label:SetTextColor(unpack(Kit.colors.text)) end)
    b:SetScript("OnLeave", function(self) self.label:SetTextColor(unpack(Kit.colors.muted)) end)
    return b
end

-- Thin scrollbar for a plain ScrollFrame whose child is set later. Wheel scrolls 48px.
function Kit.Scroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:EnableMouseWheel(true)
    local track = CreateFrame("Frame", nil, parent)
    track:SetWidth(3)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 0)
    local trackTex = track:CreateTexture(nil, "BACKGROUND")
    trackTex:SetAllPoints()
    Solid(trackTex, Kit.colors.line)
    local thumb = CreateFrame("Button", nil, track)
    thumb:SetWidth(3)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()
    Solid(thumb.tex, Kit.colors.faint)
    scroll.track, scroll.thumb = track, thumb

    local function Max()
        local child = scroll:GetScrollChild()
        if not child then return 0 end
        return max(0, child:GetHeight() - scroll:GetHeight())
    end
    function scroll:UpdateThumb()
        local top, view = Max(), self:GetHeight()
        track:SetShown(top > 0 and self:IsShown())
        if top <= 0 then return end
        local trackH = track:GetHeight()
        local h = max(24, trackH * view / (view + top))
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(trackH - h) * (self:GetVerticalScroll() / top))
    end
    function scroll:ScrollTo(y)
        self:SetVerticalScroll(min(max(0, y), Max()))
        self:UpdateThumb()
    end
    scroll:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self:GetVerticalScroll() - delta * 48) end)
    scroll:SetScript("OnSizeChanged", function(self) self:UpdateThumb() end)
    thumb:SetScript("OnEnter", function() Solid(thumb.tex, Kit.colors.muted) end)
    thumb:SetScript("OnLeave", function() Solid(thumb.tex, Kit.colors.faint) end)
    thumb:SetScript("OnMouseDown", function()
        local _, startY = GetCursorPosition()
        local startScroll = scroll:GetVerticalScroll()
        local scale = track:GetEffectiveScale()
        thumb:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local range = track:GetHeight() - thumb:GetHeight()
            if range <= 0 then return end
            scroll:ScrollTo(startScroll + (startY - y) / scale * Max() / range)
        end)
    end)
    thumb:SetScript("OnMouseUp", function() thumb:SetScript("OnUpdate", nil) end)
    return scroll
end

---------------------------------------------------------------------------
-- Glow: thin lines with gaps travelling around a frame's edge
---------------------------------------------------------------------------

local Glow = {}
Glow.__index = Glow

local function PlaceSpan(tex, host, w, h, th, a, b)
    tex:ClearAllPoints()
    if a < w then
        tex:SetPoint("TOPLEFT", host, "TOPLEFT", a, 0)
        tex:SetSize(b - a, th)
    elseif a < w + h then
        tex:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, -(a - w))
        tex:SetSize(th, b - a)
    elseif a < 2 * w + h then
        tex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -(a - w - h), 0)
        tex:SetSize(b - a, th)
    else
        tex:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, a - 2 * w - h)
        tex:SetSize(th, b - a)
    end
    tex:Show()
end

local function NextCorner(s, w, h, p)
    return s < w and w or s < w + h and w + h or s < 2 * w + h and 2 * w + h or p
end

local function PlaceLine(line, host, w, h, th, s, len)
    local p = 2 * (w + h)
    s = s % p
    local e = s + len
    local cut = NextCorner(s, w, h, p)
    if e <= cut then
        PlaceSpan(line[1], host, w, h, th, s, e)
        line[2]:Hide()
    else
        PlaceSpan(line[1], host, w, h, th, s, cut)
        local rest = min(e - cut, len)
        local s2 = cut % p
        PlaceSpan(line[2], host, w, h, th, s2, min(s2 + rest, NextCorner(s2, w, h, p)))
    end
end

function Kit.Glow(target, opts)
    opts = opts or {}
    local pad = opts.pad or 2
    local host = CreateFrame("Frame", nil, target)
    host:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
    host:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
    host:SetFrameLevel(target:GetFrameLevel() + 5)
    host:Hide()
    local self = setmetatable({ host = host, n = opts.lines or 8, th = opts.thickness or 1, period = opts.period or 4, lines = {} }, Glow)
    for i = 1, self.n do
        self.lines[i] = { host:CreateTexture(nil, "OVERLAY"), host:CreateTexture(nil, "OVERLAY") }
    end
    local elapsed = 0
    host:SetScript("OnUpdate", function(_, dt)
        elapsed = (elapsed + dt) % self.period
        self:Paint(elapsed / self.period)
    end)
    return self
end

function Glow:Paint(phase)
    local w, h = self.host:GetSize()
    if not w or w <= 0 or h <= 0 then return end
    local p = 2 * (w + h)
    local step = p / self.n
    local len = min(step * 0.5, w, h)
    for i, line in ipairs(self.lines) do
        PlaceLine(line, self.host, w, h, self.th, phase * p + (i - 1) * step, len)
    end
end

function Glow:Start(r, g, b, a)
    for _, line in ipairs(self.lines) do
        line[1]:SetColorTexture(r, g, b, a or 1)
        line[2]:SetColorTexture(r, g, b, a or 1)
    end
    if not self.host:IsShown() then
        self.host:Show()
        self:Paint(0)
    end
end

function Glow:Stop()
    self.host:Hide()
end

---------------------------------------------------------------------------
-- Layout mode handles: a frame dragged in /rc layout, saved as a UIParent point
---------------------------------------------------------------------------

function Kit.Anchor(posKey, default)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame.posKey, frame.default = posKey, default
    frame:SetScript("OnDragStart", function(self)
        if RC:IsUILayoutUnlocked() and not InCombatLockdown() then
            self.rcMoving = true
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self.rcMoving then return end
        self.rcMoving = nil
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint(1)
        RC.db.profile[self.posKey] = { point, "UIParent", relativePoint, x, y }
    end)
    function frame:Place()
        local pos = RC.db.profile[self.posKey]
        if type(pos) ~= "table" then pos = self.default end
        self:ClearAllPoints()
        self:SetPoint(pos[1] or "CENTER", UIParent, pos[3] or "CENTER", tonumber(pos[4]) or 0, tonumber(pos[5]) or 0)
    end
    function frame:ResetPosition()
        RC.db.profile[self.posKey] = nil
        self:Place()
    end
    frame:Place()
    return frame
end

-- A thin accent outline shown on a handle while layout mode is on, so the drag area is visible.
function Kit.ShowHandle(frame, on)
    if not frame then return end
    if not frame._rcHandle then
        local h = CreateFrame("Frame", nil, frame)
        h:SetAllPoints()
        h:SetFrameLevel(frame:GetFrameLevel() + 20)
        Kit.Skin(h, { 0, 0, 0, 0 })
        frame._rcHandle = h
    end
    local r, g, b = Kit.Accent()
    Kit.SetBorderColor(frame._rcHandle, r, g, b, 0.9)
    frame._rcHandle:SetShown(on and true or false)
    frame:EnableMouse(on and true or false)
end

---------------------------------------------------------------------------
-- Items, money and prices
---------------------------------------------------------------------------

function Kit.QualityColor(q)
    q = Kit.Plain(q, 1)
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

function Kit.MoneyText(copper, size)
    copper = floor(copper or 0)
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        return C_CurrencyInfo.GetCoinTextureString(copper, size or 12)
    end
    return GetMoneyString(copper)
end

-- Rounded so a card stays short: whole gold from 1g, whole silver below.
function Kit.ShortMoney(copper, size)
    if copper >= 10000 then copper = floor(copper / 10000) * 10000
    elseif copper >= 100 then copper = floor(copper / 100) * 100 end
    return Kit.MoneyText(copper, size)
end

-- "[Name]" -> "Name": the brackets read as clutter on a card. It stays a link.
function Kit.NoBrackets(link) return (link:gsub("|h%[(.-)%]|h", "|h%1|h")) end

-- "ilvl 678 · Chest" for gear, nil for everything else or when the item isn't cached yet.
function Kit.GearLine(link, L)
    if not link or Kit.IsSecret(link) or not C_Item then return nil end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then return nil end
    local ilvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
    local slot = _G[equipLoc]
    if ilvl and slot then return string.format(L["ilvl %d · %s"], ilvl, slot) end
    if ilvl then return string.format(L["ilvl %d"], ilvl) end
    return slot
end

-- Prices (public APIs, neither addon is a dependency):
--   TradeSkillMaster: TSM_API.ToItemString(link), TSM_API.GetCustomPriceValue(source, itemString)
--     with "dbmarket" (your realm) and "dbregionmarketavg" (your region). Copper or nil.
--   Auctionator: Auctionator.API.v1.GetAuctionPriceByItemLink(callerID, link). Copper or nil.
--   Vendor: sellPrice from C_Item.GetItemInfo (nil until the item is cached).
local function Positive(v) return (type(v) == "number" and v > 0) and v or nil end

local function TSMPrice(source, link)
    if not (TSM_API and TSM_API.ToItemString and TSM_API.GetCustomPriceValue) then return nil end
    local ok, itemString = pcall(TSM_API.ToItemString, link)
    if not ok or not itemString then return nil end
    local ok2, value = pcall(TSM_API.GetCustomPriceValue, source, itemString)
    return ok2 and Positive(value) or nil
end

local function AuctionatorPrice(link)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemLink) then return nil end
    local ok, value = pcall(api.GetAuctionPriceByItemLink, "RaidControl", link)
    return ok and Positive(value) or nil
end

local function VendorPrice(link)
    if not (C_Item and C_Item.GetItemInfo) then return nil end
    return Positive((select(11, C_Item.GetItemInfo(link))))
end

Kit.TSMPrice, Kit.AuctionatorPrice, Kit.VendorPrice = TSMPrice, AuctionatorPrice, VendorPrice

-- Every price we can find for an item: { { label, copper, vendor? }, ... }.
function Kit.AllPrices(link, L)
    local list = {}
    local function Add(label, copper, vendor) if copper then list[#list + 1] = { label = label, copper = copper, vendor = vendor } end end
    Add(L["TSM realm market"], TSMPrice("dbmarket", link))
    Add(L["TSM region average"], TSMPrice("dbregionmarketavg", link))
    Add(L["Auctionator"], AuctionatorPrice(link))
    Add(L["Vendor"], VendorPrice(link), true)
    return list
end

-- The one price shown for an item, by the Loot history price setting: copper, isVendor.
function Kit.CardPrice(link)
    if not link or Kit.IsSecret(link) then return nil end
    local src = RC.db and RC.db.profile and RC.db.profile.lootHistoryPriceSource or "auto"
    if src == "tsm" then return TSMPrice("dbmarket", link) end
    if src == "tsmRegion" then return TSMPrice("dbregionmarketavg", link) end
    if src == "auctionator" then return AuctionatorPrice(link) end
    if src == "vendor" then return VendorPrice(link), true end
    local ah = TSMPrice("dbmarket", link) or TSMPrice("dbregionmarketavg", link) or AuctionatorPrice(link)
    if ah then return ah end
    return VendorPrice(link), true
end

function Kit.SourceLabel(L)
    local labels = { auto = L["Best available"], tsm = L["TSM realm market"], tsmRegion = L["TSM region average"],
        auctionator = L["Auctionator"], vendor = L["Vendor price"] }
    local src = RC.db and RC.db.profile and RC.db.profile.lootHistoryPriceSource or "auto"
    return labels[src] or labels.auto
end

-- Item tooltip plus every price we found, for one item and the whole stack.
function Kit.PriceTooltip(owner, link, qty, L, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link)
    local prices = Kit.AllPrices(link, L)
    qty = qty or 1
    if #prices > 0 then
        local r, g, b = Kit.Accent()
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(qty > 1 and string.format(L["RaidControl value (x%d)"], qty) or L["RaidControl value"], r, g, b)
        for _, p in ipairs(prices) do
            local right = Kit.MoneyText(p.copper, 12)
            if qty > 1 then right = Kit.MoneyText(p.copper * qty, 12) .. "  |cff8a8a99(" .. Kit.MoneyText(p.copper, 10) .. ")|r" end
            GameTooltip:AddDoubleLine(p.label, right, 0.8, 0.8, 0.85, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end
