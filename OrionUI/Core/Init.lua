-- OrionUI core: namespace and constants. The single source of the display name, so a
-- rename is ns.NAME plus folder/TOC/global names (CLAUDE.md §6.1).
local ADDON_NAME, ns = ...

ns.NAME = "OrionUI"
ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"
ns.TANKED_GRACE = 6 -- seconds a player still counts as tanking a boss (CLAUDE.md §7.6)
