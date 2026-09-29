-- MechanicRegistry (CLAUDE.md §7.5): the neutral identity layer between the Journal,
-- our curated data and whatever key a boss mod uses. Neither BigWigs nor DBM IDs are
-- "the" language; everything downstream sees InternalMechanic objects.
--
--   InternalMechanic = { id, encounterID, journalSpellID, sectionID, title, icon,
--                        tags = { tank = true, deadly = true, ... }, ownerUnit, adhoc }
--
-- Resolution order for a boss-mod key: curated BossModIDMap -> negative key = Journal
-- section (BigWigs convention) -> Journal spell ID -> ad-hoc mechanic. Unknown keys
-- still resolve (as ad-hoc) so custom reminders can target anything a boss mod emits.
local _, ns = ...

local Registry = { byEncounter = {}, looseAdhoc = {} }
ns.MechanicRegistry = Registry

local function Tags(base, override)
    local tags = {}
    for k, v in pairs(base or {}) do tags[k] = v end
    for k, v in pairs(override or {}) do tags[k] = v end
    return tags
end

-- Builds (once) the mechanics of an encounter from the Journal catalog + curated data.
function Registry:LoadEncounter(encounterID)
    if not encounterID then return nil end
    local reg = self.byEncounter[encounterID]
    if reg and reg.complete then return reg end
    reg = reg or { bySpell = {}, bySection = {}, adhoc = {}, list = {} }
    self.byEncounter[encounterID] = reg

    local boss = ns.JournalCatalog:Boss(encounterID)
    if not boss then
        -- Catalog not cached yet (e.g. first pull happened in combat); try again next time.
        return reg
    end
    local overrides = ns.Data.TankbusterOverrides[encounterID] or {}
    local owners = ns.Data.OwnerUnits[encounterID] or {}
    for _, a in ipairs(boss.abilities) do
        if not reg.bySpell[a.spellID] then
            local m = {
                id = encounterID .. ":" .. a.spellID, encounterID = encounterID,
                journalSpellID = a.spellID, sectionID = a.sectionID, title = a.title, icon = a.icon,
                tags = Tags(a.tags, overrides[a.spellID]), ownerUnit = owners[a.spellID],
            }
            reg.bySpell[a.spellID] = m
            reg.bySection[a.sectionID] = m
            reg.list[#reg.list + 1] = m
        end
    end
    reg.complete = true
    return reg
end

function Registry:ForEncounter(encounterID)
    local reg = self:LoadEncounter(encounterID)
    return reg and reg.list or {}
end

function Registry:ByJournalSpell(encounterID, spellID)
    local reg = self:LoadEncounter(encounterID)
    return reg and reg.bySpell[spellID]
end

-- -> InternalMechanic (never nil when a key or text is given).
function Registry:Resolve(source, key, encounterID, text)
    if key == nil and text == nil then return nil end
    local reg = encounterID and self:LoadEncounter(encounterID)
    if reg then
        local map = ns.Data.BossModIDMap[encounterID]
        local mapped = map and map[source] and map[source][key]
        if mapped and reg.bySpell[mapped] then return reg.bySpell[mapped] end
        if type(key) == "number" then
            if key < 0 and reg.bySection[-key] then return reg.bySection[-key] end
            if reg.bySpell[key] then return reg.bySpell[key] end
        end
    end
    -- Ad-hoc: stable per encounter + source + key so bindings can still target it.
    local adhocKey = source .. ":" .. tostring(key or text)
    local store = reg and reg.adhoc or self.looseAdhoc -- outside encounters (trash, tests)
    if not store[adhocKey] then
        store[adhocKey] = {
            id = tostring(encounterID or 0) .. ":" .. adhocKey, encounterID = encounterID,
            title = text, tags = {}, adhoc = true,
            journalSpellID = type(key) == "number" and key > 0 and key or nil,
        }
    end
    return store[adhocKey]
end

-- Forget built encounters (e.g. after the catalog cache was rebuilt).
function Registry:Reset()
    self.byEncounter = {}
    self.looseAdhoc = {}
end
