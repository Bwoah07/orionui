local addonName, addonTable = ...
-- OrionUI's built-in copy of RaidControl (Stig's own addon). It stays off while the standalone
-- RaidControl addon is enabled for this character, so the two never fight over frames,
-- bindings and slash commands. Every other RaidControl file returns early when ns.RC is nil.
do
    local exists = C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist("Raidcontrol")
    if exists and C_AddOns.GetAddOnEnableState("Raidcontrol", UnitName("player")) > 0 then
        return
    end
end
local RC = LibStub("AceAddon-3.0"):NewAddon("OrionUIRaidControl", "AceConsole-3.0", "AceEvent-3.0")
-- Modules reach the addon through the private namespace (ns.RC). The single
-- public global is RaidControl, for key bindings, macros and other addons.
addonTable.RC = RC
_G.RaidControl = RC
local L = LibStub("AceLocale-3.0"):GetLocale("OrionUIRaidControl")
RC.L = L
RC.SUPPORTED_INTERFACE = 120100
do
    -- Shown in the settings sidebar and profile exports.
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, version = pcall(getMetadata or function() return nil end, addonName or "Raidcontrol", "Version")
    RC.version = ok and type(version) == "string" and version or nil
end
RC.SUPPORTED_INTERFACES = {
    [120007] = true,
    [120100] = true,
    [16001] = true, -- WoW Forever beta
}

local function RC_SetPropagateKeyboardInput(frame, propagate)
    if not frame or not frame.SetPropagateKeyboardInput then
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        return
    end

    pcall(frame.SetPropagateKeyboardInput, frame, propagate)
end

function RC:IsSupportedInterface(interfaceVersion)
    return self.SUPPORTED_INTERFACES[tonumber(interfaceVersion)] == true
end

-- =============================================================================
-- CLIENT FLAVOR
-- WoW Forever runs on the mainline client (same UI, API and Midnight addon
-- restrictions) but ships level-60 classic content: no Mythic+ keystones and no
-- modern specializations to rely on. Modules ask here instead of sniffing the
-- build themselves so retail behaviour stays the default.
-- =============================================================================
local FOREVER_INTERFACE_CEILING = 20000

function RC:IsForeverClient()
    if self.isForeverClient ~= nil then
        return self.isForeverClient
    end

    local isForever = false
    if WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE
        and LE_EXPANSION_LEVEL_CURRENT and LE_EXPANSION_CLASSIC then
        isForever = LE_EXPANSION_LEVEL_CURRENT == LE_EXPANSION_CLASSIC
    elseif GetBuildInfo then
        local _, _, _, interfaceVersion = GetBuildInfo()
        interfaceVersion = tonumber(interfaceVersion)
        isForever = interfaceVersion ~= nil and interfaceVersion < FOREVER_INTERFACE_CEILING
            and (not WOW_PROJECT_ID or WOW_PROJECT_ID == WOW_PROJECT_MAINLINE)
    end

    self.isForeverClient = isForever
    return isForever
end

function RC:GetClientLabel()
    return self:IsForeverClient() and "Forever" or "Retail"
end

function RC:SupportsMythicPlus()
    return not self:IsForeverClient()
        and C_MythicPlus ~= nil
        and type(C_MythicPlus.GetOwnedKeystoneChallengeMapID) == "function"
end

-- Returns specID, name, description, icon, role for the player's active
-- specialization, or nil when the client has none (Forever, low level).
function RC:GetPlayerSpecializationInfo()
    local getSpecialization = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
    local getSpecializationInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo
        or GetSpecializationInfo
    if type(getSpecialization) ~= "function" or type(getSpecializationInfo) ~= "function" then
        return nil
    end

    local ok, specIndex = pcall(getSpecialization)
    if not ok or type(specIndex) ~= "number" or specIndex <= 0 then
        return nil
    end

    local infoOK, specID, name, description, icon, role = pcall(getSpecializationInfo, specIndex)
    if not infoOK or type(specID) ~= "number" or specID <= 0 then
        return nil
    end
    return specID, name, description, icon, role
end

-- Inspected specID for another unit, or nil when unknown or unsupported.
function RC:GetInspectSpecID(unit)
    if not unit or type(GetInspectSpecialization) ~= "function" then
        return nil
    end
    local ok, specID = pcall(GetInspectSpecialization, unit)
    if ok and type(specID) == "number" and specID > 0 then
        return specID
    end
    return nil
end

-- =============================================================================
-- KEYBINDING LOCALIZATION (Blizzard Keybinding UI)
-- Single header "RaidControl" with all bindings under it
-- =============================================================================
BINDING_HEADER_RAIDCONTROL = "RaidControl"

BINDING_NAME_RC_TARGET_SKULL = L["Target - Skull"]
BINDING_NAME_RC_TARGET_CROSS = L["Target - Cross"]
BINDING_NAME_RC_TARGET_SQUARE = L["Target - Square"]
BINDING_NAME_RC_TARGET_MOON = L["Target - Moon"]
BINDING_NAME_RC_TARGET_TRIANGLE = L["Target - Triangle"]
BINDING_NAME_RC_TARGET_DIAMOND = L["Target - Diamond"]
BINDING_NAME_RC_TARGET_CIRCLE = L["Target - Circle"]
BINDING_NAME_RC_TARGET_STAR = L["Target - Star"]
BINDING_NAME_RC_TARGET_CLEAR = L["Target - Clear"]

BINDING_NAME_RC_WORLD_SKULL = L["World - Skull at Cursor"]
BINDING_NAME_RC_WORLD_CROSS = L["World - Cross at Cursor"]
BINDING_NAME_RC_WORLD_SQUARE = L["World - Square at Cursor"]
BINDING_NAME_RC_WORLD_MOON = L["World - Moon at Cursor"]
BINDING_NAME_RC_WORLD_TRIANGLE = L["World - Triangle at Cursor"]
BINDING_NAME_RC_WORLD_DIAMOND = L["World - Diamond at Cursor"]
BINDING_NAME_RC_WORLD_CIRCLE = L["World - Circle at Cursor"]
BINDING_NAME_RC_WORLD_STAR = L["World - Star at Cursor"]
BINDING_NAME_RC_WORLD_CLEAR = L["World - Clear All"]

BINDING_NAME_RC_CYCLE_MARKER = L["Utility - Cycle Marker"]
BINDING_NAME_RC_SHUFFLE_WORLD_MARKER = L["Utility - Shuffle World Marker"]
BINDING_NAME_RC_SCREENSHOT_MODE = L["Utility - Max Quality Screenshot"]

_G["BINDING_NAME_CLICK RC_KeybindTarget8:LeftButton"] = L["Target - Skull"]
_G["BINDING_NAME_CLICK RC_KeybindTarget7:LeftButton"] = L["Target - Cross"]
_G["BINDING_NAME_CLICK RC_KeybindTarget6:LeftButton"] = L["Target - Square"]
_G["BINDING_NAME_CLICK RC_KeybindTarget5:LeftButton"] = L["Target - Moon"]
_G["BINDING_NAME_CLICK RC_KeybindTarget4:LeftButton"] = L["Target - Triangle"]
_G["BINDING_NAME_CLICK RC_KeybindTarget3:LeftButton"] = L["Target - Diamond"]
_G["BINDING_NAME_CLICK RC_KeybindTarget2:LeftButton"] = L["Target - Circle"]
_G["BINDING_NAME_CLICK RC_KeybindTarget1:LeftButton"] = L["Target - Star"]
_G["BINDING_NAME_CLICK RC_KeybindTarget0:LeftButton"] = L["Target - Clear"]
_G["BINDING_NAME_CLICK RC_RoleMarkButton:LeftButton"] = L["Utility - Apply Tank and Healer Marks"]

_G["BINDING_NAME_CLICK RC_KeybindWorld8:LeftButton"] = L["World - Skull at Cursor"]
_G["BINDING_NAME_CLICK RC_KeybindWorld7:LeftButton"] = L["World - Cross at Cursor"]
_G["BINDING_NAME_CLICK RC_KeybindWorld6:LeftButton"] = L["World - Square at Cursor"]
_G["BINDING_NAME_CLICK RC_KeybindWorld5:LeftButton"] = L["World - Moon at Cursor"]
_G["BINDING_NAME_CLICK RC_KeybindWorld4:LeftButton"] = L["World - Triangle at Cursor"]
_G["BINDING_NAME_CLICK RC_KeybindWorld3:LeftButton"] = L["World - Diamond at Cursor"]
_G["BINDING_NAME_CLICK RC_KeybindWorld2:LeftButton"] = L["World - Circle at Cursor"]
_G["BINDING_NAME_CLICK RC_KeybindWorld1:LeftButton"] = L["World - Star at Cursor"]
_G["BINDING_NAME_CLICK RC_KeybindWorld0:LeftButton"] = L["World - Clear All"]
_G["BINDING_NAME_CLICK RC_KeybindCycle:LeftButton"] = L["Utility - Cycle Marker"]
_G["BINDING_NAME_CLICK RC_KeybindShuffleWorld:LeftButton"] = L["Utility - Shuffle World Marker"]

-- =============================================================================
-- KEYBINDING SECURE BUTTONS (Midnight API Requirement)
-- =============================================================================
-- Midnight API requires SetRaidTarget/SetRaidMarker to be called via secure path
-- We create hidden SecureActionButtonTemplate buttons that keybindings click

RC.KeybindButtons = {}

local TargetMarkerToWorldMarker = {
    [1] = 5,
    [2] = 6,
    [3] = 3,
    [4] = 2,
    [5] = 7,
    [6] = 1,
    [7] = 4,
    [8] = 8,
}

local function GetWorldMarkerID(targetMarkerID)
    return TargetMarkerToWorldMarker[targetMarkerID] or targetMarkerID
end

local function ConfigureHiddenClickButton(btn)
    btn:SetSize(1, 1)
    btn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -2000, 2000)
    btn:SetAlpha(0)
    btn:EnableMouse(true)
    btn:RegisterForClicks("AnyUp")
    btn:SetAttribute("useOnKeyDown", false)
    btn:Show()
end

local function ConfigureTargetMarkerButton(btn, markerIndex)
    btn:SetAttribute("type", "macro")
    btn:SetAttribute("type1", "macro")
    local macroText = "/tm " .. (markerIndex or 0)
    btn:SetAttribute("macrotext", macroText)
    btn:SetAttribute("macrotext1", macroText)
end

local function ConfigureWorldMarkerButton(btn, markerIndex)
    if markerIndex == 0 then
        local macroText = (_G.SLASH_CLEAR_WORLD_MARKER1 or "/cwm") .. " " .. (_G.ALL or "all")
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("type1", "macro")
        btn:SetAttribute("macrotext", macroText)
        btn:SetAttribute("macrotext1", macroText)
    else
        local worldMarkerID = GetWorldMarkerID(markerIndex)
        btn:SetAttribute("type", "worldmarker")
        btn:SetAttribute("type1", "worldmarker")
        btn:SetAttribute("marker", tostring(worldMarkerID))
        btn:SetAttribute("action", "set")
        btn:SetAttribute("action1", "set")
    end
end

function RC:ConfigureMarkerActionButton(btn, markerIndex, allowTarget, allowWorld, modifier)
    if not btn or (InCombatLockdown and InCombatLockdown()) then
        return false
    end

    modifier = tostring(modifier or "SHIFT"):upper()
    if modifier ~= "CTRL" and modifier ~= "ALT" then
        modifier = "SHIFT"
    end

    local modifierKey = string.lower(modifier)
    for _, key in ipairs({ "shift", "ctrl", "alt" }) do
        btn:SetAttribute(key .. "-type*", nil)
        btn:SetAttribute(key .. "-macrotext1", nil)
        btn:SetAttribute(key .. "-macrotext2", nil)
        btn:SetAttribute(key .. "-marker*", nil)
        btn:SetAttribute(key .. "-action1", nil)
        btn:SetAttribute(key .. "-action2", nil)
    end

    btn:SetAttribute("type*", "macro")
    local targetMarkerSlash = _G.SLASH_TARGET_MARKER1 or "/tm"
    btn:SetAttribute("macrotext1", allowTarget and string.format("%s %d", targetMarkerSlash, markerIndex or 0) or "")
    btn:SetAttribute("macrotext2", allowTarget and (targetMarkerSlash .. " 0") or "")

    if allowWorld then
        local worldMarkerID = GetWorldMarkerID(markerIndex or 0)
        if markerIndex == 0 then
            local clearWorldSlash = _G.SLASH_CLEAR_WORLD_MARKER1 or "/cwm"
            local clearAllMacro = clearWorldSlash .. " " .. (_G.ALL or "all")
            btn:SetAttribute(modifierKey .. "-type*", "macro")
            btn:SetAttribute(modifierKey .. "-macrotext1", clearAllMacro)
            btn:SetAttribute(modifierKey .. "-macrotext2", clearAllMacro)
        else
            btn:SetAttribute(modifierKey .. "-type*", "worldmarker")
            btn:SetAttribute(modifierKey .. "-marker*", tostring(worldMarkerID))
            btn:SetAttribute(modifierKey .. "-action1", "set")
            btn:SetAttribute(modifierKey .. "-action2", "clear")
        end
    end

    btn.worldMarkerModifier = modifier
    return true
end

function RC:CreateKeybindButtons()
    -- Target marker buttons (0-8, where 0 = clear)
    for i = 0, 8 do
        local btn = CreateFrame("Button", "RC_KeybindTarget" .. i, nil, "SecureActionButtonTemplate")
        btn:RegisterForClicks("AnyUp", "AnyDown")
        ConfigureTargetMarkerButton(btn, i)
        RC.KeybindButtons["target" .. i] = btn
    end

    -- World marker buttons (0-8, where 0 = clear all)
    -- Uses native "worldmarker" secure action type — no macrotext needed
    for i = 0, 8 do
        local btn = CreateFrame("Button", "RC_KeybindWorld" .. i, nil, "SecureActionButtonTemplate")
        btn:RegisterForClicks("AnyUp", "AnyDown")
        ConfigureWorldMarkerButton(btn, i)
        RC.KeybindButtons["world" .. i] = btn
    end

    -- =========================================================
    -- CYCLE MARKER LOGIC
    -- A single secure handler that decrements from 8 down to 1.
    -- Target vs World is determined by the modifier check.
    -- =========================================================
    local cycleBtn = CreateFrame("Button", "RC_KeybindCycle", UIParent, "SecureHandlerClickTemplate, SecureActionButtonTemplate")
    ConfigureHiddenClickButton(cycleBtn)
    cycleBtn:SetAttribute("type1", "macro")

    -- Internal state: Start at 8 (Skull)
    cycleBtn:SetAttribute("markIndex", 8)

    if SecureHandlerWrapScript then
        SecureHandlerWrapScript(cycleBtn, "PreClick", cycleBtn, [[
            local idx = self:GetAttribute("markIndex") or 8
            local modReq = self:GetAttribute("worldModifier") or "SHIFT"
            local isWorld = false
            if modReq == "SHIFT" and IsShiftKeyDown() then isWorld = true
            elseif modReq == "CTRL" and IsControlKeyDown() then isWorld = true
            elseif modReq == "ALT" and IsAltKeyDown() then isWorld = true
            end
            if isWorld then
                local worldIdx = idx
                if idx == 1 then worldIdx = 5
                elseif idx == 2 then worldIdx = 6
                elseif idx == 4 then worldIdx = 2
                elseif idx == 5 then worldIdx = 7
                elseif idx == 6 then worldIdx = 1
                elseif idx == 7 then worldIdx = 4
                end
                self:SetAttribute("type1", "macro")
                self:SetAttribute("macrotext1", "/wm [@cursor] " .. worldIdx)
            else
                self:SetAttribute("type1", "macro")
                self:SetAttribute("macrotext1", "/tm [@target,exists] " .. idx)
            end
            idx = idx - 1
            if idx < 1 then idx = 8 end
            self:SetAttribute("markIndex", idx)
        ]])
    else
        cycleBtn:SetAttribute("_onclick", [[
        -- Read current index
        local idx = self:GetAttribute("markIndex") or 8

        -- Read modifier preference from our global config passed in later
        local modReq = self:GetAttribute("worldModifier") or "SHIFT"

        -- Determine if we are placing a World Marker vs Target Marker
        local isWorld = false
        if modReq == "SHIFT" and IsShiftKeyDown() then isWorld = true
        elseif modReq == "CTRL" and IsControlKeyDown() then isWorld = true
        elseif modReq == "ALT" and IsAltKeyDown() then isWorld = true
        end

        if isWorld then
            -- World Marker Secure execution
            local worldIdx = idx
            if idx == 1 then worldIdx = 5
            elseif idx == 2 then worldIdx = 6
            elseif idx == 4 then worldIdx = 2
            elseif idx == 5 then worldIdx = 7
            elseif idx == 6 then worldIdx = 1
            elseif idx == 7 then worldIdx = 4
            end
            self:SetAttribute("type", "macro")
            self:SetAttribute("macrotext", "/wm [@cursor] " .. worldIdx)
        else
            -- Target Marker Secure execution
            self:SetAttribute("type", "macro")
            self:SetAttribute("macrotext", "/tm [@target,exists] " .. idx)
        end

        -- Cycle logic: 8 -> 1 then wrap to 8
        idx = idx - 1
        if idx < 1 then idx = 8 end

        self:SetAttribute("markIndex", idx)
        ]])
    end

    RC.KeybindButtons["cycle"] = cycleBtn

    -- =========================================================
    -- WORLD MARKER SHUFFLE
    -- A dedicated secure in-combat path that places world markers
    -- 8 -> 1 at the current cursor location, one press per marker.
    -- =========================================================
    local shuffleBtn = CreateFrame("Button", "RC_KeybindShuffleWorld", UIParent, "SecureHandlerClickTemplate, SecureActionButtonTemplate")
    ConfigureHiddenClickButton(shuffleBtn)
    shuffleBtn:SetAttribute("type1", "macro")
    shuffleBtn:SetAttribute("macrotext1", string.format("/wm [@cursor] %d", GetWorldMarkerID(8)))
    shuffleBtn:SetAttribute("markIndex", 8)

    if SecureHandlerWrapScript then
        SecureHandlerWrapScript(shuffleBtn, "PreClick", shuffleBtn, [[
            local idx = self:GetAttribute("markIndex") or 8
            local worldIdx = idx
            if idx == 1 then worldIdx = 5
            elseif idx == 2 then worldIdx = 6
            elseif idx == 4 then worldIdx = 2
            elseif idx == 5 then worldIdx = 7
            elseif idx == 6 then worldIdx = 1
            elseif idx == 7 then worldIdx = 4
            end
            self:SetAttribute("type1", "macro")
            self:SetAttribute("macrotext1", "/wm [@cursor] " .. worldIdx)
            idx = idx - 1
            if idx < 1 then idx = 8 end
            self:SetAttribute("markIndex", idx)
        ]])
    else
        shuffleBtn:SetAttribute("_onclick", [[
            local idx = self:GetAttribute("markIndex") or 8
            local worldIdx = idx
            if idx == 1 then worldIdx = 5
            elseif idx == 2 then worldIdx = 6
            elseif idx == 4 then worldIdx = 2
            elseif idx == 5 then worldIdx = 7
            elseif idx == 6 then worldIdx = 1
            elseif idx == 7 then worldIdx = 4
            end
            self:SetAttribute("type", "macro")
            self:SetAttribute("macrotext", "/wm [@cursor] " .. worldIdx)
            idx = idx - 1
            if idx < 1 then idx = 8 end
            self:SetAttribute("markIndex", idx)
        ]])
    end

    RC.KeybindButtons["shuffleWorld"] = shuffleBtn
end

-- =============================================================================
-- KEYBINDING HELPER FUNCTIONS (click secure buttons)
-- =============================================================================

function RCPlaceTargetMarker(index)
    local btn = RC.KeybindButtons["target" .. (index or 0)]
    if btn then
        btn:Click("LeftButton")
    end
end

function RCPlaceWorldMarker(index)
    local btn = RC.KeybindButtons["world" .. (index or 0)]
    if btn then
        btn:Click("LeftButton")
    end
end

function RCClearAllWorldMarkers()
    local btn = RC.KeybindButtons["world0"]
    if btn then
        btn:Click("LeftButton")

        -- Reset marker cycles to Skull.
        RC:ResetTargetCycle()
    end
end

function RCShuffleWorldMarker()
    local btn = RC.KeybindButtons["shuffleWorld"]
    if btn then
        btn:Click("LeftButton")
    end
end

-- Used when "Clear All" is pressed via UI (to reset cycle)
function RC:ResetTargetCycle()
    if InCombatLockdown and InCombatLockdown() then
        return
    end
    if RC.KeybindButtons["cycle"] then
        RC.KeybindButtons["cycle"]:SetAttribute("markIndex", 8)
    end
    if RC.KeybindButtons["shuffleWorld"] then
        RC.KeybindButtons["shuffleWorld"]:SetAttribute("markIndex", 8)
    end
end

local KimiQuotes = {
    "Bwoah.",
    "Leave me alone, I know what I'm doing.",
    "For what?",
    "I'm not here to finish second.",
    "The steering wheel is the same as last year.",
    "We are checking.",
    "Ice cream time.",
    "No, I don't want to.",
    "It's more like a hobby for me.",
    "I was having a shit.",
    "I know what I'm doing.",
    "Don't shout there, ffs.",
    "I don't care what you think.",
    "You will not have the drink.",
    "I don't want to talk about it.",
    "Just leave me alone.",
}

function RC:ShowError(message)
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(message, 1, 0.15, 0.15, 1)
    else
        self:Print(message)
    end
end

function RC:CanManageGroup()
    if not IsInGroup() then
        return false, L["You must be in a group."]
    end

    if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
        return true
    end

    return false, L["You must be the group leader or assistant."]
end

local function CallPartyInfo(method, ...)
    local api = C_PartyInfo and C_PartyInfo[method]
    if type(api) ~= "function" then
        return false, L["The group API is unavailable."]
    end

    local ok, result = pcall(api, ...)
    if not ok then
        return false, result
    end
    return true, result
end

function RC:StartReadyCheck()
    return CallPartyInfo("DoReadyCheck")
end

function RC:ConfirmGroupReadyCheck(isReady)
    return CallPartyInfo("ConfirmReadyCheck", isReady == true)
end

function RC:PromoteGroupAssistant(name)
    if not name or name == "" then
        return false, L["A player name is required."]
    end
    return CallPartyInfo("PromoteToAssistant", name, true)
end

function RC:DemoteGroupAssistant(name)
    if not name or name == "" then
        return false, L["A player name is required."]
    end
    return CallPartyInfo("DemoteAssistant", name, true)
end

function RC:UninviteGroupMember(name, reason)
    if not name or name == "" then
        return false, L["A player name is required."]
    end
    return CallPartyInfo("UninviteUnit", name, reason, true)
end

function RC:InviteGroupMember(name)
    if not name or name == "" then
        return false, L["A player name is required."]
    end
    return CallPartyInfo("InviteUnit", name)
end

function RC:SendChat(message, chatType, languageID, target)
    local api = C_ChatInfo and C_ChatInfo.SendChatMessage
    if type(api) ~= "function" then
        return false, L["The chat API is unavailable."]
    end

    local ok, result = pcall(api, message, chatType, languageID, target)
    if not ok then
        return false, result
    end
    return true, result
end

function RC:GetGroupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
    return nil
end

local RC_BUFF_PROVIDER_RULES = {
    { name = "Bloodlust", classes = { "SHAMAN", "MAGE", "EVOKER", "HUNTER" } },
    { name = "Battle Res", classes = { "DRUID", "WARLOCK", "DEATHKNIGHT", "PALADIN" } },
    { name = "Chaos Brand", classes = { "DEMONHUNTER" } },
    { name = "Mystic Touch", classes = { "MONK" } },
    { name = "Skyfury", classes = { "SHAMAN" } },
    { name = "Blessing of the Bronze", classes = { "EVOKER" } },
    { name = "Attack Power", classes = { "WARRIOR" } },
    { name = "Intellect", classes = { "MAGE" } },
    { name = "Versatility", classes = { "PALADIN" } },
    { name = "Fortitude", classes = { "PRIEST" } },
    { name = "Mark of the Wild", classes = { "DRUID" } },
}

local RC_PERSONAL_CORE_AURA_RULES = {
    ["Attack Power"] = { "battle shout" },
    ["Intellect"] = { "arcane intellect" },
    ["Versatility"] = { "devotion aura", "blessing of seasons" },
    ["Fortitude"] = { "power word: fortitude" },
    ["Mark of the Wild"] = { "mark of the wild" },
}

local MAX_HELPFUL_AURAS = 40

local function ValueIsAccessible(value)
    if value == nil then
        return true
    end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        if ok and secret then
            return false
        end
    end
    if canaccessvalue then
        local ok, accessible = pcall(canaccessvalue, value)
        if ok and accessible == false then
            return false
        end
    end
    return true
end

local function SafeLowerText(value)
    if value == nil or not ValueIsAccessible(value) then
        return ""
    end

    local ok, text = pcall(tostring, value)
    if not ok or not text or text == "nil" then
        return ""
    end

    return string.lower(text)
end

local function SafeNumber(value)
    if not ValueIsAccessible(value) then
        return nil
    end
    local ok, numberValue = pcall(tonumber, value)
    if ok then
        return numberValue
    end
    return nil
end

local function SafeIcon(value, fallback)
    if not ValueIsAccessible(value) then
        return fallback
    end
    local ok, valueType = pcall(type, value)
    if ok and (valueType == "number" or valueType == "string") then
        return value
    end
    return fallback
end

local function ReadPackedAura(aura)
    if not ValueIsAccessible(aura) then
        return nil, nil, nil, false
    end
    local okType, auraType = pcall(type, aura)
    if not okType or auraType ~= "table" then
        return nil, nil, nil, false
    end
    local ok, name, icon, spellID = pcall(function()
        return aura.name, aura.icon, aura.spellId
    end)
    local nameAccessible = name ~= nil and ValueIsAccessible(name)
    local spellIDAccessible = spellID ~= nil and ValueIsAccessible(spellID)
    if not ok or (not nameAccessible and not spellIDAccessible) then
        return nil, nil, nil, false
    end
    return name, icon, spellID, true
end

local function ForEachHelpfulAura(unit, callback)
    if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
        for index = 1, MAX_HELPFUL_AURAS do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HELPFUL")
            if not ok or not ValueIsAccessible(aura) then
                return false
            end
            if aura == nil then
                return true
            end
            local name, icon, spellID, accessible = ReadPackedAura(aura)
            if not accessible then
                return false
            end
            if callback(name, icon, spellID) then
                return true
            end
        end
        return true
    end

    if not (AuraUtil and type(AuraUtil.ForEachAura) == "function") then
        return false
    end

    local accessible = true
    local ok = pcall(AuraUtil.ForEachAura, unit, "HELPFUL", nil, function(first, ...)
        if not ValueIsAccessible(first) then
            accessible = false
            return true
        end

        local name, icon, spellID
        local okType, firstType = pcall(type, first)
        if okType and firstType == "table" then
            name, icon, spellID, accessible = ReadPackedAura(first)
            if not accessible then
                return true
            end
        else
            local values = { ... }
            name, icon, spellID = first, values[1], values[9]
            local nameAccessible = name ~= nil and ValueIsAccessible(name)
            local spellIDAccessible = spellID ~= nil and ValueIsAccessible(spellID)
            if not nameAccessible and not spellIDAccessible then
                accessible = false
                return true
            end
        end
        return callback(name, icon, spellID)
    end, true)
    return ok and accessible
end

function RC:GetCoreBuffRules()
    return RC_BUFF_PROVIDER_RULES
end

function RC:GetGroupUnits()
    local units = {}
    if IsInRaid and IsInRaid() then
        local members = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, members do
            table.insert(units, "raid" .. i)
        end
    elseif IsInGroup and IsInGroup() then
        table.insert(units, "player")
        local members = GetNumGroupMembers and GetNumGroupMembers() or 1
        for i = 1, math.max((members or 1) - 1, 0) do
            table.insert(units, "party" .. i)
        end
    else
        table.insert(units, "player")
    end
    return units
end

function RC:ScanUnitBuffStatus(unit)
    local data = {
        accessible = false,
        food = false,
        flask = false,
        rune = false,
        weaponMain = false,
        weaponOff = false,
        shamanEnchant = false,
    }

    if not unit or (UnitExists and not UnitExists(unit)) then
        return data
    end

    data.accessible = ForEachHelpfulAura(unit, function(name, icon, spellID)
        local spellName = SafeLowerText(name)
        local auraIcon = SafeIcon(icon, nil)
        local auraSpellID = SafeNumber(spellID)

        if string.find(spellName, "well fed") or string.find(spellName, "feast") then
            data.food = auraIcon or 134062
        end
        if string.find(spellName, "flask") or string.find(spellName, "phial") or string.find(spellName, "elixir") then
            data.flask = auraIcon or 132805
        end
        if string.find(spellName, "augmentation") or string.find(spellName, "draconic augment") or string.find(spellName, "rune") then
            data.rune = auraIcon or 134419
        end
        if string.find(spellName, "sharpening stone") or string.find(spellName, "weightstone") or string.find(spellName, "oil") or string.find(spellName, "coating") or string.find(spellName, "imbue") or string.find(spellName, "windfury") or string.find(spellName, "flametongue") or string.find(spellName, "frostbrand") or string.find(spellName, "rockbiter") then
            data.weaponMain = auraIcon or 135129
        end
        if auraSpellID == 33757 or auraSpellID == 318038 or auraSpellID == 318040 or auraSpellID == 318039 or auraSpellID == 318041 or auraSpellID == 318035 then
            data.shamanEnchant = auraIcon or 135129
        end
    end)

    return data
end

function RC:ScanPersonalCoreBuffStatus(unit, buffName)
    local needles = RC_PERSONAL_CORE_AURA_RULES[buffName]
    if not needles then
        return nil
    end

    if not unit or (UnitExists and not UnitExists(unit)) then
        return false
    end

    local foundName
    local accessible = ForEachHelpfulAura(unit, function(name)
        local spellName = SafeLowerText(name)
        for _, needle in ipairs(needles) do
            if string.find(spellName, needle, 1, true) then
                foundName = spellName
                return true
            end
        end
    end)
    if not accessible then
        return nil, "unavailable"
    end

    if foundName then
        return true, foundName
    end
    return false
end

function RC:BuildBuffSnapshot()
    local snapshot = {
        total = 0,
        available = 0,
        unavailable = {},
        food = 0,
        flask = 0,
        rune = 0,
        weapon = 0,
        missingFood = {},
        missingFlask = {},
        missingRune = {},
        missingWeapon = {},
        missingSynergy = {},
        classes = {},
    }

    for _, unit in ipairs(self:GetGroupUnits()) do
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            local name = GetUnitName(unit, true) or UnitName(unit) or unit
            local _, classFile = UnitClass(unit)
            if classFile then
                snapshot.classes[classFile] = true
            end

            local data = self:ScanUnitBuffStatus(unit)
            snapshot.total = snapshot.total + 1
            if data.accessible == false then
                table.insert(snapshot.unavailable, name)
            else
                snapshot.available = snapshot.available + 1
                if data.food then snapshot.food = snapshot.food + 1 else table.insert(snapshot.missingFood, name) end
                if data.flask then snapshot.flask = snapshot.flask + 1 else table.insert(snapshot.missingFlask, name) end
                if data.rune then snapshot.rune = snapshot.rune + 1 else table.insert(snapshot.missingRune, name) end
                if data.weaponMain or data.weaponOff or data.shamanEnchant then
                    snapshot.weapon = snapshot.weapon + 1
                else
                    table.insert(snapshot.missingWeapon, name)
                end
            end
        end
    end

    for _, rule in ipairs(RC_BUFF_PROVIDER_RULES) do
        local found = false
        for _, classFile in ipairs(rule.classes) do
            if snapshot.classes[classFile] then
                found = true
                break
            end
        end
        if not found then
            table.insert(snapshot.missingSynergy, rule.name)
        end
    end

    return snapshot
end

function RC:FormatBuffSnapshot(snapshot)
    snapshot = snapshot or self:BuildBuffSnapshot()
    local total = math.max(snapshot.total or 0, 0)
    if total == 0 then
        return L["No live group units"], 1, 0.35, 0.35
    end

    local available = math.max(snapshot.available == nil and total or snapshot.available, 0)
    if available == 0 then
        return L["Consumable data unavailable"], 0.65, 0.65, 0.65
    end

    local text = string.format(L["Food %d/%d  Flask %d/%d  Rune %d/%d  Weap %d/%d"],
        snapshot.food or 0, available,
        snapshot.flask or 0, available,
        snapshot.rune or 0, available,
        snapshot.weapon or 0, available)
    if available < total then
        text = text .. "  " .. string.format(L["Data %d unavailable"], total - available)
    end
    local allConsumables = snapshot.food == available and snapshot.flask == available and snapshot.rune == available and snapshot.weapon == available
    local allSynergy = #(snapshot.missingSynergy or {}) == 0
    if allConsumables and allSynergy and available == total then
        return text, 0.35, 1, 0.35
    end
    return text, 1, 0.78, 0.25
end

local function TrimRaidContextText(value)
    if value == nil then
        return ""
    end
    return tostring(value):match("^%s*(.-)%s*$") or ""
end

local function NormalizeRaidContextText(value)
    local text = TrimRaidContextText(value)
    if text == "" then
        return nil
    end
    if Ambiguate then
        local short = Ambiguate(text, "short")
        if short and short ~= "" then
            text = short
        end
    end
    text = text:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    if text == "" then
        return nil
    end
    return text
end

function RC:BuildRaidContextKey(prefix, id, name, fallback)
    local numericID = tonumber(id)
    if numericID and numericID > 0 then
        return tostring(prefix or "key") .. ":" .. tostring(numericID)
    end
    local normalized = NormalizeRaidContextText(name) or NormalizeRaidContextText(fallback) or "unassigned"
    return tostring(prefix or "key") .. ":" .. normalized
end

function RC:BuildLegacyBossKey(encounterID, bossName)
    local id = tonumber(encounterID)
    if id and id > 0 then
        return "encounter:" .. tostring(id)
    end
    return self:BuildRaidContextKey("boss", nil, bossName, "unassigned")
end

function RC:OnRaidContextEncounterStart(_, encounterID, encounterName, difficultyID)
    self.CurrentEncounterID = tonumber(encounterID)
    self.CurrentEncounterName = encounterName
    self.CurrentEncounterDifficultyID = tonumber(difficultyID)
end

function RC:OnRaidContextEncounterEnd()
    self.CurrentEncounterID = nil
    self.CurrentEncounterName = nil
    self.CurrentEncounterDifficultyID = nil
end

function RC:GetRaidContext(options)
    options = type(options) == "table" and options or {}

    local instanceName, instanceType, difficultyID, difficultyName, _, _, _, instanceMapID
    if GetInstanceInfo then
        instanceName, instanceType, difficultyID, difficultyName, _, _, _, instanceMapID = GetInstanceInfo()
    end

    local mapID
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, value = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then
            mapID = value
        end
    end

    local journalInstanceID
    if EJ_GetInstanceForMap and instanceMapID then
        local ok, value = pcall(EJ_GetInstanceForMap, instanceMapID)
        if ok then
            journalInstanceID = value
        end
    end

    local manualRaidName = TrimRaidContextText(options.manualRaidName or options.raidName)
    local manualBossName = TrimRaidContextText(options.manualBossName or options.bossName)
    local raidName = manualRaidName ~= "" and manualRaidName or TrimRaidContextText(instanceName)
    if raidName == "" and GetRealZoneText then
        raidName = TrimRaidContextText(GetRealZoneText())
    end
    if raidName == "" then
        raidName = "Unassigned Raid"
    end

    local encounterID = tonumber(options.encounterID or self.CurrentEncounterID)
    local encounterName = TrimRaidContextText(options.encounterName or self.CurrentEncounterName)
    local bossName = manualBossName ~= "" and manualBossName or encounterName
    if bossName == "" then
        bossName = "Unassigned"
    end

    local activeDifficultyID = tonumber(options.difficultyID or self.CurrentEncounterDifficultyID or difficultyID)
    local activeDifficultyName = TrimRaidContextText(options.difficultyName or difficultyName)
    if activeDifficultyName == "" then
        activeDifficultyName = "Any Difficulty"
    end

    local groupSize = GetNumGroupMembers and GetNumGroupMembers() or 0
    local raidSize = groupSize
    if IsInRaid and IsInRaid() and GetNumGroupMembers then
        raidSize = GetNumGroupMembers()
    end

    local raidKey = self:BuildRaidContextKey("raid", journalInstanceID or instanceMapID or mapID, raidName, "unassigned")
    local difficultyKey = self:BuildRaidContextKey("difficulty", activeDifficultyID, activeDifficultyName, "any")
    local bossKey
    if encounterID and encounterID > 0 then
        bossKey = "boss:encounter:" .. tostring(encounterID)
    else
        bossKey = raidKey .. ":boss:" .. (NormalizeRaidContextText(bossName) or "unassigned")
    end

    return {
        raidName = raidName,
        raidKey = raidKey,
        bossName = bossName,
        bossKey = bossKey,
        legacyBossKey = self:BuildLegacyBossKey(encounterID, bossName),
        difficultyID = activeDifficultyID,
        difficultyName = activeDifficultyName,
        difficultyKey = difficultyKey,
        encounterID = encounterID,
        encounterName = encounterName ~= "" and encounterName or nil,
        instanceName = instanceName,
        instanceType = instanceType,
        instanceMapID = tonumber(instanceMapID),
        mapID = tonumber(mapID),
        journalInstanceID = tonumber(journalInstanceID),
        groupSize = tonumber(groupSize) or 0,
        raidSize = tonumber(raidSize) or 0,
        inGroup = IsInGroup and IsInGroup() or false,
        inRaid = IsInRaid and IsInRaid() or false,
        source = manualBossName ~= "" and "manual" or ((encounterID and encounterID > 0) and "encounter" or (manualRaidName ~= "" and "manual" or "instance")),
    }
end

function RC:OnInitialize()
    -- 1. Register Slash Commands
    SLASH_RL1 = "/rl"
    SlashCmdList["RL"] = ReloadUI

    SLASH_BWOAH1 = "/bwoah"
    SlashCmdList["BWOAH"] = function()
        local quote = KimiQuotes[math.random(#KimiQuotes)]
        RC:SendChat(quote, "SAY")
    end

    -- Split saved tank audio choices before AceDB fills in the new defaults.
    -- Migrate every saved profile, including profiles that are not active today.
    local savedProfiles = _G.OrionUIRaidControlDB and _G.OrionUIRaidControlDB.profiles
    if type(savedProfiles) == "table" then
        for _, profile in pairs(savedProfiles) do
            if type(profile) == "table" and not profile.tankAssistPresentationMigration then
                for _, category in ipairs({ "Taunt", "Defensive", "Movement" }) do
                    local prefix = "tankAssist" .. category
                    if profile[prefix .. "Sound"] == nil then
                        profile[prefix .. "Sound"] = profile.tankAssistSound or "voicepack"
                    end
                    if profile[prefix .. "CustomSoundFile"] == nil then
                        profile[prefix .. "CustomSoundFile"] = profile.tankAssistCustomSoundFile or ""
                    end
                    if profile[prefix .. "SoundChannel"] == nil then
                        profile[prefix .. "SoundChannel"] = "inherit"
                    end
                end
                if profile.tankAssistShowVisual == false and profile.tankAssistShowTimerBars == nil then
                    profile.tankAssistShowTimerBars = false
                end
                profile.tankAssistPresentationMigration = true
            end
        end
    end

    -- 2. Load DB and Modules
    self.db = LibStub("AceDB-3.0"):New("OrionUIRaidControlDB", {
        profile = {
            minimap = { hide = false },
            pos = { point = "TOPLEFT", x = 0, y = 0 },
            alpha = 1,
            scale = 1.3, -- Legacy launcher scale key
            launcherScale = 1.3,
            topBarScale = 1.3,
            menuScale = 1.3,
            fontName = "RaidControl",
            workspaceScale = 1.0,
            settingsScale = 1.0,
            raidSplitScale = 1.0,
            bossNotesManagerScale = 1.0,
            raidSplitPos = { "CENTER", "UIParent", "CENTER", 0, 0 },
            raidSplitTooltipName = true,
            raidSplitTooltipLevel = true,
            raidSplitTooltipRole = true,
            raidSplitTooltipSpec = true,
            pullTimerDuration = 10,
            hideMarkers = false,
            showDropdownMarkers = true,
            showActionStripMarkers = true,
            hideRoles = false,
            enableTargetMarkers = true,                                -- Click to place target marker
            enableWorldMarkers = true,                                 -- Shift-click to place world marker (group only)
            enableShiftWorldMarkers = true,                            -- Enable shift+click for world markers
            worldMarkerModifier = "SHIFT",                             -- Modifier used by marker rows to place flares
            lockFrames = true,                                         -- Layout mode is the only movement state
            pullTimerAddon = "auto",                                   -- "auto", "bigwigs", "dbm", "ert", or "none"
            -- Text color settings (RGB 0-1)
            titleTextColor = { r = 1, g = 1, b = 1 },                  -- White
            buttonTextColor = { r = 1, g = 1, b = 1 },                 -- White
            generalTextColor = { r = 1, g = 1, b = 1 },                -- White
            borderColor = { r = 0.105, g = 0.145, b = 0.170, a = 0.82 },
            backgroundColor = { r = 0.050, g = 0.070, b = 0.090, a = 0.98 },
            headerColor = { r = 0.035, g = 0.052, b = 0.068, a = 0.98 },
            surfaceColor = { r = 0.061, g = 0.095, b = 0.120, a = 0.62 },
            controlColor = { r = 0.075, g = 0.113, b = 0.141, a = 0.90 },
            accentColor = { r = 12 / 255, g = 210 / 255, b = 157 / 255, a = 1 },
            useClassColor = false,
            hideTopBar = false,
            hideMenu = false,
            hideLauncherWhenSolo = false,
            hideBlizzardRaidControl = true,
            -- Control button visibility
            showPullButton = true,
            showReadyButton = true,
            showConvertButton = true,
            showDifficultyButton = true,
            showInviteButton = true,
            showClearButton = false,
            showDisbandButton = true,
            showScreenshotButton = true,
            screenshotRenderScale = 2,
            screenshotSizePreset = "3840x2160",
            screenshotSizeOverride = "3840x2160",
            screenshotFormat = "jpg",
            screenshotQuality = 10,
            screenshotApplyMaxGraphics = true,
            screenshotHideUI = true,
            screenshotDelay = 1,
            screenshotConfirmHighQuality = true,
            guildInviteRankVisibility = {}, -- Rank filter toggles for the dropdown Inv button
            theme = "Starforge",
            -- Action Strip
            showActionStrip = false,
            actionStripPos = { "TOP", "UIParent", "TOP", 0, -50 },
            lockActionStrip = true,
            actionStripShowReady = true,
            actionStripShowPull = true,
            actionStripShowConvert = true,
            actionStripShowDifficulty = true,
            actionStripShowInvite = true,
            actionStripShowClearTarget = false,
            actionStripShowClearWorld = false,
            actionStripShowDisband = true,
            actionStripShowScreenshot = true,
            actionStripLayout = "single",
            actionStripMarkerPosition = "first",
            actionStripScale = 1,
            actionStripButtonWidth = 54,
            actionStripButtonHeight = 22,
            actionStripMarkerSize = 24,
            -- Smart Split Settings
            smartSplitMonk = true,        -- Optimize for Melee (Monk)
            smartSplitDH = true,          -- Optimize for Casters (DH)
            smartSplitHealers = 0,        -- 0 = Auto, 1-5 = Fixed per group
            smartSplitTanks = 0,          -- 0 = Auto, 1-2 = Fixed per group
            smartSplitBalanceDPS = false, -- Balance DPS using Details! meter
            smartSplitKeepSelfG1 = false, -- Keep player in Group 1
            smartSplitTwoWayOddEven = true, -- 2-way split uses 1/3/5/7 vs 2/4/6/8 groups
            raidSplitGuildRankVisibility = {}, -- Rank filter toggles for Guild Import panel
            raidSplitBossLayouts = {}, -- Boss key -> savedLayouts name for RaidSplit Layout Manager
            -- AutoAssist
            enableAutoAssist = false,
            enableAutoMainTanks = false,
            autoAssistOfficers = true,
            autoAssistMinRank = 1, -- Min guild rank to auto-promote (1 = GM, 2 = next rank, etc.)
            autoAssistRankName = nil, -- Specific guild rank name for auto-promote
            autoAssistList = "", -- Comma-separated list of names
            -- RaidSplit Layouts
            savedLayouts = {}, -- Saved RaidSplit layouts; legacy and schema=2 boss layout records
            -- AutoInvite
            enableAutoInvite = false,
            autoInviteKeyword = "inv",
            inviteRestriction = "Anyone",
            -- CombatLogger
            enableCombatLogger = true,
            combatLogPrompt = true,
            combatLogDecisions = {},
            logRaid = true,
            logParty = true,
            logArena = true,
            logBG = false,
            -- AutoVendor
            enableAutoRepair = false,
            useGuildRepair = false,
            enableAutoSellJunk = false,
            -- SynergyAnalyzer
            enableSynergyAnalyzer = true,
            -- KeySync
            enableKeySync = true,
            -- RaidLeadTools
            enableRaidLeadTools = true,
            enableBattleResTracker = true,
            showBattleResFrame = true,
            battleResShowIcon = true,
            battleResShowLabel = false,
            battleResShowCount = true,
            battleResShowMax = false,
            battleResShowTimer = true,
            battleResTimerFormat = "mmss",
            battleResShowCooldownSwipe = true,
            battleResShowRecent = false,
            battleResRecentCount = 4,
            battleResRecentDuration = 45,
            battleResStyle = "compact",
            battleResLabel = "Battle Res",
            battleResIcon = "auto",
            battleResIconSize = 30,
            battleResFontSize = 13,
            battleResTimerFontSize = 12,
            battleResWidth = 170,
            battleResPadding = 7,
            battleResGap = 7,
            battleResBackgroundAlpha = 0.88,
            battleResBorderAlpha = 0.18,
            battleResShowRechargeBar = true,
            battleResRechargeBarHeight = 3,
            battleResReadyColor = { r = 0.25, g = 0.90, b = 0.45, a = 1 },
            battleResRechargeColor = { r = 1.00, g = 0.72, b = 0.20, a = 1 },
            battleResEmptyColor = { r = 1.00, g = 0.28, b = 0.22, a = 1 },
            battleResTimerColor = { r = 0.78, g = 0.88, b = 1.00, a = 1 },
            battleResScale = 1,
            battleResAlpha = 1,
            showHealerManaFrame = true,
            healerManaVisibility = "group",
            healerManaEnableInRaid = true,
            healerManaEnableInDungeons = true,
            healerManaOnlyIfPlayerIsHealer = false,
            healerManaMaxHealers = 6,
            healerManaScale = 1,
            healerManaAlpha = 1,
            healerManaNameFontSize = 15,
            healerManaManaFontSize = 30,
            healerManaFontSize = 15,
            healerManaLowThreshold = 30,
            healerManaShowSolo = false,
            healerManaStyle = "compact",
            healerManaTitle = "Healer Mana",
            healerManaShowTitle = false,
            healerManaShowBackground = false,
            healerManaShowBars = false,
            healerManaShowStateTags = true,
            healerManaShowDrinking = true,
            healerManaStatusSound = "none",
            healerManaClassColorNames = true,
            healerManaShowSpecIcon = true,
            healerManaWidth = 220,
            healerManaFrameWidth = 220,
            healerManaIconSize = 48,
            healerManaRowSpacing = 6,
            healerManaGrowDirection = "DOWN",
            healerManaNameYOffset = 3,
            healerManaManaYOffset = 4,
            healerManaPadding = 2,
            healerManaAvoidTopUI = true,
            healerManaBackgroundAlpha = 0,
            healerManaBorderAlpha = 0.16,
            healerManaRowAlpha = 0.28,
            healerManaBarAlpha = 0.82,
            healerManaBarHeight = 5,
            healerManaManaColor = { r = 0.28, g = 0.64, b = 1.00, a = 1 },
            healerManaLowColor = { r = 1.00, g = 0.30, b = 0.24, a = 1 },
            healerManaDrinkingColor = { r = 0.20, g = 0.90, b = 0.64, a = 1 },
            healerManaUpdateInterval = 1,
            healerManaUseFrameFallback = true,
            enableWhoPulled = true,
            whoPulledChatPrint = true,
            enableRaidNotes = true,
            raidNoteText = "",
            raidNoteChannel = "RAID_WARNING",
            bossNotes = {
                version = 1,
                notes = {},
                bossIndex = {},
                notesById = {},
                noteOrder = {},
                autoLoadEncounter = true,
                autoLoadTarget = true,
                autoLoadMouseover = true,
                autoAdvanceAfterKill = true,
                selectedNote = nil,
                activeNoteId = nil,
                lastRaidKey = nil,
                lastBossKey = nil,
                lastDifficultyKey = nil,
                viewer = {
                    shown = false,
                    locked = true,
                    style = "text",
                    scale = 1,
                    alpha = 1,
                    backgroundAlpha = 0.82,
                    borderAlpha = 0.22,
                    timerAlertBorder = true,
                    fontSize = 11,
                    width = 320,
                    height = 220,
                    left = nil,
                    top = nil,
                },
            },
            enableNoteReminders = true,
            noteRemindersAutoLoad = true,
            noteRemindersUsePersonal = true,
            noteRemindersShowAllShared = false,
            noteRemindersShowBars = true,
            noteRemindersShowIcons = true,
            noteRemindersShowNameplates = true,
            noteRemindersLocked = true,
            noteReminderTTS = true,
            noteReminderSound = "raidwarning",
            noteReminderSoundChannel = "Master",
            noteReminderTtsVolume = 100,
            noteReminderLeadTime = 5,
            noteReminderMaxVisible = 4,
            noteReminderScale = 1,
            noteReminderWidth = 360,
            noteReminderRowHeight = 42,
            noteReminderIconSize = 36,
            noteReminderAlpha = 1,
            noteReminderBackgroundAlpha = 0.94,
            noteReminderPos = { "CENTER", "UIParent", "CENTER", 0, 160 },
            noteReminderNameplateSize = 38,
            noteReminderNameplateOffsetX = 0,
            noteReminderNameplateOffsetY = 4,
            noteReminderNameplateShowLabel = true,
            nsrtShareOnReadyCheck = false,
            enableDurabilityComm = true,
            durabilityReadyCheckRequest = true,
            durabilityWarnThreshold = 30,
            autoConvertKeywordInvites = false,
            -- TankAssist
            enableTankAssist = true,
            tankAssistCoTankName = "",
            tankAssistSound = "voicepack",
            tankAssistSoundChannel = "Master",
            tankAssistCustomSoundFile = "",
            tankAssistSoundEnabled = true,
            tankAssistTauntEnabled = true,
            tankAssistDefensiveEnabled = true,
            tankAssistMovementEnabled = true,
            tankAssistTauntSound = "voicepack",
            tankAssistDefensiveSound = "ready",
            tankAssistMovementSound = "tts",
            tankAssistTauntCustomSoundFile = "",
            tankAssistDefensiveCustomSoundFile = "",
            tankAssistMovementCustomSoundFile = "",
            tankAssistTauntSoundChannel = "inherit",
            tankAssistDefensiveSoundChannel = "inherit",
            tankAssistMovementSoundChannel = "inherit",
            tankAssistTauntCountdownEnabled = true,
            tankAssistDefensiveCountdownEnabled = true,
            tankAssistMovementCountdownEnabled = true,
            tankAssistTauntCountdownSeconds = 3,
            tankAssistDefensiveCountdownSeconds = 3,
            tankAssistMovementCountdownSeconds = 3,
            tankAssistTtsVolume = 100,
            tankAssistAlertIcon = "skull",
            tankAssistSelectedBoss = "nekzali",
            tankAssistBossOverrides = {},
            tankAssistAlertCooldown = 6,
            tankAssistDefensiveLeadSeconds = 3,
            tankAssistMovementLeadSeconds = 8,
            tankAssistEnableDungeonBusters = true,
            tankAssistVisualDuration = 2.5,
            tankAssistShowVisual = true,
            tankAssistDisplayStyle = "panel",
            tankAssistAlertWidth = 420,
            tankAssistAlertFontSize = 28,
            tankAssistDetailFontSize = 14,
            tankAssistShowIcon = true,
            tankAssistShowDetail = true,
            tankAssistShowTimer = true,
            tankAssistTextAlign = "LEFT",
            tankAssistBackgroundAlpha = 0.88,
            tankAssistTauntColor = { r = 1, g = 0.35, b = 0.2 },
            tankAssistDefensiveColor = { r = 1, g = 0.75, b = 0.2 },
            tankAssistMovementColor = { r = 0.2, g = 0.8, b = 1 },
            tankAssistShowTimerBars = true,
            tankAssistTimerTaunt = true,
            tankAssistTimerDefensive = true,
            tankAssistTimerMovement = true,
            tankAssistTimerWidth = 360,
            tankAssistTimerHeight = 34,
            tankAssistTimerFontSize = 15,
            tankAssistTimerMaxBars = 3,
            tankAssistTimerHorizon = 30,
            tankAssistTimerGrowth = "DOWN",
            tankAssistTimerSpacing = 5,
            tankAssistTimerBackgroundAlpha = 0.65,
            tankAssistTimerShowIcon = true,
            tankAssistTimerShowLabel = true,
            tankAssistTimerShowSeconds = true,
            tankAssistTimerPos = { "CENTER", "UIParent", "CENTER", 0, 55 },
            tankAssistShowStatus = false,
            tankAssistFramesLocked = true,
            tankAssistFrameScale = 1,
            tankAssistFrameAlpha = 1,
            tankAssistAlertPos = { "CENTER", "UIParent", "CENTER", 0, 150 },
            tankAssistStatusPos = { "CENTER", "UIParent", "CENTER", 0, 84 },
            tankAssistTanksOnly = true,
            tankAssistEncounterOnly = true,
            tankAssistUseAuraRules = true,
            tankAssistUseCastRules = true,
            tankAssistSmartPolarity = true,
            tankAssistAnnounceRule = false,
            -- Midnight role marking uses a prepared secure click and automatic verification.
            autoMarkTanks = true,
            autoMarkTanksIcon = 6, -- Square
            autoMarkHealers = true,
            autoMarkHealersIcon = 2, -- Circle
            autoMarkRolesDungeonOnly = true,
            autoMarkRoleButtonScale = 1,
            autoMarkRoleButtonPos = { "TOP", "UIParent", "TOP", 0, -180 },
            autoMarkRolePromptDismissed = false,

            -- Cycle Keybinds
            cycleMarkerModifier = "SHIFT",

            -- ConsumableChecker
            enableConsumableChecker = true,
            whisperSlackers = false,
            reportToChat = false,
            -- Ready Check Tracker
            enableReadyTracker = true,
            announceReadySlackers = false,
            useCustomReadyCheck = true, -- Use our pretty frame instead of Blizzard's
            readyTrackerMissingOnly = false,
            readyTrackerWhisperMissing = true,
            readyTrackerScale = 1,
            readyTrackerAlpha = 1,
            readyTrackerAutoCloseSeconds = 8,
        },
        global = {
            blockedActionLog = {},
        },
    }, "Default")

    if not self.db.profile.blizzardRaidControlVisibilitySettingMigration then
        self.db.profile.hideBlizzardRaidControl = true
        self.db.profile.blizzardRaidControlVisibilitySettingMigration = true
    end

    if not self.db.profile.tankAssistMidnightS2Migration then
        self.db.profile.enableTankAssist = true
        self.db.profile.tankAssistSelectedBoss = "nekzali"
        self.db.profile.tankAssistMidnightS2Migration = true
    end

    -- Automatic Main Tank assignment is no longer safe on the Midnight client:
    -- SetPartyAssignment can raise ADDON_ACTION_FORBIDDEN without a hardware
    -- click. Retire the old option for existing profiles as well as new ones.
    if not self.db.profile.mainTankAutomationRetiredMigration then
        self.db.profile.enableAutoMainTanks = false
        self.db.profile.mainTankAutomationRetiredMigration = true
    end

    if not self.db.profile.overrideBindingRetiredMigration then
        self.db.profile.cycleMarkerKey = nil
        self.db.profile.overrideBindingRetiredMigration = true
    end

    -- Migrate legacy bundled-font names to the public release font entry.
    if self.db.profile.fontName == "RaidControl Font" or self.db.profile.fontName == "Bwoah" then
        self.db.profile.fontName = "RaidControl"
    end

    -- MIGRATION: Force old "GoldText" defaults to pure white
    local function isOldGold(c)
        if not c then return false end
        return c.r == 1 and (c.g > 0.81 and c.g < 0.83) and c.b == 0
    end
    if isOldGold(self.db.profile.titleTextColor) then self.db.profile.titleTextColor = { r = 1, g = 1, b = 1 } end
    if isOldGold(self.db.profile.buttonTextColor) then self.db.profile.buttonTextColor = { r = 1, g = 1, b = 1 } end
    if isOldGold(self.db.profile.generalTextColor) then self.db.profile.generalTextColor = { r = 1, g = 1, b = 1 } end

    -- MIGRATION: retire the gold/condensed visual generation completely. This
    -- runs once so existing installs receive the same clean baseline as fresh
    -- profiles while future user color edits remain untouched.
    if not self.db.profile.cleanInterfaceMigration then
        self.db.profile.theme = "Starforge"
        self.db.profile.fontName = "RaidControl"
        self.db.profile.borderColor = { r = 1, g = 1, b = 1, a = 0.05 }
        self.db.profile.backgroundColor = { r = 0.050, g = 0.070, b = 0.090, a = 0.98 }
        self.db.profile.headerColor = { r = 0.035, g = 0.052, b = 0.068, a = 0.98 }
        self.db.profile.surfaceColor = { r = 0.061, g = 0.095, b = 0.120, a = 0.62 }
        self.db.profile.controlColor = { r = 0.075, g = 0.113, b = 0.141, a = 0.90 }
        self.db.profile.accentColor = { r = 12 / 255, g = 210 / 255, b = 157 / 255, a = 1 }
        self.db.profile.useClassColor = false
        self.db.profile.cleanInterfaceMigration = true
    end

    -- MIGRATION: tighten the old translucent grey default into the current matte RaidControl profile.
    local bg = self.db.profile.backgroundColor
    if bg and math.abs((bg.r or 0) - 0.1) < 0.01 and math.abs((bg.g or 0) - 0.1) < 0.01 and math.abs((bg.b or 0) - 0.1) < 0.01 then
        self.db.profile.backgroundColor = { r = 0.055, g = 0.055, b = 0.055, a = 0.92 }
    end

    -- MIGRATION: 1.7.42 briefly treated layout choices as color presets and
    -- could overwrite the user's palette. Remove only those exact generated
    -- palettes; layout switching is geometry-only from this point forward.
    if not self.db.profile.layoutPaletteMigration then
        local accent = self.db.profile.accentColor
        local generatedAccents = {
            { 12 / 255, 210 / 255, 157 / 255 },
            { 120 / 255, 65 / 255, 200 / 255 },
            { 63 / 255, 167 / 255, 1 },
            { 1, 90 / 255, 31 / 255 },
        }
        local generatedPalette = false
        if accent then
            for _, color in ipairs(generatedAccents) do
                if math.abs((accent.r or 0) - color[1]) < 0.002
                    and math.abs((accent.g or 0) - color[2]) < 0.002
                    and math.abs((accent.b or 0) - color[3]) < 0.002 then
                    generatedPalette = true
                    break
                end
            end
        end
        if generatedPalette then
            self.db.profile.backgroundColor = { r = 0.055, g = 0.055, b = 0.055, a = 0.92 }
            self.db.profile.borderColor = { r = 0, g = 0, b = 0, a = 1 }
            self.db.profile.accentColor = { r = 0.10, g = 0.78, b = 0.66, a = 1 }
        end
        self.db.profile.layoutPaletteMigration = true
    end

    -- MIGRATION: lift the original near-black defaults into the lighter,
    -- translucent surface system. Exact custom colors are left untouched.
    if not self.db.profile.translucentSurfaceMigration then
        local oldBg = self.db.profile.backgroundColor
        if oldBg
            and math.abs((oldBg.r or 0) - 0.055) < 0.002
            and math.abs((oldBg.g or 0) - 0.055) < 0.002
            and math.abs((oldBg.b or 0) - 0.055) < 0.002 then
            self.db.profile.backgroundColor = { r = 0.11, g = 0.11, b = 0.11, a = 0.78 }
        end
        local oldBorder = self.db.profile.borderColor
        if oldBorder
            and (oldBorder.r or 0) == 0
            and (oldBorder.g or 0) == 0
            and (oldBorder.b or 0) == 0 then
            self.db.profile.borderColor = { r = 0.22, g = 0.22, b = 0.22, a = 0.72 }
        end
        self.db.profile.translucentSurfaceMigration = true
    end

    -- MIGRATION: replace the washed translucent-grey defaults from 1.7.44
    -- with the solid slate panel design. Exact custom palettes are preserved.
    if not self.db.profile.solidSlateSurfaceMigration then
        local bgColor = self.db.profile.backgroundColor
        if bgColor
            and math.abs((bgColor.r or 0) - 0.11) < 0.002
            and math.abs((bgColor.g or 0) - 0.11) < 0.002
            and math.abs((bgColor.b or 0) - 0.11) < 0.002 then
            self.db.profile.backgroundColor = { r = 0.045, g = 0.065, b = 0.082, a = 0.98 }
        end
        local headerColor = self.db.profile.headerColor
        if headerColor
            and math.abs((headerColor.r or 0) - 0.14) < 0.002
            and math.abs((headerColor.g or 0) - 0.14) < 0.002
            and math.abs((headerColor.b or 0) - 0.14) < 0.002 then
            self.db.profile.headerColor = { r = 0.065, g = 0.090, b = 0.110, a = 0.98 }
        end
        local surfaceColor = self.db.profile.surfaceColor
        if surfaceColor
            and math.abs((surfaceColor.r or 0) - 0.16) < 0.002
            and math.abs((surfaceColor.g or 0) - 0.16) < 0.002
            and math.abs((surfaceColor.b or 0) - 0.16) < 0.002 then
            self.db.profile.surfaceColor = { r = 0.075, g = 0.105, b = 0.130, a = 0.94 }
        end
        local controlColor = self.db.profile.controlColor
        if controlColor
            and math.abs((controlColor.r or 0) - 0.18) < 0.002
            and math.abs((controlColor.g or 0) - 0.18) < 0.002
            and math.abs((controlColor.b or 0) - 0.18) < 0.002 then
            self.db.profile.controlColor = { r = 0.090, g = 0.130, b = 0.160, a = 0.98 }
        end
        local borderColor = self.db.profile.borderColor
        if borderColor
            and math.abs((borderColor.r or 0) - 0.22) < 0.002
            and math.abs((borderColor.g or 0) - 0.22) < 0.002
            and math.abs((borderColor.b or 0) - 0.22) < 0.002 then
            self.db.profile.borderColor = { r = 0.34, g = 0.40, b = 0.44, a = 0.55 }
        end
        self.db.profile.solidSlateSurfaceMigration = true
    end

    -- MIGRATION: move the exact solid-slate defaults to a tinted-black,
    -- slightly translucent palette. User-customized colors remain untouched.
    if not self.db.profile.tintedBlackSurfaceMigration then
        local bgColor = self.db.profile.backgroundColor
        if bgColor
            and math.abs((bgColor.r or 0) - 0.045) < 0.002
            and math.abs((bgColor.g or 0) - 0.065) < 0.002
            and math.abs((bgColor.b or 0) - 0.082) < 0.002 then
            self.db.profile.backgroundColor = { r = 0.012, g = 0.020, b = 0.028, a = 0.88 }
        end
        local headerColor = self.db.profile.headerColor
        if headerColor
            and math.abs((headerColor.r or 0) - 0.065) < 0.002
            and math.abs((headerColor.g or 0) - 0.090) < 0.002
            and math.abs((headerColor.b or 0) - 0.110) < 0.002 then
            self.db.profile.headerColor = { r = 0.020, g = 0.032, b = 0.043, a = 0.92 }
        end
        local surfaceColor = self.db.profile.surfaceColor
        if surfaceColor
            and math.abs((surfaceColor.r or 0) - 0.075) < 0.002
            and math.abs((surfaceColor.g or 0) - 0.105) < 0.002
            and math.abs((surfaceColor.b or 0) - 0.130) < 0.002 then
            self.db.profile.surfaceColor = { r = 0.030, g = 0.046, b = 0.058, a = 0.84 }
        end
        local controlColor = self.db.profile.controlColor
        if controlColor
            and math.abs((controlColor.r or 0) - 0.090) < 0.002
            and math.abs((controlColor.g or 0) - 0.130) < 0.002
            and math.abs((controlColor.b or 0) - 0.160) < 0.002 then
            self.db.profile.controlColor = { r = 0.045, g = 0.068, b = 0.082, a = 0.90 }
        end
        local borderColor = self.db.profile.borderColor
        if borderColor
            and math.abs((borderColor.r or 0) - 0.34) < 0.002
            and math.abs((borderColor.g or 0) - 0.40) < 0.002
            and math.abs((borderColor.b or 0) - 0.44) < 0.002 then
            self.db.profile.borderColor = { r = 0.22, g = 0.28, b = 0.32, a = 0.48 }
        end
        self.db.profile.tintedBlackSurfaceMigration = true
    end

    -- MIGRATION: move the previous tinted-black defaults to the unified
    -- Starforge-inspired blue-charcoal system. Only exact shipped colors move;
    -- user-customized palettes remain untouched.
    if not self.db.profile.refinedSurfaceMigration then
        local bgColor = self.db.profile.backgroundColor
        if bgColor
            and math.abs((bgColor.r or 0) - 0.012) < 0.002
            and math.abs((bgColor.g or 0) - 0.020) < 0.002
            and math.abs((bgColor.b or 0) - 0.028) < 0.002 then
            self.db.profile.backgroundColor = { r = 0.050, g = 0.070, b = 0.090, a = 0.98 }
        end
        local headerColor = self.db.profile.headerColor
        if headerColor
            and math.abs((headerColor.r or 0) - 0.020) < 0.002
            and math.abs((headerColor.g or 0) - 0.032) < 0.002
            and math.abs((headerColor.b or 0) - 0.043) < 0.002 then
            self.db.profile.headerColor = { r = 0.035, g = 0.052, b = 0.068, a = 0.98 }
        end
        local surfaceColor = self.db.profile.surfaceColor
        if surfaceColor
            and math.abs((surfaceColor.r or 0) - 0.030) < 0.002
            and math.abs((surfaceColor.g or 0) - 0.046) < 0.002
            and math.abs((surfaceColor.b or 0) - 0.058) < 0.002 then
            self.db.profile.surfaceColor = { r = 0.061, g = 0.095, b = 0.120, a = 0.62 }
        end
        local controlColor = self.db.profile.controlColor
        if controlColor
            and math.abs((controlColor.r or 0) - 0.045) < 0.002
            and math.abs((controlColor.g or 0) - 0.068) < 0.002
            and math.abs((controlColor.b or 0) - 0.082) < 0.002 then
            self.db.profile.controlColor = { r = 0.075, g = 0.113, b = 0.141, a = 0.90 }
        end
        local borderColor = self.db.profile.borderColor
        if borderColor
            and math.abs((borderColor.r or 0) - 0.22) < 0.002
            and math.abs((borderColor.g or 0) - 0.28) < 0.002
            and math.abs((borderColor.b or 0) - 0.32) < 0.002 then
            self.db.profile.borderColor = { r = 1, g = 1, b = 1, a = 0.08 }
        end
        self.db.profile.refinedSurfaceMigration = true
    end

    -- Replace only the shipped translucent-white border values. Deliberate
    -- custom colors, including opaque white, remain untouched.
    if not self.db.profile.subtleNeutralBorderMigration then
        local borderColor = self.db.profile.borderColor
        if borderColor
            and (borderColor.r or 0) > 0.98
            and (borderColor.g or 0) > 0.98
            and (borderColor.b or 0) > 0.98
            and (borderColor.a or 0) <= 0.20 then
            self.db.profile.borderColor = { r = 0.105, g = 0.145, b = 0.170, a = 0.82 }
        end
        self.db.profile.subtleNeutralBorderMigration = true
    end

    -- Fresh profiles already have separate audio defaults. Keep deliberate TTS,
    -- custom-file, and silent selections intact across subsequent logins.
    self.db.profile.tankAssistPresentationMigration = true

    -- World-marker modifier clicks are part of the marker feature itself.
    -- Older profiles could silently disable them with a redundant legacy flag.
    self.db.profile.enableShiftWorldMarkers = true

    -- Migrate the old combined launcher scale into independent tab and menu scales.
    local legacyLauncherScale = tonumber(self.db.profile.launcherScale)
        or tonumber(self.db.profile.scale)
        or 1
    if self.db.profile.topBarScale == nil then
        self.db.profile.topBarScale = legacyLauncherScale
    end
    if self.db.profile.menuScale == nil then
        self.db.profile.menuScale = legacyLauncherScale
    end
    self.db.profile.topBarScale = math.max(0.5, math.min(2, tonumber(self.db.profile.topBarScale) or legacyLauncherScale))
    self.db.profile.menuScale = math.max(0.5, math.min(2, tonumber(self.db.profile.menuScale) or legacyLauncherScale))
    self.db.profile.launcherScale = self.db.profile.topBarScale
    self.db.profile.scale = self.db.profile.topBarScale

    -- Settings, Raid Split, and Boss Notes are one tabbed workspace and must
    -- always retain the same apparent footprint when switching between them.
    local workspaceScale = tonumber(self.db.profile.workspaceScale)
        or tonumber(self.db.profile.settingsScale)
        or tonumber(self.db.profile.raidSplitScale)
        or 1.0
    if not self.db.profile.unifiedWorkspaceChromeMigration then
        if math.abs(workspaceScale - 1.3) < 0.001 then
            workspaceScale = 1.0
        end
        self.db.profile.unifiedWorkspaceChromeMigration = true
    end
    workspaceScale = math.max(0.50, math.min(2.00, workspaceScale))
    self.db.profile.workspaceScale = workspaceScale
    self.db.profile.settingsScale = workspaceScale
    self.db.profile.raidSplitScale = workspaceScale
    self.db.profile.bossNotesManagerScale = workspaceScale

    -- Normalize the shared layout locks once. The Boss Notes viewer keeps its
    -- own independent lock because it also supports viewer-only editing.
    if not self.db.profile.layoutModeExclusiveLockMigration then
        self.db.profile.lockFrames = true
        self.db.profile.lockActionStrip = true
        self.db.profile.noteRemindersLocked = true
        self.db.profile.tankAssistFramesLocked = true
        self.db.profile.layoutModeExclusiveLockMigration = true
    end

    if not self.db.profile.healerManaPortraitRowsMigration then
        self.db.profile.healerManaStyle = "compact"
        self.db.profile.healerManaNameFontSize = 15
        self.db.profile.healerManaManaFontSize = 30
        self.db.profile.healerManaFontSize = 15
        self.db.profile.healerManaShowTitle = false
        self.db.profile.healerManaShowBackground = false
        self.db.profile.healerManaShowBars = false
        self.db.profile.healerManaShowStateTags = false
        self.db.profile.healerManaWidth = 190
        self.db.profile.healerManaFrameWidth = 190
        self.db.profile.healerManaIconSize = 48
        self.db.profile.healerManaPadding = 0
        self.db.profile.healerManaBackgroundAlpha = 0
        self.db.profile.healerManaPortraitRowsMigration = true
    end

    if not self.db.profile.healerManaStatusAlertsMigration then
        self.db.profile.healerManaShowStateTags = true
        self.db.profile.healerManaStatusSound = self.db.profile.healerManaStatusSound or "none"
        self.db.profile.healerManaStatusAlertsMigration = true
    end

    -- Give the large portrait percentages enough room and keep the display
    -- clear of Midnight's top utility buttons. Preserve larger custom values.
    if not self.db.profile.healerManaReadableLayoutMigration then
        if (tonumber(self.db.profile.healerManaFrameWidth) or 190) <= 190 then
            self.db.profile.healerManaFrameWidth = 220
            self.db.profile.healerManaWidth = 220
        end
        if (tonumber(self.db.profile.healerManaRowSpacing) or 2) <= 2 then
            self.db.profile.healerManaRowSpacing = 6
        end
        if (tonumber(self.db.profile.healerManaPadding) or 0) <= 0 then
            self.db.profile.healerManaPadding = 2
        end
        self.db.profile.healerManaAvoidTopUI = self.db.profile.healerManaAvoidTopUI ~= false
        self.db.profile.healerManaReadableLayoutMigration = true
    end

    if self.db.profile.battleResIcon == "Interface\\Icons\\Spell_Nature_Reincarnation" then
        self.db.profile.battleResIcon = "auto"
    end

    -- OrionUI: RaidControl's accent is OrionUI blue. Runs once per profile after the
    -- palette migrations above, so a colour the user picks later is kept.
    if not self.db.profile.orionBlueMigration then
        local blue = addonTable.Theme and addonTable.Theme.BRAND
        if blue then
            self.db.profile.accentColor = { r = blue.r, g = blue.g, b = blue.b, a = 1 }
            self.db.profile.useClassColor = false
        end
        self.db.profile.orionBlueMigration = true
    end

    if self.ApplyTheme then
        self:ApplyTheme(self.db.profile.theme or "Starforge", false)
    end

    self:RegisterChatCommand("rc", function(input)
        input = strtrim(input or "")
        local command, rest = input:match("^(%S*)%s*(.-)$")
        command = string.lower(command or "")
        rest = rest or ""
        local lower = string.lower(input)

        if command == "help" or command == "?" then
            self:PrintSlashHelp()
            return
        elseif command == "pull" then
            local control = self:GetModule("Control", true)
            if not control then
                self:Print(L["Pull timer is not available."])
            elseif rest == "0" or string.lower(rest) == "cancel" then
                control:EndPull()
            else
                control:BeginPull(tonumber(rest) or self.db.profile.pullTimerDuration)
            end
            return
        elseif lower == "reset" then
            if InCombatLockdown and InCombatLockdown() then
                self:Print(L["The launcher can't be moved in combat. Try again after the fight."])
                return
            end
            self.db.profile.pos = { point = "CENTER", x = 0, y = 0 }
            self.db.profile.scale = 1
            self.db.profile.launcherScale = 1
            self.db.profile.topBarScale = 1
            self.db.profile.menuScale = 1
            self.db.profile.alpha = 1
            if self.TopBar then
                self.TopBar:ClearAllPoints()
                self.TopBar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                self.TopBar:SetScale(1)
                self.TopBar:SetAlpha(1)
                self:SetTopBarSuppressed(false)
            end
            if self.Menu then
                self.Menu:SetScale(1)
                self.Menu:SetAlpha(1)
            end
            self:Print(L["Launcher reset to the centre of the screen (scale 1.0, opacity 100%)."])
            return
        elseif lower == "layout" then
            local layoutMode = self:GetModule("LayoutMode", true)
            if layoutMode and layoutMode.Toggle then
                layoutMode:Toggle()
            end
            return
        elseif lower == "demo" or lower == "demo on" or lower == "demo off" then
            local raidDemo = self:GetModule("RaidDemo", true)
            if raidDemo then
                if lower == "demo on" then
                    raidDemo:SetActive(true)
                elseif lower == "demo off" then
                    raidDemo:SetActive(false)
                else
                    raidDemo:Toggle()
                end
            end
            return
        elseif lower == "unlock" then
            local layoutMode = self:GetModule("LayoutMode", true)
            if layoutMode and layoutMode.SetActive then
                layoutMode:SetActive(true)
            end
            return
        elseif lower == "lock" then
            local layoutMode = self:GetModule("LayoutMode", true)
            if layoutMode then
                if layoutMode:IsActive() then
                    layoutMode:SetActive(false)
                elseif layoutMode.SetAllFrameLocks then
                    layoutMode:SetAllFrameLocks(true)
                    self:Print(L["All RaidControl UI elements locked."])
                end
            end
            return
        elseif lower == "strip" then
            self.db.profile.showActionStrip = not self.db.profile.showActionStrip
            local ActionStrip = self:GetModule("ActionStrip", true)
            if ActionStrip and ActionStrip.UpdateVisibility then
                ActionStrip:UpdateVisibility()
                self:Print(self.db.profile.showActionStrip and L["Action Strip is now VISIBLE."] or L["Action Strip is now HIDDEN."])
            end
            return
        elseif lower == "split" then
            local RaidSplit = self:GetModule("RaidSplit", true)
            if RaidSplit then RaidSplit:Toggle() end
            return
        elseif lower == "screenshot" or lower == "ss" or lower == "photo" then
            local ScreenshotModule = self:GetModule("Screenshot", true)
            if ScreenshotModule and ScreenshotModule.Take then
                ScreenshotModule:Take()
            else
                self:Print(L["Screenshot module is not available."])
            end
            return
        elseif lower == "layouts" then
            local RaidSplit = self:GetModule("RaidSplit", true)
            if RaidSplit and RaidSplit.ListLayouts then RaidSplit:ListLayouts() end
            return
        elseif lower == "bres" or lower == "battle" then
            local leadTools = self:GetModule("RaidLeadTools", true)
            if leadTools and leadTools.ReportBattleRes then leadTools:ReportBattleRes() end
            return
        elseif lower == "pulled" or lower == "whopulled" then
            local leadTools = self:GetModule("RaidLeadTools", true)
            if leadTools and leadTools.ReportWhoPulled then leadTools:ReportWhoPulled(true) end
            return
        elseif lower == "version" then
            local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
                or GetAddOnMetadata and GetAddOnMetadata("Raidcontrol", "Version")
                or L["unknown"]
            local clientVersion, build, _, interfaceVersion = GetBuildInfo()
            local support = self:IsSupportedInterface(interfaceVersion) and L["supported"] or L["untested"]
            self:Print(string.format(
                L["RaidControl %s | WoW %s %s (%s) | interface %s (%s)"],
                tostring(version),
                self:GetClientLabel(),
                tostring(clientVersion or L["unknown"]),
                tostring(build or L["unknown"]),
                tostring(interfaceVersion or L["unknown"]),
                support
            ))
            return
        elseif lower == "markerstatus" or lower == "markers" then
            local profile = self.db.profile
            local modifier = tostring(profile.worldMarkerModifier or "SHIFT"):upper()
            local button = _G.RC_MarkerBtn8
            local keybindButton = _G.RC_KeybindWorld8
            local prefix = string.lower(modifier) .. "-"
            local leftMacro = button and button:GetAttribute("macrotext1")
            local rightMacro = button and button:GetAttribute("macrotext2")
            local modifierMacro = button and button:GetAttribute(prefix .. "macrotext1")
            local modifierRightMacro = button and button:GetAttribute(prefix .. "macrotext2")
            local keybindMacro = keybindButton and keybindButton:GetAttribute("macrotext")
            self:Print(string.format(
                "Marker status: world=%s, modifier=%s, leader=%s, assist=%s, combat=%s.",
                profile.enableWorldMarkers ~= false and "ON" or "OFF",
                modifier,
                UnitIsGroupLeader("player") and "YES" or "NO",
                UnitIsGroupAssistant("player") and "YES" or "NO",
                InCombatLockdown and InCombatLockdown() and "YES" or "NO"
            ))
            self:Print("Skull left: " .. tostring(leftMacro or "NONE"))
            self:Print("Skull right: " .. tostring(rightMacro or "NONE"))
            self:Print("Skull modifier left: " .. tostring(modifierMacro or "NONE"))
            self:Print("Skull modifier right: " .. tostring(modifierRightMacro or "NONE"))
            self:Print("Skull keybind: " .. tostring(keybindMacro or "NONE"))
            return
        elseif lower == "durability" or lower == "dura" then
            local leadTools = self:GetModule("RaidLeadTools", true)
            if leadTools and leadTools.RequestDurability then leadTools:RequestDurability(true) end
            return
        elseif lower == "note" or lower:sub(1, 5) == "note " then
            local bossNotes = self:GetModule("BossNotes", true)
            if bossNotes and bossNotes.HandleViewerSlashCommand then
                bossNotes:HandleViewerSlashCommand(strtrim(input:sub(5) or ""))
            else
                self:Print(L["Boss notes are not available."])
            end
            return
        elseif lower == "notes" or lower == "bossnotes" then
            local bossNotes = self:GetModule("BossNotes", true)
            if bossNotes and bossNotes.Open then
                bossNotes:Open()
            else
                self:Print(L["Boss notes are not available."])
            end
            return
        elseif command == "save" or command == "load" then
            local name = strtrim(rest)
            if name ~= "" then
                local RaidSplit = self:GetModule("RaidSplit", true)
                if RaidSplit and command == "save" then
                    RaidSplit:SaveLayout(name)
                elseif RaidSplit then
                    RaidSplit:LoadLayout(name)
                end
            else
                self:Printf(L["Usage: /rc %s <layout name>"], command)
            end
            return
        elseif input ~= "" and command ~= "settings" and command ~= "config" and command ~= "options" then
            self:Printf(L["Unknown command '%s'. Type |cff00b3ff/rc help|r for the list."], input)
            return
        end

        local Settings = self:GetModule("Settings")
        if Settings and Settings.Open then Settings:Open() end
    end)
    self:RegisterChatCommand("raidcontrol", function()
        local Settings = self:GetModule("Settings")
        if Settings and Settings.Open then Settings:Open() end
    end)

    self:CreateTopBar()
    self:CreateMenu()

    self:ApplyInterfaceVisibility()

    self:CreateKeybindButtons()
    self:UpdateCycleKeybinds()
    -- Minimal login message
    self:Print(L["RaidControl loaded. Type |cff00b3ff/rc|r for settings."])
end

-- Keep the secure cycle button's modifier current. Key assignment is owned by
-- WoW's normal CLICK binding entry in Bindings.xml; addon-driven override
-- binding mutations can raise ADDON_ACTION_FORBIDDEN during reload.
local SLASH_HELP_LINES = {
    { "/rc", L["Open settings"] },
    { "/rc help", L["Show this list"] },
    { "/rc pull [seconds]", L["Start the pull timer (/rc pull 0 cancels it)"] },
    { "/rc layout", L["Toggle Edit Mode for every RaidControl frame"] },
    { "/rc unlock | lock", L["Unlock or lock every RaidControl frame"] },
    { "/rc reset", L["Move the launcher back to the centre of the screen"] },
    { "/rc strip", L["Show or hide the action strip"] },
    { "/rc notes", L["Open Boss Notes"] },
    { "/rc split", L["Open Raid Split"] },
    { "/rc save | load <name>", L["Save or load a Raid Split layout"] },
    { "/rc layouts", L["List saved Raid Split layouts"] },
    { "/rcorion", L["Import an Orion raid plan into Raid Split"] },
    { "/rc bres", L["Report battle res charges"] },
    { "/rc pulled", L["Report who pulled the last boss"] },
    { "/rc durability", L["Request durability from RaidControl users"] },
    { "/rc screenshot", L["Take a max-quality screenshot"] },
    { "/rc demo", L["Toggle the preview raid"] },
    { "/rc version", L["Show the addon and client version"] },
}

function RC:PrintSlashHelp()
    self:Print(L["Commands:"])
    for _, line in ipairs(SLASH_HELP_LINES) do
        print(string.format("  |cff00b3ff%s|r  %s", line[1], line[2]))
    end
end

function RC:UpdateCycleKeybinds()
    if InCombatLockdown and InCombatLockdown() then
        self.CycleKeybindRefreshPending = true
        return false
    end
    if RC.KeybindButtons["cycle"] then
        RC.KeybindButtons["cycle"]:SetAttribute("worldModifier", self.db.profile.cycleMarkerModifier or "SHIFT")
    end
    self.CycleKeybindRefreshPending = nil
    return true
end

-- Keep Escape handling entirely on addon-owned frames. UISpecialFrames is read
-- from protected Blizzard paths and must not be modified by RaidControl.
RC.escapeFrames = {}
RC.escapeFrameSerial = 0

local function IsEscapeFrameShown(frame)
    if not frame or frame.rcWorkspaceHosted or type(frame.IsShown) ~= "function" then
        return false
    end
    local ok, shown = pcall(frame.IsShown, frame)
    return ok and shown == true
end

function RC:MarkEscapeFrameShown(frame)
    if not frame then
        return
    end
    self.escapeFrameSerial = (self.escapeFrameSerial or 0) + 1
    frame.rcEscapeShownOrder = self.escapeFrameSerial
end

function RC:CloseTopEscapeFrame()
    local selected
    local selectedOrder = -1
    for _, frame in ipairs(self.escapeFrames or {}) do
        if IsEscapeFrameShown(frame) then
            local order = tonumber(frame.rcEscapeShownOrder or frame.rcEscapeRegisteredOrder) or 0
            if order >= selectedOrder then
                selected = frame
                selectedOrder = order
            end
        end
    end

    if selected then
        if type(selected.rcEscapeHandler) == "function" then
            local ok, handled = pcall(selected.rcEscapeHandler, selected)
            if ok and handled then
                return true
            end
        end
        if type(selected.Hide) == "function" then
            local ok = pcall(selected.Hide, selected)
            if ok then
                return true
            end
        end
    end

    if self.IsMenuOpen then
        self:CloseMenu()
        return true
    end
    return false
end

function RC:EnsureEscapeDispatcher()
    if self.EscapeDispatcher or not CreateFrame or not UIParent then
        return self.EscapeDispatcher
    end

    local dispatcher = CreateFrame("Frame", "RC_EscapeDispatcher", UIParent)
    dispatcher:EnableKeyboard(true)
    RC_SetPropagateKeyboardInput(dispatcher, true)
    dispatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- PLAYER_REGEN_DISABLED fires just before lockdown: make sure a swallowed
    -- Escape can never leave every key blocked for the whole fight.
    dispatcher:RegisterEvent("PLAYER_REGEN_DISABLED")
    dispatcher:SetScript("OnEvent", function(frame)
        RC_SetPropagateKeyboardInput(frame, true)
    end)
    dispatcher:SetScript("OnKeyDown", function(frame, key)
        local handled = key == "ESCAPE" and RC:CloseTopEscapeFrame() or false
        RC_SetPropagateKeyboardInput(frame, not handled)
        if handled and C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                RC_SetPropagateKeyboardInput(frame, true)
            end)
        end
    end)
    dispatcher:SetScript("OnKeyUp", function(frame)
        RC_SetPropagateKeyboardInput(frame, true)
    end)
    dispatcher:Show()
    self.EscapeDispatcher = dispatcher
    return dispatcher
end

function RC:RegisterEscapeFrame(frame, handler)
    if not frame then
        return
    end
    if type(handler) == "function" then
        frame.rcEscapeHandler = handler
    end
    if not frame.rcEscapeRegistered then
        frame.rcEscapeRegistered = true
        self.escapeFrameSerial = (self.escapeFrameSerial or 0) + 1
        frame.rcEscapeRegisteredOrder = self.escapeFrameSerial
        table.insert(self.escapeFrames, frame)
        if type(frame.HookScript) == "function" then
            frame:HookScript("OnShow", function(owner)
                RC:MarkEscapeFrameShown(owner)
            end)
        end
        if IsEscapeFrameShown(frame) then
            self:MarkEscapeFrameShown(frame)
        end
    end
    self:EnsureEscapeDispatcher()
end

-- Close all registered frames and the launcher menu during addon-owned cleanup.
function RC:CloseAllPanels()
    for _, frame in ipairs(self.escapeFrames or {}) do
        if IsEscapeFrameShown(frame) and type(frame.Hide) == "function" then
            pcall(frame.Hide, frame)
        end
    end
    if self.IsMenuOpen then
        self:CloseMenu()
    end
end

function RC:IsUILayoutUnlocked()
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    local layoutMode = self:GetModule("LayoutMode", true)
    return layoutMode and layoutMode.IsActive and layoutMode:IsActive() or false
end

function RC:RefreshLauncherInteractionState()
    local topBar = self.TopBar
    if not topBar or not self.Config then
        return
    end

    local active = self.IsMenuOpen or topBar.rcHovered or self:IsUILayoutUnlocked()
    self:RefreshLauncherSurface(topBar, active)

    if active then
        topBar:SetBackdropBorderColor(self.Config.Accent.r, self.Config.Accent.g, self.Config.Accent.b, 0.38)
    else
        topBar:SetBackdropBorderColor(self:GetControlBorderColor(0.12))
    end
end

function RC:SaveTopBarPosition()
    local topBar = self.TopBar
    if not topBar or not self.db or not self.db.profile then
        return
    end
    local point, _, relativePoint, x, y = topBar:GetPoint(1)
    if point and relativePoint and type(x) == "number" and type(y) == "number" then
        self.db.profile.pos = {
            point = point,
            relativePoint = relativePoint,
            x = x,
            y = y,
        }
    end
end

function RC:ApplyTopBarScale(rawScale)
    local scale = math.max(0.5, math.min(2, tonumber(rawScale) or 1))
    self.db.profile.topBarScale = scale
    self.db.profile.launcherScale = scale
    self.db.profile.scale = scale
    -- The launcher is a secure frame; resizing it in combat is blocked, so the
    -- saved value is applied when combat ends.
    if InCombatLockdown and InCombatLockdown() then
        self.LauncherScalePending = true
        return scale
    end
    if self.TopBar then
        self:SetScalePreserveCenter(self.TopBar, scale, function()
            self:SaveTopBarPosition()
        end)
    end
    if self.Menu then
        self:AnchorMenuToTopBar()
    end
    return scale
end

local function RC_FrameShownSafe(frame)
    if not frame or type(frame.IsShown) ~= "function" then
        return nil
    end
    local ok, shown = pcall(frame.IsShown, frame)
    if not ok or not ValueIsAccessible(shown) or type(shown) ~= "boolean" then
        return nil
    end
    return shown
end

function RC:CanApplyLauncherVisibility()
    if type(InCombatLockdown) == "function" then
        local ok, inCombat = pcall(InCombatLockdown)
        if not ok or not ValueIsAccessible(inCombat) or inCombat == true then
            return false
        end
    end
    if UIParent and type(UIParent.IsShown) == "function" then
        return RC_FrameShownSafe(UIParent) == true
    end
    return true
end

function RC:IsLauncherHiddenWhileSolo()
    local profile = self.db and self.db.profile
    if not profile or profile.hideLauncherWhenSolo ~= true then
        return false
    end
    if self.IsUILayoutUnlocked and self:IsUILayoutUnlocked() then
        return false
    end
    if type(IsInGroup) ~= "function" then
        return false
    end
    local ok, grouped = pcall(IsInGroup)
    if not ok or not ValueIsAccessible(grouped) or type(grouped) ~= "boolean" then
        return false
    end
    return grouped == false
end

function RC:ApplyLauncherVisibilityNow()
    if not self:CanApplyLauncherVisibility() then
        self.LauncherVisibilityPending = true
        return false
    end

    local menuShown
    if self.Menu then
        menuShown = RC_FrameShownSafe(self.Menu)
    end
    local topBarShown
    if self.TopBar then
        topBarShown = RC_FrameShownSafe(self.TopBar)
    end
    if (self.Menu and menuShown == nil) or (self.TopBar and topBarShown == nil) then
        self.LauncherVisibilityPending = true
        return false
    end

    self.LauncherVisibilityPending = nil
    local hiddenWhileSolo = self:IsLauncherHiddenWhileSolo()
    if self.Menu and not self.MenuAnimationState then
        pcall(self.Menu.SetAttribute, self.Menu, "rcOpen", self.IsMenuOpen == true)
        if self.IsMenuOpen and not hiddenWhileSolo and menuShown == false then
            pcall(self.Menu.Show, self.Menu)
        elseif (not self.IsMenuOpen or hiddenWhileSolo) and menuShown == true then
            pcall(self.Menu.Hide, self.Menu)
        end
    end

    if self.TopBar then
        local hiddenBySetting = (self.db and self.db.profile and self.db.profile.hideTopBar) or hiddenWhileSolo
        local menuDisabled = (self.db and self.db.profile and self.db.profile.hideMenu) or hiddenWhileSolo
        pcall(self.TopBar.SetAttribute, self.TopBar, "rcEnabled", not hiddenBySetting)
        pcall(self.TopBar.SetAttribute, self.TopBar, "rcMenuEnabled", not menuDisabled)
        pcall(self.TopBar.SetAttribute, self.TopBar, "rcMenuOpen", self.IsMenuOpen == true)
        local shouldShow = not hiddenBySetting and not self.TopBarSuppressed
        if shouldShow then
            pcall(self.TopBar.SetAlpha, self.TopBar, self.db.profile.alpha or 1)
            if topBarShown == false then
                pcall(self.TopBar.Show, self.TopBar)
            end
        elseif topBarShown == true then
            pcall(self.TopBar.Hide, self.TopBar)
        end
    end
    return true
end

function RC:ScheduleLauncherVisibilityRefresh()
    self.LauncherVisibilityPending = true
    if self.LauncherVisibilityScheduled then
        return true
    end
    if not (C_Timer and type(C_Timer.After) == "function") then
        return false
    end

    self.LauncherVisibilityScheduled = true
    C_Timer.After(0, function()
        RC.LauncherVisibilityScheduled = nil
        if RC.LauncherVisibilityPending then
            RC:ApplyLauncherVisibilityNow()
        end
    end)
    return true
end

function RC:ApplyMenuScale(rawScale)
    local scale = math.max(0.5, math.min(2, tonumber(rawScale) or 1))
    self.db.profile.menuScale = scale
    if InCombatLockdown and InCombatLockdown() then
        self.LauncherScalePending = true
        return scale
    end
    if self.Menu then
        self.Menu:SetScale(scale)
        self:AnchorMenuToTopBar()
    end
    return scale
end

function RC:ApplyLauncherScale(rawScale)
    local scale = self:ApplyTopBarScale(rawScale)
    self:ApplyMenuScale(scale)
    return scale
end

local RC_SETTINGS_SHELL_TEXTURE = "Interface\\AddOns\\OrionUI\\RaidControl\\Media\\settings-shell.png"
local RC_SETTINGS_SHELL_CONTENT_LEFT = 260 / 1180
local RC_SETTINGS_SHELL_HEADER_BOTTOM = 110 / 720
local RC_SETTINGS_SHELL_BODY_BOTTOM = 690 / 720

function RC:CreateLauncherSurface(frame, kind)
    if not frame then
        return
    end

    local texture = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    texture:SetAllPoints(frame)
    texture:SetTexture(RC_SETTINGS_SHELL_TEXTURE)
    if kind == "tab" then
        texture:SetTexCoord(RC_SETTINGS_SHELL_CONTENT_LEFT, 1, 0, RC_SETTINGS_SHELL_HEADER_BOTTOM)
    else
        texture:SetTexCoord(
            RC_SETTINGS_SHELL_CONTENT_LEFT,
            1,
            RC_SETTINGS_SHELL_HEADER_BOTTOM,
            RC_SETTINGS_SHELL_BODY_BOTTOM
        )
    end

    local tint = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    tint:SetAllPoints(texture)
    frame.rcLauncherSurfaceTexture = texture
    frame.rcLauncherSurfaceTint = tint
    frame.rcLauncherSurfaceKind = kind
    self:RefreshLauncherSurface(frame, false)
end

function RC:RefreshLauncherSurface(frame, active)
    local tint = frame and frame.rcLauncherSurfaceTint
    if not tint then
        return
    end
    local color
    local alpha
    if frame.rcLauncherSurfaceKind == "tab" then
        color = active and self.Config.ButtonHover or self.Config.HeaderBg
        alpha = active and 0.34 or 0.18
    else
        color = self.Config.Color
        alpha = 0.10
    end
    tint:SetColorTexture(color.r, color.g, color.b, alpha)
end

local RC_SECURE_MENU_APPLY = [[
    local content = self:GetFrameRef("rcContent")
    if content then
        content:Show()
        content:SetAlpha(1)
    end
    local blocker = self:GetFrameRef("rcBlocker")
    if blocker then
        blocker:Hide()
    end
    if self:GetAttribute("rcOpen") then
        self:Show()
    else
        self:Hide()
    end
]]

local RC_SECURE_MENU_OPEN = [[
    if button == "LeftButton"
        and self:GetAttribute("state-combat") == "combat"
        and self:GetAttribute("rcMenuEnabled") then
        local menu = self:GetFrameRef("rcMenu")
        if menu then
            menu:SetHeight(menu:GetAttribute("rcTargetHeight") or 150)
            menu:SetAlpha(menu:GetAttribute("rcAlpha") or 1)
            menu:SetAttribute("rcOpen", true)
            menu:RunAttribute("apply")
            self:SetAttribute("rcMenuOpen", true)
            self:Hide()
        end
    end
]]

local RC_SECURE_COMBAT_MENU_OPEN = [[
    if button == "LeftButton" and self:GetAttribute("state-combat") == "combat" then
        local topBar = self:GetFrameRef("rcTopBar")
        local menu = self:GetFrameRef("rcMenu")
        if topBar and menu and topBar:GetAttribute("rcMenuEnabled") then
            menu:SetHeight(menu:GetAttribute("rcTargetHeight") or 150)
            menu:SetAlpha(menu:GetAttribute("rcAlpha") or 1)
            menu:SetAttribute("rcOpen", true)
            menu:RunAttribute("apply")
            topBar:SetAttribute("rcMenuOpen", true)
            topBar:Hide()
            self:Hide()
        end
    end
]]

local RC_SECURE_MENU_CLOSE = [[
    local topBar = self:GetFrameRef("rcTopBar")
    local combatButton = self:GetFrameRef("rcCombatButton")
    if button == "LeftButton"
        and topBar
        and topBar:GetAttribute("state-combat") == "combat" then
        local menu = self:GetFrameRef("rcMenu")
        if menu then
            menu:SetAttribute("rcOpen", false)
            menu:RunAttribute("apply")
        end
        topBar:SetAttribute("rcMenuOpen", false)
        if topBar:GetAttribute("rcEnabled") then
            topBar:Show()
        end
        if combatButton then
            combatButton:Show()
        end
    end
]]

local RC_SECURE_MENU_COMBAT_STATE = [[
    if newstate == "combat" then
        local menu = self:GetFrameRef("rcMenu")
        if menu then
            local open = self:GetAttribute("rcMenuOpen") and self:GetAttribute("rcMenuEnabled")
            menu:SetHeight(menu:GetAttribute("rcTargetHeight") or 150)
            menu:SetAlpha(menu:GetAttribute("rcAlpha") or 1)
            menu:SetAttribute("rcOpen", open and true or false)
            menu:RunAttribute("apply")
            if open then
                self:Hide()
            elseif self:GetAttribute("rcEnabled") then
                self:Show()
            else
                self:Hide()
            end
        end
    end
]]

local RC_SECURE_COMBAT_MENU_STATE = [[
    if newstate == "combat" then
        local topBar = self:GetFrameRef("rcTopBar")
        local menu = self:GetFrameRef("rcMenu")
        if topBar and menu then
            local enabled = topBar:GetAttribute("rcEnabled")
            local menuEnabled = topBar:GetAttribute("rcMenuEnabled")
            local open = topBar:GetAttribute("rcMenuOpen") and menuEnabled
            menu:SetHeight(menu:GetAttribute("rcTargetHeight") or 150)
            menu:SetAlpha(menu:GetAttribute("rcAlpha") or 1)
            menu:SetAttribute("rcOpen", open and true or false)
            menu:RunAttribute("apply")
            if open then
                topBar:Hide()
                self:Hide()
            elseif enabled and menuEnabled then
                topBar:Show()
                self:Show()
            else
                topBar:Hide()
                self:Hide()
            end
        end
    else
        self:Hide()
    end
]]

local function RC_SetSecureFrameRef(frame, key, target)
    if type(SecureHandlerSetFrameRef) == "function" then
        SecureHandlerSetFrameRef(frame, key, target)
        return true
    end
    local setFrameRef = frame and frame.SetFrameRef
    if type(setFrameRef) == "function" then
        setFrameRef(frame, key, target)
        return true
    end
    return false
end

function RC:CreateTopBar()
    if not RC.Config then
        self:Print(L["CRITICAL ERROR: RC.Config is nil. Media module failed to load."])
        return
    end
    self.TopBar = CreateFrame(
        "Button",
        "RC_TopBar",
        UIParent,
        "SecureHandlerClickTemplate,SecureHandlerStateTemplate,BackdropTemplate"
    )
    self.TopBar.rcBorderMinAlpha = 0.07
    self.TopBar:SetSize(232, 30)

    local scale = self.db.profile.topBarScale or self.db.profile.launcherScale or self.db.profile.scale or 1
    self.TopBar:SetScale(scale)

    -- Restore position after scale so saved offsets remain visually stable.
    local pos = self.db.profile.pos or { point = "CENTER", x = 0, y = 300 }
    self.TopBar:SetPoint(pos.point, UIParent, pos.relativePoint or pos.point, pos.x, pos.y)

    -- Store original position for scale changes
    self.TopBar.originalPoint = pos.point
    self.TopBar.originalX = pos.x
    self.TopBar.originalY = pos.y

    -- Compact launcher uses the same control surface as the rest of RaidControl.
    self:SkinFrame(self.TopBar)
    self:SetFrameThemeRole(self.TopBar, "Color", 0.20)
    self:CreateLauncherSurface(self.TopBar, "tab")

    -- Title (explicit font, dynamic color from settings)
    local title = self.TopBar:CreateFontString(nil, "OVERLAY")
    RC:SetFont(title, 11, "OUTLINE")
    title:SetPoint("CENTER", self.TopBar, "CENTER", 0, 0)
    title:SetJustifyH("CENTER")
    title:SetText("RaidControl")
    title:SetTextColor(RC:GetTitleColor())
    RC:RegisterTextColor(title, "title")
    self.TopBar.Title = title

    -- Hover/open feedback remains active while movement stays layout-only.
    self.TopBar:SetScript("OnEnter", function(btn)
        btn.rcHovered = true
        RC:RefreshLauncherInteractionState()
    end)
    self.TopBar:SetScript("OnLeave", function(btn)
        btn.rcHovered = nil
        RC:RefreshLauncherInteractionState()
    end)

    -- Toggle Logic
    self.TopBar:RegisterForClicks("AnyUp")
    self.TopBar:HookScript("OnClick", function(btn, button)
        if btn.rcWasDragged then
            btn.rcWasDragged = nil
            return
        end
        if button == "RightButton" then
            local workspace = self:GetModule("Workspace", true)
            if workspace and workspace.OpenSettingsFromRightClick then
                workspace:OpenSettingsFromRightClick()
            else
                local Settings = self:GetModule("Settings", true)
                if Settings and Settings.Open then
                    Settings:Open()
                end
            end
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            RC.IsMenuOpen = true
            RC.TopBarSuppressed = true
            RC.MenuAnimationState = nil
            RC.MenuTransitionPending = true
            return
        end
        self:ToggleMenu()
    end)

    self.TopBar:SetAlpha(self.db.profile.alpha or 1)

    -- Drag & Drop is intentionally exclusive to global layout mode.
    self.TopBar:SetMovable(true)
    self.TopBar:EnableMouse(true)
    self.TopBar:SetClampedToScreen(true) -- CRITICAL FIX: Prevent off-screen
    self.TopBar:RegisterForDrag("LeftButton")
    self.TopBar:SetScript("OnDragStart", function(btn)
        if RC:IsUILayoutUnlocked() then
            btn.rcMoving = true
            btn.rcWasDragged = true
            btn:StartMoving()
        end
    end)
    self.TopBar:SetScript("OnDragStop", function(btn)
        if not btn.rcMoving then return end
        btn.rcMoving = nil
        btn:StopMovingOrSizing()
        RC:SaveTopBarPosition()
    end)
end

function RC:CreateMenu()
    self.Menu = CreateFrame("Frame", "RC_Menu", UIParent, "SecureHandlerStateTemplate,BackdropTemplate")
    self.Menu.rcBorderMinAlpha = 0.07
    self.Menu:SetSize(232, 150)
    self:AnchorMenuToTopBar()
    self.Menu:SetScale(self.db.profile.menuScale or self.db.profile.launcherScale or self.db.profile.scale or 1)
    self.Menu:SetFrameStrata(self.TopBar:GetFrameStrata())
    self.Menu:SetFrameLevel((self.TopBar:GetFrameLevel() or 1) + 5)
    self.Menu:SetClipsChildren(true)
    self.Menu:SetClampedToScreen(true)
    self:SkinFrame(self.Menu)
    self:SetFrameThemeRole(self.Menu, "Color", 0.20)

    self.MenuSurfaceLayer = CreateFrame("Frame", nil, self.Menu)
    self.MenuSurfaceLayer:SetPoint("TOPLEFT", self.Menu, "TOPLEFT", 1, -1)
    self.MenuSurfaceLayer:SetPoint("TOPRIGHT", self.Menu, "TOPRIGHT", -1, -1)
    self.MenuSurfaceLayer:SetHeight(148)
    self.MenuSurfaceLayer:SetFrameLevel((self.Menu:GetFrameLevel() or 1) + 1)
    self:CreateLauncherSurface(self.MenuSurfaceLayer, "menu")

    -- These two layers are referenced and mutated by the restricted combat
    -- snippets. Midnight rejects ordinary addon frames as secure frame handles,
    -- so both references must point at secure-handler frames.
    self.MenuContent = CreateFrame("Frame", nil, self.Menu, "SecureHandlerBaseTemplate")
    self.MenuContent:SetAllPoints(self.Menu)
    self.MenuContent:SetFrameLevel((self.Menu:GetFrameLevel() or 1) + 5)
    self.MenuContent:SetAlpha(1)
    self.MenuContentAlpha = 1

    self.MenuTransitionBlocker = CreateFrame("Frame", nil, self.Menu, "SecureHandlerBaseTemplate")
    self.MenuTransitionBlocker:SetAllPoints(self.Menu)
    self.MenuTransitionBlocker:SetFrameLevel((self.Menu:GetFrameLevel() or 1) + 50)
    self.MenuTransitionBlocker:EnableMouse(true)
    self.MenuTransitionBlocker:Hide()

    self.Menu:SetAlpha(self.db.profile.alpha or 1)
    self.Menu:EnableMouse(false)
    self.Menu:EnableKeyboard(false)
    RC_SetPropagateKeyboardInput(self.Menu, true)
    self.Menu:SetScript("OnKeyDown", nil)

    -- While the menu is open it covers the launcher tab, so in layout mode
    -- dragging the menu moves the launcher (the tab re-anchors under it).
    self.Menu:SetMovable(true)
    self.Menu:RegisterForDrag("LeftButton")
    self.Menu:SetScript("OnDragStart", function(menu)
        if RC:IsUILayoutUnlocked() then
            menu.rcMoving = true
            menu:StartMoving()
        end
    end)
    self.Menu:SetScript("OnDragStop", function(menu)
        if not menu.rcMoving then return end
        menu.rcMoving = nil
        menu:StopMovingOrSizing()
        RC:MoveTopBarToMenu()
    end)

    -- Module Registry for dynamic content
    self.MenuModules = {}
    self.IsMenuOpen = false
    self:CreateMenuChrome()
    self:ConfigureSecureMenuToggle()
    self:RefreshCoreTheme(true)
    self.Menu:SetScript("OnShow", function()
        if InCombatLockdown and InCombatLockdown() then
            RC.IsMenuOpen = true
            RC.TopBarSuppressed = true
            RC.MenuTransitionPending = true
        end
    end)
    self.Menu:SetScript("OnHide", function()
        RC.IsMenuOpen = false
        RC:SetTopBarSuppressed(false)
    end)
    if UIParent and type(UIParent.HookScript) == "function" and not self.LauncherParentShowHooked then
        self.LauncherParentShowHooked = true
        UIParent:HookScript("OnShow", function()
            RC:ScheduleLauncherVisibilityRefresh()
        end)
    end

    self.Menu:Hide()
end

function RC:ConfigureSecureMenuToggle()
    local topBar = self.TopBar
    local menu = self.Menu
    local closeButton = self.MenuCloseButton
    if not topBar or not menu or not closeButton or not RegisterStateDriver then
        return
    end

    local profile = self.db and self.db.profile or {}
    local combatButton = self.CombatMenuToggle
    if not combatButton then
        combatButton = CreateFrame(
            "Button",
            "RC_CombatMenuToggle",
            UIParent,
            "SecureHandlerClickTemplate,SecureHandlerStateTemplate"
        )
        combatButton:SetAllPoints(topBar)
        if combatButton.SetFrameStrata and topBar.GetFrameStrata then
            combatButton:SetFrameStrata(topBar:GetFrameStrata())
        end
        combatButton:SetFrameLevel((topBar:GetFrameLevel() or 1) + 100)
        combatButton:RegisterForClicks("AnyUp")
        combatButton:EnableMouse(true)
        self.CombatMenuToggle = combatButton
    end
    menu:SetAttribute("rcOpen", false)
    menu:SetAttribute("rcTargetHeight", menu.TargetHeight or 150)
    menu:SetAttribute("rcAlpha", profile.alpha or 1)
    menu:SetAttribute("apply", RC_SECURE_MENU_APPLY)
    local refsReady = RC_SetSecureFrameRef(menu, "rcContent", self.MenuContent)
        and RC_SetSecureFrameRef(menu, "rcBlocker", self.MenuTransitionBlocker)
        and RC_SetSecureFrameRef(topBar, "rcMenu", menu)
        and RC_SetSecureFrameRef(combatButton, "rcTopBar", topBar)
        and RC_SetSecureFrameRef(combatButton, "rcMenu", menu)
        and RC_SetSecureFrameRef(closeButton, "rcTopBar", topBar)
        and RC_SetSecureFrameRef(closeButton, "rcMenu", menu)
        and RC_SetSecureFrameRef(closeButton, "rcCombatButton", combatButton)
    if not refsReady then
        return
    end

    local hiddenWhileSolo = self:IsLauncherHiddenWhileSolo()
    topBar:SetAttribute("rcEnabled", profile.hideTopBar ~= true and not hiddenWhileSolo)
    topBar:SetAttribute("rcMenuEnabled", profile.hideMenu ~= true and not hiddenWhileSolo)
    topBar:SetAttribute("rcMenuOpen", false)
    topBar:SetAttribute("_onclick", RC_SECURE_MENU_OPEN)
    topBar:SetAttribute("_onstate-combat", RC_SECURE_MENU_COMBAT_STATE)

    combatButton:SetAttribute("_onclick", RC_SECURE_COMBAT_MENU_OPEN)
    combatButton:SetAttribute("_onstate-combat", RC_SECURE_COMBAT_MENU_STATE)

    closeButton:SetAttribute("_onclick", RC_SECURE_MENU_CLOSE)
    RegisterStateDriver(topBar, "combat", "[combat] combat; nocombat")
    RegisterStateDriver(combatButton, "combat", "[combat] combat; nocombat")
end

function RC:MoveTopBarToMenu()
    local topBar, menu = self.TopBar, self.Menu
    if not topBar or not menu or (InCombatLockdown and InCombatLockdown()) then
        return
    end
    local centerX = menu:GetCenter()
    local top = menu:GetTop()
    if centerX and top then
        local ratio = (menu:GetEffectiveScale() or 1) / (topBar:GetEffectiveScale() or 1)
        topBar:ClearAllPoints()
        topBar:SetPoint("TOP", UIParent, "BOTTOMLEFT", centerX * ratio, top * ratio)
        self:SaveTopBarPosition()
    end
    self:AnchorMenuToTopBar()
end

function RC:AnchorMenuToTopBar()
    if not self.Menu or not self.TopBar then
        return
    end

    -- Keep the hidden protected menu at its final open position at all times.
    -- A combat click may show it but cannot safely re-anchor it, so parking the
    -- closed menu below the tab created a one-tab-height gap on the first pull.
    self.Menu:ClearAllPoints()
    self.Menu:SetPoint("TOP", self.TopBar, "TOP", 0, 0)
end

local function RC_MenuClampProgress(progress)
    return math.max(0, math.min(1, tonumber(progress) or 0))
end

local function RC_MenuSmootherStep(progress)
    local value = RC_MenuClampProgress(progress)
    return value * value * value * (value * ((value * 6) - 15) + 10)
end

function RC:EnsureMenuAnimation()
    if self.MenuTransitionOnUpdateInstalled or not self.Menu then
        return
    end

    self.MenuTransitionOnUpdateInstalled = true
    self.Menu:HookScript("OnUpdate", function(_, elapsed)
        RC:UpdateMenuTransition(elapsed)
    end)
end

function RC:SetMenuContentAlpha(alpha)
    local value = RC_MenuClampProgress(alpha)
    self.MenuContentAlpha = value
    if self.MenuContent then
        pcall(self.MenuContent.SetAlpha, self.MenuContent, value)
        if value <= 0.001 then
            pcall(self.MenuContent.Hide, self.MenuContent)
        else
            pcall(self.MenuContent.Show, self.MenuContent)
        end
    end
end

function RC:SetMenuTransitionBlocked(blocked)
    if not self.MenuTransitionBlocker then
        return
    end
    if blocked then
        pcall(self.MenuTransitionBlocker.Show, self.MenuTransitionBlocker)
    else
        pcall(self.MenuTransitionBlocker.Hide, self.MenuTransitionBlocker)
    end
end

function RC:UpdateMenuTransition(elapsed)
    local state = self.MenuAnimationState
    if not state or not self.Menu then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self.MenuTransitionPending = true
        return
    end

    local frameElapsed = math.max(0, tonumber(elapsed) or 0)
    state.elapsed = (state.elapsed or 0) + math.min(frameElapsed, 0.05)
    local progress = RC_MenuClampProgress(state.elapsed / math.max(0.01, state.duration or 0.01))
    local heightProgress
    local contentProgress
    if state.opening then
        heightProgress = RC_MenuSmootherStep(RC_MenuClampProgress(progress / 0.78))
        contentProgress = RC_MenuSmootherStep(RC_MenuClampProgress((progress - 0.70) / 0.30))
    else
        contentProgress = RC_MenuSmootherStep(RC_MenuClampProgress(progress / 0.25))
        heightProgress = RC_MenuSmootherStep(RC_MenuClampProgress((progress - 0.18) / 0.82))
    end

    local height = state.startHeight + ((state.targetHeight - state.startHeight) * heightProgress)
    local contentAlpha = state.startContentAlpha
        + ((state.targetContentAlpha - state.startContentAlpha) * contentProgress)
    pcall(self.Menu.SetHeight, self.Menu, height)
    self:SetMenuContentAlpha(contentAlpha)

    if progress >= 1 then
        self:FinishMenuTransition()
    end
end

function RC:FinishMenuTransition()
    local menu = self.Menu
    if not menu then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self.MenuTransitionPending = true
        return
    end
    local open = self.IsMenuOpen == true
    local targetHeight = open and (menu.TargetHeight or 150) or 0
    local targetAlpha = open and (self.db.profile.alpha or 1) or 0
    if open then
        pcall(menu.SetHeight, menu, targetHeight)
        pcall(menu.SetAlpha, menu, targetAlpha)
        self:SetMenuContentAlpha(1)
        pcall(menu.EnableMouse, menu, true)
        pcall(menu.Show, menu)
    else
        pcall(menu.EnableMouse, menu, false)
        pcall(menu.Hide, menu)
        pcall(menu.SetHeight, menu, menu.TargetHeight or 150)
        pcall(menu.SetAlpha, menu, self.db.profile.alpha or 1)
        self:SetMenuContentAlpha(1)
    end
    pcall(menu.EnableKeyboard, menu, false)
    self:SetMenuTransitionBlocked(false)
    self.MenuAnimationState = nil
    self:SetTopBarSuppressed(open)
    self:RefreshLauncherInteractionState()
end

function RC:SetMenuOpen(open, instant)
    if not self.Menu then
        return false
    end
    open = open and true or false
    local inCombat = InCombatLockdown and InCombatLockdown()
    if inCombat then
        self.IsMenuOpen = open
        self.TopBarSuppressed = open
        self.LayoutRefreshPending = true
        self.MenuTransitionPending = true
        return false
    end

    local wasOpen = self.IsMenuOpen == true
    local wasAnimating = self.MenuAnimationState ~= nil
    if open then
        self:RefreshLayout()
        self:AnchorMenuToTopBar(true)
        if not wasOpen and not wasAnimating then
            pcall(self.Menu.SetHeight, self.Menu, 0)
            self:SetMenuContentAlpha(0)
        end
        pcall(self.Menu.Show, self.Menu)
    end

    self.IsMenuOpen = open
    local targetHeight = open and (self.Menu.TargetHeight or 150) or 0
    local targetAlpha = open and (self.db.profile.alpha or 1) or 0
    pcall(self.Menu.EnableMouse, self.Menu, open)
    pcall(self.Menu.EnableKeyboard, self.Menu, false)
    pcall(self.Menu.SetAttribute, self.Menu, "rcOpen", open)
    pcall(self.Menu.SetAttribute, self.Menu, "rcTargetHeight", self.Menu.TargetHeight or 150)
    pcall(self.Menu.SetAttribute, self.Menu, "rcAlpha", self.db.profile.alpha or 1)
    if self.TopBar then
        pcall(self.TopBar.SetAttribute, self.TopBar, "rcMenuOpen", open)
    end
    if open then
        self:SetTopBarSuppressed(true)
    end
    self:RefreshLauncherInteractionState()

    if instant then
        if open then
            pcall(self.Menu.SetHeight, self.Menu, targetHeight)
            pcall(self.Menu.SetAlpha, self.Menu, targetAlpha)
            self:SetMenuContentAlpha(1)
            pcall(self.Menu.Show, self.Menu)
        else
            pcall(self.Menu.Hide, self.Menu)
            pcall(self.Menu.SetHeight, self.Menu, self.Menu.TargetHeight or 150)
            pcall(self.Menu.SetAlpha, self.Menu, self.db.profile.alpha or 1)
            self:SetMenuContentAlpha(1)
        end
        self:SetMenuTransitionBlocked(false)
        self.MenuAnimationState = nil
        self:SetTopBarSuppressed(open)
        return true
    end

    self:EnsureMenuAnimation()
    self:SetMenuTransitionBlocked(true)
    local startHeight = self.Menu:GetHeight() or 0
    local visibleAlpha = self.db.profile.alpha or 1
    pcall(self.Menu.SetAlpha, self.Menu, visibleAlpha)
    self.MenuAnimationState = {
        opening = open,
        startHeight = startHeight,
        targetHeight = targetHeight,
        startContentAlpha = self.MenuContentAlpha or (open and 0 or 1),
        targetContentAlpha = open and 1 or 0,
        elapsed = 0,
    }

    local fullHeight = math.max(self.Menu.TargetHeight or 150, startHeight, targetHeight, 1)
    local heightDistance = math.abs(targetHeight - startHeight) / fullHeight
    local contentDistance = math.abs(self.MenuAnimationState.targetContentAlpha - self.MenuAnimationState.startContentAlpha)
    local distance = math.max(heightDistance, contentDistance)
    local baseDuration = open and 0.42 or 0.36
    self.MenuAnimationState.duration = math.max(0.12, baseDuration * distance)
    if distance <= 0.001 then
        self:FinishMenuTransition()
    end
    return true
end

function RC:RecoverLauncherInteraction()
    if InCombatLockdown and InCombatLockdown() then
        self.MenuTransitionPending = true
        return false
    end
    self.MenuTransitionPending = nil
    self.MenuAnimationState = nil
    self:SetMenuTransitionBlocked(false)
    self:SetMenuContentAlpha(1)
    if not self.Menu then
        return false
    end
    pcall(self.Menu.EnableKeyboard, self.Menu, false)
    return self:SetMenuOpen(self.IsMenuOpen == true, true)
end

function RC:SetMenuClosedInstant()
    if self.Menu then
        self:SetMenuOpen(false, true)
    else
        self.IsMenuOpen = false
    end
end

function RC:ApplyInterfaceVisibility()
    if self.db and self.db.profile
        and (self.db.profile.hideMenu or self:IsLauncherHiddenWhileSolo()) then
        self:SetMenuClosedInstant()
    end
    self:ScheduleLauncherVisibilityRefresh()

    local actionStrip = self:GetModule("ActionStrip", true)
    if actionStrip and actionStrip.UpdateVisibility then
        actionStrip:UpdateVisibility()
    end
end

-- Shared geometry for the drop-down panel. Every row (control buttons, raid
-- markers, footer) sits on the same inset so the left and right edges line up.
RC.MenuLayout = {
    inset = 8,
    contentWidth = 216,
    rowHeight = 28,
    gap = 4,
}

-- One tooltip style for every drop-down control: white title, grey detail,
-- accent-coloured click hints. detail and hints may be functions so the text
-- reflects live state (pull running, modifier setting) at hover time.
function RC:ShowMenuTooltip(owner, title, detail, hints)
    if not GameTooltip or not owner then
        return
    end
    if type(detail) == "function" then
        detail = detail()
    end
    if type(hints) == "function" then
        hints = hints()
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(title or "", 1, 1, 1)
    if detail and detail ~= "" then
        GameTooltip:AddLine(detail, 0.75, 0.75, 0.75, true)
    end
    if type(hints) == "table" and #hints > 0 then
        local accent = self.Config.Accent
        for _, hint in ipairs(hints) do
            GameTooltip:AddLine(hint, accent.r, accent.g, accent.b)
        end
    end
    GameTooltip:Show()
end

function RC:HideMenuTooltip(owner)
    if GameTooltip and (not owner or not GameTooltip.IsOwned or GameTooltip:IsOwned(owner)) then
        GameTooltip:Hide()
    end
end

local MENU_ROLE_PILL_HEIGHT = 22
local MENU_ROLE_PILL_GAP = 4
local MENU_ROLE_ICON_SIZE = 14

local function StyleMenuRolePill(pill, hovered)
    if not pill or not pill.SetBackdropColor then
        return
    end
    local hover = RC.Config.ButtonHover
    pill:SetBackdropColor(hover.r, hover.g, hover.b, hovered and 0.55 or 0)
end

-- Size each role pill to its count so "2" and "12" keep equal padding.
local function LayoutMenuRolePills(roleSummary)
    if not roleSummary or not roleSummary.roleOrder then
        return
    end
    local x = 0
    for _, key in ipairs(roleSummary.roleOrder) do
        local frames = roleSummary.roleFrames[key]
        local pill = frames and frames.pill
        if pill then
            local textWidth = frames.count.GetStringWidth and frames.count:GetStringWidth() or 8
            local width = math.floor(6 + MENU_ROLE_ICON_SIZE + 4 + math.max(8, textWidth or 8) + 7 + 0.5)
            pill:SetWidth(width)
            pill:ClearAllPoints()
            pill:SetPoint("LEFT", roleSummary, "LEFT", x, 0)
            x = x + width + MENU_ROLE_PILL_GAP
        end
    end
    roleSummary:SetWidth(math.max(1, x - MENU_ROLE_PILL_GAP))
end

local function StyleMenuCloseButton(btn, hovered)
    if not btn then
        return
    end
    local err = RC.Config.ErrorColor
    if hovered then
        btn:SetBackdropColor(err.r, err.g, err.b, 0.55)
        btn.Icon:SetVertexColor(1, 1, 1, 1)
    else
        btn:SetBackdropColor(0, 0, 0, 0)
        local muted = RC.Config.MutedText
        btn.Icon:SetVertexColor(muted.r, muted.g, muted.b, 0.85)
    end
    btn:SetBackdropBorderColor(0, 0, 0, 0)
end

function RC:CreateMenuChrome()
    local layout = RC.MenuLayout
    local footer = CreateFrame("Frame", nil, self.MenuContent or self.Menu, "BackdropTemplate")
    footer.rcBorderAlphaOverride = 0
    local content = self.MenuContent or self.Menu
    footer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    footer:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
    footer:SetHeight(34)
    self:SkinFrame(footer, nil, true)
    self:SetFrameThemeRole(footer, "HeaderBg", 0.38)
    footer:SetBackdropBorderColor(0, 0, 0, 0)
    self.MenuFooter = footer

    local separator = footer:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", footer, "TOPLEFT", 1, 0)
    separator:SetPoint("TOPRIGHT", footer, "TOPRIGHT", -1, 0)
    separator:SetHeight(1)
    separator:SetColorTexture(RC.Config.SeparatorColor.r, RC.Config.SeparatorColor.g, RC.Config.SeparatorColor.b, 0.85)
    self.MenuFooterSeparator = separator

    -- The role pills start on the same inset as the control grid above them.
    local roleSummary = CreateFrame("Frame", nil, footer)
    roleSummary:SetPoint("LEFT", footer, "LEFT", layout.inset, 0)
    roleSummary:SetSize(140, MENU_ROLE_PILL_HEIGHT)
    roleSummary.roleFrames = {}
    roleSummary.roleOrder = { "TANK", "HEALER", "DPS" }
    self.MenuRoleSummary = roleSummary

    local roleLabels = {
        TANK = _G.TANK or L["Tanks"],
        HEALER = _G.HEALER or L["Healers"],
        DPS = _G.DAMAGER or L["Damage"],
    }

    for _, key in ipairs(roleSummary.roleOrder) do
        local pill = CreateFrame("Button", nil, roleSummary, "BackdropTemplate")
        pill.rcBorderAlphaOverride = 0
        pill:SetSize(40, MENU_ROLE_PILL_HEIGHT)
        self:SkinFrame(pill, nil, true)
        StyleMenuRolePill(pill, false)

        local icon = pill:CreateTexture(nil, "OVERLAY")
        icon:SetTexture(RC.RoleIcons.Texture)
        icon:SetTexCoord(unpack(RC.RoleIcons[key]))
        icon:SetSize(MENU_ROLE_ICON_SIZE, MENU_ROLE_ICON_SIZE)
        icon:SetPoint("LEFT", pill, "LEFT", 6, 0)

        local roleColor = RC.Config.RoleColors[key]
        local count = pill:CreateFontString(nil, "OVERLAY")
        RC:SetFont(count, 11, "OUTLINE")
        count:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        count:SetJustifyH("LEFT")
        count:SetTextColor(roleColor.r, roleColor.g, roleColor.b, 1)
        count:SetText("0")

        pill:SetScript("OnEnter", function(btn)
            StyleMenuRolePill(btn, true)
            local Roles = RC:GetModule("Roles", true)
            if Roles and Roles.ShowTooltip then
                Roles:ShowTooltip(btn, key)
            else
                RC:ShowMenuTooltip(btn, roleLabels[key])
            end
        end)
        pill:SetScript("OnLeave", function(btn)
            StyleMenuRolePill(btn, false)
            RC:HideMenuTooltip(btn)
        end)

        roleSummary.roleFrames[key] = { pill = pill, icon = icon, count = count }
    end
    LayoutMenuRolePills(roleSummary)

    -- Borderless icon button: quiet until hovered, then the usual red close tint.
    local closeButton = RC:CreateCloseButton(footer, 22, "SecureHandlerClickTemplate,BackdropTemplate")
    closeButton.rcBorderAlphaOverride = 0
    self:SetFrameThemeRole(closeButton, "Transparent")
    closeButton.Icon:SetSize(10, 10)
    StyleMenuCloseButton(closeButton, false)
    closeButton:SetPoint("RIGHT", footer, "RIGHT", -layout.inset, 0)
    closeButton:SetScript("OnEnter", function(btn)
        StyleMenuCloseButton(btn, true)
        RC:ShowMenuTooltip(btn, _G.CLOSE or L["Close"], nil, { L["Esc also closes the panel"] })
    end)
    closeButton:SetScript("OnLeave", function(btn)
        StyleMenuCloseButton(btn, false)
        RC:HideMenuTooltip(btn)
    end)
    closeButton:HookScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            RC.IsMenuOpen = false
            RC.TopBarSuppressed = false
            RC.MenuAnimationState = nil
            RC.MenuTransitionPending = true
            return
        end
        RC:CloseMenu()
    end)
    self.MenuCloseButton = closeButton
end

function RC:PositionMenuFooter()
    local menu = self.Menu
    local footer = self.MenuFooter
    if not menu or not footer then
        return
    end
    local footerHeight = footer:GetHeight() or 34
    local targetHeight = menu.TargetHeight or footerHeight
    local y = -math.max(0, targetHeight - footerHeight)
    footer:ClearAllPoints()
    local content = self.MenuContent or menu
    footer:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
    footer:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, y)
end

-- =============================================================================
-- BLIZZARD RAID CONTROL COMPATIBILITY
-- =============================================================================

function RC:ApplyBlizzardRaidControlVisibility()
    if InCombatLockdown and InCombatLockdown() then
        self.BlizzardRaidControlPending = true
        return false
    end

    local hide = self.db and self.db.profile and self.db.profile.hideBlizzardRaidControl == true
    local manager = _G.CompactRaidFrameManager
    local candidates = {
        manager,
        _G.CompactRaidFrameManagerToggleButton,
        _G.CompactRaidFrameManagerDisplayFrame,
        manager and manager.ToggleButton,
        manager and manager.toggleButton,
        manager and manager.displayFrame,
    }
    local seen = {}
    self.BlizzardRaidControlOriginalState = self.BlizzardRaidControlOriginalState or {}
    local applied = false
    for _, frame in pairs(candidates) do
        if frame and not seen[frame] then
            seen[frame] = true
            local original = self.BlizzardRaidControlOriginalState[frame]
            if not original then
                original = {
                    alpha = frame.GetAlpha and frame:GetAlpha() or 1,
                    mouseEnabled = frame.IsMouseEnabled and frame:IsMouseEnabled(),
                }
                if original.mouseEnabled == nil then
                    original.mouseEnabled = true
                end
                self.BlizzardRaidControlOriginalState[frame] = original
            end
            if frame.SetAlpha then
                frame:SetAlpha(hide and 0 or original.alpha or 1)
                applied = true
            end
            if frame.EnableMouse then
                frame:EnableMouse(not hide and original.mouseEnabled ~= false)
            end
        end
    end

    self.BlizzardRaidControlPending = (not applied) or nil
    return applied
end

function RC:OnBlizzardRaidControlEvent(event, addonName)
    if event == "ADDON_LOADED" and addonName ~= "Blizzard_CompactRaidFrames" then
        return
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
        self:ApplyInterfaceVisibility()
    end
    self:ApplyBlizzardRaidControlVisibility()
    if C_Timer and C_Timer.After and not self.BlizzardRaidControlRefreshQueued then
        self.BlizzardRaidControlRefreshQueued = true
        C_Timer.After(0, function()
            self.BlizzardRaidControlRefreshQueued = nil
            self:ApplyBlizzardRaidControlVisibility()
        end)
    end
end

function RC:RefreshCoreTheme(duringCreation)
    if not duringCreation and InCombatLockdown and InCombatLockdown() then
        -- Resizing the secure launcher and menu is blocked in combat.
        self.CoreThemeRefreshPending = true
        return
    end
    self.CoreThemeRefreshPending = nil
    if self.TopBar then
        self:SetFrameThemeRole(self.TopBar, "Color", 0.20)
        self:RefreshLauncherSurface(self.TopBar, self.TopBar.rcHovered or self:IsUILayoutUnlocked())
        self.TopBar:SetBackdropBorderColor(self:GetControlBorderColor(0.12))
    end
    if self.Menu then
        self:SetFrameThemeRole(self.Menu, "Color", 0.20)
        self:RefreshLauncherSurface(self.MenuSurfaceLayer, false)
        self.Menu:SetBackdropBorderColor(self:GetControlBorderColor(0.14))
    end
    if self.MenuFooter then
        self:SetFrameThemeRole(self.MenuFooter, "HeaderBg", 0.38)
        self.MenuFooter:SetBackdropBorderColor(0, 0, 0, 0)
    end

    local modern = self:IsModernTheme()
    local launcherWidth = self:GetThemeLayout("launcherWidth", 232)
    local launcherHeight = self:GetThemeLayout("launcherHeight", 30)
    local menuFooterHeight = self:GetThemeLayout("menuFooterHeight", modern and 38 or 34)

    if self.TopBar then
        self.TopBar:SetWidth(launcherWidth)
        self.TopBar:SetHeight(launcherHeight)
        self.TopBar:SetAlpha(self.db.profile.alpha or 1)
        if self.TopBar.Title then
            RC:SetFont(self.TopBar.Title, 11, "OUTLINE")
            self.TopBar.Title:ClearAllPoints()
            self.TopBar.Title:SetPoint("CENTER", self.TopBar, "CENTER", 0, 0)
            self.TopBar.Title:SetJustifyH("CENTER")
        end
    end
    if self.Menu then
        self.Menu:SetWidth(launcherWidth)
    end
    if self.TopBarMenuHint then
        self.TopBarMenuHint:Hide()
    end
    if self.MenuFooter then
        self.MenuFooter:SetHeight(menuFooterHeight)
    end

    if self.MenuFooterSeparator then
        self.MenuFooterSeparator:SetColorTexture(self.Config.SeparatorColor.r, self.Config.SeparatorColor.g, self.Config.SeparatorColor.b, self.Config.SeparatorColor.a or 0.06)
    end

    if self.Menu and self.MenuModules then
        self:RefreshLayout()
    end
    self:RefreshLauncherInteractionState()
end

function RC:UpdateMenuRoleSummary(tanks, healers, dps)
    if not self.MenuRoleSummary or not self.MenuRoleSummary.roleFrames then
        return
    end

    if self.db and self.db.profile and self.db.profile.hideRoles then
        self.MenuRoleSummary:Hide()
        return
    end

    self.MenuRoleSummary:Show()
    self.MenuRoleSummary.roleFrames.TANK.count:SetText(tanks or 0)
    self.MenuRoleSummary.roleFrames.HEALER.count:SetText(healers or 0)
    self.MenuRoleSummary.roleFrames.DPS.count:SetText(dps or 0)
    LayoutMenuRolePills(self.MenuRoleSummary)
end

function RC:SetTopBarSuppressed(suppressed)
    self.TopBarSuppressed = suppressed and true or false
    self:ScheduleLauncherVisibilityRefresh()
end

-- Close menu without toggling (for ESC/keybind handlers)
function RC:CloseMenu()
    if not self.IsMenuOpen or not self.Menu then
        return
    end
    self:SetMenuOpen(false, true)
end

-- Register a module to appear in the dropdown menu
-- config = { name, order, frame, isVisible (function or nil) }
function RC:RegisterMenuModule(config)
    if not self.MenuModules then self.MenuModules = {} end
    if config and config.frame and self.MenuContent and config.frame.SetParent
        and not (InCombatLockdown and InCombatLockdown()) then
        config.frame:SetParent(self.MenuContent)
    end
    table.insert(self.MenuModules, config)
    -- Sort by order
    table.sort(self.MenuModules, function(a, b) return (a.order or 100) < (b.order or 100) end)
    if not (InCombatLockdown and InCombatLockdown()) then
        self:RefreshLayout()
    else
        self.LayoutRefreshPending = true
    end
end

function RC:RefreshLayout()
    if not self.Menu or not self.MenuModules then return end
    if InCombatLockdown and InCombatLockdown() then
        self.LayoutRefreshPending = true
        return
    end
    self.LayoutRefreshPending = false

    if self.MenuRoleSummary then
        if self.db.profile.hideRoles then
            self.MenuRoleSummary:Hide()
        else
            self.MenuRoleSummary:Show()
        end
    end

    -- Keep the space above the first row equal to the space above the footer
    -- (10px modern, 8px classic) so the controls sit centred in the panel.
    local modern = self:IsModernTheme()
    local topPadding = modern and 10 or 8
    local bottomPadding = self.MenuFooter and (modern and 48 or 42) or 12
    local spacing = modern and 6 or 4
    local yOffset = -topPadding
    local totalHeight = topPadding

    -- Iterate through registered modules in order
    for _, mod in ipairs(self.MenuModules) do
        local frame = mod.frame
        local isVisible = true

        if frame and self.MenuContent and frame.SetParent
            and (not frame.GetParent or frame:GetParent() ~= self.MenuContent) then
            frame:SetParent(self.MenuContent)
        end

        -- Check visibility function or setting
        if mod.isVisible then
            isVisible = mod.isVisible()
        end

        if frame and isVisible then
            frame:ClearAllPoints()
            frame:SetPoint("TOP", self.MenuContent or self.Menu, "TOP", 0, yOffset)
            frame:Show()

            local h = frame:GetHeight()
            yOffset = yOffset - h - spacing
            totalHeight = totalHeight + h + spacing
        elseif frame then
            frame:Hide()
        end
    end

    -- Add bottom padding
    totalHeight = totalHeight + bottomPadding - spacing -- Remove last spacing, add bottom padding

    self.Menu.TargetHeight = math.max(totalHeight, 0)
    if self.MenuSurfaceLayer then
        self.MenuSurfaceLayer:SetHeight(math.max(1, self.Menu.TargetHeight - 2))
    end
    if self.Menu.SetAttribute then
        self.Menu:SetAttribute("rcTargetHeight", self.Menu.TargetHeight)
        self.Menu:SetAttribute("rcAlpha", self.db.profile.alpha or 1)
    end
    self:PositionMenuFooter()

    if not self.MenuAnimationState then
        self.Menu:SetHeight(self.Menu.TargetHeight)
    end
end

function RC:ToggleMenu()
    if not self.Menu then
        return
    end

    if self.db and self.db.profile
        and (self.db.profile.hideMenu or self:IsLauncherHiddenWhileSolo()) then
        self:SetMenuClosedInstant()
        return
    end

    -- If settings window is open, close it first and don't reopen menu
    local SettingsModule = RC:GetModule("Settings")
    ---@diagnostic disable-next-line: undefined-field
    if SettingsModule and SettingsModule.frame and SettingsModule.frame:IsShown() then
        ---@diagnostic disable-next-line: undefined-field
        SettingsModule.frame:Hide()
        return
    end

    self:SetMenuOpen(not self.IsMenuOpen, true)
end

function RC:OnAddonActionBlocked(event, blockedAddon, blockedFunction)
    local normalizedAddon = tostring(blockedAddon or ""):lower()
    local normalizedSelf = tostring(addonName or "Raidcontrol"):lower()
    if normalizedAddon ~= "raidcontrol" and normalizedAddon ~= normalizedSelf then
        return
    end

    local functionName = tostring(blockedFunction or "unknown protected function")
    local now = GetTime and GetTime() or 0
    local signature = tostring(event) .. ":" .. functionName
    if self.LastBlockedActionSignature == signature
        and now > 0
        and now - (self.LastBlockedActionTime or 0) < 1 then
        return
    end
    self.LastBlockedActionSignature = signature
    self.LastBlockedActionTime = now

    local timestamp = time and time() or 0
    local context = {
        version = tostring(self.version or "unknown"),
        combat = InCombatLockdown and InCombatLockdown() and true or false,
        menuOpen = self.IsMenuOpen == true,
        menuAnimating = self.MenuAnimationState ~= nil,
    }
    local log = self.db and self.db.global and self.db.global.blockedActionLog
    if type(log) == "table" then
        local last = log[#log]
        if last and last.event == tostring(event) and last.func == functionName then
            last.count = (last.count or 1) + 1
            last.lastTimestamp = timestamp
            last.context = context
        else
            log[#log + 1] = {
                event = tostring(event),
                func = functionName,
                timestamp = timestamp,
                lastTimestamp = timestamp,
                count = 1,
                context = context,
            }
        end
        while #log > 20 do
            table.remove(log, 1)
        end
    end
end

function RC:FinalizeLauncherStartupState()
    self.LauncherStartupCloseScheduled = nil
    self.IsMenuOpen = false
    self.TopBarSuppressed = false
    self.MenuAnimationState = nil
    self.MenuTransitionPending = nil

    if InCombatLockdown and InCombatLockdown() then
        self.LauncherStartupClosePending = true
        return false
    end

    self.LauncherStartupClosePending = nil
    if self.Menu then
        self:SetMenuOpen(false, true)
        self:AnchorMenuToTopBar(false)
    end
    self:ScheduleLauncherVisibilityRefresh()
    return true
end

function RC:OnEnable()
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnBlizzardRaidControlEvent")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnBlizzardRaidControlEvent")
    self:RegisterEvent("ADDON_LOADED", "OnBlizzardRaidControlEvent")
    self:RegisterEvent("ADDON_ACTION_BLOCKED", "OnAddonActionBlocked")
    self:RegisterEvent("ADDON_ACTION_FORBIDDEN", "OnAddonActionBlocked")
    self:RegisterEvent("ENCOUNTER_START", "OnRaidContextEncounterStart")
    self:RegisterEvent("ENCOUNTER_END", "OnRaidContextEncounterEnd")
    self:ApplyBlizzardRaidControlVisibility()

    self.LauncherStartupCloseScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if RC.LauncherStartupCloseScheduled then
                RC:FinalizeLauncherStartupState()
            end
        end)
    else
        self:FinalizeLauncherStartupState()
    end
end

function RC:OnDisable()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("GROUP_ROSTER_UPDATE")
    self:UnregisterEvent("ADDON_LOADED")
    self:UnregisterEvent("ADDON_ACTION_BLOCKED")
    self:UnregisterEvent("ADDON_ACTION_FORBIDDEN")
    self:UnregisterEvent("ENCOUNTER_START")
    self:UnregisterEvent("ENCOUNTER_END")
end

function RC:OnPlayerRegenEnabled()
    if self.LauncherStartupClosePending then
        self:FinalizeLauncherStartupState()
    end
    if self.LayoutRefreshPending then
        self.LayoutRefreshPending = false
        self:RefreshLayout()
    end
    if self.LauncherScalePending then
        self.LauncherScalePending = nil
        local profile = self.db.profile
        self:ApplyTopBarScale(profile.topBarScale or profile.launcherScale or 1)
        self:ApplyMenuScale(profile.menuScale or profile.launcherScale or 1)
    end
    if self.CoreThemeRefreshPending then
        self:RefreshCoreTheme()
    end
    self:RecoverLauncherInteraction()
    self:ApplyInterfaceVisibility()
    if self.BlizzardRaidControlPending or (self.db and self.db.profile and self.db.profile.hideBlizzardRaidControl) then
        self:ApplyBlizzardRaidControlVisibility()
    end
    if self.CycleKeybindRefreshPending then
        self:UpdateCycleKeybinds()
    end
    if self.MarkerModifierRefreshPending then
        self.MarkerModifierRefreshPending = nil
        for _, moduleName in ipairs({ "Markers", "ActionStrip", "Control" }) do
            local module = self:GetModule(moduleName, true)
            if module and module.RefreshModifierAttributes then
                module:RefreshModifierAttributes()
            end
        end
    end
    local settings = self:GetModule("Settings", true)
    if settings and settings.openPending then
        settings.openPending = nil
        settings.combatOpenNotified = nil
        settings:Open()
    end
end

-- Toggle frame lock state
function RC:SetFrameLock(locked)
    if not locked and not self:IsUILayoutUnlocked() then
        locked = true
    end
    self.db.profile.lockFrames = locked and true or false
    self:RefreshLauncherInteractionState()
end

-- Export global for keybinding handlers
_G.RCPlaceTargetMarker = RCPlaceTargetMarker
_G.RCPlaceWorldMarker = RCPlaceWorldMarker
_G.RCClearAllWorldMarkers = RCClearAllWorldMarkers
_G.RCShuffleWorldMarker = RCShuffleWorldMarker
