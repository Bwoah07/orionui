-- Defensive catalog per specialization (CLAUDE.md §7.7, §7.12). ALL AUTHORED BY US.
--
--   key       stable id used in presets and bindings (never change it once shipped)
--   spell     spell ID: the cooldown we read and the ability we tell the player to press
--   duration  seconds the effect lasts; used by Coverage to know "already active" when
--             auras are withheld in combat. Estimates until checked in game.
--   strength  1 minor, 2 medium, 3 major. An active defensive covers candidates of equal
--             or lower strength ("skip when covered").
--   dmg       "all" | "physical" | "magic": what it is good against.
--
-- Sources for the non-Blood specs (2026-09-30): Maxroll Mythic+ guides for 12.1, Warcraft
-- Wiki and Wowhead for spell IDs. "ingame" = the game returned the right name for the ID
-- (/ouidev secrets all, 2026-09-30, docs/verification-log.md). Durations are unverified.
-- Talented spells the player doesn't have are skipped automatically (C_SpellBook check).
local _, ns = ...

ns.Data.Defensives = {
    [250] = { -- Blood Death Knight
        { key = "vampiric_blood", spell = 55233,  duration = 10, strength = 2, dmg = "all" },      -- ingame
        { key = "icebound",       spell = 48792,  duration = 8,  strength = 3, dmg = "all" },      -- ingame
        { key = "drw",            spell = 49028,  duration = 8,  strength = 2, dmg = "physical" }, -- ingame
        { key = "ams",            spell = 48707,  duration = 5,  strength = 2, dmg = "magic" },    -- ingame
        { key = "tombstone",      spell = 219809, duration = 8,  strength = 1, dmg = "all" },      -- ingame (talent)
        { key = "rune_tap",       spell = 194679, duration = 4,  strength = 1, dmg = "all" },      -- ingame (talent)
        { key = "lichborne",      spell = 49039,  duration = 10, strength = 1, dmg = "all" },      -- ingame
    },
    [66] = { -- Protection Paladin
        { key = "guardian_kings",  spell = 86659,  duration = 8,  strength = 3, dmg = "all" },   -- ingame
        { key = "ardent_defender", spell = 31850,  duration = 8,  strength = 3, dmg = "all" },   -- ingame
        { key = "eye_of_tyr",      spell = 387174, duration = 9,  strength = 2, dmg = "all" },   -- ingame (talent)
        { key = "spellwarding",    spell = 204018, duration = 10, strength = 2, dmg = "magic" }, -- ingame (talent; shares CD with BoP)
        { key = "divine_shield",   spell = 642,    duration = 8,  strength = 3, dmg = "all" },   -- ingame (immunity, last resort)
    },
    [581] = { -- Vengeance Demon Hunter
        { key = "fiery_brand",   spell = 204021, duration = 10, strength = 2, dmg = "all" },      -- ingame
        { key = "metamorphosis", spell = 187827, duration = 15, strength = 3, dmg = "all" },      -- ingame
        { key = "demon_spikes",  spell = 203720, duration = 8,  strength = 1, dmg = "physical" }, -- ingame
        { key = "darkness",      spell = 196718, duration = 8,  strength = 1, dmg = "all" },      -- ingame
    },
    [268] = { -- Brewmaster Monk
        { key = "celestial_infusion", spell = 1241059, duration = 16, strength = 2, dmg = "all" },   -- ingame (Midnight)
        { key = "celestial_brew",     spell = 322507,  duration = 8,  strength = 2, dmg = "all" },   -- ingame (choice with Infusion)
        { key = "fortifying_brew",    spell = 115203,  duration = 15, strength = 3, dmg = "all" },   -- ingame
        { key = "diffuse_magic",      spell = 122783,  duration = 6,  strength = 2, dmg = "magic" }, -- ingame (talent)
        { key = "dampen_harm",        spell = 122278,  duration = 10, strength = 2, dmg = "all" },   -- ingame (talent)
        { key = "exploding_keg",      spell = 325153,  duration = 3,  strength = 1, dmg = "physical" }, -- ingame (talent)
    },
    [73] = { -- Protection Warrior
        { key = "shield_wall",      spell = 871,   duration = 8, strength = 3, dmg = "all" },      -- ingame
        { key = "last_stand",       spell = 12975, duration = 15, strength = 2, dmg = "all" },     -- ingame
        { key = "demo_shout",       spell = 1160,  duration = 8, strength = 1, dmg = "all" },      -- ingame
        { key = "spell_reflection", spell = 23920, duration = 5, strength = 1, dmg = "magic" },    -- ingame
        { key = "shield_block",     spell = 2565,  duration = 6, strength = 1, dmg = "physical" }, -- ingame
    },
    [104] = { -- Guardian Druid
        { key = "barkskin",           spell = 22812,  duration = 8,  strength = 2, dmg = "all" },  -- ingame
        { key = "survival_instincts", spell = 61336,  duration = 6,  strength = 3, dmg = "all" },  -- ingame
        { key = "rage_of_sleeper",    spell = 200851, duration = 8,  strength = 2, dmg = "all" },  -- ingame (talent)
        { key = "incarnation",        spell = 102558, duration = 30, strength = 3, dmg = "all" },  -- ingame (talent)
        { key = "frenzied_regen",     spell = 22842,  duration = 3,  strength = 1, dmg = "all" },  -- ingame (heal)
    },
}

-- Default priority per spec: the first ready, not-covered, damage-matching entry wins.
-- Medium cooldowns come first so the big ones stay available for the worst hits.
-- Users reorder these on the Defensive priority page (stored in the reminders profile).
ns.Data.DefensivePresets = {
    [250] = { "vampiric_blood", "drw", "icebound", "ams", "tombstone", "rune_tap", "lichborne" },
    [66]  = { "eye_of_tyr", "guardian_kings", "ardent_defender", "spellwarding", "divine_shield" },
    [581] = { "fiery_brand", "demon_spikes", "metamorphosis", "darkness" },
    [268] = { "celestial_infusion", "celestial_brew", "dampen_harm", "diffuse_magic", "fortifying_brew", "exploding_keg" },
    [73]  = { "shield_block", "demo_shout", "last_stand", "shield_wall", "spell_reflection" },
    [104] = { "barkskin", "rage_of_sleeper", "survival_instincts", "incarnation", "frenzied_regen" },
}

function ns.Data.DefensiveByKey(specID, key)
    for _, d in ipairs(ns.Data.Defensives[specID] or {}) do
        if d.key == key then return d end
    end
end
