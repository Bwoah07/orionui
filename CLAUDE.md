# CLAUDE.md: RaidControl (standalone)

This branch is the standalone RaidControl addon, cut out of OrionUI's built-in copy
(OrionUI/RaidControl on main). It carries the launcher tab, its drop-down menu, the action strip
and tank assist's taunt and movement calls (Stig, 2026-10-14; defensive calls are off by default
and not in the settings). Raid Split, lead tools, ready tracker and automation stay in OrionUI.
- Tank assist: Modules/TankAssist*.lua; Modules/BossModTimeline.lua links Blizzard timeline events
  to BigWigs spell keys (ns.BossModTimeline). Alert and bars move with /rc layout.

- The repository root is the addon folder (`RaidControl.toc`). Libraries come from `.pkgmeta`
  externals (Ace3, LibSharedMedia-3.0); `tools/fetch-libs.sh` for local dev. `Libs/` is gitignored.
- Settings: `Settings.lua`, one AceConfig panel (`/rc`, right-click the tab, Escape menu, Blizzard
  AddOns options). Saved variable `RaidControlDB` (AceDB, same name as the old standalone addon).
- Defaults: launcher tab + drop-down menu on (`hideTopBar = false`), action strip off
  (`showActionStrip = false`).
- Do not mention or depend on other UI suites by name anywhere in this branch.
- Never block or taint in combat: the tab and menu are secure frames; layout changes wait for
  the end of combat. WoW 12.x rules apply (secret values, restricted actions).
