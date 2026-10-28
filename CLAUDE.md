# CLAUDE.md: RaidControl (standalone)

This branch is the standalone RaidControl addon, cut out of OrionUI's built-in copy
(OrionUI/RaidControl on main). It carries the launcher tab, its drop-down menu, the action strip
and tank assist's taunt and movement calls (Stig, 2026-10-14; defensive calls are off by default
and not in the settings). Raid Split came back on 2026-10-14 as its own top tab; the ready check panel (Modules/ReadyTracker.lua) came back too, with durability sync between RaidControl users (Modules/Durability.lua, prefix RCLEAD; also reads and answers the shared LibDurability protocol, prefix LibDRBLT); lead tools, boss notes and
automation stay in OrionUI.
- Loot window and loot roll frames (Modules/Loot.lua), Loot history cards (Modules/LootHistory.lua, `/rc lootfeed`) and the
  Loot appraiser window (Modules/LootAppraiser.lua, `/rc la`), from OrionUI; shared look, prices and event bus in
  Modules/LootKit.lua. Settings under Interface > Loot Window / Loot History / Loot Appraiser; frames move in /rc layout.
- Blood DK Bone Shield icon (Modules/BoneShield.lua, from OrionUI; settings under Tank > Bone Shield, `/rc bone` diagnostics).
- Tank assist: Modules/TankAssist*.lua; Modules/BossModTimeline.lua links Blizzard timeline events
  to BigWigs spell keys (ns.BossModTimeline). Alert and bars move with /rc layout.

- The repository root is the addon folder (`RaidControl.toc`). Libraries come from `.pkgmeta`
  externals (Ace3, LibSharedMedia-3.0); `tools/fetch-libs.sh` for local dev. `Libs/` is gitignored.
- Settings: the original RaidControl settings window (Modules/Settings.lua + Modules/SettingsV2/,
  from the Bwoah07/Raidcontrol repo) inside the original Workspace host (Modules/Workspace.lua).
  Top tabs: Settings (Interface, Ready Check, Screenshots, Look & Feel), Raid Split (Modules/RaidSplit.lua) and
  Tank (the Tank settings page, hidden from the sidebar). Opened by `/rc`, `/rc split`, `/rc tank`,
  right-click the tab, Escape menu, Blizzard AddOns page and the
  addon compartment (Modules/BlizzardOptions.lua). Saved variable `RaidControlDB` (AceDB, same name as the old standalone addon).
- Defaults: launcher tab + drop-down menu on (`hideTopBar = false`), action strip off
  (`showActionStrip = false`).
- Do not mention or depend on other UI suites by name anywhere in this branch.
- Never block or taint in combat: the tab and menu are secure frames; layout changes wait for
  the end of combat. WoW 12.x rules apply (secret values, restricted actions).
