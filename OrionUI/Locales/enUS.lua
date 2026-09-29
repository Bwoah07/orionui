-- English strings. Other locales override keys; a missing key falls back to the key
-- itself, so strings are written as readable English keys.
local _, ns = ...

local L = setmetatable({}, { __index = function(_, key) return key end })
ns.L = L

-- Keys with placeholders or where the key would be awkward as display text.
L.SLASH_HELP = "Commands: /oui (options), /oui edit, /oui log, /oui debug <module|all> <level>, /oui profile <layout|reminders> <name>, /oui reset <module>"
L.COMBAT_REFUSED = "Not possible in combat. It will run when combat ends."
L.IMPORT_CONFIRM = "This replaces the %s profile \"%s\". A backup is made first."
