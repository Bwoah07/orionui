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

-- Hearthstone toy IDs from Data/Hearthstones.lua with the game's name and whether you own it.
-- Item names can need a moment to load; run it twice if some say "loading".
local function CheckHearthstones()
    local lines = {}
    local ids = { ns.Data.HEARTHSTONE_ITEM }
    for _, id in ipairs(ns.Data.HearthstoneToys) do ids[#ids + 1] = id end
    for _, t in ipairs(ns.Data.TeleportToys) do ids[#ids + 1] = t.item end
    for _, id in ipairs(ids) do
        local name = C_Item.GetItemNameByID(id)
        if not name then C_Item.RequestLoadItemDataByID(id) end
        local owned = (PlayerHasToy and PlayerHasToy(id)) and "  owned" or ""
        lines[#lines + 1] = ("%7d  %s%s"):format(id, name or "loading / MISSING", owned)
    end
    ns.CopyBox:Show(L["Hearthstone check"], table.concat(lines, "\n"))
end

-- Interrupt spell IDs per class (Data/Interrupts.lua) and which one the focus cast bar uses.
local function CheckInterrupts()
    local lines = {}
    local using = ns.FocusCastBarKick and ns.FocusCastBarKick()
    lines[1] = "focus cast bar uses: " .. tostring(using and C_Spell.GetSpellName(using) or "none")
    for class, ids in pairs(ns.Data.Interrupts) do
        for _, id in ipairs(ids) do
            lines[#lines + 1] = ("%-12s %7d  %s"):format(class, id, C_Spell.GetSpellName(id) or "MISSING")
        end
    end
    ns.CopyBox:Show(L["Interrupt check"], table.concat(lines, "\n"))
end

ns.Slash:Register("check", function(args)
    if args[1] == "defensives" then Check()
    elseif args[1] == "hearthstones" then CheckHearthstones()
    elseif args[1] == "interrupts" then CheckInterrupts()
    else ns.Print("/oui check defensives | hearthstones | interrupts") end
end, "defensives | hearthstones | interrupts  (IDs with the game's names)")
