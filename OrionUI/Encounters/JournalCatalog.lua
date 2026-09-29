-- Encounter Journal catalog (CLAUDE.md §7.3): bosses and abilities of an instance,
-- keyed by dungeonEncounterID (= ENCOUNTER_START's encounterID, verified 2026-09-29).
-- Built lazily out of combat and cached in OrionUIDB.caches.journal, stamped with
-- locale + game build so a patch or language change rebuilds it. Never exported.
--
-- Findings this relies on (docs/verification-log.md):
--  * EJ_GetEncounterInfoByIndex(i, instance) 7th return = dungeonEncounterID.
--  * The Journal has its own difficulty; difficulty-specific sections come back with
--    filteredByDifficulty = true. We set the instance's difficulty while scraping and
--    put the user's Journal difficulty back afterwards.
--  * Icon flags are indexes n whose meaning is the n-th bit of Enum.JournalEncounterIconFlags.
local _, ns = ...

local Catalog = { CACHE_VERSION = 1 }
ns.JournalCatalog = Catalog

local MAX_BOSSES, MAX_SECTIONS = 20, 400
local ABILITY, OVERVIEW = 2, 3 -- Enum.JournalEncounterSecTypes

-- Flag index -> tag name ("tank", "deadly", "magic", ...), derived from the enum so it
-- follows Blizzard if they add flags.
local flagTags
local function FlagTags()
    if flagTags then return flagTags end
    flagTags = {}
    for name, value in pairs(Enum.JournalEncounterIconFlags or {}) do
        local index = math.floor(math.log(value) / math.log(2) + 0.5)
        flagTags[index] = name:lower()
    end
    return flagTags
end

local function Stamp()
    local _, build = GetBuildInfo()
    return GetLocale() .. ":" .. tostring(build) .. ":" .. Catalog.CACHE_VERSION
end

local function Cache()
    local c = ns.DB.sv.caches
    c.journal = c.journal or {}
    if c.journal.stamp ~= Stamp() then
        c.journal = { stamp = Stamp(), instances = {} }
    end
    return c.journal.instances
end

local function Tags(sectionID)
    local flags = C_EncounterJournal.GetSectionIconFlags(sectionID)
    local tags = {}
    for _, index in ipairs(flags or {}) do
        local tag = FlagTags()[index]
        if tag then tags[tag] = true end
    end
    return tags
end

-- Depth-first over the section tree; keeps abilities with a spell, skips passives,
-- difficulty-filtered duplicates and repeats of the same spell.
local function ReadAbilities(rootSectionID)
    local abilities, seen, stack, visited = {}, {}, { rootSectionID }, 0
    while #stack > 0 and visited < MAX_SECTIONS do
        local id = table.remove(stack)
        local info = C_EncounterJournal.GetSectionInfo(id)
        visited = visited + 1
        if info then
            if info.siblingSectionID then stack[#stack + 1] = info.siblingSectionID end
            if info.firstChildSectionID then stack[#stack + 1] = info.firstChildSectionID end
            local spellID = info.spellID
            if not info.filteredByDifficulty and info.headerType == ABILITY and spellID and spellID > 0
                and not seen[spellID] and not C_Spell.IsSpellPassive(spellID) then
                seen[spellID] = true
                abilities[#abilities + 1] = {
                    spellID = spellID, sectionID = id, title = info.title,
                    icon = info.abilityIcon, description = info.description, tags = Tags(id),
                }
            end
        end
    end
    return abilities
end

local function Scrape(journalInstanceID, difficultyID)
    local oldDifficulty = EJ_GetDifficulty()
    EJ_SelectInstance(journalInstanceID)
    if difficultyID and EJ_IsValidInstanceDifficulty(difficultyID) then EJ_SetDifficulty(difficultyID) end
    local name = EJ_GetInstanceInfo(journalInstanceID)
    local entry = { name = name, journalInstanceID = journalInstanceID, difficultyID = difficultyID, bosses = {} }
    for i = 1, MAX_BOSSES do
        local bossName, _, journalEncounterID, rootSectionID, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(i, journalInstanceID)
        if not bossName then break end
        EJ_SelectEncounter(journalEncounterID)
        entry.bosses[#entry.bosses + 1] = {
            name = bossName, index = i, journalEncounterID = journalEncounterID,
            encounterID = dungeonEncounterID, abilities = rootSectionID and ReadAbilities(rootSectionID) or {},
        }
    end
    if oldDifficulty and EJ_GetDifficulty() ~= oldDifficulty then EJ_SetDifficulty(oldDifficulty) end
    return entry
end

-- -> catalog entry, or nil + reason. Only scrapes out of combat and while the Adventure
-- Guide is closed (selecting an instance would change what it shows).
function Catalog:Get(journalInstanceID, difficultyID)
    if not journalInstanceID then return nil, "no journal instance" end
    local key = journalInstanceID .. ":" .. tostring(difficultyID or 0)
    local cache = Cache()
    if cache[key] then return cache[key] end
    if InCombatLockdown() then return nil, "combat" end
    if EncounterJournal and EncounterJournal:IsShown() then return nil, "journal open" end
    local ok, entry = ns.SafeCall("JournalCatalog", Scrape, journalInstanceID, difficultyID)
    if not ok then return nil, "scrape failed" end
    cache[key] = entry
    ns.Log:Info("JournalCatalog", "cached %s (%d bosses)", tostring(entry.name), #entry.bosses)
    return entry
end

-- Boss entry by ENCOUNTER_START encounterID, searching cached instances.
function Catalog:Boss(encounterID)
    for _, entry in pairs(Cache()) do
        for _, boss in ipairs(entry.bosses) do
            if boss.encounterID == encounterID then return boss, entry end
        end
    end
end

-- Catalog for where the player is now (warm the cache on zone-in).
function Catalog:Current()
    local inst = ns.EncounterManager.instance
    return self:Get(inst.journalInstanceID, inst.difficultyID)
end

-- Warm the cache when entering an instance, out of combat.
ns.Events:On("OUI_INSTANCE_CHANGED", Catalog, function(_, _, inst)
    if inst.journalInstanceID then
        ns.Combat:Defer("journal-catalog", function() Catalog:Current() end)
    end
end)
Catalog.name = "JournalCatalog"
