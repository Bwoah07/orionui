-- Raid tools pages in OrionUI's options, generated from RaidControl's own settings defaults.
-- RaidControl keeps its settings in its own AceDB (OrionUIRaidControlDB); these pages read and
-- write that table directly. Settings are grouped by key prefix; each value's type picks the
-- widget. Hand-tuned pages can replace a group later.
local _, ns = ...

local L = ns.L

-- Ordered: the first matching pattern decides a key's page. Page id -> label.
local GROUPS = {
    { id = "RC_Launcher", label = L["Launcher and markers"], order = 1, match = {
        "^hideTopBar$", "^hideMenu$", "^hideLauncherWhenSolo$", "^hideBlizzardRaidControl$", "^launcherScale$",
        "^topBarScale$", "^menuScale$", "^useClassColor$", "^show%a+Button$", "^pullTimer", "^hideMarkers$",
        "^showDropdownMarkers$", "^showActionStripMarkers$", "^hideRoles$", "^enable%a*Markers$",
        "^worldMarkerModifier$", "^cycleMarkerModifier$", "^theme$" } },
    { id = "RC_ActionStrip", label = L["Action strip"], order = 2, match = { "^showActionStrip$", "^lockActionStrip$", "^actionStrip" } },
    { id = "RC_RaidSplit", label = L["Raid split"], order = 3, match = { "^smartSplit", "^raidSplitTooltip" } },
    { id = "RC_Ready", label = L["Ready check"], order = 4, match = {
        "^enableReadyTracker$", "^readyTracker", "^announceReadySlackers$", "^useCustomReadyCheck$",
        "^enableConsumableChecker$", "^whisperSlackers$", "^reportToChat$", "^enableSynergyAnalyzer$",
        "^enableDurabilityComm$", "^durability" } },
    { id = "RC_Lead", label = L["Lead tools"], order = 5, match = {
        "^enableRaidLeadTools$", "^enableWhoPulled$", "^whoPulled", "^enableKeySync$" } },
    { id = "RC_BattleRes", label = L["Battle res"], order = 6, match = { "^enableBattleResTracker$", "^showBattleResFrame$", "^battleRes" } },
    { id = "RC_HealerMana", label = L["Healer mana"], order = 7, match = { "^showHealerManaFrame$", "^healerMana" } },
    { id = "RC_TankAssist", label = L["Tank assist"], order = 8, match = { "^enableTankAssist$", "^tankAssist" } },
    { id = "RC_AutoMarker", label = L["Auto marker"], order = 9, match = { "^autoMark" } },
    { id = "RC_Group", label = L["Invites and assists"], order = 10, match = {
        "^enableAutoInvite$", "^autoInviteKeyword$", "^inviteRestriction$", "^autoConvertKeywordInvites$",
        "^enableAutoAssist$", "^enableAutoMainTanks$", "^autoAssist" } },
    { id = "RC_Logging", label = L["Combat logging"], order = 11, match = { "^enableCombatLogger$", "^combatLogPrompt$", "^log%u" } },
    { id = "RC_Vendor", label = L["Repair and junk"], order = 12, match = { "^enableAutoRepair$", "^useGuildRepair$", "^enableAutoSellJunk$" } },
    { id = "RC_Screenshot", label = L["Screenshots"], order = 13, match = { "^screenshot" } },
}

-- Never shown: positions, legacy keys, notes (not part of OrionUI), internal state.
local SKIP = { "Pos$", "Migration", "^bossNotes", "^noteReminder", "^enableNoteReminders", "^raidNote",
    "^enableRaidNotes", "^nsrt", "Locked$", "^lockFrames$", "PromptDismissed$", "Scale$" }
-- ...except these scale settings, which are real options.
local SCALE_OK = { launcherScale = true, topBarScale = true, menuScale = true, actionStripScale = true,
    battleResScale = true, healerManaScale = true, tankAssistFrameScale = true, autoMarkRoleButtonScale = true }

-- Known choices for text settings.
local ENUMS = {
    inviteRestriction = { "Anyone", "Guild Only", "Friends Only" },
    pullTimerAddon = { "auto", "bigwigs", "dbm", "ert", "none" },
    worldMarkerModifier = { "SHIFT", "CTRL", "ALT" },
    cycleMarkerModifier = { "SHIFT", "CTRL", "ALT" },
    healerManaGrowDirection = { "DOWN", "UP" },
    tankAssistTimerGrowth = { "DOWN", "UP" },
    tankAssistTextAlign = { "LEFT", "CENTER", "RIGHT" },
    battleResTimerFormat = { "mmss", "seconds" },
    screenshotFormat = { "jpg", "png", "tga" },
}

local PREFIXES = { "actionStrip", "smartSplit", "raidSplit", "readyTracker", "battleRes", "healerMana",
    "tankAssist", "autoMark", "autoAssist", "screenshot", "durability", "whoPulled", "combatLog" }

local function RC() return ns.RC end
local function Profile() return ns.RC and ns.RC.db and ns.RC.db.profile end
local function Defaults() return ns.RC and ns.RC.db and ns.RC.db.defaults and ns.RC.db.defaults.profile end

local function Skipped(key)
    if SCALE_OK[key] then return false end
    for _, p in ipairs(SKIP) do if key:find(p) then return true end end
    return false
end

local function GroupOf(key)
    for _, g in ipairs(GROUPS) do
        for _, p in ipairs(g.match) do if key:find(p) then return g.id end end
    end
end

-- "tankAssistTauntCountdownSeconds" -> "Taunt countdown seconds"
local function Label(key)
    for _, p in ipairs(PREFIXES) do
        if key:sub(1, #p) == p and #key > #p then key = key:sub(#p + 1) break end
    end
    local words = key:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
    words = words:lower():gsub("^%l", string.upper)
    return words
end

local function IsColor(v) return type(v) == "table" and type(v.r) == "number" and type(v.g) == "number" end

local function NumberSpec(key, def)
    local lk = key:lower()
    if lk:find("alpha") then return 0, 1, 0.05 end
    if lk:find("scale") then return 0.5, 2, 0.05 end
    if def == math.floor(def) then return 0, math.max(10, def * 3), 1 end
    return 0, math.max(1, def * 3), 0.1
end

-- Settings apply live where RaidControl's modules re-read them; many layout ones need a reload.
local function Changed()
    local rc = RC()
    if not rc then return end
    if rc.RefreshLayout then ns.SafeCall("RaidControl", rc.RefreshLayout, rc) end
    if rc.ApplyInterfaceVisibility then ns.SafeCall("RaidControl", rc.ApplyInterfaceVisibility, rc) end
    for name, mod in rc:IterateModules() do
        for _, fn in ipairs({ "Refresh", "RefreshLayout", "ApplySettings", "UpdateLayout" }) do
            if type(mod[fn]) == "function" and mod:IsEnabled() then
                ns.SafeCall("RaidControl:" .. name, mod[fn], mod)
                break
            end
        end
    end
end

local function Specs(groupId)
    local out = {}
    if not RC() then
        return { { type = "Description", label = L["The standalone RaidControl addon is enabled, so OrionUI's raid tools stay off. Disable one of them."] } }
    end
    local defaults = Defaults()
    if not defaults then return { { type = "Description", label = L["Raid tools haven't finished loading yet."] } } end
    local keys = {}
    for key, def in pairs(defaults) do
        local t = type(def)
        if (t == "boolean" or t == "number" or t == "string" or IsColor(def)) and not Skipped(key) and GroupOf(key) == groupId then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b)
        local ea, eb = a:find("^enable") or a:find("^show"), b:find("^enable") or b:find("^show")
        if (ea and 1 or 0) ~= (eb and 1 or 0) then return ea ~= nil end
        return a < b
    end)
    for _, key in ipairs(keys) do
        local def = defaults[key]
        local spec = { label = Label(key), path = key }
        if type(def) == "boolean" then
            spec.type = "Toggle"
            spec.get = function() local v = Profile()[key]; if v == nil then return def end return v end
            spec.set = function(v) Profile()[key] = v; Changed() end
        elseif type(def) == "number" then
            spec.type = "Slider"
            spec.min, spec.max, spec.step = NumberSpec(key, def)
            spec.get = function() return tonumber(Profile()[key]) or def end
            spec.set = function(v) Profile()[key] = v; Changed() end
        elseif type(def) == "string" then
            spec.type = ENUMS[key] and "Dropdown" or "Input"
            spec.values = ENUMS[key]
            spec.get = function() return Profile()[key] or def end
            spec.set = function(v) Profile()[key] = v; Changed() end
        else -- colour {r,g,b,a}
            spec.type = "Color"
            spec.hasAlpha = def.a ~= nil
            spec.get = function()
                local c = Profile()[key] or def
                return { c.r, c.g, c.b, c.a or 1 }
            end
            spec.set = function(v)
                Profile()[key] = { r = v[1], g = v[2], b = v[3], a = def.a ~= nil and v[4] or nil }
                Changed()
            end
        end
        out[#out + 1] = spec
    end
    out[#out + 1] = { type = "Description", label = L["Some of these only change after a /reload."] }
    out[#out + 1] = { type = "Button", label = L["Reload UI"], func = ReloadUI }
    return out
end

for _, g in ipairs(GROUPS) do
    local id = g.id
    ns.Modules:New(id, {
        category = "raid", label = g.label, order = g.order,
        options = function() return Specs(id) end,
    })
end

-- Opens RaidControl's Raid Split window from OrionUI.
ns.Slash:Register("split", function()
    local rc = RC()
    local split = rc and rc:GetModule("RaidSplit", true)
    if split and split.Open then split:Open() elseif split and split.Toggle then split:Toggle() end
end, "open Raid Split")
