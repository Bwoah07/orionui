-- /ouidev ej [journalInstanceID | mplus]
-- Dumps what the Encounter Journal gives us for a dungeon/raid: bosses with their
-- journal and dungeon encounter IDs, and the full ability section tree with spellIDs
-- and role/mechanic icon flags. Verifies the JournalCatalog plan (CLAUDE.md §7.3).
--
-- EJ_* globals are not in the generated API docs; their return order is taken from
-- Blizzard_EncounterJournal (Mainline) usage in wow-ui-source 12.1.0. The 7th return of
-- EJ_GetEncounterInfoByIndex (dungeonEncounterID) is NOT confirmed by that source: this
-- probe is how we confirm it (it should match ENCOUNTER_START's encounterID).
local _, ns = ...

local Report = ns.Report
local Describe, Try = ns.Describe, ns.Try

local MAX_BOSSES, MAX_SECTIONS = 20, 250

-- Icon flags are indexes into ENCOUNTER_JOURNAL_SECTION_FLAG<n> global strings,
-- exactly how the Journal UI labels them.
local function FlagNames(sectionID)
    local ok, flags = Try(C_EncounterJournal.GetSectionIconFlags, sectionID)
    if not ok then return "ERR" end
    if not flags or #flags == 0 then return "" end
    local names = {}
    for _, f in ipairs(flags) do
        names[#names + 1] = _G["ENCOUNTER_JOURNAL_SECTION_FLAG" .. f] or ("flag" .. f)
    end
    return " [" .. table.concat(names, ",") .. "]"
end

-- Depth-first walk via firstChildSectionID / siblingSectionID.
local function WalkSections(rootID)
    local stack, count = { { id = rootID, depth = 0 } }, 0
    while #stack > 0 and count < MAX_SECTIONS do
        local node = table.remove(stack)
        local ok, info = Try(C_EncounterJournal.GetSectionInfo, node.id)
        if ok and info then
            count = count + 1
            Report:Line("%s- %s spell=%s type=%s filtered=%s%s", string.rep("  ", node.depth + 1),
                Describe(info.title), Describe(info.spellID), Describe(info.headerType),
                Describe(info.filteredByDifficulty), FlagNames(node.id))
            -- Push sibling first so the child is processed next (pre-order).
            if info.siblingSectionID then table.insert(stack, { id = info.siblingSectionID, depth = node.depth }) end
            if info.firstChildSectionID then table.insert(stack, { id = info.firstChildSectionID, depth = node.depth + 1 }) end
        elseif not ok then
            Report:Line("   ERR section %s: %s", tostring(node.id), tostring(info))
        end
    end
    if count >= MAX_SECTIONS then Report:Line("   (stopped at %d sections)", MAX_SECTIONS) end
end

local function DumpInstance(journalInstanceID)
    EJ_SelectInstance(journalInstanceID)
    local instName = EJ_GetInstanceInfo(journalInstanceID)
    Report:Line("instance %s journalInstanceID=%d EJ difficulty=%s", Describe(instName), journalInstanceID, Describe(EJ_GetDifficulty()))
    for i = 1, MAX_BOSSES do
        local name, _, journalEncounterID, rootSectionID, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(i, journalInstanceID)
        if not name then break end
        Report:Line("BOSS %d %s journalEncounterID=%s dungeonEncounterID=%s rootSection=%s",
            i, Describe(name), Describe(journalEncounterID), Describe(dungeonEncounterID), Describe(rootSectionID))
        EJ_SelectEncounter(journalEncounterID) -- the Journal UI selects before reading sections
        if rootSectionID then WalkSections(rootSectionID) end
    end
end

local function DumpMythicPlusMaps()
    local ok, maps = Try(C_ChallengeMode.GetMapTable)
    if not ok or not maps then Report:Line("GetMapTable failed: %s", tostring(maps)) return end
    for _, cmID in ipairs(maps) do
        local name, _, _, _, _, mapID = C_ChallengeMode.GetMapUIInfo(cmID)
        local okJ, jid = Try(C_EncounterJournal.GetInstanceForGameMap, mapID)
        Report:Line("M+ challengeMapID=%d %s instanceMapID=%s -> journalInstanceID=%s",
            cmID, Describe(name), Describe(mapID), okJ and Describe(jid) or "ERR")
    end
    Report:Line("Dump one: /ouidev ej <journalInstanceID>")
end

function ns.ProbeJournal(args)
    if InCombatLockdown() then
        ns.Chat("ej: run this out of combat")
        return
    end
    -- Selecting an instance changes what an open Journal window shows; don't fight the user.
    if EncounterJournal and EncounterJournal:IsShown() then
        ns.Chat("ej: close the Adventure Guide first")
        return
    end
    Report:Begin("JOURNAL")
    if args[1] == "mplus" then
        DumpMythicPlusMaps()
    else
        local jid = tonumber(args[1])
        if not jid then
            local instanceMapID = select(8, GetInstanceInfo())
            local ok, found = Try(C_EncounterJournal.GetInstanceForGameMap, instanceMapID)
            Report:Line("current instanceMapID=%s GetInstanceForGameMap -> %s", Describe(instanceMapID), ok and Describe(found) or "ERR")
            if ok and type(found) == "number" and not ns.IsSecret(found) then jid = found end
        end
        if jid then
            DumpInstance(jid)
        else
            Report:Line("not in a journal instance. Use /ouidev ej <journalInstanceID> or /ouidev ej mplus")
        end
    end
    return Report:End(args.show ~= false)
end
