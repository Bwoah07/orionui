-- Minimal WoW environment for busted (CLAUDE.md §16.1). Enough API surface to load the
-- core files and drive them: frames record their event registrations and scripts so
-- tests can fire events; timers run when the test advances the clock.
local mock = { now = 0, frames = {}, timers = {}, inCombat = false }

-- A sentinel standing in for a 12.x secret value. Any attempt to stringify, concatenate
-- or compare it errors, so tests catch code that would misuse a secret.
local SECRET = setmetatable({}, {
    __tostring = function() error("secret value was stringified", 2) end,
    __concat = function() error("secret value was concatenated", 2) end,
    __eq = function() error("secret value was compared", 2) end,
})
mock.SECRET = SECRET

unpack = unpack or table.unpack
table.maxn = table.maxn or function(t)
    local n = 0
    for k in pairs(t) do if type(k) == "number" and k > n then n = k end end
    return n
end

function _G.issecretvalue(v) return rawequal(v, SECRET) end
function _G.canaccesstable(t) return not rawequal(t, SECRET) end
function _G.GetTime() return mock.now end
function _G.time() return 1700000000 + math.floor(mock.now) end
_G.date = os.date
function _G.wipe(t) for k in pairs(t) do t[k] = nil end return t end
function _G.debugstack() return "" end
function _G.geterrorhandler() return function(e) mock.lastError = e end end
function _G.InCombatLockdown() return mock.inCombat end
function _G.tinsert(t, v) table.insert(t, v) end
_G.strmatch = string.match -- WoW alias; LibStub uses it
_G.print = _G.print
_G.UISpecialFrames = {}
_G.SlashCmdList = {}
_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

_G.C_AddOns = {
    GetAddOnMetadata = function() return "@project-version@" end,
    IsAddOnLoaded = function(name) return mock.loadedAddons and mock.loadedAddons[name] or false end,
}
_G.Enum = {
    AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4, Chat = 5 },
    AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
}
_G.C_RestrictedActions = { GetAddOnRestrictionState = function() return 0 end }
_G.C_SpecializationInfo = {
    GetSpecialization = function() return 1 end,
    GetSpecializationInfo = function() return 250, "Blood", "", 0, "TANK" end,
}
function _G.UnitClass() return "Death Knight", "DEATHKNIGHT", 6 end
function _G.UnitFullName() return "Tester", "Realm" end
function _G.GetNormalizedRealmName() return "Realm" end
function _G.GetInstanceInfo() return "World", "none" end

-- Frames: any unknown method is a no-op returning the frame, so UI code loads.
local function NewFrame()
    local f = { events = {}, scripts = {} }
    f.RegisterEvent = function(self, e) self.events[e] = true end
    f.UnregisterEvent = function(self, e) self.events[e] = nil end
    f.UnregisterAllEvents = function(self) self.events = {} end
    f.RegisterUnitEvent = function(self, e) self.events[e] = true end
    f.SetScript = function(self, k, fn) self.scripts[k] = fn end
    f.GetScript = function(self, k) return self.scripts[k] end
    setmetatable(f, { __index = function() return function(self) return self end end })
    mock.frames[#mock.frames + 1] = f
    return f
end
function _G.CreateFrame() return NewFrame() end

-- Fires a Blizzard event on every frame registered for it.
function mock.Fire(event, ...)
    for _, f in ipairs(mock.frames) do
        if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
    end
end

-- Timers run when the clock is advanced past their due time.
local function AddTimer(delay, fn, iterations)
    local t = { due = mock.now + delay, fn = fn, interval = delay, left = iterations }
    t.Cancel = function(self) self.cancelled = true end
    mock.timers[#mock.timers + 1] = t
    return t
end
_G.C_Timer = {
    After = function(d, fn) AddTimer(d, fn, 1) end,
    NewTimer = function(d, fn) return AddTimer(d, fn, 1) end,
    NewTicker = function(d, fn, n) return AddTimer(d, fn, n or math.huge) end,
}
function mock.Advance(seconds)
    mock.now = mock.now + seconds
    local ran = true
    while ran do
        ran = false
        for _, t in ipairs(mock.timers) do
            if not t.cancelled and t.left > 0 and t.due <= mock.now then
                t.left = t.left - 1
                t.due = t.due + t.interval
                ran = true
                t.fn(t)
            end
        end
    end
end

-- Loads an addon file with the (addonName, ns) varargs WoW passes to every file.
function mock.LoadAddonFile(path, addonName, ns)
    local chunk = assert(loadfile(path))
    chunk(addonName, ns)
    return ns
end

-- Loads the listed OrionUI files (paths relative to the repo root) into a fresh ns.
function mock.LoadCore(files)
    local ns = {}
    for _, f in ipairs(files) do mock.LoadAddonFile(f, "OrionUI", ns) end
    return ns
end

_G.WowMock = mock
return mock
