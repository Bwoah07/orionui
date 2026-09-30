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

-- Every other spec (Phase 4b, 2026-09-30). Researched from own class knowledge and current
-- guides; "unverified" until /oui check defensives returns the right names in game.
-- Most personal defensives are class-wide, so each class has a shared list and specs add
-- their extras. Entries are listed in default priority order (see DefensivePresets below).
-- duration = 0 for heals and short absorbs: they never count as "already covering" you.
local function D(key, spell, duration, strength, dmg)
    return { key = key, spell = spell, duration = duration, strength = strength, dmg = dmg or "all" }
end

local CLASS = {
    DEATHKNIGHT = {
        D("ams",         48707, 5,  2, "magic"), -- unverified for DPS specs (tank IDs ingame)
        D("icebound",    48792, 8,  3),
        D("lichborne",   49039, 10, 1),
        D("death_pact",  48743, 0,  1),          -- talent, heal
        D("amz",         51052, 6,  2, "magic"), -- talent, group
    },
    DEMONHUNTER = {
        D("blur",        198589, 10, 2),
        D("darkness",    196718, 8,  1),
    },
    DRUID = {
        D("barkskin",    22812,  8,  2),
        D("renewal",     108238, 0,  1),         -- talent, heal
    },
    EVOKER = {
        D("obsidian_scales", 363916, 12, 2),
        D("renewing_blaze",  374348, 8,  1),     -- talent
        D("zephyr",          374227, 8,  1),     -- talent, group
    },
    HUNTER = {
        D("sotf",         264735, 8, 2),         -- Survival of the Fittest
        D("exhilaration", 109304, 0, 1),         -- heal
        D("turtle",       186265, 8, 3),         -- Aspect of the Turtle (immunity, last resort)
    },
    MAGE = {
        D("mirror_image", 55342,  10, 1),
        D("alter_time",   342245, 10, 1),
        D("greater_invis", 110959, 3, 2),
        D("ice_cold",     414658, 6,  3),        -- talent, replaces Ice Block
        D("ice_block",    45438,  10, 3),        -- immunity, last resort
        D("mass_barrier", 414660, 0,  1),        -- talent, group
    },
    MONK = {
        D("diffuse_magic",   122783, 6,  2, "magic"),
        D("dampen_harm",     122278, 10, 2),
        D("fortifying_brew", 115203, 15, 3),
    },
    PALADIN = {
        D("divine_protection", 498, 8, 2),
        D("divine_shield",     642, 8, 3),       -- immunity, last resort
    },
    PRIEST = {
        D("desperate_prayer", 19236, 10, 1),
        D("fade",             586,   10, 1),     -- damage reduction via talent
    },
    ROGUE = {
        D("feint",        1966,   6,  1),
        D("cloak",        31224,  5,  2, "magic"),
        D("evasion",      5277,   10, 2, "physical"),
        D("crimson_vial", 185311, 0,  1),        -- heal
    },
    SHAMAN = {
        D("astral_shift",  108271, 12, 2),
        D("stone_bulwark", 108270, 0,  1),       -- talent, absorb
    },
    WARLOCK = {
        D("dark_pact",        108416, 0, 2),     -- talent, absorb
        D("unending_resolve", 104773, 8, 3),
    },
    WARRIOR = {
        D("spell_reflection",  23920,  5,  1, "magic"),
        D("impending_victory", 202168, 0,  1),   -- talent, heal
        D("rallying_cry",      97462,  10, 1),   -- group
    },
}

-- specID -> { class, extras placed first, before the shared class list }
local SPECS = {
    [251] = { "DEATHKNIGHT" }, [252] = { "DEATHKNIGHT" },                 -- Frost, Unholy
    [577] = { "DEMONHUNTER" }, [1480] = { "DEMONHUNTER" },                -- Havoc, Devourer
    [102] = { "DRUID" },                                                  -- Balance
    [103] = { "DRUID", { D("survival_instincts", 61336, 6, 3) } },        -- Feral
    [105] = { "DRUID", { D("ironbark", 102342, 12, 2) } },                -- Restoration (self)
    [1467] = { "EVOKER" }, [1468] = { "EVOKER" }, [1473] = { "EVOKER" },  -- Dev, Pres, Aug
    [253] = { "HUNTER" }, [254] = { "HUNTER" }, [255] = { "HUNTER" },     -- BM, MM, SV
    [62] = { "MAGE", { D("prismatic_barrier", 235450, 0, 1) } },          -- Arcane
    [63] = { "MAGE", { D("blazing_barrier", 235313, 0, 1) } },            -- Fire
    [64] = { "MAGE", { D("ice_barrier", 11426, 0, 1) } },                 -- Frost
    [269] = { "MONK", { D("touch_of_karma", 122470, 10, 2) } },           -- Windwalker
    [270] = { "MONK" },                                                   -- Mistweaver
    [65] = { "PALADIN" },                                                 -- Holy
    [70] = { "PALADIN", { D("shield_of_vengeance", 184662, 10, 1) } },    -- Retribution
    [256] = { "PRIEST", { D("pain_suppression", 33206, 8, 3) } },         -- Discipline (self)
    [257] = { "PRIEST" },                                                 -- Holy
    [258] = { "PRIEST", { D("dispersion", 47585, 6, 3), D("vampiric_embrace", 15286, 0, 1) } }, -- Shadow
    [259] = { "ROGUE" }, [260] = { "ROGUE" }, [261] = { "ROGUE" },        -- Assa, Outlaw, Sub
    [262] = { "SHAMAN" }, [263] = { "SHAMAN" }, [264] = { "SHAMAN" },     -- Ele, Enh, Resto
    [265] = { "WARLOCK" }, [266] = { "WARLOCK" }, [267] = { "WARLOCK" },  -- Aff, Demo, Destro
    [71] = { "WARRIOR", { D("die_by_the_sword", 118038, 8, 2) } },        -- Arms
    [72] = { "WARRIOR", { D("enraged_regeneration", 184364, 8, 2) } },    -- Fury
}

for specID, s in pairs(SPECS) do
    local list = {}
    for _, d in ipairs(s[2] or {}) do list[#list + 1] = d end
    for _, d in ipairs(CLASS[s[1]]) do list[#list + 1] = d end
    ns.Data.Defensives[specID] = list
end

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
-- Specs without a hand-written order use catalog order.
for specID, list in pairs(ns.Data.Defensives) do
    if not ns.Data.DefensivePresets[specID] then
        local keys = {}
        for i, d in ipairs(list) do keys[i] = d.key end
        ns.Data.DefensivePresets[specID] = keys
    end
end

function ns.Data.DefensiveByKey(specID, key)
    for _, d in ipairs(ns.Data.Defensives[specID] or {}) do
        if d.key == key then return d end
    end
end
