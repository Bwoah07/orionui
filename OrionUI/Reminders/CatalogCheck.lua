-- /oui check defensives: lists every defensive in Data/Defensives.lua with the name the
-- game returns for its spell ID, so a wrong ID shows up as "MISSING" or a wrong name.
-- Spell names are never secret, so this is safe anywhere. For your current spec it also
-- says whether you know the spell (talent picked).
local _, ns = ...

local L = ns.L

local function Check()
    local specs = {}
    for specID in pairs(ns.Data.Defensives) do specs[#specs + 1] = specID end
    table.sort(specs)
    local lines, missing = {}, 0
    for _, specID in ipairs(specs) do
        local _, specName, _, _, _, classFile = GetSpecializationInfoByID(specID)
        lines[#lines + 1] = ("%d %s %s"):format(specID, tostring(classFile), tostring(specName))
        for _, d in ipairs(ns.Data.Defensives[specID]) do
            local name = C_Spell.GetSpellName(d.spell)
            if not name then missing = missing + 1 end
            local known = ""
            if specID == ns.Player.specID then
                known = C_SpellBook.IsSpellKnown(d.spell) and "  known" or "  not known"
            end
            lines[#lines + 1] = ("  %-20s %7d  %s%s"):format(d.key, d.spell, name or "MISSING", known)
        end
    end
    table.insert(lines, 1, ("%d specs, %d spell IDs the game doesn't know"):format(#specs, missing))
    ns.CopyBox:Show(L["Defensive catalog check"], table.concat(lines, "\n"))
end

ns.Slash:Register("check", function(args)
    if args[1] ~= "defensives" then ns.Print("/oui check defensives") return end
    Check()
end, "defensives  (every defensive spell ID with the game's name for it)")
