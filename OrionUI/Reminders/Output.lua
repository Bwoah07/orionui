-- Reminder output: icon + text + countdown on screen, optional sound and speech.
-- Shows up to three reminders stacked, soonest on top. The defensive's icon is the big
-- one (what to press); the ability's name and time to impact sit next to it.
-- Our own numbers only (expiresAt from the boss mod), so no secret values are involved.
local _, ns = ...

local L = ns.L
local Output = { rows = {} }
ns.ReminderOutput = Output

local MAX = 3
local anchor, ticker

local function Speak(text)
    if not (C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.SpeakText) then return end
    local voices = C_VoiceChat.GetTtsVoices()
    local voice = voices and voices[1]
    if voice then C_VoiceChat.SpeakText(voice.voiceID, text, 0, 100, false) end
end

local function NewRow(i)
    local T = ns.Theme
    local row = CreateFrame("Frame", nil, anchor)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.icon:SetPoint("LEFT")
    row.border = CreateFrame("Frame", nil, row)
    row.border:SetAllPoints(row.icon)
    T:Skin(row.border, { 0, 0, 0, 0 })
    row.cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cd:SetAllPoints(row.icon)
    row.cd:SetReverse(true)
    row.cd:SetHideCountdownNumbers(true)
    row.title = row:CreateFontString(nil, "OVERLAY")
    row.title:SetPoint("BOTTOMLEFT", row.icon, "RIGHT", 10, 1)
    row.title:SetJustifyH("LEFT")
    row.sub = row:CreateFontString(nil, "OVERLAY")
    row.sub:SetPoint("TOPLEFT", row.icon, "RIGHT", 10, -3)
    row.sub:SetJustifyH("LEFT")
    Output.rows[i] = row
    return row
end

function Output:ApplySettings()
    if not anchor then return end
    local size = ns.Reminders.db.iconSize
    local font = ns.Theme:Font()
    anchor:SetSize(size * 5, size)
    for i = 1, MAX do
        local row = self.rows[i] or NewRow(i)
        row:SetSize(size * 5, size)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(i - 1) * (size + 8))
        -- Rows after the first are smaller so the most urgent one stands out.
        local s = i == 1 and size or math.floor(size * 0.7)
        row.icon:SetSize(s, s)
        row.title:SetFont(font, i == 1 and math.floor(size * 0.36) or math.floor(size * 0.3), "OUTLINE")
        row.sub:SetFont(font, math.max(10, math.floor(size * 0.24)), "OUTLINE")
    end
end

local function Describe(r)
    if r.mode == "defensive" then
        if r.defensive then
            local name = C_Spell.GetSpellName(r.defensive.spell) or r.defensive.key
            return name .. (r.maybe and " ?" or ""), C_Spell.GetSpellTexture(r.defensive.spell), true
        elseif r.covered then
            local name = C_Spell.GetSpellName(r.covered.spell) or r.covered.key
            return L["Covered"] .. ": " .. name, C_Spell.GetSpellTexture(r.covered.spell), false
        end
        return L["No defensive ready"], r.icon, false
    end
    return r.text or "?", r.icon, false
end

function Output:Render()
    local list, now = ns.Scheduler:Visible(), GetTime()
    local r1, g1, b1 = ns.Theme:Accent()
    for i = 1, MAX do
        local row, r = self.rows[i], list[i]
        if r then
            local title, icon, isAction = Describe(r)
            local left = math.max(0, r.expiresAt - now)
            row.icon:SetTexture(icon or 134400)
            row.title:SetText(title)
            if isAction then row.title:SetTextColor(r1, g1, b1) else row.title:SetTextColor(1, 1, 1) end
            local timeText = left < 10 and ("%.1f"):format(left) or ("%d"):format(math.floor(left))
            if r.noTime then timeText = "" end -- custom message reminders have no hit time
            row.sub:SetText((r.mode == "defensive" and (r.text or "") .. "  " or "") .. timeText)
            if isAction then ns.Theme:SetBorderColor(row.border, r1, g1, b1, 1) else ns.Theme:SetBorderColor(row.border, 0, 0, 0, 1) end
            if row.shownFor ~= r or row.shownUntil ~= r.expiresAt then
                row.shownFor, row.shownUntil = r, r.expiresAt
                row.cd:SetCooldown(now, math.max(0.1, left))
            end
            row:Show()
        else
            row.shownFor = nil
            row:Hide()
        end
    end
    if #list == 0 then
        anchor:Hide()
        if ticker then ticker:Cancel() ticker = nil end
    else
        anchor:Show()
        if not ticker then ticker = C_Timer.NewTicker(0.1, function() Output:Render() end) end
    end
end

local function OnShow(_, _, r)
    if not anchor then return end
    Output:Render()
    if r.announced then return end -- a revision of a reminder already announced
    r.announced = true
    -- A custom reminder carries its own sound/speech choice; others use the global settings.
    local db = ns.Reminders.db
    local sound, speech = db.sound, db.speech
    if r.sound ~= nil then sound = r.sound end
    if r.speech ~= nil then speech = r.speech end
    if sound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
    if speech then
        local title = Describe(r)
        Speak(title)
    end
end

-- Called from the Reminders module's OnEnable (settings are bound by then).
function Output:Create()
    if anchor then return self:ApplySettings() end
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetFrameStrata("HIGH")
    anchor:Hide()
    self:ApplySettings()
    ns.Movers:Register("Reminders", {
        label = L["Defensive reminders"], getFrame = function() return anchor end, default = { x = 0, y = 140 },
    })
end

ns.Events:On("OUI_REMINDER_SHOW", Output, OnShow)
ns.Events:On("OUI_REMINDER_HIDE", Output, function() if anchor then Output:Render() end end)
Output.name = "ReminderOutput"
