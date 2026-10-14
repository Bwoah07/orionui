local _, ns = ...
local RC = ns.RC
local L = RC.L
---@class BoneShield : AceModule, AceEvent-3.0
local BoneShield = RC:NewModule("BoneShield", "AceEvent-3.0")

-- Blood Death Knight Bone Shield icon: stack count on the top edge, time left in the centre,
-- red count and blink below 5 stacks, orange border near expiry, grey with a red 0 when it drops
-- in combat. Warnings by voice (Text to Speech) or the raid warning sound.
--
-- What 12.x allows:
--  * Out of combat Bone Shield is readable: stacks, duration, expiry.
--  * In combat our aura queries are refused. The count is copied from the Cooldown Manager's
--    tracked-buff frame (FontString:SetText takes the secret text): shown, never read. Whether
--    a tracked buff is up stays readable (auraInstanceID is set only while it is up).
--  * Low stacks in combat: Ossuary is up exactly while Bone Shield has 5+ stacks, so "Bone
--    Shield up, Ossuary down" means below 5. Needs Ossuary in the tracked buffs too.
--  * Expiry in combat: our own casts are readable, so a local clock restarts on each refresh
--    (Marrowrend, Death's Caress). Where casts turn secret the clock isn't restarted and the
--    expiry warning stays quiet rather than guessing.
--  * The engine plays a sound when Bone Shield drops or returns (C_UnitAuras.AddAuraSound).

local BLOOD_SPEC = 250
local BONE_SHIELD = 195181
local BONE_SHIELD_SET = { [BONE_SHIELD] = true }
local OSSUARY = { [219786] = true, [219788] = true }
local REFRESHERS = { [195182] = true, [195292] = true } -- Marrowrend, Death's Caress
local DEFAULT_DURATION = 30 -- replaced by the real duration whenever the aura is readable
local LOW_AT = 5 -- fixed by the Ossuary signal
local SOUND_FILE = 567397 -- Sound/Interface/RaidWarning.ogg
local UPDATE_EVERY = 0.1
local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }

BoneShield.ROWS = {
    essential = "EssentialCooldownViewer",
    utility = "UtilityCooldownViewer",
    buffs = "BuffIconCooldownViewer",
}

local SIDE_POINTS = {
    ABOVE = { "BOTTOM", "TOP", 0, 1 },
    BELOW = { "TOP", "BOTTOM", 0, -1 },
    LEFT = { "RIGHT", "LEFT", -1, 0 },
    RIGHT = { "LEFT", "RIGHT", 1, 0 },
}

---------------------------------------------------------------------------
-- Secret values
---------------------------------------------------------------------------

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function Plain(v)
    if IsSecret(v) then return nil end
    return v
end

local function CanRead(t)
    if IsSecret(t) or type(t) ~= "table" then return false end
    if canaccesstable then return canaccesstable(t) == true end
    return true
end

local function AurasSecret()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        return ok and secret == true
    end
    return InCombatLockdown()
end

---------------------------------------------------------------------------
-- Cooldown Manager frames
---------------------------------------------------------------------------

local infoCache = {} -- cooldownID -> set of spell IDs it stands for

local function SpellsFor(cooldownID)
    local set = infoCache[cooldownID]
    if set then return set end
    set = {}
    local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
    if ok and CanRead(info) then
        for _, key in ipairs({ "spellID", "overrideSpellID", "overrideTooltipSpellID" }) do
            local v = Plain(info[key])
            if v then set[v] = true end
        end
        if CanRead(info.linkedSpellIDs) then
            for _, v in ipairs(info.linkedSpellIDs) do
                v = Plain(v)
                if v then set[v] = true end
            end
        end
    end
    -- Cache only real answers: an empty set cached in combat would hide the buff for good.
    if next(set) then infoCache[cooldownID] = set end
    return set
end

-- The last match per spell set: in combat the lookup can fail while the frame found out of
-- combat still shows the buff.
local lastFound = setmetatable({}, { __mode = "k" })
local function Search(spellIDs)
    if not C_CooldownViewer then return nil end
    for _, name in ipairs(VIEWERS) do
        local viewer = _G[name]
        if viewer then
            for _, child in ipairs({ viewer:GetChildren() }) do
                local id = child.cooldownID
                if not IsSecret(id) and id ~= nil then
                    for spell in pairs(SpellsFor(id)) do
                        if spellIDs[spell] then return child end
                    end
                end
            end
        end
    end
end

local function Find(spellIDs)
    local child = Search(spellIDs)
    if child then lastFound[spellIDs] = child return child end
    local old = lastFound[spellIDs]
    if not old then return nil end
    -- Reuse it only while we can't tell what it tracks now (a pooled frame may have moved on).
    local id = old.cooldownID
    if IsSecret(id) or (id ~= nil and next(SpellsFor(id)) == nil) then return old end
end

local function IsUp(child)
    return child ~= nil and type(child.auraInstanceID) ~= "nil"
end

local function StackString(child)
    local apps = child and (child.Applications or (child.Icon and child.Icon.Applications))
    local fs = apps and (apps.Applications or apps)
    if fs and fs.GetText then return fs end
end

local function CopyStacks(child, target)
    local fs = StackString(child)
    if not fs then return false end
    target:SetText(fs:GetText())
    return true
end

local function CopyCountdown(child, target)
    local cd = child and child.Cooldown
    local fs = cd and cd.GetCountdownFontString and cd:GetCountdownFontString()
    if not fs and child and child.Bar then fs = child.Bar.Duration end
    if not (fs and fs.GetText) then return false end
    local text = fs:GetText()
    if type(text) == "nil" then return false end
    target:SetText(text)
    return true
end

-- Keeps a Cooldown Manager icon alive (we still copy its text) but invisible, so Bone Shield
-- doesn't show twice. Alpha only: the frame is not protected and GetText works at alpha 0.
-- Other addons may set alpha on those icons, so a hook puts it back to 0; the value can be
-- secret (engine fades), so it is never compared.
local concealed, hooked = {}, setmetatable({}, { __mode = "k" })

local function Reveal(key)
    local child = concealed[key]
    concealed[key] = nil
    if child and child.__rcConcealed then
        child.__rcConcealed = nil
        child:SetAlpha(1)
    end
end

local function Conceal(key, child)
    local old = concealed[key]
    if old and old ~= child then Reveal(key) end
    if not child then return end
    concealed[key] = child
    if not hooked[child] then
        hooked[child] = true
        hooksecurefunc(child, "SetAlpha", function(frame, alpha)
            if frame.__rcConcealed and (IsSecret(alpha) or alpha ~= 0) then frame:SetAlpha(0) end
        end)
    end
    if not child.__rcConcealed then
        child.__rcConcealed = true
        child:SetAlpha(0)
    end
end

---------------------------------------------------------------------------
-- State and settings
---------------------------------------------------------------------------

local state = {
    duration = DEFAULT_DURATION,
    expiresAt = nil,
    wasActive = nil,
    wasLow = false,
    expirySounded = false,
    lastSound = 0,
}

local function DB()
    return RC.db.profile
end

local function Get(key, fallback)
    local value = DB()[key]
    if value == nil or (fallback ~= nil and type(value) ~= type(fallback)) then return fallback end
    return value
end

local function IsBlood()
    if not GetSpecialization or not GetSpecializationInfo then return false end
    local index = GetSpecialization()
    if not index then return false end
    return GetSpecializationInfo(index) == BLOOD_SPEC
end

local function Speak(text)
    if not (C_VoiceChat and C_VoiceChat.SpeakText) then return false end
    local tankAssist = RC:GetModule("TankAssist", true)
    local voiceID = tankAssist and tankAssist.GetTtsVoiceID and tankAssist:GetTtsVoiceID() or 0
    local ok
    if Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback then
        ok = pcall(C_VoiceChat.SpeakText, voiceID, text, Enum.VoiceTtsDestination.LocalPlayback, 0, 100)
    else
        ok = pcall(C_VoiceChat.SpeakText, voiceID, text, 0, 100, true)
    end
    return ok
end

local function PlayWarning(text)
    if GetTime() - state.lastSound < 2 then return end -- two warnings in the same moment: play once
    state.lastSound = GetTime()
    if Get("boneShieldAlertStyle", "voice") == "voice" and Speak(text) then return end
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
end

local function ConcealIfAsked(key, child)
    if Get("boneShieldHideInCDM", true) and BoneShield.active then Conceal(key, child) else Reveal(key) end
end

-- -> active (true/false/nil = can't tell), stacks (number|nil), low (true/false/nil), CDM frame
local function Read()
    if not AurasSecret() then
        ConcealIfAsked("BoneShield", Find(BONE_SHIELD_SET))
        ConcealIfAsked("Ossuary", Find(OSSUARY))
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(BONE_SHIELD)
        if type(aura) == "nil" then return false, nil, nil end
        if CanRead(aura) then
            local stacks = Plain(aura.applications)
            local expires, duration = Plain(aura.expirationTime), Plain(aura.duration)
            if type(duration) == "number" and duration > 0 then state.duration = duration end
            if type(expires) == "number" and expires > 0 then state.expiresAt = expires end
            if type(stacks) == "number" then return true, stacks, stacks < LOW_AT end
        end
    end
    local child = Find(BONE_SHIELD_SET)
    ConcealIfAsked("BoneShield", child)
    -- No frame to copy from: fail open. In combat keep showing it on our cast clock.
    if not child then return (state.wasActive or InCombatLockdown()) and true or nil, nil, nil end
    local active = IsUp(child)
    local low
    if active then
        local ossuary = Find(OSSUARY)
        if ossuary then
            low = not IsUp(ossuary)
            ConcealIfAsked("Ossuary", ossuary)
        end
    end
    return active, nil, low, child
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local function SetBorder(frame, r, g, b)
    for _, line in ipairs(frame.borderLines) do
        line:SetColorTexture(r, g, b, 1)
    end
end

function BoneShield:CreateFrame()
    if self.frame then return end
    local frame = CreateFrame("Frame", "RaidControlBoneShield", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(target)
        if RC:IsUILayoutUnlocked() then
            target.rcMoving = true
            target:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(target)
        if not target.rcMoving then return end
        target.rcMoving = nil
        target:StopMovingOrSizing()
        -- Dragging it means it should stay where it was dropped.
        local point, _, relativePoint, x, y = target:GetPoint(1)
        DB().boneShieldPos = { point, "UIParent", relativePoint, x, y }
        DB().boneShieldAttach = "none"
    end)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(BONE_SHIELD) or 136120)
    frame.icon = icon
    -- Darkens the icon a little so white text reads on it.
    frame.shade = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    frame.shade:SetAllPoints()

    -- 1px border drawn inside the icon edge.
    frame.borderLines = {}
    local edges = {
        { "TOPLEFT", "TOPRIGHT", nil, 1 },
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }
    for _, edge in ipairs(edges) do
        local line = frame:CreateTexture(nil, "OVERLAY", nil, 1)
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        if edge[3] then line:SetWidth(edge[3]) end
        if edge[4] then line:SetHeight(edge[4]) end
        frame.borderLines[#frame.borderLines + 1] = line
    end
    SetBorder(frame, 0, 0, 0)

    -- Text sits on its own frame above the border, so the border never cuts through the numbers.
    frame.textHolder = CreateFrame("Frame", nil, frame)
    frame.textHolder:SetAllPoints()
    frame.textHolder:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.count = frame.textHolder:CreateFontString(nil, "OVERLAY")
    frame.timer = frame.textHolder:CreateFontString(nil, "OVERLAY")

    frame.blink = frame:CreateAnimationGroup()
    frame.blink:SetLooping("BOUNCE")
    local fade = frame.blink:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.25)
    fade:SetDuration(0.35)

    frame:Hide()
    self.frame = frame
end

function BoneShield:GetAttachFrame()
    local attach = Get("boneShieldAttach", "none")
    local name
    if attach == "custom" then
        name = strtrim(Get("boneShieldAttachFrame", "") or "")
    else
        name = self.ROWS[attach]
    end
    local target = name and name ~= "" and _G[name]
    if type(target) == "table" and target.GetWidth and target ~= self.frame then
        return target
    end
end

function BoneShield:Layout()
    local frame = self.frame
    if not frame then return end
    local size = Get("boneShieldIconSize", 36)
    local fontSize = Get("boneShieldFontSize", 18)
    frame:SetSize(size, size)
    -- Own outline + shadow (the shared RaidControl font drops outlines), so the numbers stay
    -- readable over the bright icon.
    local font = RC:GetFont()
    local name = Get("boneShieldFont", "default")
    if name ~= "default" then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        font = LSM and LSM:Fetch("font", name, true) or font
    end
    local outline = Get("boneShieldThickOutline", true) and "THICKOUTLINE" or "OUTLINE"
    local timerSize = math.max(8, math.floor(fontSize * Get("boneShieldTimerScale", 0.9) + 0.5))
    for _, text in ipairs({ frame.count, frame.timer }) do
        text:SetFont(font or STANDARD_TEXT_FONT, text == frame.count and fontSize or timerSize, outline)
        text:SetShadowColor(0, 0, 0, 1)
        text:SetShadowOffset(1, -1)
    end
    frame.shade:SetColorTexture(0, 0, 0, Get("boneShieldDarken", 0.35))
    frame.count:ClearAllPoints()
    frame.count:SetPoint("CENTER", frame, "TOP", 0, 0)
    frame.timer:ClearAllPoints()
    frame.timer:SetPoint("CENTER", frame, "CENTER", 0, 0)

    frame:ClearAllPoints()
    local target = self:GetAttachFrame()
    if target then
        local p = SIDE_POINTS[Get("boneShieldAttachSide", "LEFT")] or SIDE_POINTS.LEFT
        local gap = Get("boneShieldAttachGap", 1)
        frame:SetPoint(p[1], target, p[2], p[3] * gap, p[4] * gap)
    else
        local pos = Get("boneShieldPos", nil) or { "CENTER", "UIParent", "CENTER", -220, -120 }
        frame:SetPoint(pos[1] or "CENTER", UIParent, pos[3] or "CENTER", pos[4] or 0, pos[5] or 0)
        self:RetryAttach()
    end
    frame:EnableMouse(RC:IsUILayoutUnlocked())
end

-- The row we attach to may be built after login: retry for a while.
function BoneShield:RetryAttach()
    if self.attachTicker or Get("boneShieldAttach", "none") == "none" then return end
    local tries = 0
    self.attachTicker = C_Timer.NewTicker(1, function()
        tries = tries + 1
        if self:GetAttachFrame() or tries >= 15 then
            self.attachTicker:Cancel()
            self.attachTicker = nil
            if self:GetAttachFrame() then self:Layout() end
        end
    end)
end

function BoneShield:SetBlink(on)
    local blink = self.frame.blink
    if on and not blink:IsPlaying() then
        blink:Play()
    elseif not on and blink:IsPlaying() then
        blink:Stop()
        self.frame:SetAlpha(1)
    end
end

function BoneShield:Render(active, stacks, low, child, remaining)
    local frame = self.frame
    if self.preview then
        frame.icon:SetDesaturated(false)
        frame.count:SetText("7")
        frame.count:SetTextColor(1, 1, 1)
        frame.timer:SetText(Get("boneShieldShowTime", true) and "24" or "")
        frame.timer:SetTextColor(1, 1, 1)
        SetBorder(frame, 0, 0, 0)
        self:SetBlink(false)
        frame:Show()
        return
    end
    if active == false then
        self:SetBlink(false)
        frame.timer:SetText("")
        if Get("boneShieldDownWarning", true) and InCombatLockdown() then
            frame.count:SetText("0")
            frame.count:SetTextColor(1, 0.25, 0.25)
            frame.icon:SetDesaturated(true)
            SetBorder(frame, 1, 0.25, 0.25)
            frame:Show()
        else
            frame:Hide()
        end
        return
    end
    if active == nil then frame:Hide() return end -- can't see it (not tracked in the Cooldown Manager)
    frame.icon:SetDesaturated(false)
    if stacks then
        frame.count:SetText(stacks)
    elseif not (child and CopyStacks(child, frame.count)) then
        frame.count:SetText("")
    end
    local lowOn = Get("boneShieldLowWarning", true) and low == true
    local expiring = Get("boneShieldExpiryWarning", true) and remaining and remaining <= Get("boneShieldGlowAt", 8)
    if lowOn then frame.count:SetTextColor(1, 0.3, 0.3) else frame.count:SetTextColor(1, 1, 1) end
    if expiring then SetBorder(frame, 1, 0.6, 0.1) else SetBorder(frame, 0, 0, 0) end
    -- Time left: our own readable value wins; else the Cooldown Manager's countdown.
    if not Get("boneShieldShowTime", true) then
        frame.timer:SetText("")
    elseif remaining and (not InCombatLockdown() or not child) then
        frame.timer:SetText(math.max(0, math.ceil(remaining)))
    elseif not (child and CopyCountdown(child, frame.timer)) then
        frame.timer:SetText(remaining and math.max(0, math.ceil(remaining)) or "")
    end
    if expiring then frame.timer:SetTextColor(1, 0.6, 0.1) else frame.timer:SetTextColor(1, 1, 1) end
    self:SetBlink(lowOn or expiring)
    frame:Show()
end

---------------------------------------------------------------------------
-- Update loop and warnings
---------------------------------------------------------------------------

function BoneShield:Update()
    if not self.frame then return end
    if not self.active then
        if self.preview then self:Render() else self.frame:Hide() end
        return
    end
    local active, stacks, low, child = Read()
    local style = Get("boneShieldAlertStyle", "voice")

    -- Voice mode says drop/gain itself (engine aura sounds only play a sound file).
    -- Only on a known change, so "can't see it" never counts as "dropped".
    if style == "voice" and state.wasActive ~= nil and active ~= nil and active ~= state.wasActive then
        if active == false and Get("boneShieldSoundOnDrop", true) and InCombatLockdown() then PlayWarning(L["Bone Shield down"]) end
        if active == true and Get("boneShieldSoundOnGain", false) then PlayWarning(L["Bone Shield up"]) end
    end

    if active and not state.wasActive and not state.expiresAt then
        state.expiresAt = GetTime() + state.duration -- came up without a cast we saw
    elseif active == false then
        state.expiresAt, state.expirySounded = nil, false
    end
    state.wasActive = active

    local remaining = active and state.expiresAt and (state.expiresAt - GetTime()) or nil
    if remaining and remaining < -1 then remaining = nil end -- clock overran; don't invent anything

    -- Sounds on crossings only, never repeatedly.
    if Get("boneShieldLowWarning", true) and low == true and not state.wasLow then PlayWarning(L["Bone Shield low"]) end
    state.wasLow = low == true
    local soundAt = Get("boneShieldSoundAt", 5)
    if Get("boneShieldExpiryWarning", true) and remaining and soundAt > 0 and remaining <= soundAt and not state.expirySounded then
        state.expirySounded = true
        PlayWarning(L["Bone Shield expiring"])
    end

    self:Render(active, stacks, low, child, remaining)
    if active or InCombatLockdown() then self:StartTicker() else self:StopTicker() end
end

function BoneShield:StartTicker()
    if self.ticker then return end
    self.ticker = C_Timer.NewTicker(UPDATE_EVERY, function() self:Update() end)
end

function BoneShield:StopTicker()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

-- Engine aura sounds: registered only for what the settings ask for.
function BoneShield:SetSounds()
    for _, id in ipairs(self.soundIDs or {}) do C_UnitAuras.RemoveAuraSound(id) end
    self.soundIDs = {}
    if not (self.active and C_UnitAuras.AddAuraSound and Enum and Enum.UnitAuraSoundTrigger) then return end
    if Get("boneShieldAlertStyle", "voice") == "voice" then return end -- spoken from Update instead
    local trigger = Enum.UnitAuraSoundTrigger
    local function Add(when)
        local ok, id = pcall(C_UnitAuras.AddAuraSound, when,
            { unitToken = "player", spellID = BONE_SHIELD, soundFileID = SOUND_FILE, outputChannel = "Master" })
        if ok and id then self.soundIDs[#self.soundIDs + 1] = id end
    end
    if Get("boneShieldSoundOnDrop", true) then Add(trigger.Removed) end
    if Get("boneShieldSoundOnGain", false) then Add(trigger.Added) end
end

function BoneShield:UNIT_AURA(_, unit)
    if unit ~= "player" or self.auraPending then return end
    self.auraPending = true
    C_Timer.After(0, function()
        self.auraPending = nil
        self:Update()
    end)
end

function BoneShield:UNIT_SPELLCAST_SUCCEEDED(_, unit, _, spellID)
    if unit ~= "player" or IsSecret(spellID) or not REFRESHERS[spellID] then return end
    state.expiresAt, state.expirySounded = GetTime() + state.duration, false
end

-- Turns the tracker on for Blood with the setting on, off otherwise.
function BoneShield:Refresh()
    self:CreateFrame()
    local wanted = Get("boneShieldEnabled", true) and IsBlood()
    if wanted ~= (self.active == true) then
        self.active = wanted or nil
        if wanted then
            self:RegisterEvent("UNIT_AURA")
            self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
        else
            self:UnregisterEvent("UNIT_AURA")
            self:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
            self:StopTicker()
            self:SetBlink(false)
            state.wasActive, state.expiresAt = nil, nil
        end
    end
    if not Get("boneShieldHideInCDM", true) or not self.active then
        Reveal("BoneShield")
        Reveal("Ossuary")
    end
    self:Layout()
    self:SetSounds()
    self:Update()
end

function BoneShield:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function(_, unit)
        if unit == nil or unit == "player" then self:Refresh() end
    end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "Update")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "Update")
    self:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED", function() wipe(infoCache) end)
    self:Refresh()
end

-- Layout mode (/rc layout): show a sample icon so it can be dragged.
function BoneShield:BeginLayoutMode()
    if not (self.active or IsBlood()) then return end
    self:CreateFrame()
    self.preview = true
    self.frame:EnableMouse(true)
    self:Render()
end

function BoneShield:EndLayoutMode()
    if not self.frame then return end
    self.preview = nil
    self:Layout()
    self:Update()
end

function BoneShield:ResetPosition()
    DB().boneShieldPos = nil
    DB().boneShieldAttach = "none"
    self:Layout()
end

function BoneShield:Test()
    state.lastSound = 0
    PlayWarning(L["Bone Shield low"])
end

-- /rc bone: what the icon sees right now (run it in combat when it misbehaves).
function BoneShield:PrintDiagnostics()
    local ok, active, stacks, low, child = pcall(Read)
    if not ok then
        RC:Print("Bone Shield: read error: " .. tostring(active))
        return
    end
    local function T(v) return v == nil and "unknown" or tostring(v) end
    RC:Print(("Bone Shield: active=%s stacks=%s low=%s cdmFrame=%s ossuaryFrame=%s combat=%s blood=%s shown=%s"):format(
        T(active), IsSecret(stacks) and "secret" or T(stacks), T(low), child and "found" or "none",
        Find(OSSUARY) and "found" or "none", tostring(InCombatLockdown()), tostring(IsBlood()),
        tostring(self.frame and self.frame:IsShown())))
    self:Test()
end
