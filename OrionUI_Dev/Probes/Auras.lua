-- /ouidev auras [list | spellID ...]
-- Can we read our own buffs (Bone Shield stacks/expiry, active defensives) in each
-- restriction state? "list" dumps every helpful aura on the player so buff IDs we
-- don't know yet (e.g. Boiling Point) can be discovered.
local _, ns = ...

local Report = ns.Report
local Describe, DescribeFields, SecretSummary, Try = ns.Describe, ns.DescribeFields, ns.SecretSummary, ns.Try

-- Fields we care about; any other fields are appended by DescribeFields automatically.
local AURA_FIELDS = { "name", "spellId", "applications", "duration", "expirationTime", "auraInstanceID", "sourceUnit", "isFromPlayerOrPlayerPet" }
local MAX_LIST = 60

local function ProbeAura(entry)
    local id = entry.id
    local S = C_Secrets or {}
    local okS, sec = Try(S.GetSpellAuraSecrecy, id)
    local okB, should = Try(S.ShouldSpellAuraBeSecret, id)
    Report:Line("-- %d %s [%s] auraSecrecy=%s shouldBeSecret=%s", id, entry.label or "?", entry.status or "custom",
        okS and ns.EnumName(Enum.SecrecyLevel, sec) or ("ERR " .. tostring(sec)), okB and Describe(should) or ("ERR " .. tostring(should)))
    local ok, aura = Try(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if not ok then
        Report:Line("   ERR %s", tostring(aura))
    elseif type(aura) == "nil" then
        -- The API is RequiresNonSecretAura: nil can mean "not active" OR "withheld".
        Report:Line("   nil (not active, or withheld because secret)")
    else
        Report:Line("   %s", DescribeFields(aura, AURA_FIELDS))
        Report:Line("   secrecy: %s", SecretSummary(aura, AURA_FIELDS))
    end
end

local function ListAll()
    Report:Line("helpful auras on player (GetAuraDataByIndex):")
    for i = 1, MAX_LIST do
        local ok, aura = Try(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
        if not ok then Report:Line("   ERR %s", tostring(aura)) break end
        if type(aura) == "nil" then
            Report:Line("   (%d auras)", i - 1)
            break
        end
        if ns.CanReadTable(aura) then
            Report:Line("   #%d spellId=%s name=%s stacks=%s expires=%s", i, Describe(aura.spellId),
                Describe(aura.name), Describe(aura.applications), Describe(aura.expirationTime))
        else
            Report:Line("   #%d <inaccessible table>", i)
        end
    end
end

function ns.ProbeAuras(args)
    Report:Begin("AURAS")
    if args[1] == "list" then
        ListAll()
    else
        local list = {}
        for _, a in ipairs(args) do
            local id = tonumber(a)
            if id then list[#list + 1] = { id = id, label = "custom" } end
        end
        if #list == 0 then list = ns.AuraLists[ns.CurrentSpecID() or 0] or {} end
        if #list == 0 then Report:Line("no aura list for this spec; use /ouidev auras list or /ouidev auras <spellID>") end
        for _, e in ipairs(list) do ProbeAura(e) end
    end
    return Report:End(args.show ~= false)
end
