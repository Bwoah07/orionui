# RaidControl → OrionUI inventory

Stig's own addon (Author: Bwoah, v1.11.3-beta, ~74k lines incl. Ace3/LibSerialize/LibDeflate).
Source: `C:\Program Files (x86)\World of Warcraft\_retail_\Interfacen\AddOns\Raidcontrol`
(the `Interfacen` folder isn't loaded by the game). Decision 2026-09-30: rewrite its features into
OrionUI as modules on our framework. It is 100% Stig's own addon (confirmed 2026-09-30), so its code,
data and media can be reused freely; the no-copy rule (CLAUDE.md §2.2) doesn't apply to it.
We drop Ace3 (our own module/options/profile system replaces it).

Surveyed 2026-09-30 from module headers only; details to be read per module when ported.

| Module | Lines | What it does | Plan |
|---|---|---|---|
| RaidSplit | 6331 | Smart raid splits (groups by role/spec, balancing) | **Port: core raid-organization feature** |
| Roles | 315 | Melee/ranged/role detection by spec ID | Port with RaidSplit (shared helper) |
| RaidLeadTools | 3336 | Lead panel: healer mana, battle-res history, comms | Port (check overlap with EUI BattleRes) |
| ReadyTracker | 1878 | Ready-check roster: consumables/issues view | Port (tri-state rules, §6.6) |
| ConsumableChecker | 139 | Manual consumable scan + chat report | Merge into ReadyTracker port |
| SynergyAnalyzer | 52 | Missing raid buffs for the roster | Merge into ReadyTracker port |
| BossNotes | 9465 | Per-boss notes, Encounter Journal driven | Port later; big (split into files) |
| NoteReminders | 1185 | Reminders from notes (melee/ranged aware) | Fold into OrionUI Custom reminders |
| NSRTInterop | 464 | Northern Sky Raid Tools integration | Decide later (NSRT is All Rights Reserved) |
| TankAssist / TankAssistMidnight / AlertHUD / CountdownAudio | ~5100 | Tank mechanics: boss ownership, **Encounter Timeline "Finished" as the trigger on restricted maps**, alert HUD, countdown audio | Compare with OrionUI's reminder engine; take the ideas we lack (timeline-driven triggers, countdown audio) |
| AutoMarker | 938 | Auto raid markers (inspect-based roles for M+) | Port |
| AutoInvite | 100 | Invite on whisper/keyword | Port (small) |
| AutoAssist | 422 | Auto-promote assists | Port (small) |
| KeySync | 298 | M+ keystone sharing over addon comms | Port |
| CombatLogger | 243 | Prompt to enable combat logging per content | Port (EUI QoL has AutoLogging: check overlap) |
| AutoVendor | 79 | Auto repair / sell junk | Covered by EUI QoL? check; else port (fail closed, §8.5) |
| MarkerBar / Control / ActionStrip | ~2100 | Top bar, marker bar, pull/ready buttons, action strip | **Port** (Stig, 2026-09-30): the top bar, drop-down menu and action strip do more than EUI's Raid Tools |
| LayoutMode | 817 | Launcher drop-down menu (secure) + its layout mode | **Port the launcher drop-down menu** (Stig); its layout/edit mode is replaced by OrionUI's |
| Workspace / FrameScaling / SettingsV2 | ~4200 | Its own UI shell and settings | Skip: OrionUI has these |
| Screenshot | 526 | Screenshot CVar profile | Low priority |
| RaidDemo | 391 | Demo roster for testing UI | Port as a dev/test helper |
| OrionImport | 308 | Import of Orion guild settings | Replace with the OrionUI installer |
| BlizzardOptions / Settings | ~4600 | Settings panels | Skip (OrionUI options) |
