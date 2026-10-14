local _, ns = ...
local RC = ns.RC
local ReadyTracker = RC:NewModule("ReadyTracker", "AceEvent-3.0")

local FRAME_WIDTH = 468
local ROW_HEIGHT = 24
local MIN_FRAME_HEIGHT = 286
-- Header, summary, columns and buttons around the roster rows.
local FRAME_CHROME_HEIGHT = 180
-- Never cap below a full 20-player mythic roster; larger groups grow with
-- the screen and scroll only when the screen itself runs out.
local MIN_ROSTER_CAP = FRAME_CHROME_HEIGHT + 20 * ROW_HEIGHT
local SCREEN_MARGIN = 40
-- Fully prepared ready rows are dimmed, never hidden, in the Issues view.
local SETTLED_ROW_ALPHA = 0.45

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function ShortName(value)
    if type(value) ~= "string" or value == "" or IsSecret(value) then
        return nil
    end
    return (value:match("^([^-]+)") or value):lower()
end

local function IsTrackableGroupUnit(unit)
    if not unit or IsSecret(unit) or type(unit) ~= "string" then
        return false
    end
    return unit == "player" or unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil
end

function ReadyTracker:OnInitialize()
    self.db = RC.db.profile
    self.readyCheckActive = false
    self.responses = {}
    self.consumableData = {}
    self.pendingBuffUnits = {}
    self.initiator = nil
    self:CreateMainFrame()
end

function ReadyTracker:OnEnable()
    self:RegisterEvent("READY_CHECK")
    self:RegisterEvent("READY_CHECK_CONFIRM")
    self:RegisterEvent("READY_CHECK_FINISHED")
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupRosterUpdate")
    self:RegisterEvent("UNIT_CONNECTION", "OnUnitConnection")
    self:RegisterEvent("UNIT_INVENTORY_CHANGED", "OnUnitInventoryChanged")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnPlayerEquipmentChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "HideBlizzardFrame")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")

    self:HideBlizzardFrame()
end

-- Suppress Blizzard's default ready-check window without hiding or reparenting
-- its protected frame. Alpha and mouse state are changed only out of combat.
function ReadyTracker:HideBlizzardFrame()
    local frame = _G.ReadyCheckFrame
    if not frame then
        self.blizzardFramePending = true
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        self.blizzardFramePending = true
        return false
    end

    local suppress = self.db and self.db.enableReadyTracker and self.db.useCustomReadyCheck
    if frame.SetAlpha then
        frame:SetAlpha(suppress and 0 or 1)
    end
    if frame.EnableMouse then
        frame:EnableMouse(not suppress)
    end
    -- Mouse state does not cascade to children: the invisible Yes/No buttons
    -- would still answer the ready check on a stray click.
    for _, name in ipairs({ "ReadyCheckListenerFrame", "ReadyCheckFrameYesButton", "ReadyCheckFrameNoButton" }) do
        local child = _G[name]
        if child and child.EnableMouse then
            child:EnableMouse(not suppress)
        end
    end
    self.blizzardFramePending = nil
    return true
end

function ReadyTracker:OnPlayerRegenEnabled()
    if self.blizzardFramePending then
        self:HideBlizzardFrame()
    end
end

-- ============================================================================
-- BUFF CHECKING - ALL VISIBLE BUFFS
-- ============================================================================

local function CheckAllConsumables(unit)
    if RC.ScanUnitBuffStatus then
        local data = RC:ScanUnitBuffStatus(unit)
        data.unit = unit
        return data
    end

    local data = {
        accessible = false,
        food = false,
        flask = false,
        rune = false,
        weaponMain = false,
        weaponOff = false,
        shamanEnchant = false, -- Rockbiter/Windfury etc
    }
    return data
end

local function SafeUnitName(unit)
    if not unit or IsSecret(unit) or not UnitExists(unit) then
        return nil
    end
    local ok, name = pcall(GetUnitName, unit, true)
    if ok and not IsSecret(name) and type(name) == "string" and name ~= "" then
        return name
    end
    return nil
end

local function SafeClassFile(unit)
    if not unit or IsSecret(unit) or not UnitExists(unit) then
        return nil
    end
    local ok, _, classFile = pcall(UnitClass, unit)
    if ok and not IsSecret(classFile) and type(classFile) == "string" then
        return classFile
    end
    return nil
end

local function SafeUnitBoolean(api, unit)
    if type(api) ~= "function" or not unit or IsSecret(unit) then
        return nil
    end
    local ok, value = pcall(api, unit)
    if ok and not IsSecret(value) and type(value) == "boolean" then
        return value
    end
    return nil
end

function ReadyTracker:IsConsumableScanEnabled()
    return not self.db or self.db.enableConsumableChecker ~= false
end

function ReadyTracker:NamesMatch(left, right)
    local leftKey = ShortName(left)
    return leftKey ~= nil and leftKey == ShortName(right)
end

function ReadyTracker:PlayReadyCheckSound()
    local played = false
    if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then
        played = pcall(PlaySound, SOUNDKIT.READY_CHECK, "Master")
    end
    if not played and PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        played = pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON, "Master")
    end
    if not played and PlaySoundFile then
        pcall(PlaySoundFile, "Sound\\Interface\\ReadyCheck.ogg", "Master")
    end
end

-- Returns the roster entries plus whether every group unit resolved to a
-- name. Names can come back secret or empty mid-encounter or while a member
-- is loading, so an incomplete read must never be treated as "they left".
function ReadyTracker:CollectGroupUnits()
    local entries = {}
    local complete = true
    local numGroupMembers = GetNumGroupMembers()

    local function add(unit)
        local name = SafeUnitName(unit)
        if not name then
            complete = false
        else
            local classFile = SafeClassFile(unit)
            table.insert(entries, {
                name = name,
                unit = unit,
                classFile = classFile,
                connected = SafeUnitBoolean(UnitIsConnected, unit),
                dead = SafeUnitBoolean(UnitIsDeadOrGhost, unit),
            })
        end
    end

    if UnitInRaid("player") then
        for i = 1, numGroupMembers do
            add("raid" .. i)
        end
    else
        add("player")
        for i = 1, math.max((numGroupMembers or 1) - 1, 0) do
            add("party" .. i)
        end
    end

    return entries, complete
end

function ReadyTracker:StartConsumableScan(entries)
    if self.scanTimer then
        self.scanTimer:Cancel()
        self.scanTimer = nil
    end

    if not self:IsConsumableScanEnabled() then
        self.scanQueue = {}
        self.scanIndex = 1
        self.buffScanActive = false
        self:UpdateFrame()
        return
    end

    self.scanQueue = entries or {}
    self.scanIndex = 1
    self.buffScanActive = #self.scanQueue > 0

    local function step()
        if not self:ShouldTrackBuffRefresh() then
            self.buffScanActive = false
            return
        end

        local scanned = 0
        while self.scanIndex <= #self.scanQueue and scanned < 4 do
            local entry = self.scanQueue[self.scanIndex]
            if entry and not IsSecret(entry.name) and type(entry.name) == "string" and entry.unit then
                local data = CheckAllConsumables(entry.unit)
                data.unit = entry.unit
                data.classFile = entry.classFile or SafeClassFile(entry.unit)
                data.connected = entry.connected
                data.dead = entry.dead
                data.scanned = true
                self.consumableData[entry.name] = data
            end
            self.scanIndex = self.scanIndex + 1
            scanned = scanned + 1
        end

        self:UpdateFrame()

        if self.scanIndex <= #self.scanQueue then
            self.scanTimer = C_Timer.NewTimer(0.03, step)
        else
            self.buffScanActive = false
            self.scanTimer = nil
            self:UpdateFrame()
        end
    end

    if C_Timer and C_Timer.NewTimer then
        self.scanTimer = C_Timer.NewTimer(0, step)
    else
        step()
    end
end

function ReadyTracker:CancelConsumableRefresh()
    self.buffScanActive = false
    if self.scanTimer then
        self.scanTimer:Cancel()
        self.scanTimer = nil
    end
    if self.buffRefreshTimer then
        self.buffRefreshTimer:Cancel()
        self.buffRefreshTimer = nil
    end
    self.pendingFullBuffScan = nil
    self.pendingBuffUnits = {}
end

function ReadyTracker:BuildCachedBuffSnapshot()
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

    for name in pairs(self.responses or {}) do
        local data = self.consumableData and self.consumableData[name]
        if data and data.scanned then
            snapshot.total = snapshot.total + 1
            if data.classFile then
                snapshot.classes[data.classFile] = true
            end
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

    local coreRules = RC.GetCoreBuffRules and RC:GetCoreBuffRules() or {}
    for _, rule in ipairs(coreRules) do
        local found = false
        for _, classFile in ipairs(rule.classes or {}) do
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

local function ConsumableMissing(data, enabled)
    if enabled == false then
        return false
    end
    if not data or not data.scanned then
        return true
    end
    if data.accessible == false then
        return false
    end
    return not data.food
        or not data.flask
        or not data.rune
        or not (data.weaponMain or data.weaponOff or data.shamanEnchant)
end

function ReadyTracker:HasMissingConsumables(data)
    return ConsumableMissing(data, self:IsConsumableScanEnabled())
end

function ReadyTracker:HasPreparationIssue(data, durability)
    data = data or {}
    if data.connected == false or data.dead == true then
        return true
    end
    if self:HasMissingConsumables(data) then
        return true
    end
    local threshold = tonumber(self.db and self.db.durabilityWarnThreshold) or 30
    return type(durability) == "number" and not IsSecret(durability) and durability <= threshold
end

function ReadyTracker:HasDisplayIssue(status, data, durability)
    return status ~= "ready" or self:HasPreparationIssue(data, durability)
end

function ReadyTracker:GetEntryPriority(status, data, durability)
    data = data or {}
    if data.connected == false or data.dead == true then return 1 end
    if status == "notready" then return 2 end
    if status == false then return 3 end
    if self:HasPreparationIssue(data, durability) then return 4 end
    return 5
end

function ReadyTracker:BuildReadinessSummary(durabilityResolver)
    local summary = {
        total = 0,
        ready = 0,
        waiting = 0,
        notReady = 0,
        prepIssues = 0,
        durability = {},
    }
    for name, status in pairs(self.responses or {}) do
        summary.total = summary.total + 1
        if status == "ready" then
            summary.ready = summary.ready + 1
        elseif status == "notready" then
            summary.notReady = summary.notReady + 1
        else
            summary.waiting = summary.waiting + 1
        end
        local durability = durabilityResolver and durabilityResolver(name) or nil
        summary.durability[name] = durability
        if self:HasPreparationIssue(self.consumableData and self.consumableData[name], durability) then
            summary.prepIssues = summary.prepIssues + 1
        end
    end
    return summary
end

local function AppendMissingConsumables(data, out)
    if not data or not data.scanned then
        table.insert(out, "scan pending")
        return
    end
    if data.accessible == false then
        table.insert(out, "aura data unavailable")
        return
    end
    if not data.food then table.insert(out, "food") end
    if not data.flask then table.insert(out, "flask") end
    if not data.rune then table.insert(out, "rune") end
    if not (data.weaponMain or data.weaponOff or data.shamanEnchant) then
        table.insert(out, "weapon")
    end
end

function ReadyTracker:BuildMissingConsumableReport()
    local report = {}
    if not self:IsConsumableScanEnabled() then
        return report
    end
    for name in pairs(self.responses or {}) do
        local data = self.consumableData and self.consumableData[name]
        -- Only report what a finished scan actually saw missing; never whisper
        -- "scan pending" or "aura data unavailable" to a raider.
        if data and data.scanned and data.accessible ~= false and self:HasMissingConsumables(data) then
            local missing = {}
            AppendMissingConsumables(data, missing)
            table.insert(report, { name = name, missing = missing })
        end
    end
    table.sort(report, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return report
end

function ReadyTracker:RefreshAllConsumables()
    local entries, complete = self:CollectGroupUnits()
    self:ApplyRosterEntries(entries, complete)
    self:StartConsumableScan(entries)
end

function ReadyTracker:WhisperMissingConsumables()
    if not self:IsConsumableScanEnabled() then
        RC:ShowError("Consumable scans are disabled in settings.")
        return false
    end
    if not RC.db.profile.readyTrackerWhisperMissing then
        RC:ShowError("Missing-consumable whispers are disabled in settings.")
        return false
    end
    if InCombatLockdown and InCombatLockdown() then
        RC:ShowError("Missing-consumable whispers are unavailable during combat.")
        return false
    end

    local report = self:BuildMissingConsumableReport()
    if #report == 0 then
        RC:Print("No missing consumables found.")
        return true
    end

    local sent = 0
    local playerName = SafeUnitName("player")
    for _, entry in ipairs(report) do
        if entry.name and entry.name ~= playerName then
            RC:SendChat("RC: Missing " .. table.concat(entry.missing, ", ") .. ".", "WHISPER", nil, entry.name)
            sent = sent + 1
        end
    end
    RC:Print(string.format("Whispered %d player%s with missing consumables.", sent, sent == 1 and "" or "s"))
    return true
end

function ReadyTracker:ShouldTrackBuffRefresh()
    if not self:IsConsumableScanEnabled() then
        return false
    end
    return self.readyCheckActive or (self.frame and self.frame:IsShown() and next(self.responses or {}) ~= nil)
end

-- Merges a roster read into the check. Members already on the list stay on it
-- unless a complete roster read shows they really left the group.
function ReadyTracker:ApplyRosterEntries(entries, complete)
    local activeNames = {}
    for _, entry in ipairs(entries or {}) do
        if not IsSecret(entry.name) and type(entry.name) == "string" and entry.name ~= "" then
            activeNames[entry.name] = true
            if self.responses[entry.name] == nil then
                self.responses[entry.name] = false
            end
            local data = self.consumableData[entry.name]
            if data then
                data.unit = entry.unit
                data.classFile = entry.classFile or data.classFile
                data.connected = entry.connected
                data.dead = entry.dead
            else
                self.consumableData[entry.name] = {
                    unit = entry.unit,
                    classFile = entry.classFile,
                    connected = entry.connected,
                    dead = entry.dead,
                    scanned = false,
                }
            end
        end
    end

    if not complete then
        return
    end
    for name in pairs(self.responses or {}) do
        if not activeNames[name] then
            self.responses[name] = nil
            self.consumableData[name] = nil
        end
    end
end

function ReadyTracker:RefreshConsumableUnit(unit)
    if not IsTrackableGroupUnit(unit) or not UnitExists(unit) then
        return
    end

    local name
    for storedName, storedData in pairs(self.consumableData or {}) do
        if storedData and storedData.unit == unit then
            name = storedName
            break
        end
    end
    if not name then
        return
    end

    local data = CheckAllConsumables(unit)
    data.unit = unit
    data.classFile = SafeClassFile(unit)
    data.connected = SafeUnitBoolean(UnitIsConnected, unit)
    data.dead = SafeUnitBoolean(UnitIsDeadOrGhost, unit)
    data.scanned = true
    self.consumableData[name] = data
end

function ReadyTracker:ScheduleBuffRefresh(unit, fullScan)
    if not self:ShouldTrackBuffRefresh() then
        return
    end

    if fullScan then
        self.pendingFullBuffScan = true
    elseif IsTrackableGroupUnit(unit) then
        self.pendingBuffUnits = self.pendingBuffUnits or {}
        self.pendingBuffUnits[unit] = true
    end

    if self.buffRefreshTimer then
        return
    end

    self.buffRefreshTimer = C_Timer.NewTimer(0.12, function()
        self.buffRefreshTimer = nil
        if not self:ShouldTrackBuffRefresh() then
            self.pendingFullBuffScan = nil
            self.pendingBuffUnits = {}
            return
        end

        if self.pendingFullBuffScan then
            self.pendingFullBuffScan = nil
            local entries, complete = self:CollectGroupUnits()
            self:ApplyRosterEntries(entries, complete)
            self:StartConsumableScan(entries)
            return
        end

        local pending = self.pendingBuffUnits or {}
        self.pendingBuffUnits = {}
        for unit in pairs(pending) do
            self:RefreshConsumableUnit(unit)
        end
        self:UpdateFrame()
    end)
end

function ReadyTracker:OnUnitAura(event, unit)
    self:ScheduleBuffRefresh(unit, false)
end

function ReadyTracker:OnUnitInventoryChanged(event, unit)
    self:ScheduleBuffRefresh(unit, false)
end

function ReadyTracker:OnPlayerEquipmentChanged()
    self:ScheduleBuffRefresh("player", false)
end

function ReadyTracker:OnGroupRosterUpdate()
    if self._layoutModeActive and self._layoutPreviewState and not self._layoutPreviewInterrupted then
        return
    end
    if not self.readyCheckActive and not (self.frame and self.frame:IsShown()) then
        return
    end
    if self:IsConsumableScanEnabled() then
        self:ScheduleBuffRefresh(nil, true)
        return
    end
    local entries, complete = self:CollectGroupUnits()
    self:ApplyRosterEntries(entries, complete)
    self:UpdateFrame()
end

function ReadyTracker:OnUnitConnection(event, unit)
    if not IsTrackableGroupUnit(unit) or (not self.readyCheckActive and not (self.frame and self.frame:IsShown())) then
        return
    end
    for _, data in pairs(self.consumableData or {}) do
        if data and data.unit == unit then
            data.connected = SafeUnitBoolean(UnitIsConnected, unit)
            data.dead = SafeUnitBoolean(UnitIsDeadOrGhost, unit)
            break
        end
    end
    if self:IsConsumableScanEnabled() then
        self:ScheduleBuffRefresh(unit, false)
    else
        self:UpdateFrame()
    end
end

-- ============================================================================
-- READY CHECK EVENTS
-- ============================================================================

function ReadyTracker:READY_CHECK(event, initiator, duration)
    if not self.db.enableReadyTracker then return end

    if self._layoutModeActive then
        self._layoutPreviewInterrupted = true
    end
    self.displayGeneration = (self.displayGeneration or 0) + 1
    self:PlayReadyCheckSound()

    self.readyCheckActive = true
    self.responses = {}
    self.consumableData = {}
    self.initiator = IsSecret(initiator) and nil or initiator

    local entries = self:CollectGroupUnits()
    for _, entry in ipairs(entries) do
        if not IsSecret(entry.name) then
            self.responses[entry.name] = false
            self.consumableData[entry.name] = {
                unit = entry.unit,
                classFile = entry.classFile,
                connected = entry.connected,
                dead = entry.dead,
                scanned = false,
            }
        end
    end

    -- Mark initiator as ready (initiator is a NAME, not a unit token!)
    if initiator and not IsSecret(initiator) then
        -- Find the matching name in our responses (might have a realm suffix).
        for name in pairs(self.responses) do
            if self:NamesMatch(name, initiator) then
                self.responses[name] = "ready"
                break
            end
        end

        -- Automatically ready the current player if they initiated
        local playerName = SafeUnitName("player")
        if self:NamesMatch(playerName, initiator) then
            RC:ConfirmGroupReadyCheck(true)
        end
    end

    -- Show our pretty frame with buttons (only if custom enabled)
    if self.db.useCustomReadyCheck then
        self:HideBlizzardFrame()
        self:ShowReadyCheckFrame(duration or 30)
    end

    self:StartConsumableScan(entries)

    local leadTools = RC:GetModule("RaidLeadTools", true)
    if leadTools and leadTools.RequestDurability and leadTools.SendDurability then
        if self.db.durabilityReadyCheckRequest ~= false then
            leadTools:RequestDurability(false)
            local generation = self.displayGeneration
            C_Timer.After(3, function()
                if generation == self.displayGeneration and leadTools.ReportDurability then
                    leadTools:ReportDurability()
                end
            end)
        else
            leadTools:SendDurability()
        end
    end
end

function ReadyTracker:READY_CHECK_CONFIRM(event, unit, isReady)
    if not self.db.enableReadyTracker then return end
    if not self.readyCheckActive then return end

    if IsSecret(unit) or IsSecret(isReady) then return end
    local name = SafeUnitName(unit)
    if name and self.responses[name] ~= nil then
        self.responses[name] = isReady and "ready" or "notready"
        local data = self.consumableData[name]
        if data then
            data.connected = SafeUnitBoolean(UnitIsConnected, unit)
            data.dead = SafeUnitBoolean(UnitIsDeadOrGhost, unit)
        end
        self:UpdateFrame()

        -- Check if all players have responded and fade buttons if so
        self:CheckAndFadeButtons()
    end
end

-- Check if all players have responded and fade buttons accordingly
function ReadyTracker:CheckAndFadeButtons()
    if not self.readyCheckActive then return end

    local allResponded = true
    local allReady = true
    local allNotReady = true
    local hasResponses = false

    for _, status in pairs(self.responses) do
        if status == false then
            allResponded = false
            allReady = false
            allNotReady = false
            break
        else
            hasResponses = true
            if status == "ready" then
                allNotReady = false
            else
                allReady = false
            end
        end
    end

    -- Fade buttons if everyone is ready, not ready, or all have responded
    if hasResponses and (allResponded or allReady or allNotReady) then
        local f = self.frame
        if f and f:IsShown() then
            for _, btn in ipairs(self.responseButtons) do
                if not btn.clicked then
                    btn.inactive = true
                    btn:SetAlpha(0.3)
                end
            end
        end
    end
end

function ReadyTracker:READY_CHECK_FINISHED(event, preempted)
    if not self.db.enableReadyTracker then return end
    if not self.readyCheckActive then return end
    self.readyCheckActive = false

    local keepVisibleScan = self.frame and self.frame:IsShown() and self.scanTimer
    if not keepVisibleScan then
        self.buffScanActive = false
        if self.scanTimer then
            self.scanTimer:Cancel()
            self.scanTimer = nil
        end
    end

    local afk = {}
    local notReady = {}

    for name, status in pairs(self.responses) do
        if status == false then
            table.insert(afk, name)
        elseif status == "notready" then
            table.insert(notReady, name)
        end
    end

    -- Print AFK to chat (personal only)
    if #afk > 0 then
        RC:Print("AFK: " .. table.concat(afk, ", "))
    end

    self:ReportResults(afk, notReady)

    -- Show re-check button for leader/assist
    if self.frame and self.frame:IsShown() then
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            self.frame.recheckBtn:Show()
        end
        for _, button in ipairs(self.responseButtons or {}) do
            button:Hide()
        end
        self.frame.initiatorText:Hide()
        local generation = self.displayGeneration
        local autoClose = math.max(0, math.min(30, tonumber(self.db.readyTrackerAutoCloseSeconds) or 8))
        if autoClose > 0 then
            C_Timer.After(autoClose, function()
                if generation == self.displayGeneration and not self.readyCheckActive and not self._layoutModeActive then
                    self:FadeOutFrame()
                end
            end)
        end
    end
end

-- ============================================================================
-- MAIN PRETTY FRAME
-- ============================================================================

function ReadyTracker:SaveFramePosition()
    local frame = self.frame
    if not frame or not self.db then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    if point and relativePoint and type(x) == "number" and type(y) == "number" then
        self.db.readyTrackerPos = { point, relativePoint, x, y }
    end
end

function ReadyTracker:RestoreFramePosition()
    local frame = self.frame
    if not frame then return end
    self.db = RC.db.profile
    local scale = math.max(0.7, math.min(1.5, tonumber(self.db.readyTrackerScale) or 1))
    frame:SetScale(scale)
    frame:ClearAllPoints()
    local pos = self.db.readyTrackerPos
    if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string" then
        frame:SetPoint(pos[1], UIParent, pos[2], tonumber(pos[3]) or 0, tonumber(pos[4]) or 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
    end
    frame._rcPositionReady = true
end

function ReadyTracker:ApplyScale(rawScale)
    local frame = self.frame
    self.db = RC.db.profile
    local scale = math.max(0.7, math.min(1.5, tonumber(rawScale) or 1))
    self.db.readyTrackerScale = scale
    if not frame then return scale end
    if not frame._rcPositionReady then
        self:RestoreFramePosition()
        return scale
    end
    if RC.SetScalePreserveCenter then
        RC:SetScalePreserveCenter(frame, scale, function()
            self:SaveFramePosition()
        end)
    else
        frame:SetScale(scale)
    end
    return scale
end

function ReadyTracker:ApplyDisplaySettings()
    local frame = self.frame
    if not frame then return end
    self.db = RC.db.profile
    local alpha = math.max(0.45, math.min(1, tonumber(self.db.readyTrackerAlpha) or 1))
    frame:SetAlpha(alpha)
    if not frame._rcPositionReady then self:RestoreFramePosition() end
    self:ApplyScale(self.db.readyTrackerScale or 1)
end

function ReadyTracker:ResetPosition()
    if InCombatLockdown and InCombatLockdown() then
        RC:Print("Ready-check position cannot be reset during combat.")
        return false
    end
    self.db.readyTrackerPos = nil
    if self.frame then self.frame._rcPositionReady = nil end
    self:ApplyDisplaySettings()
    return true
end

function ReadyTracker:UpdateFilterButtons()
    local frame = self.frame
    if not frame then return end
    local issuesOnly = self.db.readyTrackerMissingOnly == true
    local selected = RC.Config.NavSelectedBg or RC.Config.Selected
    local normal = RC.Config.ButtonBg
    local border = RC.Config.NavSelectedBorder or RC.Config.Accent
    for button, active in pairs({ [frame.allBtn] = not issuesOnly, [frame.missingOnlyBtn] = issuesOnly }) do
        if button then
            button:SetBackdropColor(
                active and selected.r or normal.r,
                active and selected.g or normal.g,
                active and selected.b or normal.b,
                active and math.max(0.22, selected.a or 0.12) or (normal.a or 1)
            )
            if active then
                button:SetBackdropBorderColor(border.r, border.g, border.b, 0.72)
            else
                button:SetBackdropBorderColor(RC:GetControlBorderColor())
            end
        end
    end
end

function ReadyTracker:CreateMainFrame()
    local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    f:SetSize(FRAME_WIDTH, 350)
    RC:SkinFrame(f)
    RC:ApplyThemedWindow(f, "window")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(100)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:Hide()
    RC:RegisterEscapeFrame(f)

    -- Header
    local header = CreateFrame("Frame", nil, f)
    header:SetSize(f:GetWidth(), 35)
    header:SetPoint("TOP", f, "TOP", 0, 0)
    RC:SkinFrame(header, nil, true)
    RC:ApplyThemedHeader(header)
    f.header = header
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if ReadyTracker._layoutModeActive and not (InCombatLockdown and InCombatLockdown()) then
            f:StartMoving()
        end
    end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        ReadyTracker:SaveFramePosition()
    end)

    local headerText = header:CreateFontString(nil, "OVERLAY")
    RC:SetFont(headerText, 14, "OUTLINE")
    headerText:SetPoint("LEFT", header, "LEFT", 14, 0)
    headerText:SetText("READY CHECK")
    RC:SetTextColor(headerText, "title")
    f.headerText = headerText

    -- Timer bar
    f.timerBar = CreateFrame("StatusBar", nil, header)
    f.timerBar:SetPoint("BOTTOM", header, "BOTTOM", 0, 2)
    f.timerBar:SetSize(f:GetWidth() - 20, 3)
    f.timerBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    f.timerBar:SetStatusBarColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b)
    f.timerBar:SetMinMaxValues(0, 30)
    f.timerBar:SetValue(30)

    -- Countdown timer text (right side of header)
    f.timerText = header:CreateFontString(nil, "OVERLAY")
    RC:SetFont(f.timerText, 13, "OUTLINE")
    f.timerText:SetPoint("RIGHT", header, "RIGHT", -38, 0)
    f.timerText:SetTextColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b)
    f.timerText:SetText("")

    local closeButton = RC:CreateCloseButton(header, 20)
    closeButton:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    closeButton:SetFrameLevel((header:GetFrameLevel() or f:GetFrameLevel() or 100) + 5)
    closeButton:SetScript("OnClick", function()
        ReadyTracker:HideReadyCheckFrame()
    end)
    f.closeButton = closeButton

    local summaryBand = CreateFrame("Frame", nil, f, "BackdropTemplate")
    summaryBand:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -35)
    summaryBand:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -35)
    summaryBand:SetHeight(38)
    RC:SkinFrame(summaryBand)
    RC:ApplyThemedPanel(summaryBand, "panel", { alpha = 0.48, borderAlpha = 0.08 })
    f.summaryBand = summaryBand

    local function AddMetricSeparator(x)
        local line = summaryBand:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(RC.Config.SeparatorColor.r, RC.Config.SeparatorColor.g, RC.Config.SeparatorColor.b, 0.36)
        line:SetSize(1, 20)
        line:SetPoint("LEFT", summaryBand, "LEFT", x, 0)
        f.metricSeparators = f.metricSeparators or {}
        f.metricSeparators[#f.metricSeparators + 1] = line
    end
    AddMetricSeparator(117)
    AddMetricSeparator(234)
    AddMetricSeparator(351)

    f.tallyText = f:CreateFontString(nil, "OVERLAY")
    RC:SetFont(f.tallyText, 11, "OUTLINE")
    f.tallyText:SetPoint("CENTER", summaryBand, "LEFT", 58, 0)
    f.tallyText:SetWidth(108)
    f.tallyText:SetJustifyH("CENTER")
    f.tallyText:SetText("READY  0 / 0")

    f.waitingText = f:CreateFontString(nil, "OVERLAY")
    RC:SetFont(f.waitingText, 11, "OUTLINE")
    f.waitingText:SetPoint("CENTER", summaryBand, "LEFT", 175, 0)
    f.waitingText:SetWidth(108)
    f.waitingText:SetJustifyH("CENTER")
    f.waitingText:SetText("WAITING  0")

    f.notReadyText = f:CreateFontString(nil, "OVERLAY")
    RC:SetFont(f.notReadyText, 11, "OUTLINE")
    f.notReadyText:SetPoint("CENTER", summaryBand, "LEFT", 292, 0)
    f.notReadyText:SetWidth(108)
    f.notReadyText:SetJustifyH("CENTER")
    f.notReadyText:SetText("NOT READY  0")

    local buffHitbox = CreateFrame("Frame", nil, summaryBand)
    buffHitbox:SetPoint("TOPRIGHT", summaryBand, "TOPRIGHT", 0, 0)
    buffHitbox:SetPoint("BOTTOMRIGHT", summaryBand, "BOTTOMRIGHT", 0, 0)
    buffHitbox:SetWidth(117)
    buffHitbox:EnableMouse(true)
    f.buffHitbox = buffHitbox

    f.buffSummaryText = buffHitbox:CreateFontString(nil, "OVERLAY")
    RC:SetFont(f.buffSummaryText, 10, "OUTLINE")
    f.buffSummaryText:SetPoint("CENTER", buffHitbox, "CENTER", 0, 0)
    f.buffSummaryText:SetWidth(108)
    f.buffSummaryText:SetJustifyH("CENTER")
    f.buffSummaryText:SetText("ISSUES  0")

    buffHitbox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Preparation Details", 1, 1, 1)
        local snapshot = ReadyTracker:BuildCachedBuffSnapshot()
        if not ReadyTracker:IsConsumableScanEnabled() then
            GameTooltip:AddLine("Consumable scans are disabled.", 0.72, 0.72, 0.72)
        elseif snapshot and snapshot.total and snapshot.total > 0 then
            local available = snapshot.available == nil and snapshot.total or snapshot.available
            GameTooltip:AddLine(string.format("Food: %d/%d", snapshot.food or 0, available), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(string.format("Flask: %d/%d", snapshot.flask or 0, available), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(string.format("Rune: %d/%d", snapshot.rune or 0, available), 0.85, 0.85, 0.85)
            GameTooltip:AddLine(string.format("Weapon: %d/%d", snapshot.weapon or 0, available), 0.85, 0.85, 0.85)
            if available < snapshot.total then
                GameTooltip:AddLine(string.format("Aura data unavailable: %d", snapshot.total - available), 0.65, 0.65, 0.65)
            end
            if snapshot.missingSynergy and #snapshot.missingSynergy > 0 then
                GameTooltip:AddLine("Missing raid buffs: " .. table.concat(snapshot.missingSynergy, ", "), 1, 0.45, 0.25, true)
            else
                GameTooltip:AddLine("Core raid buffs covered.", 0.35, 1, 0.35)
            end
        else
            GameTooltip:AddLine("No live group units found.", 1, 0.45, 0.25)
        end
        GameTooltip:AddLine("Issues also include offline, dead, and low-durability players.", 0.65, 0.72, 0.78, true)
        GameTooltip:Show()
    end)
    buffHitbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local function CreateToolButton(parent, text, width)
        local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        btn:SetSize(width, 24)
        RC:SkinFrame(btn)
        RC:ApplyThemedPanel(btn, "button")
        btn.Text = btn:CreateFontString(nil, "OVERLAY")
        RC:SetFont(btn.Text, 10, "OUTLINE")
        btn.Text:SetPoint("CENTER")
        btn.Text:SetText(text)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, 1)
        end)
        return btn
    end

    f.allBtn = CreateToolButton(f, "All", 58)
    f.allBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -80)
    f.allBtn:SetScript("OnClick", function()
        RC.db.profile.readyTrackerMissingOnly = false
        ReadyTracker:UpdateFrame()
    end)

    f.missingOnlyBtn = CreateToolButton(f, "Issues", 62)
    f.missingOnlyBtn:SetPoint("LEFT", f.allBtn, "RIGHT", 4, 0)
    f.missingOnlyBtn:SetScript("OnClick", function()
        RC.db.profile.readyTrackerMissingOnly = true
        ReadyTracker:UpdateFrame()
    end)
    for _, filterButton in ipairs({ f.allBtn, f.missingOnlyBtn }) do
        filterButton:SetScript("OnLeave", function()
            ReadyTracker:UpdateFilterButtons()
        end)
    end

    f.refreshBuffBtn = CreateToolButton(f, "Refresh", 74)
    f.refreshBuffBtn:SetPoint("LEFT", f.missingOnlyBtn, "RIGHT", 10, 0)
    f.refreshBuffBtn:SetScript("OnClick", function()
        ReadyTracker:RefreshAllConsumables()
    end)

    f.whisperMissingBtn = CreateToolButton(f, "Whisper", 82)
    f.whisperMissingBtn:SetPoint("LEFT", f.refreshBuffBtn, "RIGHT", 6, 0)
    f.whisperMissingBtn:SetScript("OnClick", function()
        ReadyTracker:WhisperMissingConsumables()
    end)

    -- Column headers - ALL CONSUMABLES
    local cols = {
        {text = "Name", width = 132, x = 8},
        {text = "Food", width = 42, x = 142},
        {text = "Flask", width = 42, x = 184},
        {text = "Rune", width = 42, x = 226},
        {text = "Weap", width = 42, x = 268},
        {text = "Dura", width = 52, x = 312},
        {text = "Status", width = 76, x = 372},
    }

    f.columnHeaders = {}
    for _, col in ipairs(cols) do
        local t = f:CreateFontString(nil, "OVERLAY")
        RC:SetFont(t, 10, "OUTLINE")
        t:SetPoint("TOPLEFT", f, "TOPLEFT", col.x, -112)
        t:SetWidth(col.width)
        t:SetText(col.text)
        t:SetJustifyH("CENTER")
        t:SetTextColor(0.6, 0.6, 0.6)
        f.columnHeaders[#f.columnHeaders + 1] = t
    end

    -- Content area
    local scrollFrame = CreateFrame("ScrollFrame", nil, f)
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -132)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 48)
    scrollFrame:EnableMouseWheel(true)
    f.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(446, 1)
    scrollFrame:SetScrollChild(content)
    f.content = content

    f.scrollbar = RC:CreateScrollbar(f, scrollFrame)
    f.scrollbar:ClearAllPoints()
    f.scrollbar:SetPoint("TOPRIGHT", scrollFrame, "TOPRIGHT", 8, -2)
    f.scrollbar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 8, 2)
    f.rows = {}

    -- Button area at bottom
    local btnArea = CreateFrame("Frame", nil, f)
    btnArea:SetSize(f:GetWidth(), 40)
    btnArea:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)

    -- Buttons (stored on frame to show/hide based on initiator)
    f.buttons = {}

    -- READY button - left side
    f.readyBtn = CreateFrame("Button", nil, btnArea, "BackdropTemplate")
    f.readyBtn:SetSize(104, 32)
    f.readyBtn:SetPoint("LEFT", 76, 0)
    RC:SkinFrame(f.readyBtn)
    RC:ApplyThemedPanel(f.readyBtn, "button")
    f.readyBtn:SetBackdropColor(0.1, 0.3, 0.1, 1)

    f.readyBtn.Text = f.readyBtn:CreateFontString(nil, "OVERLAY")
    RC:SetFont(f.readyBtn.Text, 12, "OUTLINE")
    f.readyBtn.Text:SetPoint("CENTER")
    f.readyBtn.Text:SetText("Ready")

    -- Store button references for mutual fading
    self.responseButtons = {}

    -- Helper to handle response: hide both buttons, show "Response sent" briefly
    local function SetResponseGiven(_)
        local generation = ReadyTracker.displayGeneration
        for _, btn in ipairs(self.responseButtons) do
            btn.responded = true
            btn.inactive = true
            btn:Hide()
        end
        f.responseSentText:Show()
        C_Timer.After(2, function()
            if generation == ReadyTracker.displayGeneration and f.responseSentText then
                f.responseSentText:Hide()
            end
        end)
    end

    -- Helper to check if all players have responded
    local function CheckAllResponded()
        if not ReadyTracker.readyCheckActive then return false end
        local allResponded = true
        for _, status in pairs(ReadyTracker.responses) do
            if status == false then
                allResponded = false
                break
            end
        end
        return allResponded
    end

    -- Helper to fade both buttons when all responded
    local function FadeIfAllResponded()
        if CheckAllResponded() then
            for _, btn in ipairs(self.responseButtons) do
                if not btn.responded then
                    btn.inactive = true
                    btn:SetAlpha(0.3)
                end
            end
        end
    end

    -- READY button click handler - use secure action to avoid taint
    f.readyBtn:SetScript("OnClick", function()
        local success = RC:ConfirmGroupReadyCheck(true)
        if success then
            SetResponseGiven(f.readyBtn)
            -- Update our local state immediately for responsiveness
            local playerName = SafeUnitName("player")
            if playerName then
                ReadyTracker.responses[playerName] = "ready"
                ReadyTracker:UpdateFrame()
            end
            -- Check if everyone is now ready
            local generation = ReadyTracker.displayGeneration
            C_Timer.After(0.1, function()
                if generation == ReadyTracker.displayGeneration then FadeIfAllResponded() end
            end)
        end
    end)
    table.insert(f.buttons, f.readyBtn)
    table.insert(self.responseButtons, f.readyBtn)
    f.readyBtn.responded = false
    f.readyBtn.inactive = false

    -- NOT READY button - right side
    f.notReadyBtn = CreateFrame("Button", nil, btnArea, "BackdropTemplate")
    f.notReadyBtn:SetSize(104, 32)
    f.notReadyBtn:SetPoint("RIGHT", -76, 0)
    RC:SkinFrame(f.notReadyBtn)
    RC:ApplyThemedPanel(f.notReadyBtn, "button")
    f.notReadyBtn:SetBackdropColor(0.3, 0.1, 0.1, 1)

    f.notReadyBtn.Text = f.notReadyBtn:CreateFontString(nil, "OVERLAY")
    RC:SetFont(f.notReadyBtn.Text, 12, "OUTLINE")
    f.notReadyBtn.Text:SetPoint("CENTER")
    f.notReadyBtn.Text:SetText("Not Ready")

    f.notReadyBtn:SetScript("OnEnter", function()
        if f.notReadyBtn.inactive then
            f.notReadyBtn:SetAlpha(0.6)
        end
        f.notReadyBtn:SetBackdropBorderColor(1, 0.3, 0.3, 1)
    end)
    f.notReadyBtn:SetScript("OnLeave", function()
        if f.notReadyBtn.inactive then
            f.notReadyBtn:SetAlpha(0.3)
        end
        f.notReadyBtn:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, 1)
    end)

    -- NOT READY button click handler
    f.notReadyBtn:SetScript("OnClick", function()
        local success = RC:ConfirmGroupReadyCheck(false)
        if success then
            SetResponseGiven(f.notReadyBtn)
            -- Update our local state immediately for responsiveness
            local playerName = SafeUnitName("player")
            if playerName then
                ReadyTracker.responses[playerName] = "notready"
                ReadyTracker:UpdateFrame()
            end
            local generation = ReadyTracker.displayGeneration
            C_Timer.After(0.1, function()
                if generation == ReadyTracker.displayGeneration then FadeIfAllResponded() end
            end)
        end
    end)
    table.insert(f.buttons, f.notReadyBtn)
    table.insert(self.responseButtons, f.notReadyBtn)
    f.notReadyBtn.responded = false
    f.notReadyBtn.inactive = false

    -- Ready button hover effects
    f.readyBtn:SetScript("OnEnter", function()
        if f.readyBtn.inactive then
            f.readyBtn:SetAlpha(0.6)
        end
        f.readyBtn:SetBackdropBorderColor(0.3, 1, 0.3, 1)
    end)
    f.readyBtn:SetScript("OnLeave", function()
        if f.readyBtn.inactive then
            f.readyBtn:SetAlpha(0.3)
        end
        f.readyBtn:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, 1)
    end)

    -- "Response sent" feedback text (shown briefly after clicking a button)
    f.responseSentText = btnArea:CreateFontString(nil, "OVERLAY")
    RC:SetFont(f.responseSentText, 13, "OUTLINE")
    f.responseSentText:SetPoint("CENTER", btnArea, "CENTER", 0, 0)
    f.responseSentText:SetText("Response sent")
    f.responseSentText:SetTextColor(0.3, 1, 0.3)
    f.responseSentText:Hide()

    -- Text for initiator (instead of buttons)
    f.initiatorText = btnArea:CreateFontString(nil, "OVERLAY")
    RC:SetFont(f.initiatorText, 14, "OUTLINE")
    f.initiatorText:SetPoint("CENTER", btnArea, "CENTER", 0, 0)
    f.initiatorText:SetText("You started this Ready Check")
    f.initiatorText:SetTextColor(0.3, 1, 0.3)
    f.initiatorText:Hide()

    -- Re-check button (shown after check finishes, only for leader/assist)
    f.recheckBtn = CreateFrame("Button", nil, f)
    f.recheckBtn:SetSize(120, 26)
    f.recheckBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    RC:SkinFrame(f.recheckBtn)
    RC:ApplyThemedPanel(f.recheckBtn, "button")
    local recheckText = f.recheckBtn:CreateFontString(nil, "OVERLAY")
    RC:SetFont(recheckText, 11, "OUTLINE")
    recheckText:SetPoint("CENTER")
    recheckText:SetText("Send Again")
    f.recheckBtn.Text = recheckText
    f.recheckBtn:SetScript("OnEnter", function()
        f.recheckBtn:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
    end)
    f.recheckBtn:SetScript("OnLeave", function()
        f.recheckBtn:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, 1)
    end)
    f.recheckBtn:SetScript("OnClick", function()
        local Control = RC:GetModule("Control", true)
        if Control then
            Control:DoReadyCheck()
        end
    end)
    f.recheckBtn:Hide()

    self.frame = f
    self:ApplyDisplaySettings()
    self:RefreshTheme()
end

function ReadyTracker:RefreshTheme()
    local f = self.frame
    if not f then
        return
    end
    RC:ApplyThemedWindow(f, "window")
    if f.header then
        RC:ApplyThemedHeader(f.header)
    end
    if f.summaryBand then
        RC:ApplyThemedPanel(f.summaryBand, "panel", { alpha = 0.48, borderAlpha = 0.08 })
    end
    for _, separator in ipairs(f.metricSeparators or {}) do
        separator:SetColorTexture(RC.Config.SeparatorColor.r, RC.Config.SeparatorColor.g, RC.Config.SeparatorColor.b, 0.36)
    end
    for _, header in ipairs(f.columnHeaders or {}) do
        header:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, 0.78)
    end
    if f.timerBar then
        f.timerBar:SetStatusBarColor(RC.Config.SliderFill.r, RC.Config.SliderFill.g, RC.Config.SliderFill.b, RC.Config.SliderFill.a or 1)
    end
    if f.timerText then
        f.timerText:SetTextColor(RC.Config.Selected.r, RC.Config.Selected.g, RC.Config.Selected.b, RC.Config.Selected.a or 1)
    end
    if f.tallyText then
        f.tallyText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
    end
    if f.buffSummaryText then
        f.buffSummaryText:SetTextColor(RC.Config.MutedText.r, RC.Config.MutedText.g, RC.Config.MutedText.b, RC.Config.MutedText.a or 1)
    end

    local toolButtons = { f.allBtn, f.missingOnlyBtn, f.refreshBuffBtn, f.whisperMissingBtn, f.recheckBtn }
    for _, btn in ipairs(toolButtons) do
        if btn then
            RC:ApplyThemedPanel(btn, "button")
            if btn.Text then
                btn.Text:SetTextColor(RC:GetButtonTextColor())
            end
        end
    end
    if f.readyBtn then
        f.readyBtn:SetBackdropColor(RC.Config.SuccessColor.r * 0.22, RC.Config.SuccessColor.g * 0.36, RC.Config.SuccessColor.b * 0.22, 1)
        f.readyBtn:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, math.max(0.15, RC.Config.Border.a or 0))
    end
    if f.notReadyBtn then
        f.notReadyBtn:SetBackdropColor(RC.Config.ErrorColor.r * 0.40, RC.Config.ErrorColor.g * 0.20, RC.Config.ErrorColor.b * 0.20, 1)
        f.notReadyBtn:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, math.max(0.15, RC.Config.Border.a or 0))
    end
    if f.responseSentText then
        f.responseSentText:SetTextColor(RC.Config.SuccessColor.r, RC.Config.SuccessColor.g, RC.Config.SuccessColor.b, 1)
    end
    if f.initiatorText then
        f.initiatorText:SetTextColor(RC.Config.SuccessColor.r, RC.Config.SuccessColor.g, RC.Config.SuccessColor.b, 1)
    end
    self:UpdateFilterButtons()
    local scansEnabled = self:IsConsumableScanEnabled()
    if f.refreshBuffBtn then f.refreshBuffBtn:SetShown(scansEnabled) end
    if f.whisperMissingBtn then
        f.whisperMissingBtn:SetShown(scansEnabled and self.db.readyTrackerWhisperMissing ~= false)
    end
    if f:IsShown() then self:UpdateFrame() end
end

function ReadyTracker:ShowReadyCheckFrame(duration)
    local f = self.frame
    if not f then return end
    duration = type(duration) == "number" and not IsSecret(duration) and duration or 30
    duration = math.max(1, math.min(60, duration))

    self:ApplyDisplaySettings()

    -- Reset alpha and stop any fade
    f:SetAlpha(math.max(0.45, math.min(1, tonumber(self.db.readyTrackerAlpha) or 1)))
    f:SetScript("OnUpdate", nil)
    if f.scrollFrame then
        f.scrollFrame:SetVerticalScroll(0)
    end
    if f.scrollbar then
        f.scrollbar:SetValue(0)
    end

    -- Hide re-check button for fresh check
    f.recheckBtn:Hide()
    f.responseSentText:Hide()
    f.timerText:SetText("")
    self:UpdateFilterButtons()

    -- Reset button states for new ready check
    for _, btn in ipairs(self.responseButtons) do
        btn:SetAlpha(1)
        btn:Show()
        btn.responded = false
        btn.inactive = false
        btn:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, 1)
    end

    f:Show()
    self:UpdateFrame()

    -- Show/hide buttons based on whether player is initiator
    local playerName = SafeUnitName("player")
    local isInitiator = self:NamesMatch(playerName, self.initiator)

    if isInitiator then
        for _, btn in ipairs(f.buttons) do btn:Hide() end
        f.initiatorText:Show()
    else
        for _, btn in ipairs(f.buttons) do btn:Show() end
        f.initiatorText:Hide()
    end

    -- Animate timer bar + countdown text
    f.timerBar:SetMinMaxValues(0, duration)
    f.timerBar:SetValue(duration)

    local startTime = GetTime()
    f:SetScript("OnUpdate", function()
        local elapsed  = GetTime() - startTime
        local remaining = duration - elapsed
        if remaining <= 0 then
            remaining = 0
            f:SetScript("OnUpdate", nil)
            f.timerText:SetText("")
        else
            f.timerText:SetText(math.ceil(remaining) .. "s")
        end
        f.timerBar:SetValue(remaining)
    end)
end

function ReadyTracker:HideReadyCheckFrame()
    local f = self.frame
    if not f then return end
    self:CancelConsumableRefresh()
    self.displayGeneration = (self.displayGeneration or 0) + 1
    f:SetScript("OnUpdate", nil)
    f:SetAlpha(math.max(0.45, math.min(1, tonumber(self.db.readyTrackerAlpha) or 1)))
    f:Hide()
end

function ReadyTracker:FadeOutFrame()
    local f = self.frame
    if not f or not f:IsShown() then return end

    local alpha = f:GetAlpha() or 1
    f:SetScript("OnUpdate", function(self, elapsed)
        alpha = alpha - (elapsed * 2) -- Fade over 0.5 seconds
        if alpha <= 0 then
            alpha = 0
            f:SetScript("OnUpdate", nil)
            f:Hide()
            ReadyTracker:CancelConsumableRefresh()
            f:SetAlpha(math.max(0.45, math.min(1, tonumber(ReadyTracker.db.readyTrackerAlpha) or 1)))
        else
            f:SetAlpha(alpha)
        end
    end)
end

-- Every tracked member, problems first (offline/dead, declined, waiting,
-- preparation issues, then fully prepared). Nobody is ever filtered out:
-- the list must show the whole raid for the whole check.
function ReadyTracker:GetDisplayNames(summary)
    local durabilityByName = summary and summary.durability or {}
    local names = {}
    for name in pairs(self.responses or {}) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b)
        local priorityA = self:GetEntryPriority(self.responses[a], self.consumableData[a], durabilityByName[a])
        local priorityB = self:GetEntryPriority(self.responses[b], self.consumableData[b], durabilityByName[b])
        if priorityA ~= priorityB then return priorityA < priorityB end
        return a < b
    end)
    return names
end

-- Grows to fit every row, up to the visible screen height (in this frame's
-- scaled units); past that the list scrolls.
function ReadyTracker:GetFrameHeight(rowCount, screenHeight, scale)
    local wanted = math.max(MIN_FRAME_HEIGHT, FRAME_CHROME_HEIGHT + (rowCount or 0) * ROW_HEIGHT)
    local cap = MIN_ROSTER_CAP
    if type(screenHeight) == "number" and screenHeight > 0 then
        cap = math.max(cap, screenHeight / (tonumber(scale) or 1) - SCREEN_MARGIN)
    end
    return math.min(wanted, cap)
end

function ReadyTracker:UpdateFrame()
    local f = self.frame
    if not f then return end

    local leadTools = RC:GetModule("RaidLeadTools", true)
    local summary = self:BuildReadinessSummary(function(name)
        local data = self.consumableData and self.consumableData[name]
        if data and type(data.previewDurability) == "number" then
            return data.previewDurability
        end
        return leadTools and leadTools.GetDurabilityForName and leadTools:GetDurabilityForName(name) or nil
    end)
    f.tallyText:SetText(string.format("READY  %d / %d", summary.ready, summary.total))
    f.waitingText:SetText(string.format("WAITING  %d", summary.waiting))
    f.notReadyText:SetText(string.format("NOT READY  %d", summary.notReady))
    f.tallyText:SetTextColor(RC.Config.SuccessColor.r, RC.Config.SuccessColor.g, RC.Config.SuccessColor.b, 1)
    f.waitingText:SetTextColor(1, 0.78, 0.25, 1)
    f.notReadyText:SetTextColor(RC.Config.ErrorColor.r, RC.Config.ErrorColor.g, RC.Config.ErrorColor.b, 1)
    if self.buffScanActive then
        f.buffSummaryText:SetText("ISSUES  ...")
        f.buffSummaryText:SetTextColor(1, 0.78, 0.25, 1)
    else
        f.buffSummaryText:SetText(string.format("ISSUES  %d", summary.prepIssues))
        if summary.prepIssues > 0 then
            f.buffSummaryText:SetTextColor(RC.Config.ErrorColor.r, RC.Config.ErrorColor.g, RC.Config.ErrorColor.b, 1)
        else
            f.buffSummaryText:SetTextColor(RC.Config.SuccessColor.r, RC.Config.SuccessColor.g, RC.Config.SuccessColor.b, 1)
        end
    end
    self:UpdateFilterButtons()
    local scansEnabled = self:IsConsumableScanEnabled()
    if f.refreshBuffBtn then f.refreshBuffBtn:SetShown(scansEnabled) end
    if f.whisperMissingBtn then
        f.whisperMissingBtn:SetShown(scansEnabled and self.db.readyTrackerWhisperMissing ~= false)
    end

    -- Hide old rows
    for _, row in ipairs(f.rows) do
        row:Hide()
    end

    local i = 0
    local issuesView = RC.db.profile.readyTrackerMissingOnly == true

    for _, name in ipairs(self:GetDisplayNames(summary)) do
        local data = self.consumableData[name] or {}
        local response = self.responses[name]
        local durability = summary.durability[name]
        i = i + 1

        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, f.content, "BackdropTemplate")
            row:SetSize(f.content:GetWidth() - 6, ROW_HEIGHT)
            RC:SkinFrame(row)
            RC:ApplyThemedPanel(row, "panel", { alpha = 0.26, borderAlpha = 0.04 })

            -- Name
            row.nameText = row:CreateFontString(nil, "OVERLAY")
            RC:SetFont(row.nameText, 11, "OUTLINE")
            row.nameText:SetPoint("LEFT", 10, 0)
            row.nameText:SetWidth(126)
            row.nameText:SetJustifyH("LEFT")
            if row.nameText.SetWordWrap then row.nameText:SetWordWrap(false) end

            -- Buff indicators (using custom styled frames and icons)
            row.buffs = {}
            row.buffFrames = {}
            local xPos = {163, 205, 247, 289}
            for j = 1, 4 do
                local frame = CreateFrame("Frame", nil, row, "BackdropTemplate")
                frame:SetSize(16, 16)
                frame:SetPoint("CENTER", row, "TOPLEFT", xPos[j], -(ROW_HEIGHT / 2))
                RC:SkinFrame(frame)

                local ind = frame:CreateTexture(nil, "OVERLAY")
                ind:SetAllPoints(frame)
                ind:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.buffs[j] = ind
                row.buffFrames[j] = frame
            end

            -- Status icon
            row.statusIcon = row:CreateTexture(nil, "OVERLAY")
            row.statusIcon:SetSize(14, 14)
            row.statusIcon:SetPoint("CENTER", row, "TOPLEFT", 380, -(ROW_HEIGHT / 2))
            row.statusIcon:Hide()

            row.durabilityText = row:CreateFontString(nil, "OVERLAY")
            RC:SetFont(row.durabilityText, 10, "OUTLINE")
            row.durabilityText:SetPoint("CENTER", row, "TOPLEFT", 338, -(ROW_HEIGHT / 2))
            row.durabilityText:SetWidth(50)
            row.durabilityText:SetJustifyH("CENTER")

            -- Status text (fallback)
            row.statusText = row:CreateFontString(nil, "OVERLAY")
            RC:SetFont(row.statusText, 9, "OUTLINE")
            -- Icon + label sit together under the centred "Status" header and
            -- stay inside the row's right edge.
            row.statusText:SetPoint("LEFT", row, "TOPLEFT", 391, -(ROW_HEIGHT / 2))
            row.statusText:SetWidth(52)
            row.statusText:SetJustifyH("LEFT")
            row.statusText:SetWordWrap(false)

            table.insert(f.rows, row)
        end

        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 3, -((i - 1) * ROW_HEIGHT))
        row:SetBackdropColor(
            RC.Config.SurfaceBg.r,
            RC.Config.SurfaceBg.g,
            RC.Config.SurfaceBg.b,
            i % 2 == 0 and 0.34 or 0.22
        )
        row:SetAlpha((issuesView and not self:HasDisplayIssue(response, data, durability)) and SETTLED_ROW_ALPHA or 1)
        row:Show()

        -- Name color
        local r, g, b = 1, 1, 1
        local classColor = data.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.classFile]
        if classColor then
            r, g, b = classColor.r, classColor.g, classColor.b
        end
        if data.connected == false then
            r, g, b = 0.48, 0.48, 0.48
        end
        row.nameText:SetText(name)
        row.nameText:SetTextColor(r, g, b)

        -- Buff indicators (using actual icons and desaturation)
        local function SetBuff(ind, iconFrame, iconData, defaultIcon)
            if iconData then
                ind:SetTexture(iconData)
                ind:SetDesaturated(false)
                ind:SetVertexColor(1, 1, 1)
                iconFrame:SetBackdropBorderColor(RC.Config.SuccessColor.r, RC.Config.SuccessColor.g, RC.Config.SuccessColor.b, 0.38)
            else
                ind:SetTexture(defaultIcon)
                ind:SetDesaturated(true)
                ind:SetVertexColor(0.42, 0.42, 0.42)
                if self:IsConsumableScanEnabled() and data.scanned then
                    iconFrame:SetBackdropBorderColor(RC.Config.ErrorColor.r, RC.Config.ErrorColor.g, RC.Config.ErrorColor.b, 0.62)
                else
                    iconFrame:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, 0.18)
                end
            end
        end

        SetBuff(row.buffs[1], row.buffFrames[1], data.food, 134062)
        SetBuff(row.buffs[2], row.buffFrames[2], data.flask, 132805)
        SetBuff(row.buffs[3], row.buffFrames[3], data.rune, 134419)
        SetBuff(row.buffs[4], row.buffFrames[4], data.weaponMain or data.shamanEnchant, 135129)

        if row.durabilityText then
            if durability then
                row.durabilityText:SetText(durability .. "%")
                if durability <= (RC.db.profile.durabilityWarnThreshold or 30) then
                    row.durabilityText:SetTextColor(1, 0.25, 0.18, 1)
                elseif durability <= 60 then
                    row.durabilityText:SetTextColor(1, 0.78, 0.25, 1)
                else
                    row.durabilityText:SetTextColor(0.35, 1, 0.35, 1)
                end
            else
                row.durabilityText:SetText("--")
                row.durabilityText:SetTextColor(0.45, 0.45, 0.45, 1)
            end
        end

        -- Status icon and label
        if data.connected == false then
            row.statusIcon:Hide()
            row.statusText:SetText("OFFLINE")
            row.statusText:SetTextColor(0.55, 0.55, 0.55, 1)
        elseif data.dead == true then
            row.statusIcon:Hide()
            row.statusText:SetText("DEAD")
            row.statusText:SetTextColor(RC.Config.ErrorColor.r, RC.Config.ErrorColor.g, RC.Config.ErrorColor.b, 1)
        elseif response == "ready" then
            row.statusText:SetText("READY")
            row.statusText:SetTextColor(RC.Config.SuccessColor.r, RC.Config.SuccessColor.g, RC.Config.SuccessColor.b, 1)
            row.statusIcon:SetTexture(RC.Icons.Texture)
            row.statusIcon:SetTexCoord(unpack(RC.Icons.GreenCheck))
            row.statusIcon:Show()
        elseif response == "notready" then
            row.statusText:SetText("NO")
            row.statusText:SetTextColor(RC.Config.ErrorColor.r, RC.Config.ErrorColor.g, RC.Config.ErrorColor.b, 1)
            row.statusIcon:SetTexture(RC.Icons.Texture)
            row.statusIcon:SetTexCoord(unpack(RC.Icons.RedX))
            row.statusIcon:Show()
        else
            row.statusText:SetText("WAIT")
            row.statusText:SetTextColor(1, 0.78, 0.25, 1)
            row.statusIcon:SetTexture(RC.Icons.Texture)
            row.statusIcon:SetTexCoord(unpack(RC.Icons.YellowQuestion))
            row.statusIcon:Show()
        end
    end

    local screenHeight = UIParent and UIParent.GetHeight and UIParent:GetHeight() or nil
    f:SetHeight(self:GetFrameHeight(i, screenHeight, f:GetScale()))

    local contentHeight = math.max(i * ROW_HEIGHT, 1)
    f.content:SetHeight(contentHeight)
    if f.scrollFrame and f.content.SetWidth then
        f.content:SetWidth(f.scrollFrame:GetWidth() or 446)
    end
    if f.scrollbar and f.scrollbar.Update and f.scrollFrame then
        f.scrollbar:Update(contentHeight, f.scrollFrame:GetHeight() or 1)
    end
end

function ReadyTracker:BeginLayoutMode()
    if InCombatLockdown and InCombatLockdown() then
        return false
    end
    self._layoutModeActive = true
    self._layoutPreviewInterrupted = nil
    if self.readyCheckActive then
        self._layoutPreviewState = { live = true }
        self.frame:Show()
        return true
    end

    self:CancelConsumableRefresh()
    self._layoutPreviewState = {
        wasShown = self.frame and self.frame:IsShown() or false,
        responses = self.responses,
        consumableData = self.consumableData,
        readyCheckActive = self.readyCheckActive,
        initiator = self.initiator,
    }
    self.responses = {
        ["Auralis-Realm"] = "ready",
        ["Nymara-Realm"] = "notready",
        ["Solenne-Realm"] = false,
        ["Kharos-Realm"] = "ready",
    }
    self.consumableData = {
        ["Auralis-Realm"] = { classFile = "PRIEST", connected = true, dead = false, scanned = true, food = 134062, flask = 132805, rune = 134419, weaponMain = 135129, previewDurability = 94 },
        ["Nymara-Realm"] = { classFile = "DRUID", connected = true, dead = false, scanned = true, food = 134062, flask = false, rune = false, weaponMain = 135129, previewDurability = 22 },
        ["Solenne-Realm"] = { classFile = "SHAMAN", connected = true, dead = false, scanned = true, food = 134062, flask = 132805, rune = 134419, weaponMain = 135129, previewDurability = 78 },
        ["Kharos-Realm"] = { classFile = "WARRIOR", connected = false, dead = false, scanned = true, food = 134062, flask = 132805, rune = 134419, weaponMain = 135129, previewDurability = 63 },
    }
    self.readyCheckActive = false
    self.initiator = nil
    self.displayGeneration = (self.displayGeneration or 0) + 1
    self.frame:SetScript("OnUpdate", nil)
    self:ApplyDisplaySettings()
    self.frame.timerText:SetText("")
    self.frame.timerBar:SetMinMaxValues(0, 30)
    self.frame.timerBar:SetValue(24)
    self.frame.recheckBtn:Hide()
    self.frame.responseSentText:Hide()
    for _, button in ipairs(self.responseButtons or {}) do button:Hide() end
    self.frame.initiatorText:SetText("Layout preview")
    self.frame.initiatorText:Show()
    self.frame:Show()
    self:UpdateFrame()
    return true
end

function ReadyTracker:EndLayoutMode()
    local state = self._layoutPreviewState
    self._layoutPreviewState = nil
    self._layoutModeActive = nil
    self.frame.initiatorText:SetText("You started this Ready Check")
    if not state or state.live or self._layoutPreviewInterrupted then
        self._layoutPreviewInterrupted = nil
        self:UpdateFrame()
        return
    end

    self.responses = state.responses or {}
    self.consumableData = state.consumableData or {}
    self.readyCheckActive = state.readyCheckActive == true
    self.initiator = state.initiator
    if state.wasShown then
        self.frame:Show()
        self:UpdateFrame()
    else
        self:HideReadyCheckFrame()
    end
end

function ReadyTracker:PreviewLayout()
    local layoutMode = RC:GetModule("LayoutMode", true)
    if layoutMode and layoutMode.SetActive then
        return layoutMode:SetActive(true)
    end
    return false
end

function ReadyTracker:ApplySettings()
    self.db = RC.db.profile
    if not self:IsConsumableScanEnabled() then
        self:CancelConsumableRefresh()
    end
    self:ApplyDisplaySettings()
    self:UpdateFrame()
end

function ReadyTracker:ReportResults(afk, notReady)
    if #afk == 0 and #notReady == 0 then
        RC:Print("Everyone is ready!")
        return
    end

    -- Only report NOT READY to chat (AFK is already printed separately)
    if #notReady > 0 then
        local msg = "NOT READY: " .. table.concat(notReady, ", ")
        RC:Print(msg)

        -- Only the player who started the check announces, so a raid full of
        -- RaidControl users doesn't post the same line many times.
        local startedByMe = false
        if self.initiator and UnitIsUnit then
            local ok, same = pcall(UnitIsUnit, self.initiator, "player")
            startedByMe = ok and same == true
        end
        if self.db.announceReadySlackers and startedByMe then
            local channel = RC:GetGroupChannel()
            if channel then
                RC:SendChat("RC: " .. msg, channel)
            end
        end
    end
end
