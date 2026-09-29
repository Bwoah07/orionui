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

## 2026-09-29: In-game results, open world (build 12.1.0 69933, Blood DK)

Ran `/ouidev all`, `/ouidev auras list`, `/ouidev threat` out of combat and on a training dummy.

- **Out of combat:** every restriction type is off, but `C_Secrets.HasSecretRestrictions()` = true and
  **`C_CombatLog.IsCombatLogRestricted()` = true even in the open world out of combat.** Treat CLEU as
  unavailable by default. Every cooldown/charge field is readable.
- **In combat (Combat restriction ON only):** `ShouldCooldownsBeSecret` and `ShouldAurasBeSecret` = true.
  In `GetSpellCooldown`, `startTime`, `duration`, `modRate` and `timeUntilEndOfStartRecovery` are secret, but
  **`isActive` and `isEnabled` stay readable**, as documented. In `GetSpellCharges`, `maxCharges` and
  `isActive` are readable and everything else is secret. So `ReadinessStrategy.API` works in combat on a
  dummy: we can tell "on cooldown or not" but not "how long is left".
  Still to confirm: Encounter and ChallengeMode restriction states.
- `isOnGCD` came back nil outside `SPELL_UPDATE_COOLDOWN`, matching the docs.
- Every Blood spell in the list has `GetSpellCooldownSecrecy` = ContextuallySecret (none is flagged
  NeverSecret or AlwaysSecret).
- **Spell IDs confirmed by name in game:** 55233 Vampiric Blood, 48707 Anti-Magic Shell, 48792 Icebound
  Fortitude, 49028 Dancing Rune Weapon, 194679 Rune Tap, 219809 Tombstone, 51052 Anti-Magic Zone,
  49039 Lichborne. (Rune Tap and Tombstone were known=false because they aren't talented.)
- Bone Shield (195181): not tested yet. It wasn't active during the test.
- Threat on the training dummy: `UnitThreatSituation` / `UnitDetailedThreatSituation` returned nil (not
  secret) for `target`. This probably means the dummy has no threat table. Needs a real boss.
- **Player auras in combat are withheld from us.** With `ShouldAurasBeSecret` = true:
  `C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")` **throws** "Auras cannot be accessed when secret
  while tainted" (and taints the caller), and `GetPlayerAuraBySpellID` returns nil for everything.
  Consequences: never iterate auras by index while auras are secret. Coverage (§7.8) can't read active
  defensives from auras in combat and has to rely on cast tracking or fail open. Bone Shield stacks and expiry
  (§8.3) must be displayed by engine widgets (CDM / aura containers), not computed in Lua.

## 2026-09-29: In-game results, dungeon boss (Magisters' Terrace, follower dungeon diff 205, BigWigs)

Encounter 3071 "Arcanotron Custos", with watch mode on.

- **Restriction states in a dungeon:** `Map` is ON the whole time inside the instance. During the boss,
  Combat, Encounter, Map and **Chat** are all ON. `ADDON_RESTRICTION_STATE_CHANGED` fires "activating" at
  ENCOUNTER_START and "off" at ENCOUNTER_END, as documented.
- **Cooldown readiness during a boss fight:** same as in open-world combat. `isActive` and `isEnabled` are
  readable, and the timing fields are secret. **ReadinessStrategy.API works under the Encounter restriction.**
  Only ChallengeMode (M+) is still unconfirmed.
- **Player auras:** withheld in dungeon combat and in the encounter (same as in the open world).
- **Threat (important for TankOwnership §7.6):**
  - `UnitThreatSituation("player", "boss1")` = 3, **readable** during the encounter.
  - `UnitDetailedThreatSituation("player", "boss1")`: **every return is secret**.
  - Oddly, `UnitDetailedThreatSituation("player", "target")` was readable while the target was boss1. Don't
    rely on this: use `UnitThreatSituation(player, bossN)` (status 3 = securely tanking, 2 = tanking but insecure).
  - On dungeon trash (no encounter) both threat calls were readable on `target`.
  - `C_Secrets.CanCompareUnitTokens("target","boss1")` = true and `UnitIsUnit` is readable in the encounter.
  - `UnitGUID` is secret on every enemy inside the instance, trash included. Unit tokens it is.
- **BigWigs payloads are plain even when Blizzard's timeline is secret:**
  - The Blizzard timeline `EVENT_ADDED` has spellID, spellName, icon, severity and isApproximate **secret**.
    Only `id`, `source`, `duration` and `maxQueueDuration` are plain.
  - BigWigs still sends plain keys (spell IDs like 474496 "Tank Knockback", 1214081, 1214032, 474345),
    plain durations, text and icon.
  - `BigWigs_StartBar`'s **9th argument is the Blizzard timeline event id** (1, 2, 3...). It links a BigWigs
    bar to a timeline event.
  - **Every timer fires both `BigWigs_StartBar` and `BigWigs_Timer`**, so the bridge must dedupe.
  - **`BigWigs_StopBar(mod, text)` carries only the bar text, not the key.** The bridge has to remember
    text → key from StartBar to cancel the right mechanic.
  - When a bar ends, BigWigs sends `BigWigs_Message(mod, key, text, color, icon, false, nil)` with the same key.
  - Non-boss BigWigs modules also send messages ("Victory", "Statistics", "BossBlock"). Filter by module.
  - End of fight: `ENCOUNTER_END(3071, name, 205, 5, success=1, unitStatus)`, then `BigWigs_OnBossWin`,
    then `BigWigs_OnBossDisable` about 1 s later.
- `/ouidev ej` wasn't run, so the 7th return of `EJ_GetEncounterInfoByIndex` is still unconfirmed.

## 2026-09-29: In-game results, Mythic+ (Den of Nalorakk, 4 bosses, BigWigs)

- `ChallengeMode` restriction goes to "activating" when the key starts and "off" after the last boss.
  During the key, Map and Chat are also ON. In boss fights, all of Combat, Encounter, ChallengeMode, Map and
  Chat are ON.
- **Cooldown readiness:** all 168 `/ouidev secrets` verdicts in the log (open world, dungeon, M+ trash and
  M+ bosses 3207, 3208, 3209) say `isActive` was readable. **ReadinessStrategy.API is confirmed for every
  PvE restriction state.**
- **Threat:** `UnitThreatSituation("player", "boss1")` stayed readable (3 = tanking) in every M+ boss.
  `UnitDetailedThreatSituation` on bossN was always secret. On Nalorakk, boss2 existed with
  `canAttack=false` and nil threat, so treat an attackable unit with nil threat as "not on its threat table".
- `CanCompareUnitTokens` = true and `UnitIsUnit(target, bossN)` is readable in M+ encounters.
- Player auras are withheld in M+ combat as elsewhere.

## 2026-09-29: Bone Shield confirmed

Out of combat, `/ouidev auras list` shows **Bone Shield = 195181** (stacks 12, expiry readable) and
**Ossuary = 219788** as player auras. Both are readable out of combat only (auras are withheld in combat,
see above).

## 2026-09-29: Encounter Journal dump (Temple of Sethraliss, Mythic)

- `C_EncounterJournal.GetInstanceForGameMap(instanceMapID)` works with `GetInstanceInfo()`'s 8th return
  (1877 -> journal instance 1030).
- **The 7th return of `EJ_GetEncounterInfoByIndex` is the dungeonEncounterID**: it gave 2124, 2125, 2126 and
  2127 for the four bosses, which are Temple of Sethraliss's known encounter IDs. That's the same ID space
  as `ENCOUNTER_START` (e.g. 3071, 3207 in earlier logs). Key JournalCatalog on it, as §7.3 says.
- `headerType` matches `Enum.JournalEncounterSecTypes`: 0 stage, 1 creature, 2 ability, 3 overview.
- Role/mechanic flags come through (Tank Alert, Healer Alert, Important, Deadly, Interruptible, Poison,
  Mythic Difficulty...). Tank-tagged abilities here: Overload, Lightning Bite, Tainted Strike.
- **The Journal keeps its own difficulty** (it reported EJ difficulty 1 while we were in a Mythic
  dungeon), and difficulty-specific sections come back as duplicates with `filteredByDifficulty=true`.
  JournalCatalog must set the Journal difficulty to the instance difficulty before scraping (and restore
  the user's choice afterwards), and skip filtered sections.
- The same spell can appear more than once (Tempest Winds, Lingering Storm): dedupe by spellID per encounter.
