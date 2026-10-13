# CLAUDE.md: RaidControl (standalone)

This branch is the standalone RaidControl addon, cut out of OrionUI's built-in copy
(OrionUI/RaidControl on main). It only carries the launcher tab, its drop-down menu and the
action strip; Raid Split, tank assist, lead tools, ready tracker and automation stay in OrionUI.

- The repository root is the addon folder (`RaidControl.toc`). Libraries come from `.pkgmeta`
  externals (Ace3, LibSharedMedia-3.0); `tools/fetch-libs.sh` for local dev. `Libs/` is gitignored.
- Settings: `Settings.lua`, one AceConfig panel (`/rc`, right-click the tab, Escape menu, Blizzard
  AddOns options). Saved variable `RaidControlDB` (AceDB, same name as the old standalone addon).
- Defaults: launcher tab + drop-down menu on (`hideTopBar = false`), action strip off
  (`showActionStrip = false`).
- Do not mention or depend on other UI suites by name anywhere in this branch.
- Never block or taint in combat: the tab and menu are secure frames; layout changes wait for
  the end of combat. WoW 12.x rules apply (secret values, restricted actions).
