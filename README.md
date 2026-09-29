# OrionUI (working name)

A free, all-included World of Warcraft UI pack built on EllesmereUI.
Work in progress. See CLAUDE.md for the full project brief.

## Local development (Windows)

1. Run `bash tools/fetch-libs.sh` once (fetches LibStub, LibSerialize, LibDeflate into `OrionUI/Libs`).
2. Link the addons into the game (PowerShell):
   `New-Item -ItemType Junction -Path "<WoW>\_retail_\Interface\AddOns\OrionUI" -Target "C:\OrionUI\OrionUI"`
   (same for `OrionUI_Dev`).
3. `/reload` in game. `/oui` opens the options.
