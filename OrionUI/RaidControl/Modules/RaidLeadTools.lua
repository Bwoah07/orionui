local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
---@class RaidLeadTools : AceModule, AceComm-3.0
local RaidLeadTools = RC:NewModule("RaidLeadTools", "AceComm-3.0")

local COMM_PREFIX = "RCLEAD"
local HOSTILE_FLAG = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local GROUP_FLAGS = (COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001)
    + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002)
    + (COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004)
local BRES_SPELLS = {
    [20484] = L["Rebirth"],
    [20707] = L["Soulstone"],
    [61999] = L["Raise Ally"],
    [391054] = L["Intercession"],
}
local BRES_CHARGE_SPELL_ID = 20484
local BRES_FALLBACK_ICON = 136080
local HEALER_MANA_FALLBACK_ICON = 135915
local HEALER_MANA_DRINK_ICON = "Interface\\Icons\\INV_Drink_18"
-- Healer-mana state codes stay English (tests and alert rules compare them);
-- only the tag drawn on the row is translated.
local HEALER_MANA_STATE_LABELS = {
    OFF = L["OFF"],
    DEAD = L["DEAD"],
    OOR = L["OOR"],
    DRINKING = L["DRINKING"],
    LOW = L["LOW"],
}
-- Battle-res history status codes, translated only for display.
local BRES_STATUS_LABELS = {
    Cast = L["Cast"],
    Incoming = L["Incoming"],
    Resurrected = L["Resurrected"],
}
local HEALER_INSPECT_DELAY = 0.08
local HEALER_MANA_TOP_SAFE_MARGIN = 84
local HEALER_MANA_TOP_WIDGET_GAP = 12
-- Raid status HUDs are passive readouts: keep them in the same layer as unit
-- frames so Blizzard windows, bags, menus and RaidControl panels draw over them.
local RAID_STATUS_HUD_STRATA = "LOW"
local HEALER_MANA_TOP_WIDGETS = {
    "MicroMenuContainer",
    "MicroButtonAndBagsBar",
    "CharacterMicroButton",
    "ProfessionMicroButton",
    "SocialsMicroButton",
    "GuildMicroButton",
    "LFDMicroButton",
    "CollectionsMicroButton",
    "EJMicroButton",
    "StoreMicroButton",
    "MainMenuMicroButton",
    "HelpMicroButton",
    "MinimapCluster",
}
local PULL_CAPTURE_WINDOW_SECONDS = 8
local HEALER_MANA_ALERT_STATES = {
    LOW = true,
    DRINKING = true,
    DEAD = true,
    OOR = true,
    OFF = true,
}

local function IsSecret(value)
    if not issecretvalue then
        return false
    end
    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

local function NormalizeName(name)
    if IsSecret(name) or name == nil or name == "" then
        return nil
    end
    name = tostring(name):gsub("^%*+", ""):gsub("%*+$", "")
    if Ambiguate then
        local short = Ambiguate(name, "short")
        if short and short ~= "" then
            name = short
        end
    end
    if strsplit then
        local short = strsplit("-", name)
        if short and short ~= "" then
            return short:gsub("^%*+", ""):gsub("%*+$", "")
        end
    end
    local short = name:match("^([^%-]+)") or name
    return short:gsub("^%*+", ""):gsub("%*+$", "")
end

local function Now()
    return time and time() or 0
end

local function PreciseNow()
    return GetTime and GetTime() or Now()
end

local function IsOrdinaryNumber(value)
    return not IsSecret(value) and type(value) == "number"
end

local function CleanDisplayText(text)
    if IsSecret(text) or text == nil then
        return nil
    end
    text = tostring(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text ~= "" and text or nil
end

local function SafeNumber(value)
    if IsSecret(value) or value == nil then
        return nil
    end
    local ok, number = pcall(tonumber, value)
    if not ok or IsSecret(number) or type(number) ~= "number" then
        return nil
    end
    return number
end

local function SafeFrameNumber(frame, methodName)
    local method = frame and frame[methodName]
    if type(method) ~= "function" then
        return nil
    end
    local ok, value = pcall(method, frame)
    return ok and SafeNumber(value) or nil
end

local function SafeFrameShown(frame)
    if not frame or type(frame.IsShown) ~= "function" then
        return false
    end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and not IsSecret(shown) and shown == true
end

local function PowerNumber(value)
    return SafeNumber(value)
end

local function SafeUnitPowerPercent(unit)
    if type(UnitPowerPercent) ~= "function" or not (CurveConstants and CurveConstants.ScaleTo100) then
        return nil
    end
    local manaType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
    local ok, value = pcall(UnitPowerPercent, unit, manaType, true, CurveConstants.ScaleTo100)
    if not ok then
        return nil
    end
    if IsSecret(value) then
        return nil, "mana-scaled-protected", nil, true, value
    end
    local percent = IsOrdinaryNumber(value) and math.max(0, math.min(100, value)) or nil
    if percent == nil then
        return nil
    end
    return percent, "mana-scaled", string.format("%d%%", math.floor(percent + 0.5))
end

local function PercentFromPower(current, maximum, minimum)
    current = PowerNumber(current)
    maximum = PowerNumber(maximum)
    minimum = PowerNumber(minimum) or 0
    if current == nil or not maximum or maximum <= minimum then
        return nil
    end
    local percent = math.floor(((current - minimum) / (maximum - minimum)) * 100 + 0.5)
    return math.max(0, math.min(100, percent))
end

local function HasFlag(flags, flag)
    return bit and bit.band and bit.band(flags or 0, flag or 0) ~= 0
end

local function SetSafeFont(fontString, size, flags)
    RC:SetFont(fontString, size, flags)
    if not fontString:GetFont() and GameFontNormal then
        local fallbackPath = GameFontNormal:GetFont()
        if fallbackPath then
            fontString:SetFont(fallbackPath, size, flags)
        else
            fontString:SetFontObject(GameFontNormal)
        end
    end
end

local function GetCommChannel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    elseif IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function IsGroupLeaderOrAssist()
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function GetChargesForSpell(spellID)
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and not IsSecret(info) and type(info) == "table" then
            local okFields, currentCharges, maxCharges, cooldownStartTime, cooldownDuration = pcall(function()
                return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration
            end)
            if okFields then
                return SafeNumber(currentCharges), SafeNumber(maxCharges), SafeNumber(cooldownStartTime), SafeNumber(cooldownDuration)
            end
        end
    end
    if GetSpellCharges then
        local ok, current, maxCharges, startTime, duration = pcall(GetSpellCharges, spellID)
        if ok then
            return SafeNumber(current), SafeNumber(maxCharges), SafeNumber(startTime), SafeNumber(duration)
        end
    end
    return nil
end

local function GetDefaultBattleResIcon()
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, texture = pcall(C_Spell.GetSpellTexture, 20484)
        if ok and not IsSecret(texture) and texture then
            return texture
        end
    end
    if GetSpellTexture then
        local ok, texture = pcall(GetSpellTexture, 20484)
        if ok and not IsSecret(texture) and texture then
            return texture
        end
    end
    return BRES_FALLBACK_ICON
end

local function GetBattleResInstanceContext()
    if type(GetInstanceInfo) ~= "function" then
        return false, nil
    end
    local ok, instanceName, instanceType, difficultyID, _, _, _, _, instanceID = pcall(GetInstanceInfo)
    if not ok or IsSecret(instanceType) or (instanceType ~= "party" and instanceType ~= "raid") then
        return false, nil
    end
    if IsSecret(instanceName) then
        instanceName = nil
    end
    local key = table.concat({
        tostring(SafeNumber(instanceID) or instanceName or "instance"),
        instanceType,
        tostring(SafeNumber(difficultyID) or 0),
    }, ":")
    return true, key
end

local function SafeUnitExists(unit)
    if type(UnitExists) ~= "function" then
        return unit == "player"
    end
    local ok, exists = pcall(UnitExists, unit)
    return ok and not IsSecret(exists) and exists == true
end

local function SafeBooleanCall(callback, ...)
    if type(callback) ~= "function" then
        return false
    end
    local ok, value = pcall(callback, ...)
    return ok and not IsSecret(value) and value == true
end

local function IsActiveMythicPlus()
    if not (C_ChallengeMode and type(C_ChallengeMode.IsChallengeModeActive) == "function") then
        return false
    end
    local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
    if not ok or IsSecret(active) or active ~= true then
        return false
    end
    if type(C_ChallengeMode.GetActiveKeystoneInfo) ~= "function" then
        return true
    end
    local okLevel, level = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
    level = okLevel and SafeNumber(level) or nil
    return level == nil or level > 0
end

local function GetInstanceType()
    if type(GetInstanceInfo) ~= "function" then
        return nil
    end
    local ok, _, instanceType = pcall(GetInstanceInfo)
    if not ok or IsSecret(instanceType) then
        return nil
    end
    return instanceType
end

local function IsSavedPositionOffscreen(position)
    if type(position) ~= "table" then
        return false
    end
    local point = position[1]
    local relativePoint = position[3]
    local x = SafeNumber(position[4])
    local y = SafeNumber(position[5])
    if point ~= relativePoint then
        return false
    end
    return (point == "TOPLEFT" and ((x and x < 0) or (y and y > 0)))
        or (point == "TOPRIGHT" and ((x and x > 0) or (y and y > 0)))
        or (point == "BOTTOMLEFT" and ((x and x < 0) or (y and y < 0)))
        or (point == "BOTTOMRIGHT" and ((x and x > 0) or (y and y < 0)))
        or false
end

local function ReadUnitIdentity(unit)
    if not unit then
        return nil, nil
    end
    local name
    if type(GetUnitName) == "function" then
        local ok, value = pcall(GetUnitName, unit, true)
        if ok and not IsSecret(value) then
            name = NormalizeName(value)
        end
    end
    if not name and type(UnitName) == "function" then
        local ok, value = pcall(UnitName, unit)
        if ok and not IsSecret(value) then
            name = NormalizeName(value)
        end
    end
    local guid
    if type(UnitGUID) == "function" then
        local ok, value = pcall(UnitGUID, unit)
        if ok and not IsSecret(value) then
            guid = value
        end
    end
    return name, guid
end

local function GetUnitRangeState(unit)
    if UnitInRange then
        local ok, inRange, checked = pcall(UnitInRange, unit)
        if ok and not IsSecret(checked) and not IsSecret(inRange) and checked and inRange == false then
            return "OOR"
        end
    end
    if UnitIsVisible then
        local ok, visible = pcall(UnitIsVisible, unit)
        if ok and not IsSecret(visible) and visible == false then
            return "OOR"
        end
    end
    if UnitIsConnected then
        local ok, connected = pcall(UnitIsConnected, unit)
        if ok and not IsSecret(connected) and connected == false then
            return "OFF"
        end
    end
    return nil
end

local function IsPlayerUnit(unit)
    if not unit then
        return false
    end
    if UnitGUID then
        local okGuid, guid = pcall(UnitGUID, unit)
        if okGuid and not IsSecret(guid) and guid and tostring(guid):match("^Player") then
            return true
        end
    end
    if UnitIsPlayer then
        local ok, isPlayer = pcall(UnitIsPlayer, unit)
        if ok and not IsSecret(isPlayer) and isPlayer == true then
            return true
        end
    end
    return false
end

local function GetManaDetails(unit)
    local manaType = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

    local function ReadPowerPair(powerIndex)
        local calls = {}
        if powerIndex ~= nil then
            calls[#calls + 1] = { unit, powerIndex }
            calls[#calls + 1] = { unit, powerIndex, true }
            calls[#calls + 1] = { unit, powerIndex, false }
        else
            calls[#calls + 1] = { unit }
        end
        for _, args in ipairs(calls) do
            local okPower, power = pcall(UnitPower, unpack(args))
            local okMax, maximum = pcall(UnitPowerMax, unpack(args))
            power = okPower and PowerNumber(power) or nil
            maximum = okMax and PowerNumber(maximum) or nil
            if power ~= nil and maximum and maximum > 0 then
                return power, maximum
            end
        end
        return nil, nil
    end

    local power, maximum = ReadPowerPair(manaType)
    if maximum and maximum > 0 and power ~= nil then
        return power, maximum, "mana"
    end

    local currentType
    local okType, powerType = pcall(UnitPowerType, unit)
    if okType then
        currentType = SafeNumber(powerType)
    end

    local powerTypes = { currentType, 0 }
    for _, powerIndex in ipairs(powerTypes) do
        if powerIndex ~= nil then
            power, maximum = ReadPowerPair(powerIndex)
            if maximum and maximum > 0 and power ~= nil then
                return power, maximum, "power" .. tostring(powerIndex)
            end
        end
    end

    power, maximum = ReadPowerPair(nil)
    if maximum and maximum > 0 and power ~= nil then
        return power, maximum, "default"
    end

    if UnitMana and UnitManaMax then
        local okPower, manaPower = pcall(UnitMana, unit)
        local okMax, manaMax = pcall(UnitManaMax, unit)
        manaPower = okPower and PowerNumber(manaPower) or nil
        manaMax = okMax and PowerNumber(manaMax) or nil
        if manaPower ~= nil and manaMax and manaMax > 0 then
            return manaPower, manaMax, "mana-alias"
        end
    end

    return nil, nil, "none"
end

local function ReadManaPercentLikeElvUI(unit)
    local directPercent, directSource, directText, directProtected, protectedValue = SafeUnitPowerPercent(unit)
    if directProtected then
        return nil, directSource, nil, true, protectedValue
    end
    if directPercent ~= nil then
        return math.floor(directPercent + 0.5), directSource, directText
    elseif directText then
        return nil, directSource, directText
    end
    local power, maximum, source = GetManaDetails(unit)
    local percent = PercentFromPower(power, maximum, 0)
    if percent ~= nil then
        return percent, source, string.format("%d%%", percent)
    end
    return nil
end

local function UnitMatchesFrame(frame, unit)
    if not frame or not unit then
        return false
    end
    local frameUnit
    if frame.GetAttribute then
        local ok, value = pcall(frame.GetAttribute, frame, "unit")
        if ok then
            frameUnit = value
        end
    end
    if IsSecret(frameUnit) then
        return false
    end
    if frameUnit == nil then
        frameUnit = frame.unit
    end
    if IsSecret(frameUnit) then
        return false
    end
    if frameUnit == nil then
        frameUnit = frame.displayedUnit
    end
    if IsSecret(frameUnit) or frameUnit == nil then
        return false
    end
    if frameUnit == unit then
        return true
    end
    return false
end

local function AddNameKey(keys, name)
    name = CleanDisplayText(name)
    if not name then
        return
    end
    local normalized = NormalizeName(name) or name
    keys[string.lower(name)] = true
    keys[string.lower(normalized)] = true
    local firstWord = normalized:match("^(%S+)")
    if firstWord and #firstWord >= 4 then
        keys[string.lower(firstWord)] = true
    end
end

local function GetUnitNameKeys(unit)
    local keys = {}
    local okFull, fullName = pcall(GetUnitName, unit, true)
    if okFull and not IsSecret(fullName) and fullName then
        AddNameKey(keys, fullName)
    end
    local okShort, shortName = pcall(GetUnitName, unit, false)
    if okShort and not IsSecret(shortName) and shortName then
        AddNameKey(keys, shortName)
    end
    if UnitName then
        local okName, name, realm = pcall(UnitName, unit)
        if okName and not IsSecret(name) and name then
            AddNameKey(keys, name)
            if not IsSecret(realm) and realm and realm ~= "" then
                AddNameKey(keys, name .. "-" .. realm)
            end
        end
    end
    return next(keys) and keys or nil
end

local function GetUnitPowerAliases(unit)
    local aliases = {}
    local seen = {}

    local function AddAlias(value)
        value = CleanDisplayText(value)
        if not value then
            return
        end
        local normalized = NormalizeName(value) or value
        for _, alias in ipairs({ value, normalized }) do
            if alias and alias ~= "" and not seen[alias] then
                seen[alias] = true
                aliases[#aliases + 1] = alias
            end
        end
    end

    local okFull, fullName = pcall(GetUnitName, unit, true)
    if okFull then
        AddAlias(fullName)
    end
    local okShort, shortName = pcall(GetUnitName, unit, false)
    if okShort then
        AddAlias(shortName)
    end
    if UnitName then
        local okName, name, realm = pcall(UnitName, unit)
        if okName then
            AddAlias(name)
            if not IsSecret(name) and not IsSecret(realm) and name and realm and realm ~= "" then
                AddAlias(name .. "-" .. realm)
            end
        end
    end

    return aliases
end

local function ReadFontStringText(fontString)
    if IsSecret(fontString) or not fontString then
        return nil
    end
    if type(fontString) == "string" then
        return CleanDisplayText(fontString)
    end
    if fontString.GetText then
        local ok, text = pcall(fontString.GetText, fontString)
        if ok then
            return CleanDisplayText(text)
        end
    end
    return nil
end

local function TextMatchesNameKeys(text, nameKeys)
    text = CleanDisplayText(text)
    if not text or not nameKeys then
        return false
    end
    local normalized = NormalizeName(text) or text
    local lowerText = string.lower(text)
    local lowerNormalized = string.lower(normalized)
    if nameKeys[lowerText] or nameKeys[lowerNormalized] then
        return true
    end
    if #lowerNormalized >= 4 then
        for key in pairs(nameKeys) do
            if #key >= 4 and (key:find(lowerNormalized, 1, true) or lowerNormalized:find(key, 1, true)) then
                return true
            end
        end
    end
    return false
end

local function FrameNameMatches(frame, nameKeys)
    if not frame or not nameKeys then
        return false
    end
    local candidates = {
        frame.Name,
        frame.name,
        frame.NameText,
        frame.nameText,
        frame.Text,
        frame.text,
    }
    for _, candidate in ipairs(candidates) do
        local text = ReadFontStringText(candidate)
        if TextMatchesNameKeys(text, nameKeys) then
            return true
        end
    end
    return false
end

local function ParsePercentText(text)
    text = CleanDisplayText(text)
    if not text then
        return nil
    end
    local percent = text:match("(%d+)%s*%%")
    if percent then
        return math.max(0, math.min(100, tonumber(percent)))
    end
    local current, currentSuffix, maximum, maximumSuffix = text:match("([%d%.]+)%s*([kKmMbB]?)%s*/%s*([%d%.]+)%s*([kKmMbB]?)")
    current = tonumber(current)
    maximum = tonumber(maximum)
    if current and maximum and maximum > 0 then
        local function ApplySuffix(value, suffix)
            suffix = suffix and suffix:lower() or ""
            if suffix == "k" then
                return value * 1000
            elseif suffix == "m" then
                return value * 1000000
            elseif suffix == "b" then
                return value * 1000000000
            end
            return value
        end
        current = ApplySuffix(current, currentSuffix)
        maximum = ApplySuffix(maximum, maximumSuffix)
        return math.max(0, math.min(100, math.floor((current / maximum) * 100 + 0.5)))
    end
    return nil
end

local function ReadPowerBarGeometry(bar)
    if not bar or not bar.GetStatusBarTexture or not bar.GetWidth then
        return nil
    end
    local okTexture, texture = pcall(bar.GetStatusBarTexture, bar)
    if not okTexture or not texture then
        return nil
    end

    local okBarWidth, barWidth = pcall(bar.GetWidth, bar)
    local fillWidth
    if texture.GetWidth then
        local okFillWidth, value = pcall(texture.GetWidth, texture)
        if okFillWidth then
            fillWidth = value
        end
    end
    local percent = PercentFromPower(fillWidth, barWidth, 0)
    if percent then
        return percent
    end

    if bar.GetHeight and texture.GetHeight then
        local okBarHeight, barHeight = pcall(bar.GetHeight, bar)
        local okFillHeight, fillHeight = pcall(texture.GetHeight, texture)
        if okBarHeight and okFillHeight then
            return PercentFromPower(fillHeight, barHeight, 0)
        end
    end
    return nil
end

local function ReadPowerBar(bar)
    if not bar then
        return nil
    end
    local cur = PowerNumber(bar.cur)
        or PowerNumber(bar.current)
        or PowerNumber(bar.CurrentValue)
    local max = PowerNumber(bar.max)
        or PowerNumber(bar.maximum)
        or PowerNumber(bar.MaxValue)
    local directPercent = PercentFromPower(cur, max, 0)
    if directPercent then
        return directPercent
    end
    local textCandidates = {
        bar.value,
        bar.Value,
        bar.Text,
        bar.text,
        bar.PercentText,
        bar.percentText,
        bar.ValueText,
        bar.valueText,
    }
    for _, textObject in ipairs(textCandidates) do
        local percent = ParsePercentText(ReadFontStringText(textObject))
        if percent then
            return percent
        end
    end
    local geometryPercent = ReadPowerBarGeometry(bar)
    if geometryPercent then
        return geometryPercent
    end
    if not bar.GetMinMaxValues or not bar.GetValue then
        return nil
    end
    local okMinMax, minValue, maxValue = pcall(bar.GetMinMaxValues, bar)
    local okValue, value = pcall(bar.GetValue, bar)
    if not okMinMax or not okValue then
        return nil
    end
    return PercentFromPower(value, maxValue, minValue)
end

local powerBarFieldNames = {
    "Power",
    "power",
    "PowerBar",
    "powerBar",
    "powerbar",
    "Mana",
    "mana",
    "ManaBar",
    "manaBar",
    "manabar",
    "AdditionalPower",
    "additionalPower",
    "AlternativePower",
    "alternativePower",
    "AltPower",
    "altPower",
}

local function ReadFramePowerPercent(frame, depth, seen, allowSelfBar)
    if not frame then
        return nil
    end

    local percent
    if allowSelfBar then
        percent = ReadPowerBar(frame)
        if percent then
            return percent
        end
    end

    for _, fieldName in ipairs(powerBarFieldNames) do
        local value = frame[fieldName]
        if type(value) == "table" then
            percent = ReadPowerBar(value)
            if percent then
                return percent
            end
        end
    end

    return nil
end

local function ReadSmallestVisibleStatusBar(frame)
    if not frame or not frame.GetChildren then
        return nil
    end

    local children = { frame:GetChildren() }
    local smallest
    local smallestHeight
    for _, child in ipairs(children) do
        local isStatusBar = child and child.GetMinMaxValues and child.GetValue
        if child and child.IsObjectType then
            local okType, result = pcall(child.IsObjectType, child, "StatusBar")
            isStatusBar = okType and result or false
        end
        if isStatusBar then
            local shown = true
            if child.IsShown then
                local okShown, result = pcall(child.IsShown, child)
                shown = okShown and result or false
            end
            local okHeight, height
            if child.GetHeight then
                okHeight, height = pcall(child.GetHeight, child)
            end
            height = okHeight and SafeNumber(height) or nil
            if shown and height and height > 0 and (not smallestHeight or height < smallestHeight) then
                smallest = child
                smallestHeight = height
            end
        end
    end

    return smallest and ReadPowerBar(smallest) or nil
end

local function AddFrameCandidate(candidates, frame)
    if frame then
        candidates[#candidates + 1] = frame
    end
end

local function AddHeaderButtons(candidates, header, count)
    if not header then
        return
    end
    for index = 1, count do
        AddFrameCandidate(candidates, header[index])
    end
end

local function SetProtectedPercentText(fontString, protectedValue)
    if not fontString or type(fontString.SetFormattedText) ~= "function" then
        return false
    end
    -- Midnight permits protected values to be displayed by a FontString as
    -- long as addon Lua does not inspect or perform arithmetic on the value.
    return pcall(fontString.SetFormattedText, fontString, "%d%%", protectedValue)
end

local function GetManaPercentFromVisibleFrames(unit, force)
    if not force and not (RC.db and RC.db.profile and RC.db.profile.healerManaUseFrameFallback == true) then
        return nil
    end
    local nameKeys = GetUnitNameKeys(unit)
    local candidates = {}
    AddHeaderButtons(candidates, _G.ERFPartyHeader, 5)
    AddHeaderButtons(candidates, _G.ERFFlatHeader, 40)
    for group = 1, 8 do
        AddHeaderButtons(candidates, _G["ERFGroupHeader" .. group], 5)
    end
    for i = 1, 5 do
        AddFrameCandidate(candidates, _G["CompactPartyFrameMember" .. i])
    end
    for i = 1, 40 do
        AddFrameCandidate(candidates, _G["CompactRaidFrame" .. i])
    end
    for group = 1, 8 do
        for member = 1, 5 do
            AddFrameCandidate(candidates, _G["CompactRaidGroup" .. group .. "Member" .. member])
            AddFrameCandidate(candidates, _G["ElvUF_RaidGroup" .. group .. "UnitButton" .. member])
            AddFrameCandidate(candidates, _G["ElvUF_Raid40Group" .. group .. "UnitButton" .. member])
            AddFrameCandidate(candidates, _G["ElvUF_PartyGroup" .. group .. "UnitButton" .. member])
        end
    end
    AddFrameCandidate(candidates, _G.ElvUF_Player)
    AddFrameCandidate(candidates, _G.ElvUF_Target)
    AddFrameCandidate(candidates, _G.ElvUF_Focus)

    for _, frame in ipairs(candidates) do
        if UnitMatchesFrame(frame, unit) or FrameNameMatches(frame, nameKeys) then
            local percent = ReadFramePowerPercent(frame, 0, nil, false)
                or ReadSmallestVisibleStatusBar(frame)
            if percent then
                return percent, "unit-frame"
            end
        end
    end

    local elvObjects = (_G.ElvUF and _G.ElvUF.objects) or (_G.ElvUI and _G.ElvUI[1] and _G.ElvUI[1].oUF and _G.ElvUI[1].oUF.objects)
    if elvObjects then
        for _, frame in pairs(elvObjects) do
            if UnitMatchesFrame(frame, unit) or FrameNameMatches(frame, nameKeys) then
                local percent = ReadFramePowerPercent(frame, 0, nil, false)
                if percent then
                    return percent, "elvui"
                end
            end
        end
    end

    return nil
end

local function GetManaPercentFromAliases(unit)
    for _, alias in ipairs(GetUnitPowerAliases(unit)) do
        local percent, source, percentText, protected, protectedValue = ReadManaPercentLikeElvUI(alias)
        if protected then
            return nil, "name:" .. tostring(source), nil, true, protectedValue
        end
        if percent ~= nil or percentText then
            return percent, "name:" .. tostring(source), percentText
        end
    end
    return nil
end

local function FindMatchingUnitToken(unit)
    if type(unit) == "string" and UnitExists(unit) and (unit == "player" or unit:match("^party%d+$") or unit:match("^raid%d+$")) then
        return unit
    end
    local okGuid, guid = pcall(UnitGUID, unit)
    if not okGuid or IsSecret(guid) or not guid then
        return unit
    end
    local tokens = { "player", "target", "focus", "mouseover" }
    for i = 1, 4 do
        tokens[#tokens + 1] = "party" .. i
    end
    for i = 1, 40 do
        tokens[#tokens + 1] = "raid" .. i
    end
    for _, token in ipairs(tokens) do
        if UnitExists(token) then
            local okOtherGuid, otherGuid = pcall(UnitGUID, token)
            if okOtherGuid and not IsSecret(otherGuid) and otherGuid and otherGuid == guid then
                return token
            end
        end
    end
    return unit
end

local function GetManaCacheKey(unit)
    local okGuid, guid = pcall(UnitGUID, unit)
    if okGuid and not IsSecret(guid) and guid then
        return guid
    end
    local okName, name = pcall(GetUnitName, unit, true)
    if okName and not IsSecret(name) and name then
        return name
    end
    return unit
end

local function CacheManaPercent(owner, unit, percent, protectedGeometry)
    if not owner or percent == nil or percent < 0 then
        return
    end
    owner.healerManaCache = owner.healerManaCache or {}
    owner.healerManaCache[GetManaCacheKey(unit)] = {
        percent = percent,
        time = PreciseNow(),
        protectedGeometry = protectedGeometry == true,
    }
end

local function GetCachedManaPercent(owner, unit, protectedGeometryOnly)
    if not owner or not owner.healerManaCache then
        return nil
    end
    local cached = owner.healerManaCache[GetManaCacheKey(unit)]
    if cached and cached.time and (PreciseNow() - cached.time) <= 12
        and (not protectedGeometryOnly or cached.protectedGeometry == true) then
        return cached.percent, "cache"
    end
    return nil
end

local function ResolveProtectedMana(owner, unit, readableUnit, source, protectedValue)
    -- Midnight raid-unit mana may be a protected value. Pass it only to
    -- Blizzard-owned display sinks; never infer it from another frame's fill
    -- geometry or branch on it in addon Lua.
    return nil, source, nil, protectedValue, true
end

local function GetCommManaForName(owner, name)
    if not owner or not owner.healerManaComm or not name then
        return nil
    end
    local key = NormalizeName(name) or name
    local direct = owner.healerManaComm[key]
    if direct and direct.updated and (Now() - direct.updated) <= 8 then
        return direct.percent, "comm", direct.drinking
    end
    for storedName, info in pairs(owner.healerManaComm) do
        if NormalizeName(storedName) == key and info.updated and (Now() - info.updated) <= 8 then
            return info.percent, "comm", info.drinking
        end
    end
    return nil
end

local function GetManaPercent(owner, unit)
    local readableUnit = FindMatchingUnitToken(unit)
    local apiPercent, apiSource, apiText, apiProtected, apiProtectedValue = ReadManaPercentLikeElvUI(readableUnit)
    if apiProtected then
        return ResolveProtectedMana(owner, unit, readableUnit, apiSource, apiProtectedValue)
    end
    if apiPercent ~= nil or apiText then
        CacheManaPercent(owner, unit, apiPercent)
        return apiPercent, apiSource, apiText
    end
    local aliasPercent, aliasSource, aliasText, aliasProtected, aliasProtectedValue = GetManaPercentFromAliases(readableUnit)
    if aliasProtected then
        return ResolveProtectedMana(owner, unit, readableUnit, aliasSource, aliasProtectedValue)
    end
    if aliasPercent ~= nil or aliasText then
        CacheManaPercent(owner, unit, aliasPercent)
        return aliasPercent, aliasSource, aliasText
    end

    local power, maximum, source = GetManaDetails(readableUnit)
    if not maximum or maximum <= 0 or power == nil then
        local retryAliasPercent, retryAliasSource, retryAliasText, retryAliasProtected, retryProtectedValue = GetManaPercentFromAliases(readableUnit)
        if retryAliasProtected then
            return ResolveProtectedMana(owner, unit, readableUnit, retryAliasSource, retryProtectedValue)
        end
        if retryAliasPercent ~= nil or retryAliasText then
            CacheManaPercent(owner, unit, retryAliasPercent)
            return retryAliasPercent, retryAliasSource, retryAliasText
        end
        local framePercent, frameSource = GetManaPercentFromVisibleFrames(unit)
        if not framePercent and readableUnit ~= unit then
            framePercent, frameSource = GetManaPercentFromVisibleFrames(readableUnit)
        end
        if framePercent then
            CacheManaPercent(owner, unit, framePercent)
            return framePercent, frameSource, string.format("%d%%", framePercent)
        end
        local cachedPercent, cachedSource = GetCachedManaPercent(owner, unit)
        if cachedPercent then
            return cachedPercent, cachedSource, string.format("%d%%", cachedPercent)
        end
        local rangeState = GetUnitRangeState(unit)
        if rangeState then
            return nil, rangeState
        end
        return nil, "pending"
    end

    local percent = PercentFromPower(power, maximum, 0)
    if percent == nil then
        local framePercent, frameSource = GetManaPercentFromVisibleFrames(unit)
        if not framePercent and readableUnit ~= unit then
            framePercent, frameSource = GetManaPercentFromVisibleFrames(readableUnit)
        end
        if framePercent then
            CacheManaPercent(owner, unit, framePercent)
            return framePercent, frameSource, string.format("%d%%", framePercent)
        end
        local cachedPercent, cachedSource = GetCachedManaPercent(owner, unit)
        if cachedPercent then
            return cachedPercent, cachedSource, string.format("%d%%", cachedPercent)
        end
        local rangeState = GetUnitRangeState(unit)
        if rangeState then
            return nil, rangeState
        end
        return nil, "pending"
    end
    if percent <= 0 and power <= 0 then
        if source == "mana" or source == "power0" then
            return 0, source
        end
        local framePercent, frameSource = GetManaPercentFromVisibleFrames(unit)
        if not framePercent and readableUnit ~= unit then
            framePercent, frameSource = GetManaPercentFromVisibleFrames(readableUnit)
        end
        if framePercent and framePercent > 0 then
            CacheManaPercent(owner, unit, framePercent)
            return framePercent, frameSource, string.format("%d%%", framePercent)
        end
        local cachedPercent, cachedSource = GetCachedManaPercent(owner, unit)
        if cachedPercent then
            return cachedPercent, cachedSource, string.format("%d%%", cachedPercent)
        end
        local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
        if okDead and not IsSecret(dead) and not dead then
            local rangeState = GetUnitRangeState(unit)
            if rangeState then
                return nil, rangeState
            end
            return nil, "pending"
        end
    end

    CacheManaPercent(owner, unit, percent)
    return percent, source, string.format("%d%%", percent)
end

local function GetGroupUnits()
    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, math.min(GetNumGroupMembers() or 0, 40) do
            units[#units + 1] = "raid" .. i
        end
    else
        units[#units + 1] = "player"
        if IsInGroup and IsInGroup() then
            for i = 1, math.min(GetNumSubgroupMembers and GetNumSubgroupMembers() or 0, 4) do
                units[#units + 1] = "party" .. i
            end
        end
    end
    return units
end

local function IsPlayerInHealerSpec()
    if not (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecializationInfo) then
        return false
    end
    local ok, specIndex = pcall(C_SpecializationInfo.GetSpecialization)
    if not ok or IsSecret(specIndex) or not specIndex then
        return false
    end
    local okRole, _, _, _, _, role = pcall(C_SpecializationInfo.GetSpecializationInfo, specIndex)
    return okRole and not IsSecret(role) and role == "HEALER"
end

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function IsTrackedHealerUnit(unit)
    if not unit or not UnitExists(unit) then
        return false
    end
    if UnitGroupRolesAssigned then
        local okRole, role = pcall(UnitGroupRolesAssigned, unit)
        if okRole and not IsSecret(role) and role == "HEALER" then
            return true
        end
    end
    if UnitIsUnit then
        local okPlayer, isPlayer = pcall(UnitIsUnit, unit, "player")
        if okPlayer and not IsSecret(isPlayer) and isPlayer then
            return IsPlayerInHealerSpec()
        end
    end
    return unit == "player" and IsPlayerInHealerSpec()
end

local function ShouldShowHealerMana(db)
    if not db or db.showHealerManaFrame == false then
        return false
    end
    local grouped = SafeBooleanCall(IsInGroup)
    local mode = tostring(db.healerManaVisibility or "group"):lower()
    if mode ~= "instances" and mode ~= "mplus" and mode ~= "raid" then
        mode = "group"
    end
    if not grouped then
        return mode == "group" and db.healerManaShowSolo == true
    end
    if db.healerManaOnlyIfPlayerIsHealer == true and not IsPlayerInHealerSpec() then
        return false
    end
    if mode == "mplus" then
        return IsActiveMythicPlus()
    elseif mode == "raid" then
        return GetInstanceType() == "raid"
    elseif mode == "instances" then
        return GetInstanceType() == "raid" or IsActiveMythicPlus()
    end
    return true
end

function RaidLeadTools:ShouldShowHealerMana()
    return ShouldShowHealerMana(self.db)
end

local function GetTrackedHealerUnits(db)
    local units = {}
    local maxHealers = math.max(1, math.min(8, tonumber(db and db.healerManaMaxHealers) or 6))
    if IsInRaid and IsInRaid() then
        for i = 1, math.min(GetNumGroupMembers() or 0, 40) do
            if #units >= maxHealers then
                break
            end
            local unit = "raid" .. i
            if IsTrackedHealerUnit(unit) then
                units[#units + 1] = unit
            end
        end
    elseif IsInGroup and IsInGroup() then
        for _, unit in ipairs(GetGroupUnits()) do
            if #units >= maxHealers then
                break
            end
            if IsTrackedHealerUnit(unit) then
                units[#units + 1] = unit
            end
        end
    elseif db and db.healerManaShowSolo == true then
        if IsTrackedHealerUnit("player") then
            units[#units + 1] = "player"
        end
    end
    return units
end

function RaidLeadTools:GetTrackedHealerUnits()
    return GetTrackedHealerUnits(self.db)
end

local function GetDBColor(color, fallbackR, fallbackG, fallbackB, fallbackA)
    if type(color) ~= "table" then
        return fallbackR, fallbackG, fallbackB, fallbackA
    end
    return color.r or color[1] or fallbackR,
        color.g or color[2] or fallbackG,
        color.b or color[3] or fallbackB,
        color.a or color[4] or fallbackA
end

local function ClampNumber(value, minimum, maximum, fallback)
    value = SafeNumber(value) or fallback
    return math.max(minimum, math.min(maximum, value))
end

function RaidLeadTools:NormalizeHealerManaStyle(style)
    style = tostring(style or "detailed"):lower()
    if style ~= "compact" and style ~= "minimal" then
        return "detailed"
    end
    return style
end

function RaidLeadTools:NormalizeBattleResStyle(style)
    style = tostring(style or "compact"):lower()
    if style ~= "stacked" and style ~= "badge" then
        return "compact"
    end
    return style
end

function RaidLeadTools:ResolveHealerManaVisual(healer)
    healer = type(healer) == "table" and healer or {}
    local db = self.db or {}
    local manaR, manaG, manaB, manaA = GetDBColor(db.healerManaManaColor, 0.28, 0.64, 1.00, 1)
    local lowR, lowG, lowB, lowA = GetDBColor(db.healerManaLowColor, 1.00, 0.30, 0.24, 1)
    local drinkR, drinkG, drinkB, drinkA = GetDBColor(db.healerManaDrinkingColor, 0.20, 0.90, 0.64, 1)
    local percent = SafeNumber(healer.percent)
    local lowThreshold = ClampNumber(db.healerManaLowThreshold, 1, 99, 30)
    local result = {
        statusText = healer.percentText
            or (percent and string.format("%d%%", math.floor(percent + 0.5)))
            or "--",
        stateText = "",
        value = percent or 0,
        r = manaR,
        g = manaG,
        b = manaB,
        a = manaA,
        iconAlpha = 1,
    }

    if healer.connected == false then
        result.statusText = "--"
        result.stateText = "OFF"
        result.r, result.g, result.b, result.a = 0.52, 0.55, 0.60, 1
        result.iconAlpha = 0.38
    elseif healer.dead then
        result.statusText = healer.percentText or (percent and string.format("%d%%", math.floor(percent + 0.5))) or "0%"
        result.stateText = "DEAD"
        result.r, result.g, result.b, result.a = 0.92, 0.22, 0.20, 1
        result.iconAlpha = 0.48
    elseif healer.manaState == "OOR" then
        result.stateText = "OOR"
        result.r, result.g, result.b, result.a = 0.68, 0.72, 0.78, 1
        result.iconAlpha = 0.72
    elseif healer.drinking and db.healerManaShowDrinking ~= false then
        result.stateText = "DRINKING"
        result.r, result.g, result.b, result.a = drinkR, drinkG, drinkB, drinkA
    elseif percent and percent <= lowThreshold then
        result.stateText = "LOW"
        result.r, result.g, result.b, result.a = lowR, lowG, lowB, lowA
    elseif not percent then
        result.statusText = healer.percentText or "--"
        result.stateText = healer.manaState == "OOR" and "OOR"
            or healer.manaState == "OFF" and "OFF"
            or ""
        result.r, result.g, result.b, result.a = 0.78, 0.82, 0.88, 1
    end

    result.isLowMana = healer.connected ~= false and percent ~= nil and percent <= lowThreshold
    if result.isLowMana then
        result.statusR, result.statusG, result.statusB, result.statusA = lowR, lowG, lowB, lowA
    else
        result.statusR, result.statusG, result.statusB, result.statusA = result.r, result.g, result.b, result.a
    end
    result.value = math.max(0, math.min(100, result.value))
    return result
end

function RaidLeadTools:IsSavedBattleResPositionOffscreen(position)
    return IsSavedPositionOffscreen(position)
end

function RaidLeadTools:PlayHealerManaStatusSound()
    local mode = self.db and self.db.healerManaStatusSound or "none"
    if mode == "none" then
        return false
    end
    local sharedPath = RC.ResolveSharedMediaSound and RC:ResolveSharedMediaSound(mode)
    if sharedPath and PlaySoundFile then
        local ok, result = pcall(PlaySoundFile, sharedPath, "Master")
        return ok and result ~= false
    end
    if not (PlaySound and SOUNDKIT) then
        return false
    end
    local soundKit = mode == "bell" and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        or SOUNDKIT.RAID_WARNING
    if not soundKit then
        return false
    end
    return pcall(PlaySound, soundKit, "Master")
end

function RaidLeadTools:UpdateHealerManaStatusAlerts(healers)
    healers = type(healers) == "table" and healers or {}
    local previous = self.healerManaAlertStates or {}
    local current = {}
    local shouldPlay = false

    for index, healer in ipairs(healers) do
        local key = tostring(healer.guid or healer.unit or healer.name or index)
        local state = self:ResolveHealerManaVisual(healer).stateText or ""
        current[key] = state
        if self.healerManaAlertsPrimed
            and previous[key] ~= nil
            and previous[key] ~= state
            and HEALER_MANA_ALERT_STATES[state] then
            shouldPlay = true
        end
    end

    self.healerManaAlertStates = current
    if not self.healerManaAlertsPrimed then
        self.healerManaAlertsPrimed = true
        return false
    end
    if shouldPlay then
        return self:PlayHealerManaStatusSound()
    end
    return false
end

local function IsUnitDrinking(unit)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
        return nil
    end
    for i = 1, 40 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok or IsSecret(aura) then
            return nil
        end
        if aura == nil then
            break
        end
        local okType, auraType = pcall(type, aura)
        if not okType or auraType ~= "table" then
            return nil
        end
        local okFields, name, spellID = pcall(function()
            return aura.name, aura.spellId
        end)
        if not okFields then
            return nil
        end
        if (IsSecret(name) or not name) and not IsSecret(spellID) and spellID
            and C_Spell and C_Spell.GetSpellName then
            local okSpell, spellName = pcall(C_Spell.GetSpellName, spellID)
            if okSpell and not IsSecret(spellName) then
                name = spellName
            end
        end
        if not IsSecret(name) and name then
            local lower = string.lower(name)
            if lower:find("drink", 1, true) or lower:find("refreshment", 1, true) then
                return true
            end
        end
    end
    return false
end

local function GetLowestDurabilityPercent()
    local lowest
    for slot = 1, 19 do
        local current, maximum
        if GetInventoryItemDurability then
            current, maximum = GetInventoryItemDurability(slot)
        end
        if current and maximum and maximum > 0 then
            local percent = math.floor((current / maximum) * 100 + 0.5)
            if not lowest or percent < lowest then
                lowest = percent
            end
        end
    end
    return lowest
end

function RaidLeadTools:OnInitialize()
    self.db = RC.db.profile
    self.durability = {}
    self.lastPull = nil
    self.pullCandidates = {}
    self.bresCasts = {}
    self.bresCastGUIDs = {}
    self.bresPendingCasts = {}
    self.bresUnitState = {}
    self.bresRosterByUnit = {}
    self.bresRosterByGUID = {}
    self.bresInstanceKey = nil
    self.healerManaComm = {}
    self.healerSpecCache = {}
    self.healerInspectQueue = {}
    self.healerManaAlertStates = {}
    self.healerManaAlertsPrimed = false
    self.pullCaptureActive = false
    self:CreateBattleResFrame()
    self:CreateHealerManaFrame()
    self:RefreshTheme()
end

function RaidLeadTools:IsBattleResInstance()
    return GetBattleResInstanceContext()
end

function RaidLeadTools:GetBattleResGroupUnits()
    local units = { "player" }
    if SafeBooleanCall(IsInRaid) then
        local ok, count = pcall(GetNumGroupMembers)
        count = ok and SafeNumber(count) or 0
        for index = 1, math.min(count or 0, 40) do
            units[#units + 1] = "raid" .. index
        end
    elseif SafeBooleanCall(IsInGroup) then
        local ok, count = pcall(GetNumSubgroupMembers)
        count = ok and SafeNumber(count) or 0
        for index = 1, math.min(count or 0, 4) do
            units[#units + 1] = "party" .. index
        end
    end
    return units
end

function RaidLeadTools:UpdateBattleResRosterCache()
    self.bresRosterByUnit = self.bresRosterByUnit or {}
    self.bresRosterByGUID = self.bresRosterByGUID or {}
    for _, unit in ipairs(self:GetBattleResGroupUnits()) do
        if SafeUnitExists(unit) then
            local name, guid = ReadUnitIdentity(unit)
            if name then
                self.bresRosterByUnit[unit] = name
                if guid then
                    self.bresRosterByGUID[guid] = name
                end
            end
        end
    end
    self:BackfillBattleResHistoryNames()
end

function RaidLeadTools:BackfillBattleResHistoryNames()
    for _, entry in ipairs(self.bresCasts or {}) do
        if not NormalizeName(entry.name) and entry.sourceUnit then
            entry.name = self:ResolveBattleResUnitName(entry.sourceUnit) or entry.name
        end
        if not NormalizeName(entry.target) and entry.targetUnit then
            entry.target = self:ResolveBattleResUnitName(entry.targetUnit) or entry.target
        end
    end
end

function RaidLeadTools:ResolveBattleResUnitName(unit)
    if not unit then
        return nil
    end
    local name, guid = ReadUnitIdentity(unit)
    if name then
        self.bresRosterByUnit = self.bresRosterByUnit or {}
        self.bresRosterByGUID = self.bresRosterByGUID or {}
        self.bresRosterByUnit[unit] = name
        if guid then
            self.bresRosterByGUID[guid] = name
        end
        return name
    end
    local cached = self.bresRosterByUnit and self.bresRosterByUnit[unit]
    if cached then
        return cached
    end
    return guid and self.bresRosterByGUID and self.bresRosterByGUID[guid] or nil
end

function RaidLeadTools:RefreshBattleResInstanceContext()
    local active, instanceKey = self:IsBattleResInstance()
    if self.bresInstanceKey ~= instanceKey then
        self.bresInstanceKey = instanceKey
        self.bresCasts = {}
        self.bresCastGUIDs = {}
        self.bresPendingCasts = {}
        self.bresUnitState = {}
    end
    return active
end

function RaidLeadTools:OnEnable()
    self:RegisterComm(COMM_PREFIX)
    self:RegisterLeadToolEvents()
    self:UpdateBattleResRosterCache()
    self:RefreshBattleResInstanceContext()
    if not self.bresTicker and C_Timer and C_Timer.NewTicker then
        self.bresTicker = C_Timer.NewTicker(1, function()
            self:ScanBattleResTargets()
            self:MaybeSendHealerMana()
            self:UpdateBattleResFrame()
            self:UpdateHealerManaFrame()
        end)
    end
    self:UpdateBattleResFrame()
    self:UpdateHealerManaFrame()
end

function RaidLeadTools:OnDisable()
    self:StopPullCapture()
    if self.bresTicker then
        self.bresTicker:Cancel()
        self.bresTicker = nil
    end
    if self.bresFrame then
        self.bresFrame:Hide()
    end
    if self.healerManaFrame then
        self.healerManaFrame:Hide()
    end
    self:UnregisterLeadToolEvents()
    self.healerInspectQueue = {}
    self.healerCurrentInspect = nil
    self.healerManaAlertStates = {}
    self.healerManaAlertsPrimed = false
end

function RaidLeadTools:RefreshHealerManaUnitEvents()
    if type(CreateFrame) ~= "function" then
        return
    end

    self.healerManaUnitEventFrames = self.healerManaUnitEventFrames or {}
    local units = self:GetTrackedHealerUnits()
    local trackerCount = math.max(#units, #self.healerManaUnitEventFrames)
    for index = 1, trackerCount do
        local tracker = self.healerManaUnitEventFrames[index]
        if not tracker then
            tracker = CreateFrame("Frame")
            tracker:SetScript("OnEvent", function()
                if self.leadEventsEnabled then
                    self:UpdateHealerManaFrame(true)
                end
            end)
            self.healerManaUnitEventFrames[index] = tracker
        end
        if tracker.UnregisterAllEvents then
            tracker:UnregisterAllEvents()
        end
        local unit = units[index]
        tracker._raidControlUnit = unit
        if unit and tracker.RegisterUnitEvent then
            tracker:RegisterUnitEvent("UNIT_POWER_UPDATE", unit)
            tracker:RegisterUnitEvent("UNIT_MAXPOWER", unit)
            tracker:RegisterUnitEvent("UNIT_DISPLAYPOWER", unit)
        end
    end
end

function RaidLeadTools:RegisterLeadToolEvents()
    self.leadEventsEnabled = true
    if not self.leadEventFrame then
        local frame = CreateFrame("Frame", "RC_RaidLeadToolsEventFrame")
        frame:SetScript("OnEvent", function(_, event, ...)
            if not self.leadEventsEnabled then
                return
            end
            if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA"
                or event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_SPECIALIZATION_CHANGED"
            then
                self:UpdateBattleResRosterCache()
                self:RefreshBattleResInstanceContext()
                self:RefreshHealerManaUnitEvents()
                self:UpdateBattleResFrame()
                self:UpdateHealerManaFrame(true)
            elseif event == "ENCOUNTER_START" then
                local encounterID, encounterName = ...
                self:StartBossPullTracking(encounterID, encounterName)
                self:UpdateHealerManaFrame(true)
            elseif event == "ENCOUNTER_END" then
                self:EndBossPullTracking()
                self:UpdateHealerManaFrame(true)
            elseif event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_COMPLETED"
                or event == "CHALLENGE_MODE_RESET" or event == "WORLD_STATE_TIMER_START"
                or event == "WORLD_STATE_TIMER_STOP" then
                self:UpdateBattleResFrame()
                self:UpdateHealerManaFrame(true)
            elseif event == "INCOMING_RESURRECT_CHANGED" then
                self:ScanBattleResTargets()
                self:UpdateBattleResFrame()
            elseif event == "INSPECT_READY" then
                self:OnHealerInspectReady(...)
            elseif event == "PLAYER_REGEN_DISABLED" then
                self:StartPullCapture()
            elseif event == "PLAYER_REGEN_ENABLED" then
                self:OnLeadCombatEnded()
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                self:ProcessUnitSpellcastSucceeded(...)
            elseif event == "UNIT_SPELLCAST_SENT" then
                self:ProcessUnitSpellcastSent(...)
            else
                self:UpdateHealerManaFrame(true)
            end
        end)
        self.leadEventFrame = frame
    end
    local events = {
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD",
        "ZONE_CHANGED_NEW_AREA",
        "PLAYER_ROLES_ASSIGNED",
        "PLAYER_SPECIALIZATION_CHANGED",
        "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED",
        "INSPECT_READY",
        "INCOMING_RESURRECT_CHANGED",
        "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_SENT",
        "CHALLENGE_MODE_START",
        "CHALLENGE_MODE_COMPLETED",
        "CHALLENGE_MODE_RESET",
        "WORLD_STATE_TIMER_START",
        "WORLD_STATE_TIMER_STOP",
        "ENCOUNTER_START",
        "ENCOUNTER_END",
    }
    if not self.leadEventsRegistered then
        for _, event in ipairs(events) do
            self.leadEventFrame:RegisterEvent(event)
        end
        self.leadEventsRegistered = true
    end
    self:RefreshHealerManaUnitEvents()
end

function RaidLeadTools:StartPullCapture()
    if self.db.enableWhoPulled == false or self.pullCaptureActive or not self.leadEventFrame then
        return
    end
    self.pullCaptureActive = true
    self.pullCandidates = {}
    self.pullCaptureEndsAt = PreciseNow() + PULL_CAPTURE_WINDOW_SECONDS
end

function RaidLeadTools:StopPullCapture()
    self.pullCaptureActive = false
    self.pullCaptureEndsAt = nil
end

function RaidLeadTools:CaptureCombatLogEvent()
    if not self.pullCaptureActive or not CombatLogGetCurrentEventInfo then
        return
    end
    if self.pullCaptureEndsAt and PreciseNow() >= self.pullCaptureEndsAt then
        self:StopPullCapture()
        return
    end
    local _, subEvent, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, destFlags, _,
        spellID, spellName = CombatLogGetCurrentEventInfo()
    self:ProcessCombatLogEvent(
        subEvent,
        sourceGUID,
        sourceName,
        sourceFlags,
        destGUID,
        destName,
        destFlags,
        spellID,
        spellName
    )
end

function RaidLeadTools:UnregisterLeadToolEvents()
    self.leadEventsEnabled = false
end

function RaidLeadTools:ProcessUnitSpellcastSent(unit, targetName, castGUID, spellID)
    if not self:IsEnabled() or self.db.enableBattleResTracker == false or IsSecret(spellID) or not BRES_SPELLS[spellID] then
        return false
    end
    if not self:IsBattleResInstance() or IsSecret(castGUID) then
        return false
    end
    castGUID = castGUID or (tostring(unit or "unit") .. ":" .. tostring(Now()))
    self.bresPendingCasts = self.bresPendingCasts or {}
    self.bresPendingCasts[castGUID] = {
        name = self:ResolveBattleResUnitName(unit),
        target = NormalizeName(targetName),
        sourceUnit = unit,
        when = Now(),
    }
    return true
end

function RaidLeadTools:ProcessUnitSpellcastSucceeded(unit, castGUID, spellID)
    if not self:IsEnabled() or self.db.enableBattleResTracker == false or IsSecret(spellID) or not BRES_SPELLS[spellID] then
        return false
    end
    local inBattleResInstance = self:IsBattleResInstance()
    if not inBattleResInstance then
        return false
    end
    local now = Now()
    self.bresCastGUIDs = self.bresCastGUIDs or {}
    for guid, recordedAt in pairs(self.bresCastGUIDs) do
        if (now - recordedAt) > 30 then
            self.bresCastGUIDs[guid] = nil
        end
    end
    if IsSecret(castGUID) then
        castGUID = nil
    end
    if castGUID and self.bresCastGUIDs[castGUID] then
        return false
    end
    if castGUID then
        self.bresCastGUIDs[castGUID] = now
    end
    local sent = castGUID and self.bresPendingCasts and self.bresPendingCasts[castGUID]
    if sent and self.bresPendingCasts then
        self.bresPendingCasts[castGUID] = nil
    end
    local sourceName = self:ResolveBattleResUnitName(unit) or (sent and sent.name)
    local targetName = sent and sent.target
    local pending = self:FindBattleResAwaitingCaster(now)
    if pending then
        pending.name = sourceName or pending.name
        pending.target = targetName or pending.target
        pending.spell = BRES_SPELLS[spellID]
        pending.castGUID = castGUID or pending.castGUID
        pending.sourceUnit = unit or pending.sourceUnit
        pending.updatedAt = now
        self:UpdateBattleResFrame()
    else
        self:RecordBattleRes(sourceName, BRES_SPELLS[spellID], targetName, "Cast", nil, castGUID, unit)
    end
    return true
end

function RaidLeadTools:QueueHealerInspect(unit, guid)
    if not unit or not guid or self.healerSpecCache[guid] then
        return false
    end
    if not (CanInspect and NotifyInspect and UnitExists(unit)) then
        return false
    end
    if IsInCombat() then
        self.healerInspectPendingAfterCombat = true
        return false
    end
    if self.healerCurrentInspect and self.healerCurrentInspect.guid == guid then
        return false
    end
    local okCanInspect, canInspect = pcall(CanInspect, unit)
    if not okCanInspect or IsSecret(canInspect) or not canInspect then
        return false
    end
    self.healerInspectQueue = self.healerInspectQueue or {}
    for _, queued in ipairs(self.healerInspectQueue) do
        if queued.guid == guid then
            return false
        end
    end
    self.healerInspectQueue[#self.healerInspectQueue + 1] = { unit = unit, guid = guid }
    self:ProcessHealerInspectQueue()
    return true
end

function RaidLeadTools:ProcessHealerInspectQueue()
    if IsInCombat() then
        self.healerInspectPendingAfterCombat = true
        return false
    end
    if self.healerCurrentInspect or not self.healerInspectQueue or #self.healerInspectQueue == 0 then
        return false
    end
    local entry = table.remove(self.healerInspectQueue, 1)
    if not entry or not UnitExists(entry.unit) then
        self:ProcessHealerInspectQueue()
        return false
    end
    self.healerCurrentInspect = entry
    local okNotify = pcall(NotifyInspect, entry.unit)
    if not okNotify then
        self.healerCurrentInspect = nil
        if C_Timer and C_Timer.After then
            C_Timer.After(HEALER_INSPECT_DELAY, function() self:ProcessHealerInspectQueue() end)
        end
        return false
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(2, function()
            if self.healerCurrentInspect and self.healerCurrentInspect.guid == entry.guid then
                if IsInCombat() then
                    self.healerCurrentInspect = nil
                    self.healerInspectPendingAfterCombat = true
                    return
                end
                self.healerCurrentInspect = nil
                self:ProcessHealerInspectQueue()
            end
        end)
    end
    return true
end

function RaidLeadTools:OnHealerInspectReady(guid)
    local entry = self.healerCurrentInspect
    if not entry or entry.guid ~= guid then
        return
    end
    if IsInCombat() then
        self.healerCurrentInspect = nil
        self.healerInspectPendingAfterCombat = true
        return
    end
    self.healerCurrentInspect = nil
    if UnitExists(entry.unit) and GetInspectSpecialization then
        local okSpec, specID = pcall(GetInspectSpecialization, entry.unit)
        if okSpec and IsOrdinaryNumber(specID) and specID > 0 then
            self.healerSpecCache = self.healerSpecCache or {}
            self.healerSpecCache[guid] = specID
        end
    end
    self:UpdateHealerManaFrame(true)
    if C_Timer and C_Timer.After then
        C_Timer.After(HEALER_INSPECT_DELAY, function() self:ProcessHealerInspectQueue() end)
    end
end

function RaidLeadTools:OnLeadCombatEnded()
    self:StopPullCapture()
    if self.healerInspectPendingAfterCombat and ClearInspectPlayer then
        pcall(ClearInspectPlayer)
    end
    self.healerInspectPendingAfterCombat = nil
    self.healerCurrentInspect = nil
    self:ProcessHealerInspectQueue()
    self:UpdateHealerManaFrame(true)
end

function RaidLeadTools:GetHealerSpecIcon(unit, guid)
    if self.db and (self.db.healerManaShowSpecIcon == false
        or self:NormalizeHealerManaStyle(self.db.healerManaStyle) == "minimal") then
        return HEALER_MANA_FALLBACK_ICON
    end
    local specID = guid and self.healerSpecCache and self.healerSpecCache[guid]
    if unit == "player" and C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecializationInfo then
        local okSpec, specIndex = pcall(C_SpecializationInfo.GetSpecialization)
        if okSpec and not IsSecret(specIndex) and specIndex then
            local okInfo, _, _, _, icon = pcall(C_SpecializationInfo.GetSpecializationInfo, specIndex)
            if okInfo and not IsSecret(icon) and icon then
                return icon
            end
        end
    end
    if specID and GetSpecializationInfoByID then
        local okInfo, _, _, _, icon = pcall(GetSpecializationInfoByID, specID)
        if okInfo and not IsSecret(icon) and icon then
            return icon
        end
    elseif guid then
        self:QueueHealerInspect(unit, guid)
    end
    return HEALER_MANA_FALLBACK_ICON
end

function RaidLeadTools:SaveHealerManaPosition(frame)
    frame = frame or self.healerManaFrame
    if not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    self.db.healerManaPos = { point, "UIParent", relativePoint, x, y }
end

function RaidLeadTools:ApplyHealerManaScale(rawScale)
    local scale = ClampNumber(rawScale, 0.5, 2, 1)
    self.db.healerManaScale = scale
    if self.healerManaFrame then
        if RC.SetScalePreserveCenter then
            RC:SetScalePreserveCenter(self.healerManaFrame, scale, function(frame)
                self:SaveHealerManaPosition(frame)
            end)
        else
            self.healerManaFrame:SetScale(scale)
        end
    end
    return scale
end

function RaidLeadTools:KeepHealerManaClearOfTopUI(frame)
    frame = frame or self.healerManaFrame
    if not frame or not self.db or self.db.healerManaAvoidTopUI == false or not UIParent then
        return false
    end

    local parentTop = SafeFrameNumber(UIParent, "GetTop")
    local parentBottom = SafeFrameNumber(UIParent, "GetBottom")
    local parentLeft = SafeFrameNumber(UIParent, "GetLeft")
    local frameTop = SafeFrameNumber(frame, "GetTop")
    local frameLeft = SafeFrameNumber(frame, "GetLeft")
    local frameRight = SafeFrameNumber(frame, "GetRight")
    if not parentTop or not parentBottom or not parentLeft or not frameTop or not frameLeft or not frameRight then
        return false
    end

    local safeTop = parentTop - HEALER_MANA_TOP_SAFE_MARGIN
    for _, globalName in ipairs(HEALER_MANA_TOP_WIDGETS) do
        local widget = _G[globalName]
        if SafeFrameShown(widget) then
            local widgetLeft = SafeFrameNumber(widget, "GetLeft")
            local widgetRight = SafeFrameNumber(widget, "GetRight")
            local widgetBottom = SafeFrameNumber(widget, "GetBottom")
            local overlapsHorizontally = widgetLeft and widgetRight
                and frameRight > (widgetLeft - HEALER_MANA_TOP_WIDGET_GAP)
                and frameLeft < (widgetRight + HEALER_MANA_TOP_WIDGET_GAP)
            if overlapsHorizontally and widgetBottom
                and widgetBottom > parentBottom + ((parentTop - parentBottom) * 0.55) then
                safeTop = math.min(safeTop, widgetBottom - HEALER_MANA_TOP_WIDGET_GAP)
            end
        end
    end

    if frameTop <= safeTop then
        return false
    end

    local centerX = (frameLeft + frameRight) / 2
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "BOTTOMLEFT", centerX - parentLeft, safeTop - parentBottom)
    return true
end

function RaidLeadTools:CreateHealerManaFrame()
    local frame = CreateFrame("Frame", "RC_HealerManaFrame", UIParent, "BackdropTemplate")
    frame:SetSize(120, 38)
    frame:SetScale(ClampNumber(self.db.healerManaScale, 0.5, 2, 1))
    if self.db.healerManaPos then
        frame:SetPoint(unpack(self.db.healerManaPos))
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 145)
    end
    frame:SetFrameStrata(RAID_STATUS_HUD_STRATA)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        if RC.IsUILayoutUnlocked and RC:IsUILayoutUnlocked() then
            f.rcMoving = true
            f:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(f)
        if not f.rcMoving then return end
        f.rcMoving = nil
        f:StopMovingOrSizing()
        self:KeepHealerManaClearOfTopUI(f)
        self:SaveHealerManaPosition(f)
    end)
    RC:SkinFrame(frame)
    RC:ApplyThemedPanel(frame, "panel", { alpha = 0.35 })

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetFontObject(GameFontNormal)
    SetSafeFont(frame.title, 11, "OUTLINE")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -6)
    frame.title:SetText(L["HEALER MANA"])
    frame.title:SetTextColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)

    frame.rows = {}
    for i = 1, 8 do
        local row = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        row:SetSize(120, 38)
        RC:SkinFrame(row)
        RC:ApplyThemedPanel(row, "row", { alpha = 0 })

        row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
        row.iconFrame:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.iconFrame:SetSize(38, 38)
        row.iconFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 2,
        })
        row.iconFrame:SetBackdropColor(0, 0, 0, 1)
        row.iconFrame:SetBackdropBorderColor(0, 0, 0, 1)

        row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
        row.icon:SetPoint("TOPLEFT", row.iconFrame, "TOPLEFT", 2, -2)
        row.icon:SetPoint("BOTTOMRIGHT", row.iconFrame, "BOTTOMRIGHT", -2, 2)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetFontObject(GameFontNormal)
        row.name:SetJustifyH("LEFT")

        row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.status:SetFontObject(GameFontNormal)
        row.status:SetJustifyH("LEFT")

        row.state = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.state:SetFontObject(GameFontNormal)
        row.state:SetJustifyH("RIGHT")

        row.barTrack = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.barTrack:SetColorTexture(0, 0, 0, 0.38)

        row.manaBar = CreateFrame("StatusBar", nil, row)
        row.manaBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        row.manaBar:SetMinMaxValues(0, 100)
        row.manaBar:SetValue(0)
        row.manaBar:SetFrameLevel((row:GetFrameLevel() or 1) + 1)

        frame.rows[i] = row
    end
    frame:Hide()
    self.healerManaFrame = frame
end

function RaidLeadTools:ApplyHealerManaDisplay(healers)
    local frame = self.healerManaFrame
    if not frame then
        return
    end
    healers = type(healers) == "table" and healers or {}
    local db = self.db or {}
    local style = self:NormalizeHealerManaStyle(db.healerManaStyle)
    local portraitRows = style == "compact"
    local width = ClampNumber(db.healerManaFrameWidth or db.healerManaWidth, 140, 420, 210)
    local iconSize = ClampNumber(db.healerManaIconSize, 16, 64, 24)
    local nameFontSize = ClampNumber(db.healerManaNameFontSize or db.healerManaFontSize, 8, 32, 13)
    local manaFontSize = ClampNumber(db.healerManaManaFontSize, 8, 32, 14)
    local spacing = ClampNumber(db.healerManaRowSpacing, 0, 20, 2)
    local padding = ClampNumber(db.healerManaPadding, 0, 16, 6)
    local barHeight = ClampNumber(db.healerManaBarHeight, 2, 12, 5)
    local showTitle = db.healerManaShowTitle ~= false
    local showBackground = db.healerManaShowBackground ~= false
    local showBars = db.healerManaShowBars ~= false
    local showIcons = db.healerManaShowSpecIcon ~= false and style ~= "minimal"
    local showStateTags = db.healerManaShowStateTags ~= false
    local growDown = db.healerManaGrowDirection ~= "UP"
    local backgroundAlpha = ClampNumber(db.healerManaBackgroundAlpha, 0, 1, 0.88)
    local borderAlpha = ClampNumber(db.healerManaBorderAlpha, 0, 1, 0.16)
    local rowAlpha = ClampNumber(db.healerManaRowAlpha, 0, 1, 0.28)
    local barAlpha = ClampNumber(db.healerManaBarAlpha, 0.1, 1, 0.82)
    local scale = ClampNumber(db.healerManaScale, 0.5, 2, 1)
    local alpha = ClampNumber(db.healerManaAlpha, 0.2, 1, 1)
    local titleOffset = showTitle and 22 or 0
    local barReserve = showBars and (barHeight + 3) or 0
    local textGap = 3
    -- Size the text columns from their fonts so "100%" at a large mana font
    -- and "DRINKING" at a large name font are never cut off.
    local stateFontSize = math.max(8, math.min(16, nameFontSize - 2))
    local stateWidth = math.max(68, math.ceil(stateFontSize * 5.2))
    local statusWidth = math.max(58, math.ceil(manaFontSize * 2.6))
    if style == "minimal" then
        -- Keep at least ~60px for the healer's name beside the two columns.
        width = math.max(width, 7 + statusWidth + 7 + (showStateTags and (stateWidth + 6) or 0) + 6 + 60)
    end
    local rowHeight
    if portraitRows then
        rowHeight = math.max(showIcons and iconSize or 0, nameFontSize + manaFontSize + textGap + 12) + barReserve
    elseif style == "detailed" then
        rowHeight = math.max(showIcons and iconSize or 0, nameFontSize + manaFontSize + textGap + 8) + barReserve
    else
        rowHeight = math.max(showIcons and iconSize or 0, math.max(nameFontSize, manaFontSize) + 10) + barReserve
    end

    local visibleCount = math.min(#healers, #frame.rows)
    local layoutSignature = table.concat({
        style,
        tostring(width),
        tostring(iconSize),
        tostring(nameFontSize),
        tostring(manaFontSize),
        tostring(spacing),
        tostring(padding),
        tostring(barHeight),
        showTitle and "1" or "0",
        showBars and "1" or "0",
        showIcons and "1" or "0",
        showStateTags and "1" or "0",
        growDown and "1" or "0",
        tostring(scale),
        tostring(alpha),
        tostring(visibleCount),
        tostring(db.healerManaTitle or "Healer Mana"),
    }, "|")
    local layoutChanged = frame._raidControlLayoutSignature ~= layoutSignature
    frame._raidControlLayoutSignature = layoutSignature

    local panel = RC.Config.HeaderBg or RC.Config.Color or { r = 0.04, g = 0.06, b = 0.08, a = 1 }
    local surface = RC.Config.SurfaceBg or RC.Config.PanelBg or panel
    local border = RC.Config.Border or { r = 1, g = 1, b = 1, a = 0.1 }
    frame.title:SetShown(showTitle)
    frame:SetBackdropColor(panel.r, panel.g, panel.b, showBackground and backgroundAlpha or 0)
    frame:SetBackdropBorderColor(border.r, border.g, border.b, showBackground and borderAlpha or 0)

    if layoutChanged then
        frame.title:SetText(tostring(db.healerManaTitle or "Healer Mana"):upper())
        SetSafeFont(frame.title, math.max(9, math.min(14, nameFontSize - 2)), "OUTLINE")
        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -padding)
        for index, row in ipairs(frame.rows or {}) do
            row:ClearAllPoints()
            local offset = (index - 1) * (rowHeight + spacing)
            if growDown then
                row:SetPoint("TOPLEFT", frame, "TOPLEFT", padding, -(padding + titleOffset + offset))
            else
                row:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", padding, padding + offset)
            end
            row:SetSize(width, rowHeight)
            row.iconFrame:ClearAllPoints()
            row.iconFrame:SetPoint("LEFT", row, "LEFT", 4, math.floor(barReserve / 2))
            row.iconFrame:SetSize(iconSize, iconSize)
            row.barTrack:ClearAllPoints()
            row.barTrack:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 3, 3)
            row.barTrack:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 3)
            row.barTrack:SetHeight(barHeight)
            row.manaBar:ClearAllPoints()
            row.manaBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 3, 3)
            row.manaBar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -3, 3)
            row.manaBar:SetHeight(barHeight)
            SetSafeFont(row.name, nameFontSize, "OUTLINE")
            SetSafeFont(row.status, manaFontSize, "OUTLINE")
            SetSafeFont(row.state, stateFontSize, "OUTLINE")
            row.name:ClearAllPoints()
            row.status:ClearAllPoints()
            row.state:ClearAllPoints()
            local textLeft = showIcons and (iconSize + 11) or 7
            if portraitRows then
                local textTop = -math.max(0, math.floor((rowHeight - barReserve - nameFontSize - manaFontSize - textGap) / 2))
                row.name:SetJustifyH("LEFT")
                row.name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, textTop)
                row.name:SetPoint("RIGHT", row, "RIGHT", showStateTags and -(stateWidth + 6) or -2, 0)
                row.status:SetJustifyH("LEFT")
                row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -textGap)
                row.status:SetWidth(math.max(64, width - textLeft))
                row.state:SetJustifyH("RIGHT")
                row.state:SetPoint("TOPRIGHT", row, "TOPRIGHT", -2, textTop)
                row.state:SetSize(stateWidth, nameFontSize + 4)
            elseif style == "detailed" then
                local textBlockHeight = nameFontSize + manaFontSize + textGap + 5
                local textTop = -math.max(3, math.floor((rowHeight - barReserve - textBlockHeight) / 2))
                row.name:SetJustifyH("LEFT")
                row.name:SetPoint("TOPLEFT", row, "TOPLEFT", textLeft, textTop)
                row.name:SetPoint("RIGHT", row, "RIGHT", showStateTags and -(stateWidth + 8) or -6, 0)
                row.state:SetJustifyH("RIGHT")
                row.state:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, textTop)
                row.state:SetSize(stateWidth, nameFontSize + 4)
                row.status:SetJustifyH("LEFT")
                row.status:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -textGap)
                row.status:SetWidth(math.max(52, width - textLeft - 8))
            else
                row.status:SetJustifyH("RIGHT")
                row.status:SetPoint("RIGHT", row, "RIGHT", -7, math.floor(barReserve / 2))
                row.status:SetSize(statusWidth, manaFontSize + 5)
                row.state:SetJustifyH("RIGHT")
                row.state:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
                row.state:SetSize(stateWidth, nameFontSize + 4)
                row.name:SetJustifyH("LEFT")
                row.name:SetPoint("LEFT", row, "LEFT", textLeft, math.floor(barReserve / 2))
                row.name:SetPoint("RIGHT", showStateTags and row.state or row.status, "LEFT", -6, 0)
            end
        end
        self:ApplyHealerManaScale(scale)
        frame:SetAlpha(alpha)
        local rowsHeight = (visibleCount * rowHeight) + (math.max(0, visibleCount - 1) * spacing)
        frame:SetSize(width + (padding * 2), math.max(rowHeight, titleOffset + rowsHeight) + (padding * 2))
        self:KeepHealerManaClearOfTopUI(frame)
    end

    for index, row in ipairs(frame.rows or {}) do
        local healer = healers[index]
        local visibleRowAlpha = (style == "minimal" or not showBackground) and 0 or rowAlpha
        row:SetBackdropColor(surface.r, surface.g, surface.b, visibleRowAlpha)
        row:SetBackdropBorderColor(border.r, border.g, border.b, visibleRowAlpha == 0 and 0 or math.min(borderAlpha, 0.24))
        row.iconFrame:SetShown(showIcons and healer ~= nil)
        row.barTrack:SetShown(showBars and healer ~= nil)
        row.manaBar:SetShown(showBars and healer ~= nil)
        if healer then
            local visual = self:ResolveHealerManaVisual(healer)
            local classColor = db.healerManaClassColorNames ~= false
                and healer.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[healer.class]
            row.icon:SetTexture(healer.drinking and db.healerManaShowDrinking ~= false
                and HEALER_MANA_DRINK_ICON or healer.icon or HEALER_MANA_FALLBACK_ICON)
            row.icon:SetVertexColor(visual.iconAlpha, visual.iconAlpha, visual.iconAlpha, 1)
            row.iconFrame:SetBackdropColor(0.01, 0.015, 0.02, 0.92)
            if portraitRows and not healer.drinking then
                row.iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
            else
                row.iconFrame:SetBackdropBorderColor(visual.r, visual.g, visual.b, 0.92)
            end
            row.name:SetText(healer.name or L["Unknown"])
            row.name:SetTextColor(classColor and classColor.r or 0.90, classColor and classColor.g or 0.92, classColor and classColor.b or 0.95, 1)
            row.status:SetText(visual.statusText)
            if healer.hasProtectedManaValue then
                SetProtectedPercentText(row.status, healer.protectedManaValue)
            end
            if portraitRows then
                if visual.isLowMana then
                    row.status:SetTextColor(visual.statusR, visual.statusG, visual.statusB, visual.statusA)
                else
                    local white = RC.Config.WhiteText or RC.Config.Text or { r = 1, g = 1, b = 1, a = 1 }
                    row.status:SetTextColor(white.r, white.g, white.b, white.a or 1)
                end
            else
                row.status:SetTextColor(visual.statusR, visual.statusG, visual.statusB, visual.statusA)
            end
            row.state:SetText(HEALER_MANA_STATE_LABELS[visual.stateText] or visual.stateText)
            row.state:SetTextColor(visual.r, visual.g, visual.b, visual.a)
            row.state:SetShown(showStateTags)
            row._raidControlManaUnit = healer.unit
            row._raidControlManaStyle = style
            row._raidControlBarAlpha = barAlpha
            row.manaBar:SetMinMaxValues(0, 100)
            if healer.hasProtectedManaValue then
                row.manaBar:SetValue(healer.protectedManaValue)
            else
                row.manaBar:SetValue(visual.value)
            end
            row.manaBar:SetStatusBarColor(visual.r, visual.g, visual.b, barAlpha)
            row:Show()
        else
            row._raidControlManaUnit = nil
            row:Hide()
        end
    end

    frame:SetShown(visibleCount > 0)
end

function RaidLeadTools:UpdateHealerManaFrame(force)
    local frame = self.healerManaFrame
    if not frame then
        return
    end
    if self._layoutModeActive then
        return
    end
    if not self:IsEnabled() or not ShouldShowHealerMana(self.db) then
        frame:Hide()
        return
    end
    local now = PreciseNow()
    if not force and self.nextHealerManaUpdate and now < self.nextHealerManaUpdate then
        return
    end
    self.nextHealerManaUpdate = now + math.max(0.25, math.min(5, tonumber(self.db.healerManaUpdateInterval) or 1))

    local healers = {}
    for _, unit in ipairs(self:GetTrackedHealerUnits()) do
        if UnitExists(unit) then
            local okName, name = pcall(GetUnitName, unit, false)
            if okName and not IsSecret(name) and name then
                local percent, manaState, percentText, protectedManaValue, hasProtectedManaValue = GetManaPercent(self, unit)
                local commPercent, commState, commDrinking = GetCommManaForName(self, name)
                if not percent and commPercent then
                    percent = commPercent
                    manaState = commState
                    percentText = string.format("%d%%", commPercent)
                end
                local okClass, _, class = pcall(UnitClass, unit)
                class = okClass and not IsSecret(class) and class or nil
                local okConnected, connected = pcall(UnitIsConnected, unit)
                connected = okConnected and not IsSecret(connected) and connected ~= false
                local okGuid, guid = pcall(UnitGUID, unit)
                guid = okGuid and not IsSecret(guid) and guid or unit
                local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
                dead = okDead and not IsSecret(dead) and dead or false
                local visibleState = GetUnitRangeState(unit)
                if not connected then
                    manaState = "OFF"
                elseif visibleState then
                    manaState = visibleState
                elseif not percent and not percentText then
                    manaState = manaState or "pending"
                end
                healers[#healers + 1] = {
                    unit = unit,
                    guid = guid,
                    name = NormalizeName(name) or name,
                    percent = percent,
                    percentText = percentText,
                    protectedManaValue = protectedManaValue,
                    hasProtectedManaValue = hasProtectedManaValue,
                    manaState = manaState,
                    drinking = connected and self.db.healerManaShowDrinking ~= false
                        and (IsUnitDrinking(unit) == true or commDrinking == true),
                    dead = dead,
                    connected = connected,
                    class = class,
                    icon = self:GetHealerSpecIcon(unit, guid),
                }
            end
        end
    end

    self:UpdateHealerManaStatusAlerts(healers)
    self:ApplyHealerManaDisplay(healers)
end

function RaidLeadTools:MaybeSendHealerMana()
    if not self:IsEnabled() or self.db.showHealerManaFrame == false then
        return
    end
    if not (IsInGroup and IsInGroup()) then
        return
    end
    local channel = GetCommChannel()
    if not channel then
        return
    end
    if not IsTrackedHealerUnit("player") then
        return
    end
    local percent = GetManaPercent(self, "player")
    if not percent then
        return
    end
    percent = math.max(0, math.min(100, math.floor(percent + 0.5)))
    local drinking = IsUnitDrinking("player") and 1 or 0
    local now = Now()
    if self.lastManaSent and (now - self.lastManaSent) < 2 and self.lastManaValue == percent and self.lastManaDrinking == drinking then
        return
    end
    self.lastManaSent = now
    self.lastManaValue = percent
    self.lastManaDrinking = drinking
    self:SendCommMessage(COMM_PREFIX, "MANA:" .. tostring(percent) .. ":" .. tostring(drinking), channel)
    local playerName = GetUnitName and GetUnitName("player", true) or UnitName("player")
    if not IsSecret(playerName) and playerName then
        local key = NormalizeName(playerName) or playerName
        self.healerManaComm[key] = { percent = percent, drinking = drinking == 1, updated = now }
    end
end

function RaidLeadTools:IsEnabled()
    return self.db and self.db.enableRaidLeadTools ~= false
end

function RaidLeadTools:SaveBattleResPosition(frame)
    frame = frame or self.bresFrame
    if not frame then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    self.db.battleResPos = { point, "UIParent", relativePoint, x, y }
end

function RaidLeadTools:ApplyBattleResScale(rawScale)
    local scale = ClampNumber(rawScale, 0.5, 2, 1)
    self.db.battleResScale = scale
    if self.bresFrame then
        if RC.SetScalePreserveCenter then
            RC:SetScalePreserveCenter(self.bresFrame, scale, function(frame)
                self:SaveBattleResPosition(frame)
            end)
        else
            self.bresFrame:SetScale(scale)
        end
    end
    return scale
end

function RaidLeadTools:CreateBattleResFrame()
    local frame = CreateFrame("Frame", "RC_BattleResFrame", UIParent, "BackdropTemplate")
    frame:SetSize(88, 40)
    frame:SetScale(ClampNumber(self.db.battleResScale, 0.5, 2, 1))
    frame:SetClampedToScreen(true)
    local savedPosition = self.db.battleResPos
    if savedPosition and not self:IsSavedBattleResPositionOffscreen(savedPosition) then
        frame:SetPoint(unpack(self.db.battleResPos))
    else
        self.db.battleResPos = nil
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 210)
    end
    frame:SetFrameStrata(RAID_STATUS_HUD_STRATA)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(f)
        if RC.IsUILayoutUnlocked and RC:IsUILayoutUnlocked() then
            f.rcMoving = true
            f:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(f)
        if not f.rcMoving then return end
        f.rcMoving = nil
        f:StopMovingOrSizing()
        self:SaveBattleResPosition(f)
    end)
    RC:SkinFrame(frame)
    RC:ApplyThemedPanel(frame, "panel", { role = "HeaderBg", alpha = 0.94 })

    frame.accentLine = frame:CreateTexture(nil, "ARTWORK")
    frame.accentLine:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -5)
    frame.accentLine:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 1, 5)
    frame.accentLine:SetWidth(2)

    frame.rechargeTrack = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    frame.rechargeTrack:SetColorTexture(0, 0, 0, 0.45)

    frame.rechargeBar = CreateFrame("StatusBar", nil, frame)
    frame.rechargeBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    frame.rechargeBar:SetMinMaxValues(0, 100)
    frame.rechargeBar:SetValue(0)
    frame.rechargeBar:SetFrameLevel((frame:GetFrameLevel() or 1) + 1)

    frame.recentDivider = frame:CreateTexture(nil, "ARTWORK")
    frame.recentDivider:SetHeight(1)

    frame.iconBackdrop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.iconBackdrop:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6)
    RC:SkinFrame(frame.iconBackdrop)
    RC:ApplyThemedPanel(frame.iconBackdrop, "input")

    frame.icon = frame.iconBackdrop:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", frame.iconBackdrop, "TOPLEFT", 1, -1)
    frame.icon:SetPoint("BOTTOMRIGHT", frame.iconBackdrop, "BOTTOMRIGHT", -1, 1)
    frame.icon:SetTexture(GetDefaultBattleResIcon())
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.cooldown = CreateFrame("Cooldown", nil, frame.iconBackdrop, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetDrawEdge(false)
    frame.cooldown:SetDrawBling(false)
    frame.cooldown:SetHideCountdownNumbers(true)

    frame.iconCount = frame.iconBackdrop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.iconCount:SetFontObject(GameFontNormal)
    SetSafeFont(frame.iconCount, 15, "OUTLINE")
    frame.iconCount:SetPoint("BOTTOMRIGHT", frame.iconBackdrop, "BOTTOMRIGHT", -2, 2)

    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.label:SetFontObject(GameFontNormal)
    SetSafeFont(frame.label, 13, "OUTLINE")
    frame.label:SetPoint("TOPLEFT", frame.iconBackdrop, "TOPRIGHT", 7, -2)
    frame.label:SetTextColor(0.82, 0.82, 0.82, 1)

    frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.count:SetFontObject(GameFontNormal)
    SetSafeFont(frame.count, 14, "OUTLINE")
    frame.count:SetPoint("TOPLEFT", frame.label, "BOTTOMLEFT", 0, -1)
    frame.count:SetTextColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)

    frame.timer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.timer:SetFontObject(GameFontNormal)
    SetSafeFont(frame.timer, 12, "OUTLINE")
    frame.timer:SetPoint("TOPLEFT", frame.count, "BOTTOMLEFT", 0, -1)
    frame.timer:SetTextColor(0.92, 0.92, 0.92, 1)

    frame.recentHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.recentHeader:SetFontObject(GameFontNormal)
    SetSafeFont(frame.recentHeader, 10, "OUTLINE")
    frame.recentHeader:SetText(L["RECENT BATTLE RES"])
    frame.recentHeader:SetTextColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)

    frame.recentRows = {}
    for i = 1, 8 do
        local row = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row:SetFontObject(GameFontNormal)
        SetSafeFont(row, 10, "OUTLINE")
        row:SetJustifyH("LEFT")
        row:SetTextColor(0.82, 0.82, 0.82, 1)
        frame.recentRows[i] = row
    end

    frame:SetScript("OnEnter", function()
        self:ShowBattleResTooltip(frame)
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    frame:Hide()
    self.bresFrame = frame
end

local function FormatRemainingTime(remaining, format)
    remaining = math.max(0, math.ceil(remaining or 0))
    if format == "seconds" then
        return tostring(remaining) .. "s"
    elseif format == "compact" then
        if remaining >= 60 then
            return tostring(math.ceil(remaining / 60)) .. "m"
        end
        return tostring(remaining) .. "s"
    end
    return string.format("%d:%02d", math.floor(remaining / 60), remaining % 60)
end

function RaidLeadTools:GetBattleResStatus()
    local current, maxCharges, startTime, duration = GetChargesForSpell(BRES_CHARGE_SPELL_ID)
    if current ~= nil and maxCharges ~= nil and not (current == 0 and maxCharges == 0) then
        return current, maxCharges, startTime, duration, BRES_CHARGE_SPELL_ID
    end
    return nil
end

function RaidLeadTools:GetBattleResVisualState(current, maxCharges, startTime, duration, now)
    local db = self.db or {}
    local readyR, readyG, readyB, readyA = GetDBColor(db.battleResReadyColor, 0.25, 0.90, 0.45, 1)
    local rechargeR, rechargeG, rechargeB, rechargeA = GetDBColor(db.battleResRechargeColor, 1.00, 0.72, 0.20, 1)
    local emptyR, emptyG, emptyB, emptyA = GetDBColor(db.battleResEmptyColor, 1.00, 0.28, 0.22, 1)
    local state = "unknown"
    local r, g, b, a = emptyR, emptyG, emptyB, emptyA
    if current and maxCharges and current >= maxCharges and maxCharges > 0 then
        state = "ready"
        r, g, b, a = readyR, readyG, readyB, readyA
    elseif current and current > 0 then
        state = "recharging"
        r, g, b, a = rechargeR, rechargeG, rechargeB, rechargeA
    elseif current ~= nil then
        state = "empty"
    end

    local progress = 0
    now = SafeNumber(now) or (GetTime and GetTime()) or 0
    startTime = SafeNumber(startTime)
    duration = SafeNumber(duration)
    if current and maxCharges and current >= maxCharges then
        progress = 1
    elseif startTime and duration and duration > 0 then
        progress = math.max(0, math.min(1, (now - startTime) / duration))
    end
    return {
        state = state,
        r = r,
        g = g,
        b = b,
        a = a,
        progress = progress,
    }
end

function RaidLeadTools:FormatBattleResStatusValues(current, maxCharges)
    local text
    if current == nil then
        text = self.db.battleResShowMax ~= false and "0/0" or "0"
    else
        text = self.db.battleResShowMax ~= false and maxCharges
            and string.format("%d/%d", current, maxCharges)
            or tostring(current)
    end
    local visual = self:GetBattleResVisualState(current, maxCharges)
    return text, visual.r, visual.g, visual.b
end

function RaidLeadTools:FormatBattleResStatus()
    local current, maxCharges = self:GetBattleResStatus()
    return self:FormatBattleResStatusValues(current, maxCharges)
end

function RaidLeadTools:FormatBattleResTimer(current, maxCharges, startTime, duration)
    if current == nil or maxCharges == nil then
        return "--"
    end
    if current >= maxCharges and maxCharges > 0 then
        return L["READY"]
    end
    if not startTime or not duration or duration <= 0 then
        return "--"
    end
    local remaining = math.max(0, (startTime + duration) - GetTime())
    if remaining <= 0 then
        return L["READY"]
    end
    return FormatRemainingTime(remaining, self.db.battleResTimerFormat or "mmss")
end

function RaidLeadTools:FormatBattleResHistoryEntry(entry, now)
    entry = entry or {}
    local caster = entry.name or L["Resolving caster"]
    local target = entry.target or L["Resolving target"]
    local age = math.max(0, math.floor((now or Now()) - (entry.completedAt or entry.when or 0)))
    local primary = string.format("%s -> %s", caster, target)
    local status = entry.status or "Cast"
    local secondary = string.format(L["%s - %s - %ds ago"], entry.spell or L["Battle Res"], BRES_STATUS_LABELS[status] or status, age)
    return primary, secondary
end

function RaidLeadTools:ShowBattleResTooltip(owner)
    if not GameTooltip then
        return
    end
    local frame = self.bresFrame
    self:BackfillBattleResHistoryNames()
    GameTooltip:SetOwner(owner or frame, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["RaidControl Battle Res"], 1, 1, 1)
    local current = frame and frame.currentCharges
    local maximum = frame and frame.maxCharges
    local timer = frame and frame.timer and frame.timer:GetText() or "--"
    GameTooltip:AddDoubleLine(
        L["Available charges"],
        current ~= nil and maximum ~= nil and string.format("%d / %d", current, maximum) or L["Unknown"],
        0.72, 0.78, 0.84,
        1, 1, 1
    )
    GameTooltip:AddDoubleLine(L["Next charge"], timer ~= L["READY"] and timer or L["Ready"], 0.72, 0.78, 0.84, 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Recent Battle Res"], RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b)
    if self.bresCasts and #self.bresCasts > 0 then
        for i = #self.bresCasts, math.max(#self.bresCasts - 4, 1), -1 do
            local primary, secondary = self:FormatBattleResHistoryEntry(self.bresCasts[i])
            GameTooltip:AddLine(primary, 0.92, 0.92, 0.92)
            GameTooltip:AddLine(secondary, 0.62, 0.68, 0.74)
        end
    else
        GameTooltip:AddLine(L["No Battle Res casts recorded yet."], 0.62, 0.68, 0.74)
    end
    GameTooltip:Show()
end

function RaidLeadTools:ApplyBattleResDisplaySettings()
    if not self.bresFrame then
        return
    end
    local frame = self.bresFrame
    local iconSize = ClampNumber(self.db.battleResIconSize, 14, 64, 30)
    local fontSize = ClampNumber(self.db.battleResFontSize, 8, 28, 13)
    local timerFontSize = ClampNumber(self.db.battleResTimerFontSize, 8, 28, math.max(10, fontSize - 1))
    local padding = 5
    local gap = 7
    local iconValue = self.db.battleResIcon or "auto"
    local scale = ClampNumber(self.db.battleResScale, 0.5, 2, 1)
    local alpha = ClampNumber(self.db.battleResAlpha, 0.2, 1, 1)
    local showTimer = self.db.battleResShowTimer ~= false
    local settingsSignature = table.concat({
        tostring(iconSize),
        tostring(fontSize),
        tostring(timerFontSize),
        tostring(iconValue),
        tostring(scale),
        tostring(alpha),
        tostring(showTimer),
    }, "|")
    local settingsChanged = frame._raidControlSettingsSignature ~= settingsSignature
    frame._raidControlSettingsSignature = settingsSignature

    if settingsChanged then
        local numericIcon = tonumber(iconValue)
        frame.icon:SetTexture(iconValue == "auto" and GetDefaultBattleResIcon() or numericIcon or iconValue)
        frame.iconBackdrop:SetSize(iconSize + 2, iconSize + 2)
        SetSafeFont(frame.timer, timerFontSize, "OUTLINE")
        SetSafeFont(frame.iconCount, math.max(10, fontSize + 2), "OUTLINE")
        self:ApplyBattleResScale(scale)
        frame:SetAlpha(alpha)
    end

    frame.iconBackdrop:Show()
    local showCooldown = self.db.battleResShowCooldownSwipe ~= false
        and frame.currentCharges ~= nil
        and frame.currentCharges <= 0
        and frame.rechargeStart
        and frame.rechargeDuration
    frame.cooldown:SetShown(showCooldown and true or false)
    frame.label:Hide()
    frame.count:Hide()
    frame.timer:SetShown(showTimer)
    frame.iconCount:SetText(frame.count:GetText() or "")
    frame.iconCount:Show()
    frame.accentLine:Hide()
    frame.rechargeTrack:Hide()
    frame.rechargeBar:Hide()
    frame.recentHeader:Hide()
    frame.recentDivider:Hide()
    for _, row in ipairs(frame.recentRows or {}) do
        row:Hide()
    end

    local visual = self:GetBattleResVisualState(
        frame.currentCharges,
        frame.maxCharges,
        frame.rechargeStart,
        frame.rechargeDuration
    )
    local timerR, timerG, timerB, timerA = GetDBColor(self.db.battleResTimerColor, 0.78, 0.88, 1.00, 1)
    local panel = RC.Config.HeaderBg or RC.Config.Color or { r = 0.04, g = 0.06, b = 0.08, a = 1 }
    local border = RC.Config.Border or { r = 1, g = 1, b = 1, a = 0.1 }
    frame:SetBackdropColor(panel.r, panel.g, panel.b, ClampNumber(self.db.battleResBackgroundAlpha, 0, 1, 0.88))
    frame:SetBackdropBorderColor(border.r, border.g, border.b, ClampNumber(self.db.battleResBorderAlpha, 0, 1, 0.18))
    frame.iconCount:SetTextColor(visual.r, visual.g, visual.b, visual.a)
    frame.timer:SetTextColor(timerR, timerG, timerB, timerA)
    frame.iconBackdrop:SetBackdropBorderColor(visual.r, visual.g, visual.b, 0.74)

    local timerWidth = showTimer and math.max(iconSize + 2, frame.timer:GetStringWidth()) or 0
    local timerHeight = showTimer and math.max(12, timerFontSize + 3) or 0
    local layoutSignature = table.concat({
        settingsSignature,
        tostring(timerWidth),
    }, "|")
    local layoutChanged = frame._raidControlLayoutSignature ~= layoutSignature
    frame._raidControlLayoutSignature = layoutSignature

    if layoutChanged then
        frame.timer:ClearAllPoints()
        frame.iconBackdrop:ClearAllPoints()
        frame.iconBackdrop:SetPoint("TOP", frame, "TOP", 0, -padding)
        if showTimer then
            frame.timer:SetPoint("TOP", frame.iconBackdrop, "BOTTOM", 0, -2)
            frame.timer:SetWidth(timerWidth)
            frame.timer:SetHeight(timerHeight)
            frame.timer:SetJustifyH("CENTER")
        end
        frame:SetSize(
            math.max(iconSize + 2, timerWidth) + (padding * 2),
            iconSize + 2 + (padding * 2) + (showTimer and (timerHeight + 2) or 0)
        )
    end
end

function RaidLeadTools:UpdateBattleResFrame()
    if not self.bresFrame then
        return
    end
    if self._layoutModeActive then
        return
    end
    if not self:IsEnabled() or self.db.enableBattleResTracker == false or self.db.showBattleResFrame == false then
        self.bresFrame:Hide()
        return
    end

    local shouldShow = self:RefreshBattleResInstanceContext()
    self.bresFrame:SetShown(shouldShow)
    if not shouldShow then
        return
    end
    self:BackfillBattleResHistoryNames()
    local current, maxCharges, startTime, duration = self:GetBattleResStatus()
    local _, r, g, b = self:FormatBattleResStatusValues(current, maxCharges)
    local text = current ~= nil and tostring(current) or "?"
    local timerText = self:FormatBattleResTimer(current, maxCharges, startTime, duration)
    self.bresFrame.currentCharges = current
    self.bresFrame.maxCharges = maxCharges
    self.bresFrame.rechargeStart = startTime
    self.bresFrame.rechargeDuration = duration
    self.bresFrame.count:SetText(text)
    self.bresFrame.count:SetTextColor(r or 1, g or 1, b or 1, 1)
    self.bresFrame.timer:SetText(timerText or "")
    self.bresFrame.iconCount:SetText(text)
    if self.bresFrame.cooldown then
        if current ~= nil and current <= 0 and maxCharges and startTime and duration and duration > 0 then
            self.bresFrame.cooldown:SetCooldown(startTime, duration)
        else
            self.bresFrame.cooldown:Clear()
        end
    end

    self:ApplyBattleResDisplaySettings()
end

function RaidLeadTools:BeginLayoutMode(persistent)
    if persistent then
        if self._raidStatusPreviewTimer and self._raidStatusPreviewTimer.Cancel then
            self._raidStatusPreviewTimer:Cancel()
        end
        self._raidStatusPreviewTimer = nil
        self._raidStatusPreviewActive = nil
    end
    self._layoutModeActive = true

    if self.healerManaFrame then
        self:ApplyHealerManaDisplay({
            { name = "Auralis", percent = 86, class = "PRIEST", connected = true, icon = HEALER_MANA_FALLBACK_ICON },
            { name = "Nymara", percent = 24, class = "DRUID", connected = true, icon = HEALER_MANA_FALLBACK_ICON },
            { name = "Solenne", percent = 58, class = "SHAMAN", connected = true, drinking = true, icon = HEALER_MANA_FALLBACK_ICON },
        })
    end

    local bres = self.bresFrame
    if bres then
        local now = PreciseNow()
        local current, maximum, duration = 1, 2, 90
        local startTime = now - 45
        bres.currentCharges = current
        bres.maxCharges = maximum
        bres.rechargeStart = startTime
        bres.rechargeDuration = duration
        local countText = tostring(current)
        bres.count:SetText(countText)
        bres.iconCount:SetText(countText)
        bres.timer:SetText(FormatRemainingTime(45, self.db.battleResTimerFormat or "mmss"))
        if bres.cooldown and bres.cooldown.SetCooldown then
            bres.cooldown:SetCooldown(startTime, duration)
        end
        self:ApplyBattleResDisplaySettings()
        bres:Show()
    end
end

function RaidLeadTools:RefreshRaidStatusDisplays()
    if self._layoutModeActive then
        self:BeginLayoutMode()
    else
        self:UpdateBattleResFrame()
        self:UpdateHealerManaFrame(true)
    end
end

function RaidLeadTools:PreviewRaidStatusHUD()
    if InCombatLockdown and InCombatLockdown() then
        RC:Print(L["Raid status preview is unavailable during combat."])
        return false
    end
    local layoutMode = RC:GetModule("LayoutMode", true)
    if layoutMode and layoutMode.IsActive and layoutMode:IsActive() then
        self:BeginLayoutMode(true)
        return true
    end
    if self._raidStatusPreviewTimer and self._raidStatusPreviewTimer.Cancel then
        self._raidStatusPreviewTimer:Cancel()
    end
    self._raidStatusPreviewActive = true
    self:BeginLayoutMode()
    if C_Timer and C_Timer.NewTimer then
        self._raidStatusPreviewTimer = C_Timer.NewTimer(15, function()
            self._raidStatusPreviewTimer = nil
            if self._raidStatusPreviewActive then
                self:EndLayoutMode()
            end
        end)
    end
    return true
end

function RaidLeadTools:ResetRaidStatusPositions()
    if InCombatLockdown and InCombatLockdown() then
        RC:Print(L["Raid status positions cannot be reset during combat."])
        return false
    end
    self.db.healerManaPos = nil
    self.db.battleResPos = nil
    if self.healerManaFrame then
        self.healerManaFrame:ClearAllPoints()
        self.healerManaFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 145)
        self:KeepHealerManaClearOfTopUI(self.healerManaFrame)
    end
    if self.bresFrame then
        self.bresFrame:ClearAllPoints()
        self.bresFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 210)
    end
    if self._layoutModeActive then
        self:BeginLayoutMode()
    else
        self:RefreshRaidStatusDisplays()
    end
    return true
end

function RaidLeadTools:EndLayoutMode()
    if self._raidStatusPreviewTimer and self._raidStatusPreviewTimer.Cancel then
        self._raidStatusPreviewTimer:Cancel()
    end
    self._raidStatusPreviewTimer = nil
    self._raidStatusPreviewActive = nil
    self._layoutModeActive = nil
    self:UpdateBattleResFrame()
    self:UpdateHealerManaFrame(true)
end

function RaidLeadTools:RefreshTheme()
    local bres = self.bresFrame
    if bres then
        RC:ApplyThemedPanel(bres, "panel", { role = "HeaderBg", alpha = 0.94 })
        if bres.iconBackdrop then
            RC:ApplyThemedPanel(bres.iconBackdrop, "input")
        end
        if bres.label then
            bres.label:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
        end
        if bres.timer then
            bres.timer:SetTextColor(RC.Config.Text.r, RC.Config.Text.g, RC.Config.Text.b, RC.Config.Text.a or 1)
        end
        if bres.recentHeader then
            bres.recentHeader:SetTextColor(RC.Config.Selected.r, RC.Config.Selected.g, RC.Config.Selected.b, RC.Config.Selected.a or 1)
        end
        self:ApplyBattleResDisplaySettings()
    end

    local healer = self.healerManaFrame
    if healer then
        RC:ApplyThemedPanel(healer, "panel", { alpha = 0.35 })
        if healer.title then
            healer.title:SetTextColor(RC.Config.Selected.r, RC.Config.Selected.g, RC.Config.Selected.b, RC.Config.Selected.a or 1)
        end
        for _, row in ipairs(healer.rows or {}) do
            RC:ApplyThemedPanel(row, "row", { alpha = 0 })
            if row.iconFrame then
                RC:ApplyThemedPanel(row.iconFrame, "input")
            end
        end
        self:UpdateHealerManaFrame(true)
    end
end

function RaidLeadTools:ReportBattleRes()
    if not self:IsEnabled() then return end
    local text = self:FormatBattleResStatus()
    RC:Printf("%s: %s", self.db.battleResLabel or L["Battle Res"], text)
    if self.bresCasts and #self.bresCasts > 0 then
        local latest = self.bresCasts[#self.bresCasts]
        RC:Print(string.format(L["Last Battle Res: %s used %s."], latest.name or "?", latest.spell or L["Battle Res"]))
    end
end

function RaidLeadTools:RecordBattleRes(sourceName, spellName, targetName, status, targetUnit, castGUID, sourceUnit)
    self.bresCasts = self.bresCasts or {}
    local normalizedSource = NormalizeName(sourceName)
    local normalizedTarget = NormalizeName(targetName)
    local entry = {
        name = normalizedSource or (not IsSecret(sourceName) and sourceName or nil),
        spell = spellName,
        target = normalizedTarget or (not IsSecret(targetName) and targetName or nil),
        status = status,
        unitKey = targetUnit,
        targetUnit = targetUnit,
        sourceUnit = sourceUnit,
        castGUID = castGUID,
        when = Now(),
    }
    table.insert(self.bresCasts, entry)
    while #self.bresCasts > 12 do
        table.remove(self.bresCasts, 1)
    end
    self:UpdateBattleResFrame()
    return entry
end

function RaidLeadTools:FindBattleResAwaitingCaster(now)
    now = now or Now()
    for index = #(self.bresCasts or {}), 1, -1 do
        local entry = self.bresCasts[index]
        if (now - (entry.when or 0)) > 8 then
            break
        end
        if entry.status == "Incoming" and not NormalizeName(entry.name) then
            return entry
        end
    end
    return nil
end

function RaidLeadTools:FindPendingBattleRes(targetName, now)
    local normalizedTarget = NormalizeName(targetName) or targetName
    local fallback
    now = now or Now()
    for i = #(self.bresCasts or {}), 1, -1 do
        local entry = self.bresCasts[i]
        if (now - (entry.when or 0)) > 8 then
            break
        end
        if entry.status == "Cast" or entry.status == "Incoming" then
            local entryTarget = NormalizeName(entry.target) or entry.target
            if normalizedTarget and entryTarget == normalizedTarget then
                return entry
            end
            if not entryTarget and not fallback then
                fallback = entry
            end
        end
    end
    return fallback
end

function RaidLeadTools:MarkBattleResIncoming(targetName, unitKey)
    local now = Now()
    local entry = self:FindPendingBattleRes(targetName, now)
    if not entry then
        self:RecordBattleRes(nil, L["Battle Res"], targetName, "Incoming", unitKey)
        return self.bresCasts[#self.bresCasts]
    end
    entry.target = NormalizeName(targetName) or targetName or entry.target
    entry.unitKey = unitKey or entry.unitKey
    entry.targetUnit = unitKey or entry.targetUnit
    entry.status = "Incoming"
    entry.updatedAt = now
    self:UpdateBattleResFrame()
    return entry
end

function RaidLeadTools:ScanBattleResTargets()
    if not self:IsEnabled() or self.db.enableBattleResTracker == false or not UnitHasIncomingResurrection then
        return
    end
    local inBattleResInstance = self:IsBattleResInstance()
    if not inBattleResInstance then
        return
    end

    self.bresUnitState = self.bresUnitState or {}
    local units = self:GetBattleResGroupUnits()

    local seen = {}
    for _, unit in ipairs(units) do
        if SafeUnitExists(unit) then
            seen[unit] = true
            local okIncoming, incoming = pcall(UnitHasIncomingResurrection, unit)
            local okDead, dead = pcall(UnitIsDeadOrGhost, unit)
            local name = self:ResolveBattleResUnitName(unit)
            local state = self.bresUnitState[unit] or {}
            if okIncoming and IsSecret(incoming) then
                okIncoming, incoming = false, false
            end
            if okDead and IsSecret(dead) then
                okDead, dead = false, false
            end
            if okIncoming and incoming and not state.incoming then
                self:MarkBattleResIncoming(name or unit, unit)
            elseif state.incoming and okDead and not dead then
                for i = #self.bresCasts, 1, -1 do
                    local entry = self.bresCasts[i]
                    if (entry.targetUnit == unit or entry.unitKey == unit) and entry.status == "Incoming" then
                        entry.status = "Resurrected"
                        entry.completedAt = Now()
                        break
                    end
                end
            end
            state.incoming = okIncoming and incoming or false
            state.dead = okDead and dead or false
            self.bresUnitState[unit] = state
        end
    end
    for unit in pairs(self.bresUnitState) do
        if not seen[unit] then
            self.bresUnitState[unit] = nil
        end
    end
end

function RaidLeadTools:ProcessCombatLogEvent(subEvent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellID, spellName)
    if not self:IsEnabled() then
        return
    end

    if self.db.enableBattleResTracker ~= false and BRES_SPELLS[spellID] and subEvent == "SPELL_CAST_SUCCESS" then
        self:RecordBattleRes(sourceName, BRES_SPELLS[spellID] or spellName, destName, "Cast")
    end

    if not self.pullCaptureActive or self.db.enableWhoPulled == false then
        return
    end
    if subEvent ~= "SPELL_DAMAGE" and subEvent ~= "SWING_DAMAGE" and subEvent ~= "RANGE_DAMAGE" and subEvent ~= "SPELL_MISSED" and subEvent ~= "SWING_MISSED" then
        return
    end

    local groupSource = HasFlag(sourceFlags, GROUP_FLAGS)
    local hostileSource = HasFlag(sourceFlags, HOSTILE_FLAG)
    local groupTarget = HasFlag(destFlags, GROUP_FLAGS)
    local hostileTarget = HasFlag(destFlags, HOSTILE_FLAG)
    local candidate
    if groupSource and hostileTarget then
        candidate = {
            source = NormalizeName(sourceName) or sourceName or sourceGUID or L["Unknown"],
            target = destName or destGUID or L["Unknown"],
            spell = spellName or (subEvent == "SWING_DAMAGE" and L["Melee"] or subEvent),
            when = PreciseNow(),
        }
    elseif hostileSource and groupTarget then
        candidate = {
            source = NormalizeName(destName) or destName or destGUID or L["Unknown"],
            target = sourceName or sourceGUID or L["Unknown"],
            spell = L["body pull / aggro"],
            when = PreciseNow(),
        }
    end
    if candidate then
        self.pullCandidates = self.pullCandidates or {}
        table.insert(self.pullCandidates, candidate)
        while #self.pullCandidates > 40 do
            table.remove(self.pullCandidates, 1)
        end
    end
end

function RaidLeadTools:StartBossPullTracking(encounterID, encounterName)
    self:UpdateBattleResFrame()
    if self.db.enableWhoPulled == false then
        return
    end
    self:StopPullCapture()
    self.activePullEncounterID = encounterID
    self.pullReportedForEncounter = nil
    local candidate
    local encounterLower = tostring(encounterName or ""):lower()
    for i = 1, #(self.pullCandidates or {}) do
        local entry = self.pullCandidates[i]
        if (PreciseNow() - (entry.when or 0)) <= 8 then
            local targetLower = tostring(entry.target or ""):lower()
            if encounterLower ~= "" and (targetLower:find(encounterLower, 1, true) or encounterLower:find(targetLower, 1, true)) then
                candidate = entry
                break
            end
            candidate = entry
        end
    end
    local function FindBossTarget()
        for i = 1, 8 do
            local unit = "boss" .. i .. "target"
            if UnitExists(unit) then
                local ok, name = pcall(GetUnitName, unit, true)
                if ok and not IsSecret(name) and name then
                    return {
                        source = NormalizeName(name) or name,
                        target = encounterName or L["Boss"],
                        spell = L["initial aggro"],
                        when = PreciseNow(),
                    }
                end
            end
        end
        return nil
    end
    candidate = candidate or FindBossTarget()

    local function CommitCandidate(found)
        if not found or self.activePullEncounterID ~= encounterID or self.pullReportedForEncounter then
            return
        end
        found.encounterID = encounterID
        found.encounter = encounterName
        self.lastPull = found
        self.pullReportedForEncounter = true
        if self.db.whoPulledChatPrint ~= false then
            self:ReportWhoPulled()
        end
    end
    CommitCandidate(candidate)
    if not candidate and C_Timer and C_Timer.After then
        C_Timer.After(0.15, function() CommitCandidate(FindBossTarget()) end)
        C_Timer.After(0.50, function() CommitCandidate(FindBossTarget()) end)
    end
    self.pullCandidates = {}
end

function RaidLeadTools:EndBossPullTracking()
    self:StopPullCapture()
    self.activePullEncounterID = nil
    self.pullReportedForEncounter = nil
    self.pullCandidates = {}
    self:UpdateBattleResFrame()
end

function RaidLeadTools:ReportWhoPulled()
    if not self.lastPull then
        RC:Print(L["Who pulled: no pull recorded yet."])
        return
    end
    local source = self.lastPull.source or L["Unknown"]
    local target = self.lastPull.target or L["Unknown"]
    local spell = self.lastPull.spell or L["Unknown"]
    if self.lastPull.encounter then
        RC:Print(string.format(L["Who pulled %s: %s engaged %s with %s."], self.lastPull.encounter, source, target, spell))
    else
        RC:Print(string.format(L["Who pulled: %s engaged %s with %s."], source, target, spell))
    end
end

function RaidLeadTools:SendDurability()
    if self.db.enableDurabilityComm == false then
        return
    end
    local channel = GetCommChannel()
    if not channel then
        return
    end
    local percent = GetLowestDurabilityPercent()
    if percent then
        self:SendCommMessage(COMM_PREFIX, "DURA:" .. tostring(percent), channel)
        local playerName = GetUnitName and GetUnitName("player", true) or UnitName("player")
        if playerName then
            self.durability[playerName] = { percent = percent, updated = Now() }
        end
    end
end

function RaidLeadTools:RequestDurability(manual)
    if not self:IsEnabled() or self.db.enableDurabilityComm == false then
        return
    end
    self.durability = self.durability or {}
    self:SendDurability()
    local channel = GetCommChannel()
    if channel then
        self:SendCommMessage(COMM_PREFIX, "DREQ", channel)
    end
    if manual then
        C_Timer.After(2, function()
            self:ReportDurability()
        end)
    end
end

function RaidLeadTools:ReportDurability()
    local threshold = tonumber(self.db.durabilityWarnThreshold) or 30
    local low = {}
    for name, info in pairs(self.durability or {}) do
        if info.percent and info.percent <= threshold then
            table.insert(low, string.format("%s %d%%", NormalizeName(name) or name, info.percent))
        end
    end
    table.sort(low)
    if #low == 0 then
        RC:Print(string.format(L["Durability: no RaidControl users below %d%%."], threshold))
    else
        RC:Print(string.format(L["Low durability: %s"], table.concat(low, ", ")))
    end
end

function RaidLeadTools:GetDurabilityForName(name)
    local key = NormalizeName(name) or name
    if not key then
        return nil
    end
    local direct = self.durability and self.durability[key]
    if direct then
        return direct.percent, direct.updated
    end
    for storedName, info in pairs(self.durability or {}) do
        if NormalizeName(storedName) == key then
            return info.percent, info.updated
        end
    end
    return nil
end

function RaidLeadTools:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= COMM_PREFIX or not message then
        return
    end
    local manaPercent, manaDrinking = message:match("^MANA:(%d+):([01])$")
    if manaPercent then
        local name = NormalizeName(sender) or sender
        if name then
            self.healerManaComm = self.healerManaComm or {}
            self.healerManaComm[name] = {
                percent = math.max(0, math.min(100, tonumber(manaPercent) or 0)),
                drinking = manaDrinking == "1",
                updated = Now(),
            }
            self:UpdateHealerManaFrame()
        end
        return
    end
    if self.db.enableDurabilityComm == false then
        return
    end
    if message == "DREQ" then
        C_Timer.After(0.2 + math.random() * 0.8, function()
            self:SendDurability()
        end)
        return
    end
    local percent = message:match("^DURA:(%d+)$")
    if percent then
        local name = NormalizeName(sender) or sender
        self.durability[name] = { percent = tonumber(percent), updated = Now() }
        local readyTracker = RC:GetModule("ReadyTracker", true)
        if readyTracker and readyTracker.UpdateFrame then
            readyTracker:UpdateFrame()
        end
    end
end

function RaidLeadTools:READY_CHECK()
    if self.db.durabilityReadyCheckRequest ~= false then
        self:RequestDurability(false)
        C_Timer.After(3, function()
            self:ReportDurability()
        end)
    else
        self:SendDurability()
    end
end

function RaidLeadTools:GROUP_ROSTER_UPDATE()
    self:UpdateBattleResFrame()
    self:UpdateHealerManaFrame()
end

function RaidLeadTools:PostRaidNote()
    if self.db.enableRaidNotes == false then
        RC:ShowError(L["Raid notes are disabled."])
        return false
    end
    local note = self.db.raidNoteText or ""
    note = note:gsub("^%s+", ""):gsub("%s+$", "")
    if note == "" then
        RC:ShowError(L["Write a raid note in Settings > Raid > Lead Tools first."])
        return false
    end
    local channel = self.db.raidNoteChannel or "RAID_WARNING"
    if channel == "RAID_WARNING" and not IsGroupLeaderOrAssist() then
        channel = RC:GetGroupChannel() or "SAY"
    elseif channel == "GROUP" then
        channel = RC:GetGroupChannel() or "SAY"
    end
    for line in note:gmatch("[^\r\n]+") do
        RC:SendChat(line, channel)
    end
    return true
end
