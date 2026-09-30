-- Raid tools pages in OrionUI's options for the built-in RaidControl.
--
-- Hand-picked (Stig, 2026-09-30: the generated pages were unreadable): seven pages, each split
-- into sections, only the settings people actually change, with plain names. Everything else
-- keeps RaidControl's defaults. RaidControl stores its settings in its own AceDB
-- (OrionUIRaidControlDB); these pages read and write that profile directly.
local _, ns = ...

local L = ns.L

local function Profile() return ns.RC and ns.RC.db and ns.RC.db.profile end
local function Defaults() return ns.RC and ns.RC.db and ns.RC.db.defaults and ns.RC.db.defaults.profile end

local MARKERS = {
    { value = 1, text = L["Star"] }, { value = 2, text = L["Circle"] }, { value = 3, text = L["Diamond"] },
    { value = 4, text = L["Triangle"] }, { value = 5, text = L["Moon"] }, { value = 6, text = L["Square"] },
    { value = 7, text = L["Cross"] }, { value = 8, text = L["Skull"] },
}
local MODIFIERS = { { value = "SHIFT", text = L["Shift"] }, { value = "CTRL", text = L["Ctrl"] }, { value = "ALT", text = L["Alt"] } }

-- Row: { key, label, [kind = "slider"|"input"|"dropdown"|"color"], min, max, step, values, invert, desc }
-- A toggle unless kind says otherwise; invert shows the opposite of a "hide..." setting.
local PAGES = {
    { id = "RC_Launcher", label = L["Launcher"], order = 1,
      desc = L["The RaidControl launcher bar and its drop-down menu."],
      sections = {
        { L["Launcher"], {
            { "hideTopBar", L["Show the launcher bar"], invert = true },
            { "hideLauncherWhenSolo", L["Hide it when I'm not in a group"] },
            { "hideBlizzardRaidControl", L["Hide Blizzard's raid manager"] },
            { "topBarScale", L["Launcher size"], kind = "slider", min = 0.5, max = 2, step = 0.05 },
            { "menuScale", L["Menu size"], kind = "slider", min = 0.5, max = 2, step = 0.05 },
        } },
        { L["Menu buttons"], {
            { "showReadyButton", L["Ready check"] },
            { "showPullButton", L["Pull timer"] },
            { "showConvertButton", L["Convert party / raid"] },
            { "showDifficultyButton", L["Difficulty"] },
            { "showInviteButton", L["Guild invite"] },
            { "showClearButton", L["Clear markers"] },
            { "showDisbandButton", L["Disband group"] },
            { "showScreenshotButton", L["Screenshot"] },
            { "hideRoles", L["Show tank / healer / DPS counts"], invert = true },
        } },
        { L["Pull timer"], {
            { "pullTimerDuration", L["Pull timer length (seconds)"], kind = "slider", min = 3, max = 30, step = 1 },
            { "pullTimerAddon", L["Send the pull timer through"], kind = "dropdown", values = {
                { value = "auto", text = L["Automatic"] }, { value = "bigwigs", text = "BigWigs" },
                { value = "dbm", text = "DBM" }, { value = "ert", text = "MRT" }, { value = "none", text = L["Blizzard only"] } } },
        } },
        { L["Markers"], {
            { "hideMarkers", L["Show marker buttons"], invert = true },
            { "showDropdownMarkers", L["Markers in the drop-down menu"] },
            { "enableTargetMarkers", L["Click marks your target"] },
            { "enableWorldMarkers", L["Modifier-click places a world marker"] },
            { "worldMarkerModifier", L["World marker modifier"], kind = "dropdown", values = MODIFIERS },
            { "cycleMarkerModifier", L["Cycle keybind modifier"], kind = "dropdown", values = MODIFIERS },
        } },
      } },

    { id = "RC_ActionStrip", label = L["Action strip"], order = 2,
      desc = L["A slim row of raid buttons you can place anywhere. Move it with /oui edit or RaidControl's layout mode."],
      sections = {
        { L["Action strip"], {
            { "showActionStrip", L["Show the action strip"] },
            { "actionStripScale", L["Size"], kind = "slider", min = 0.5, max = 2, step = 0.05 },
            { "showActionStripMarkers", L["Include marker buttons"] },
        } },
        { L["Buttons"], {
            { "actionStripShowReady", L["Ready check"] },
            { "actionStripShowPull", L["Pull timer"] },
            { "actionStripShowConvert", L["Convert party / raid"] },
            { "actionStripShowDifficulty", L["Difficulty"] },
            { "actionStripShowInvite", L["Guild invite"] },
            { "actionStripShowClearTarget", L["Clear target markers"] },
            { "actionStripShowClearWorld", L["Clear world markers"] },
            { "actionStripShowDisband", L["Disband group"] },
            { "actionStripShowScreenshot", L["Screenshot"] },
        } },
      } },

    { id = "RC_RaidSplit", label = L["Raid split"], order = 3,
      desc = L["How Smart Split builds groups. Open Raid Split from the launcher or with /oui split."],
      sections = {
        { L["Smart split"], {
            { "smartSplitMonk", L["Spread Monks across groups"], desc = L["Mystic Touch: +5% physical damage taken."] },
            { "smartSplitDH", L["Spread Demon Hunters across groups"], desc = L["Chaos Brand: +5% magic damage taken."] },
            { "smartSplitBalanceDPS", L["Balance DPS between groups"], desc = L["Uses Details! damage numbers."] },
            { "smartSplitKeepSelfG1", L["Always keep me in group 1"] },
            { "smartSplitTwoWayOddEven", L["Two-way split: odd groups vs even groups"] },
            { "smartSplitTanks", L["Tanks per group"], kind = "dropdown", values = {
                { value = 0, text = L["Automatic"] }, { value = 1, text = "1" }, { value = 2, text = "2" } } },
            { "smartSplitHealers", L["Healers per group"], kind = "dropdown", values = {
                { value = 0, text = L["Automatic"] }, { value = 1, text = "1" }, { value = 2, text = "2" },
                { value = 3, text = "3" }, { value = 4, text = "4" }, { value = 5, text = "5" } } },
        } },
        { L["Player tooltip shows"], {
            { "raidSplitTooltipName", L["Name"] },
            { "raidSplitTooltipLevel", L["Item level"] },
            { "raidSplitTooltipRole", L["Role"] },
            { "raidSplitTooltipSpec", L["Specialization"] },
        } },
      } },

    { id = "RC_Ready", label = L["Ready check"], order = 4,
      desc = L["RaidControl's ready check window, consumables and durability checks."],
      sections = {
        { L["Ready check"], {
            { "enableReadyTracker", L["Track ready checks"] },
            { "useCustomReadyCheck", L["Use RaidControl's ready check window"] },
            { "readyTrackerMissingOnly", L["Only list people who aren't ready"] },
            { "readyTrackerAutoCloseSeconds", L["Close the window after (seconds)"], kind = "slider", min = 0, max = 30, step = 1 },
            { "readyTrackerWhisperMissing", L["Whisper people who aren't ready"] },
            { "announceReadySlackers", L["Announce who isn't ready in chat"] },
        } },
        { L["Consumables and buffs"], {
            { "enableConsumableChecker", L["Check food, flasks and runes"] },
            { "whisperSlackers", L["Whisper people who are missing them"] },
            { "reportToChat", L["Post the result in chat"] },
            { "enableSynergyAnalyzer", L["Warn about missing raid buffs"] },
        } },
        { L["Durability"], {
            { "enableDurabilityComm", L["Share durability with the group"] },
            { "durabilityReadyCheckRequest", L["Ask for durability on ready check"] },
            { "durabilityWarnThreshold", L["Warn below (percent)"], kind = "slider", min = 5, max = 90, step = 5 },
        } },
      } },

    { id = "RC_Lead", label = L["Lead tools"], order = 5,
      desc = L["Tools for raid leaders: who pulled, keystones, battle res and healer mana."],
      sections = {
        { L["General"], {
            { "enableRaidLeadTools", L["Enable lead tools"] },
            { "enableWhoPulled", L["Tell me who pulled"] },
            { "whoPulledChatPrint", L["Print it in chat"] },
            { "enableKeySync", L["Share Mythic+ keystones with the group"] },
        } },
        { L["Battle res"], {
            { "enableBattleResTracker", L["Track battle res charges"] },
            { "showBattleResFrame", L["Show the battle res frame"] },
            { "battleResShowTimer", L["Show the recharge timer"] },
            { "battleResShowRecent", L["List recent battle resses"] },
            { "battleResScale", L["Size"], kind = "slider", min = 0.5, max = 2, step = 0.05 },
        } },
        { L["Healer mana"], {
            { "showHealerManaFrame", L["Show healer mana"] },
            { "healerManaEnableInRaid", L["In raids"] },
            { "healerManaEnableInDungeons", L["In dungeons"] },
            { "healerManaOnlyIfPlayerIsHealer", L["Only when I'm a healer"] },
            { "healerManaShowDrinking", L["Show who is drinking"] },
            { "healerManaLowThreshold", L["Low mana below (percent)"], kind = "slider", min = 5, max = 80, step = 5 },
            { "healerManaScale", L["Size"], kind = "slider", min = 0.5, max = 2, step = 0.05 },
        } },
      } },

    { id = "RC_TankAssist", label = L["Tank assist"], order = 6,
      desc = L["RaidControl's tank swap, defensive and movement calls. OrionUI's defensive reminders are separate (Reminders)."],
      sections = {
        { L["Tank assist"], {
            { "enableTankAssist", L["Enable tank assist"] },
            { "tankAssistTanksOnly", L["Only when I'm a tank"] },
            { "tankAssistEncounterOnly", L["Only during boss fights"] },
            { "tankAssistEnableDungeonBusters", L["Include dungeon tank busters"] },
            { "tankAssistCoTankName", L["Co-tank name (empty = automatic)"], kind = "input" },
        } },
        { L["Calls"], {
            { "tankAssistTauntEnabled", L["Taunt swaps"] },
            { "tankAssistDefensiveEnabled", L["Defensives"] },
            { "tankAssistMovementEnabled", L["Movement"] },
            { "tankAssistDefensiveLeadSeconds", L["Defensive call this early (seconds)"], kind = "slider", min = 1, max = 10, step = 0.5 },
            { "tankAssistMovementLeadSeconds", L["Movement call this early (seconds)"], kind = "slider", min = 1, max = 15, step = 0.5 },
            { "tankAssistAlertCooldown", L["Don't repeat a call within (seconds)"], kind = "slider", min = 0, max = 20, step = 1 },
        } },
        { L["Sound and display"], {
            { "tankAssistSoundEnabled", L["Play sounds"] },
            { "tankAssistTtsVolume", L["Voice volume"], kind = "slider", min = 0, max = 100, step = 5 },
            { "tankAssistShowVisual", L["Show the alert"] },
            { "tankAssistShowTimerBars", L["Show timer bars"] },
            { "tankAssistFrameScale", L["Size"], kind = "slider", min = 0.5, max = 2, step = 0.05 },
            { "tankAssistTauntColor", L["Taunt colour"], kind = "color" },
            { "tankAssistDefensiveColor", L["Defensive colour"], kind = "color" },
            { "tankAssistMovementColor", L["Movement colour"], kind = "color" },
        } },
      } },

    { id = "RC_Automation", label = L["Automation"], order = 7,
      desc = L["Things RaidControl can do for you: invites, assists, role markers, combat logging, repairs, screenshots."],
      sections = {
        { L["Auto invite"], {
            { "enableAutoInvite", L["Invite people who whisper the keyword"] },
            { "autoInviteKeyword", L["Keyword"], kind = "input" },
            { "inviteRestriction", L["Who can use it"], kind = "dropdown", values = {
                { value = "Anyone", text = L["Anyone"] }, { value = "Guild Only", text = L["Guild only"] },
                { value = "Friends Only", text = L["Friends only"] } } },
            { "autoConvertKeywordInvites", L["Turn the party into a raid when needed"] },
        } },
        { L["Auto assist"], {
            { "enableAutoAssist", L["Give assist automatically"] },
            { "autoAssistOfficers", L["To guild officers"] },
            { "autoAssistMinRank", L["Up to guild rank (1 = Guild Master)"], kind = "slider", min = 1, max = 10, step = 1 },
            { "autoAssistList", L["And these names (comma separated)"], kind = "input" },
            { "enableAutoMainTanks", L["Set main tanks automatically"] },
        } },
        { L["Role markers"], {
            { "autoMarkTanks", L["Mark tanks"] },
            { "autoMarkTanksIcon", L["Tank marker"], kind = "dropdown", values = MARKERS },
            { "autoMarkHealers", L["Mark healers"] },
            { "autoMarkHealersIcon", L["Healer marker"], kind = "dropdown", values = MARKERS },
            { "autoMarkRolesDungeonOnly", L["Only in dungeons"] },
        } },
        { L["Combat logging"], {
            { "enableCombatLogger", L["Help with combat logging"] },
            { "combatLogPrompt", L["Ask before logging"] },
            { "logRaid", L["In raids"] },
            { "logParty", L["In dungeons"] },
            { "logArena", L["In arenas"] },
            { "logBG", L["In battlegrounds"] },
        } },
        { L["Repair and junk"], {
            { "enableAutoRepair", L["Repair automatically"] },
            { "useGuildRepair", L["Use guild funds first"] },
            { "enableAutoSellJunk", L["Sell grey items automatically"] },
        } },
        { L["Screenshot mode"], {
            { "screenshotHideUI", L["Hide the UI for the screenshot"] },
            { "screenshotApplyMaxGraphics", L["Use maximum graphics for the screenshot"] },
            { "screenshotFormat", L["File format"], kind = "dropdown", values = {
                { value = "jpg", text = "JPG" }, { value = "png", text = "PNG" }, { value = "tga", text = "TGA" } } },
            { "screenshotQuality", L["Quality"], kind = "slider", min = 1, max = 10, step = 1 },
            { "screenshotDelay", L["Delay (seconds)"], kind = "slider", min = 0, max = 5, step = 0.5 },
        } },
      } },
}

-- Applies every setting the way RaidControl's own settings window did (its "refresh after
-- profile import" routine): scales through their Apply functions, then each module's refresh.
local function Call(obj, fn, ...)
    if obj and type(obj[fn]) == "function" then ns.SafeCall("RaidControl:" .. fn, obj[fn], obj, ...) end
end

local function Changed()
    local rc = ns.RC
    if not rc then return end
    local p = rc.db.profile
    local function Mod(name) return rc:GetModule(name, true) end
    p.useClassColor = false -- OrionUI stays blue
    Call(rc, "ApplyTheme", p.theme or "Starforge", false)
    local legacy = p.launcherScale or p.scale or 1
    Call(rc, "ApplyTopBarScale", p.topBarScale or legacy)
    Call(rc, "ApplyMenuScale", p.menuScale or legacy)
    Call(rc, "ApplyInterfaceVisibility")
    Call(rc, "RefreshLayout")
    Call(rc, "RefreshTheme", false)
    local control = Mod("Control")
    Call(control, "RefreshButtonVisibility")
    Call(control, "RefreshModifierAttributes")
    Call(Mod("Markers"), "RefreshModifierAttributes")
    local strip = Mod("ActionStrip")
    Call(strip, "RefreshButtonVisibility")
    Call(strip, "UpdateVisibility")
    Call(strip, "UpdateScale", p.actionStripScale or 1)
    Call(strip, "RefreshModifierAttributes")
    local lead = Mod("RaidLeadTools")
    Call(lead, "ApplyBattleResScale", p.battleResScale or 1)
    Call(lead, "ApplyHealerManaScale", p.healerManaScale or 1)
    Call(lead, "ApplyBattleResDisplaySettings")
    Call(lead, "UpdateBattleResFrame")
    Call(lead, "UpdateHealerManaFrame", true)
    Call(lead, "RefreshRaidStatusDisplays")
    local tank = Mod("TankAssist")
    Call(tank, "ApplyEnabledState")
    Call(tank, "RefreshRuntimeSettings")
    Call(tank, "ApplyFrameSettings")
    Call(Mod("AutoMarker"), "ApplySettings")
    Call(Mod("ReadyTracker"), "ApplySettings")
end

local function Spec(row)
    local key, def = row[1], Defaults()[row[1]]
    local function Get()
        local v = Profile()[key]
        if v == nil then v = def end
        return v
    end
    local function Set(v) Profile()[key] = v; Changed() end
    local s = { label = row[2], desc = row.desc, path = key }
    local kind = row.kind or "toggle"
    if kind == "toggle" then
        s.type = "Toggle"
        if row.invert then
            s.get = function() return not Get() end
            s.set = function(v) Set(not v) end
        else
            s.get, s.set = Get, Set
        end
    elseif kind == "slider" then
        s.type, s.min, s.max, s.step = "Slider", row.min, row.max, row.step
        s.get = function() return tonumber(Get()) or row.min end
        s.set = Set
    elseif kind == "dropdown" then
        s.type, s.values, s.get, s.set = "Dropdown", row.values, Get, Set
    elseif kind == "input" then
        s.type = "Input"
        s.get = function() return tostring(Get() or "") end
        s.set = Set
    elseif kind == "color" then
        s.type = "Color"
        s.get = function() local c = Get() or {} return { c.r or 1, c.g or 1, c.b or 1, c.a or 1 } end
        s.set = function(v) Set({ r = v[1], g = v[2], b = v[3], a = v[4] }) end
    end
    return s
end

local function Specs(page)
    if not ns.RC then
        return { { type = "Description", label = L["Raid tools are off because the standalone RaidControl addon is enabled."] } }
    end
    if not Defaults() then return { { type = "Description", label = L["Raid tools haven't finished loading yet."] } } end
    local out = {}
    for _, section in ipairs(page.sections) do
        out[#out + 1] = { type = "Header", label = section[1] }
        for _, row in ipairs(section[2]) do
            if Defaults()[row[1]] ~= nil then out[#out + 1] = Spec(row) end -- skip keys this build lacks
        end
    end
    out[#out + 1] = { type = "Header", label = L["Apply"] }
    out[#out + 1] = { type = "Description", label = L["Most changes show right away; a few need a /reload."] }
    out[#out + 1] = { type = "Button", label = L["Reload UI"], func = ReloadUI }
    return out
end

for _, page in ipairs(PAGES) do
    ns.Modules:New(page.id, {
        category = "raid", label = page.label, order = page.order, desc = page.desc,
        options = function() return Specs(page) end,
    })
end

-- Opens RaidControl's Raid Split window from OrionUI.
ns.Slash:Register("split", function()
    local rc = ns.RC
    local split = rc and rc:GetModule("RaidSplit", true)
    if split and split.Open then split:Open() elseif split and split.Toggle then split:Toggle() end
end, "open Raid Split")
