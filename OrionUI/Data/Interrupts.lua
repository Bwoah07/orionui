-- The player's interrupt per class, used for the focus cast bar's "kick ready" colour.
-- Authored by us (spell IDs are game facts). The first one the player knows wins.
-- IDs from memory (2026-09-30), to confirm in game with /oui check interrupts.
local _, ns = ...

ns.Data.Interrupts = {
    DEATHKNIGHT = { 47528 },          -- Mind Freeze
    DEMONHUNTER = { 183752 },         -- Disrupt
    DRUID       = { 106839, 78675 },  -- Skull Bash, Solar Beam
    EVOKER      = { 351338 },         -- Quell
    HUNTER      = { 147362, 187707 }, -- Counter Shot, Muzzle
    MAGE        = { 2139 },           -- Counterspell
    MONK        = { 116705 },         -- Spear Hand Strike
    PALADIN     = { 96231 },          -- Rebuke
    PRIEST      = { 15487 },          -- Silence
    ROGUE       = { 1766 },           -- Kick
    SHAMAN      = { 57994 },          -- Wind Shear
    WARLOCK     = { 119910, 19647 },  -- Spell Lock (Command Demon), Spell Lock (Felhunter)
    WARRIOR     = { 6552 },           -- Pummel
}
