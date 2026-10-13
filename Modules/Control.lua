local _, ns = ...
local RC = ns.RC
local L = RC.L
local Control = RC:NewModule("Control", "AceEvent-3.0")

local CONTROL_MENU_WIDTH = 216
local CONTROL_BUTTON_WIDTH = 50
local CONTROL_BUTTON_HEIGHT = 28
local CONTROL_BUTTON_SPACING = 4
local CONTROL_BUTTON_ROW_GAP = 4
-- Up to this many buttons share one row; more split into two even rows.
local CONTROL_MAX_SINGLE_ROW = 5

local function FitControlButtonText(btn, width, height)
    if not btn then
        return
    end

    btn:SetSize(width or CONTROL_BUTTON_WIDTH, height or CONTROL_BUTTON_HEIGHT)

    local text = btn.Text
    if not text then
        return
    end

    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    text:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    if text.SetJustifyH then text:SetJustifyH("CENTER") end
    if text.SetJustifyV then text:SetJustifyV("MIDDLE") end
    if text.SetWordWrap then text:SetWordWrap(false) end
    if text.SetNonSpaceWrap then text:SetNonSpaceWrap(false) end
end

-- Splits `count` buttons into a grid that always spans the full content width:
-- up to CONTROL_MAX_SINGLE_ROW share one row, otherwise two rows with the
-- shorter second row centred under the first. Every button in the grid has the
-- same width (the pixel remainder goes to the leading columns) so the edges
-- line up with the marker row below. Returns a list of { x, y, width }.
local function ComputeControlGrid(count, contentWidth, spacing, rowHeight, rowGap)
    local cells = {}
    if count <= 0 then
        return cells, 0
    end

    local columns = count <= CONTROL_MAX_SINGLE_ROW and count or math.ceil(count / 2)
    local usable = contentWidth - ((columns - 1) * spacing)
    local baseWidth = math.floor(usable / columns)
    local remainder = usable - (baseWidth * columns)

    local function ColumnWidth(column)
        return baseWidth + ((column <= remainder) and 1 or 0)
    end

    local rows = math.ceil(count / columns)
    local index = 0
    for row = 1, rows do
        local inRow = math.min(columns, count - index)
        local x = 0
        if inRow < columns then
            local rowWidth = (inRow * baseWidth) + ((inRow - 1) * spacing)
            x = math.floor((contentWidth - rowWidth) / 2)
        end
        for column = 1, inRow do
            index = index + 1
            local width = inRow < columns and baseWidth or ColumnWidth(column)
            cells[index] = { x = x, y = -((row - 1) * (rowHeight + rowGap)), width = width }
            x = x + width + spacing
        end
    end

    local height = (rows * rowHeight) + ((rows - 1) * rowGap)
    return cells, height
end
Control.ComputeControlGrid = ComputeControlGrid

local function SafeMessageText(message)
    if message == nil then
        return nil
    end
    local okText, text = pcall(tostring, message)
    if not okText or type(text) ~= "string" then
        return nil
    end
    local okIndex = pcall(function()
        return text:sub(1, 1)
    end)
    if not okIndex then
        return nil
    end
    return text
end

local function RunSlashCommand(commandName, args)
    local handler = SlashCmdList and SlashCmdList[commandName]
    if not handler then
        return false
    end

    return pcall(handler, args or "")
end

local function NormalizeName(name)
    if not name or name == "" then
        return nil
    end
    if Ambiguate then
        return Ambiguate(name, "none")
    end
    if strsplit then
        return strsplit("-", name)
    end
    return name:match("^([^%-]+)") or name
end

local function NameKey(name)
    local normalized = NormalizeName(name)
    return normalized and string.lower(normalized) or nil
end

local function NormalizeWorldModifier(modifier)
    modifier = tostring(modifier or "SHIFT"):upper()
    if modifier ~= "CTRL" and modifier ~= "ALT" then
        modifier = "SHIFT"
    end
    return modifier
end

local function GetWorldModifierLabel()
    return NormalizeWorldModifier(RC.db and RC.db.profile and RC.db.profile.worldMarkerModifier)
end

local function ApplyClearWorldModifier(btn)
    if not btn then
        return
    end
    local profile = RC.db and RC.db.profile or {}
    local modifier = NormalizeWorldModifier(profile.worldMarkerModifier)
    RC:ConfigureMarkerActionButton(btn, 0, profile.enableTargetMarkers ~= false, profile.enableWorldMarkers ~= false, modifier)
end

function Control:OnInitialize()
    -- Initialize the Control module
    self.pullActive = false
    self.pullTimer = nil
end

function Control:NormalizePullDuration(seconds)
    seconds = tonumber(seconds) or (RC.db and RC.db.profile and RC.db.profile.pullTimerDuration) or 10
    seconds = math.floor(seconds + 0.5)
    if seconds < 1 then seconds = 1 end
    if seconds > 60 then seconds = 60 end
    return seconds
end

-- Detect which pull timer addon is available
function Control:DetectPullAddon()
    local setting = RC.db.profile.pullTimerAddon or "auto"

    -- If user has explicitly chosen an addon, use it (if available)
    if setting == "bigwigs" then
        return "bigwigs"
    elseif setting == "dbm" then
        return "dbm"
    elseif setting == "ert" then
        return "ert"
    elseif setting == "none" then
        return "none"
    end

    -- Auto-detect: check what's available
    if SlashCmdList["BIGWIGSPULL"] or SlashCmdList["PULL"] or BigWigs then
        return "bigwigs"
    end

    if DBM or SlashCmdList["DEADLYBOSSMODS"] then
        return "dbm"
    end

    if SlashCmdList["EXORSUSRAIDTOOLS"] or SlashCmdList["ERT"] or _G.GMRT then
        return "ert"
    end

    return "none"
end

-- Start pull timer — try Blizzard API first, then addon-specific methods
function Control:TriggerPull(seconds)
    seconds = self:NormalizePullDuration(seconds)
    local secondsStr = tostring(seconds)
    local addon = self:DetectPullAddon()
    local sent = false

    -- BigWigs
    if addon == "bigwigs" then
        sent = RunSlashCommand("BIGWIGSPULL", secondsStr) or RunSlashCommand("PULL", secondsStr)
    end

    -- DBM
    if not sent and addon == "dbm" then
        sent = RunSlashCommand("DEADLYBOSSMODS", "pull " .. secondsStr)
    end

    -- ERT/MRT
    if not sent and addon == "ert" then
        sent = RunSlashCommand("EXORSUSRAIDTOOLS", "countdown " .. secondsStr)
            or RunSlashCommand("ERT", "countdown " .. secondsStr)
            or RunSlashCommand("MRT", "countdown " .. secondsStr)
    end

    if not sent and C_PartyInfo and C_PartyInfo.DoCountdown then
        C_PartyInfo.DoCountdown(seconds)
        sent = true
    end

    return sent
end

-- Cancel pull timer — Blizzard API first, then brute-force addon methods
function Control:TriggerCancelPull()
    -- Method 1: Blizzard API — DoCountdown(0) cancels the countdown
    -- Note: CancelCountdown() does NOT exist; use DoCountdown(0)
    if C_PartyInfo and C_PartyInfo.DoCountdown then
        C_PartyInfo.DoCountdown(0)
    end

    -- Method 2: /pull 0 — works for BigWigs and most addons
    RunSlashCommand("PULL", "0")

    -- Method 3: BigWigs-specific pull cancel
    RunSlashCommand("BIGWIGSPULL", "0")

    -- Method 4: DBM-specific cancel
    RunSlashCommand("DEADLYBOSSMODS", "pull 0")

    -- Method 5: ERT/MRT cancel
    RunSlashCommand("EXORSUSRAIDTOOLS", "countdown 0")
    RunSlashCommand("ERT", "countdown 0")
    RunSlashCommand("MRT", "countdown 0")

    return true
end

function Control:NotifyPullStateChanged()
    local ActionStrip = RC:GetModule("ActionStrip", true)
    if ActionStrip and ActionStrip.RefreshPullButton then
        ActionStrip:RefreshPullButton()
    end
end

function Control:BeginPull(seconds)
    local ok, message = RC:CanManageGroup()
    if not ok then
        RC:ShowError(message)
        return false
    end

    seconds = self:NormalizePullDuration(seconds)
    self:StartPullTimer(seconds)
    if not self:TriggerPull(seconds) then
        self:CancelPullTimer()
        RC:ShowError(L["No pull timer provider is available."])
        return false
    end
    return true
end

function Control:EndPull()
    if self.pullActive then
        self:TriggerCancelPull()
    end
    self:CancelPullTimer()
    return true
end

function Control:DoReadyCheck()
    if InCombatLockdown and InCombatLockdown() then
        RC:ShowError(L["Ready checks are unavailable during combat."])
        return false
    end

    local ok, message = RC:CanManageGroup()
    if not ok then
        RC:ShowError(message)
        return false
    end

    local success, err = RC:StartReadyCheck()
    if not success then
        RC:ShowError(L["Unable to start the ready check."])
        if err then
            RC:Print(tostring(err))
        end
        return false
    end
    return true
end

function Control:ToggleRaidConversion()
    if InCombatLockdown and InCombatLockdown() then
        RC:ShowError(L["Group conversion is unavailable during combat."])
        return false
    end

    if not IsInGroup() then
        RC:ShowError(L["You must be in a group."])
        return false
    end

    if not UnitIsGroupLeader("player") then
        RC:ShowError(L["You must be the group leader."])
        return false
    end

    if not C_PartyInfo then
        RC:ShowError(L["Group conversion is unavailable."])
        return false
    end

    local convertToRaid = not UnitInRaid("player")
    if C_PartyInfo.AllowedToDoPartyConversion then
        local ok, allowed = pcall(C_PartyInfo.AllowedToDoPartyConversion, convertToRaid)
        if not ok or not allowed then
            RC:ShowError(L["WoW is not allowing group conversion right now."])
            return false
        end
    end

    local convert = convertToRaid and C_PartyInfo.ConvertToRaid or C_PartyInfo.ConvertToParty
    if type(convert) ~= "function" then
        RC:ShowError(L["Group conversion is unavailable."])
        return false
    end

    local success = pcall(convert)
    if not success then
        RC:ShowError(L["Unable to convert the group."])
        return false
    end

    return true
end

function Control:ClearTargetMarkers()
    RC:ResetTargetCycle()
    RC:Print(L["Target marker clear uses WoW's secure /tm 0 path on your current target."])
    return true
end

function Control:ClearWorldMarkers()
    if InCombatLockdown and InCombatLockdown() then
        RC:ShowError(string.format(L["Use %s-click on Clr or a world-clear keybind during combat."], GetWorldModifierLabel()))
        return false
    end

    local ok, message = RC:CanManageGroup()
    if not ok then
        RC:ShowError(message)
        return false
    end

    RCClearAllWorldMarkers()
    return true
end

function Control:DisbandGroup()
    if InCombatLockdown and InCombatLockdown() then
        RC:ShowError(L["Disband is unavailable during combat."])
        return false
    end
    if not IsInGroup() then
        RC:ShowError(L["You must be in a group."])
        return false
    end
    if not UnitIsGroupLeader("player") then
        RC:ShowError(L["You must be the group leader."])
        return false
    end

    local removed = 0
    local playerKey = NameKey(UnitName("player"))
    if IsInRaid and IsInRaid() then
        for i = (GetNumGroupMembers() or 0), 1, -1 do
            local name = GetRaidRosterInfo(i)
            if name and NameKey(name) ~= playerKey then
                local success = RC:UninviteGroupMember(name)
                if success then
                    removed = removed + 1
                end
            end
        end
    else
        local members = GetNumSubgroupMembers and GetNumSubgroupMembers() or math.max((GetNumGroupMembers and GetNumGroupMembers() or 1) - 1, 0)
        for i = members, 1, -1 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
                local success = RC:UninviteGroupMember(name)
                if success then
                    removed = removed + 1
                end
            end
        end
    end

    RC:Print(string.format(removed == 1 and L["Disbanded %d member."] or L["Disbanded %d members."], removed))
    return true
end

function Control:ConfirmDisband()
    if InCombatLockdown and InCombatLockdown() then
        RC:ShowError(L["Disband is unavailable during combat."])
        return false
    end
    if not IsInGroup() then
        RC:ShowError(L["You must be in a group."])
        return false
    end
    if not UnitIsGroupLeader("player") then
        RC:ShowError(L["You must be the group leader."])
        return false
    end

    StaticPopupDialogs["RC_CONFIRM_DISBAND_GROUP"] = StaticPopupDialogs["RC_CONFIRM_DISBAND_GROUP"] or {
        text = L["Disband the current group?"],
        button1 = L["Disband"],
        button2 = L["Cancel"],
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function()
            local control = RC:GetModule("Control", true)
            if control and control.DisbandGroup then
                control:DisbandGroup()
            end
        end,
    }
    StaticPopup_Show("RC_CONFIRM_DISBAND_GROUP")
    return true
end

function Control:GetGuildInviteRankList()
    local ranks, seen = {}, {}
    if not IsInGuild or not IsInGuild() then
        return ranks
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end

    local guildCount = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, guildCount do
        local _, rankName, rankIndex, _, _, _, _, _, online, _, _, _, _, isMobile = GetGuildRosterInfo(i)
        if rankIndex ~= nil then
            local key = tostring(rankIndex)
            if not seen[key] then
                seen[key] = {
                    index = rankIndex,
                    name = (rankName and rankName ~= "" and rankName) or string.format(L["Rank %d"], rankIndex + 1),
                    online = 0,
                }
                table.insert(ranks, seen[key])
            end
            if online and not isMobile then
                seen[key].online = (seen[key].online or 0) + 1
            end
        end
    end

    table.sort(ranks, function(a, b)
        return (a.index or 99) < (b.index or 99)
    end)
    return ranks
end

function Control:InviteGuildBySelectedRanks()
    if InCombatLockdown and InCombatLockdown() then
        RC:ShowError(L["Guild invites are unavailable during combat."])
        return false
    end

    if IsInGroup() and not UnitIsGroupLeader("player") and not UnitIsGroupAssistant("player") then
        RC:ShowError(L["You must be the group leader or assistant."])
        return false
    end

    if not IsInGuild or not IsInGuild() then
        RC:ShowError(L["You must be in a guild."])
        return false
    end

    local selected = RC.db.profile.guildInviteRankVisibility or {}
    local hasRank = false
    for _, enabled in pairs(selected) do
        if enabled then
            hasRank = true
            break
        end
    end
    if not hasRank then
        RC:ShowError(L["Select invite ranks in Settings > Automation > Invites."])
        return false
    end

    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end

    local guildCount = GetNumGuildMembers and GetNumGuildMembers() or 0
    if guildCount == 0 then
        RC:Print(L["Requesting guild roster. Try Inv again in a moment."])
        return false
    end

    local grouped = {}
    for _, unit in ipairs(RC:GetGroupUnits()) do
        local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
        local key = NameKey(name)
        if key then
            grouped[key] = true
        end
    end

    local playerKey = NameKey(UnitName("player"))
    local currentMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    local capacity = 40 - math.max(currentMembers, 1)
    if capacity <= 0 then
        RC:ShowError(L["Group is full."])
        return false
    end

    local invited = 0
    for i = 1, guildCount do
        local name, _, rankIndex, _, _, _, _, _, online, _, _, _, _, isMobile = GetGuildRosterInfo(i)
        local key = NameKey(name)
        if name and key and online and not isMobile and selected[tostring(rankIndex or 0)] and key ~= playerKey and not grouped[key] then
            local success = RC:InviteGroupMember(NormalizeName(name) or name)
            if success then
                invited = invited + 1
                grouped[key] = true
                if invited >= capacity then
                    break
                end
            end
        end
    end

    if invited > 0 then
        RC:Print(string.format(invited == 1 and L["Invited %d online guild member."] or L["Invited %d online guild members."], invited))
    else
        RC:Print(L["No online guild members matched the selected ranks."])
    end
    return invited > 0
end

function Control:OnEnable()
    self:CreateControlButtons()
    -- Register with menu system
    RC:RegisterMenuModule({
        name = "Control",
        order = 20,
        frame = self.frame,
        isVisible = function()
            Control:RefreshButtonVisibility()
            return Control:HasVisibleButtons()
        end
    })
    -- Listen for countdown events
    self:RegisterEvent("CHAT_MSG_RAID_WARNING", "OnRaidWarning")
    self:RegisterEvent("CHAT_MSG_PARTY_LEADER", "OnPartyMessage")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnPlayerRegenEnabled")
end

function Control:OnPlayerRegenEnabled()
    if self.pendingButtonRefresh then
        self.pendingButtonRefresh = nil
        self:RefreshButtonVisibility()
        if RC.RefreshLayout then
            RC:RefreshLayout()
        end
    end
end

function Control:HasVisibleButtons()
    local profile = RC.db and RC.db.profile
    if not profile then
        return true
    end
    return profile.showReadyButton ~= false
        or profile.showPullButton ~= false
        or profile.showConvertButton ~= false
        or profile.showDifficultyButton ~= false
        or profile.showInviteButton ~= false
        or profile.showClearButton ~= false
        or profile.showDisbandButton ~= false
        or profile.showScreenshotButton ~= false
end

function Control:OnRaidWarning(event, message)
    self:CheckPullTimer(message)
end

function Control:OnPartyMessage(event, message, sender)
    -- CHAT_MSG_PARTY_LEADER already identifies leader-chat traffic.
    -- Avoid calling UnitIsGroupLeader(sender) because chat payload values can be
    -- secret/tainted in modern clients and trigger protected argument errors.
    self:CheckPullTimer(message)
end

function Control:CheckPullTimer(message)
    message = SafeMessageText(message)
    if not message then
        return
    end
    local pullTime = message:match("Pull[ing]* in (%d+)")
    if pullTime then
        self:StartPullTimer(tonumber(pullTime))
    elseif message:match("[Cc]ancel.*[Pp]ull") or message:match("[Aa]bort") or message:match("Pull CANCELLED") then
        self:CancelPullTimer()
    end
end

function Control:StartPullTimer(seconds)
    seconds = self:NormalizePullDuration(seconds)
    self.pullActive = true
    if self.pullButton then
        self.pullButton.Text:SetText(L["Cancel"])
        self.pullButton.customBg = true
        self.pullButton:SetBackdropColor(0.6, 0.15, 0.15, 0.9) -- Dark red tint for cancel
    end

    -- Clear existing timer if any
    if self.pullTimer then
        self.pullTimer:Cancel()
    end

    -- Set timer to reset button after countdown
    self.pullTimer = C_Timer.NewTimer(seconds + 1, function()
        self:ResetPullButton()
    end)

    self:NotifyPullStateChanged()
end

function Control:CancelPullTimer()
    if self.pullTimer then
        self.pullTimer:Cancel()
        self.pullTimer = nil
    end

    self:ResetPullButton()
end

function Control:ResetPullButton()
    self.pullActive = false
    if self.pullButton then
        self.pullButton.Text:SetText(L["Pull"])
        self.pullButton.customBg = nil
        self.pullButton:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b,
            RC.Config.ButtonBg.a)
    end
    self:NotifyPullStateChanged()
end

function Control:CreateControlButtons()
    if not RC.Menu then return end

    local container = CreateFrame("Frame", nil, RC.Menu)
    container:SetSize(CONTROL_MENU_WIDTH, (CONTROL_BUTTON_HEIGHT * 2) + CONTROL_BUTTON_ROW_GAP)
    self.frame = container

    local btnWidth = CONTROL_BUTTON_WIDTH
    local pullBtnWidth = CONTROL_BUTTON_WIDTH
    local spacing = CONTROL_BUTTON_SPACING
    local rowGap = CONTROL_BUTTON_ROW_GAP
    local rowHeight = CONTROL_BUTTON_HEIGHT
    local totalBtnWidth = pullBtnWidth + (3 * btnWidth) + (3 * spacing)
    local startX = (CONTROL_MENU_WIDTH - totalBtnWidth) / 2

    local function PlaceInGrid(button, row, col)
        local x = startX + ((col - 1) * (btnWidth + spacing))
        local y = -((row - 1) * (rowHeight + rowGap))
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
    end

    local function AddTooltip(btn, title, detail, hints)
        btn:HookScript("OnEnter", function(self)
            RC:ShowMenuTooltip(self, title, detail, hints)
        end)
        btn:HookScript("OnLeave", function(self)
            RC:HideMenuTooltip(self)
        end)
    end

    local function CreateSecureGridButton(label)
        local btn = CreateFrame("Button", nil, container, "SecureActionButtonTemplate,BackdropTemplate")
        btn.rcBorderMinAlpha = 0.06
        btn:SetSize(btnWidth, rowHeight)
        btn:RegisterForClicks("AnyDown")
        btn:SetAttribute("useOnKeyDown", true)
        RC:SkinFrame(btn)
        RC:SetFrameThemeRole(btn, "ButtonBg")
        btn:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a)
        btn:SetBackdropBorderColor(RC:GetControlBorderColor())

        local text = btn:CreateFontString(nil, "OVERLAY")
        RC:SetFont(text, 11, "OUTLINE")
        text:SetText(label)
        text:SetTextColor(RC:GetButtonTextColor())
        RC:RegisterTextColor(text, "button")
        btn.Text = text
        FitControlButtonText(btn, btnWidth, rowHeight)

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.52)
            if not self.customBg then
                self:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            local br, bg, bb, ba = RC:GetControlBorderColor()
            self:SetBackdropBorderColor(br, bg, bb, ba)
            if not self.customBg then
                self:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a)
            end
        end)
        btn:SetScript("OnMouseDown", function(self)
            if not self.customBg then
                self:SetBackdropColor(RC.Config.ButtonPressed.r, RC.Config.ButtonPressed.g, RC.Config.ButtonPressed.b, 1)
            end
        end)
        btn:SetScript("OnMouseUp", function(self)
            if self.customBg then return end
            if self:IsMouseOver() then
                self:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
            else
                self:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a)
            end
        end)
        return btn
    end

    local function CreateStandardGridButton(width)
        local btn = RC:CreateStandardButton(nil, container, width or btnWidth, rowHeight)
        FitControlButtonText(btn, width or btnWidth, rowHeight)
        return btn
    end

    -- Ready Check Button (LEFTMOST)
    local readyBtn = CreateStandardGridButton(btnWidth)
    readyBtn.Text:SetText(L["Ready"])
    PlaceInGrid(readyBtn, 1, 1)
    readyBtn:SetScript("OnClick", function()
        Control:DoReadyCheck()
    end)
    AddTooltip(readyBtn, L["Ready Check"], L["Asks everyone in the group to confirm they are ready."], { L["Click: start a ready check"] })
    self.readyButton = readyBtn

    -- Pull/Cancel Button
    self.pullButton = CreateStandardGridButton(pullBtnWidth)
    self.pullButton.Text:SetText(L["Pull"])
    PlaceInGrid(self.pullButton, 1, 2)
    self.pullButton:SetScript("OnClick", function()
        if Control.pullActive then
            Control:EndPull()
        else
            Control:BeginPull(RC.db.profile.pullTimerDuration)
        end
    end)
    AddTooltip(self.pullButton, L["Pull Timer"], function()
        if Control.pullActive then
            return L["A pull countdown is running."]
        end
        return string.format(L["Counts down %d seconds for the whole group."], Control:NormalizePullDuration(RC.db.profile.pullTimerDuration))
    end, function()
        return { Control.pullActive and L["Click: cancel the pull"] or L["Click: start the pull timer"] }
    end)

    -- Convert Button
    local convertBtn = CreateStandardGridButton(btnWidth)
    convertBtn.Text:SetText(L["Conv"])
    PlaceInGrid(convertBtn, 1, 3)
    convertBtn:SetScript("OnClick", function()
        Control:ToggleRaidConversion()
    end)
    AddTooltip(convertBtn, L["Convert Group"], L["Switches between party and raid. Group leader only."], function()
        return { IsInRaid and IsInRaid() and L["Click: convert to party"] or L["Click: convert to raid"] }
    end)
    self.convertButton = convertBtn

    -- Difficulty Button
    self.diffButton = CreateStandardGridButton(btnWidth)
    self.diffButton.Text:SetText(L["Diff"])
    PlaceInGrid(self.diffButton, 1, 4)
    self.diffButton:SetScript("OnClick", function()
        Control:ToggleDifficultyMenu(Control.diffButton)
    end)
    AddTooltip(self.diffButton, L["Difficulty"], L["Shows the current difficulty. Opens the difficulty picker and instance reset."], { L["Click: choose difficulty"] })

    local inviteBtn = CreateStandardGridButton(btnWidth)
    inviteBtn.Text:SetText(L["Inv"])
    PlaceInGrid(inviteBtn, 2, 1)
    inviteBtn:SetScript("OnClick", function()
        Control:InviteGuildBySelectedRanks()
    end)
    AddTooltip(inviteBtn, L["Invite Guild Ranks"], L["Invites online guild members from the ranks chosen in Settings > Automation > Invites."], { L["Click: send invites"] })
    self.inviteButton = inviteBtn

    local clearBtn = CreateSecureGridButton(L["Clr"])
    PlaceInGrid(clearBtn, 2, 2)
    ApplyClearWorldModifier(clearBtn)
    clearBtn:HookScript("PostClick", function(btn)
        local modifier = btn.worldMarkerModifier or "SHIFT"
        local usedWorldModifier = (modifier == "SHIFT" and IsShiftKeyDown and IsShiftKeyDown())
            or (modifier == "CTRL" and IsControlKeyDown and IsControlKeyDown())
            or (modifier == "ALT" and IsAltKeyDown and IsAltKeyDown())
        if usedWorldModifier then
            if not (InCombatLockdown and InCombatLockdown()) then
                RC:ResetTargetCycle()
            end
            return
        end
        RC:ResetTargetCycle()
    end)
    AddTooltip(clearBtn, L["Clear Markers"], function()
        return string.format(L["Click: clear your current target marker. %s-click: clear all world markers."], GetWorldModifierLabel())
    end)
    clearBtn:Hide()
    self.clearButton = clearBtn

    local disbandBtn = CreateStandardGridButton(btnWidth)
    disbandBtn.Text:SetText(L["Disb"])
    PlaceInGrid(disbandBtn, 2, 3)
    disbandBtn:SetScript("OnClick", function()
        Control:ConfirmDisband()
    end)
    AddTooltip(disbandBtn, L["Disband Group"], L["Removes everyone from the group after a confirmation. Group leader only."], { L["Click: disband (asks first)"] })
    self.disbandButton = disbandBtn

    local screenshotBtn = CreateStandardGridButton(btnWidth)
    screenshotBtn.Text:SetText(L["Shot"])
    screenshotBtn.rcDefaultText = L["Shot"]
    screenshotBtn.rcBusyText = "..."
    PlaceInGrid(screenshotBtn, 2, 4)
    screenshotBtn:SetScript("OnClick", function()
        local ScreenshotModule = RC:GetModule("Screenshot", true)
        if ScreenshotModule and ScreenshotModule.Take then
            ScreenshotModule.button = screenshotBtn
            ScreenshotModule:Take()
        end
    end)
    AddTooltip(screenshotBtn, L["Max Graphics Screenshot"], L["Raises graphics to your screenshot settings, hides the UI, takes the shot, then restores everything."], { L["Click: take screenshot"] })
    self.screenshotButton = screenshotBtn

    -- Update difficulty button text on load
    self:UpdateDiffButton()

    -- Listen for difficulty changes
    self:RegisterEvent("PLAYER_DIFFICULTY_CHANGED", "UpdateDiffButton")
    self:RefreshButtonVisibility()
end

function Control:RefreshButtonVisibility()
    if not self.frame then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        self.pendingButtonRefresh = true
        return
    end

    local profile = RC.db and RC.db.profile or {}
    local buttons = {
        { button = self.readyButton, key = "showReadyButton" },
        { button = self.pullButton, key = "showPullButton" },
        { button = self.convertButton, key = "showConvertButton" },
        { button = self.diffButton, key = "showDifficultyButton" },
        { button = self.inviteButton, key = "showInviteButton" },
        { button = self.disbandButton, key = "showDisbandButton" },
        { button = self.screenshotButton, key = "showScreenshotButton" },
    }
    if self.clearButton then
        self.clearButton:Hide()
    end

    local visibleButtons = {}
    for _, entry in ipairs(buttons) do
        if entry.button and profile[entry.key] ~= false then
            table.insert(visibleButtons, entry.button)
        elseif entry.button then
            entry.button:Hide()
        end
    end
    local cells, height = ComputeControlGrid(#visibleButtons, CONTROL_MENU_WIDTH, CONTROL_BUTTON_SPACING,
        CONTROL_BUTTON_HEIGHT, CONTROL_BUTTON_ROW_GAP)
    for index, button in ipairs(visibleButtons) do
        local cell = cells[index]
        FitControlButtonText(button, cell.width, CONTROL_BUTTON_HEIGHT)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self.frame, "TOPLEFT", cell.x, cell.y)
        button:Show()
    end
    self.frame:SetHeight(height)
end

function Control:RefreshModifierAttributes()
    if InCombatLockdown and InCombatLockdown() then
        -- Secure attributes are locked; RC re-applies every surface after combat.
        RC.MarkerModifierRefreshPending = true
        return
    end
    ApplyClearWorldModifier(self.clearButton)
end

function Control:GetCurrentDifficultyID()
    local inInstance = IsInInstance()
    if inInstance then
        local _, _, diffID = GetInstanceInfo()
        return diffID
    end

    local raidDiff = GetRaidDifficultyID()
    if raidDiff == 14 or raidDiff == 15 or raidDiff == 16 then
        return raidDiff
    end

    return GetDungeonDifficultyID()
end

function Control:GetDifficultyLabel()
    local diffID = self:GetCurrentDifficultyID()
    if diffID == 2 or diffID == 15 then
        return L["Hero"]
    elseif diffID == 23 or diffID == 16 then
        return L["Myth"]
    elseif diffID == 8 then
        return "M+"
    elseif diffID == 1 or diffID == 14 then
        return L["Norm"]
    end
    return L["Diff"]
end

-- Update the difficulty button text to show current difficulty
function Control:UpdateDiffButton()
    if not self.diffButton then return end
    self.diffButton.Text:SetText(self:GetDifficultyLabel())
end

function Control:ToggleDifficultyMenu(anchorBtn)
    if InCombatLockdown and InCombatLockdown() then
        RC:ShowError(L["Difficulty changes are unavailable during combat."])
        return false
    end

    if self.difficultyMenu and self.difficultyMenu:IsShown() then
        self.difficultyMenu:Hide()
        return
    end

    if not self.difficultyMenu then
        local menu = CreateFrame("Frame", "RC_DifficultyMenu", UIParent, "BackdropTemplate")
        menu:SetSize(120, 122) -- 4 rows of 26 with 2px gaps and 6px padding
        RC:SkinFrame(menu)
        menu:SetBackdropColor(RC.Config.Color.r, RC.Config.Color.g, RC.Config.Color.b, 0.98)
        menu:SetFrameStrata("TOOLTIP") -- Higher than UI, lower than click handler
        menu:EnableMouse(true)
        menu:Hide()

        -- Register for ESC key closing
        RC:RegisterEscapeFrame(menu)

        -- Close when clicking outside. One reusable catcher sits under the
        -- menu while it is open and is always hidden together with it.
        local clickCatcher = CreateFrame("Frame", nil, UIParent)
        clickCatcher:SetAllPoints(UIParent)
        clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        clickCatcher:EnableMouse(true)
        clickCatcher:Hide()
        clickCatcher:SetScript("OnMouseDown", function()
            if not menu:IsMouseOver() then
                menu:Hide()
            end
        end)
        menu.clickHandler = clickCatcher
        menu:SetScript("OnShow", function()
            clickCatcher:Show()
        end)
        menu:SetScript("OnHide", function()
            clickCatcher:Hide()
        end)

        local difficulties = {
            { id = 14, dungeonID = 1, name = L["Normal"] },
            { id = 15, dungeonID = 2, name = L["Heroic"] },
            { id = 16, dungeonID = 23, name = L["Mythic"] },
            { id = "reset", name = L["Reset Instances"] },
        }

        menu.buttons = {}
        for i, diff in ipairs(difficulties) do
            local btn = CreateFrame("Button", nil, menu, "BackdropTemplate")
            btn:SetSize(110, 26)
            btn:SetPoint("TOP", menu, "TOP", 0, -6 - (i - 1) * 28)
            RC:SkinFrame(btn)

            -- Make Reset stand out slightly
            if diff.id == "reset" then
                btn:SetBackdropColor(0.2, 0.05, 0.05, 1) -- faint red tint
                btn:SetBackdropBorderColor(0.4, 0.1, 0.1, 1)
            else
                btn:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, 1)
            end

            local text = btn:CreateFontString(nil, "OVERLAY")
            RC:SetFont(text, 11, "")
            text:SetPoint("LEFT", 10, 0)
            text:SetText(diff.name)

            if diff.id == "reset" then
                text:SetTextColor(1, 0.4, 0.4)
            else
                text:SetTextColor(RC:GetGeneralTextColor())
            end
            btn.Text = text

            -- Active difficulty indicator
            local indicator = btn:CreateTexture(nil, "OVERLAY")
            indicator:SetColorTexture(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
            indicator:SetSize(3, 18)
            indicator:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
            indicator:Hide()
            btn.indicator = indicator

            btn:SetScript("OnEnter", function(self)
                self:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)

                if diff.id == "reset" then
                    self:SetBackdropColor(0.4, 0.1, 0.1, 1)
                else
                    self:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
                end
                text:SetTextColor(1, 1, 1)
            end)
            btn:SetScript("OnLeave", function(self)
                if diff.id == "reset" then
                    self:SetBackdropBorderColor(0.4, 0.1, 0.1, 1)
                    self:SetBackdropColor(0.2, 0.05, 0.05, 1)
                    text:SetTextColor(1, 0.4, 0.4)
                else
                    self:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, 1)
                    self:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, 1)
                    text:SetTextColor(RC:GetGeneralTextColor())
                end
            end)
            btn:SetScript("OnClick", function()
                if InCombatLockdown and InCombatLockdown() then
                    RC:ShowError(L["Difficulty changes are unavailable during combat."])
                    menu:Hide()
                    return
                end
                if diff.id == "reset" then
                    if UnitIsGroupLeader("player") or not IsInGroup() then
                        ResetInstances()
                    else
                        RC:ShowError(L["You must be the group leader."])
                    end
                else
                    if IsInGroup() and not UnitIsGroupLeader("player") then
                        RC:ShowError(L["You must be the group leader."])
                        return
                    end
                    SetRaidDifficultyID(diff.id)
                    SetDungeonDifficultyID(diff.dungeonID)
                end
                menu:Hide()
                Control:UpdateDiffButton()
            end)

            btn.diffID = diff.id
            btn.dungeonID = diff.dungeonID
            table.insert(menu.buttons, btn)
        end

        self.difficultyMenu = menu
    end

    -- Update active difficulty indicator
    local raidDiff = GetRaidDifficultyID()
    local dungeonDiff = GetDungeonDifficultyID()

    local inInstance, instanceType = IsInInstance()
    if inInstance then
        local _, _, currentDiffID = GetInstanceInfo()
        raidDiff = currentDiffID
        dungeonDiff = currentDiffID
    end

    for _, btn in ipairs(self.difficultyMenu.buttons) do
        if btn.diffID == "reset" then
            btn.indicator:Hide()
        elseif btn.diffID == raidDiff or btn.dungeonID == dungeonDiff then
            btn.indicator:Show()
            btn:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 0.5)
        else
            btn.indicator:Hide()
            btn:SetBackdropBorderColor(RC.Config.Border.r, RC.Config.Border.g, RC.Config.Border.b, 1)
        end
    end

    self.difficultyMenu:ClearAllPoints()
    self.difficultyMenu:SetPoint("TOP", anchorBtn, "BOTTOM", 0, -2)
    self.difficultyMenu:Show()
end
