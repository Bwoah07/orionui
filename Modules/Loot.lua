local _, ns = ...
local RC = ns.RC
local L = RC.L
local Kit = ns.LootKit
---@class Loot : AceModule, AceEvent-3.0
local Loot = RC:NewModule("Loot", "AceEvent-3.0")

-- Our own loot window and group loot roll frames in place of Blizzard's. Every drop is a card like
-- the Loot history ones: quality strip and wash, a big icon with a quality border, the name with
-- what it is under it, the count and its auction value on the right. Epic and better get a
-- travelling glow. A shadowed panel with a dark header and an accent line.
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

local HEADER = 32
local FOOTER = 34
local PAD = 6       -- inside the panel, around the cards
local GAP = 4       -- between cards
local ROLL_GAP = 6
local MAX_BLIZZARD_ROLLS = 4 -- GroupLootFrame1..4
local WHITE = "Interface\\Buttons\\WHITE8X8"

local ROLL_PASS, ROLL_NEED, ROLL_GREED, ROLL_TRANSMOG = 0, 1, 2, 4

local GLOW_FROM = { never = 99, rare = 3, epic = 4, legendary = 5 }

local DEFAULTS = {
    lootEnabled = true,
    lootPosition = "saved", -- or "cursor"
    lootWidth = 300,
    lootIconSize = 34,
    lootScale = 1,
    lootAllButton = true,
    lootShowItemLevel = true,
    lootShowValue = true,
    lootRolls = true,
    lootRollWidth = 340,
    lootRollIconSize = 38,
    lootRollGrowUp = true,
    lootGlowFrom = "epic",
}
Loot.DEFAULTS = DEFAULTS
local db = Kit.Settings(DEFAULTS)

local C = Kit.colors
local Plain, IsSecret = Kit.Plain, Kit.IsSecret
local QualityColor = Kit.QualityColor

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

local function QualityOf(q)
    q = Plain(q, 1)
    if type(q) ~= "number" then return 1 end
    return q
end

local function Glows(q) return QualityOf(q) >= (GLOW_FROM[db.lootGlowFrom] or 99) end

-- Card dressing: strip and wash in the quality colour; stronger for drops that glow.
local function Dress(card, quality, money)
    local r, g, b = QualityColor(quality)
    if money then r, g, b = C.gold[1], C.gold[2], C.gold[3] end
    local q = QualityOf(quality)
    local glow = Glows(quality) and not money
    card.strip:SetColorTexture(r, g, b, 1)
    card.strip:SetWidth(glow and 3 or 2)
    card.strip:SetShown(money or q >= 1)
    local washA = glow and 0.30 or (q >= 2 or money) and 0.15 or 0.06
    card.wash:SetGradient("HORIZONTAL", CreateColor(r, g, b, washA), CreateColor(r, g, b, 0))
    card.qr, card.qg, card.qb = r, g, b
    return r, g, b, glow
end

-- Icon box: 1px quality border, cropped icon, stack count.
local function NewIcon(parent)
    local box = CreateFrame("Frame", nil, parent)
    Kit.Skin(box, { 0, 0, 0, 1 })
    box.tex = box:CreateTexture(nil, "ARTWORK")
    box.tex:SetPoint("TOPLEFT", 1, -1)
    box.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    box.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box.count = box:CreateFontString(nil, "OVERLAY")
    box.count:SetPoint("BOTTOMRIGHT", -2, 2)
    box.count:SetJustifyH("RIGHT")
    function box:Paint(texture, count, r, g, b)
        self.tex:SetTexture(texture or 134400)
        Kit.SetBorderColor(self, r, g, b, 1)
        count = Plain(count, 1)
        Kit.SetFont(self.count, max(9, floor(self:GetHeight() * 0.34)), "OUTLINE")
        if type(count) == "number" and count > 1 then
            self.count:SetText(count)
            self.count:Show()
        else
            self.count:Hide()
        end
    end
    return box
end

-- Card base shared by loot rows and roll frames.
local function CardBase(card, bg)
    Kit.Skin(card, bg or C.card)
    card.wash = card:CreateTexture(nil, "BACKGROUND", nil, 1)
    card.wash:SetPoint("TOPLEFT", 1, -1)
    card.wash:SetPoint("BOTTOMRIGHT", -1, 1)
    card.wash:SetColorTexture(1, 1, 1, 1)
    card.strip = card:CreateTexture(nil, "BORDER")
    card.strip:SetPoint("TOPLEFT", 1, -1)
    card.strip:SetPoint("BOTTOMLEFT", 1, 1)
    card.strip:SetWidth(2)
    card.icon = NewIcon(card)
    card.glow = Kit.Glow(card, { lines = 8, thickness = 1, period = 5, pad = 1 })
    card.name = Kit.Text(card, 13)
    card.name:SetWordWrap(false)
    card.sub = Kit.Text(card, 10, C.muted)
    card.sub:SetWordWrap(false)
end

---------------------------------------------------------------------------
-- Loot window
---------------------------------------------------------------------------

local function RowOnEnter(row)
    Kit.SetBg(row, C.cardHi)
    Kit.SetBorderColor(row, row.qr or 0.3, row.qg or 0.3, row.qb or 0.3, 0.9)
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
    Kit.SetBg(row, C.card)
    Kit.SetBorderColor(row, 0, 0, 0, 1)
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
    CardBase(row)
    row.count = Kit.Text(row, 13)
    row.count:SetJustifyH("RIGHT")
    row.value = Kit.Text(row, 10)
    row.value:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:SetScript("OnClick", RowOnClick)
    rows[i] = row
    return row
end

-- Fills a row. info = { texture, name, count, quality, sub, quest, locked, money, link }
local function PaintRow(row, info)
    local size = db.lootIconSize
    local h = size + 10
    row:SetHeight(h)
    row.icon:SetSize(size, size)
    row.icon:ClearAllPoints()
    row.icon:SetPoint("LEFT", 7, 0)

    local r, g, b, glow = Dress(row, info.quality, info.money)
    local br, bg, bb = r, g, b
    if info.quest then br, bg, bb = 1, 0.82, 0 end
    row.icon:Paint(info.texture, nil, br, bg, bb)
    row.icon.tex:SetVertexColor(1, info.locked and 0.25 or 1, info.locked and 0.25 or 1)
    if glow then row.glow:Start(r, g, b, 0.9) else row.glow:Stop() end

    -- Right column: x4 on top, the stack's value under it.
    local count = Plain(info.count, 1)
    if type(count) ~= "number" then count = 1 end
    row.count:SetText("x" .. count)
    row.count:SetShown(count > 1 and not info.money)
    local unit, vendor
    if db.lootShowValue and info.link and not info.money then unit, vendor = Kit.CardPrice(info.link) end
    if info.unit then unit, vendor = info.unit, info.vendor end
    row.unitValue = unit and unit * count or 0
    row.vendorValue = vendor
    if unit and db.lootShowValue then
        row.value:SetText(Kit.ShortMoney(unit * count, 10))
        if vendor then row.value:SetTextColor(0.55, 0.55, 0.6) else row.value:SetTextColor(1, 1, 1) end
        row.value:Show()
    else
        row.value:Hide()
    end

    Kit.SetFont(row.name, 13)
    Kit.SetFont(row.sub, 10)
    Kit.SetFont(row.count, 13, "OUTLINE")
    Kit.SetFont(row.value, 10)
    row.name:SetText(info.name)
    if info.money then
        row.name:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
    else
        row.name:SetTextColor(r, g, b)
    end
    local textLeft = 7 + size + 10
    local rightW = 0
    if row.count:IsShown() then rightW = max(rightW, row.count:GetUnboundedStringWidth()) end
    if row.value:IsShown() then rightW = max(rightW, row.value:GetUnboundedStringWidth()) end
    local rightPad = rightW > 0 and rightW + 16 or 10
    row.name:ClearAllPoints()
    row.sub:ClearAllPoints()
    row.count:ClearAllPoints()
    row.value:ClearAllPoints()
    if info.sub and info.sub ~= "" then
        row.name:SetPoint("BOTTOMLEFT", row, "LEFT", textLeft, 1)
        row.name:SetPoint("RIGHT", -rightPad, 0)
        row.sub:SetPoint("TOPLEFT", row, "LEFT", textLeft, -3)
        row.sub:SetPoint("RIGHT", -rightPad, 0)
        row.sub:SetText(info.sub)
        if info.quest then row.sub:SetTextColor(1, 0.82, 0) else row.sub:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
        row.sub:Show()
    else
        row.name:SetPoint("LEFT", textLeft, 0)
        row.name:SetPoint("RIGHT", -rightPad, 0)
        row.sub:Hide()
    end
    if row.count:IsShown() and row.value:IsShown() then
        row.count:SetPoint("BOTTOMRIGHT", row, "RIGHT", -9, 1)
        row.value:SetPoint("TOPRIGHT", row, "RIGHT", -9, -3)
    else
        row.count:SetPoint("RIGHT", -9, 0)
        row.value:SetPoint("RIGHT", -9, 0)
    end
    Kit.SetBg(row, C.card)
    Kit.SetBorderColor(row, 0, 0, 0, 1)
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
        info.sub = L["Money"]
        if not IsSecret(item) and type(item) == "string" then info.name = item:gsub("\n", ", ") end
    elseif Plain(questID, nil) and not Plain(isActive, true) then
        info.quest, info.sub = true, L["Starts a quest"]
    elseif Plain(isQuestItem, false) or Plain(questID, nil) then
        info.quest, info.sub = true, L["Quest item"]
    elseif slotType == Enum.LootSlotType.Currency then
        info.sub = L["Currency"]
    else
        local q = QualityOf(quality)
        local link = GetLootSlotLink(slot)
        if not IsSecret(link) then info.link = link end
        local gear = db.lootShowItemLevel and Kit.GearLine(info.link, L)
        info.sub = gear or _G["ITEM_QUALITY" .. q .. "_DESC"]
    end
    return info
end

local FAKE_LOOT = {
    { texture = 135349, name = "Starforged Cleaver",        quality = 5, sub = "ilvl 691 · Two-Hand", unit = 48500000 },
    { texture = 132744, name = "Nightwatch Bulwark Plate",  quality = 4, sub = "ilvl 678 · Chest", unit = 2150000 },
    { texture = 133432, name = "Band of the Hunter's Belt", quality = 3, sub = "ilvl 671 · Finger", unit = 412000 },
    { texture = 134939, name = "Shimmering Riftdust",       quality = 2, count = 14, sub = "Enchanting", unit = 18500 },
    { texture = 134327, name = "Sealed Orders",             quality = 1, quest = true, sub = "Quest item" },
    { texture = 133784, name = "24 Gold, 61 Silver",        quality = 1, money = true, sub = "Money" },
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
    local y, shown, worth = 0, 0, 0
    for _, row in ipairs(rows) do
        if (row.slot or row.fake) and not row.cleared then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", win.body, "TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", win.body, "RIGHT", 0, 0)
            row:Show()
            y = y + row:GetHeight() + GAP
            shown = shown + 1
            if not row.vendorValue then worth = worth + (row.unitValue or 0) end
        else
            row:Hide()
        end
    end
    if shown > 0 then y = y - GAP end
    win.empty:SetShown(shown == 0)
    if shown == 0 then y = 34 end
    local hasAll = db.lootAllButton and shown > 1
    local hasWorth = db.lootShowValue and worth > 0
    local footer = hasAll or hasWorth
    win.lootAll:SetShown(hasAll)
    win.worth:SetShown(hasWorth)
    if hasWorth then win.worth:SetText(string.format(L["Worth %s"], Kit.ShortMoney(worth, 11))) end
    win.footerLine:SetShown(footer)
    win.count:SetText(shown == 1 and L["1 item"] or string.format(L["%d items"], shown))
    win.count:SetShown(shown > 0)
    win:SetSize(db.lootWidth, HEADER + PAD + y + PAD + (footer and FOOTER or 0))
end

local function PlaceWindow()
    win:SetScale(db.lootScale)
    win:ClearAllPoints()
    if lootOpen and db.lootPosition == "cursor" and not editing then
        local x, y = GetCursorPosition()
        local s = win:GetEffectiveScale()
        -- First card lands under the cursor, like Blizzard's loot-under-mouse.
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 40, y / s + HEADER + PAD + (db.lootIconSize + 10) / 2)
    else
        win:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    end
end

local function EnsureWindow()
    if win then return end
    anchor = Kit.Anchor("lootWindowPos", { "CENTER", "UIParent", "CENTER", -360, 120 })
    anchor:SetSize(db.lootWidth, HEADER)

    -- Named so Escape closes it (UISpecialFrames needs a global name).
    win = CreateFrame("Frame", "RaidControlLootFrame", UIParent)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()
    Kit.Skin(win, C.bg)
    Kit.Shadow(win, 14, 0.55)
    tinsert(UISpecialFrames, "RaidControlLootFrame")
    Loot.frame = win

    local r, g, b = Kit.Accent()
    -- Header: darker band, accent mark, title, item count and close.
    win.header = win:CreateTexture(nil, "BACKGROUND", nil, -7)
    win.header:SetPoint("TOPLEFT", 1, -1)
    win.header:SetPoint("TOPRIGHT", -1, -1)
    win.header:SetHeight(HEADER - 1)
    Kit.Solid(win.header, C.header)
    win.mark = win:CreateTexture(nil, "ARTWORK")
    win.mark:SetSize(3, 14)
    win.mark:SetPoint("LEFT", win, "TOPLEFT", 10, -HEADER / 2)
    win.mark:SetColorTexture(r, g, b, 1)
    win.title = Kit.Text(win, 14)
    win.title:SetPoint("LEFT", win.mark, "RIGHT", 7, 0)
    win.close = Kit.TextButton(win, "x", 15)
    win.close:SetPoint("RIGHT", win, "TOPRIGHT", -4, -HEADER / 2)
    win.close:SetScript("OnClick", function() win:Hide() end)
    win.count = Kit.Text(win, 11, C.muted)
    win.count:SetPoint("RIGHT", win.close, "LEFT", -2, 0)
    win.line = win:CreateTexture(nil, "BORDER")
    win.line:SetPoint("TOPLEFT", 1, -HEADER)
    win.line:SetPoint("TOPRIGHT", -1, -HEADER)
    win.line:SetHeight(1)
    win.line:SetColorTexture(1, 1, 1, 1)
    win.line:SetGradient("HORIZONTAL", CreateColor(r, g, b, 1), CreateColor(r, g, b, 0.08))

    win.body = CreateFrame("Frame", nil, win)
    win.body:SetPoint("TOPLEFT", PAD, -(HEADER + PAD))
    win.body:SetPoint("TOPRIGHT", -PAD, -(HEADER + PAD))
    win.body:SetHeight(1)
    win.empty = Kit.Text(win.body, 12, C.muted)
    win.empty:SetPoint("TOP", 0, -10)
    win.empty:SetText(L["Nothing to loot"])

    -- Footer: value of what's left on the left, Loot all on the right.
    win.footerLine = win:CreateTexture(nil, "BORDER")
    win.footerLine:SetPoint("BOTTOMLEFT", 1, FOOTER)
    win.footerLine:SetPoint("BOTTOMRIGHT", -1, FOOTER)
    win.footerLine:SetHeight(1)
    Kit.Solid(win.footerLine, C.line)
    win.worth = Kit.Text(win, 11, C.muted)
    win.worth:SetPoint("BOTTOMLEFT", 10, FOOTER / 2 - 6)
    win.lootAll = Kit.Button(win, L["Loot all"], 92, 22, "accent")
    win.lootAll:SetPoint("BOTTOMRIGHT", -PAD, (FOOTER - 22) / 2)
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
    anchor:SetSize(db.lootWidth, HEADER)
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
        row.glow:Stop()
        self:LayoutWindow()
    end
end

function Loot:LOOT_SLOT_CHANGED(_, slot)
    local row = FindRow(slot)
    if row then
        PaintRow(row, SlotInfo(slot))
        self:LayoutWindow()
    end
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
    rf.glow:Stop()
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
    btn.bg:SetColorTexture(1, 1, 1, 0.08)
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip_SetTitle(GameTooltip, btn.tip)
    if not btn:IsEnabled() and btn.reason then
        GameTooltip:AddLine(btn.reason, RED_FONT_COLOR.r, RED_FONT_COLOR.g, RED_FONT_COLOR.b, true)
    end
    GameTooltip:Show()
end

local function RollButtonOnLeave(btn)
    btn.bg:SetColorTexture(1, 1, 1, 0.03)
    GameTooltip:Hide()
end

local function SetRollButton(btn, enabled, reason)
    btn:SetEnabled(enabled)
    btn:SetAlpha(enabled and 1 or 0.3)
    btn.icon:SetDesaturated(not enabled)
    btn.reason = (not enabled) and reason or nil
end

local function RollOnUpdate(rf)
    if rf.result then return end
    local frac, left
    if rf.fake then
        frac = 1 - ((GetTime() - rf.fakeStart) % 20) / 20
        left = frac * 20
    elseif rf.rollID then
        left = Plain(GetLootRollTimeLeft(rf.rollID), nil)
        if type(left) ~= "number" or not rf.rollTime or rf.rollTime <= 0 then return end
        frac = max(0, min(1, left / rf.rollTime))
        left = left / 1000
    else
        return
    end
    rf.timer:SetValue(frac)
    rf.timeText:SetText(string.format("%d", floor(left + 0.5)))
    if frac < 0.2 then
        rf.timer:SetStatusBarColor(0.9, 0.28, 0.22)
        rf.timeText:SetTextColor(0.95, 0.4, 0.35)
    else
        rf.timer:SetStatusBarColor(Kit.Accent())
        rf.timeText:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    end
end

local function NewRollFrame()
    local rf = CreateFrame("Frame", nil, UIParent)
    rf:SetFrameStrata("DIALOG")
    rf:SetToplevel(true)
    rf:EnableMouse(true)
    rf:Hide()
    CardBase(rf, C.bg)
    Kit.Shadow(rf, 10, 0.5)

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

    rf.buttons = {}
    for _, def in ipairs(ROLL_BUTTONS) do
        local btn = CreateFrame("Button", nil, rf)
        btn:SetMotionScriptsWhileDisabled(true)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(1, 1, 1, 0.03)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetPoint("TOPLEFT", 3, -3)
        btn.icon:SetPoint("BOTTOMRIGHT", -3, 3)
        btn.icon:SetAtlas(def.atlas .. "-up")
        btn:SetHighlightAtlas(def.atlas .. "-highlight", "ADD")
        btn.rollType, btn.tip = def.rollType, def.tip
        btn:SetScript("OnClick", RollButtonOnClick)
        btn:SetScript("OnEnter", RollButtonOnEnter)
        btn:SetScript("OnLeave", RollButtonOnLeave)
        btn:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.icon:SetAtlas(def.atlas .. "-down") end end)
        btn:SetScript("OnMouseUp", function(self) self.icon:SetAtlas(def.atlas .. "-up") end)
        rf.buttons[def.key] = btn
    end

    rf.resultText = rf:CreateFontString(nil, "OVERLAY")
    rf.resultText:Hide()

    -- Timer: a 3px bar on a dark track along the bottom, seconds left next to the buttons.
    rf.track = rf:CreateTexture(nil, "BORDER")
    rf.track:SetPoint("BOTTOMLEFT", 1, 1)
    rf.track:SetPoint("BOTTOMRIGHT", -1, 1)
    rf.track:SetHeight(3)
    rf.track:SetColorTexture(0, 0, 0, 0.6)
    rf.timer = CreateFrame("StatusBar", nil, rf)
    rf.timer:SetPoint("BOTTOMLEFT", 1, 1)
    rf.timer:SetPoint("BOTTOMRIGHT", -1, 1)
    rf.timer:SetHeight(3)
    rf.timer:SetStatusBarTexture(WHITE)
    rf.timer:SetStatusBarColor(Kit.Accent())
    rf.timer:SetMinMaxValues(0, 1)
    rf.timeText = Kit.Text(rf, 10, C.muted)
    rf.timeText:SetJustifyH("RIGHT")
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
    local size = db.lootRollIconSize
    local h = size + 14
    rf:SetScale(db.lootScale)
    rf:SetSize(db.lootRollWidth, h)
    rf.icon:SetSize(size, size)
    rf.icon:ClearAllPoints()
    rf.icon:SetPoint("LEFT", 8, 1)

    local r, g, b, glow = Dress(rf, info.quality)
    rf.icon:Paint(info.texture, info.count, r, g, b)
    if glow then rf.glow:Start(r, g, b, 0.9) else rf.glow:Stop() end

    -- Buttons, right to left: Pass, Greed or Transmog, Need.
    local bsize = min(30, size - 6)
    local need, greed, tmog, pass = rf.buttons.need, rf.buttons.greed, rf.buttons.transmog, rf.buttons.pass
    for _, btn in pairs(rf.buttons) do btn:SetSize(bsize, bsize); btn:ClearAllPoints(); btn:Show() end
    pass:SetPoint("RIGHT", rf, "RIGHT", -8, 1)
    local mid, other = greed, tmog
    if info.canTransmog then mid, other = tmog, greed end
    other:Hide()
    mid:SetPoint("RIGHT", pass, "LEFT", -3, 0)
    need:SetPoint("RIGHT", mid, "LEFT", -3, 0)
    SetRollButton(need, info.canNeed, info.reasonNeed)
    SetRollButton(greed, info.canGreed, info.reasonGreed)
    SetRollButton(tmog, true)
    SetRollButton(pass, true)
    rf.timeText:ClearAllPoints()
    rf.timeText:SetPoint("RIGHT", need, "LEFT", -6, 0)
    Kit.SetFont(rf.timeText, 11)

    local left = 8 + size + 10
    Kit.SetFont(rf.name, 13)
    Kit.SetFont(rf.sub, 10)
    rf.name:ClearAllPoints()
    rf.name:SetPoint("BOTTOMLEFT", rf, "LEFT", left, 2)
    rf.name:SetPoint("RIGHT", need, "LEFT", -26, 0)
    rf.name:SetText(info.name)
    rf.name:SetTextColor(r, g, b)
    rf.sub:ClearAllPoints()
    rf.sub:SetPoint("TOPLEFT", rf, "LEFT", left, -2)
    rf.sub:SetPoint("RIGHT", need, "LEFT", -26, 0)
    local parts = {}
    local gear = db.lootShowItemLevel and Kit.GearLine(info.link, L)
    if gear then parts[#parts + 1] = gear end
    if info.bop then parts[#parts + 1] = ITEM_BIND_ON_PICKUP end
    local unit, vendor = info.unit, info.vendor
    if not unit and db.lootShowValue and info.link then unit, vendor = Kit.CardPrice(info.link) end
    if unit and not vendor and db.lootShowValue then parts[#parts + 1] = Kit.ShortMoney(unit, 10) end
    rf.sub:SetText(info.sub or table.concat(parts, "  ·  "))

    rf.resultText:Hide()
    rf.timeText:Show()
    rf.timer:SetValue(1)
    rf.timer:SetStatusBarColor(Kit.Accent())
end

function Loot:LayoutRolls()
    if not rollAnchor then return end
    local h = db.lootRollIconSize + 14
    rollAnchor:SetSize(db.lootRollWidth, h)
    local step = h + ROLL_GAP
    local growUp = db.lootRollGrowUp
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
    if not db.lootRolls then return end
    local texture, name, count, quality, bop, canNeed, canGreed, _, reasonNeed, reasonGreed, _, _, canTransmog = GetLootRollItemInfo(rollID)
    if not IsSecret(name) and name == nil then return end -- the roll is already over
    local rf = GetRollFrame()
    rf.rollID, rf.rollTime, rf.fake, rf.result = rollID, Plain(rollTime, 0), nil, nil
    local link = GetLootRollItemLink(rollID)
    PaintRoll(rf, {
        texture = texture, name = name, count = count, quality = quality, bop = Plain(bop, false),
        canNeed = Plain(canNeed, true), canGreed = Plain(canGreed, true), canTransmog = Plain(canTransmog, false),
        reasonNeed = Reason(reasonNeed),
        reasonGreed = Reason(reasonGreed),
        link = not IsSecret(link) and link or nil,
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
    rf.timeText:Hide()
    Kit.SetFont(rf.resultText, 22, "OUTLINE")
    rf.resultText:ClearAllPoints()
    rf.resultText:SetPoint("RIGHT", rf, "RIGHT", -14, 1)
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
    { texture = 135349, name = "Starforged Cleaver", quality = 5, bop = true, canNeed = true, canGreed = true,
      sub = "ilvl 691  ·  Two-Hand  ·  Bind on Pickup" },
    { texture = 132744, name = "Nightwatch Bulwark Plate", quality = 4, bop = true, canNeed = false, canGreed = true, canTransmog = true,
      reasonNeed = "You can't need this item.", sub = "ilvl 678  ·  Chest  ·  Bind on Pickup" },
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
    rollAnchor = Kit.Anchor("lootRollPos", { "CENTER", "UIParent", "CENTER", 0, 260 })
    rollAnchor:SetSize(db.lootRollWidth, db.lootRollIconSize + 14)
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
    if db.lootRolls then ShowFakeRolls() end
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
    if not lootOpen then self:ShowWindow() end
    -- The window sits on top of its anchor; let the drag reach the anchor through it.
    win:EnableMouse(false)
    for _, row in ipairs(rows) do row:EnableMouse(false) end
    Kit.ShowHandle(anchor, true)
    ClearFakeRolls()
    ShowFakeRolls()
    for _, rf in ipairs(activeRolls) do
        rf:EnableMouse(false)
        rf.icon:EnableMouse(false)
        for _, btn in pairs(rf.buttons) do btn:EnableMouse(false) end
    end
    Kit.ShowHandle(rollAnchor, true)
end

function Loot:EndLayoutMode()
    if not editing then return end
    editing = false
    Kit.ShowHandle(anchor, false)
    Kit.ShowHandle(rollAnchor, false)
    if win then win:EnableMouse(true) end
    for _, row in ipairs(rows) do row:EnableMouse(true) end
    for _, rf in ipairs(rollFrames) do
        rf:EnableMouse(true)
        rf.icon:EnableMouse(true)
        for _, btn in pairs(rf.buttons) do btn:EnableMouse(true) end
    end
    ClearFakeRolls()
    if lootOpen then self:ShowWindow() else self:HideWindow() end
end

-- Settings changed: switch on/off and redraw.
function Loot:Refresh()
    local want = db.lootEnabled == true
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
    SetBlizzardRolls(db.lootRolls)
    anchor:SetSize(db.lootWidth, HEADER)
    rollAnchor:SetSize(db.lootRollWidth, db.lootRollIconSize + 14)
    if win:IsShown() then self:ShowWindow() end
    for _, rf in ipairs(activeRolls) do
        if rf.fake then PaintRoll(rf, FAKE_ROLLS[rf.fake]) end
    end
    self:LayoutRolls()
end

function Loot:ResetPosition()
    if anchor then anchor:ResetPosition() end
    if rollAnchor then rollAnchor:ResetPosition() end
    if win and win:IsShown() then self:ShowWindow() end
    self:LayoutRolls()
end

function Loot:Activate()
    EnsureWindow()
    EnsureRollAnchor()
    self.active = true
    SetBlizzardLoot(true)
    SetBlizzardRolls(db.lootRolls)
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
