-- /ouidev casts
-- For 90 seconds, logs the player's own spell casts (UNIT_SPELLCAST_SUCCEEDED) and spell
-- proc glows (SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE) with whether the spell ID is
-- readable. Answers: can a local clock follow Bone Shield refreshes (Marrowrend etc.)
-- in combat, and does Boiling Point show up as a Blood Boil proc glow?
-- Read-only: listens to events, changes nothing.
local _, ns = ...

local Report = ns.Report
local Describe = ns.Describe

local DURATION = 90
local listening = false

local function Name(spellID)
    if ns.IsSecret(spellID) or type(spellID) ~= "number" then return "?" end
    return tostring(C_Spell.GetSpellName(spellID))
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, a, b, c)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- a = unit, b = castGUID, c = spellID
        Report:Event("CAST spell=%s (%s) combat=%s", Describe(c), Name(c), tostring(InCombatLockdown()))
    else
        Report:Event("%s spell=%s (%s) combat=%s", (event:gsub("SPELL_ACTIVATION_OVERLAY_", "")), Describe(a), Name(a), tostring(InCombatLockdown()))
    end
end)

function ns.ProbeCasts(args)
    if listening then
        ns.Chat("casts: already listening")
        return
    end
    listening = true
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
    frame:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
    Report:Event("CASTS listening for %ds", DURATION)
    ns.Chat(("casts: listening for %d seconds. Fight the dummy (Marrowrend, Blood Boil, Death Strike), then /ouidev log"):format(DURATION))
    C_Timer.After(DURATION, function()
        frame:UnregisterAllEvents()
        listening = false
        Report:Event("CASTS stopped")
        ns.Chat("casts: stopped. /ouidev log to view")
    end)
end
