-- Blood Death Knight (CLAUDE.md §8.3): Bone Shield counter.
--
-- What 12.x allows (verified 2026-09-30):
--  * Out of combat Bone Shield is readable: exact stacks, colour by threshold.
--  * In combat our aura queries are refused, so the count is mirrored from the Cooldown
--    Manager's tracked-buff frame (ns.CDMMirror): displayed, never read. That needs Bone
--    Shield in the CDM's tracked buffs. We still know whether it is up (plain signal),
--    so "Bone Shield is down" works in combat; "below N stacks" does not.
--  * The engine itself can play a sound when Bone Shield drops or returns
--    (C_UnitAuras.AddAuraSound); heard in game on both triggers.
local _, ns = ...

local L = ns.L
local S = ns.Schema

local BONE_SHIELD = 195181
local SOUND_FILE = 567397 -- Sound/Interface/RaidWarning.ogg, heard in game 2026-09-30
local UPDATE_EVERY = 0.2

local M = ns.Modules:New("BloodDK", {
    category = "tank", label = L["Blood Death Knight"],
    desc = L["A large Bone Shield counter with a warning when it drops. In combat the count is copied from your Cooldown Manager, so keep Bone Shield in its tracked buffs."],
    profileKey = "layout",
    loadWhen = { class = "DEATHKNIGHT", specID = 250 },
    schema = S.Table{ fields = {
        boneShield = S.Table{ label = L["Bone Shield"], order = 1, fields = {
            show = S.Bool{ default = true, label = L["Show the Bone Shield counter"], order = 1 },
            showIcon = S.Bool{ default = true, label = L["Show the icon next to the count"], order = 2 },
            fontSize = S.Number{ default = 28, min = 12, max = 64, step = 1, label = L["Count size"], order = 3 },
            warnAt = S.Number{ default = 5, min = 0, max = 10, step = 1, label = L["Low stacks colour below (out of combat only)"], order = 4,
                desc = L["The game hides the number in combat, so the colour can only change outside combat."] },
            downWarning = S.Bool{ default = true, label = L["Show \"Bone Shield down\" in combat"], order = 5 },
            soundOnDrop = S.Bool{ default = true, label = L["Sound when Bone Shield drops"], order = 6 },
            soundOnGain = S.Bool{ default = false, label = L["Sound when Bone Shield comes back"], order = 7 },
        } },
    } },
})

local frame, icon, count, ticker
local soundIDs = {}
local cdmMissingLogged = false

local function Create()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(120, 40)
    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("LEFT")
    icon:SetTexture(C_Spell.GetSpellTexture(BONE_SHIELD))
    frame.border = CreateFrame("Frame", nil, frame)
    frame.border:SetAllPoints(icon)
    ns.Theme:Skin(frame.border, { 0, 0, 0, 0 })
    count = frame:CreateFontString(nil, "OVERLAY")
    frame:Hide()
    ns.Movers:Register("BloodBoneShield", {
        label = L["Bone Shield"], getFrame = function() return frame end, default = { x = 0, y = -120 },
    })
end

local function Layout()
    local db = M.db.boneShield
    local size = db.fontSize
    count:SetFont(ns.Theme:Font(), size, "OUTLINE")
    icon:SetSize(size * 1.3, size * 1.3)
    icon:SetShown(db.showIcon)
    frame.border:SetShown(db.showIcon)
    count:ClearAllPoints()
    if db.showIcon then
        count:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    else
        count:SetPoint("LEFT")
    end
    frame:SetSize(size * 4, size * 1.4)
end

local function ShowDown()
    if M.db.boneShield.downWarning then
        count:SetText(L["Bone Shield down"])
        count:SetTextColor(1, 0.25, 0.25)
        icon:SetDesaturated(true)
        frame:Show()
    else
        frame:Hide()
    end
end

-- Out of combat: read the real aura (allowed then).
local function UpdateReadable()
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(BONE_SHIELD)
    if not ns.Secret.CanRead(aura) then return false end
    local stacks = ns.Secret.Plain(aura.applications)
    if type(stacks) ~= "number" then return false end
    count:SetText(stacks)
    icon:SetDesaturated(false)
    if stacks < M.db.boneShield.warnAt then count:SetTextColor(1, 0.35, 0.35) else count:SetTextColor(1, 1, 1) end
    frame:Show()
    return true
end

-- In combat: mirror the Cooldown Manager.
local function UpdateMirrored()
    local child = ns.CDMMirror:Find({ [BONE_SHIELD] = true })
    if not child then
        if not cdmMissingLogged then
            cdmMissingLogged = true
            M:Warn("Bone Shield is not in the Cooldown Manager's tracked buffs; the counter can't update in combat")
        end
        frame:Hide()
        return
    end
    if not ns.CDMMirror:IsActive(child) then return ShowDown() end
    count:SetTextColor(1, 1, 1)
    icon:SetDesaturated(false)
    if ns.CDMMirror:CopyStacks(child, count) then frame:Show() else frame:Hide() end
end

function M:Update()
    if not frame then return end
    if not self.db.boneShield.show then frame:Hide() return end
    if C_Secrets.ShouldAurasBeSecret() then
        UpdateMirrored()
    elseif not UpdateReadable() then
        -- Readable but absent: only worth a warning while fighting.
        if InCombatLockdown() then ShowDown() else frame:Hide() end
    end
end

-- Engine aura sounds: registered only for what the settings ask for.
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
    -- Out of combat UNIT_AURA is enough; in combat the CDM is polled lightly (0.2s) because
    -- its frames can be reassigned between buffs and we can't read aura events then.
    ns.Events:OnUnit("UNIT_AURA", { "player" }, self, function() ns.Events:Coalesce("blood-bone", function() M:Update() end) end)
    ns.Events:On("OUI_COMBAT_START", self, function() StartTicker() M:Update() end)
    ns.Events:On("OUI_COMBAT_END", self, function() StopTicker() M:Update() end)
    if InCombatLockdown() then StartTicker() end
    self:Update()
end

function M:OnDisable()
    StopTicker()
    for _, id in ipairs(soundIDs) do C_UnitAuras.RemoveAuraSound(id) end
    wipe(soundIDs)
    if frame then frame:Hide() end
end

function M:Refresh()
    if not frame then return end
    Layout()
    SetSounds()
    self:Update()
end
