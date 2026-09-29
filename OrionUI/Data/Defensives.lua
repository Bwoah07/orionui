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
-- Spell IDs marked "ingame" returned the right name in game on 2026-09-29
-- (docs/verification-log.md). Durations are unverified.
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
}

-- Default priority per spec: the first ready, not-covered, damage-matching entry wins.
-- Users reorder these on the Defensives page (stored in the reminders profile).
ns.Data.DefensivePresets = {
    [250] = { "vampiric_blood", "drw", "icebound", "ams", "tombstone", "rune_tap", "lichborne" },
}

function ns.Data.DefensiveByKey(specID, key)
    for _, d in ipairs(ns.Data.Defensives[specID] or {}) do
        if d.key == key then return d end
    end
end
