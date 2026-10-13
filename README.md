# RaidControl

A small, free raid helper for World of Warcraft (Retail, Midnight).

- **Launcher tab**: a slim tab you can place anywhere. Click it to open the drop-down menu.
- **Drop-down menu**: ready check, pull timer, convert party / raid, difficulty, guild invite,
  clear markers, disband, screenshot, tank / healer / DPS counts and raid marker buttons.
- **Action strip** (off by default): the same buttons as a single row you can place anywhere.

Defaults: the launcher tab and its drop-down menu are on, the action strip is off.

## Commands

- `/rc` opens the settings (also right-click the tab, the Escape menu, or Options > AddOns > RaidControl)
- `/rc help` lists every command
- `/rc layout` moves the tab and the action strip; `/rc reset` puts the tab back in the centre
- `/rc strip` shows or hides the action strip
- `/rc pull [seconds]` starts a pull timer (`/rc pull 0` cancels it)

Key bindings for target markers, world markers and the marker cycle are under
Options > Keybindings > AddOns > RaidControl.

## Development

The repository root is the addon folder. Run `bash tools/fetch-libs.sh` once to fetch Ace3 into
`Libs/` (LibSharedMedia-3.0 must be copied in by hand, see the script), then link or copy the
folder to `World of Warcraft/_retail_/Interface/AddOns/RaidControl`.

Releases are built by the BigWigs packager (`.pkgmeta`): pushing a `v*` tag runs
`.github/workflows/release.yml`, which uploads to CurseForge once the `CF_API_KEY` secret and
`## X-Curse-Project-ID` in `RaidControl.toc` are set.
