-- Loot: our own loot window and group loot roll frames in OrionUI's look (flat dark panel,
-- 1px border, OrionUI blue, EUI's font, quality-coloured names and icon borders, a travelling
-- glow on epic and better). Replaces Blizzard's LootFrame and GroupLootFrame1..4 while on.
--
-- How it plugs in (checked in wow-ui-source and EllesmereUI's source, 2026-10-04):
--   * LootFrame registers LOOT_OPENED / LOOT_CLOSED itself (LootFrame.lua). We unregister those
--     two while on, so Blizzard's window never opens, and register them again when switched off.
--     EllesmereUI's BlizzardSkin only reskins LootFrame, so with ours on its skin just has nothing
--     to show; nothing clashes.
--   * START_LOOT_ROLL no longer goes through UIParent in 12.x: Blizzard_Game's EventRouting calls
--     GroupLootContainer_AddRoll. The container sits in the managed UIParent layout, and EUI's
--     skin notes that touching it taints, so we never do. Blizzard's roll frames keep running
--     their normal life (so their queue and CANCEL_LOOT_ROLL handling stay correct); we only make
--     GroupLootFrame1..4 invisible and click-through, and draw our own from the same events.
--   * The bind-on-pickup and roll confirmation popups (LOOT_BIND_CONFIRM, CONFIRM_LOOT_ROLL) are
--     shown by Blizzard_Game's event handlers, not by the frames we hide, so they still appear.
--   * LootSlot, RollOnLoot and the loot getters are plain globals with no restriction
--     annotations. Loot is not documented as secret, but values still go through ns.Secret
--     before we compare or index with them. [VERIFY looting and rolling in combat]
local _, ns = ...

local L = ns.L
local S = ns.Schema
local Theme = ns.Theme

local GetTime = GetTime
local floor, max, min = math.floor, math.max, math.min

local HEADER = 26
local FOOTER = 30
local ROW_PAD = 4
local ROLL_GAP = 4
local MAX_BLIZZARD_ROLLS = 4 -- GroupLootFrame1..4 (NUM_GROUP_LOOT_FRAMES in GroupLootFrame.lua)

-- Roll types (the button IDs in GroupLootFrame.xml).
local ROLL_PASS, ROLL_NEED, ROLL_GREED, ROLL_TRANSMOG = 0, 1, 2, 4

local GLOW_FROM = { never = 99, rare = 3, epic = 4, legendary = 5 }

local M = ns.Modules:New("Loot", {
    category = "qol", label = L["Loot"], order = 6,
    desc = L["OrionUI's own loot window and loot roll frames in place of Blizzard's. Use /oui loot to preview them."],
    profileKey = "layout",
    schema = S.Table{ fields = {
        -- Window
        position = S.Enum{ section = L["Loot window"], default = "saved", values = { "saved", "cursor" },
            valueLabels = { saved = L["Where you placed it in /oui edit"], cursor = L["At the mouse cursor"] },
            label = L["Open"], order = 1 },
        width = S.Number{ section = L["Loot window"], default = 260, min = 180, max = 420, step = 2, label = L["Width"], order = 2 },
        iconSize = S.Number{ section = L["Loot window"], default = 30, min = 18, max = 44, step = 1, label = L["Icon size"], order = 3 },
        scale = S.Number{ section = L["Loot window"], default = 1, min = 0.6, max = 1.6, step = 0.05, label = L["Scale"], order = 4 },
        lootAll = S.Bool{ section = L["Loot window"], default = true, label = L["Show a Loot all button"], order = 5 },
        showItemLevel = S.Bool{ section = L["Loot window"], default = true, label = L["Show item level and slot under the name"], order = 6 },
        -- Rolls
        rolls = S.Bool{ section = L["Loot rolls"], default = true, label = L["Replace Blizzard's loot roll frames"], order = 10,
            desc = L["Need, Greed, Transmog and Pass on our own frames. Switch off to keep Blizzard's (or EllesmereUI's skinned) roll frames."] },
        rollWidth = S.Number{ section = L["Loot rolls"], default = 320, min = 240, max = 480, step = 2, label = L["Roll frame width"], order = 11 },
        rollIconSize = S.Number{ section = L["Loot rolls"], default = 34, min = 24, max = 48, step = 1, label = L["Roll icon size"], order = 12 },
        rollGrowUp = S.Bool{ section = L["Loot rolls"], default = true, label = L["Stack new rolls upwards"], order = 13 },
        -- Highlight
        glowFrom = S.Enum{ section = L["Highlight"], default = "epic", values = { "rare", "epic", "legendary", "never" },
            valueLabels = { rare = L["Rare and better"], epic = L["Epic and better"], legendary = L["Legendary and better"], never = L["Never"] },
            label = L["Glow around"], order = 20 },
    } },
    options = function(self)
        return {
            { type = "Header", label = L["Preview"] },
            { type = "Button", label = L["Preview loot window and rolls"], style = "accent", func = function() self:Preview() end },
        }
    end,
})

local anchor, rollAnchor -- what /oui edit moves
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

local function Plain(v, fallback) return ns.Secret.Plain(v, fallback) end

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

local function Glows(q) return QualityOf(q) >= (GLOW_FROM[M.db.glowFrom] or 99) end

local function Font(fs, size, flags) fs:SetFont(Theme:Font(), size, flags or "") end

-- "ilvl 678 · Chest" for gear, nil for everything else or when the item isn't cached yet.
local function GearLine(link)
    if not link or ns.Secret.Is(link) or not C_Item then return nil end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_NON_EQUIP_IGNORE" then return nil end
    local ilvl = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
    local slot = _G[equipLoc]
    if ilvl and slot then return string.format(L["ilvl %d · %s"], ilvl, slot) end
    if ilvl then return string.format(L["ilvl %d"], ilvl) end
    return slot
end

-- Icon box: 1px border in the quality colour, cropped icon, stack count, glow.
local function NewIcon(parent)
    local box = CreateFrame("Frame", nil, parent)
    Theme:Skin(box, { 0, 0, 0, 1 }, Theme.colors.border)
    box.tex = box:CreateTexture(nil, "ARTWORK")
    box.tex:SetPoint("TOPLEFT", 1, -1)
    box.tex:SetPoint("BOTTOMRIGHT", -1, 1)
    box.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    box.count = box:CreateFontString(nil, "OVERLAY")
    box.count:SetPoint("BOTTOMRIGHT", -1, 2)
    box.count:SetJustifyH("RIGHT")
    box.glow = ns.PixelGlow:New(box, { lines = 6, thickness = 1, period = 3.5, pad = 2 })
    function box:Paint(texture, quality, count, borderR, borderG, borderB)
        self.tex:SetTexture(texture)
        local r, g, b = QualityColor(quality)
        Theme:SetBorderColor(self, borderR or r, borderG or g, borderB or b, 1)
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
        M:LayoutWindow()
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
    row.name = Theme:Text(row, 13)
    row.name:SetWordWrap(false)
    row.sub = Theme:Text(row, 10, Theme.colors.muted)
    row.sub:SetWordWrap(false)
    row:SetScript("OnEnter", RowOnEnter)
    row:SetScript("OnLeave", RowOnLeave)
    row:SetScript("OnClick", RowOnClick)
    rows[i] = row
    return row
end

-- Fills a row. info = { texture, name, count, quality, sub, quest, questStarts, locked, money }
local function PaintRow(row, info)
    local db = M.db
    local size = db.iconSize
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
        if info.quest then row.sub:SetTextColor(1, 0.82, 0) else row.sub:SetTextColor(unpack(Theme.colors.muted)) end
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

-- Blizzard's window skips slots of type None the same way (LootFrame.lua).
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
        if not ns.Secret.Is(item) and type(item) == "string" then info.name = item:gsub("\n", ", ") end
    elseif Plain(questID, nil) and not Plain(isActive, true) then
        info.quest, info.sub = true, L["Starts a quest"]
    elseif Plain(isQuestItem, false) or Plain(questID, nil) then
        info.quest, info.sub = true, L["Quest item"]
    elseif slotType == Enum.LootSlotType.Currency then
        info.sub = L["Currency"]
    else
        local q = QualityOf(quality)
        local gear = M.db.showItemLevel and GearLine(GetLootSlotLink(slot))
        info.sub = gear or _G["ITEM_QUALITY" .. q .. "_DESC"]
    end
    return info
end

local FAKE_LOOT = {
    { texture = 135349, name = "Starforged Cleaver of Orion", quality = 5, sub = "ilvl 691 · Two-Hand" },
    { texture = 132744, name = "Nightwatch Bulwark Plate",     quality = 4, sub = "ilvl 678 · Chest" },
    { texture = 133432, name = "Band of the Hunter's Belt",    quality = 3, sub = "ilvl 671 · Finger" },
    { texture = 134939, name = "Shimmering Riftdust",         quality = 2, count = 14, sub = "Uncommon" },
    { texture = 134327, name = "Sealed Orders",               quality = 1, quest = true, sub = "Quest item" },
    { texture = 133784, name = "24 Gold, 61 Silver",          quality = 1, money = true },
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

function M:BuildWindow()
    for _, row in ipairs(rows) do row:Hide(); row.slot, row.fake, row.cleared = nil, nil, nil end
    local entries = Entries()
    for i, e in ipairs(entries) do
        local row = Row(i)
        row.slot, row.fake, row.cleared = e.slot, e.fake, false
        PaintRow(row, e.info or SlotInfo(e.slot))
    end
    self:LayoutWindow()
end

function M:LayoutWindow()
    local db = self.db
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
    local footer = db.lootAll and shown > 1
    win.lootAll:SetShown(footer)
    win.count:SetText(shown == 1 and L["1 item"] or string.format(L["%d items"], shown))
    win.count:SetShown(shown > 0)
    win:SetSize(db.width, HEADER + ROW_PAD + y + ROW_PAD + (footer and FOOTER or 0))
end

local function PlaceWindow()
    local db = M.db
    win:SetScale(db.scale)
    win:ClearAllPoints()
    if lootOpen and db.position == "cursor" and not editing then
        local x, y = GetCursorPosition()
        local s = win:GetEffectiveScale()
        -- First row lands under the cursor, like Blizzard's loot-under-mouse.
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 30, y / s + HEADER + ROW_PAD + db.iconSize / 2 + 4)
    else
        win:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    end
end

local function EnsureWindow()
    if win then return end
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(260, HEADER)
    ns.Movers:Register("Loot", { label = L["Loot window"], getFrame = function() return anchor end, default = { x = -360, y = 120 } })

    -- Named so Escape closes it (UISpecialFrames needs a global name).
    win = CreateFrame("Frame", "OrionUILootFrame", UIParent)
    win:SetFrameStrata("HIGH")
    win:SetToplevel(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:Hide()
    Theme:Skin(win, Theme.colors.bg, Theme.colors.border)
    Theme:Shadow(win, 10)
    tinsert(UISpecialFrames, "OrionUILootFrame")

    local r, g, b = Theme:Accent()
    win.title = Theme:Text(win, 13)
    win.title:SetPoint("LEFT", win, "TOPLEFT", 10, -HEADER / 2)
    win.title:SetTextColor(r, g, b)
    win.close = Theme:TextButton(win, "x", 16)
    win.close:SetPoint("RIGHT", win, "TOPRIGHT", -2, -HEADER / 2)
    win.close:SetScript("OnClick", function() win:Hide() end)
    win.count = Theme:Text(win, 10, Theme.colors.muted)
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
    win.empty = Theme:Text(win.body, 12, Theme.colors.muted)
    win.empty:SetPoint("TOP", 0, -8)
    win.empty:SetText(L["Nothing to loot"])

    win.lootAll = Theme:Button(win, L["Loot all"], 90, 20, "accent")
    win.lootAll:SetPoint("BOTTOMRIGHT", -6, 6)
    win.lootAll:SetScript("OnClick", function()
        if lootOpen then
            for slot = GetNumLootItems(), 1, -1 do
                if HasLoot(slot) then LootSlot(slot) end
            end
        else
            for _, row in ipairs(rows) do row.cleared = true end
            M:LayoutWindow()
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

function M:ShowWindow()
    EnsureWindow()
    anchor:SetSize(self.db.width, HEADER)
    if lootOpen then
        win.title:SetText(IsFishingLoot() and L["Fishing"] or L["Loot"])
    else
        win.title:SetText(editing and L["Loot (edit mode)"] or L["Loot (preview)"])
    end
    self:BuildWindow()
    PlaceWindow()
    if not win:IsShown() then
        win:Show()
        win.fade:Play()
    end
end

function M:HideWindow()
    if not win then return end
    closing = true
    win:Hide()
    closing = false
end

---------------------------------------------------------------------------
-- Loot events
---------------------------------------------------------------------------

local function OnLootOpened(_, _, _, isFromItem)
    lootOpen = true
    previewing = false
    M:ShowWindow()
    if isFromItem then
        PlaySound(SOUNDKIT.UI_CONTAINER_ITEM_OPEN)
    elseif IsFishingLoot() then
        PlaySound(SOUNDKIT.FISHING_REEL_IN)
    elseif GetNumLootItems() == 0 then
        PlaySound(SOUNDKIT.LOOT_WINDOW_OPEN_EMPTY)
    end
end

local function OnLootClosed()
    lootOpen = false
    StaticPopup_Hide("LOOT_BIND")
    if editing then M:ShowWindow() else M:HideWindow() end
end

local function FindRow(slot)
    for _, row in ipairs(rows) do
        if row.slot == slot then return row end
    end
end

local function OnSlotCleared(_, _, slot)
    local row = FindRow(slot)
    if row then
        row.cleared = true
        M:LayoutWindow()
    end
end

local function OnSlotChanged(_, _, slot)
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
    M:LayoutRolls()
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
    if frac < 0.2 then rf.timer:SetStatusBarColor(0.85, 0.25, 0.2) else rf.timer:SetStatusBarColor(Theme:Accent()) end
end

local function NewRollFrame()
    local rf = CreateFrame("Frame", nil, UIParent)
    rf:SetFrameStrata("DIALOG")
    rf:SetToplevel(true)
    rf:EnableMouse(true)
    rf:Hide()
    Theme:Skin(rf, Theme.colors.bg, Theme.colors.border)
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

    rf.name = Theme:Text(rf, 13)
    rf.name:SetWordWrap(false)
    rf.sub = Theme:Text(rf, 10, Theme.colors.muted)
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

    rf.result = nil
    rf.resultText = rf:CreateFontString(nil, "OVERLAY")
    rf.resultText:Hide()

    rf.timer = CreateFrame("StatusBar", nil, rf)
    rf.timer:SetPoint("BOTTOMLEFT", 1, 1)
    rf.timer:SetPoint("BOTTOMRIGHT", -1, 1)
    rf.timer:SetHeight(2)
    rf.timer:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    rf.timer:SetStatusBarColor(Theme:Accent())
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
    local db = M.db
    local size = db.rollIconSize
    rf:SetScale(db.scale)
    rf:SetSize(db.rollWidth, size + 10)
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
    local gear = db.showItemLevel and GearLine(info.link)
    if gear then parts[#parts + 1] = gear end
    if info.bop then parts[#parts + 1] = ITEM_BIND_ON_PICKUP end
    rf.sub:SetText(info.sub or table.concat(parts, " · "))

    rf.resultText:Hide()
    rf.timer:SetValue(1)
    rf.timer:SetStatusBarColor(Theme:Accent())
end

function M:LayoutRolls()
    if not rollAnchor then return end
    local db = self.db
    rollAnchor:SetSize(db.rollWidth, db.rollIconSize + 10)
    local step = db.rollIconSize + 10 + ROLL_GAP
    for i, rf in ipairs(activeRolls) do
        rf:ClearAllPoints()
        if db.rollGrowUp then
            rf:SetPoint("BOTTOM", rollAnchor, "BOTTOM", 0, (i - 1) * step)
        else
            rf:SetPoint("TOP", rollAnchor, "TOP", 0, -(i - 1) * step)
        end
    end
end

local function AddRoll(rf)
    activeRolls[#activeRolls + 1] = rf
    M:LayoutRolls()
    rf:Show()
end

local function Reason(code)
    code = Plain(code, nil)
    if type(code) ~= "number" then return nil end
    return _G["LOOT_ROLL_INELIGIBLE_REASON" .. code]
end

local function OnStartLootRoll(_, _, rollID, rollTime)
    if not M.db.rolls then return end
    local texture, name, count, quality, bop, canNeed, canGreed, _, reasonNeed, reasonGreed, _, _, canTransmog = GetLootRollItemInfo(rollID)
    if not ns.Secret.Is(name) and name == nil then return end -- the roll is already over (Blizzard's frame checks the same)
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

local function OnCancelRoll(_, _, rollID)
    local rf = FindRoll(rollID)
    if rf and not rf.result then RemoveRoll(rf) end -- a shown need result stays until its timer ends
end

local function OnCancelAll()
    for i = #activeRolls, 1, -1 do
        if not activeRolls[i].fake then RemoveRoll(activeRolls[i]) end
    end
end

-- Need rolls on main-spec items report the number; show it on the frame for a moment.
local function OnNeedRoll(_, _, rollID, roll, isWinning)
    local rf = FindRoll(rollID)
    if not rf then return end
    rf.result = true
    for _, btn in pairs(rf.buttons) do btn:Hide() end
    Font(rf.resultText, 20, "OUTLINE")
    rf.resultText:ClearAllPoints()
    rf.resultText:SetPoint("RIGHT", rf, "RIGHT", -12, 1)
    rf.resultText:SetText(Plain(roll, "?"))
    if Plain(isWinning, false) then rf.resultText:SetTextColor(0.3, 0.9, 0.4) else rf.resultText:SetTextColor(0.9, 0.3, 0.3) end
    rf.resultText:Show()
    rf.timer:SetValue(0)
    PlaySound(Plain(isWinning, false) and SOUNDKIT.UI_NEED_ROLL_POSITIVE or SOUNDKIT.UI_NEED_ROLL_NEGATIVE)
    rf.resultTimer = C_Timer.NewTimer(4, function() rf.resultTimer = nil; if rf.rollID == rollID then RemoveRoll(rf) end end)
end

local FAKE_ROLLS = {
    { texture = 135349, name = "Starforged Cleaver of Orion", quality = 5, bop = true, canNeed = true, canGreed = true, sub = "ilvl 691 · Two-Hand · Bind on Pickup" },
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
    rollAnchor = CreateFrame("Frame", nil, UIParent)
    rollAnchor:SetSize(320, 44)
    ns.Movers:Register("LootRolls", { label = L["Loot rolls"], getFrame = function() return rollAnchor end, default = { x = 0, y = 260 } })
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
            -- Skins (EllesmereUI's) repaint these frames on show; keep them invisible.
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
-- Preview, edit mode, lifecycle
---------------------------------------------------------------------------

function M:Preview()
    if lootOpen then return end
    EnsureWindow()
    EnsureRollAnchor()
    previewing = true
    self:ShowWindow()
    ClearFakeRolls()
    if self.db.rolls then ShowFakeRolls() end
    if self.previewTimer then self.previewTimer:Cancel() end
    self.previewTimer = self:After(15, function()
        self.previewTimer = nil
        if editing then return end
        ClearFakeRolls()
        if previewing then
            previewing = false
            if not lootOpen then M:HideWindow() end
        end
    end)
end

function M:Refresh()
    if not win then return end
    SetBlizzardRolls(self.db.rolls)
    if win:IsShown() then self:ShowWindow() end
    self:LayoutRolls()
    anchor:SetSize(self.db.width, HEADER)
end

function M:OnEnable()
    EnsureWindow()
    EnsureRollAnchor()
    SetBlizzardLoot(true)
    SetBlizzardRolls(self.db.rolls)
    ns.Events:On("LOOT_OPENED", self, OnLootOpened)
    ns.Events:On("LOOT_CLOSED", self, OnLootClosed)
    ns.Events:On("LOOT_SLOT_CLEARED", self, OnSlotCleared)
    ns.Events:On("LOOT_SLOT_CHANGED", self, OnSlotChanged)
    ns.Events:On("START_LOOT_ROLL", self, OnStartLootRoll)
    ns.Events:On("CANCEL_LOOT_ROLL", self, OnCancelRoll)
    ns.Events:On("CANCEL_ALL_LOOT_ROLLS", self, OnCancelAll)
    ns.Events:On("MAIN_SPEC_NEED_ROLL", self, OnNeedRoll)
    ns.Events:On("OUI_EDIT_MODE", self, function(_, _, shown)
        editing = shown and true or false
        if editing then
            if not lootOpen then self:ShowWindow() end
            ClearFakeRolls()
            ShowFakeRolls()
        else
            ClearFakeRolls()
            if not lootOpen then self:HideWindow() else self:ShowWindow() end
        end
    end)
    self:Refresh()
end

function M:OnDisable()
    editing, previewing = false, false
    for i = #activeRolls, 1, -1 do RemoveRoll(activeRolls[i]) end
    -- Closing our window also closes loot that is open right now (CloseLoot in OnHide), so the
    -- game isn't left with loot open and no window; the next loot opens in Blizzard's.
    if win and win:IsShown() then win:Hide() end
    lootOpen = false
    SetBlizzardLoot(false)
    SetBlizzardRolls(false)
end

ns.Slash:Register("loot", function() M:Preview() end, "preview the loot window and loot rolls")
