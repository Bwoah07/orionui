-- RaidControl esES locale (Spanish (Spain)).
-- Only add keys that have a translation; untranslated keys fall back to enUS.
-- Copy the key from Locales/enUS.lua and assign the translated string, e.g.
-- L["Ready Check"] = "..."

local L = LibStub("AceLocale-3.0"):NewLocale("OrionUIRaidControl", "esES")
if not L then
    return
end
