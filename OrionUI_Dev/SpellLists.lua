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
        { id = 31850,  label = "Ardent Defender",      status = "xref" },
        { id = 86659,  label = "Guardian of Ancient Kings", status = "xref" },
        { id = 642,    label = "Divine Shield",        status = "xref" },
    },
    [581] = { -- Vengeance Demon Hunter
        { id = 204021, label = "Fiery Brand",          status = "xref" },
        { id = 187827, label = "Metamorphosis",        status = "xref" },
        { id = 203720, label = "Demon Spikes",         status = "xref" },
    },
    [268] = { -- Brewmaster Monk
        { id = 115203, label = "Fortifying Brew",      status = "xref" },
        { id = 322507, label = "Celestial Brew",       status = "xref" },
        { id = 122278, label = "Dampen Harm",          status = "xref" },
        { id = 115176, label = "Zen Meditation",       status = "xref" },
    },
    [73] = { -- Protection Warrior
        { id = 871,    label = "Shield Wall",          status = "xref" },
        { id = 12975,  label = "Last Stand",           status = "xref" },
        { id = 2565,   label = "Shield Block",         status = "unverified" },
        { id = 23920,  label = "Spell Reflection",     status = "unverified" },
    },
    [104] = { -- Guardian Druid
        { id = 61336,  label = "Survival Instincts",   status = "xref" },
        { id = 22812,  label = "Barkskin",             status = "xref" },
        { id = 192081, label = "Ironfur",              status = "xref" },
        { id = 22842,  label = "Frenzied Regeneration", status = "xref" },
    },
}

-- Player auras worth probing per spec (buff IDs can differ from the cast IDs above).
ns.AuraLists = {
    [250] = {
        { id = 195181, label = "Bone Shield",          status = "unverified" },
        { id = 55233,  label = "Vampiric Blood (buff)", status = "unverified" },
        { id = 81256,  label = "Dancing Rune Weapon (buff)", status = "unverified" },
        { id = 48707,  label = "Anti-Magic Shell (buff)", status = "unverified" },
        { id = 48792,  label = "Icebound Fortitude (buff)", status = "unverified" },
    },
}

-- The player's current specialization ID (e.g. 250 for Blood), or nil.
function ns.CurrentSpecID()
    local index = C_SpecializationInfo.GetSpecialization()
    if not index then return nil end
    return (C_SpecializationInfo.GetSpecializationInfo(index))
end
