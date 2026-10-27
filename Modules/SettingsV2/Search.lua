local _, ns = ...
local RC = ns.RC
local L = RC.L

RC.SettingsV2 = RC.SettingsV2 or {}
local V2 = RC.SettingsV2

V2.Search = V2.Search or {}
local Search = V2.Search

local INDEX = {
    { label = "Show Top Bar and Dropdown", page = "interface", tab = "layout", path = "Interface > General", keywords = "launcher menu visibility hide open" },
    { label = "Enable Action Strip", page = "interface", tab = "action_strip", path = "Interface > Action Strip", keywords = "quick bar visibility" },
    { label = "Loot Window", page = "interface", tab = "loot", path = "Interface > Loot Window", keywords = "loot window roll need greed transmog pass item drop" },
    { label = "Tank and Healer Role Marks", page = "interface", tab = "marks", path = "Interface > Role Marks", keywords = "mark tank healer square circle mythic dungeon auto marker role reminder button" },
    { label = "Marker Clicks", page = "interface", tab = "layout", path = "Interface > General", keywords = "raid target world marker modifier shift ctrl alt click dropdown action strip" },
    { label = "Show Blizzard Raid Tools", page = "interface", tab = "layout", path = "Interface > General", keywords = "default compact raid manager panel hide blizzard stupid raid tools" },
    { label = "Unlock and Move UI", page = "interface", tab = "layout", path = "Unlock UI button at the bottom of this window", keywords = "edit mode layout lock frames drag reposition" },

    { label = "Dropdown Buttons", page = "interface", tab = "buttons", path = "Interface > Dropdown", keywords = "menu actions visibility" },
    { label = "Ready Check Button", page = "interface", tab = "buttons", path = "Interface > Dropdown", keywords = "ready action" },
    { label = "Pull Timer Button", page = "interface", tab = "buttons", path = "Interface > Dropdown", keywords = "countdown action" },
    { label = "Convert Group Button", page = "interface", tab = "buttons", path = "Interface > Dropdown", keywords = "raid party conversion" },
    { label = "Difficulty Button", page = "interface", tab = "buttons", path = "Interface > Dropdown", keywords = "mythic heroic normal" },
    { label = "Invite Button", page = "interface", tab = "buttons", path = "Interface > Dropdown", keywords = "guild group" },
    { label = "Disband Button", page = "interface", tab = "buttons", path = "Interface > Dropdown", keywords = "remove group" },
    { label = "Screenshot Button", page = "interface", tab = "buttons", path = "Interface > Dropdown", keywords = "shot capture" },
    { label = "Dropdown Markers", page = "interface", tab = "buttons", path = "Interface > Dropdown", keywords = "raid target world marker icons" },
    { label = "Role Display", page = "interface", tab = "buttons", path = "Interface > Dropdown", keywords = "tank healer damage counts" },

    { label = "Action Strip Visibility", page = "interface", tab = "action_strip", path = "Interface > Action Strip", keywords = "quick bar mouseover" },
    { label = "Action Strip Layout", page = "interface", tab = "action_strip", path = "Interface > Action Strip", keywords = "orientation rows columns spacing size scale" },
    { label = "Action Strip Buttons", page = "interface", tab = "action_strip", path = "Interface > Action Strip", keywords = "ready pull convert difficulty invite disband shot" },
    { label = "Action Strip Markers", page = "interface", tab = "action_strip", path = "Interface > Action Strip", keywords = "raid target world marker icons" },
    { label = "Marker Bar Preset", page = "interface", tab = "action_strip", path = "Interface > Action Strip", keywords = "icons layout" },

    { label = "Ready Check Tracker", page = "ready", path = "Ready Check", keywords = "responses prepared missing consumables" },
    { label = "Ready Responses", page = "ready", path = "Ready Check", keywords = "ready not ready waiting offline afk slackers whisper announce" },
    { label = "Consumable Scan", page = "ready", path = "Ready Check", keywords = "food flask rune weapon oil buff" },
    { label = "Ready Check Position", page = "ready", path = "Ready Check", keywords = "move preview reset layout scale opacity" },

    { label = "Tank Assist", page = "tank", tab = "overview", path = "Tank > Overview", keywords = "enable co tank cotank swap taunt stacks boss dungeon mythic tank buster" },
    { label = "Co-Tank Tracking", page = "tank", tab = "overview", path = "Tank > Overview", keywords = "tank target ownership manual name override detect" },
    { label = "Tank Quick Setup", page = "tank", tab = "overview", path = "Tank > Overview", keywords = "preset clean hud text sound silent mute" },
    { label = "Tank Frame Position and Size", page = "tank", tab = "overview", path = "Tank > Overview", keywords = "preview move reset layout unlock lock drag scale opacity" },
    { label = "Bone Shield", page = "tank", tab = "bone", path = "Tank > Bone Shield", keywords = "blood death knight dk stacks ossuary marrowrend icon cooldown manager" },
    { label = "Tank Warning Types", page = "tank", tab = "warnings", path = "Tank > Warnings", keywords = "taunt swap movement enable disable" },
    { label = "Tank Warning Style", page = "tank", tab = "warnings", path = "Tank > Warnings", keywords = "text only panel compact hud screen display alert detail icon timer font size width alignment background opacity" },
    { label = "Tank Warning Colors", page = "tank", tab = "warnings", path = "Tank > Warnings", keywords = "taunt swap movement timer bar color" },
    { label = "Tank Warning Timing", page = "tank", tab = "warnings", path = "Tank > Warnings", keywords = "movement lead repeat lockout duration seconds" },
    { label = "Upcoming Tank Timer Bars", page = "tank", tab = "timers", path = "Tank > Timer Bars", keywords = "taunt swap movement countdown upcoming mechanic look ahead horizon maximum bars" },
    { label = "Tank Timer Bar Layout", page = "tank", tab = "timers", path = "Tank > Timer Bars", keywords = "width height spacing direction grow stack font background opacity icons labels seconds" },
    { label = "Tank Assist Sound Output", page = "tank", tab = "sounds", path = "Tank > Sounds", keywords = "mute silent disable enable master channel sharedmedia tts volume custom file" },
    { label = "Taunt and Swap Sounds", page = "tank", tab = "sounds", path = "Tank > Sounds", keywords = "taunt sound alert channel sharedmedia search sound library preview voice countdown" },
    { label = "Movement Sounds", page = "tank", tab = "sounds", path = "Tank > Sounds", keywords = "separate movement sound alert channel sharedmedia voice countdown" },
    { label = "Tank Boss Rules", page = "tank", tab = "bosses", path = "Tank > Boss Rules", keywords = "midnight encounter journal stacks taunt logic timeline aura cast overrides custom swap text hits icon" },

    { label = "Theme Presets", page = "appearance", tab = "theme", path = "Look & Feel > Theme", keywords = "shadowsteel starforge palette style" },
    { label = "Custom Accent Color", page = "appearance", tab = "theme", path = "Look & Feel > Theme", keywords = "class color custom theme" },
    { label = "Surface Colors", page = "appearance", tab = "surfaces", path = "Look & Feel > Surfaces", keywords = "panel header sidebar section row controls inputs border" },
    { label = "Surface Opacity", page = "appearance", tab = "surfaces", path = "Look & Feel > Surfaces", keywords = "panel header sidebar section row controls border transparent alpha" },
    { label = "Global Font", page = "appearance", tab = "text", path = "Look & Feel > Fonts", keywords = "fonts sharedmedia typeface text" },
    { label = "Text Colors", page = "appearance", tab = "text", path = "Look & Feel > Fonts", keywords = "title button general font color" },
    { label = "Top Tab Scale", page = "appearance", tab = "scaling", path = "Look & Feel > Scaling", keywords = "launcher top bar size" },
    { label = "Dropdown Panel Scale", page = "appearance", tab = "scaling", path = "Look & Feel > Scaling", keywords = "menu size" },
    { label = "Settings Window Scale", page = "appearance", tab = "scaling", path = "Look & Feel > Scaling", keywords = "settings window size" },
    { label = "Menu Alpha", page = "appearance", tab = "scaling", path = "Look & Feel > Scaling", keywords = "alpha transparency dropdown" },
    { label = "Profile Transfer", page = "appearance", tab = "profiles", path = "Look & Feel > Profiles", keywords = "export import profile string backup share" },

    { label = "Screenshot Quality", page = "screenshot", tab = "quality", path = "Screenshots > Quality", keywords = "shot capture jpg tga format graphics" },
    { label = "Hide UI During Screenshot", page = "screenshot", tab = "quality", path = "Screenshots > Quality", keywords = "capture clean interface" },
    { label = "Screenshot Render Scale", page = "screenshot", tab = "quality", path = "Screenshots > Quality", keywords = "resolution supersampling graphics" },
    { label = "Screenshot Delay", page = "screenshot", tab = "quality", path = "Screenshots > Quality", keywords = "timer wait capture" },
    { label = "Screenshot Resolution", page = "screenshot", tab = "resolution", path = "Screenshots > Resolution", keywords = "size 1080p 1440p ultrawide 4k 5k custom current" },
}

local function Normalize(value)
    value = tostring(value or ""):lower()
    value = value:gsub("[^%w]+", " ")
    return value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function StartsWithWord(haystack, needle)
    return haystack:sub(1, #needle) == needle or haystack:find(" " .. needle, 1, true) ~= nil
end

function Search:Normalize(value)
    return Normalize(value)
end

function Search:GetIndex()
    return INDEX
end

function Search:FilterOptions(list, order, query)
    list = list or {}
    local normalizedQuery = Normalize(query)
    if normalizedQuery == "" then
        return list, order
    end

    local tokens = {}
    for token in normalizedQuery:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end

    local filteredList = {}
    local filteredOrder = {}
    local seen = {}
    local function Include(key)
        if seen[key] or list[key] == nil then
            return
        end
        seen[key] = true
        local haystack = Normalize(tostring(list[key]) .. " " .. tostring(key))
        for _, token in ipairs(tokens) do
            if not haystack:find(token, 1, true) then
                return
            end
        end
        filteredList[key] = list[key]
        filteredOrder[#filteredOrder + 1] = key
    end

    for _, key in ipairs(order or {}) do
        Include(key)
    end

    local remaining = {}
    for key in pairs(list) do
        if not seen[key] then
            remaining[#remaining + 1] = key
        end
    end
    table.sort(remaining, function(left, right)
        return Normalize(list[left]) < Normalize(list[right])
    end)
    for _, key in ipairs(remaining) do
        Include(key)
    end

    return filteredList, filteredOrder
end

-- Entries can name a client feature they need (see RC:SupportsMythicPlus) so
-- WoW Forever does not surface settings for systems it does not have.
local ENTRY_REQUIREMENTS = {
    mythicPlus = function() return not RC.SupportsMythicPlus or RC:SupportsMythicPlus() end,
}

local function IsEntryAvailable(entry)
    local check = entry.requires and ENTRY_REQUIREMENTS[entry.requires]
    return not check or check() == true
end

function Search:Find(query, limit)
    local normalizedQuery = Normalize(query)
    if normalizedQuery == "" then
        return {}
    end

    local tokens = {}
    for token in normalizedQuery:gmatch("%S+") do
        tokens[#tokens + 1] = token
    end

    local ranked = {}
    for _, entry in ipairs(INDEX) do
        local label = Normalize(entry.label)
        local path = Normalize(entry.path)
        local keywords = Normalize(entry.keywords)
        -- Also match the label as the player sees it in their language.
        local localizedLabel = L and Normalize(L[entry.label]) or label
        local haystack = label .. " " .. path .. " " .. keywords .. " " .. localizedLabel
        local allTokensMatch = IsEntryAvailable(entry)
        local score = 0

        for _, token in ipairs(tokens) do
            if not haystack:find(token, 1, true) then
                allTokensMatch = false
                break
            end
            if StartsWithWord(label, token) then
                score = score + 90
            elseif label:find(token, 1, true) then
                score = score + 55
            elseif path:find(token, 1, true) then
                score = score + 28
            else
                score = score + 16
            end
        end

        if allTokensMatch then
            if label == normalizedQuery then
                score = score + 1000
            elseif label:sub(1, #normalizedQuery) == normalizedQuery then
                score = score + 700
            elseif label:find(normalizedQuery, 1, true) then
                score = score + 450
            elseif path:find(normalizedQuery, 1, true) then
                score = score + 180
            elseif keywords:find(normalizedQuery, 1, true) then
                score = score + 120
            end
            ranked[#ranked + 1] = { entry = entry, score = score }
        end
    end

    table.sort(ranked, function(left, right)
        if left.score == right.score then
            if #left.entry.label == #right.entry.label then
                return left.entry.label < right.entry.label
            end
            return #left.entry.label < #right.entry.label
        end
        return left.score > right.score
    end)

    local results = {}
    local resultLimit = math.max(1, tonumber(limit) or 30)
    for index = 1, math.min(#ranked, resultLimit) do
        results[index] = ranked[index].entry
    end
    return results
end
