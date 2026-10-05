-- OrionUI core: namespace and constants. ns.NAME is the single source of the display
-- name, so a rename is ns.NAME plus folder/TOC/global names (CLAUDE.md §6.1).
local ADDON_NAME, ns = ...

ns.NAME = "OrionUI"
-- Short name in front of every chat line (Stig, 2026-10-05: "OrionUIRaidControl:" was too long).
ns.CHAT_PREFIX = "|cff2673d9Orion|r"
ns.ADDON_NAME = ADDON_NAME
ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
-- Packaged builds replace the token; an unreplaced token means a git checkout.
ns.IS_DEV = ns.VERSION:find("project%-version") ~= nil or ns.VERSION == "dev"

ns.TANKED_GRACE = 6 -- seconds a player still counts as tanking a boss (CLAUDE.md §7.6)
ns.MAX_BACKUPS = 5
ns.MEDIA_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"

ns.Data = {} -- curated data tables (Data/*.lua, phase 3)
