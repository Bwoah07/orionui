-- luacheck config. The only globals we may create are listed in `globals` (CLAUDE.md §6.1).
std = "lua51"
max_line_length = false
codes = true
exclude_files = { "**/Libs/**", "tests/mocks/**", "tools/**" }
ignore = {
    "212/self", -- unused self in methods
    "211/ADDON_NAME", -- `local ADDON_NAME, ns = ...` header in every file
}

globals = {
    "OrionUIDB", "OrionUICharDB", "OrionUIAPI", "OrionUIDevDB",
    "SLASH_OUIDEV1", "SLASH_ORIONUI1", "SlashCmdList",
    "OrionUI_OnAddonCompartmentClick", -- named by the TOC (AddonCompartmentFunc)
}

-- WoW API we read. Add to this list when a new API is verified against wow-ui-source.
read_globals = {
    "BigWigsLoader", "DBM", "EllesmereUI", "EncounterJournal",
    "C_AddOns", "C_ChallengeMode", "C_CombatLog", "C_CurveUtil", "C_EncounterJournal",
    "C_EncounterTimeline", "C_RestrictedActions", "C_Secrets", "C_SpecializationInfo",
    "C_Spell", "GetSpecializationInfoByID", "C_SpellBook", "C_Timer", "C_UnitAuras",
    "ChatFontNormal", "CreateFrame", "Enum", "UIParent", "UISpecialFrames", "LibStub",
    "GameTooltip", "ColorPickerFrame", "OKAY", "CANCEL", "STANDARD_TEXT_FONT", "IsShiftKeyDown",
    "UnitClass", "UnitFullName", "GetNormalizedRealmName", "debugstack", "time",
    "EJ_GetDifficulty", "EJ_GetEncounterInfo", "EJ_GetEncounterInfoByIndex", "EJ_GetInstanceInfo",
    "EJ_SelectEncounter", "EJ_SelectInstance", "EJ_SetDifficulty", "EJ_IsValidInstanceDifficulty", "GetLocale",
    "GetBuildInfo", "GetInstanceInfo", "GetTime", "InCombatLockdown", "IsEncounterInProgress",
    "UnitAffectingCombat", "UnitCanAttack", "UnitDetailedThreatSituation", "UnitExists",
    "UnitGUID", "UnitIsUnit", "UnitThreatSituation",
    "canaccesstable", "canaccessvalue", "issecrettable", "issecretvalue",
    "C_VoiceChat", "PlaySound", "SOUNDKIT", "C_CooldownViewer", "C_CurveUtil", "CreateColor",
    "BuffIconCooldownViewer", "BuffBarCooldownViewer",
    "date", "geterrorhandler", "tinsert", "wipe",
}

files["tests/**"] = { std = "+busted" }
