-- Top bar (v2, Stig 2026-09-30): a small movable strip of tiles.
--
--   [friends][guild]   [ 19:09 ]   [hearthstone][M+ portals][extra buttons]
--                    FPS 60 | MS 5
--
-- * Clock: big, centred. Tooltip with local/realm time and the daily/weekly reset; left-click
--   the calendar, right-click the stopwatch/alarm.
-- * Friends / Guild: online counts; tooltips list who is online (class colours, zone); click
--   opens the Friends / Guild window.
-- * Hearthstone: left-click a random hearthstone from your pool, middle- and right-click two
--   more you choose (Dalaran / Garrison by default, or any item or toy ID).
-- * M+ portals: a flyout with this season's dungeons. Teleports you know are clickable, the
--   rest are greyed out. Found from the game itself: the season's maps
--   (C_ChallengeMode.GetMapTable) are matched to your spellbook's teleport flyouts through the
--   spell descriptions, so there is no hand-kept list to go stale.
-- * In combat only FPS | MS stays (the tiles hide through a secure state driver).
--
-- Buttons that cast or use things are secure action buttons, so every layout change goes through
-- ns.Combat:Defer, and the bar is never touched in combat except by its state driver.
local _, ns = ...

local L = ns.L
local S = ns.Schema

local GetFramerate, GetNetStats = GetFramerate, GetNetStats
local ICONS = ns.MEDIA_PATH .. "Textures\\"

local M = ns.Modules:New("TopBar", {
    category = "qol", label = L["Top bar"], order = 1,
    desc = L["Clock, friends, guild, hearthstones and Mythic+ portals in one small bar. In combat only FPS and latency stay. Move it with /oui edit."],
    profileKey = "layout",
    schemaVersion = 4,
    migrations = {
        -- v1 had left/right button lists; the hearthstone and extra buttons now have their own settings.
        [2] = function(db)
            local words = {}
            for w in tostring(db.rightButtons or ""):gmatch("%d+") do words[#words + 1] = w end
            for w in tostring(db.leftButtons or ""):gmatch("%d+") do words[#words + 1] = w end
            if #words > 0 then db.travel = db.travel or {} db.travel.extraItems = table.concat(words, " ") end
            db.leftButtons, db.rightButtons, db.background, db.extraItems = nil, nil, nil, nil
            db.showClock, db.clock24, db.realmTime, db.showFPS, db.showMS, db.fontSize = nil, nil, nil, nil, nil, nil
            if db.height == 24 then db.height = nil end
        end,
        -- Bigger, easier to read FPS / MS (Stig, 2026-09-30).
        [3] = function(db) if db.statsSize == 11 then db.statsSize = nil end end,
        -- The hand-picked hearthstone pool became one on/off switch (Stig, 2026-09-30).
        [4] = function(db) db.pool = nil end,
    },
    schema = S.Table{ fields = {
        height = S.Number{ section = L["Look"], default = 30, min = 20, max = 50, step = 1, label = L["Tile size"], order = 1 },
        clockSize = S.Number{ section = L["Look"], default = 22, min = 12, max = 40, step = 1, label = L["Clock size"], order = 2 },
        statsSize = S.Number{ section = L["Look"], default = 13, min = 8, max = 20, step = 1, label = L["FPS / MS text size"], order = 3 },
        tileAlpha = S.Number{ section = L["Look"], default = 0.8, min = 0, max = 1, step = 0.05, label = L["Tile background (0 = transparent)"], order = 4 },
        borders = S.Bool{ section = L["Look"], default = true, label = L["Tile borders"], order = 4.2,
            desc = L["Off: no black edge around the tiles. They still light up blue on mouseover."] },
        clockFont = S.Enum{ section = L["Look"], default = "bold", values = { "ui", "bold", "orion2", "orion3" }, label = L["Clock font"], order = 4.4,
            valueLabels = { ui = L["UI font"], bold = L["Expressway Bold"], orion2 = L["Orion 2 Bold (Inter)"], orion3 = L["Orion 3 Bold (Rajdhani)"] } },
        clockColor = S.Enum{ section = L["Look"], default = "white", values = { "white", "accent", "class" }, label = L["Clock colour"], order = 4.6,
            valueLabels = { white = L["White"], accent = L["OrionUI blue"], class = L["Class colour"] } },
        hideInCombat = S.Bool{ section = L["Look"], default = true, label = L["In combat show only FPS and MS"], order = 5 },
        clock = S.Table{ label = L["Clock"], order = 10, fields = {
            show = S.Bool{ default = true, label = L["Show the clock"], order = 1 },
            clock24 = S.Bool{ default = true, label = L["24-hour clock"], order = 2 },
            realmTime = S.Bool{ default = false, label = L["Use realm time"], order = 3 },
            stats = S.Bool{ default = true, label = L["Show FPS and MS under it"], order = 4 },
            resting = S.Bool{ default = true, label = L["Zzz on the clock while resting (inn or city)"], order = 5 },
        } },
        social = S.Table{ label = L["Friends and guild"], order = 20, fields = {
            friends = S.Bool{ default = true, label = L["Friends"], order = 1 },
            guild = S.Bool{ default = true, label = L["Guild"], order = 2 },
            crest = S.Bool{ default = true, label = L["Guild button in your guild's colours"], order = 2.5 },
            maxLines = S.Number{ default = 25, min = 5, max = 60, step = 1, label = L["Names in the tooltip"], order = 3 },
        } },
        travel = S.Table{ label = L["Hearthstones and portals"], order = 30, fields = {
            hearth = S.Bool{ default = true, label = L["Hearthstone button"], order = 1 },
            random = S.Bool{ default = true, label = L["Random hearthstone on left-click"], order = 1.5,
                desc = L["On: a random hearthstone toy you own each time. Off: your normal Hearthstone."] },
            middleClick = S.String{ default = "dalaran", label = L["Middle-click uses"], order = 2,
                desc = L["dalaran, garrison, or an item or toy ID. Empty = nothing."] },
            rightClick = S.String{ default = "garrison", label = L["Right-click uses"], order = 3,
                desc = L["dalaran, garrison, or an item or toy ID. Empty = nothing."] },
            portals = S.Bool{ default = true, label = L["Mythic+ portals button"], order = 4 },
            extraItems = S.String{ default = "", label = L["Extra buttons (item or toy IDs)"], order = 5 },
        } },
    } },
})

local bar, stats, statsText, flyout
local tiles = {}     -- key -> tile
local extra = {}     -- extra secure buttons in use
local spare = {}     -- released extra buttons (secure frames can't be deleted)
local portalButtons = {}
M.tiles, M.portalButtons = tiles, portalButtons -- for tests

---------------------------------------------------------------------------
-- Hearthstones
---------------------------------------------------------------------------

local function HasToy(id) return PlayerHasToy and PlayerHasToy(id) or false end
local function Owns(id)
    if HasToy(id) then return true end
    local n = C_Item.GetItemCount(id)
    return type(n) == "number" and n > 0
end

local function OwnedHearthstones()
    local list = {}
    if Owns(ns.Data.HEARTHSTONE_ITEM) then list[#list + 1] = ns.Data.HEARTHSTONE_ITEM end
    for _, id in ipairs(ns.Data.HearthstoneToys) do
        if HasToy(id) then list[#list + 1] = id end
    end
    return list
end

-- Left-click choices: every hearthstone you own when random is on, else the plain Hearthstone
-- (or, without one in your bags, your first hearthstone toy).
local function Pool()
    local owned = OwnedHearthstones()
    if M.db.travel.random then return owned end
    if Owns(ns.Data.HEARTHSTONE_ITEM) then return { ns.Data.HEARTHSTONE_ITEM } end
    return owned[1] and { owned[1] } or {}
end

local FIXED = {}
for _, t in ipairs(ns.Data.TeleportToys) do FIXED[t.key] = t.item end

-- "dalaran" / "garrison" / "12345" -> item ID, or nil (named ones only when owned).
local function ResolveItem(word)
    word = tostring(word or ""):lower():match("^%s*(.-)%s*$")
    if word == "" then return nil end
    if FIXED[word] then return Owns(FIXED[word]) and FIXED[word] or nil end
    return tonumber(word)
end

local function ItemName(id) return C_Item.GetItemNameByID(id) or (L["Item"] .. " " .. id) end

---------------------------------------------------------------------------
-- Tiles
---------------------------------------------------------------------------

-- Resting border: black, or invisible with borders turned off (Stig, 2026-10-02).
local function RestBorder(t)
    ns.Theme:SetBorderColor(t.edge, 0, 0, 0, M.db.borders and 1 or 0)
end

-- A dark square with a 1px border that lights up in OrionUI blue on hover.
local function StyleTile(t)
    t.bg = t:CreateTexture(nil, "BACKGROUND")
    t.bg:SetAllPoints()
    t.edge = CreateFrame("Frame", nil, t)
    t.edge:SetAllPoints()
    t.edge:SetFrameLevel(t:GetFrameLevel() + 3)
    ns.Theme:Skin(t.edge, { 0, 0, 0, 0 }, { 0, 0, 0, 1 })
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetPoint("TOPLEFT", 3, -3)
    t.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    t.count = t.edge:CreateFontString(nil, "OVERLAY")
    t.count:SetPoint("BOTTOMRIGHT", -2, 2)
    t:HookScript("OnEnter", function(self) ns.Theme:SetBorderColor(self.edge, ns.Theme:Accent()) end)
    t:HookScript("OnLeave", function(self) RestBorder(self) GameTooltip_Hide() end)
end

local function PlainTile(key)
    local t = CreateFrame("Button", nil, bar)
    StyleTile(t)
    t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tiles[key] = t
    return t
end

local function SecureTile(parent)
    local t = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    t:RegisterForClicks("AnyUp", "AnyDown")
    StyleTile(t)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.cd = CreateFrame("Cooldown", nil, t, "CooldownFrameTemplate")
    t.cd:SetAllPoints(t.icon)
    t.cd:SetHideCountdownNumbers(true)
    return t
end

local function UpdateItemCooldown(t, id)
    if not id then t.cd:Clear() return end
    local start, duration = C_Item.GetItemCooldown(id)
    if ns.Secret.Is(start) or ns.Secret.Is(duration) then return end
    if type(duration) == "number" and duration > 1.5 then t.cd:SetCooldown(start, duration) else t.cd:Clear() end
end

---------------------------------------------------------------------------
-- Clock and stats
---------------------------------------------------------------------------

local function ClockString()
    local db = M.db.clock
    if db.realmTime then
        local h, m = GetGameTime()
        if db.clock24 then return ("%02d:%02d"):format(h, m) end
        return ("%d:%02d %s"):format((h % 12 == 0) and 12 or h % 12, m, h < 12 and "AM" or "PM")
    end
    return date(db.clock24 and "%H:%M" or "%I:%M %p")
end

local function Duration(sec)
    sec = math.max(0, math.floor(sec or 0))
    local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
    if d > 0 then return ("%dd %dh"):format(d, h) end
    if h > 0 then return ("%dh %dm"):format(h, m) end
    return ("%dm"):format(m)
end

-- Labels white, values in OrionUI blue (Stig, 2026-09-30). The exact accent was too dark for small
-- digits on the dark outline (Stig, 2026-10-01), so the same blue is brightened to full strength
-- (same hue and saturation, not mixed with white, so it stays the OrionUI blue).
local function BlueHex()
    local r, g, b = ns.Theme:Accent()
    local scale = 1 / math.max(r, g, b, 0.01)
    local function Hex(v) return math.floor(math.min(1, v * scale) * 255 + 0.5) end
    return ("|cff%02x%02x%02x"):format(Hex(r), Hex(g), Hex(b))
end

-- FPS / MS values coloured by how good they are (Stig, 2026-10-02): green, yellow, red.
-- FPS: 60+ / 30-59 / under 30. MS: under 100 / 100-199 / 200+.
local function Grade(good, okay)
    if good then return "|cff5ed45e" end
    if okay then return "|cffffd23f" end
    return "|cffff4d4d"
end

local function UpdateTexts()
    local db = M.db
    if tiles.clock and db.clock.show then tiles.clock.text:SetText(ClockString()) end
    if db.clock.stats and statsText then
        local fps = math.floor(GetFramerate() + 0.5)
        local _, _, home, world = GetNetStats()
        local ms = math.max(home or 0, world or 0)
        statsText:SetText(("|cffffffffFPS|r %s%d|r   |cffffffffMS|r %s%d|r"):format(
            Grade(fps >= 60, fps >= 30), fps, Grade(ms < 100, ms < 200), ms))
        stats:SetWidth(math.ceil(statsText:GetStringWidth()) + 12)
    end
end

local function UpdateResting()
    local zzz = tiles.clock and tiles.clock.zzz
    if zzz then zzz:SetShown(M.db.clock.show and M.db.clock.resting and IsResting() or false) end
end

local function ClockTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
    GameTooltip:AddLine(date("%A %d %B"), 1, 1, 1)
    local h, m = GetGameTime()
    GameTooltip:AddDoubleLine(L["Local time"], date("%H:%M"), 0.7, 0.7, 0.7, 1, 1, 1)
    GameTooltip:AddDoubleLine(L["Realm time"], ("%02d:%02d"):format(h, m), 0.7, 0.7, 0.7, 1, 1, 1)
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
        GameTooltip:AddLine(" ")
        GameTooltip:AddDoubleLine(L["Daily reset"], Duration(C_DateAndTime.GetSecondsUntilDailyReset()), 0.7, 0.7, 0.7, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Weekly reset"], Duration(C_DateAndTime.GetSecondsUntilWeeklyReset()), 0.7, 0.7, 0.7, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Left-click: calendar"], 0.2, 0.6, 1)
    GameTooltip:AddLine(L["Right-click: stopwatch and alarm"], 0.2, 0.6, 1)
    GameTooltip:Show()
end

local function ClockClick(_, button)
    if button == "RightButton" then
        C_AddOns.LoadAddOn("Blizzard_TimeManager")
        if TimeManager_Toggle then TimeManager_Toggle() end
    elseif ToggleCalendar then
        ToggleCalendar()
    end
end

---------------------------------------------------------------------------
-- Friends and guild
---------------------------------------------------------------------------

local CLASS_BY_NAME = {} -- localized class name -> class file ("Death Knight" -> "DEATHKNIGHT")
for file, name in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do CLASS_BY_NAME[name] = file end
for file, name in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do CLASS_BY_NAME[name] = file end

local function ClassHex(classFile)
    local c = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    return c and c:GenerateHexColorMarkup() or "|cffffffff"
end

local function OnlineFriends()
    local list = {}
    for i = 1, C_FriendList.GetNumFriends() do
        local f = C_FriendList.GetFriendInfoByIndex(i)
        if f and f.connected then
            list[#list + 1] = { name = f.name, class = CLASS_BY_NAME[f.className], zone = f.area }
        end
    end
    local _, bnOnline = BNGetNumFriends()
    for i = 1, bnOnline or 0 do
        local a = C_BattleNet.GetFriendAccountInfo(i)
        local g = a and a.gameAccountInfo
        if g and g.isOnline and g.clientProgram == BNET_CLIENT_WOW and g.characterName then
            list[#list + 1] = { name = g.characterName, bnet = a.accountName, class = CLASS_BY_NAME[g.className], zone = g.areaName }
        end
    end
    return list
end

local function OnlineGuild()
    local list = {}
    if not IsInGuild() then return list end
    for i = 1, GetNumGuildMembers() do
        local name, rank, _, _, _, zone, _, _, online, _, classFile = GetGuildRosterInfo(i)
        if online and name then
            list[#list + 1] = { name = Ambiguate(name, "guild"), class = classFile, zone = zone, rank = rank }
        end
    end
    return list
end

local function SocialTooltip(self, title, list, hint, extraLine)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
    GameTooltip:AddDoubleLine(title, ("%d %s"):format(#list, L["online"]), 1, 1, 1, 0.37, 0.83, 0.37)
    if extraLine then GameTooltip:AddLine(extraLine, 0.9, 0.8, 0.5, true) end
    if #list > 0 then GameTooltip:AddLine(" ") end
    for i, p in ipairs(list) do
        if i > M.db.social.maxLines then
            GameTooltip:AddLine(("... +%d"):format(#list - i + 1), 0.6, 0.6, 0.6)
            break
        end
        local left = ClassHex(p.class) .. p.name .. "|r" .. (p.bnet and (" |cff82c5ff(" .. p.bnet .. ")|r") or "")
        local right = p.zone or ""
        if p.rank then right = right .. "  |cff8a8a95" .. p.rank .. "|r" end
        GameTooltip:AddDoubleLine(left, right, 1, 1, 1, 0.75, 0.75, 0.75)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(hint, 0.2, 0.6, 1)
    GameTooltip:Show()
end

-- Guild shield (Stig, 2026-10-02): the real emblem was unreadable at tile size, so the guild
-- button is our own shield painted in the guild's tabard colours from C_GuildInfo.GetGuildTabardInfo
-- (background colour fill, border colour rim). Not in a guild, no tabard yet, or turned off: our
-- own guild icon as before.
local function UpdateCrest()
    local t = tiles.guild
    if not t then return end
    local info = M.db.social.crest and IsInGuild() and C_GuildInfo and C_GuildInfo.GetGuildTabardInfo
        and C_GuildInfo.GetGuildTabardInfo("player")
    if info and info.emblemFileID then
        t.icon:SetTexture(ICONS .. "IconShield")
        t.icon:SetVertexColor(info.backgroundColor:GetRGB())
        t.shieldEdge:SetVertexColor(info.borderColor:GetRGB())
        t.shieldEdge:Show()
    else
        t.icon:SetTexture(ICONS .. "IconGuild")
        t.icon:SetVertexColor(1, 1, 1)
        t.shieldEdge:Hide()
    end
end

local function UpdateSocial()
    if tiles.friends then tiles.friends.count:SetText(#OnlineFriends()) end
    if tiles.guild then tiles.guild.count:SetText(IsInGuild() and #OnlineGuild() or "") end
    UpdateCrest()
end

---------------------------------------------------------------------------
-- Mythic+ portals
---------------------------------------------------------------------------

-- Spells in your spellbook flyouts (dungeon teleports live there): { spellID, known, desc }.
local function FlyoutSpells()
    local out = {}
    if not (GetFlyoutInfo and GetFlyoutSlotInfo) then return out end
    local bank = Enum.SpellBookSpellBank.Player
    for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
            local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
            if item and item.itemType == Enum.SpellBookItemType.Flyout then
                local _, _, numSlots = GetFlyoutInfo(item.actionID)
                for i = 1, numSlots or 0 do
                    local spellID, _, known = GetFlyoutSlotInfo(item.actionID, i)
                    if spellID then
                        local desc = C_Spell.GetSpellDescription(spellID)
                        if not desc or desc == "" then C_Spell.RequestLoadSpellData(spellID) end
                        out[#out + 1] = { spellID = spellID, known = known, desc = desc or "" }
                    end
                end
            end
        end
    end
    return out
end

local SMALL = { the = true, of = true, ["and"] = true, a = true }
local function Short(name)
    local words = {}
    for word in name:gmatch("[%w']+") do
        if not SMALL[word:lower()] then words[#words + 1] = word end
    end
    if #words == 1 then return words[1]:sub(1, 3) end -- "The Stonevault" -> "Sto"
    local letters = {}
    for i, w in ipairs(words) do letters[i] = w:sub(1, 1):upper() end
    return table.concat(letters)
end

-- This season's dungeons with their teleport (if you have one).
local function SeasonPortals()
    local maps = C_ChallengeMode.GetMapTable() or {}
    local spells = FlyoutSpells()
    local out = {}
    for _, mapID in ipairs(maps) do
        local name, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
        if name then
            local found
            for _, s in ipairs(spells) do
                if s.desc:find(name, 1, true) then found = s break end
            end
            out[#out + 1] = { mapID = mapID, name = name, short = Short(name), texture = texture,
                spellID = found and found.spellID, known = found and found.known }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function PortalButton(i)
    local b = portalButtons[i]
    if b then return b end
    b = SecureTile(flyout)
    b.label = b.edge:CreateFontString(nil, "OVERLAY")
    b.label:SetPoint("BOTTOM", 0, 2)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
        GameTooltip:AddLine(self.portal.name, 1, 1, 1)
        if self.portal.known then
            GameTooltip:AddLine(L["Click to teleport"], 0.2, 0.6, 1)
        else
            GameTooltip:AddLine(L["You don't have this teleport yet."], 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    b:HookScript("OnLeave", function() M:ScheduleFlyoutHide() end)
    b:HookScript("PostClick", function() if flyout and not InCombatLockdown() then flyout:Hide() end end)
    portalButtons[i] = b
    return b
end

-- Builds the flyout. Out of combat only (secure buttons).
local function BuildFlyout()
    local size = M.db.height + 6
    local list = SeasonPortals()
    for _, b in ipairs(portalButtons) do b:Hide() end
    local cols = 4
    for i, p in ipairs(list) do
        local b = PortalButton(i)
        b.portal = p
        b:SetSize(size, size)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", flyout, "TOPLEFT", 4 + ((i - 1) % cols) * (size + 3), -4 - math.floor((i - 1) / cols) * (size + 3))
        b.bg:SetColorTexture(0.05, 0.05, 0.06, 0.9)
        b.icon:SetTexture(p.texture or (p.spellID and C_Spell.GetSpellTexture(p.spellID)) or 134400)
        b.icon:SetDesaturated(not p.known)
        b.icon:SetAlpha(p.known and 1 or 0.45)
        b.label:SetFont(ns.Theme:Font(), math.max(9, math.floor(size * 0.3)), "OUTLINE")
        b.label:SetText(p.short)
        if p.known then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", p.spellID)
            local cd = C_Spell.GetSpellCooldown(p.spellID)
            local start, duration = cd and cd.startTime, cd and cd.duration
            if not ns.Secret.Is(duration) and type(duration) == "number" and duration > 1.5 then
                b.cd:SetCooldown(start, duration)
            else
                b.cd:Clear()
            end
        else
            b:SetAttribute("type", nil)
            b.cd:Clear()
        end
        b:Show()
    end
    local rows = math.max(1, math.ceil(#list / cols))
    flyout:SetSize(8 + math.min(math.max(#list, 1), cols) * (size + 3) - 3, 8 + rows * (size + 3) - 3)
    flyout.empty:SetShown(#list == 0)
    if #list == 0 then flyout:SetSize(220, 40) end
end

function M:ScheduleFlyoutHide()
    if self.flyoutTimer then self.flyoutTimer:Cancel() end
    self.flyoutTimer = C_Timer.NewTimer(0.6, function()
        self.flyoutTimer = nil
        if InCombatLockdown() then return end
        if flyout and flyout:IsShown() and not flyout:IsMouseOver() and not (tiles.portals and tiles.portals:IsMouseOver()) then
            flyout:Hide()
        end
    end)
end

local function ToggleFlyout()
    if InCombatLockdown() then return end
    if flyout:IsShown() then flyout:Hide() return end
    BuildFlyout()
    flyout:ClearAllPoints()
    flyout:SetPoint("TOP", tiles.portals, "BOTTOM", 0, -4)
    flyout:Show()
end

---------------------------------------------------------------------------
-- Building the bar
---------------------------------------------------------------------------

local function Create()
    if bar then return end
    bar = CreateFrame("Frame", "OrionUITopBar", UIParent) -- named: secure children need a stable parent
    bar:SetFrameStrata("LOW")
    bar:SetSize(1, 30)
    ns.Movers:Register("TopBar", { label = L["Top bar"], getFrame = function() return bar end, default = { x = 0, y = 360 } })

    local clock = PlainTile("clock")
    clock.icon:Hide()
    clock.text = clock.edge:CreateFontString(nil, "OVERLAY")
    clock.text:SetPoint("CENTER", 0, 0)
    -- Resting (inn or city): a small Zzz in the clock tile's top-right corner (Stig, 2026-10-02),
    -- animated: z, z, Z fade in one after another while drifting up, then fade out together
-- (every letter's loop is 2.45 s long, so they stay in step).
    -- Engine animation groups, so no OnUpdate; they only play while the Zzz is shown.
    local zzz = CreateFrame("Frame", nil, clock.edge)
    zzz:SetPoint("TOPRIGHT", -3, -2)
    zzz:SetSize(1, 1)
    zzz.letters, zzz.anims = {}, {}
    for i, ch in ipairs({ "z", "z", "Z" }) do
        local fs = zzz:CreateFontString(nil, "OVERLAY")
        fs:SetAlpha(0)
        fs.char = ch
        local ag = fs:CreateAnimationGroup()
        ag:SetLooping("REPEAT")
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0) fadeIn:SetToAlpha(1)
        fadeIn:SetStartDelay((i - 1) * 0.45) fadeIn:SetDuration(0.45) fadeIn:SetOrder(1)
        local rise = ag:CreateAnimation("Translation")
        rise:SetOffset(0, 2)
        rise:SetStartDelay((i - 1) * 0.45) rise:SetDuration(0.45) rise:SetOrder(1)
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1) fadeOut:SetToAlpha(0)
        fadeOut:SetStartDelay((3 - i) * 0.45 + 0.6) fadeOut:SetDuration(0.5) fadeOut:SetOrder(2)
        zzz.letters[i], zzz.anims[i] = fs, ag
    end
    zzz:SetScript("OnShow", function(self) for _, ag in ipairs(self.anims) do ag:Restart() end end)
    zzz:SetScript("OnHide", function(self) for _, ag in ipairs(self.anims) do ag:Stop() end end)
    zzz:Hide()
    clock.zzz = zzz
    clock:SetScript("OnEnter", ClockTooltip)
    clock:SetScript("OnClick", ClockClick)

    local friends = PlainTile("friends")
    friends.icon:SetTexture(ICONS .. "IconFriends")
    friends:SetScript("OnEnter", function(self)
        SocialTooltip(self, L["Friends"], OnlineFriends(), L["Left-click: open Friends"])
    end)
    friends:SetScript("OnClick", function() if ToggleFriendsFrame then ToggleFriendsFrame(1) end end)

    local guild = PlainTile("guild")
    guild.icon:SetTexture(ICONS .. "IconGuild")
    -- Shield rim (UpdateCrest), drawn over the shield fill that the icon texture holds.
    guild.shieldEdge = guild:CreateTexture(nil, "ARTWORK", nil, 1)
    guild.shieldEdge:SetAllPoints(guild.icon)
    guild.shieldEdge:SetTexture(ICONS .. "IconShieldEdge")
    guild.shieldEdge:Hide()
    guild:SetScript("OnEnter", function(self)
        if not IsInGuild() then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
            GameTooltip:AddLine(L["Not in a guild"], 1, 1, 1)
            GameTooltip:Show()
            return
        end
        local motd = GetGuildRosterMOTD and GetGuildRosterMOTD()
        SocialTooltip(self, GetGuildInfo("player") or L["Guild"], OnlineGuild(), L["Left-click: open Guild"],
            motd and motd ~= "" and motd or nil)
    end)
    guild:SetScript("OnClick", function() if ToggleGuildFrame then ToggleGuildFrame() end end)

    local hearth = SecureTile(bar)
    tiles.hearth = hearth
    -- Our own flat white house icon (same family as friends / guild / portals), not the toy's game art.
    hearth.icon:SetTexture(ICONS .. "IconHearth")
    hearth.icon:SetTexCoord(0, 1, 0, 1)
    hearth:SetScript("PreClick", function(_, button)
        if button == "LeftButton" and not InCombatLockdown() then M:RollHearth() end
    end)
    hearth:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
        GameTooltip:AddLine(L["Hearthstone"], 1, 1, 1)
        local bind = GetBindLocation and GetBindLocation()
        if bind then GameTooltip:AddDoubleLine(L["Bound to"], bind, 0.7, 0.7, 0.7, 1, 1, 1) end
        local start, duration = C_Item.GetItemCooldown(ns.Data.HEARTHSTONE_ITEM)
        if not ns.Secret.Is(duration) and type(duration) == "number" and duration > 1.5 then
            GameTooltip:AddDoubleLine(L["Cooldown"], Duration(start + duration - GetTime()), 0.7, 0.7, 0.7, 1, 0.4, 0.4)
        else
            GameTooltip:AddDoubleLine(L["Cooldown"], L["Ready"], 0.7, 0.7, 0.7, 0.37, 0.83, 0.37)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((M.db.travel.random and L["Left-click: random hearthstone"] or L["Left-click: Hearthstone"]) .. (self.leftID and (" |cff8a8a95(" .. L["next:"] .. " " .. ItemName(self.leftID) .. ")|r") or ""), 0.2, 0.6, 1)
        if self.middleID then GameTooltip:AddLine(L["Middle-click:"] .. " " .. ItemName(self.middleID), 0.2, 0.6, 1) end
        if self.rightID then GameTooltip:AddLine(L["Right-click:"] .. " " .. ItemName(self.rightID), 0.2, 0.6, 1) end
        GameTooltip:Show()
    end)

    local portals = PlainTile("portals")
    portals.icon:SetTexture(ICONS .. "IconPortal")
    portals:SetScript("OnClick", ToggleFlyout)
    portals:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
        GameTooltip:AddLine(L["Mythic+ portals"], 1, 1, 1)
        GameTooltip:AddLine(L["Click: this season's dungeon teleports"], 0.2, 0.6, 1)
        GameTooltip:Show()
    end)

    flyout = CreateFrame("Frame", "OrionUITopBarPortals", UIParent)
    flyout:SetFrameStrata("DIALOG")
    ns.Theme:Skin(flyout, { 0.05, 0.05, 0.06, 0.95 }, { 0, 0, 0, 1 })
    flyout.empty = ns.Theme:Text(flyout, 11, ns.Theme.colors.muted)
    flyout.empty:SetPoint("CENTER")
    flyout.empty:SetText(L["No Mythic+ season data yet."])
    flyout:EnableMouse(true)
    flyout:SetScript("OnLeave", function() M:ScheduleFlyoutHide() end)
    flyout:Hide()
    tinsert(UISpecialFrames, "OrionUITopBarPortals")

    -- FPS | MS: its own frame, so it stays when the tiles hide in combat.
    stats = CreateFrame("Frame", nil, UIParent)
    stats:SetFrameStrata("LOW")
    stats:SetSize(140, 14)
    statsText = stats:CreateFontString(nil, "OVERLAY")
    statsText:SetPoint("CENTER")
    statsText:SetShadowOffset(1, -1)
    statsText:SetShadowColor(0, 0, 0, 1)
end

function M:RollHearth()
    local t = tiles.hearth
    local pool = Pool()
    local id = #pool > 0 and pool[math.random(#pool)] or nil
    if id and #pool > 1 and id == t.leftID then id = pool[math.random(#pool)] end
    t.leftID = id
    t:SetAttribute("type1", "macro")
    t:SetAttribute("macrotext1", id and ("/use item:" .. id) or "")
    UpdateItemCooldown(t, id or ns.Data.HEARTHSTONE_ITEM)
end

-- Per mouse button: suffix "2" = right, "3" = middle (SecureActionButton attribute suffixes).
local function SetClickItem(t, suffix, id)
    t:SetAttribute("type" .. suffix, id and "macro" or nil)
    t:SetAttribute("macrotext" .. suffix, id and ("/use item:" .. id) or nil)
end

-- Extra buttons: item or toy IDs from the settings.
local function LayoutExtras(x, size)
    for _, b in ipairs(extra) do b:Hide() b:ClearAllPoints() spare[#spare + 1] = b end
    wipe(extra)
    for word in tostring(M.db.travel.extraItems or ""):gmatch("%d+") do
        local id = tonumber(word)
        local b = table.remove(spare) or SecureTile(bar)
        b.itemID = id
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext", "/use item:" .. id)
        b.icon:SetTexture(C_Item.GetItemIconByID(id) or 134400)
        b.bg:SetColorTexture(0.05, 0.05, 0.06, M.db.tileAlpha)
        RestBorder(b)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM", 0, -4)
            if HasToy(self.itemID) then GameTooltip:SetToyByItemID(self.itemID) else GameTooltip:SetItemByID(self.itemID) end
            GameTooltip:Show()
        end)
        b:SetSize(size, size)
        b:SetPoint("LEFT", bar, "LEFT", x, 0)
        UpdateItemCooldown(b, id)
        b:Show()
        extra[#extra + 1] = b
        x = x + size - 1
    end
    return x
end

-- Clock font (Stig, 2026-10-02: a fat clock). Expressway Bold comes from EllesmereUI (never bundled);
-- without EUI it falls back to our own Orion 2 Bold.
local CLOCK_FONTS = { orion2 = "Fonts\\Orion2-Bold.ttf", orion3 = "Fonts\\Orion3-Bold.ttf" }
local function ClockFont()
    local choice = M.db.clockFont
    if choice == "ui" then return ns.Theme:Font() end
    if choice == "bold" then
        local files = EllesmereUI and EllesmereUI.FONT_FILES
        if files and files["Expressway Bold"] and EllesmereUI.MEDIA_PATH then
            return EllesmereUI.MEDIA_PATH .. "fonts\\" .. files["Expressway Bold"]
        end
        choice = "orion2"
    end
    return ns.MEDIA_PATH .. (CLOCK_FONTS[choice] or CLOCK_FONTS.orion2)
end

local function ClockColor()
    local choice = M.db.clockColor
    if choice == "accent" then
        local r, g, b = ns.Theme:Accent()
        local scale = 1 / math.max(r, g, b, 0.01) -- brightened like the Zzz, so it reads on dark
        return math.min(1, r * scale), math.min(1, g * scale), math.min(1, b * scale)
    elseif choice == "class" then
        local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[select(2, UnitClass("player"))]
        if c then return c.r, c.g, c.b end
    end
    return 1, 1, 1
end

-- Whole layout. Out of combat only (secure buttons, state driver).
local function Layout()
    local db = M.db
    local size = db.height
    local font = ns.Theme:Font()
    for _, t in pairs(tiles) do
        t.bg:SetColorTexture(0.05, 0.05, 0.06, db.tileAlpha)
        RestBorder(t)
        t.count:SetFont(font, math.max(10, math.floor(size * 0.44)), "OUTLINE")
        t.count:SetShadowOffset(1, -1)
        t.count:SetShadowColor(0, 0, 0, 1)
        t:Hide()
    end
    tiles.friends.count:SetTextColor(0.37, 0.83, 0.37)
    tiles.guild.count:SetTextColor(1, 0.6, 0.2)

    -- Left side, clock, right side: one row with the clock centred on the bar.
    local left, right = {}, {}
    if db.social.friends then left[#left + 1] = tiles.friends end
    if db.social.guild then left[#left + 1] = tiles.guild end
    if db.travel.hearth then right[#right + 1] = tiles.hearth end
    if db.travel.portals then right[#right + 1] = tiles.portals end

    -- Tiles touch: each overlaps the previous one by 1px so neighbours share one black border
    -- (Stig, 2026-09-30: no gaps). The clock stays centred on the bar.
    local step = size - 1
    local clock = tiles.clock
    clock.text:SetFont(ClockFont(), db.clockSize, "OUTLINE")
    clock.text:SetTextColor(ClockColor())
    clock.text:SetShadowOffset(1, -1)
    clock.text:SetShadowColor(0, 0, 0, 1)
    clock.text:SetText(db.clock.clock24 and "00:00" or "12:00 PM")
    -- Zzz: small, in the same bright OrionUI blue as the FPS / MS values. The tile grows by its
    -- width on both sides so the time stays centred and never runs into it.
    -- Letters step up and to the right, each a little bigger (z z Z).
    local zSize, zW = math.max(8, math.floor(size * 0.3)), 0
    local blue = BlueHex()
    for i, fs in ipairs(clock.zzz.letters) do
        fs:SetFont(font, zSize - 3 + i, "OUTLINE")
        fs:SetText(blue .. fs.char .. "|r")
        zW = zW + math.ceil(fs:GetStringWidth())
    end
    local letters = clock.zzz.letters
    letters[3]:ClearAllPoints()
    letters[3]:SetPoint("TOPRIGHT", clock.zzz, "TOPRIGHT", 0, 0)
    letters[2]:ClearAllPoints()
    letters[2]:SetPoint("TOPRIGHT", letters[3], "TOPLEFT", 0, -3)
    letters[1]:ClearAllPoints()
    letters[1]:SetPoint("TOPRIGHT", letters[2], "TOPLEFT", 0, -3)
    local zzzW = db.clock.resting and (zW + 2) * 2 or 0
    local clockW = db.clock.show and math.max(size * 2, math.ceil(clock.text:GetStringWidth()) + 24 + zzzW) or 1
    local nExtra = 0
    for _ in tostring(db.travel.extraItems or ""):gmatch("%d+") do nExtra = nExtra + 1 end
    local leftW, rightW = #left * step, (#right + nExtra) * step
    local side = math.max(leftW, rightW)
    bar:SetSize(math.max(side * 2 + clockW, 1), size)

    local x = side - leftW
    for _, t in ipairs(left) do
        t:SetSize(size, size)
        t:ClearAllPoints()
        t:SetPoint("LEFT", bar, "LEFT", x, 0)
        t:Show()
        x = x + step
    end
    if db.clock.show then
        clock:SetSize(clockW, size)
        clock:ClearAllPoints()
        clock:SetPoint("LEFT", bar, "LEFT", side, 0)
        clock:Show()
    end
    x = side + clockW - 1
    for _, t in ipairs(right) do
        t:SetSize(size, size)
        t:ClearAllPoints()
        t:SetPoint("LEFT", bar, "LEFT", x, 0)
        t:Show()
        x = x + step
    end
    LayoutExtras(x, size)

    -- Hearthstone clicks.
    local h = tiles.hearth
    h.middleID, h.rightID = ResolveItem(db.travel.middleClick), ResolveItem(db.travel.rightClick)
    SetClickItem(h, "3", h.middleID)
    SetClickItem(h, "2", h.rightID)
    M:RollHearth()

    -- FPS | MS under the middle of the bar.
    stats:ClearAllPoints()
    stats:SetPoint("TOP", bar, "BOTTOM", 0, -3)
    statsText:SetFont(font, db.statsSize, "OUTLINE")
    stats:SetHeight(db.statsSize + 6)
    stats:SetShown(db.clock.stats)

    -- In combat only FPS | MS: a secure state driver hides the tiles (secure buttons included).
    if db.hideInCombat then
        RegisterStateDriver(bar, "visibility", "[combat] hide; show")
    else
        UnregisterStateDriver(bar, "visibility")
        bar:Show()
    end
    if flyout then flyout:Hide() end
    UpdateSocial()
    UpdateTexts()
    UpdateResting()
end

function M:Refresh()
    if not bar then return end
    ns.Combat:Defer("TopBar", Layout)
end

function M:OnEnable()
    Create()
    ns.Combat:Defer("TopBar", Layout)
    self:NewTicker(1, UpdateTexts)
    local function Cooldowns()
        if tiles.hearth then UpdateItemCooldown(tiles.hearth, tiles.hearth.leftID or ns.Data.HEARTHSTONE_ITEM) end
        for _, b in ipairs(extra) do UpdateItemCooldown(b, b.itemID) end
    end
    ns.Events:On("BAG_UPDATE_COOLDOWN", self, Cooldowns)
    ns.Events:On("SPELL_UPDATE_COOLDOWN", self, Cooldowns)
    ns.Events:On("TOYS_UPDATED", self, function() self:Refresh() end)
    ns.Events:On("BAG_UPDATE_DELAYED", self, function() self:Refresh() end)
    for _, ev in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE",
        "BN_FRIEND_ACCOUNT_OFFLINE", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "GUILDTABARD_UPDATE" }) do
        ns.Events:On(ev, self, function() ns.Events:Coalesce("topbar-social", UpdateSocial) end)
    end
    ns.Events:On("OUI_COMBAT_START", self, function() if flyout then flyout:Hide() end end)
    ns.Events:On("PLAYER_UPDATE_RESTING", self, UpdateResting)
    local function AskRoster() if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end end
    AskRoster()
    self:NewTicker(60, AskRoster)
end

function M:OnDisable()
    if flyout then flyout:Hide() end
    if stats then stats:Hide() end
    if bar then
        ns.Combat:Defer("TopBar", function()
            UnregisterStateDriver(bar, "visibility")
            bar:Hide()
        end)
    end
end
