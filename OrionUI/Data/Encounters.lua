-- Curated encounter exceptions (CLAUDE.md §7.12). ALL AUTHORED BY US. The Encounter
-- Journal covers most mechanics; these tables only hold what it gets wrong or lacks.
-- One entry per line, with a comment naming the boss and ability, so diffs stay
-- reviewable. Format documented in docs/data-authoring.md.
local _, ns = ...

-- Mechanics the Journal tags wrongly or not at all.
-- [encounterID] = { [journalSpellID] = { tank = true, buster = true, physical = true, magic = true } }
ns.Data.TankbusterOverrides = {
    -- [3071] = { -- Arcanotron Custos
    --     [474496] = { tank = true, buster = true }, -- Tank Knockback (example shape only; not verified)
    -- },
}

-- Which boss unit casts a mechanic, for multi-boss fights (TankOwnership, §7.6).
-- [encounterID] = { [journalSpellID] = n }  -- n = the N in "bossN"
ns.Data.OwnerUnits = {
}

-- Boss-mod keys that don't equal the Journal spell ID.
-- [encounterID] = { BigWigs = { [key] = journalSpellID }, DBM = { [key] = journalSpellID } }
ns.Data.BossModIDMap = {
}
