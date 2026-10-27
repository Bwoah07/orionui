local _, ns = ...
local RC = ns.RC
local L = RC.L
---@class Loot : AceModule, AceEvent-3.0
local Loot = RC:NewModule("Loot", "AceEvent-3.0")

-- Our own loot window and group loot roll frames (flat dark panel, 1px border, accent colour,
-- quality-coloured names and icon borders, a travelling glow on epic and better). Replaces
-- Blizzard's LootFrame and GroupLootFrame1..4 while on.
--
-- How it plugs in:
--  * LootFrame registers LOOT_OPENED / LOOT_CLOSED itself. We unregister those two while on, so
--    Blizzard's window never opens, and register them again when switched off.
--  * START_LOOT_ROLL goes through Blizzard_Game's EventRouting to GroupLootContainer_AddRoll.
--    The container sits in the managed UIParent layout and touching it taints, so we never do.
--    Blizzard's roll frames keep running (their queue and CANCEL_LOOT_ROLL handling stay right);
--    we only make GroupLootFrame1..4 invisible and click-through and draw our own.
--  * The bind-on-pickup and roll confirmation popups come from Blizzard_Game's handlers, not
--    from the frames we hide, so they still appear.
--  * LootSlot, RollOnLoot and the loot getters have no restrictions; values still go through
--    Plain() before we compare or index with them.

local GetTime = GetTime
local floor, max, min = math.floor, math.max, math.min

local HEADER = 26
local FOOTER = 30
local ROW_PAD = 4
local ROLL_GAP = 4
local MAX_BLIZZARD_ROLLS = 4 -- GroupLootFrame1..4
local WHITE = "Interface\\Buttons\\WHITE8X8"

local ROLL_PASS, ROLL_NEED, ROLL_GREED, ROLL_TRANSMOG = 0, 1, 2, 4

local GLOW_FROM = { never = 99, rare = 3, epic = 4, legendary = 5 }

local DEFAULTS = {
    lootEnabled = true,
    lootPosition = "saved", -- or "cursor"
    lootWidth = 260,
    lootIconSize = 30,
    lootScale = 1,
    lootAllButton = true,
    lootShowItemLevel = true,
    lootRolls = true,
    lootRollWidth = 320,
    lootRollIconSize = 34,
    lootRollGrowUp = true,
    lootGlowFrom = "epic",
}

local BG = { 0.05, 0.06, 0.075, 0.96 }
local MUTED = { 0.62, 0.66, 0.70 }

local anchor, rollAnchor -- what layout mode moves
local win                -- the loot window
local rows, rollFrames = {}, {}
local activeRolls = {}   -- ordered list of roll frames on screen
local lootOpen, closing = false, false
local previewing, editing = false, false
local blizzLootOff, blizzRollsOff = false, false
local blizzMouse = {}    -- Blizzard roll widgets we made click-through -> true

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function DB()
    return RC.db.profile
end

local function Get(key)
    local value = RC.db and RC.db.profile and RC.db.profile[key]
    local fallback = DEFAULTS[key]
    if value == nil or (fallback ~= nil and type(value) ~= type(fallback)) then
        return fallback
    end
    return value
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Plain(v, fallback)
    if IsSecret(v) or v == nil then return fallback end
    return v
end

local function Accent()
    local c = RC.Config and RC.Config.Accent
    if c then return c.r, c.g, c.b end
    return 0.09, 0.52, 0.82
end

local function BorderColor()
    local c = RC.Config and RC.Config.Border
    if c then return c.r, c.g, c.b, c.a or 1 end
    return 0.1, 0.14, 0.17, 0.9
end

local function QualityOf(q)
    q = Plain(q, 1)
    if type(q) ~= "number" then return 1 end
    return q
end

local function QualityColor(q)
    q = QualityOf(q)
    local data = ColorManager and ColorManager.GetColorDataForItemQuality and ColorManager.GetColorDataForItemQuality(q)
    if data then
        if data.color then return data.color:GetRGB() end
        if data.r then return data.r, data.g, data.b end
    end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function Glows(q) return QualityOf(q) >= (GLOW_FROM[Get("lootGlowFrom")] or 99) end

-- Sets the font directly (RC:SetFont drops OUTLINE, which the stack counts need).
local function Font(fs, size, flags)
    fs:SetFont(RC:GetFont() or STANDARD_TEXT_FONT, size, flags or "")
end

local function Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    Font(fs, size)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    if color then fs:SetTextColor(color[1], color[2], color[3]) else fs:SetTextColor(1, 1, 1) end
    fs:SetJustifyH("LEFT")
    return fs
end

-- Flat fill plus a 1px border made of four textures.
local function Skin(frame, bg)
    if bg then
        frame.bg = frame:CreateTexture(nil, "BACKGROUND")
        frame.bg:SetAllPoints()
        frame.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
    end
    local r, g, b, a = BorderColor()
    frame.border = {}
    for i = 1, 4 do
        local t = frame:CreateTexture(nil, "BORDER", nil, 2)
        t:SetColorTexture(r, g, b, a)
        frame.border[i] = t
    end
    local top, bottom, left, right = unpack(frame.border)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT"); top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT"); bottom:SetHeight(1)
    left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT"); left:SetWidth(1)
    right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT"); right:SetWidth(1)
end

local function SetBorderColor(frame, r, g, b, a)
    for _, t in ipairs(frame.border) do t:SetColorTexture(r, g, b, a or 1) end
end

local function FlatButton(parent, label, width, height, accent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, height)
    local r, g, b = Accent()
    Skin(btn, accent and { r * 0.35, g * 0.35, b * 0.35, 0.95 } or { 0.08, 0.1, 0.12, 0.95 })
    if accent then SetBorderColor(btn, r, g, b, 0.9) end
    btn.text = Text(btn, 11)
    btn.text:SetPoint("CENTER")
    btn.text:SetJustifyH("CENTER")
    btn.text:SetText(label)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    return btn
end

-- "ilvl 678 · Chest" for gear, nil for everything else or when the item isn't cached yet.
local function GearLine(link)
    if not link or IsSecret(link) or not C_Item then return nil end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then return nil end
    local ilvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
    local slot = _G[equipLoc]
    if ilvl and slot then return string.format(L["ilvl %d · %s"], ilvl, slot) end
    if ilvl then return string.format(L["ilvl %d"], ilvl) end
    return slot
end

---------------------------------------------------------------------------
-- Glow: thin lines with gaps travelling around the edge
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

local function PlaceLine(line, host, w, h, th, s, len)
    local p = 2 * (w + h)
    s = s % p
    local e = s + len
    local cut = s < w and w or s < w + h and w + h or s < 2 * w + h and 2 * w + h or p
    if e <= cut then
        PlaceSpan(line[1], host, w, h, th, s, e)
        line[2]:Hide()
    else
        PlaceSpan(line[1], host, w, h, th, s, cut)
        local rest = min(e - cut, len)
        local s2 = cut % p
        local nextCut = s2 < w and w or s2 < w + h and w + h or s2 < 2 * w + h and 2 * w + h or p
        PlaceSpan(line[2], host, w, h, th, s2, min(s2 + rest, nextCut))
    end
end

local function NewGlow(target, lines, period, pad)
    local host = CreateFrame("Frame", nil, target)
    host:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
    host:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
    host:SetFrameLevel(target:GetFrameLevel() + 5)
    host:Hide()
    local self = setmetatable({ host = host, n = lines, period = period, lines = {} }, Glow)
    for i = 1, lines do
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
        PlaceLine(line, self.host, w, h, 1, phase * p + (i - 1) * step, len)
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

-- Icon box: 1px border in the quality colour, cropped icon, stack count, glow.
local function NewIcon(parent)
    local box = CreateFrame("Frame", nil, parent)
    Skin(box, { 0, 0, 0, 1 })
    box.tex = box:CreateTexture(nil, "ARTWORK")
    box.tex:SetPoint("TOPLEFT", 1, -1)
    box.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    box.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box.count = box:CreateFontString(nil, "OVERLAY")
    box.count:SetPoint("BOTTOMRIGHT", -1, 2)
    box.count:SetJustifyH("RIGHT")
    box.glow = NewGlow(box, 6, 3.5, 2)
    function box:Paint(texture, quality, count, borderR, borderG, borderB)
        self.tex:SetTexture(texture)
        local r, g, b = QualityColor(quality)
        SetBorderColor(self, borderR or r, borderG or g, borderB or b, 1)
        count = Plain(count, 1)
        Font(self.count, max(9, floor(self:GetHeight() * 0.36)), "OUTLINE")
        if type(count) == "number" and count > 1 then
            self.count:SetText(count)
            self.count:Show()
        else
            self.count:Hide()
        end
        if Glows(quality) then self.glow:Start(r, g, b, 0.9) else self.glow:Stop() end
    end
    return box
end

-- A layout-mode handle: dragged in /rc layout, saved as a UIParent point.
local function NewAnchor(posKey, default)
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
        DB()[self.posKey] = { point, "UIParent", relativePoint, x, y }
    end)
    return frame
end

local function PlaceAnchor(frame)
    local pos = DB()[frame.posKey]
    if type(pos) ~= "table" then pos = frame.default end
    frame:ClearAllPoints()
    frame:SetPoint(pos[1] or "CENTER", UIParent, pos[3] or "CENTER", tonumber(pos[4]) or 0, tonumber(pos[5]) or 0)
end

---------------------------------------------------------------------------
-- Loot window
---------------------------------------------------------------------------

local function RowOnEnter(row)
    row.hl:Show()
    if row.fake or not row.slot then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    local slotType = GetLootSlotType(row.slot)
    if slotType == Enum.LootSlotType.Currency then
        GameTooltip:SetLootCurrency(row.slot)
    elseif slotType == Enum.LootSlotType.Item then
        GameTooltip:SetLootItem(row.slot)
    else
        GameTooltip:Hide()
        return
    end
    if CursorUpdate then CursorUpdate(row) end
end

local function RowOnLeave(row)
    row.hl:Hide()
    GameTooltip:Hide()
    if ResetCursor then ResetCursor() end
end

local function RowOnClick(row)
    if row.fake then
        row.cleared = true
        Loot:LayoutWindow()
        return
    end
    if not row.slot then return end
    if IsModifiedClick() then
        HandleModifiedItemClick(GetLootSlotLink(row.slot))
    else
        StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION")
        LootSlot(row.slot)
    end
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, win.body)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- Quality wash: the quality colour fading out to the right, only on glowing drops.
    row.wash = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.wash:SetAllPoints()
    row.wash:SetColorTexture(1, 1, 1, 1)
    row.strip = row:CreateTexture(nil, "BORDER")
    row.strip:SetPoint("TOPLEFT")
    row.strip:SetPoint("BOTTOMLEFT")
    row.strip:SetWidth(2)
    row.hl = row:CreateTexture(nil, "HIGHLIGHT")
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(1, 1, 1, 0.05)
    row.hl:Hide()
    row.icon = NewIcon(row)
    row.name = Text(row, 13)
    row.name:SetWordWrap(false)
    row.sub = Text(row, 10, MUTED)
    row.sub:SetWordWrap(false)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:SetScript("OnClick", RowOnClick)
    rows[i] = row
    return row
end

-- Fills a row. info = { texture, name, count, quality, sub, quest, locked, money }
local function PaintRow(row, info)
    local size = Get("lootIconSize")
    row:SetHeight(size + 8)
    row.icon:SetSize(size, size)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", 8, 0)
    local br, bg, bb
    if info.quest then br, bg, bb = 1, 0.82, 0 end
    row.icon:Paint(info.texture, info.quality, info.count, br, bg, bb)
    row.icon.tex:SetVertexColor(1, info.locked and 0.2 or 1, info.locked and 0.2 or 1)

    row.name:ClearAllPoints()
    row.sub:ClearAllPoints()
    local textLeft = size + 16
    Font(row.name, 13)
    Font(row.sub, 10)
    row.name:SetText(info.name)
    if info.money then
        row.name:SetTextColor(1, 0.85, 0.35)
    else
        row.name:SetTextColor(QualityColor(info.quality))
    end
    if info.sub and info.sub ~= "" then
        row.name:SetPoint("BOTTOMLEFT", row, "LEFT", textLeft, 1)
        row.name:SetPoint("RIGHT", -8, 0)
        row.sub:SetPoint("TOPLEFT", row, "LEFT", textLeft, -2)
        row.sub:SetPoint("RIGHT", -8, 0)
        row.sub:SetText(info.sub)
        if info.quest then row.sub:SetTextColor(1, 0.82, 0) else row.sub:SetTextColor(MUTED[1], MUTED[2], MUTED[3]) end
        row.sub:Show()
    else
        row.name:SetPoint("LEFT", textLeft, 0)
        row.name:SetPoint("RIGHT", -8, 0)
        row.sub:Hide()
    end

    local r, g, b = QualityColor(info.quality)
    local glow = Glows(info.quality) and not info.money
    row.strip:SetColorTexture(r, g, b, 1)
    row.strip:SetShown(glow)
    row.wash:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.16), CreateColor(r, g, b, 0))
    row.wash:SetShown(glow)
end

-- Blizzard's window skips slots of type None the same way.
local function HasLoot(slot) return GetLootSlotType(slot) ~= Enum.LootSlotType.None end

local function SlotInfo(slot)
    local texture, item, quantity, currencyID, quality, locked, isQuestItem, questID, isActive, isCoin = GetLootSlotInfo(slot)
    if Plain(currencyID, nil) and CurrencyContainerUtil then
        item, texture, quantity, quality = CurrencyContainerUtil.GetCurrencyContainerInfo(currencyID, quantity, item, texture, quality)
    end
    local slotType = GetLootSlotType(slot)
    local info = { texture = texture, name = item, count = quantity, quality = quality, locked = Plain(locked, false) }
    if Plain(isCoin, false) or slotType == Enum.LootSlotType.Money then
        info.money = true
        info.count = 0
        if not IsSecret(item) and type(item) == "string" then info.name = item:gsub("\n", ", ") end
    elseif Plain(questID, nil) and not Plain(isActive, true) then
        info.quest, info.sub = true, L["Starts a quest"]
    elseif Plain(isQuestItem, false) or Plain(questID, nil) then
        info.quest, info.sub = true, L["Quest item"]
    elseif slotType == Enum.LootSlotType.Currency then
        info.sub = L["Currency"]
    else
        local q = QualityOf(quality)
        local gear = Get("lootShowItemLevel") and GearLine(GetLootSlotLink(slot))
        info.sub = gear or _G["ITEM_QUALITY" .. q .. "_DESC"]
    end
    return info
end

local FAKE_LOOT = {
    { texture = 135349, name = "Starforged Cleaver",        quality = 5, sub = "ilvl 691 · Two-Hand" },
    { texture = 132744, name = "Nightwatch Bulwark Plate",  quality = 4, sub = "ilvl 678 · Chest" },
    { texture = 133432, name = "Band of the Hunter's Belt", quality = 3, sub = "ilvl 671 · Finger" },
    { texture = 134939, name = "Shimmering Riftdust",       quality = 2, count = 14, sub = "Uncommon" },
    { texture = 134327, name = "Sealed Orders",             quality = 1, quest = true, sub = "Quest item" },
    { texture = 133784, name = "24 Gold, 61 Silver",        quality = 1, money = true },
}

-- Which entries are on screen: real loot slots, or the preview list.
local function Entries()
    local list = {}
    if lootOpen then
        for slot = 1, GetNumLootItems() do
            if HasLoot(slot) then list[#list + 1] = { slot = slot } end
        end
    elseif previewing or editing then
        for i, info in ipairs(FAKE_LOOT) do list[#list + 1] = { fake = i, info = info } end
    end
    return list
end

function Loot:BuildWindow()
    for _, row in ipairs(rows) do row:Hide(); row.slot, row.fake, row.cleared = nil, nil, nil end
    for i, e in ipairs(Entries()) do
        local row = Row(i)
        row.slot, row.fake, row.cleared = e.slot, e.fake, false
        PaintRow(row, e.info or SlotInfo(e.slot))
    end
    self:LayoutWindow()
end

function Loot:LayoutWindow()
    local y, shown = 0, 0
    for _, row in ipairs(rows) do
        if (row.slot or row.fake) and not row.cleared then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", win.body, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", win.body, "RIGHT", 0, 0)
            row:Show()
            y = y + row:GetHeight() + 1
            shown = shown + 1
        else
            row:Hide()
        end
    end
    win.empty:SetShown(shown == 0)
    if shown == 0 then y = 30 end
    local footer = Get("lootAllButton") and shown > 1
    win.lootAll:SetShown(footer)
    win.count:SetText(shown == 1 and L["1 item"] or string.format(L["%d items"], shown))
    win.count:SetShown(shown > 0)
    win:SetSize(Get("lootWidth"), HEADER + ROW_PAD + y + ROW_PAD + (footer and FOOTER or 0))
end

local function PlaceWindow()
    win:SetScale(Get("lootScale"))
    win:ClearAllPoints()
    if lootOpen and Get("lootPosition") == "cursor" and not editing then
        local x, y = GetCursorPosition()
        local s = win:GetEffectiveScale()
        -- First row lands under the cursor, like Blizzard's loot-under-mouse.
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 30, y / s + HEADER + ROW_PAD + Get("lootIconSize") / 2 + 4)
    else
        win:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    end
end

local function EnsureWindow()
    if win then return end
    anchor = NewAnchor("lootWindowPos", { "CENTER", "UIParent", "CENTER", -360, 120 })
    anchor:SetSize(Get("lootWidth"), HEADER)
    PlaceAnchor(anchor)

    -- Named so Escape closes it (UISpecialFrames needs a global name).
    win = CreateFrame("Frame", "RaidControlLootFrame", UIParent)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()
    Skin(win, BG)
    tinsert(UISpecialFrames, "RaidControlLootFrame")
    Loot.frame = win

    local r, g, b = Accent()
    win.title = Text(win, 13)
    win.title:SetPoint("LEFT", win, "TOPLEFT", 10, -HEADER / 2)
    win.title:SetTextColor(r, g, b)
    win.close = CreateFrame("Button", nil, win)
    win.close:SetSize(18, 18)
    win.close:SetPoint("RIGHT", win, "TOPRIGHT", -4, -HEADER / 2)
    win.close.text = Text(win.close, 14, MUTED)
    win.close.text:SetPoint("CENTER")
    win.close.text:SetText("x")
    win.close:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 1, 1) end)
    win.close:SetScript("OnLeave", function(self) self.text:SetTextColor(MUTED[1], MUTED[2], MUTED[3]) end)
    win.close:SetScript("OnClick", function() win:Hide() end)
    win.count = Text(win, 10, MUTED)
    win.count:SetPoint("RIGHT", win.close, "LEFT", -2, 0)
    win.line = win:CreateTexture(nil, "BORDER")
    win.line:SetPoint("TOPLEFT", 1, -HEADER)
    win.line:SetPoint("TOPRIGHT", -1, -HEADER)
    win.line:SetHeight(1)
    win.line:SetColorTexture(r, g, b, 0.8)

    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT", 1, -(HEADER + ROW_PAD))
    win.body:SetPoint("TOPRIGHT", -1, -(HEADER + ROW_PAD))
    win.body:SetHeight(1)
    win.empty = Text(win.body, 12, MUTED)
    win.empty:SetPoint("TOP", 0, -8)
    win.empty:SetText(L["Nothing to loot"])

    win.lootAll = FlatButton(win, L["Loot all"], 90, 20, true)
    win.lootAll:SetPoint("BOTTOMRIGHT", -6, 6)
    win.lootAll:SetScript("OnClick", function()
        if lootOpen then
            for slot = GetNumLootItems(), 1, -1 do
                if HasLoot(slot) then LootSlot(slot) end
            end
        else
            for _, row in ipairs(rows) do row.cleared = true end
            Loot:LayoutWindow()
        end
    end)

    win.fade = win:CreateAnimationGroup()
    local a = win.fade:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.12)

    win:SetScript("OnHide", function()
        StaticPopup_Hide("CONFIRM_LOOT_DISTRIBUTION")
        if lootOpen and not closing then CloseLoot() end
        previewing = false
    end)
end

function Loot:ShowWindow()
    EnsureWindow()
    anchor:SetSize(Get("lootWidth"), HEADER)
    if lootOpen then
        win.title:SetText(IsFishingLoot() and L["Fishing"] or L["Loot"])
    else
        win.title:SetText(editing and L["Loot (layout mode)"] or L["Loot (preview)"])
    end
    self:BuildWindow()
    PlaceWindow()
    if not win:IsShown() then
        win:Show()
        win.fade:Play()
    end
end

function Loot:HideWindow()
    if not win then return end
    closing = true
    win:Hide()
    closing = false
end

---------------------------------------------------------------------------
-- Loot events
---------------------------------------------------------------------------

function Loot:LOOT_OPENED(_, _, isFromItem)
    lootOpen = true
    previewing = false
    self:ShowWindow()
    if isFromItem then
        PlaySound(SOUNDKIT.UI_CONTAINER_ITEM_OPEN)
    elseif IsFishingLoot() then
        PlaySound(SOUNDKIT.FISHING_REEL_IN)
    elseif GetNumLootItems() == 0 then
        PlaySound(SOUNDKIT.LOOT_WINDOW_OPEN_EMPTY)
    end
end

function Loot:LOOT_CLOSED()
    lootOpen = false
    StaticPopup_Hide("LOOT_BIND")
    if editing then self:ShowWindow() else self:HideWindow() end
end

local function FindRow(slot)
    for _, row in ipairs(rows) do
        if row.slot == slot then return row end
    end
end

function Loot:LOOT_SLOT_CLEARED(_, slot)
    local row = FindRow(slot)
    if row then
        row.cleared = true
        self:LayoutWindow()
    end
end

function Loot:LOOT_SLOT_CHANGED(_, slot)
    local row = FindRow(slot)
    if row then PaintRow(row, SlotInfo(slot)) end
end

---------------------------------------------------------------------------
-- Roll frames
---------------------------------------------------------------------------

local ROLL_BUTTONS = {
    { key = "need",     rollType = ROLL_NEED,     atlas = "lootroll-toast-icon-need",     tip = NEED },
    { key = "greed",    rollType = ROLL_GREED,    atlas = "lootroll-toast-icon-greed",    tip = GREED },
    { key = "transmog", rollType = ROLL_TRANSMOG, atlas = "lootroll-toast-icon-transmog", tip = TRANSMOGRIFICATION },
    { key = "pass",     rollType = ROLL_PASS,     atlas = "lootroll-toast-icon-pass",     tip = PASS },
}

local function RemoveRoll(rf)
    for i, f in ipairs(activeRolls) do
        if f == rf then table.remove(activeRolls, i) break end
    end
    rf:Hide()
    rf.rollID, rf.fake, rf.result = nil, nil, nil
    if rf.resultTimer then rf.resultTimer:Cancel(); rf.resultTimer = nil end
    Loot:LayoutRolls()
end

local function RollButtonOnClick(btn)
    local rf = btn:GetParent()
    if rf.fake then RemoveRoll(rf) return end
    if rf.rollID then RollOnLoot(rf.rollID, btn.rollType) end
end

local function RollButtonOnEnter(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, btn.tip)
    if not btn:IsEnabled() and btn.reason then
        GameTooltip:AddLine(btn.reason, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
    end
    GameTooltip:Show()
end

local function SetRollButton(btn, enabled, reason)
    btn:SetEnabled(enabled)
    btn:SetAlpha(enabled and 1 or 0.35)
    btn:GetNormalTexture():SetDesaturated(not enabled)
    btn.reason = (not enabled) and reason or nil
end

local function RollOnUpdate(rf)
    if rf.result then return end
    local frac
    if rf.fake then
        frac = 1 - ((GetTime() - rf.fakeStart) % 20) / 20
    elseif rf.rollID then
        local left = Plain(GetLootRollTimeLeft(rf.rollID), nil)
        if type(left) ~= "number" or not rf.rollTime or rf.rollTime <= 0 then return end
        frac = max(0, min(1, left / rf.rollTime))
    else
        return
    end
    rf.timer:SetValue(frac)
    if frac < 0.2 then rf.timer:SetStatusBarColor(0.85, 0.25, 0.2) else rf.timer:SetStatusBarColor(Accent()) end
end

local function NewRollFrame()
    local rf = CreateFrame("Frame", nil, UIParent)
    rf:SetFrameStrata("DIALOG")
    rf:SetToplevel(true)
    rf:EnableMouse(true)
    rf:Hide()
    Skin(rf, BG)
    rf.wash = rf:CreateTexture(nil, "BACKGROUND", nil, 1)
    rf.wash:SetPoint("TOPLEFT", 1, -1)
    rf.wash:SetPoint("BOTTOMRIGHT", -1, 1)
    rf.wash:SetColorTexture(1, 1, 1, 1)
    rf.strip = rf:CreateTexture(nil, "BORDER")
    rf.strip:SetPoint("TOPLEFT", 1, -1)
    rf.strip:SetPoint("BOTTOMLEFT", 1, 1)
    rf.strip:SetWidth(2)

    rf.icon = NewIcon(rf)
    rf.icon:EnableMouse(true)
    rf.icon:SetScript("OnEnter", function(self)
        local p = self:GetParent()
        if p.fake or not p.rollID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetLootRollItem(p.rollID)
        if CursorUpdate then CursorUpdate(self) end
    end)
    rf.icon:SetScript("OnLeave", function() GameTooltip:Hide(); if ResetCursor then ResetCursor() end end)
    rf.icon:SetScript("OnMouseUp", function(self)
        local p = self:GetParent()
        if p.rollID and IsModifiedClick() then HandleModifiedItemClick(GetLootRollItemLink(p.rollID)) end
    end)

    rf.name = Text(rf, 13)
    rf.name:SetWordWrap(false)
    rf.sub = Text(rf, 10, MUTED)
    rf.sub:SetWordWrap(false)

    rf.buttons = {}
    for _, def in ipairs(ROLL_BUTTONS) do
        local btn = CreateFrame("Button", nil, rf)
        btn:SetMotionScriptsWhileDisabled(true)
        btn:SetNormalAtlas(def.atlas .. "-up")
        btn:SetHighlightAtlas(def.atlas .. "-highlight", "ADD")
        btn:SetPushedAtlas(def.atlas .. "-down")
        btn.rollType, btn.tip = def.rollType, def.tip
        btn:SetScript("OnClick", RollButtonOnClick)
        btn:SetScript("OnEnter", RollButtonOnEnter)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rf.buttons[def.key] = btn
    end

    rf.resultText = rf:CreateFontString(nil, "OVERLAY")
    rf.resultText:Hide()

    rf.timer = CreateFrame("StatusBar", nil, rf)
    rf.timer:SetPoint("BOTTOMLEFT", 1, 1)
    rf.timer:SetPoint("BOTTOMRIGHT", -1, 1)
    rf.timer:SetHeight(2)
    rf.timer:SetStatusBarTexture(WHITE)
    rf.timer:SetStatusBarColor(Accent())
    rf.timer:SetMinMaxValues(0, 1)
    rf:SetScript("OnUpdate", RollOnUpdate)
    return rf
end

local function GetRollFrame()
    for _, rf in ipairs(rollFrames) do
        if not rf:IsShown() then return rf end
    end
    local rf = NewRollFrame()
    rollFrames[#rollFrames + 1] = rf
    return rf
end

-- Lays out one roll frame for the current settings and fills it.
-- info = { texture, name, count, quality, bop, canNeed, canGreed, canTransmog, reasonNeed, reasonGreed, link }
local function PaintRoll(rf, info)
    local size = Get("lootRollIconSize")
    rf:SetScale(Get("lootScale"))
    rf:SetSize(Get("lootRollWidth"), size + 10)
    rf.icon:SetSize(size, size)
    rf.icon:ClearAllPoints()
    rf.icon:SetPoint("LEFT", 6, 1)
    rf.icon:Paint(info.texture, info.quality, info.count)

    local r, g, b = QualityColor(info.quality)
    local glow = Glows(info.quality)
    rf.strip:SetColorTexture(r, g, b, 1)
    rf.strip:SetShown(glow)
    rf.wash:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0.16), CreateColor(r, g, b, 0))
    rf.wash:SetShown(glow)

    -- Buttons, right to left: Pass, Greed or Transmog, Need.
    local bsize = min(28, size - 4)
    local need, greed, tmog, pass = rf.buttons.need, rf.buttons.greed, rf.buttons.transmog, rf.buttons.pass
    for _, btn in pairs(rf.buttons) do btn:SetSize(bsize, bsize); btn:ClearAllPoints(); btn:Show() end
    pass:SetPoint("RIGHT", rf, "RIGHT", -6, 1)
    local mid, other = greed, tmog
    if info.canTransmog then mid, other = tmog, greed end
    other:Hide()
    mid:SetPoint("RIGHT", pass, "LEFT", -4, 0)
    need:SetPoint("RIGHT", mid, "LEFT", -4, 0)
    SetRollButton(need, info.canNeed, info.reasonNeed)
    SetRollButton(greed, info.canGreed, info.reasonGreed)
    SetRollButton(tmog, true)
    SetRollButton(pass, true)

    local left = size + 14
    Font(rf.name, 13)
    Font(rf.sub, 10)
    rf.name:ClearAllPoints()
    rf.name:SetPoint("BOTTOMLEFT", rf, "LEFT", left, 2)
    rf.name:SetPoint("RIGHT", need, "LEFT", -6, 0)
    rf.name:SetText(info.name)
    rf.name:SetTextColor(r, g, b)
    rf.sub:ClearAllPoints()
    rf.sub:SetPoint("TOPLEFT", rf, "LEFT", left, -1)
    rf.sub:SetPoint("RIGHT", need, "LEFT", -6, 0)
    local parts = {}
    local gear = Get("lootShowItemLevel") and GearLine(info.link)
    if gear then parts[#parts + 1] = gear end
    if info.bop then parts[#parts + 1] = ITEM_BIND_ON_PICKUP end
    rf.sub:SetText(info.sub or table.concat(parts, " · "))

    rf.resultText:Hide()
    rf.timer:SetValue(1)
    rf.timer:SetStatusBarColor(Accent())
end

function Loot:LayoutRolls()
    if not rollAnchor then return end
    local size = Get("lootRollIconSize")
    rollAnchor:SetSize(Get("lootRollWidth"), size + 10)
    local step = size + 10 + ROLL_GAP
    local growUp = Get("lootRollGrowUp")
    for i, rf in ipairs(activeRolls) do
        rf:ClearAllPoints()
        if growUp then
            rf:SetPoint("BOTTOM", rollAnchor, "BOTTOM", 0, (i - 1) * step)
        else
            rf:SetPoint("TOP", rollAnchor, "TOP", 0, -(i - 1) * step)
        end
    end
end

local function AddRoll(rf)
    activeRolls[#activeRolls + 1] = rf
    Loot:LayoutRolls()
    rf:Show()
end

local function Reason(code)
    code = Plain(code, nil)
    if type(code) ~= "number" then return nil end
    return _G["LOOT_ROLL_INELIGIBLE_REASON" .. code]
end

function Loot:START_LOOT_ROLL(_, rollID, rollTime)
    if not Get("lootRolls") then return end
    local texture, name, count, quality, bop, canNeed, canGreed, _, reasonNeed, reasonGreed, _, _, canTransmog = GetLootRollItemInfo(rollID)
    if not IsSecret(name) and name == nil then return end -- the roll is already over
    local rf = GetRollFrame()
    rf.rollID, rf.rollTime, rf.fake, rf.result = rollID, Plain(rollTime, 0), nil, nil
    PaintRoll(rf, {
        texture = texture, name = name, count = count, quality = quality, bop = Plain(bop, false),
        canNeed = Plain(canNeed, true), canGreed = Plain(canGreed, true), canTransmog = Plain(canTransmog, false),
        reasonNeed = Reason(reasonNeed),
        reasonGreed = Reason(reasonGreed),
        link = GetLootRollItemLink(rollID),
    })
    AddRoll(rf)
end

local function FindRoll(rollID)
    for _, rf in ipairs(activeRolls) do
        if rf.rollID == rollID then return rf end
    end
end

function Loot:CANCEL_LOOT_ROLL(_, rollID)
    local rf = FindRoll(rollID)
    if rf and not rf.result then RemoveRoll(rf) end -- a shown need result stays until its timer ends
end

function Loot:CANCEL_ALL_LOOT_ROLLS()
    for i = #activeRolls, 1, -1 do
        if not activeRolls[i].fake then RemoveRoll(activeRolls[i]) end
    end
end

-- Need rolls on main-spec items report the number; show it on the frame for a moment.
function Loot:MAIN_SPEC_NEED_ROLL(_, rollID, roll, isWinning)
    local rf = FindRoll(rollID)
    if not rf then return end
    rf.result = true
    for _, btn in pairs(rf.buttons) do btn:Hide() end
    Font(rf.resultText, 20, "OUTLINE")
    rf.resultText:ClearAllPoints()
    rf.resultText:SetPoint("RIGHT", rf, "RIGHT", -12, 1)
    rf.resultText:SetText(Plain(roll, "?"))
    local winning = Plain(isWinning, false)
    if winning then rf.resultText:SetTextColor(0.3, 0.9, 0.4) else rf.resultText:SetTextColor(0.9, 0.3, 0.3) end
    rf.resultText:Show()
    rf.timer:SetValue(0)
    PlaySound(winning and SOUNDKIT.UI_NEED_ROLL_POSITIVE or SOUNDKIT.UI_NEED_ROLL_NEGATIVE)
    rf.resultTimer = C_Timer.NewTimer(4, function()
        rf.resultTimer = nil
        if rf.rollID == rollID then RemoveRoll(rf) end
    end)
end

local FAKE_ROLLS = {
    { texture = 135349, name = "Starforged Cleaver", quality = 5, bop = true, canNeed = true, canGreed = true, sub = "ilvl 691 · Two-Hand · Bind on Pickup" },
    { texture = 132744, name = "Nightwatch Bulwark Plate", quality = 4, bop = true, canNeed = false, canGreed = true, canTransmog = true,
      reasonNeed = "You can't need this item.", sub = "ilvl 678 · Chest · Bind on Pickup" },
}

local function ShowFakeRolls()
    local now = GetTime()
    for i, info in ipairs(FAKE_ROLLS) do
        local rf = GetRollFrame()
        rf.rollID, rf.fake, rf.result, rf.fakeStart = nil, i, nil, now - i * 4
        PaintRoll(rf, info)
        AddRoll(rf)
    end
end

local function ClearFakeRolls()
    for i = #activeRolls, 1, -1 do
        if activeRolls[i].fake then RemoveRoll(activeRolls[i]) end
    end
end

local function EnsureRollAnchor()
    if rollAnchor then return end
    rollAnchor = NewAnchor("lootRollPos", { "CENTER", "UIParent", "CENTER", 0, 260 })
    rollAnchor:SetSize(320, 44)
    PlaceAnchor(rollAnchor)
    Loot.rollAnchor = rollAnchor
end

---------------------------------------------------------------------------
-- Blizzard's frames
---------------------------------------------------------------------------

local function SetBlizzardLoot(off)
    local f = _G.LootFrame
    if not f or off == blizzLootOff then return end
    if off then
        f:UnregisterEvent("LOOT_OPENED")
        f:UnregisterEvent("LOOT_CLOSED")
        if f:IsShown() then HideUIPanel(f) end
    else
        f:RegisterEvent("LOOT_OPENED")
        f:RegisterEvent("LOOT_CLOSED")
    end
    blizzLootOff = off
end

-- Widgets on a Blizzard roll frame that take the mouse.
local function BlizzardRollWidgets(f)
    local list = { f, f.IconFrame }
    for _, btn in ipairs(f.LootButtons or {}) do list[#list + 1] = btn end
    return list
end

local hookedShow = {}

local function SetBlizzardRolls(off)
    if off == blizzRollsOff then return end
    blizzRollsOff = off
    for i = 1, MAX_BLIZZARD_ROLLS do
        local f = _G["GroupLootFrame" .. i]
        if f then
            f:SetAlpha(off and 0 or 1)
            for _, w in ipairs(BlizzardRollWidgets(f)) do
                if off and w:IsMouseEnabled() then
                    w:EnableMouse(false)
                    blizzMouse[w] = true
                elseif not off and blizzMouse[w] then
                    w:EnableMouse(true)
                    blizzMouse[w] = nil
                end
            end
            -- Skins repaint these frames on show; keep them invisible.
            if not hookedShow[f] then
                hookedShow[f] = true
                f:HookScript("OnShow", function(self)
                    if blizzRollsOff then self:SetAlpha(0) end
                end)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Preview, layout mode, lifecycle
---------------------------------------------------------------------------

-- /rc loot: a sample window and two sample rolls for 15 seconds.
function Loot:Preview()
    if not self.active then
        RC:Print(L["The loot window is switched off (Interface > Loot Window)."])
        return
    end
    if lootOpen then return end
    previewing = true
    self:ShowWindow()
    ClearFakeRolls()
    if Get("lootRolls") then ShowFakeRolls() end
    if self.previewTimer then self.previewTimer:Cancel() end
    self.previewTimer = C_Timer.NewTimer(15, function()
        self.previewTimer = nil
        if editing then return end
        ClearFakeRolls()
        if previewing then
            previewing = false
            if not lootOpen then self:HideWindow() end
        end
    end)
end

function Loot:BeginLayoutMode()
    if not self.active then return end
    editing = true
    anchor:EnableMouse(true)
    rollAnchor:EnableMouse(true)
    if not lootOpen then self:ShowWindow() end
    -- The window sits on top of its anchor; let the drag reach the anchor through it.
    win:EnableMouse(false)
    ClearFakeRolls()
    ShowFakeRolls()
    for _, rf in ipairs(activeRolls) do rf:EnableMouse(false) end
end

function Loot:EndLayoutMode()
    if not editing then return end
    editing = false
    if anchor then anchor:EnableMouse(false) end
    if rollAnchor then rollAnchor:EnableMouse(false) end
    if win then win:EnableMouse(true) end
    for _, rf in ipairs(rollFrames) do rf:EnableMouse(true) end
    ClearFakeRolls()
    if lootOpen then self:ShowWindow() else self:HideWindow() end
end

-- Settings changed: switch on/off and redraw.
function Loot:Refresh()
    local want = Get("lootEnabled") == true
    if InCombatLockdown() then
        self.refreshAfterCombat = true
        return
    end
    if want and not self.active then
        self:Activate()
    elseif not want and self.active then
        self:Deactivate()
    end
    if not self.active then return end
    SetBlizzardRolls(Get("lootRolls"))
    anchor:SetSize(Get("lootWidth"), HEADER)
    rollAnchor:SetSize(Get("lootRollWidth"), Get("lootRollIconSize") + 10)
    if win:IsShown() then self:ShowWindow() end
    for _, rf in ipairs(activeRolls) do
        if rf.fake then PaintRoll(rf, FAKE_ROLLS[rf.fake]) end
    end
    self:LayoutRolls()
end

function Loot:ResetPosition()
    DB().lootWindowPos = nil
    DB().lootRollPos = nil
    if anchor then PlaceAnchor(anchor) end
    if rollAnchor then PlaceAnchor(rollAnchor) end
    if win and win:IsShown() then self:ShowWindow() end
    self:LayoutRolls()
end

function Loot:Activate()
    EnsureWindow()
    EnsureRollAnchor()
    self.active = true
    SetBlizzardLoot(true)
    SetBlizzardRolls(Get("lootRolls"))
    self:RegisterEvent("LOOT_OPENED")
    self:RegisterEvent("LOOT_CLOSED")
    self:RegisterEvent("LOOT_SLOT_CLEARED")
    self:RegisterEvent("LOOT_SLOT_CHANGED")
    self:RegisterEvent("START_LOOT_ROLL")
    self:RegisterEvent("CANCEL_LOOT_ROLL")
    self:RegisterEvent("CANCEL_ALL_LOOT_ROLLS")
    self:RegisterEvent("MAIN_SPEC_NEED_ROLL")
end

function Loot:Deactivate()
    self.active = false
    for _, event in ipairs({ "LOOT_OPENED", "LOOT_CLOSED", "LOOT_SLOT_CLEARED", "LOOT_SLOT_CHANGED",
        "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS", "MAIN_SPEC_NEED_ROLL" }) do
        self:UnregisterEvent(event)
    end
    editing, previewing = false, false
    for i = #activeRolls, 1, -1 do RemoveRoll(activeRolls[i]) end
    -- Closing our window also closes loot that is open right now (CloseLoot in OnHide), so the
    -- game isn't left with loot open and no window; the next loot opens in Blizzard's.
    if win and win:IsShown() then win:Hide() end
    lootOpen = false
    SetBlizzardLoot(false)
    SetBlizzardRolls(false)
end

function Loot:PLAYER_REGEN_ENABLED()
    if self.refreshAfterCombat then
        self.refreshAfterCombat = nil
        self:Refresh()
    end
end

function Loot:OnEnable()
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:Refresh()
end

function Loot:OnDisable()
    if self.active then self:Deactivate() end
end
