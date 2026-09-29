# Data authoring

Everything in `OrionUI/Data/` is written by us. Nothing is copied from other packs (CLAUDE.md §2).
The Encounter Journal already gives bosses, abilities, spell IDs and role/mechanic tags; these tables
only hold the exceptions.

Rules:
- One entry per line, with a comment naming the boss and the ability.
- Key everything on the `encounterID` from `ENCOUNTER_START` (the Journal's dungeonEncounterID).
- Before adding an entry, check the Journal data with `/oui catalog` inside the instance.
- Mark anything not seen in game with `-- unverified`.

## `Data/Encounters.lua`

```lua
-- Tags the Journal gets wrong or lacks. Merged over the Journal's tags.
ns.Data.TankbusterOverrides[encounterID] = {
    [journalSpellID] = { tank = true, buster = true, physical = true }, -- Boss: Ability
}

-- Which boss unit casts it (multi-boss fights). N as in "bossN".
ns.Data.OwnerUnits[encounterID] = {
    [journalSpellID] = 2, -- Boss: Ability (cast by boss2)
}

-- A boss-mod key that isn't the Journal spell ID.
ns.Data.BossModIDMap[encounterID] = {
    BigWigs = { [bigWigsKey] = journalSpellID }, -- Boss: Ability
    DBM = { [dbmSpellId] = journalSpellID },
}
```

Tag names come from `Enum.JournalEncounterIconFlags` in lower case (`tank`, `dps`, `healer`, `heroic`,
`deadly`, `important`, `interruptible`, `magic`, `curse`, `poison`, `disease`, `enrage`, `mythic`,
`bleed`) plus our own (`buster`, `physical`).
