local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
local RaidDemo = RC:NewModule("RaidDemo", "AceEvent-3.0")

local DEMO_SCENARIO = {
    name = L["Mythic Raid Preview"],
    size = 20,
    tanks = 2,
    healers = 4,
    damage = 14,
}

local DEMO_HEALERS = {
    { name = "Auralis", class = "PRIEST", offset = 0 },
    { name = "Nymara", class = "DRUID", offset = 7 },
    { name = "Solenne", class = "SHAMAN", offset = 14 },
    { name = "Cremina", class = "PALADIN", offset = 21 },
}

local DEMO_RAIDERS = {
    { name = "Auralis-Realm", class = "PRIEST" },
    { name = "Nymara-Realm", class = "DRUID" },
    { name = "Solenne-Realm", class = "SHAMAN" },
    { name = "Cremina-Realm", class = "PALADIN" },
    { name = "Kharos-Realm", class = "WARRIOR" },
    { name = "Veyra-Realm", class = "DEATHKNIGHT" },
    { name = "Ashfall-Realm", class = "MAGE" },
    { name = "Belara-Realm", class = "EVOKER" },
    { name = "Cyran-Realm", class = "ROGUE" },
    { name = "Daelin-Realm", class = "HUNTER" },
    { name = "Elowen-Realm", class = "WARLOCK" },
    { name = "Fenris-Realm", class = "DEMONHUNTER" },
    { name = "Galen-Realm", class = "MONK" },
    { name = "Hestia-Realm", class = "MAGE" },
    { name = "Ilyra-Realm", class = "PRIEST" },
    { name = "Joren-Realm", class = "PALADIN" },
    { name = "Kaelis-Realm", class = "HUNTER" },
    { name = "Lyra-Realm", class = "DRUID" },
    { name = "Merek-Realm", class = "WARRIOR" },
    { name = "Nyx-Realm", class = "WARLOCK" },
}

local DEMO_SURFACES = {
    { module = "RaidLeadTools", start = "BeginLayoutMode", stop = "EndLayoutMode", startArg = true },
    { module = "ReadyTracker", start = "BeginLayoutMode", stop = "EndLayoutMode" },
    { module = "TankAssist", start = "BeginLayoutMode", stop = "EndLayoutMode" },
    { module = "NoteReminders", start = "BeginLayoutMode", stop = "EndLayoutMode" },
}

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

function RaidDemo:OnInitialize()
    self.active = false
    self.startedSurfaces = {}
    self.tick = 0
end

function RaidDemo:OnEnable()
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
end

function RaidDemo:IsActive()
    return self.active == true
end

function RaidDemo:GetScenario()
    return DEMO_SCENARIO
end

local function TriangleMana(step, offset)
    local halfPeriod = 18
    local phase = (step + offset) % (halfPeriod * 2)
    local distance = phase <= halfPeriod and phase or ((halfPeriod * 2) - phase)
    local percent = 96 - ((96 - 12) * (distance / halfPeriod))
    return math.max(0, math.min(100, math.floor(percent + 0.5))), phase
end

function RaidDemo:BuildHealerSnapshot()
    local healers = {}
    for _, healer in ipairs(DEMO_HEALERS) do
        local percent, phase = TriangleMana(self.tick or 0, healer.offset)
        healers[#healers + 1] = {
            name = healer.name,
            class = healer.class,
            connected = true,
            percent = percent,
            drinking = phase > 18 and phase <= 24,
        }
    end
    return healers
end

local function FormatDemoTime(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function RaidDemo:UpdateRaidStatus()
    local leadTools = RC:GetModule("RaidLeadTools", true)
    if not leadTools then
        return
    end
    if leadTools.ApplyHealerManaDisplay then
        leadTools:ApplyHealerManaDisplay(self:BuildHealerSnapshot())
    end

    local frame = leadTools.bresFrame
    if not frame then
        return
    end
    local cycle = (self.tick or 0) % 24
    local current = cycle < 18 and 1 or 2
    local maximum = 2
    local remaining = current < maximum and (18 - cycle) or 0
    local now = GetTime and GetTime() or 0
    frame.currentCharges = current
    frame.maxCharges = maximum
    frame.rechargeStart = current < maximum and (now - cycle) or nil
    frame.rechargeDuration = current < maximum and 18 or nil
    if leadTools.FormatBattleResStatusValues and frame.count then
        local _, r, g, b = leadTools:FormatBattleResStatusValues(current, maximum)
        frame.count:SetText(tostring(current))
        frame.count:SetTextColor(r or 1, g or 1, b or 1, 1)
        if frame.iconCount then
            frame.iconCount:SetText(tostring(current))
            frame.iconCount:SetTextColor(r or 1, g or 1, b or 1, 1)
        end
    end
    if frame.timer then
        frame.timer:SetText(remaining > 0 and FormatDemoTime(remaining) or L["READY"])
    end
    if frame.cooldown then
        if remaining > 0 and frame.cooldown.SetCooldown then
            frame.cooldown:SetCooldown(frame.rechargeStart, frame.rechargeDuration)
        elseif frame.cooldown.Clear then
            frame.cooldown:Clear()
        end
    end
    if leadTools.ApplyBattleResDisplaySettings then
        leadTools:ApplyBattleResDisplaySettings()
    end
    if frame.Show then
        frame:Show()
    end
end

function RaidDemo:UpdateReadyTracker()
    local ready = RC:GetModule("ReadyTracker", true)
    if not ready or not ready.frame then
        return
    end
    -- A real ready check owns the frame until it finishes; never overwrite
    -- live responses with demo raiders (they would be announced to the raid).
    if ready.readyCheckActive or ready._layoutPreviewInterrupted then
        return
    end
    local cycle = (self.tick or 0) % 20
    local stage = math.floor(cycle / 4)
    local readyCount = math.min(#DEMO_RAIDERS, stage * 5)
    local responses = {}
    local consumables = {}
    for index, raider in ipairs(DEMO_RAIDERS) do
        if index <= readyCount then
            responses[raider.name] = "ready"
        elseif index == readyCount + 1 then
            responses[raider.name] = "notready"
        else
            responses[raider.name] = false
        end
        local nymara = raider.name == "Nymara-Realm"
        consumables[raider.name] = {
            classFile = raider.class,
            connected = not (index == 20 and stage < 3),
            dead = index == 19 and stage == 1,
            scanned = true,
            food = 134062,
            flask = not (nymara and stage < 2) and 132805 or false,
            rune = not (nymara and stage < 3) and 134419 or false,
            weaponMain = 135129,
            previewDurability = nymara and stage < 4 and 22 or math.max(42, 98 - index),
        }
    end
    ready.responses = responses
    ready.consumableData = consumables
    if ready.frame.timerBar then
        ready.frame.timerBar:SetValue(20 - cycle)
    end
    if ready.frame.timerText then
        ready.frame.timerText:SetText(string.format("%ds", 20 - cycle))
    end
    if ready.frame.initiatorText then
        ready.frame.initiatorText:SetText(L["Demo ready check"])
        ready.frame.initiatorText:Show()
    end
    if ready.UpdateFrame then
        ready:UpdateFrame()
    end
end

function RaidDemo:UpdateTankAssist()
    local tank = RC:GetModule("TankAssist", true)
    if not tank then
        return
    end
    local cycle = (self.tick or 0) % 20
    local playerTanking = cycle >= 10
    local stacks = math.min(5, 1 + math.floor((cycle % 10) / 2))
    local urgent = stacks >= 5
    local status = tank.statusFrame
    if status then
        status.name:SetText(string.format(L["Co-tank: %s"], "Kharos"))
        status.target:SetText(playerTanking and L["YOU TANK"] or L["CO-TANK"])
        status.target:SetTextColor(playerTanking and 0.35 or 1, playerTanking and 1 or 0.72, playerTanking and 0.35 or 0.2, 1)
        status.detail:SetText(string.format(L["Blackening Wounds: %d / 5"], stacks))
        status:Show()
    end
    local alert = tank.frame
    if alert then
        if urgent then
            alert.title:SetText(playerTanking and L["SWAP OUT"] or L["TAUNT NOW"])
            alert.detail:SetText(playerTanking and string.format(L["You reached %d stacks."], stacks)
                or string.format(L["%s reached %d stacks."], "Kharos", stacks))
        else
            alert.title:SetText(string.format(L["NEXT SWAP AT 5  |  %d"], stacks))
            alert.detail:SetText(playerTanking and L["You are holding the boss."]
                or string.format(L["%s is holding the boss."], "Kharos"))
        end
        alert:Show()
    end
end

function RaidDemo:UpdateNoteReminders()
    if (self.tick or 0) == 0 or (self.tick % 12) ~= 0 then
        return
    end
    local reminders = RC:GetModule("NoteReminders", true)
    if reminders and reminders.BeginLayoutMode then
        reminders:BeginLayoutMode()
    end
end

function RaidDemo:UpdateScenario()
    if not self:IsActive() then
        return false
    end
    for _, callback in ipairs({
        self.UpdateRaidStatus,
        self.UpdateReadyTracker,
        self.UpdateTankAssist,
        self.UpdateNoteReminders,
    }) do
        pcall(callback, self)
    end
    return true
end

function RaidDemo:Advance()
    if not self:IsActive() then
        return false
    end
    self.tick = (self.tick or 0) + 1
    return self:UpdateScenario()
end

function RaidDemo:CancelTicker()
    if self.ticker and self.ticker.Cancel then
        self.ticker:Cancel()
    end
    self.ticker = nil
end

function RaidDemo:StartTicker()
    self:CancelTicker()
    self.tick = 0
    self:UpdateScenario()
    if C_Timer and C_Timer.NewTicker then
        self.ticker = C_Timer.NewTicker(1, function()
            self:Advance()
        end)
    end
end

function RaidDemo:CanStart()
    if IsInCombat() then
        return false, L["Raid demo mode is unavailable during combat."]
    end
    local layoutMode = RC:GetModule("LayoutMode", true)
    if layoutMode and layoutMode.IsActive and layoutMode:IsActive() then
        return false, L["Lock the UI before starting raid demo mode."]
    end
    return true
end

function RaidDemo:Start(silent)
    if self:IsActive() then
        return true
    end

    local canStart, reason = self:CanStart()
    if not canStart then
        if not silent and RC.Print then
            RC:Print(reason)
        end
        return false
    end

    self.startedSurfaces = {}
    self.active = true
    for _, surface in ipairs(DEMO_SURFACES) do
        local module = RC:GetModule(surface.module, true)
        local callback = module and module[surface.start]
        if callback then
            local ok, result = pcall(callback, module, surface.startArg)
            if ok and result ~= false then
                self.startedSurfaces[#self.startedSurfaces + 1] = surface
            end
        end
    end

    if #self.startedSurfaces == 0 then
        self.active = false
        if not silent and RC.Print then
            RC:Print(L["Raid demo mode could not find any visual surfaces to preview."])
        end
        return false
    end

    if RC.UpdateMenuRoleSummary then
        local scenario = self:GetScenario()
        RC:UpdateMenuRoleSummary(scenario.tanks, scenario.healers, scenario.damage)
    end
    self:StartTicker()
    if not silent and RC.Print then
        RC:Print(L["Raid demo mode started. Visual preview only; no raid actions are sent."])
    end
    return true
end

function RaidDemo:Stop(silent)
    if not self:IsActive() and #(self.startedSurfaces or {}) == 0 then
        return true
    end

    self:CancelTicker()
    self.active = false
    for index = #(self.startedSurfaces or {}), 1, -1 do
        local surface = self.startedSurfaces[index]
        local module = RC:GetModule(surface.module, true)
        local callback = module and module[surface.stop]
        if callback then
            pcall(callback, module)
        end
    end
    self.startedSurfaces = {}

    local roles = RC:GetModule("Roles", true)
    if roles and roles.UpdateRoles then
        pcall(roles.UpdateRoles, roles)
    end
    if not silent and RC.Print then
        RC:Print(L["Raid demo mode stopped. Live raid displays restored."])
    end
    return true
end

function RaidDemo:SetActive(active, silent)
    if active then
        return self:Start(silent)
    end
    return self:Stop(silent)
end

function RaidDemo:Toggle()
    return self:SetActive(not self:IsActive())
end

function RaidDemo:OnDisable()
    self:Stop(true)
end

function RaidDemo:PLAYER_REGEN_DISABLED()
    self:Stop(true)
end

function RC:IsRaidDemoActive()
    local demo = self:GetModule("RaidDemo", true)
    return demo and demo:IsActive() or false
end
