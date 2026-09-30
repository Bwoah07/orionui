-- Defensive reminder engine tests: tank ownership decisions, readiness tri-state,
-- coverage from cooldown transitions, resolver chain and filters, scheduler timing,
-- revisions vs retrigger guard, cancel semantics.
local mock = WowMock

local FILES = {
    "OrionUI/Core/Init.lua", "OrionUI/Locales/enUS.lua", "OrionUI/Core/Util.lua",
    "OrionUI/Core/Log.lua", "OrionUI/Core/SafeCall.lua", "OrionUI/Core/Secret.lua",
    "OrionUI/Core/Events.lua", "OrionUI/Core/Combat.lua", "OrionUI/Core/Schema.lua",
    "OrionUI/Core/DB.lua", "OrionUI/Core/Profiles.lua", "OrionUI/Core/Modules.lua",
    "OrionUI/Data/Encounters.lua",
    "OrionUI/Encounters/EncounterManager.lua", "OrionUI/Encounters/JournalCatalog.lua",
    "OrionUI/Encounters/MechanicRegistry.lua", "OrionUI/Encounters/BossModBridge.lua",
    "OrionUI/Data/Defensives.lua",
    "OrionUI/Reminders/TankOwnership.lua", "OrionUI/Reminders/Readiness.lua",
    "OrionUI/Reminders/Coverage.lua", "OrionUI/Reminders/DefensiveResolver.lua",
    "OrionUI/Reminders/Reminders.lua", "OrionUI/Reminders/Scheduler.lua",
}

local VB, IBF, DRW, AMS = 55233, 48792, 49028, 48707

local function Start(opts)
    opts = opts or {}
    mock.frames, mock.timers, mock.inCombat, mock.now = {}, {}, false, 100
    _G.BigWigsLoader, _G.DBM = nil, nil
    -- cooldown state per spell: { active = bool|SECRET, gcd = bool }
    local cds = {}
    _G.C_Spell = {
        IsSpellPassive = function() return false end,
        GetSpellCooldown = function(id)
            local c = cds[id] or {}
            return { isEnabled = true, isActive = c.active or false, isOnGCD = c.gcd, startTime = mock.SECRET, duration = mock.SECRET }
        end,
        GetSpellName = function(id) return "Spell" .. id end,
        GetSpellTexture = function() return 1 end,
    }
    local known = opts.known or { [VB] = true, [IBF] = true, [DRW] = true, [AMS] = true }
    _G.C_SpellBook = { IsSpellKnown = function(id) return known[id] == true end }
    local threat = opts.threat or {}
    _G.UnitExists = function(u) return threat[u] ~= nil end
    _G.UnitThreatSituation = function(_, u) local t = threat[u] if t == "none" then return nil end return t end
    _G.C_EncounterJournal = { GetInstanceForGameMap = function() return nil end }
    _G.C_ChallengeMode = { IsChallengeModeActive = function() return false end }
    _G.GetInstanceInfo = function() return "World", "none" end
    local ns = mock.LoadCore(FILES)
    ns.IS_DEV = false
    ns.ReminderOutput = { Create = function() end, ApplySettings = function() end }
    ns.Player = { class = "DEATHKNIGHT", specID = 250, role = "TANK" }
    ns.DB:Initialize({}, {}, "Tester-Realm")
    ns.Combat:OnInitialize()
    ns.Modules:InitializeAll()
    local shown, hidden = {}, {}
    local sink = {}
    ns.Events:On("OUI_REMINDER_SHOW", sink, function(_, _, r) shown[#shown + 1] = r end)
    ns.Events:On("OUI_REMINDER_HIDE", sink, function(_, _, r) hidden[#hidden + 1] = r end)
    return ns, cds, shown, hidden, threat
end

-- A tank-tagged mechanic delivered as a boss-mod timer.
local function BusterTimer(ns, id, duration)
    local m = ns.MechanicRegistry:Resolve("Test", id, 4242, "Crushing Blow")
    m.tags = { tank = true }
    m.id = "4242:" .. id
    m.encounterID = 4242
    ns.BossModBridge:Timer({ source = "Test", id = id, key = id, text = "Crushing Blow", duration = duration, encounterID = 4242 })
end

describe("TankOwnership", function()
    it("reacts when tanking, not when another tank has it, and fails open when hidden", function()
        local ns, _, _, _, threat = Start({ threat = { boss1 = 3 } })
        assert.is_true((ns.TankOwnership:ShouldReact(1)))
        threat.boss1 = 0
        mock.now = mock.now + 10 -- past the grace window
        assert.is_false((ns.TankOwnership:ShouldReact(1)))
        threat.boss1 = mock.SECRET
        assert.is_true((ns.TankOwnership:ShouldReact(1)))
    end)
    it("keeps reacting inside the grace window after losing aggro", function()
        local ns, _, _, _, threat = Start({ threat = { boss1 = 3 } })
        ns.TankOwnership:ShouldReact(1)
        threat.boss1 = 0
        mock.now = mock.now + 3
        assert.is_true((ns.TankOwnership:ShouldReact(1)))
    end)
    it("with no owner, reacts if tanking any boss and fails open with no bosses", function()
        local ns, _, _, _, threat = Start({ threat = { boss1 = 0, boss2 = 2 } })
        assert.is_true((ns.TankOwnership:ShouldReact(nil)))
        threat.boss1, threat.boss2 = nil, nil
        assert.is_true((ns.TankOwnership:ShouldReact(nil)))
    end)
end)

describe("Readiness", function()
    it("is ready when not active or only on the GCD, unknown when secret", function()
        local ns, cds = Start()
        assert.is_true(ns.Readiness:IsReady(VB))
        cds[VB] = { active = true }
        assert.is_false(ns.Readiness:IsReady(VB))
        cds[VB] = { active = true, gcd = true }
        assert.is_true(ns.Readiness:IsReady(VB))
        cds[VB] = { active = mock.SECRET }
        assert.is_nil(ns.Readiness:IsReady(VB))
    end)
end)

describe("Resolver", function()
    it("follows the default order and skips spells on cooldown or not known", function()
        local ns, cds = Start({ known = { [IBF] = true, [DRW] = true } })
        local r = ns.DefensiveResolver:Resolve({ tags = {} })
        assert.are.equal("drw", r.pick.key) -- VB not known
        cds[DRW] = { active = true }
        r = ns.DefensiveResolver:Resolve({ tags = {} })
        assert.are.equal("icebound", r.pick.key)
    end)
    it("respects the user's spec order and a per-ability list", function()
        local ns = Start()
        ns.Reminders.db.presets[250] = { "icebound", "vampiric_blood" }
        assert.are.equal("icebound", ns.DefensiveResolver:Resolve({ tags = {} }).pick.key)
        local r = ns.DefensiveResolver:Resolve({ tags = {} }, { defensives = { "ams" } })
        assert.are.equal("ams", r.pick.key)
    end)
    it("filters by curated damage type", function()
        local ns = Start()
        local r = ns.DefensiveResolver:Resolve({ tags = { magicDamage = true } })
        assert.are.equal("vampiric_blood", r.pick.key) -- "all" fits magic
        ns.Reminders.db.presets[250] = { "drw", "ams" }
        r = ns.DefensiveResolver:Resolve({ tags = { magicDamage = true } })
        assert.are.equal("ams", r.pick.key) -- DRW is physical only
    end)
    it("does not suggest a weaker defensive while a stronger one runs (coverage)", function()
        local ns, cds = Start()
        ns.Coverage:Scan()
        cds[IBF] = { active = true } -- Icebound just used
        mock.Fire("SPELL_UPDATE_COOLDOWN")
        assert.is_true(ns.Coverage:IsActive("icebound"))
        local r = ns.DefensiveResolver:Resolve({ tags = {} })
        assert.is_nil(r.pick)
        assert.are.equal("icebound", r.covered.key)
        mock.now = mock.now + 9 -- IBF (8s) over
        r = ns.DefensiveResolver:Resolve({ tags = {} })
        assert.are.equal("vampiric_blood", r.pick.key)
    end)
    it("treats a GCD blip as not a cast", function()
        local ns, cds = Start()
        ns.Coverage:Scan()
        cds[DRW] = { active = true, gcd = true }
        mock.Fire("SPELL_UPDATE_COOLDOWN")
        assert.is_false(ns.Coverage:IsActive("drw"))
    end)
    it("picks a maybe-ready defensive last instead of nothing", function()
        local ns, cds = Start()
        for _, id in ipairs({ VB, IBF, DRW, AMS }) do cds[id] = { active = true } end
        cds[AMS] = { active = mock.SECRET }
        local r = ns.DefensiveResolver:Resolve({ tags = {} })
        assert.are.equal("ams", r.pick.key)
        assert.is_true(r.maybe)
    end)
end)

describe("Scheduler", function()
    it("fires leadTime before the hit, with a defensive, and hides after", function()
        local ns, _, shown, hidden = Start({ threat = { boss1 = 3 } })
        BusterTimer(ns, "cb", 20)
        mock.Advance(14.9)
        assert.are.equal(0, #shown)
        mock.Advance(0.2)
        assert.are.equal(1, #shown)
        assert.are.equal("vampiric_blood", shown[1].defensive.key)
        mock.Advance(6)
        assert.are.equal(1, #hidden)
    end)
    it("reschedules on a revision instead of firing twice", function()
        local ns, _, shown = Start({ threat = { boss1 = 3 } })
        BusterTimer(ns, "cb", 20)
        mock.Advance(5)
        BusterTimer(ns, "cb", 30) -- pushed back
        mock.Advance(12)
        assert.are.equal(0, #shown)
        mock.Advance(14)
        assert.are.equal(1, #shown)
    end)
    it("applies the retrigger guard at fire time", function()
        local ns, _, shown = Start({ threat = { boss1 = 3 } })
        local m = ns.MechanicRegistry:Resolve("BigWigs", 9, 4242, "Slam")
        m.tags, m.id = { tank = true }, "4242:9"
        ns.BossModBridge.db.source = "BigWigs"
        ns.BossModBridge.adapters.BigWigs = { IsLoaded = function() return true end, Register = function() end }
        ns.BossModBridge:Timer({ source = "BigWigs", id = "Slam (1)", key = 9, text = "Slam", duration = 6, encounterID = 4242 })
        mock.Advance(1.1)
        ns.BossModBridge:Timer({ source = "BigWigs", id = "Slam (2)", key = 9, text = "Slam", duration = 6, encounterID = 4242 })
        mock.Advance(1.1)
        assert.are.equal(1, #shown)
    end)
    it("removes pending and visible reminders when the timer is cancelled", function()
        local ns, _, shown, hidden = Start({ threat = { boss1 = 3 } })
        BusterTimer(ns, "a", 20)
        BusterTimer(ns, "b", 4)
        assert.are.equal(1, #shown)
        ns.BossModBridge:Cancel("Test", "b")
        assert.are.equal(1, #hidden)
        ns.BossModBridge:Cancel("Test", "a")
        mock.Advance(30)
        assert.are.equal(1, #shown)
    end)
    it("stays quiet for non-tanks by default and when another tank holds the boss", function()
        local ns, _, shown, _, threat = Start({ threat = { boss1 = 0 } })
        -- Real boss mod source so ownership is checked (tests bypass it).
        ns.BossModBridge.adapters.BigWigs = { IsLoaded = function() return true end, Register = function() end }
        local m = ns.MechanicRegistry:Resolve("BigWigs", 7, 4242, "Smash")
        m.tags, m.id = { tank = true }, "4242:7"
        ns.BossModBridge:Timer({ source = "BigWigs", id = "Smash", key = 7, text = "Smash", duration = 3, encounterID = 4242 })
        assert.are.equal(0, #shown)
        threat.boss1 = 3
        ns.Player.role = "HEALER"
        ns.BossModBridge:Timer({ source = "BigWigs", id = "Smash 2", key = 7, text = "Smash", duration = 3, encounterID = 4242 })
        assert.are.equal(0, #shown)
    end)
    it("honours an explicit per-ability mode", function()
        local ns, _, shown = Start()
        ns.Player.role = "HEALER"
        ns.Reminders:SetMode(4242, "4242:x", "warn")
        local m = ns.MechanicRegistry:Resolve("Test", "x", 4242, "Nova")
        m.id, m.encounterID = "4242:x", 4242
        ns.BossModBridge:Timer({ source = "Test", id = "x", key = "x", text = "Nova", duration = 3, encounterID = 4242 })
        assert.are.equal(1, #shown)
        assert.are.equal("warn", shown[1].mode)
        assert.is_nil(shown[1].defensive)
    end)
    it("reminds every role about Journal 'deadly' abilities unless turned off", function()
        local ns, _, shown = Start()
        ns.Player.role = "HEALER"
        local m = ns.MechanicRegistry:Resolve("Test", "d", 4242, "Doom")
        m.id, m.encounterID, m.tags = "4242:d", 4242, { deadly = true }
        ns.BossModBridge:Timer({ source = "Test", id = "d", key = "d", text = "Doom", duration = 3, encounterID = 4242 })
        assert.are.equal(1, #shown)
        assert.are.equal("defensive", shown[1].mode)
        ns.Reminders.db.deadlyAuto = false
        assert.are.equal("off", (ns.Reminders:AutoMode({ deadly = true })))
    end)
    it("has a catalog and a resolvable default order for every spec", function()
        local ns = Start()
        local all = { 250, 251, 252, 577, 581, 1480, 102, 103, 104, 105, 1467, 1468, 1473, 253, 254, 255,
            62, 63, 64, 268, 269, 270, 65, 66, 70, 256, 257, 258, 259, 260, 261, 262, 263, 264,
            265, 266, 267, 71, 72, 73 }
        for _, specID in ipairs(all) do
            local list = ns.Data.Defensives[specID]
            assert.is_true(list ~= nil and #list > 0, "no catalog for " .. specID)
            local seen = {}
            for _, d in ipairs(list) do
                assert.is_nil(seen[d.key], "duplicate key " .. d.key .. " in " .. specID)
                seen[d.key] = true
                assert.is_true(type(d.spell) == "number" and d.duration >= 0 and d.strength >= 1 and d.strength <= 3)
            end
            for _, key in ipairs(ns.Data.DefensivePresets[specID]) do
                assert.is_true(ns.Data.DefensiveByKey(specID, key) ~= nil, key .. " missing in " .. specID)
            end
        end
    end)
end)
