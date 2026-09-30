local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
local CombatLogger = RC:NewModule("CombatLogger", "AceEvent-3.0")

local ADVANCED_LOGGING_CVAR = "advancedCombatLogging"

local function GetCVarSafe(name)
    if C_CVar and C_CVar.GetCVar then
        return C_CVar.GetCVar(name)
    end
    if GetCVar then
        return GetCVar(name)
    end
    return nil
end

local function SetCVarSafe(name, value)
    if C_CVar and C_CVar.SetCVar then
        C_CVar.SetCVar(name, tostring(value))
        return
    end
    if SetCVar then
        SetCVar(name, tostring(value))
    end
end

local function IsAdvancedCombatLoggingEnabled()
    local value = GetCVarSafe(ADVANCED_LOGGING_CVAR)
    return value == "1" or value == 1 or value == true
end

-- Display names for the remembered-answer buckets (the keys stay English).
local DECISION_LABELS = {
    raid = L["Raid"],
    dungeon = L["Dungeon"],
    mythicplus = L["Mythic+"],
    arena = L["Arena"],
    battleground = L["Battleground"],
}

local function GetInstanceKey()
    local name, instanceType, difficultyID = GetInstanceInfo()
    return table.concat({
        tostring(name or "unknown"),
        tostring(instanceType or "none"),
        tostring(difficultyID or 0),
    }, ":")
end

local function EnsurePopupDialogs()
    StaticPopupDialogs.RAIDCONTROL_START_COMBAT_LOG = StaticPopupDialogs.RAIDCONTROL_START_COMBAT_LOG or {
        text = L["Start combat logging for %s?\n\nYour answer will be remembered for this content type."],
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(_, data)
            if data and data.module then
                data.module:SetDecision(data.context, "always")
                data.module:StartLoggingWithAdvancedCheck(data.context)
            end
        end,
        OnCancel = function(_, data, reason)
            -- Only a real "No" is remembered; a popup replaced or hidden by
            -- the client (loading screens, re-shows) must not count as one.
            if reason == "clicked" and data and data.module and data.context then
                data.module:SetDecision(data.context, "never")
            end
        end,
        noCancelOnReuse = true,
    }

    StaticPopupDialogs.RAIDCONTROL_ENABLE_ADVANCED_LOG = StaticPopupDialogs.RAIDCONTROL_ENABLE_ADVANCED_LOG or {
        text = L["Advanced Combat Logging is disabled. Enable it and start combat logging?"],
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnAccept = function(_, data)
            SetCVarSafe(ADVANCED_LOGGING_CVAR, "1")
            if data and data.module then
                data.module:StartLogging(data.context)
            end
        end,
        OnCancel = function(_, data, reason)
            -- Only a real "No" is remembered; a popup replaced or hidden by
            -- the client (loading screens, re-shows) must not count as one.
            if reason == "clicked" and data and data.module and data.context then
                data.module:SetDecision(data.context, "never")
            end
        end,
        noCancelOnReuse = true,
    }
end

function CombatLogger:OnInitialize()
    self.db = RC.db.profile
    self.isLogging = false
    self.db.combatLogDecisions = self.db.combatLogDecisions or {}
    EnsurePopupDialogs()
end

function CombatLogger:OnEnable()
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("CHALLENGE_MODE_START", "ZONE_CHANGED_NEW_AREA")
end

function CombatLogger:GetLoggingContext()
    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return nil
    end

    local instanceName, _, difficultyID = GetInstanceInfo()
    local label = instanceName or L["this instance"]
    local shouldLog = false
    local decisionKey

    if instanceType == "raid" and self.db.logRaid then
        shouldLog = true
        label = string.format(L["%s raid"], label)
        decisionKey = "raid"
    elseif instanceType == "party" and self.db.logParty then
        shouldLog = true
        local challengeActive = (C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive and C_ChallengeMode.IsChallengeModeActive())
            or difficultyID == 8
        decisionKey = challengeActive and "mythicplus" or "dungeon"
        label = string.format(challengeActive and L["%s Mythic+"] or L["%s dungeon"], label)
    elseif instanceType == "arena" and self.db.logArena then
        shouldLog = true
        label = string.format(L["%s arena"], label)
        decisionKey = "arena"
    elseif instanceType == "pvp" and self.db.logBG then
        shouldLog = true
        label = string.format(L["%s battleground"], label)
        decisionKey = "battleground"
    end

    if not shouldLog then
        return nil
    end

    return {
        key = GetInstanceKey(),
        label = label,
        difficultyID = difficultyID,
        instanceType = instanceType,
        decisionKey = decisionKey,
    }
end

function CombatLogger:SetDecision(context, decision)
    if not context or not context.decisionKey then
        return
    end
    self.db.combatLogDecisions = self.db.combatLogDecisions or {}
    self.db.combatLogDecisions[context.decisionKey] = decision
    RC:Printf(L["Combat logging preference for %s: %s."], DECISION_LABELS[context.decisionKey] or context.decisionKey,
        decision == "always" and L["always log"] or L["do not ask"])
end

function CombatLogger:ResetDecisions()
    self.db.combatLogDecisions = {}
    RC:Print(L["Combat logging remembered answers reset."])
end

function CombatLogger:StartLogging(context)
    if self.isLogging then
        return
    end
    LoggingCombat(true)
    self.isLogging = true
    if context and context.key then
        self.activeKey = context.key
    end
    RC:Printf(L["Combat logging |cFF00FF00STARTED|r for %s."], (context and context.label) or L["this instance"])
end

function CombatLogger:StartLoggingWithAdvancedCheck(context)
    if not IsAdvancedCombatLoggingEnabled() then
        StaticPopup_Show("RAIDCONTROL_ENABLE_ADVANCED_LOG", nil, nil, { module = self, context = context })
        return
    end
    self:StartLogging(context)
end

function CombatLogger:StopLogging()
    if not self.isLogging then
        return
    end
    LoggingCombat(false)
    self.isLogging = false
    self.activeKey = nil
    RC:Print(L["Combat logging |cFFFF5555STOPPED|r."])
end

function CombatLogger:EvaluateZone()
    if self.db.enableCombatLogger == false then
        self:StopLogging()
        return
    end

    local context = self:GetLoggingContext()
    if not context then
        self:StopLogging()
        return
    end

    if self.isLogging then
        return
    end
    local decision = self.db.combatLogDecisions and self.db.combatLogDecisions[context.decisionKey]
    if decision == "never" then
        return
    end
    if decision == "always" then
        self:StartLoggingWithAdvancedCheck(context)
        return
    end

    if self.db.combatLogPrompt ~= false then
        if StaticPopup_Visible and StaticPopup_Visible("RAIDCONTROL_START_COMBAT_LOG") then
            return
        end
        StaticPopup_Show("RAIDCONTROL_START_COMBAT_LOG", context.label, nil, { module = self, context = context })
    else
        self:StartLoggingWithAdvancedCheck(context)
    end
end

function CombatLogger:ZONE_CHANGED_NEW_AREA()
    C_Timer.After(1, function()
        if self and self.EvaluateZone then
            self:EvaluateZone()
        end
    end)
end
