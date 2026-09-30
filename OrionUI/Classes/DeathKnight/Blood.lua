-- Blood Death Knight (CLAUDE.md §8.3): Bone Shield counter with low-stack and expiry
-- warnings, plus the Boiling Point indicator (Classes/DeathKnight/BoilingPoint.lua).
--
-- What 12.x allows (verified in game 2026-09-30, docs/verification-log.md):
--  * Out of combat Bone Shield is readable: stacks, duration, expiry.
--  * In combat our aura queries are refused. The count is mirrored from the Cooldown
--    Manager's tracked-buff frame (ns.CDMMirror): displayed, never read. Whether a
--    tracked buff is up stays readable.
--  * Low stacks in combat: Ossuary is up exactly while Bone Shield has 5+ stacks, so
--    "Bone Shield up, Ossuary down" = below 5. Needs Ossuary in the CDM tracked buffs too.
--  * Expiry in combat: our own casts are readable in the open world, so a local clock
--    restarts on each Bone Shield refresh (Marrowrend, Death's Caress). Where casts turn
--    secret (encounters may restrict them) the clock just isn't restarted and the expiry
--    warning stays quiet rather than guessing.
--  * The engine plays a sound when Bone Shield drops or returns (C_UnitAuras.AddAuraSound).
local _, ns = ...

local L = ns.L
local S = ns.Schema

local BONE_SHIELD = 195181
local OSSUARY = { [219786] = true, [219788] = true } -- 219788 seen as the aura in game; 219786 unverified
local REFRESHERS = { [195182] = true, [195292] = true } -- Marrowrend, Death's Caress (casts seen in game)
local DEFAULT_DURATION = 30 -- replaced by the real duration whenever the aura is readable
local LOW_AT = 5 -- fixed by the Ossuary signal
local SOUND_FILE = 567397 -- Sound/Interface/RaidWarning.ogg, heard in game 2026-09-30
local UPDATE_EVERY = 0.1

local M = ns.Modules:New("BloodDK", {
    category = "tank", label = L["Blood Death Knight"],
    desc = L["Bone Shield counter with warnings, and the Boiling Point proc. In combat the count is copied from your Cooldown Manager: keep Bone Shield and Ossuary in its tracked buffs."],
    profileKey = "layout",
    loadWhen = { class = "DEATHKNIGHT", specID = 250 },
    schemaVersion = 2,
    migrations = { [2] = function(db) if db.boneShield then db.boneShield.warnAt = nil end end },
    schema = S.Table{ fields = {
        boneShield = S.Table{ label = L["Bone Shield"], order = 1, fields = {
            show = S.Bool{ default = true, label = L["Show the Bone Shield counter"], order = 1 },
            showIcon = S.Bool{ default = true, label = L["Show the icon next to the count"], order = 2 },
            fontSize = S.Number{ default = 28, min = 12, max = 64, step = 1, label = L["Count size"], order = 3 },
            lowWarning = S.Bool{ default = true, label = L["Blink and play a sound below 5 stacks"], order = 4,
                desc = L["Uses Ossuary (up at 5+ stacks) because the game hides the number in combat."] },
            expiryWarning = S.Bool{ default = true, label = L["Warn before Bone Shield runs out"], order = 5 },
            glowAt = S.Number{ default = 8, min = 2, max = 20, step = 1, label = L["Highlight when this many seconds are left"], order = 6 },
            soundAt = S.Number{ default = 5, min = 0, max = 15, step = 1, label = L["Sound when this many seconds are left (0 = off)"], order = 7 },
            downWarning = S.Bool{ default = true, label = L["Show \"Bone Shield down\" in combat"], order = 8 },
            soundOnDrop = S.Bool{ default = true, label = L["Sound when Bone Shield drops"], order = 9 },
            soundOnGain = S.Bool{ default = false, label = L["Sound when Bone Shield comes back"], order = 10 },
        } },
        boilingPoint = S.Table{ label = L["Boiling Point"], order = 2, fields = {
            show = S.Bool{ default = true, label = L["Show when Blood Boil is empowered"], order = 1,
                desc = L["Follows the game's own Blood Boil highlight."] },
            style = S.Enum{ default = "bar", values = { "bar", "icon" }, label = L["Style"], order = 2,
                valueLabels = { bar = L["Thin bar"], icon = L["Icon"] } },
            width = S.Number{ default = 240, min = 60, max = 600, step = 2, label = L["Bar width"], order = 3 },
            height = S.Number{ default = 6, min = 2, max = 30, step = 1, label = L["Bar height / icon size"], order = 4 },
            window = S.Number{ default = 3, min = 1, max = 15, step = 0.5, label = L["Countdown length (seconds)"], order = 5,
                desc = L["How long the empowered Blood Boil lasts. The game doesn't say, so set it to match the talent."] },
            pulse = S.Bool{ default = true, label = L["Pulse while active"], order = 6 },
            sound = S.Bool{ default = false, label = L["Play a sound when it procs"], order = 7 },
        } },
    } },
})
ns.BloodDK = M

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local state = {
    duration = DEFAULT_DURATION,
    expiresAt = nil,   -- local estimate (or the real value when readable)
    wasActive = nil,
    wasLow = false,
    expirySounded = false,
    lastSound = 0,
}

local function Now() return GetTime() end

local function PlayWarning()
    if Now() - state.lastSound < 2 then return end -- two warnings in the same moment: play once
    state.lastSound = Now()
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
end

-- Reads everything we are allowed to read right now.
-- -> active (tri), stacks (number|nil), low (tri), child (CDM frame|nil)
local function Read()
    if not C_Secrets.ShouldAurasBeSecret() then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(BONE_SHIELD)
        if type(aura) == "nil" then return false, nil, nil end
        if ns.Secret.CanRead(aura) then
            local stacks = ns.Secret.Plain(aura.applications)
            local exp, dur = ns.Secret.Plain(aura.expirationTime), ns.Secret.Plain(aura.duration)
            if type(dur) == "number" and dur > 0 then state.duration = dur end
            if type(exp) == "number" and exp > 0 then state.expiresAt = exp end
            if type(stacks) == "number" then return true, stacks, stacks < LOW_AT end
        end
    end
    local child = ns.CDMMirror:Find({ [BONE_SHIELD] = true })
    if not child then return nil, nil, nil end
    local active = ns.CDMMirror:IsActive(child)
    local low
    if active then
        local oss = ns.CDMMirror:Find(OSSUARY)
        if oss then low = not ns.CDMMirror:IsActive(oss) end
    end
    return active, nil, low, child
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local frame, icon, count, timer, blink

local function Create()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("LEFT")
    icon:SetTexture(C_Spell.GetSpellTexture(BONE_SHIELD))
    frame.border = CreateFrame("Frame", nil, frame)
    frame.border:SetAllPoints(icon)
    ns.Theme:Skin(frame.border, { 0, 0, 0, 0 })
    count = frame:CreateFontString(nil, "OVERLAY")
    timer = frame:CreateFontString(nil, "OVERLAY")
    blink = frame:CreateAnimationGroup()
    blink:SetLooping("BOUNCE")
    local a = blink:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetDuration(0.35)
    frame:Hide()
    ns.Movers:Register("BloodBoneShield", {
        label = L["Bone Shield"], getFrame = function() return frame end, default = { x = 0, y = -120 },
    })
end

local function Layout()
    local db = M.db.boneShield
    local size = db.fontSize
    local font = ns.Theme:Font()
    count:SetFont(font, size, "OUTLINE")
    timer:SetFont(font, math.max(10, math.floor(size * 0.45)), "OUTLINE")
    icon:SetSize(size * 1.3, size * 1.3)
    icon:SetShown(db.showIcon)
    frame.border:SetShown(db.showIcon)
    count:ClearAllPoints()
    if db.showIcon then count:SetPoint("LEFT", icon, "RIGHT", 8, 0) else count:SetPoint("LEFT") end
    timer:ClearAllPoints()
    if db.showIcon then timer:SetPoint("TOP", icon, "BOTTOM", 0, -2) else timer:SetPoint("TOPLEFT", count, "BOTTOMLEFT", 0, -2) end
    frame:SetSize(size * 4, size * 1.4)
end

local function SetBlink(on)
    if on and not blink:IsPlaying() then blink:Play() elseif not on and blink:IsPlaying() then blink:Stop() frame:SetAlpha(1) end
end

local function Render(active, stacks, low, child, remaining)
    local db = M.db.boneShield
    if not db.show then frame:Hide() return end
    if active == false then
        SetBlink(false)
        timer:SetText("")
        if db.downWarning and InCombatLockdown() then
            count:SetText(L["Bone Shield down"])
            count:SetTextColor(1, 0.25, 0.25)
            icon:SetDesaturated(true)
            frame:Show()
        else
            frame:Hide()
        end
        return
    end
    if active == nil then frame:Hide() return end -- can't see it (not tracked in the CDM)
    icon:SetDesaturated(false)
    if stacks then count:SetText(stacks) elseif not (child and ns.CDMMirror:CopyStacks(child, count)) then count:SetText("") end
    local lowOn = db.lowWarning and low == true
    local expiring = db.expiryWarning and remaining and remaining <= db.glowAt
    if lowOn then count:SetTextColor(1, 0.3, 0.3) else count:SetTextColor(1, 1, 1) end
    if expiring then
        ns.Theme:SetBorderColor(frame.border, 1, 0.6, 0.1, 1)
        timer:SetText(("%ds"):format(math.max(0, math.ceil(remaining))))
    else
        ns.Theme:SetBorderColor(frame.border, 0, 0, 0, 1)
        timer:SetText("")
    end
    SetBlink(lowOn or expiring)
    frame:Show()
end

---------------------------------------------------------------------------
-- Update loop and warnings
---------------------------------------------------------------------------

function M:Update()
    if not frame then return end
    local db = self.db.boneShield
    local active, stacks, low, child = Read()

    if active and not state.wasActive and not state.expiresAt then
        state.expiresAt = Now() + state.duration -- came up without a cast we saw
    elseif active == false then
        state.expiresAt, state.expirySounded = nil, false
    end
    state.wasActive = active

    local remaining = active and state.expiresAt and (state.expiresAt - Now()) or nil
    if remaining and remaining < -1 then remaining = nil end -- clock overran; don't invent anything

    -- Sounds on crossings only, never repeatedly.
    if db.lowWarning and low == true and not state.wasLow then PlayWarning() end
    state.wasLow = low == true
    if db.expiryWarning and remaining and db.soundAt > 0 and remaining <= db.soundAt and not state.expirySounded then
        state.expirySounded = true
        PlayWarning()
    end

    Render(active, stacks, low, child, remaining)
end

local function OnCast(_, _, _, _, spellID)
    if ns.Secret.Is(spellID) or not REFRESHERS[spellID] then return end
    state.expiresAt, state.expirySounded = Now() + state.duration, false
end

-- Engine aura sounds: registered only for what the settings ask for.
local soundIDs = {}
local function SetSounds()
    for _, id in ipairs(soundIDs) do C_UnitAuras.RemoveAuraSound(id) end
    wipe(soundIDs)
    local db, trig = M.db.boneShield, Enum.UnitAuraSoundTrigger
    local function Add(trigger)
        local id = C_UnitAuras.AddAuraSound(trigger, { unitToken = "player", spellID = BONE_SHIELD, soundFileID = SOUND_FILE, outputChannel = "Master" })
        if id then soundIDs[#soundIDs + 1] = id end
    end
    if db.soundOnDrop then Add(trig.Removed) end
    if db.soundOnGain then Add(trig.Added) end
end

local ticker
local function StartTicker()
    if ticker then return end
    -- Own handle (not M:NewTicker) because it starts and stops every combat.
    ticker = C_Timer.NewTicker(UPDATE_EVERY, function() ns.SafeCall("BloodDK", M.Update, M) end)
end
local function StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end

function M:OnEnable()
    Create()
    Layout()
    SetSounds()
    ns.Events:OnUnit("UNIT_AURA", { "player" }, self, function() ns.Events:Coalesce("blood-bone", function() M:Update() end) end)
    ns.Events:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, self, OnCast)
    ns.Events:On("OUI_COMBAT_START", self, function() StartTicker() M:Update() end)
    ns.Events:On("OUI_COMBAT_END", self, function() StopTicker() M:Update() end)
    if InCombatLockdown() then StartTicker() end
    if ns.BoilingPoint then ns.BoilingPoint:Enable() end
    self:Update()
end

function M:OnDisable()
    StopTicker()
    for _, id in ipairs(soundIDs) do C_UnitAuras.RemoveAuraSound(id) end
    wipe(soundIDs)
    if frame then SetBlink(false) frame:Hide() end
    if ns.BoilingPoint then ns.BoilingPoint:Disable() end
end

function M:Refresh()
    if not frame then return end
    Layout()
    SetSounds()
    if ns.BoilingPoint then ns.BoilingPoint:Refresh() end
    self:Update()
end
