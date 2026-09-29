-- Encounter pipeline tests: Journal catalog scrape, mechanic resolution, BigWigs and DBM
-- adapters through the bridge (dedupe, cancel by text, pause/resume, end-of-fight).
local mock = WowMock

local FILES = {
    "OrionUI/Libs/LibStub/LibStub.lua",
    "OrionUI/Core/Init.lua", "OrionUI/Locales/enUS.lua", "OrionUI/Core/Util.lua",
    "OrionUI/Core/Log.lua", "OrionUI/Core/SafeCall.lua", "OrionUI/Core/Secret.lua",
    "OrionUI/Core/Events.lua", "OrionUI/Core/Combat.lua", "OrionUI/Core/Schema.lua",
    "OrionUI/Core/DB.lua", "OrionUI/Core/Profiles.lua", "OrionUI/Core/Modules.lua",
    "OrionUI/Data/Encounters.lua",
    "OrionUI/Encounters/EncounterManager.lua", "OrionUI/Encounters/JournalCatalog.lua",
    "OrionUI/Encounters/MechanicRegistry.lua", "OrionUI/Encounters/BossModBridge.lua",
    "OrionUI/Integrations/BigWigs.lua", "OrionUI/Integrations/DBM.lua",
}

-- A tiny Encounter Journal: one instance, one boss, three abilities (one filtered).
local function MockJournal()
    _G.Enum.JournalEncounterIconFlags = { Tank = 1, Dps = 2, Healer = 4, Heroic = 8, Deadly = 16, Important = 32 }
    local sections = {
        [100] = { title = "Overview", spellID = 0, headerType = 3, firstChildSectionID = 101 },
        [101] = { title = "Crushing Blow", spellID = 5001, headerType = 2, siblingSectionID = 102 },
        [102] = { title = "Crushing Blow", spellID = 5001, headerType = 2, siblingSectionID = 103, filteredByDifficulty = true },
        [103] = { title = "Fire Nova", spellID = 5002, headerType = 2 },
    }
    _G.C_EncounterJournal = {
        GetInstanceForGameMap = function() return 900 end,
        GetSectionInfo = function(id) return sections[id] end,
        GetSectionIconFlags = function(id) if id == 101 then return { 0, 4 } end end,
    }
    local difficulty = 1
    _G.EJ_GetDifficulty = function() return difficulty end
    _G.EJ_SetDifficulty = function(d) difficulty = d end
    _G.EJ_IsValidInstanceDifficulty = function() return true end
    _G.EJ_SelectInstance = function() end
    _G.EJ_SelectEncounter = function() end
    _G.EJ_GetInstanceInfo = function() return "Test Keep" end
    _G.EJ_GetEncounterInfoByIndex = function(i)
        if i == 1 then return "Big Boss", "", 77, 100, "", 900, 4242, 1 end
    end
    _G.C_Spell = { IsSpellPassive = function() return false end }
    _G.C_ChallengeMode = { IsChallengeModeActive = function() return false end }
    _G.GetBuildInfo = function() return "12.1.0", "69933" end
    _G.GetLocale = function() return "enUS" end
    _G.GetInstanceInfo = function() return "Test Keep", "party", 8, "", 5, 0, false, 2000 end
    return function() return difficulty end
end

-- BigWigs stand-in: RegisterMessage stores callbacks; Send dispatches like BigWigs does.
local function MockBigWigs()
    local cbs = {}
    _G.BigWigsLoader = { RegisterMessage = function(_, msg, fn) cbs[msg] = fn end }
    return function(msg, ...) if cbs[msg] then cbs[msg](msg, ...) end end
end

local function MockDBM()
    local cbs = {}
    _G.DBM = { RegisterCallback = function(_, event, fn) cbs[event] = fn end }
    return function(event, ...) if cbs[event] then cbs[event](event, ...) end end
end

local function Start()
    mock.frames, mock.timers, mock.inCombat, mock.now = {}, {}, false, 100
    local ejDifficulty = MockJournal()
    local bw, dbm = MockBigWigs(), MockDBM()
    local ns = mock.LoadCore(FILES)
    ns.IS_DEV = false
    ns.Player = { class = "DEATHKNIGHT", specID = 250, role = "TANK" }
    ns.DB:Initialize({}, {}, "Tester-Realm")
    ns.Combat:OnInitialize()
    ns.Modules:InitializeAll()
    local seen = { timer = {}, cancel = {}, message = {} }
    local sink = {}
    ns.Events:On("OUI_MECHANIC_TIMER", sink, function(_, _, e) table.insert(seen.timer, e) end)
    ns.Events:On("OUI_MECHANIC_CANCEL", sink, function(_, _, e) table.insert(seen.cancel, e or "all") end)
    ns.Events:On("OUI_MECHANIC_MESSAGE", sink, function(_, _, e) table.insert(seen.message, e) end)
    return ns, bw, dbm, seen, ejDifficulty
end

local BOSS = { engageId = 4242, moduleName = "Big Boss" }

describe("Journal catalog", function()
    it("scrapes abilities with tags, skips filtered duplicates and restores the Journal difficulty", function()
        local ns, _, _, _, ejDifficulty = Start()
        local entry = assert(ns.JournalCatalog:Get(900, 8))
        assert.are.equal(1, #entry.bosses)
        local boss = entry.bosses[1]
        assert.are.equal(4242, boss.encounterID)
        assert.are.equal(2, #boss.abilities)
        assert.is_true(boss.abilities[1].tags.tank)
        assert.is_true(boss.abilities[1].tags.deadly)
        assert.are.equal(1, ejDifficulty())
    end)
end)

describe("Bridge with BigWigs", function()
    local ns, bw, seen
    before_each(function()
        ns, bw, _, seen = Start()
        ns.JournalCatalog:Get(900, 8)
        mock.Fire("ENCOUNTER_START", 4242, "Big Boss", 8, 5)
    end)

    it("resolves the key to the Journal mechanic and dedupes StartBar + Timer", function()
        bw("BigWigs_StartBar", BOSS, 5001, "Crushing Blow (1)", 20, 123, true, nil, nil, 3)
        bw("BigWigs_Timer", BOSS, 5001, 20, nil, "Crushing Blow (1)", 1, 123, true, true)
        assert.are.equal(1, #seen.timer)
        local e = seen.timer[1]
        assert.are.equal("4242:5001", e.mechanic.id)
        assert.is_true(e.mechanic.tags.tank)
        assert.are.equal(120, e.expiresAt)
    end)

    it("treats a changed time as a revision, not a duplicate", function()
        bw("BigWigs_StartBar", BOSS, 5001, "Crushing Blow (1)", 20, 123)
        mock.now = 105
        bw("BigWigs_StartBar", BOSS, 5001, "Crushing Blow (1)", 10, 123)
        assert.are.equal(2, #seen.timer)
        assert.is_true(seen.timer[2].revised)
        assert.are.equal(115, seen.timer[2].expiresAt)
    end)

    it("cancels by bar text", function()
        bw("BigWigs_StartBar", BOSS, 5002, "Fire Nova", 15, 1)
        bw("BigWigs_StopBar", BOSS, "Fire Nova")
        assert.are.equal(1, #seen.cancel)
        assert.are.equal(0, #ns.BossModBridge:Active())
    end)

    it("pauses and resumes with the remaining time", function()
        bw("BigWigs_StartBar", BOSS, 5002, "Fire Nova", 15, 1)
        mock.now = 105
        bw("BigWigs_PauseBar", BOSS, "Fire Nova")
        mock.now = 130
        bw("BigWigs_ResumeBar", BOSS, "Fire Nova")
        local last = seen.timer[#seen.timer]
        assert.are.equal(140, last.expiresAt)
    end)

    it("ignores plugins and trash modules", function()
        bw("BigWigs_Message", { moduleName = "Victory" }, nil, "Boss defeated", "green")
        bw("BigWigs_StartBar", { moduleName = "Trash" }, 1, "Trash thing", 10, 1)
        assert.are.equal(0, #seen.message)
        assert.are.equal(0, #seen.timer)
    end)

    it("drops secret values instead of passing them on", function()
        bw("BigWigs_StartBar", BOSS, mock.SECRET, mock.SECRET, 10, 1)
        assert.are.equal(0, #seen.timer)
        bw("BigWigs_StartBar", BOSS, mock.SECRET, "Unknown bar", 10, 1)
        assert.are.equal(1, #seen.timer)
        assert.is_nil(seen.timer[1].key)
        assert.is_true(seen.timer[1].mechanic.adhoc)
    end)

    it("clears everything on ENCOUNTER_END", function()
        bw("BigWigs_StartBar", BOSS, 5002, "Fire Nova", 15, 1)
        mock.Fire("ENCOUNTER_END", 4242, "Big Boss", 8, 5, 0)
        assert.are.equal(0, #ns.BossModBridge:Active())
        assert.truthy(#seen.cancel >= 1)
    end)

    it("prefers BigWigs when both boss mods are loaded", function()
        assert.are.equal("BigWigs", ns.BossModBridge:ActiveSource())
    end)
end)

describe("Bridge with DBM only", function()
    it("follows DBM timers, updates and stops, and skips utility timers", function()
        local ns, _, dbm, seen = Start()
        _G.BigWigsLoader = nil
        ns.JournalCatalog:Get(900, 8)
        mock.Fire("ENCOUNTER_START", 4242, "Big Boss", 8, 5)
        assert.are.equal("DBM", ns.BossModBridge:ActiveSource())
        ns.BossModBridge:RegisterAll()
        dbm("DBM_TimerBegin", "Timer5002", "Fire Nova", 15, 1, "cd", 5002, 0, "BigBossMod")
        dbm("DBM_TimerBegin", "DBMPizzaTimer", "Pizza", 60, 1, "pizzatimer", nil, 0, nil)
        assert.are.equal(1, #seen.timer)
        assert.are.equal("4242:5002", seen.timer[1].mechanic.id)
        mock.now = 110
        dbm("DBM_TimerUpdate", "Timer5002", 10, 30)
        assert.are.equal(130, seen.timer[#seen.timer].expiresAt)
        dbm("DBM_TimerStop", "Timer5002")
        assert.are.equal(0, #ns.BossModBridge:Active())
    end)
end)
