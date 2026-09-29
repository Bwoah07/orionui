# Verification log

Record every [VERIFY] item from CLAUDE.md here: date, game build, what was tested, result.
Then update CLAUDE.md and remove the [VERIFY] tag.

## 2026-09-29: API documentation findings (not yet tested in game)

Source: Gethe/wow-ui-source, Blizzard_APIDocumentationGenerated.

- `issecretvalue(value)` and `issecrettable(table)` exist (FrameScriptDocumentation.lua).
- **`C_Secrets` namespace** (SecretPredicateAPIDocumentation.lua) can answer secrecy questions directly:
  - `C_Secrets.GetSpellCooldownSecrecy(spell)` → `Enum.SecrecyLevel`: NeverSecret(0) / AlwaysSecret(1) / ContextuallySecret(2)
  - `C_Secrets.ShouldSpellCooldownBeSecret(spell)` → bool
  - `C_Secrets.ShouldCooldownsBeSecret()`, `C_Secrets.ShouldAurasBeSecret()`, `C_Secrets.HasSecretRestrictions()`
  - `C_Secrets.GetSpellAuraSecrecy(spell)`, `ShouldSpellAuraBeSecret(spell)`, `GetSpellCastSecrecy(spell)`
  - `C_Secrets.CanCompareUnitTokens(unit1, unit2)`
- `SecretWhenCooldownsRestricted` = secret during combat, encounter, challenge mode, or PvP restrictions.
  **"Individual spells may be flagged as never or always secret, which takes priority over restrictions."**
  This may explain why Naowh's addon couldn't branch on readiness for some spells: check per spell.
- `C_Spell.GetSpellCooldown`: struct fields `isActive`, `isEnabled`, `isOnGCD` are `NeverSecret`.
- `C_Spell.GetSpellCharges`: `maxCharges` and `isActive` are `NeverSecret`; `currentCharges` can be secret.
- Restriction types (`Enum.AddOnRestrictionType`): Combat 0, Encounter 1, ChallengeMode 2, PvPMatch 3, Map 4, Chat 5.
  States: Inactive 0, Activating 1, Active 2. Event: `ADDON_RESTRICTION_STATE_CHANGED`.
- `C_CombatLog.IsCombatLogRestricted()` → bool.
- `UnitThreatSituation`: `SecretWhenUnitThreatStateRestricted`. `UnitDetailedThreatSituation`: `SecretWhenUnitThreatValuesRestricted`.
- `C_UnitAuras.GetPlayerAuraBySpellID`: `SecretWhenUnitAuraRestricted` + `RequiresNonSecretAura`.
- Spell knowledge: `C_SpellBook.IsSpellKnown(spellID, bank)`, `C_SpellBook.IsSpellInSpellBook(spellID, bank)`.
- Spec: `C_SpecializationInfo.GetSpecialization()`.

**Next:** the `/ouidev secrets` probe should log `C_Secrets.GetSpellCooldownSecrecy` for each tank defensive,
plus `issecretvalue` on every field of GetSpellCooldown / GetSpellCharges, out of combat, in combat,
in an encounter, and in M+.

## 2026-09-29: More API findings from source (not yet tested in game)

Sources cloned to `C:\refs` (outside the repo): wow-ui-source at 12.1.0 (69933), BigWigs 7a42cfe,
DeadlyBossMods 9b5f8bb, EllesmereUI acccae4, Wago-Creator-UI 94bf7de, NorthernSkyRaidTools fa27b53,
Waypoint-UI cc4cc14.

- **Blizzard now has its own encounter timeline** (`C_EncounterTimeline`, events
  `ENCOUNTER_TIMELINE_EVENT_ADDED/REMOVED/STATE_CHANGED/...`). `EncounterTimelineEventInfo`:
  `id`, `source`, `duration`, `maxQueueDuration` are NeverSecret; **`spellID`, `spellName`, `iconFileID`,
  `severity`, `isApproximate` can be secret** (`SecretWhenEncounterEvent`). BigWigs already consumes these
  events (Core/BossPrototype.lua, Plugins/Timeline.lua, several Midnight boss modules). Implication for
  §7.4/§7.5: boss-mod keys may be derived from secret spell IDs, so mechanic identity might have to come
  from the boss mod's own option key or from timing, not spell ID. The `/ouidev bossmod` log will show it.
- `ENCOUNTER_WARNING` payload (`EncounterWarningInfo`): text, caster/target, icon, tooltipSpellID, isDeadly,
  color are all `SecretValue`; duration, severity, shouldPlaySound/Warning are plain.
- `ENCOUNTER_START(encounterID, encounterName, difficultyID, groupSize)`; `ENCOUNTER_END` adds `success`
  and `encounterUnitStatus`.
- `UnitThreatSituation(unit, mobUnit)` takes a **unit token** as 2nd arg. `UnitDetailedThreatSituation`
  returns isTanking, status, scaledPercentage, rawPercentage, rawThreat.
- `UnitGUID` is `SecretWhenUnitIdentityRestricted`; `UnitIsUnit` is `SecretWhenUnitComparisonRestricted`;
  `UnitExists` and `UnitCanAttack` have no secret annotation.
- Player aura APIs (`GetPlayerAuraBySpellID`, `GetAuraDataByIndex`) are `SecretWhenUnitAuraRestricted`;
  `RequiresNonSecretAura` means a nil result can mean "withheld", not "absent" (tri-state!).
- `canaccessvalue(v)`, `canaccesstable(t)`, `canaccesssecrets()` exist. Blizzard's own Dump.lua shows the
  safe pattern: `type()` and `issecretvalue()` are safe on anything; never `tostring` a secret.
- `IsPlayerSpell` is not in the generated docs; use `C_SpellBook.IsSpellKnown(spellID, bank)`.
- Spec: `C_SpecializationInfo.GetSpecialization()` / `GetSpecializationInfo(index)` (returns specId first).
- `GetInstanceInfo()` 8th return is the instance map ID. `C_EncounterJournal.GetInstanceForGameMap(mapID)`
  maps it to a journal instance. `C_ChallengeMode.GetMapUIInfo(id)` 6th return is mapID.
- `EJ_*` globals are not in the generated docs. Return order taken from Blizzard_EncounterJournal usage:
  `EJ_GetEncounterInfoByIndex(i[, instanceID])` → name, description, journalEncounterID, rootSectionID, link,
  ... The 7th return being dungeonEncounterID is **unconfirmed**: `/ouidev ej` prints it.
- `C_EncounterJournal.GetSectionIconFlags(sectionID)` returns indexes into global strings
  `ENCOUNTER_JOURNAL_SECTION_FLAG<n>` (that's how the Journal UI labels them).
- BigWigs messages: `BigWigsLoader.RegisterMessage(owner, msg, fn)`, dispatched as `fn(msg, ...)`; first arg
  after the message is the boss module. Shapes: `BigWigs_StartBar(mod, key, text, time, icon, isApprox, maxTime, nil, eventId)`,
  `BigWigs_Timer(mod, key, time, maxTime, text, counter, icon, isApprox, isBarEnabled)`,
  `BigWigs_TargetTimer(mod, key, time, maxTime, text, counter, icon, player, isBarEnabled)`,
  `BigWigs_Message(mod, key, text, color, icon, emphasized, displayTime)`.
- DBM: `DBM:RegisterCallback(event, fn)`, dispatched as `fn(event, ...)`. Full event list is the
  `DBMCallbackEvent` alias in DBM-Core.lua (DBM_TimerBegin/Stop/Update/Pause/Resume, DBM_Announce, DBM_Pull,
  DBM_Kill, DBM_Wipe, DBM_SetStage, ...). DBM also has `DBM_IgnoreBlizzAPI` / `DBM_ResumeBlizzAPI`.
- Current live interface numbers (from BigWigs/DBM/EUI TOCs): 120100 (and 120105 listed by BigWigs).

## Phase 0 in-game checklist (OrionUI_Dev)

Watch mode is on by default: it snapshots secrets, restrictions, auras and threat 2 s into combat
(at most once a minute), 3 s after ENCOUNTER_START and 5 s after a key starts, and logs every restriction
change and boss-mod/timeline event. `/ouidev log` shows it all in a copy box.

| # | Where | What to do |
|---|---|---|
| 1 | Out of combat, Blood spec, Bone Shield up | `/ouidev all`, copy. `/ouidev auras list`, copy. |
| 2 | Training dummy, in combat | Pull, wait 5 s, `/ouidev all` and `/ouidev threat` (target the dummy). |
| 3 | Dungeon boss (any difficulty) | Just play. Before the pull: `/ouidev ej`. After the boss: `/ouidev log`. |
| 4 | Mythic+ | Just play one boss. Afterwards `/ouidev log`. |

Paste each copy box back into the project thread. The raw log is also in
`WTF/Account/<ACCOUNT>/SavedVariables/OrionUI_Dev.lua`.
