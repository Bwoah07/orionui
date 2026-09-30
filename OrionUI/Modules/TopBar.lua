-- Top bar: a small, movable, transparent strip (not a full-width bar; Stig 2026-09-30):
-- the clock in the middle, buttons on each side of it (a random hearthstone from a pool you
-- pick, Dalaran/Garrison hearthstones, any item or toy IDs), FPS | MS small under the clock.
--
-- Everything hangs off one frame, `bar`, which holds secure buttons: it and the clock slot
-- have a fixed size set out of combat, so nothing the secure buttons anchor to ever moves or
-- resizes in combat. The clock text just changes inside its fixed slot.
--
-- The buttons are secure action buttons (a /use macro), so they can only be created or
-- changed out of combat: all layout goes through ns.Combat:Defer. The random pick happens
-- in PreClick and only out of combat (you can't hearth in combat anyway).
local _, ns = ...

local L = ns.L
local S = ns.Schema

local GetTime, GetFramerate, GetNetStats = GetTime, GetFramerate, GetNetStats

local M = ns.Modules:New("TopBar", {
    category = "qol", label = L["Top bar"],
    desc = L["A small movable strip: the clock in the middle, hearthstone buttons on each side, FPS and latency under it. Move it with /oui edit."],
    profileKey = "layout",
    schema = S.Table{ fields = {
        height = S.Number{ default = 24, min = 16, max = 48, step = 1, label = L["Button size"], order = 2 },
        background = S.Bool{ default = false, label = L["Dark background behind it"], order = 3 },
        fontSize = S.Number{ default = 12, min = 8, max = 20, step = 1, label = L["Text size"], order = 4 },
        showClock = S.Bool{ default = true, label = L["Show clock"], order = 10 },
        clock24 = S.Bool{ default = true, label = L["24-hour clock"], order = 11 },
        realmTime = S.Bool{ default = false, label = L["Use realm time"], order = 12 },
        showFPS = S.Bool{ default = true, label = L["Show FPS"], order = 13 },
        showMS = S.Bool{ default = true, label = L["Show latency (MS)"], order = 14 },
        leftButtons = S.String{ default = "hearth", label = L["Buttons left of the clock"], order = 20,
            desc = L["Separated by spaces or commas: hearth (random hearthstone), dalaran, garrison, or any item or toy ID. Closest to the clock first."] },
        rightButtons = S.String{ default = "dalaran garrison", label = L["Buttons right of the clock"], order = 21,
            desc = L["Same words as the left side. Buttons you don't own are left out."] },
        pool = S.Map{ hidden = true, of = S.Bool{ default = false } },
    } },
})

local bar, clockBtn, statsBtn, clockText, statsText
local buttons = {}   -- secure buttons in use, left to right
local spare = {}     -- released secure buttons, reused (secure frames can't be deleted)
local ticker

---------------------------------------------------------------------------
-- Ownership and the hearthstone pool
---------------------------------------------------------------------------

local function HasToy(id) return PlayerHasToy and PlayerHasToy(id) or false end

local function Owns(id)
    if HasToy(id) then return true end
    local count = C_Item.GetItemCount(id)
    return type(count) == "number" and count > 0
end

-- Hearthstones the player owns: the plain Hearthstone (if in bags) plus owned toys.
local function OwnedHearthstones()
    local list = {}
    if Owns(ns.Data.HEARTHSTONE_ITEM) then list[#list + 1] = ns.Data.HEARTHSTONE_ITEM end
    for _, id in ipairs(ns.Data.HearthstoneToys) do
        if HasToy(id) then list[#list + 1] = id end
    end
    return list
end

-- The pool: the ones ticked in options, or every owned one when nothing is ticked.
local function Pool()
    local owned, picked = OwnedHearthstones(), {}
    for _, id in ipairs(owned) do
        if M.db.pool[tostring(id)] then picked[#picked + 1] = id end
    end
    return #picked > 0 and picked or owned
end

local function ItemName(id)
    return C_Item.GetItemNameByID(id) or (L["Item"] .. " " .. id)
end

---------------------------------------------------------------------------
-- Secure buttons
---------------------------------------------------------------------------

local function SetItem(btn, id)
    btn.itemID = id
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("macrotext", id and ("/use item:" .. id) or "")
    btn.icon:SetTexture(id and C_Item.GetItemIconByID(id) or 134400) -- question mark
end

local function RollHearth(btn)
    if InCombatLockdown() then return end
    local pool = Pool()
    if #pool == 0 then SetItem(btn, nil) return end
    local id = pool[math.random(#pool)]
    if #pool > 1 and id == btn.itemID then id = pool[math.random(#pool)] end -- fewer repeats
    SetItem(btn, id)
end

local function UpdateCooldown(btn)
    if not btn.itemID then btn.cd:Clear() return end
    local start, duration = C_Item.GetItemCooldown(btn.itemID)
    -- Item cooldowns could be secret in restricted content; then leave the swipe alone.
    if ns.Secret.Is(start) or ns.Secret.Is(duration) then return end
    if type(duration) == "number" and duration > 1.5 then
        btn.cd:SetCooldown(start, duration)
    else
        btn.cd:Clear()
    end
end

local function ShowTooltip(btn)
    if not btn.itemID then return end
    GameTooltip:SetOwner(btn, "ANCHOR_BOTTOMRIGHT")
    if HasToy(btn.itemID) then GameTooltip:SetToyByItemID(btn.itemID) else GameTooltip:SetItemByID(btn.itemID) end
    if btn.random then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["A random hearthstone from your pool each time."], 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end

local function AcquireButton()
    local btn = table.remove(spare)
    if btn then return btn end
    btn = CreateFrame("Button", nil, bar, "SecureActionButtonTemplate")
    btn:RegisterForClicks("AnyUp", "AnyDown")
    ns.Theme:Skin(btn, { 0, 0, 0, 0.5 }, { 0, 0, 0, 1 })
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("TOPLEFT", 1, -1)
    btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    btn.cd:SetAllPoints(btn.icon)
    btn.cd:SetHideCountdownNumbers(true)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(btn.icon)
    hl:SetColorTexture(1, 1, 1, 0.15)
    btn:SetScript("OnEnter", ShowTooltip)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    btn:SetScript("PreClick", function(self) if self.random then RollHearth(self) end end)
    return btn
end

-- "hearth dalaran 12345" -> { {random=true}, {item=140192}, {item=12345} }, owned ones only.
local FIXED = {}
for _, t in ipairs(ns.Data.TeleportToys) do FIXED[t.key] = t.item end

local function ParseButtons(text)
    local out = {}
    for word in tostring(text or ""):lower():gmatch("[%w]+") do
        if word == "hearth" then
            out[#out + 1] = { random = true }
        elseif FIXED[word] then
            if Owns(FIXED[word]) then out[#out + 1] = { item = FIXED[word] } end
        elseif tonumber(word) then
            out[#out + 1] = { item = tonumber(word) }
        end
    end
    return out
end

local function PlaceSide(list, side, size)
    for i, w in ipairs(list) do
        local btn = AcquireButton()
        btn:SetSize(size, size)
        local offset = 4 + (i - 1) * (size + 3)
        if side == "LEFT" then
            btn:SetPoint("RIGHT", clockBtn, "LEFT", -offset, 0)
        else
            btn:SetPoint("LEFT", clockBtn, "RIGHT", offset, 0)
        end
        btn.random = w.random
        if w.random then RollHearth(btn) else SetItem(btn, w.item) end
        UpdateCooldown(btn)
        btn:Show()
        buttons[#buttons + 1] = btn
    end
    return #list > 0 and (4 + #list * (size + 3) - 3) or 0
end

-- Rebuilds the buttons from settings. Out of combat only (called via Combat:Defer).
-- Returns the width of the wider side so the bar stays centred on the clock.
local function LayoutButtons()
    for _, btn in ipairs(buttons) do
        btn:Hide()
        btn:ClearAllPoints()
        btn.random = nil
        SetItem(btn, nil)
        spare[#spare + 1] = btn
    end
    wipe(buttons)
    local db, size = M.db, M.db.height - 2
    local left = PlaceSide(ParseButtons(db.leftButtons), "LEFT", size)
    local right = PlaceSide(ParseButtons(db.rightButtons), "RIGHT", size)
    return math.max(left, right)
end

---------------------------------------------------------------------------
-- Clock and stats
---------------------------------------------------------------------------

local function ClockString()
    local db = M.db
    if db.realmTime then
        local h, m = GetGameTime()
        if db.clock24 then return ("%02d:%02d"):format(h, m) end
        return ("%d:%02d %s"):format((h % 12 == 0) and 12 or h % 12, m, h < 12 and "AM" or "PM")
    end
    return date(db.clock24 and "%H:%M" or "%I:%M %p")
end

local function LatencyColor(ms)
    if ms < 100 then return "|cff5fd35f" elseif ms < 200 then return "|cffe8c547" end
    return "|cffe05252"
end

local function UpdateTexts()
    local db = M.db
    if db.showClock then clockText:SetText(ClockString()) end
    if db.showFPS or db.showMS then
        local parts = {}
        if db.showFPS then parts[#parts + 1] = ("%d |cff9a9aa5fps|r"):format(math.floor(GetFramerate() + 0.5)) end
        if db.showMS then
            local _, _, home, world = GetNetStats()
            local ms = math.max(home or 0, world or 0)
            parts[#parts + 1] = ("%s%d|r |cff9a9aa5ms|r"):format(LatencyColor(ms), ms)
        end
        statsText:SetText(table.concat(parts, "  |cff55555f|||r  "))
    end
    statsBtn:SetWidth(statsText:GetStringWidth() + 8) -- not an anchor for anything secure
end

local function TextButton()
    local b = CreateFrame("Button", nil, bar)
    b:SetHeight(1)
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER")
    return b, fs
end

local function EnsureBar()
    if bar then return end
    bar = CreateFrame("Frame", "OrionUITopBar", UIParent) -- named: secure children need a stable parent
    bar:SetFrameStrata("LOW")
    bar:SetSize(1, 24)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetPoint("TOPLEFT", -3, 3)
    bar.bg:SetPoint("BOTTOMRIGHT", 3, -3)
    bar.bg:SetColorTexture(0.04, 0.04, 0.05, 0.6)
    ns.Movers:Register("TopBar", {
        label = L["Top bar"], getFrame = function() return bar end, default = { x = 0, y = 360 },
    })

    clockBtn, clockText = TextButton()
    clockBtn:SetScript("OnClick", function() if ToggleCalendar then ToggleCalendar() end end)
    clockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(L["Clock"])
        local h, m = GetGameTime()
        GameTooltip:AddDoubleLine(L["Local time"], date("%H:%M"), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Realm time"], ("%02d:%02d"):format(h, m), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddLine(L["Click: calendar"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    clockBtn:SetScript("OnLeave", GameTooltip_Hide)

    statsBtn, statsText = TextButton()
    statsBtn:SetScript("OnEnter", function(self)
        local down, up, home, world = GetNetStats()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(L["Performance"])
        GameTooltip:AddDoubleLine(L["Frame rate"], ("%.0f fps"):format(GetFramerate()), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Latency (home)"], ("%d ms"):format(home), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Latency (world)"], ("%d ms"):format(world), 1, 1, 1, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Bandwidth in / out"], ("%.1f / %.1f KB/s"):format(down, up), 1, 1, 1, 1, 1, 1)
        GameTooltip:Show()
    end)
    statsBtn:SetScript("OnLeave", GameTooltip_Hide)
end

-- Geometry of the whole strip. Out of combat only: bar and the clock slot are what the
-- secure buttons anchor to, so their size is fixed here and never touched in combat.
local function LayoutBar()
    local db = M.db
    for _, fs in ipairs({ clockText, statsText }) do fs:SetFont(ns.Theme:Font(), db.fontSize, "OUTLINE") end
    statsText:SetFont(ns.Theme:Font(), math.max(8, db.fontSize - 3), "OUTLINE")
    -- Fixed clock slot, wide enough for the longest time string in this format.
    clockText:SetText(db.clock24 and "00:00" or "12:00 PM")
    local slot = db.showClock and (clockText:GetStringWidth() + 14) or 4
    clockBtn:ClearAllPoints()
    clockBtn:SetPoint("CENTER", bar, "CENTER")
    clockBtn:SetSize(slot, db.height)
    clockText:SetShown(db.showClock)
    statsBtn:ClearAllPoints()
    statsBtn:SetPoint("TOP", clockBtn, "BOTTOM", 0, 1)
    statsBtn:SetHeight(db.fontSize)
    statsBtn:SetShown(db.showFPS or db.showMS)
    local side = LayoutButtons()
    bar:SetSize(slot + 2 * side, db.height)
    bar.bg:SetShown(db.background)
    UpdateTexts()
    bar:Show()
end

function M:Refresh()
    if not bar then return end
    ns.Combat:Defer("TopBar", LayoutBar)
end

function M:OnEnable()
    EnsureBar()
    ns.Combat:Defer("TopBar", LayoutBar)
    ticker = self:NewTicker(1, UpdateTexts)
    local function Cooldowns() for _, btn in ipairs(buttons) do UpdateCooldown(btn) end end
    ns.Events:On("BAG_UPDATE_COOLDOWN", self, Cooldowns)
    ns.Events:On("SPELL_UPDATE_COOLDOWN", self, Cooldowns)
    -- Toys and bag items load after login; rebuild once they're known.
    ns.Events:On("TOYS_UPDATED", self, function() self:Refresh() end)
    ns.Events:On("BAG_UPDATE_DELAYED", self, function() self:Refresh() end)
end

function M:OnDisable()
    ticker = nil
    if bar then
        ns.Combat:Defer("TopBar", function() bar:Hide() end)
    end
end

---------------------------------------------------------------------------
-- Options: the hearthstone pool (one toggle per owned hearthstone)
---------------------------------------------------------------------------

M.options = function(self)
    local out = {
        { type = "Header", label = L["Random hearthstone pool"] },
        { type = "Description", label = L["Tick the hearthstones the button may pick. With none ticked it picks from all you own."] },
    }
    local owned = OwnedHearthstones()
    if #owned == 0 then
        out[#out + 1] = { type = "Description", label = L["No hearthstones found yet. Open this page again after your toys have loaded."] }
    end
    for _, id in ipairs(owned) do
        out[#out + 1] = {
            type = "Toggle", label = ItemName(id),
            get = function() return self.db.pool[tostring(id)] == true end,
            set = function(v)
                self.db.pool[tostring(id)] = v or nil
                if self.enabled then self:Refresh() end
            end,
        }
    end
    out[#out + 1] = { type = "Button", label = L["Clear (use all I own)"], func = function()
        wipe(self.db.pool)
        if self.enabled then self:Refresh() end
        if ns.Options then ns.Options:Refresh() end
    end }
    return out
end

