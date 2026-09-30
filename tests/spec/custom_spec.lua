-- Custom reminders: timer/message/pull triggers, key vs text matching, role filter,
-- cancel semantics and single-reminder export/import.
local mock = WowMock

local FILES = {
    "OrionUI/Libs/LibStub/LibStub.lua", "OrionUI/Libs/LibSerialize/LibSerialize.lua", "OrionUI/Libs/LibDeflate/LibDeflate.lua",
    "OrionUI/Core/Init.lua", "OrionUI/Locales/enUS.lua", "OrionUI/Core/Util.lua",
    "OrionUI/Core/Log.lua", "OrionUI/Core/SafeCall.lua", "OrionUI/Core/Secret.lua",
    "OrionUI/Core/Events.lua", "OrionUI/Core/Combat.lua", "OrionUI/Core/Schema.lua",
    "OrionUI/Core/DB.lua", "OrionUI/Core/Profiles.lua", "OrionUI/Core/Modules.lua",
    "OrionUI/Core/Serialize.lua",
    "OrionUI/Data/Encounters.lua",
    "OrionUI/Encounters/EncounterManager.lua", "OrionUI/Encounters/JournalCatalog.lua",
    "OrionUI/Encounters/MechanicRegistry.lua", "OrionUI/Encounters/BossModBridge.lua",
    "OrionUI/Data/Defensives.lua",
    "OrionUI/Reminders/TankOwnership.lua", "OrionUI/Reminders/Readiness.lua",
    "OrionUI/Reminders/Coverage.lua", "OrionUI/Reminders/DefensiveResolver.lua",
    "OrionUI/Reminders/Reminders.lua", "OrionUI/Reminders/Scheduler.lua",
    "OrionUI/Reminders/CustomReminders.lua",
}

local function Start()
    mock.frames, mock.timers, mock.inCombat, mock.now = {}, {}, false, 100
    _G.BigWigsLoader, _G.DBM = nil, nil
    _G.C_Spell = { IsSpellPassive = function() return false end, GetSpellCooldown = function() return { isActive = false, isEnabled = true } end }
    _G.C_SpellBook = { IsSpellKnown = function() return true end }
    _G.UnitExists = function() return false end
    _G.C_EncounterJournal = { GetInstanceForGameMap = function() return nil end }
    _G.C_ChallengeMode = { IsChallengeModeActive = function() return false end }
    for _, f in ipairs({ FILES[1], FILES[2], FILES[3] }) do dofile(f) end
    local list = {}
    for i = 4, #FILES do list[#list + 1] = FILES[i] end
    local ns = mock.LoadCore(list)
    ns.IS_DEV = false
    ns.ReminderOutput = { Create = function() end, ApplySettings = function() end }
    ns.Player = { class = "DEATHKNIGHT", specID = 250, role = "TANK" }
    ns.DB:Initialize({}, {}, "Tester-Realm")
    ns.Combat:OnInitialize()
    ns.Modules:InitializeAll()
    local shown = {}
    ns.Events:On("OUI_REMINDER_SHOW", {}, function(_, _, r) if r.mode == "custom" then shown[#shown + 1] = r end end)
    return ns, shown
end

local function Timer(ns, id, key, text, duration)
    ns.BossModBridge:Timer({ source = "Test", id = id, key = key, text = text, duration = duration, encounterID = 4242 })
end

describe("Custom reminders", function()
    it("fires `offset` seconds before a matching timer, by key", function()
        local ns, shown = Start()
        local r = ns.CustomReminders:New(4242)
        r.match, r.offset, r.text = "474496", 3, "Face away"
        Timer(ns, "t1", 474496, "Tank Knockback", 10)
        mock.Advance(6.9)
        assert.are.equal(0, #shown)
        mock.Advance(0.2)
        assert.are.equal(1, #shown)
        assert.are.equal("Face away", shown[1].text)
    end)

    it("matches bar text case-insensitively and applies 'any boss' reminders", function()
        local ns, shown = Start()
        local r = ns.CustomReminders:New(0)
        r.match, r.offset = "knockback", 2
        Timer(ns, "t1", 1, "Tank Knockback (2)", 5)
        mock.Advance(3.1)
        assert.are.equal(1, #shown)
    end)

    it("respects the role filter and the enabled switch", function()
        local ns, shown = Start()
        local a = ns.CustomReminders:New(4242)
        a.match, a.offset, a.role = "1", 1, "HEALER"
        local b = ns.CustomReminders:New(4242)
        b.match, b.offset, b.enabled = "1", 1, false
        Timer(ns, "t1", 1, "x", 3)
        mock.Advance(3)
        assert.are.equal(0, #shown)
    end)

    it("drops a pending reminder when its timer is cancelled", function()
        local ns, shown = Start()
        local r = ns.CustomReminders:New(4242)
        r.match, r.offset = "9", 2
        Timer(ns, "t9", 9, "x", 10)
        ns.BossModBridge:Cancel("Test", "t9")
        mock.Advance(10)
        assert.are.equal(0, #shown)
    end)

    it("fires on announcements and after the pull", function()
        local ns, shown = Start()
        local m = ns.CustomReminders:New(4242)
        m.trigger, m.match = "message", "Dispels"
        local p = ns.CustomReminders:New(4242)
        p.trigger, p.offset, p.text = "pull", 5, "Lust soon"
        mock.Fire("ENCOUNTER_START", 4242, "Boss", 8, 5)
        ns.BossModBridge:Message({ source = "Test", key = 1214032, text = "Dispels (1)", encounterID = 4242 })
        assert.are.equal(1, #shown)
        assert.is_true(shown[1].noTime)
        mock.Advance(5.1)
        assert.are.equal(2, #shown)
        assert.are.equal("Lust soon", shown[2].text)
    end)

    it("exports and imports a single reminder, validating it", function()
        local ns = Start()
        local r = ns.CustomReminders:New(4242)
        r.name, r.match, r.offset = "Knockback", "474496", 4
        local str = assert(ns.CustomReminders:Export(r))
        assert.truthy(str:find("^!OUI:C:1!"))
        local ok, copy = ns.CustomReminders:Import(str, 0)
        assert.is_true(ok)
        assert.are.equal("Knockback", copy.name)
        assert.are.equal(4, copy.offset)
        assert.is_false((ns.CustomReminders:Import("junk", 0)))
    end)
end)
