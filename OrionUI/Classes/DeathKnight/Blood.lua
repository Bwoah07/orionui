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
    desc = L["Bone Shield counter with warnings, and the Boiling Point proc. In combat the count is copied from your Cooldown Manager: keep Bone Shield and Ossuary in its tracked buffs (OrionUI hides those icons for you)."],
    profileKey = "layout",
    loadWhen = { class = "DEATHKNIGHT", specID = 250 },
    schemaVersion = 8,
    migrations = {
        [2] = function(db) if db.boneShield then db.boneShield.warnAt = nil end end,
        -- The first build guessed a 3s proc; the talent actually gives 15s (3s is the echo).
        [3] = function(db) if db.boilingPoint and db.boilingPoint.window == 3 then db.boilingPoint.window = 15 end end,
        -- Stig's design (2026-09-30): compact 90x20 bar, blue proc / red echo, glow instead of pulse.
        [4] = function(db)
            local bp = db.boilingPoint
            if not bp then return end
            if bp.width == 240 and bp.height == 6 then bp.width, bp.height = 90, 20 end
            if bp.pulse ~= nil then bp.glow, bp.pulse = bp.pulse, nil end
            bp.showTime = nil -- back to the new default (off)
        end,
        -- The countdown number was removed (Stig, 2026-09-30).
        [5] = function(db) if db.boilingPoint then db.boilingPoint.showTime = nil end end,
        -- Stig (2026-09-30): Bone Shield as an EUI-style icon (stacks top, time centred since 2026-10-01);
        -- Boiling Point: red while the proc waits, blue after you cast Blood Boil.
        -- Stig (2026-09-30): Bone Shield beside the cooldown row; Boiling Point thin and longer,
        -- right above the rune bar (which moves up for the Death and Decay bar, Modules/HudStack.lua).
        [7] = function(db)
            db.boneShield = db.boneShield or {}
            db.boneShield.attach, db.boneShield.attachSide, db.boneShield.attachGap = "cooldowns", "LEFT", 1
            db.boneShield.iconSize = 36
            db.boilingPoint = db.boilingPoint or {}
            local bp = db.boilingPoint
            bp.attach, bp.attachSide, bp.attachGap, bp.matchWidth = "runes", "ABOVE", 1, false
            bp.width, bp.height = 140, 8
        end,
        -- Stig (2026-10-01): the echo bar uses OrionUI blue (ns.Theme.BRAND).
        [8] = function(db)
            local c = db.boilingPoint and db.boilingPoint.echoColor
            if type(c) == "table" and c[1] == 0.2 and c[2] == 0.55 and c[3] == 1 then db.boilingPoint.echoColor = nil end
        end,
        [6] = function(db)
            local bs, bp = db.boneShield, db.boilingPoint
            if bs then
                if bs.fontSize == 28 then bs.fontSize = nil end
                bs.showIcon = nil
            end
            if bp then
                local function Is(c, r, g, b) return type(c) == "table" and c[1] == r and c[2] == g and c[3] == b end
                if Is(bp.procColor, 0.2, 0.55, 1) then bp.procColor = nil end
                if Is(bp.echoColor, 0.9, 0.2, 0.2) then bp.echoColor = nil end
            end
        end,
    },
    schema = S.Table{ fields = {
        boneShield = S.Table{ label = L["Bone Shield"], order = 1, fields = {
            show = S.Bool{ default = true, label = L["Show the Bone Shield counter"], order = 1 },
            iconSize = S.Number{ default = 36, min = 20, max = 96, step = 1, label = L["Icon size"], order = 2 },
            fontSize = S.Number{ default = 16, min = 8, max = 40, step = 1, label = L["Stack count size"], order = 3 },
            showTime = S.Bool{ default = true, label = L["Show time left in the centre"], order = 3.5,
                desc = L["In combat the time is copied from your Cooldown Manager's Bone Shield icon."] },
            hideInCDM = S.Bool{ default = true, label = L["Hide Bone Shield and Ossuary in the Cooldown Manager"], order = 3.6,
                desc = L["Keep both in your Cooldown Manager's tracked buffs: in combat the stack count can only be read from there. This makes those icons invisible so Bone Shield doesn't show twice. Put them at the end of the row so the empty spot doesn't show."] },
            lowWarning = S.Bool{ section = L["Bone Shield warnings"], default = true, label = L["Blink and play a sound below 5 stacks"], order = 4,
                desc = L["Uses Ossuary (up at 5+ stacks) because the game hides the number in combat."] },
            expiryWarning = S.Bool{ section = L["Bone Shield warnings"], default = true, label = L["Warn before Bone Shield runs out"], order = 5 },
            glowAt = S.Number{ section = L["Bone Shield warnings"], default = 8, min = 2, max = 20, step = 1, label = L["Highlight when this many seconds are left"], order = 6 },
            alertStyle = S.Enum{ section = L["Bone Shield warnings"], default = "voice", values = { "voice", "sound" },
                valueLabels = { voice = L["Voice"], sound = L["Raid warning sound"] }, label = L["Warning sound"], order = 4.5,
                desc = L["Voice uses the game's Text to Speech voice (pick it in the game's Text to Speech settings)."] },
            soundAt = S.Number{ section = L["Bone Shield warnings"], default = 5, min = 0, max = 15, step = 1, label = L["Sound when this many seconds are left (0 = off)"], order = 7 },
            downWarning = S.Bool{ section = L["Bone Shield warnings"], default = true, label = L["Show \"Bone Shield down\" in combat"], order = 8 },
            soundOnDrop = S.Bool{ section = L["Bone Shield warnings"], default = true, label = L["Sound when Bone Shield drops"], order = 9 },
            soundOnGain = S.Bool{ section = L["Bone Shield warnings"], default = false, label = L["Sound when Bone Shield comes back"], order = 10 },
            attach = S.Enum{ section = L["Bone Shield position"], default = "cooldowns", values = ns.CDMAnchor.CHOICES, valueLabels = ns.CDMAnchor.CHOICE_LABELS,
                label = L["Attach to Cooldown Manager"], order = 20,
                desc = L["Sticks to a Cooldown Manager row, so it moves with it and stays lined up."] },
            attachSide = S.Enum{ section = L["Bone Shield position"], default = "LEFT", values = ns.CDMAnchor.SIDES, valueLabels = ns.CDMAnchor.SIDE_LABELS,
                label = L["Side"], order = 21 },
            attachGap = S.Number{ section = L["Bone Shield position"], default = 1, min = -10, max = 40, step = 1, label = L["Gap (pixels)"], order = 22 },
        } },
        boilingPoint = S.Table{ label = L["Boiling Point"], order = 2, fields = {
            show = S.Bool{ default = true, label = L["Show Boiling Point"], order = 1,
                desc = L["Red when it procs: cast Blood Boil. Blue after you cast it, while the echo is coming, glowing if a new proc rolls."] },
            style = S.Enum{ default = "bar", values = { "bar", "icon" }, label = L["Style"], order = 2,
                valueLabels = { bar = L["Bar"], icon = L["Icon"] } },
            width = S.Number{ default = 140, min = 30, max = 600, step = 2, label = L["Bar width"], order = 3 },
            height = S.Number{ default = 8, min = 4, max = 60, step = 1, label = L["Bar height / icon size"], order = 4 },
            procColor = S.Color{ section = L["Boiling Point colours"], default = { 0.9, 0.2, 0.2, 1 }, label = L["Proc colour (cast Blood Boil)"], order = 5 },
            echoColor = S.Color{ section = L["Boiling Point colours"], default = { 0.15, 0.45, 0.85, 1 }, label = L["Echo colour (after casting)"], order = 6 },
            glow = S.Bool{ section = L["Boiling Point colours"], default = true, label = L["Glow when a new proc rolls during the echo"], order = 7 },
            glowColor = S.Color{ section = L["Boiling Point colours"], default = { 1, 0.82, 0.2, 1 }, label = L["Glow colour"], order = 7.5 },
            echo = S.Bool{ section = L["Boiling Point timing"], default = true, label = L["Show the 3 second echo after casting"], order = 8 },
            window = S.Number{ section = L["Boiling Point timing"], default = 15, min = 1, max = 30, step = 0.5, label = L["Proc lasts (seconds)"], order = 9,
                desc = L["The talent gives 15 seconds to use the empowered Blood Boil."] },
            sound = S.Bool{ section = L["Boiling Point timing"], default = false, label = L["Play a sound when it procs"], order = 11 },
            attach = S.Enum{ section = L["Boiling Point position"], default = "runes", values = ns.CDMAnchor.CHOICES, valueLabels = ns.CDMAnchor.CHOICE_LABELS,
                label = L["Attach to Cooldown Manager"], order = 20,
                desc = L["Sticks to a Cooldown Manager row, so it moves with it and stays lined up."] },
            attachSide = S.Enum{ section = L["Boiling Point position"], default = "ABOVE", values = ns.CDMAnchor.SIDES, valueLabels = ns.CDMAnchor.SIDE_LABELS,
                label = L["Side"], order = 21 },
            attachGap = S.Number{ section = L["Boiling Point position"], default = 1, min = -10, max = 40, step = 1, label = L["Gap (pixels)"], order = 22 },
            matchWidth = S.Bool{ section = L["Boiling Point position"], default = false, label = L["Same width as the row (above or below it)"], order = 23 },
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

-- Voice (default, Stig 2026-10-02: nicer than the raid warning horn) or the raid warning sound.
local function PlayWarning(text)
    if Now() - state.lastSound < 2 then return end -- two warnings in the same moment: play once
    state.lastSound = Now()
    if M.db.boneShield.alertStyle == "voice" and ns.Speak then
        ns.Speak(text)
    else
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    end
end

-- Reads everything we are allowed to read right now.
-- -> active (tri), stacks (number|nil), low (tri), child (CDM frame|nil)
local BONE_SHIELD_SET = { [BONE_SHIELD] = true }
local function Conceal(key, child)
    if M.db.boneShield.hideInCDM and M.db.boneShield.show then ns.CDMMirror:Conceal(key, child) else ns.CDMMirror:Reveal(key) end
end

local function Read()
    if not C_Secrets.ShouldAurasBeSecret() then
        -- Out of combat: remember the CDM frames for later (and hide them if asked).
        Conceal("BoneShield", ns.CDMMirror:Find(BONE_SHIELD_SET))
        Conceal("Ossuary", ns.CDMMirror:Find(OSSUARY))
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
    local child = ns.CDMMirror:Find(BONE_SHIELD_SET)
    Conceal("BoneShield", child)
    -- No CDM frame to mirror: fail open. In combat keep showing it on our cast clock.
    if not child then return (state.wasActive or InCombatLockdown()) and true or nil, nil, nil end
    local active = ns.CDMMirror:IsActive(child)
    local low
    if active then
        local oss = ns.CDMMirror:Find(OSSUARY)
        if oss then low = not ns.CDMMirror:IsActive(oss) Conceal("Ossuary", oss) end
    end
    return active, nil, low, child
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------

local frame, icon, count, timer, blink, mover, Layout

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
    -- Text sits on its own frame above the border, so the border never cuts through the numbers.
    frame.text = CreateFrame("Frame", nil, frame)
    frame.text:SetAllPoints(frame)
    frame.text:SetFrameLevel(frame.border:GetFrameLevel() + 2)
    count = frame.text:CreateFontString(nil, "OVERLAY")
    timer = frame.text:CreateFontString(nil, "OVERLAY")
    blink = frame:CreateAnimationGroup()
    blink:SetLooping("BOUNCE")
    local a = blink:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.25)
    a:SetDuration(0.35)
    frame:Hide()
    mover = ns.Movers:Register("BloodBoneShield", {
        label = L["Bone Shield"], getFrame = function() return frame end, default = { x = 0, y = -120 },
        attached = function() local db = M.db.boneShield return db.attach ~= "none" and ns.CDMAnchor:Row(db.attach) ~= nil end,
        detach = function() M.db.boneShield.attach = "none" Layout() end,
    })
end

-- Looks like an EllesmereUI Cooldown Manager icon (Stig, 2026-09-30): square cropped icon,
-- 1px black border, stack count on the top edge, time left in the centre (Stig, 2026-10-01).
function Layout()
    local db = M.db.boneShield
    local font = ns.Theme:Font()
    frame:SetSize(db.iconSize, db.iconSize)
    icon:ClearAllPoints()
    icon:SetAllPoints(frame)
    count:SetFont(font, db.fontSize, "OUTLINE")
    timer:SetFont(font, math.max(8, math.floor(db.fontSize * 0.85)), "OUTLINE")
    count:ClearAllPoints()
    count:SetPoint("CENTER", frame, "TOP", 0, 0)
    timer:ClearAllPoints()
    timer:SetPoint("CENTER", frame, "CENTER", 0, 0)
    -- Attached to a CDM row, or back to its own saved spot.
    if not ns.CDMAnchor:Place(frame, db) then
        ns.CDMAnchor:Release(frame)
        ns.Movers:Apply(mover)
    end
    ns.CDMAnchor:WhenReady("BoneShield", db, function() if M.enabled then Layout() end end)
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
            count:SetText("0")
            count:SetTextColor(1, 0.25, 0.25)
            icon:SetDesaturated(true)
            ns.Theme:SetBorderColor(frame.border, 1, 0.25, 0.25, 1)
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
    if expiring then ns.Theme:SetBorderColor(frame.border, 1, 0.6, 0.1, 1) else ns.Theme:SetBorderColor(frame.border, 0, 0, 0, 1) end
    -- Time left: readable (out of combat, or our cast clock) wins; else the CDM's own countdown.
    if not db.showTime then
        timer:SetText("")
    elseif remaining and (not InCombatLockdown() or not child) then
        timer:SetText(math.max(0, math.ceil(remaining)))
    elseif not (child and ns.CDMMirror:CopyCountdown(child, timer)) then
        timer:SetText(remaining and math.max(0, math.ceil(remaining)) or "")
    end
    if expiring then timer:SetTextColor(1, 0.6, 0.1) else timer:SetTextColor(1, 1, 1) end
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

    -- Voice mode says drop/gain itself (the engine's aura sounds can only play a sound file).
    -- Only on a known change, so "can't see it" never counts as "dropped".
    if db.alertStyle == "voice" and state.wasActive ~= nil and active ~= nil and active ~= state.wasActive then
        if active == false and db.soundOnDrop and InCombatLockdown() then PlayWarning(L["Bone Shield down"]) end
        if active == true and db.soundOnGain then PlayWarning(L["Bone Shield up"]) end
    end

    if active and not state.wasActive and not state.expiresAt then
        state.expiresAt = Now() + state.duration -- came up without a cast we saw
    elseif active == false then
        state.expiresAt, state.expirySounded = nil, false
    end
    state.wasActive = active

    local remaining = active and state.expiresAt and (state.expiresAt - Now()) or nil
    if remaining and remaining < -1 then remaining = nil end -- clock overran; don't invent anything

    -- Sounds on crossings only, never repeatedly.
    if db.lowWarning and low == true and not state.wasLow then PlayWarning(L["Bone Shield low"]) end
    state.wasLow = low == true
    if db.expiryWarning and remaining and db.soundAt > 0 and remaining <= db.soundAt and not state.expirySounded then
        state.expirySounded = true
        PlayWarning(L["Bone Shield expiring"])
    end

    Render(active, stacks, low, child, remaining)
    if active or InCombatLockdown() then M:StartTicker() else M:StopTicker() end
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
    if db.alertStyle == "voice" then return end -- spoken from M:Update instead
    local function Add(trigger)
        local id = C_UnitAuras.AddAuraSound(trigger, { unitToken = "player", spellID = BONE_SHIELD, soundFileID = SOUND_FILE, outputChannel = "Master" })
        if id then soundIDs[#soundIDs + 1] = id end
    end
    if db.soundOnDrop then Add(trig.Removed) end
    if db.soundOnGain then Add(trig.Added) end
end

local ticker
function M:StartTicker()
    if ticker then return end
    -- Own handle (not M:NewTicker): runs only while Bone Shield is up or in combat.
    ticker = C_Timer.NewTicker(UPDATE_EVERY, function() ns.SafeCall("BloodDK", M.Update, M) end)
end
function M:StopTicker()
    if ticker then ticker:Cancel() ticker = nil end
end
local function StopTicker() M:StopTicker() end

function M:OnEnable()
    Create()
    Layout()
    SetSounds()
    ns.Events:OnUnit("UNIT_AURA", { "player" }, self, function() ns.Events:Coalesce("blood-bone", function() M:Update() end) end)
    ns.Events:OnUnit("UNIT_SPELLCAST_SUCCEEDED", { "player" }, self, OnCast)
    ns.Events:On("OUI_COMBAT_START", self, function() M:Update() end)
    ns.Events:On("OUI_COMBAT_END", self, function() M:Update() end)
    if ns.BoilingPoint then ns.BoilingPoint:Enable() end
    self:Update()
end

function M:OnDisable()
    StopTicker()
    for _, id in ipairs(soundIDs) do C_UnitAuras.RemoveAuraSound(id) end
    wipe(soundIDs)
    if frame then SetBlink(false) frame:Hide() end
    ns.CDMMirror:Reveal("BoneShield")
    ns.CDMMirror:Reveal("Ossuary")
    if ns.BoilingPoint then ns.BoilingPoint:Disable() end
end

-- /oui bone: what the Bone Shield icon sees right now (run it in combat when it misbehaves).
ns.Slash:Register("bone", function()
    local ok, active, stacks, low, child = pcall(Read)
    if not ok then ns.Print("Bone Shield: Read error: " .. tostring(active)) return end
    local function T(v) return v == nil and "unknown" or tostring(v) end
    ns.Print(("Bone Shield: active=%s stacks=%s low=%s cdmFrame=%s combat=%s aurasSecret=%s shown=%s enabled=%s"):format(
        T(active), ns.Secret.Is(stacks) and "secret" or T(stacks), T(low), child and "found" or "none",
        tostring(InCombatLockdown()), tostring(C_Secrets.ShouldAurasBeSecret()),
        tostring(frame and frame:IsShown()), tostring(M.enabled)))
end, "Bone Shield diagnostics")

function M:Refresh()
    if not frame then return end
    Layout()
    SetSounds()
    if ns.BoilingPoint then ns.BoilingPoint:Refresh() end
    self:Update()
end
