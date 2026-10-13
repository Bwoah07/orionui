local _, ns = ...
local RC = ns.RC
local L = RC.L
local Roles = RC:NewModule("Roles", "AceEvent-3.0")

local function CancelTimer(timer)
    if timer and timer.Cancel then
        timer:Cancel()
    end
end

-- Melee spec IDs (locale-independent)
local MeleeSpecIDs = {
    [66]  = true, -- Paladin: Protection
    [70]  = true, -- Paladin: Retribution
    [103] = true, -- Druid: Feral
    [104] = true, -- Druid: Guardian
    [255] = true, -- Hunter: Survival
    [263] = true, -- Shaman: Enhancement
    [268] = true, -- Monk: Brewmaster
    [269] = true, -- Monk: Windwalker
}

local PureMeleeClasses = {
    ["WARRIOR"] = true,
    ["DEATHKNIGHT"] = true,
    ["ROGUE"] = true,
    ["DEMONHUNTER"] = true,
}

local PureRangedClasses = {
    ["MAGE"] = true,
    ["PRIEST"] = true,
    ["WARLOCK"] = true,
    ["EVOKER"] = true,
}

-- Determine if a unit is Melee or Ranged DPS
local function IsMeleeDPS(unit)
    local _, class = UnitClass(unit)
    if PureMeleeClasses[class] then return true end
    if PureRangedClasses[class] then return false end

    -- Use spec ID for accurate hybrid class detection
    local specID
    if UnitIsUnit(unit, "player") then
        specID = RC:GetPlayerSpecializationInfo()
    else
        specID = RC:GetInspectSpecID(unit)
    end

    if specID then
        return MeleeSpecIDs[specID] == true
    end

    -- Fallback: hybrid classes (PALADIN, DRUID, SHAMAN, HUNTER, MONK) default to ranged
    return false
end

function Roles:OnInitialize()
    -- Initialize the Roles module
end

function Roles:OnEnable()
    self:CreateRoleFrame()
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "QueueRoleUpdate")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "QueueRoleUpdate")
    self:UpdateRoles()
    -- Register with menu system (at the BOTTOM)
    RC:RegisterMenuModule({
        name = "Roles",
        order = 100,
        frame = self.frame,
        isVisible = function() return false end
    })
end

function Roles:OnDisable()
    CancelTimer(self.updateTimer)
    self.updateTimer = nil
end

function Roles:QueueRoleUpdate()
    CancelTimer(self.updateTimer)
    self.updateTimer = nil

    local function Update()
        self.updateTimer = nil
        self:UpdateRoles()
    end

    if C_Timer and C_Timer.NewTimer then
        self.updateTimer = C_Timer.NewTimer(0.25, Update)
    elseif C_Timer and C_Timer.After then
        C_Timer.After(0.25, Update)
    else
        Update()
    end
end

function Roles:CreateRoleFrame()
    if not RC.Menu then return end

    local frame = CreateFrame("Frame", nil, RC.Menu)
    local rowHeight = 24
    frame:SetSize(200, rowHeight)
    self.frame = frame

    -- Role data with colored counts
    local roles = {
        { key = "TANK",   color = { 0.3, 0.6, 1 } },   -- Blue
        { key = "HEALER", color = { 0.3, 0.9, 0.3 } }, -- Green
        { key = "DPS",    color = { 0.9, 0.3, 0.3 } }, -- Red
    }

    frame.roleFrames = {}
    local iconSize = 18
    local iconGap = 2
    local countWidth = 14
    local itemWidth = iconSize + iconGap + countWidth
    local spacing = 8
    local totalWidth = (#roles * itemWidth) + ((#roles - 1) * spacing)
    local startX = (200 - totalWidth) / 2

    for i, roleData in ipairs(roles) do
        local xOffset = startX + (i - 1) * (itemWidth + spacing)

        -- Create button for interaction/tooltip
        local roleBtn = CreateFrame("Button", nil, frame)
        roleBtn:SetSize(itemWidth, rowHeight)
        roleBtn:SetPoint("LEFT", frame, "LEFT", xOffset, 0)

        -- Role icon
        local icon = roleBtn:CreateTexture(nil, "OVERLAY")
        icon:SetTexture(RC.RoleIcons.Texture)
        icon:SetTexCoord(unpack(RC.RoleIcons[roleData.key]))
        icon:SetSize(iconSize, iconSize)
        icon:SetPoint("LEFT", roleBtn, "LEFT", 0, 0)
        icon:SetVertexColor(1, 1, 1, 1)

        -- Count text
        local count = roleBtn:CreateFontString(nil, "OVERLAY")
        RC:SetFont(count, 12, "OUTLINE")
        count:SetPoint("LEFT", icon, "RIGHT", iconGap, 0)
        count:SetTextColor(roleData.color[1], roleData.color[2], roleData.color[3])
        count:SetText("0")

        -- Tooltip Handling
        roleBtn:SetScript("OnEnter", function(self)
            Roles:ShowTooltip(self, roleData.key)
        end)
        roleBtn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        frame.roleFrames[roleData.key] = { icon = icon, count = count }
    end
end

function Roles:ShowTooltip(frame, roleFilter)
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    GameTooltip:ClearLines()

    local roleName = L["Unknown"]
    local rc = RC.Config.RoleColors
    local titleR, titleG, titleB = 1, 1, 1
    if roleFilter == "TANK" then
        roleName = L["Tanks"]
        titleR, titleG, titleB = rc.TANK.r, rc.TANK.g, rc.TANK.b
    elseif roleFilter == "HEALER" then
        roleName = L["Healers"]
        titleR, titleG, titleB = rc.HEALER.r, rc.HEALER.g, rc.HEALER.b
    elseif roleFilter == "DPS" or roleFilter == "DAMAGER" then
        roleName = L["Damage"]
        titleR, titleG, titleB = rc.DPS.r, rc.DPS.g, rc.DPS.b
    end
    GameTooltip:AddLine(roleName, titleR, titleG, titleB)

    local units = {}
    if IsInRaid() then
        for i = 1, 40 do table.insert(units, "raid" .. i) end
    elseif IsInGroup() then
        table.insert(units, "player")
        for i = 1, 4 do table.insert(units, "party" .. i) end
    else
        table.insert(units, "player")
    end

    local meleeDPS = {}
    local rangedDPS = {}
    local tanks = {}
    local healers = {}

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local role = UnitGroupRolesAssigned(unit)
            -- Solo override
            if not IsInGroup() then
                local _, _, _, _, specRole = RC:GetPlayerSpecializationInfo()
                if specRole then
                    role = specRole
                end
            end

            if role == roleFilter or (roleFilter == "DPS" and role == "DAMAGER") then
                local name = UnitName(unit)
                local _, class = UnitClass(unit)
                local color = RAID_CLASS_COLORS[class]
                local text = name
                if color then
                    text = string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, name)
                end

                if role == "TANK" then
                    table.insert(tanks, text)
                elseif role == "HEALER" then
                    table.insert(healers, text)
                elseif role == "DAMAGER" then
                    if IsMeleeDPS(unit) then
                        table.insert(meleeDPS, text)
                    else
                        table.insert(rangedDPS, text)
                    end
                end
            end
        end
    end

    if roleFilter == "TANK" then
        for _, v in ipairs(tanks) do GameTooltip:AddLine(v) end
    elseif roleFilter == "HEALER" then
        for _, v in ipairs(healers) do GameTooltip:AddLine(v) end
    elseif roleFilter == "DPS" or roleFilter == "DAMAGER" then
        if #meleeDPS > 0 then
            GameTooltip:AddLine(L["Melee"], 0.80, 0.65, 0.45)
            for _, v in ipairs(meleeDPS) do GameTooltip:AddLine(v) end
        end
        if #rangedDPS > 0 then
            if #meleeDPS > 0 then GameTooltip:AddLine(" ") end
            GameTooltip:AddLine(L["Ranged"], 0.55, 0.75, 1.00)
            for _, v in ipairs(rangedDPS) do GameTooltip:AddLine(v) end
        end
    end

    GameTooltip:Show()
end

function Roles:UpdateRoles()
    if not self.frame or not self.frame.roleFrames then return end

    local tanks, healers, dps = 0, 0, 0
    local raidDemo = RC.GetModule and RC:GetModule("RaidDemo", true)
    if raidDemo and raidDemo.IsActive and raidDemo:IsActive() then
        local scenario = raidDemo:GetScenario()
        tanks, healers, dps = scenario.tanks, scenario.healers, scenario.damage
        self.frame.roleFrames["TANK"].count:SetText(tanks)
        self.frame.roleFrames["HEALER"].count:SetText(healers)
        self.frame.roleFrames["DPS"].count:SetText(dps)
        if RC.UpdateMenuRoleSummary then
            RC:UpdateMenuRoleSummary(tanks, healers, dps)
        end
        return
    end

    if IsInRaid() then
        for i = 1, 40 do
            local role = UnitGroupRolesAssigned("raid" .. i)
            if role == "TANK" then
                tanks = tanks + 1
            elseif role == "HEALER" then
                healers = healers + 1
            elseif role == "DAMAGER" then
                dps = dps + 1
            end
        end
    elseif IsInGroup() then
        for i = 1, 4 do
            local role = UnitGroupRolesAssigned("party" .. i)
            if role == "TANK" then
                tanks = tanks + 1
            elseif role == "HEALER" then
                healers = healers + 1
            elseif role == "DAMAGER" then
                dps = dps + 1
            end
        end
        local role = UnitGroupRolesAssigned("player")
        if role == "TANK" then
            tanks = tanks + 1
        elseif role == "HEALER" then
            healers = healers + 1
        elseif role == "DAMAGER" then
            dps = dps + 1
        end
    else
        -- Solo: Use specialization to determine role
        local _, _, _, _, role = RC:GetPlayerSpecializationInfo()
        if role == "TANK" then
            tanks = 1
        elseif role == "HEALER" then
            healers = 1
        elseif role == "DAMAGER" then
            dps = 1
        end
    end

    -- Update counts
    self.frame.roleFrames["TANK"].count:SetText(tanks)
    self.frame.roleFrames["HEALER"].count:SetText(healers)
    self.frame.roleFrames["DPS"].count:SetText(dps)

    if RC.UpdateMenuRoleSummary then
        RC:UpdateMenuRoleSummary(tanks, healers, dps)
    end
end
