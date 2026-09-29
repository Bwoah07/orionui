-- Core framework tests: Util, Schema, DB/Profiles, Modules lifecycle, Events, Combat
-- queue, Serialize and ProfileIO round trips. Runs outside the game with busted.
local mock = WowMock

-- Libraries come from tools/fetch-libs.sh (Libs/ is gitignored).
local LIBS = {
    "OrionUI/Libs/LibStub/LibStub.lua",
    "OrionUI/Libs/LibSerialize/LibSerialize.lua",
    "OrionUI/Libs/LibDeflate/LibDeflate.lua",
}
local CORE = {
    "OrionUI/Core/Init.lua", "OrionUI/Locales/enUS.lua", "OrionUI/Core/Util.lua",
    "OrionUI/Core/Log.lua", "OrionUI/Core/SafeCall.lua", "OrionUI/Core/Secret.lua",
    "OrionUI/Core/Events.lua", "OrionUI/Core/Combat.lua", "OrionUI/Core/Schema.lua",
    "OrionUI/Core/DB.lua", "OrionUI/Core/Profiles.lua", "OrionUI/Core/Modules.lua",
    "OrionUI/Core/Serialize.lua", "OrionUI/Core/ProfileIO.lua",
}

local function Fresh()
    mock.frames, mock.timers, mock.inCombat = {}, {}, false
    for _, f in ipairs(LIBS) do dofile(f) end
    local ns = mock.LoadCore(CORE)
    ns.IS_DEV = false
    ns.Player = { class = "DEATHKNIGHT", specID = 250, role = "TANK" }
    ns.DB:Initialize({}, {}, "Tester-Realm")
    ns.Combat:OnInitialize()
    return ns
end

describe("Util", function()
    local ns = Fresh()
    it("fills nested defaults without overwriting", function()
        local t = { a = false, nested = { x = 5 } }
        ns.Util.FillDefaults(t, { a = true, b = 2, nested = { x = 1, y = 2 } })
        assert.are.equal(false, t.a)
        assert.are.equal(2, t.b)
        assert.are.equal(5, t.nested.x)
        assert.are.equal(2, t.nested.y)
    end)
    it("reads and writes dotted paths", function()
        local t = {}
        ns.Util.SetPath(t, "a.b.c", 3)
        assert.are.equal(3, ns.Util.GetPath(t, "a.b.c"))
        assert.is_nil(ns.Util.GetPath(t, "a.x.c"))
    end)
end)

describe("Schema", function()
    local ns = Fresh()
    local S = ns.Schema
    local node = S.Table{ fields = {
        on = S.Bool{ default = true },
        n = S.Number{ default = 5, min = 0, max = 10 },
        mode = S.Enum{ default = "BAR", values = { "BAR", "ICON" } },
        color = S.Color{ default = { 1, 0, 0, 1 } },
        list = S.List{ of = S.Number{ default = 0 }, max = 2 },
        sub = S.Table{ fields = { x = S.Number{ default = 1 } } },
    } }

    it("builds defaults", function()
        local d = S.Default(node)
        assert.are.equal(true, d.on)
        assert.are.equal("BAR", d.mode)
        assert.are.equal(1, d.sub.x)
    end)

    it("repairs bad values, clamps, caps and drops unknown keys", function()
        local report = S.NewReport()
        local out = S.Validate(node, {
            on = "yes", n = 99, mode = "NOPE", color = { 2, 0, 0 },
            list = { 1, 2, 3 }, sub = { x = 4, junk = 1 }, obsolete = true,
        }, "m", report)
        assert.are.equal(true, out.on)
        assert.are.equal(10, out.n)
        assert.are.equal("BAR", out.mode)
        assert.are.same({ 1, 0, 0, 1 }, out.color)
        assert.are.equal(2, #out.list)
        assert.are.equal(4, out.sub.x)
        assert.is_nil(out.obsolete)
        assert.is_nil(out.sub.junk)
        assert.are.equal(2, #report.dropped)
        assert.truthy(#report.fixed >= 4)
    end)
end)

describe("Profiles and modules", function()
    local ns, M, enabled, disabled
    before_each(function()
        ns = Fresh()
        enabled, disabled = 0, 0
        M = ns.Modules:New("Test", {
            profileKey = "layout",
            schema = ns.Schema.Table{ fields = { size = ns.Schema.Number{ default = 3 } } },
            schemaVersion = 2,
            migrations = { [2] = function(db) db.size = (db.oldSize or db.size or 3) * 2 db.oldSize = nil end },
        })
        function M:OnEnable() enabled = enabled + 1 end
        function M:OnDisable() disabled = disabled + 1 end
        ns.Modules:InitializeAll()
    end)

    it("binds defaults and enables", function()
        assert.are.equal(3, M.db.size)
        assert.are.equal(true, M.enabled)
        assert.are.equal(1, enabled)
    end)

    it("disables and cleans up when the setting is turned off", function()
        local hits = 0
        ns.Events:On("OUI_PING", M, function() hits = hits + 1 end)
        M:SetEnabled(false)
        assert.are.equal(false, M.enabled)
        assert.are.equal(1, disabled)
        ns.Events:Fire("OUI_PING")
        assert.are.equal(0, hits) -- subscriptions removed on disable
    end)

    it("honours loadWhen", function()
        local W = ns.Modules:New("Warrior", { loadWhen = { class = "WARRIOR" } })
        ns.Modules:EvaluateAll()
        assert.are.equal(false, W.enabled)
    end)

    it("switches profiles live and keeps them separate", function()
        M.db.size = 7
        assert.is_true(ns.Profiles:New("layout", "Alt"))
        assert.is_true(ns.Profiles:Switch("layout", "Alt"))
        assert.are.equal(3, M.db.size)
        ns.Profiles:Switch("layout", "Default")
        assert.are.equal(7, M.db.size)
    end)

    it("runs migrations on old data", function()
        ns.DB.sv.profiles.layout.Old = { Test = { oldSize = 5 }, __versions = { Test = 1 } }
        ns.Profiles:Switch("layout", "Old")
        assert.are.equal(10, M.db.size)
        assert.is_nil(M.db.oldSize)
    end)

    it("backs up before delete and restores", function()
        ns.Profiles:New("layout", "Gone")
        assert.is_true(ns.Profiles:Delete("layout", "Gone"))
        assert.is_false(ns.Profiles:Exists("layout", "Gone"))
        assert.is_true(ns.DB:RestoreBackup(1))
        assert.is_true(ns.Profiles:Exists("layout", "Gone"))
    end)

    it("refuses to delete Default or the active profile", function()
        assert.is_false((ns.Profiles:Delete("layout", "Default")))
        ns.Profiles:New("layout", "Mine")
        ns.Profiles:Switch("layout", "Mine")
        assert.is_false((ns.Profiles:Delete("layout", "Mine")))
    end)

    it("round-trips export and import with validation", function()
        M.db.size = 9
        local str = assert(ns.ProfileIO:Export("layout"))
        assert.truthy(str:find("^!OUI:L:1!"))
        -- tamper: add an unknown module section
        local ok, clean, report = ns.ProfileIO:Prepare("layout", str)
        assert.is_true(ok)
        assert.are.equal(9, clean.Test.size)
        local done, rep = ns.ProfileIO:Import("layout", str, "Copy", { activate = true })
        assert.is_true(done)
        assert.are.equal("Copy", ns.Profiles:ActiveName("layout"))
        assert.are.equal(9, M.db.size)
        assert.are.equal(0, #rep.fixed)
        assert.truthy(report)
    end)

    it("rejects a reminders string in the layout store and garbage", function()
        assert.is_false((ns.ProfileIO:Prepare("layout", "hello")))
        local rstr = ns.Serialize:Encode("R", { data = {} })
        assert.is_false((ns.ProfileIO:Prepare("layout", rstr)))
    end)

    it("refuses imports in combat", function()
        local str = ns.ProfileIO:Export("layout")
        mock.inCombat = true
        local ok, err = ns.ProfileIO:Import("layout", str, "X")
        assert.is_false(ok)
        assert.are.equal("combat", err)
    end)
end)

describe("Combat queue", function()
    it("defers in combat and collapses repeated keys", function()
        local ns = Fresh()
        local runs = 0
        mock.inCombat = true
        ns.Combat:Defer("k", function() runs = runs + 1 end)
        ns.Combat:Defer("k", function() runs = runs + 10 end)
        assert.are.equal(0, runs)
        mock.inCombat = false
        mock.Fire("PLAYER_REGEN_ENABLED")
        assert.are.equal(10, runs)
    end)
end)

describe("Secret", function()
    it("keeps unknown distinct from false", function()
        local ns = Fresh()
        assert.is_nil(ns.Secret.Bool(mock.SECRET))
        assert.are.equal(false, ns.Secret.Bool(false))
        assert.are.same({ a = 1 }, ns.Secret.Scrub({ a = 1, b = mock.SECRET }))
    end)
end)
