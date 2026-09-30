-- Spell IDs the probes test. These are NOT authoritative data for OrionUI; they exist
-- so the probes have something to query. Every probe prints the spell's name as the
-- client resolves it, so a wrong ID shows up immediately as "name=nil" or a wrong name.
--
-- status: "xref" = the ID also appears with the same meaning in another addon's source
--         we cloned (cross-reference only, nothing copied), "unverified" = from memory.
--         "ingame" = the client returned the expected spell name (2026-09-29, 12.1.0).
-- See docs/verification-log.md.
local _, ns = ...

ns.SpellLists = {
    [250] = { -- Blood Death Knight
        { id = 55233,  label = "Vampiric Blood",       status = "ingame" },
        { id = 48707,  label = "Anti-Magic Shell",     status = "ingame" },
        { id = 48792,  label = "Icebound Fortitude",   status = "ingame" },
        { id = 49028,  label = "Dancing Rune Weapon",  status = "ingame" },
        { id = 194679, label = "Rune Tap",             status = "ingame" },
        { id = 219809, label = "Tombstone",            status = "ingame" },
        { id = 51052,  label = "Anti-Magic Zone",      status = "ingame" },
        { id = 49039,  label = "Lichborne",            status = "ingame" },
    },
    [66] = { -- Protection Paladin
        { id = 86659,   label = "Guardian of Ancient Kings", status = "ingame" },
        { id = 31850,   label = "Ardent Defender",      status = "ingame" },
        { id = 387174,  label = "Eye of Tyr",           status = "ingame" },
        { id = 204018,  label = "Blessing of Spellwarding", status = "ingame" },
        { id = 642,     label = "Divine Shield",        status = "ingame" },
    },
    [581] = { -- Vengeance Demon Hunter
        { id = 204021,  label = "Fiery Brand",          status = "ingame" },
        { id = 187827,  label = "Metamorphosis",        status = "ingame" },
        { id = 203720,  label = "Demon Spikes",         status = "ingame" },
        { id = 196718,  label = "Darkness",             status = "ingame" },
    },
    [268] = { -- Brewmaster Monk
        { id = 1241059, label = "Celestial Infusion",   status = "ingame" },
        { id = 322507,  label = "Celestial Brew",       status = "ingame" },
        { id = 115203,  label = "Fortifying Brew",      status = "ingame" },
        { id = 122783,  label = "Diffuse Magic",        status = "ingame" },
        { id = 122278,  label = "Dampen Harm",          status = "ingame" },
        { id = 325153,  label = "Exploding Keg",        status = "ingame" },
    },
    [73] = { -- Protection Warrior
        { id = 871,     label = "Shield Wall",          status = "ingame" },
        { id = 12975,   label = "Last Stand",           status = "ingame" },
        { id = 1160,    label = "Demoralizing Shout",   status = "ingame" },
        { id = 23920,   label = "Spell Reflection",     status = "ingame" },
        { id = 2565,    label = "Shield Block",         status = "ingame" },
    },
    [104] = { -- Guardian Druid
        { id = 22812,   label = "Barkskin",             status = "ingame" },
        { id = 61336,   label = "Survival Instincts",   status = "ingame" },
        { id = 200851,  label = "Rage of the Sleeper",  status = "ingame" },
        { id = 102558,  label = "Incarnation: Guardian of Ursoc", status = "ingame" },
        { id = 22842,   label = "Frenzied Regeneration", status = "ingame" },
    },
}

-- Player auras worth probing per spec (buff IDs can differ from the cast IDs above).
ns.AuraLists = {
    [250] = {
        { id = 195181, label = "Bone Shield",          status = "ingame" },
        { id = 55233,  label = "Vampiric Blood (buff)", status = "ingame" },
        { id = 81256,  label = "Dancing Rune Weapon (buff)", status = "ingame" },
        { id = 48707,  label = "Anti-Magic Shell (buff)", status = "ingame" },
        { id = 48792,  label = "Icebound Fortitude (buff)", status = "ingame" },
    },
}

-- The player's current specialization ID (e.g. 250 for Blood), or nil.
function ns.CurrentSpecID()
    local index = C_SpecializationInfo.GetSpecialization()
    if not index then return nil end
    return (C_SpecializationInfo.GetSpecializationInfo(index))
end
