-- /ouidev bone [sound]
-- What can an addon show about Bone Shield (and find about Boiling Point) in combat?
-- Answers the design questions for the Blood DK module (CLAUDE.md §8.3):
--  1. Are the player's aura instance IDs readable in combat, and is the aura data secret?
--  2. Can a secret stack string be displayed (FontString:SetText is AllowedWhenTainted)?
--  3. Can a colour curve take a secret stack count (Evaluate is AllowedWhenUntainted: expect no)?
--  4. What do Blizzard's Cooldown Manager buff frames expose (cooldownID, auraInstanceID,
--     Applications text) so we could mirror them?
--  5. "sound": registers an engine aura sound on Bone Shield gained/lost for 60 seconds
--     (C_UnitAuras.AddAuraSound), then removes it again. Non-destructive.
-- Out of combat it also lists auras whose name contains "Boiling" to find that spell ID.
local _, ns = ...

local Report = ns.Report
local Describe, Try = ns.Describe, ns.Try

local BONE_SHIELD = 195181
local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer", "EssentialCooldownViewer", "UtilityCooldownViewer" }

local scratch -- hidden FontString used to test displaying secret text
local function Scratch()
    if not scratch then
        local f = CreateFrame("Frame")
        f:Hide()
        scratch = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    return scratch
end

local function ProbeInstances()
    local ok, ids = Try(C_UnitAuras.GetUnitAuraInstanceIDs, "player", "HELPFUL")
    if not ok then Report:Line("GetUnitAuraInstanceIDs ERR %s", tostring(ids)) return end
    if not ns.CanReadTable(ids) then Report:Line("GetUnitAuraInstanceIDs -> %s", Describe(ids)) return end
    Report:Line("GetUnitAuraInstanceIDs: %d ids", #ids)
    for i, id in ipairs(ids) do
        if i > 12 then Report:Line("  ...") break end
        local okA, aura = Try(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", id)
        local spell = okA and ns.CanReadTable(aura) and Describe(aura.spellId) or (okA and Describe(aura) or "ERR")
        local okC, count = Try(C_UnitAuras.GetAuraApplicationDisplayCount, "player", id, 1)
        local shown = "n/a"
        if okC then
            local okS, err = pcall(Scratch().SetText, Scratch(), count)
            shown = okS and "SetText ok" or ("SetText ERR " .. tostring(err))
        end
        local okD, dur = Try(C_UnitAuras.GetAuraDuration, "player", id)
        Report:Line("  id=%s spellId=%s count=%s (%s) duration=%s", Describe(id), spell,
            okC and Describe(count) or ("ERR " .. tostring(count)), shown, okD and Describe(dur) or ("ERR " .. tostring(dur)))
        -- Colour curve fed with the (possibly secret) stack count.
        if okA and ns.CanReadTable(aura) then
            local curve = C_CurveUtil.CreateColorCurve()
            curve:AddPoint(0, CreateColor(1, 0, 0, 1))
            curve:AddPoint(5, CreateColor(1, 1, 1, 1))
            local okE, e = pcall(curve.Evaluate, curve, aura.applications)
            Report:Line("     curve:Evaluate(applications=%s) -> %s", Describe(aura.applications), okE and Describe(e) or ("ERR " .. tostring(e)))
        end
    end
end

local function ProbeViewers()
    for _, name in ipairs(VIEWERS) do
        local viewer = _G[name]
        if not viewer then
            Report:Line("%s: not present", name)
        else
            local children = { viewer:GetChildren() }
            Report:Line("%s: %d children, shown=%s", name, #children, tostring(viewer:IsShown()))
            for i, c in ipairs(children) do
                if i > 16 then Report:Line("  ...") break end
                local spell = c.GetSpellID and select(2, Try(c.GetSpellID, c))
                local apps = c.Applications
                local appText = apps and apps.Applications or apps
                local text = "n/a"
                if appText and appText.GetText then
                    local okT, t = pcall(appText.GetText, appText)
                    if okT then
                        local okS = pcall(Scratch().SetText, Scratch(), t)
                        text = Describe(t) .. (okS and " (mirrors ok)" or " (mirror ERR)")
                    end
                end
                Report:Line("  #%d cooldownID=%s spell=%s auraInstanceID=%s unit=%s applications=%s shown=%s", i,
                    Describe(c.cooldownID), Describe(spell), Describe(c.auraInstanceID), Describe(c.auraDataUnit), text, tostring(c:IsShown()))
            end
        end
    end
end

local function FindBoiling()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        Report:Line("Boiling Point search skipped (auras secret; run out of combat)")
        return
    end
    for i = 1, 60 do
        local ok, aura = Try(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok or not aura then break end
        if type(aura.name) == "string" and aura.name:find("Boiling") then
            Report:Line("FOUND %s spellId=%s stacks=%s", aura.name, Describe(aura.spellId), Describe(aura.applications))
        end
    end
end

local soundIDs
local function SoundTest()
    if soundIDs then Report:Line("sound test already running") return end
    soundIDs = {}
    local trig = Enum.UnitAuraSoundTrigger or {}
    -- 567397 = Sound/Interface/RaidWarning.ogg (file ID from memory, unverified).
    for _, t in ipairs({ { trig.Added }, { trig.Removed } }) do
        local ok, id = Try(C_UnitAuras.AddAuraSound, t[1], { unitToken = "player", spellID = BONE_SHIELD, soundFileID = 567397, outputChannel = "Master" })
        Report:Line("AddAuraSound(trigger=%s) -> %s", Describe(t[1]), ok and Describe(id) or ("ERR " .. tostring(id)))
        if ok and id then soundIDs[#soundIDs + 1] = id end
    end
    C_Timer.After(60, function()
        for _, id in ipairs(soundIDs) do pcall(C_UnitAuras.RemoveAuraSound, id) end
        soundIDs = nil
        ns.Chat("bone sound test ended (sounds removed)")
    end)
end

function ns.ProbeBone(args)
    Report:Begin("BONE")
    Report:Line("Bone Shield secrecy=%s shouldBeSecret=%s", Describe(select(2, Try(C_Secrets.GetSpellAuraSecrecy, BONE_SHIELD))),
        Describe(select(2, Try(C_Secrets.ShouldSpellAuraBeSecret, BONE_SHIELD))))
    ProbeInstances()
    ProbeViewers()
    FindBoiling()
    if args[1] == "sound" then SoundTest() end
    return Report:End(args.show ~= false)
end
