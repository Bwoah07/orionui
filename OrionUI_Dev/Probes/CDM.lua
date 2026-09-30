-- /ouidev cdm [filter]
-- Lists every cooldown/buff Blizzard's Cooldown Manager offers for the current spec, per
-- category, with the spell it stands for. Answers "can the CDM track X?" (e.g. Boiling
-- Point) from Blizzard's own API. Read-only. Optional filter: part of a spell name.
local _, ns = ...

local Report = ns.Report
local Describe, Try = ns.Describe, ns.Try

function ns.ProbeCDM(args)
    local filter = args[1] and table.concat(args, " "):lower()
    Report:Begin("CDM")
    local ok, avail = Try(C_CooldownViewer.IsCooldownViewerAvailable)
    Report:Line("available=%s", ok and Describe(avail) or "ERR")
    for name, cat in pairs(Enum.CooldownViewerCategory or {}) do
        local okS, ids = Try(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
        if okS and ns.CanReadTable(ids) then
            Report:Line("%s (%d): %d entries", name, cat, #ids)
            for _, id in ipairs(ids) do
                local okI, info = Try(C_CooldownViewer.GetCooldownViewerCooldownInfo, id)
                if okI and ns.CanReadTable(info) then
                    local spell = info.overrideSpellID or info.spellID
                    local spellName = (type(spell) == "number" and not ns.IsSecret(spell)) and C_Spell.GetSpellName(spell) or "?"
                    if not filter or (type(spellName) == "string" and spellName:lower():find(filter, 1, true)) then
                        Report:Line("   cooldownID=%s spell=%s %s known=%s hasAura=%s selfAura=%s", Describe(id), Describe(spell),
                            Describe(spellName), Describe(info.isKnown), Describe(info.hasAura), Describe(info.selfAura))
                    end
                end
            end
        else
            Report:Line("%s: %s", name, okS and Describe(ids) or ("ERR " .. tostring(ids)))
        end
    end
    return Report:End(args.show ~= false)
end
