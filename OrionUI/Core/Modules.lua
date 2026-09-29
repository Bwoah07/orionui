-- Module registry and lifecycle (CLAUDE.md §6.2). Adding a feature = one file + one TOC
-- line: the registry binds its settings, builds its options page, and enables or
-- disables it from its `enabled` setting and `loadWhen` conditions.
--
--   local M = ns.Modules:New("BloodDK", {
--       category = "tank", label = "Blood Death Knight",
--       profileKey = "layout",                 -- "layout" | "reminders" | nil (no settings)
--       loadWhen = { class = "DEATHKNIGHT", specID = 250 },
--       schema = ns.Schema.Table{ fields = { ... } },  -- or plain `defaults = {}`
--       schemaVersion = 1, migrations = { [2] = function(db) return db end },
--       requires = { "EncounterManager" },
--   })
local _, ns = ...

local Modules = { list = {}, byName = {}, initialized = false }
ns.Modules = Modules

local Proto = {}
Proto.__index = Proto

function Proto:OnInitialize() end
function Proto:OnEnable() end
function Proto:OnDisable() end
function Proto:OnProfileChanged() self:Refresh() end
function Proto:Refresh() end

function Proto:IsEnabled() return self.enabled == true end

function Proto:SetEnabled(on)
    if self.db then self.db.enabled = on and true or false end
    Modules:EvaluateAll()
end

-- Timers owned by the module; all cancelled automatically when it is disabled.
function Proto:After(delay, fn)
    local t
    t = C_Timer.NewTimer(delay, function()
        self._timers[t] = nil
        ns.SafeCall(self.name, fn, self)
    end)
    self._timers[t] = true
    return t
end

function Proto:NewTicker(interval, fn, iterations)
    local t = C_Timer.NewTicker(interval, function() ns.SafeCall(self.name, fn, self) end, iterations)
    self._timers[t] = true -- a finished ticker stays listed until disable; Cancel() on it is harmless
    return t
end

function Proto:Debug(fmt, ...) ns.Log:Debug(self.name, fmt, ...) end
function Proto:Info(fmt, ...) ns.Log:Info(self.name, fmt, ...) end
function Proto:Warn(fmt, ...) ns.Log:Warn(self.name, fmt, ...) end
function Proto:Error(fmt, ...) ns.Log:Error(self.name, fmt, ...) end

-- Resets this module's settings in the active profile (backed up first).
function Proto:ResetSettings()
    if not self.profileKey then return end
    ns.DB:Backup(self.profileKey, "before resetting " .. self.label)
    ns.Profiles:Active(self.profileKey)[self.name] = nil
    Modules:Bind(self)
    ns.SafeCall(self.name, self.OnProfileChanged, self)
    Modules:EvaluateAll()
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------

local VALID_STORE = { layout = true, reminders = true }

function Modules:New(name, spec)
    assert(type(name) == "string" and not self.byName[name], "module name missing or taken: " .. tostring(name))
    spec = spec or {}
    assert(spec.profileKey == nil or VALID_STORE[spec.profileKey], name .. ": profileKey must be layout or reminders")

    local M = setmetatable({
        name = name,
        label = spec.label or name,
        category = spec.category or "general",
        order = spec.order or 100,
        profileKey = spec.profileKey,
        loadWhen = spec.loadWhen,
        requires = spec.requires or {},
        schemaVersion = spec.schemaVersion or 1,
        migrations = spec.migrations or {},
        options = spec.options,
        api = spec.api,
        schema = spec.schema,
        enabled = false,
        _timers = {},
    }, Proto)

    if M.profileKey then
        if M.schema then
            assert(ns.Schema.IsNode(M.schema) and M.schema.kind == "table", name .. ": schema must be Schema.Table")
            if not M.schema.fields.enabled then
                M.schema.fields.enabled = ns.Schema.Bool{ default = true, label = ns.L["Enabled"], order = 0 }
            end
            M.defaults = ns.Schema.Default(M.schema)
        else
            M.defaults = spec.defaults or {}
            if M.defaults.enabled == nil then M.defaults.enabled = true end
        end
    end

    self.list[#self.list + 1] = M
    self.byName[name] = M
    if self.initialized then -- late registration (load-on-demand addon)
        self:Bind(M)
        ns.SafeCall(name, M.OnInitialize, M)
        self:EvaluateAll()
    end
    return M
end

function Modules:Get(name) return self.byName[name] end

function Modules:Iterate() return ipairs(self.list) end

---------------------------------------------------------------------------
-- Settings binding and migrations
---------------------------------------------------------------------------

-- Runs pending migrations on a module's saved table. Pure: used on login and import.
-- A migration receives the table and may modify it in place or return a new one.
function Modules:Migrate(M, data, fromVersion)
    for v = (fromVersion or 1) + 1, M.schemaVersion do
        local fn = M.migrations[v]
        if fn then
            local out = fn(data)
            if type(out) == "table" then data = out end
        end
    end
    return data
end

function Modules:Bind(M)
    if not M.profileKey then return end
    local profile = ns.Profiles:Active(M.profileKey)
    profile.__versions = profile.__versions or {}
    local data = profile[M.name]
    if type(data) ~= "table" then
        data = {}
    else
        data = self:Migrate(M, data, profile.__versions[M.name])
    end
    profile.__versions[M.name] = M.schemaVersion
    ns.Util.FillDefaults(data, M.defaults)
    profile[M.name] = data
    M.db = data
end

function Modules:BindStore(store)
    for _, M in ipairs(self.list) do
        if M.profileKey == store then
            self:Bind(M)
            if self.initialized then ns.SafeCall(M.name, M.OnProfileChanged, M) end
        end
    end
    if self.initialized then self:EvaluateAll() end
end

---------------------------------------------------------------------------
-- Enable / disable
---------------------------------------------------------------------------

local function Matches(value, want)
    if want == nil then return true end
    if type(want) == "table" then
        for _, w in ipairs(want) do if w == value then return true end end
        return false
    end
    return value == want
end

function Modules:ConditionsMet(M)
    local w = M.loadWhen
    if not w then return true end
    local p = ns.Player
    if not Matches(p.class, w.class) then return false end
    if not Matches(p.specID, w.specID) then return false end
    if not Matches(p.role, w.role) then return false end
    if not Matches(p.instanceType, w.instanceType) then return false end
    if w.addon and not C_AddOns.IsAddOnLoaded(w.addon) then return false end
    return true
end

local function Cleanup(M)
    ns.Events:OffAll(M)
    for t in pairs(M._timers) do t:Cancel() end
    wipe(M._timers)
end

function Modules:Evaluate(M)
    local want = (not M.db or M.db.enabled ~= false) and self:ConditionsMet(M)
    for _, dep in ipairs(M.requires) do
        local D = self.byName[dep]
        if not (D and D.enabled) then want = false end
    end
    if want and not M.enabled then
        M.enabled = true
        if not ns.SafeCall(M.name, M.OnEnable, M) then
            -- Half-enabled modules are worse than disabled ones: roll back.
            ns.SafeCall(M.name, M.OnDisable, M)
            Cleanup(M)
            M.enabled = false
        end
        ns.Log:Debug("Modules", "%s enabled=%s", M.name, tostring(M.enabled))
    elseif not want and M.enabled then
        M.enabled = false
        ns.SafeCall(M.name, M.OnDisable, M)
        Cleanup(M)
        ns.Log:Debug("Modules", "%s disabled", M.name)
    end
end

-- Topological order so a module is evaluated after what it requires.
function Modules:Ordered()
    local out, state = {}, {}
    local function visit(M)
        if state[M] == 2 then return end
        if state[M] == 1 then error("module dependency cycle at " .. M.name) end
        state[M] = 1
        for _, dep in ipairs(M.requires) do
            local D = self.byName[dep]
            if D then visit(D) else ns.Log:Warn(M.name, "requires unknown module %s", dep) end
        end
        state[M] = 2
        out[#out + 1] = M
    end
    for _, M in ipairs(self.list) do visit(M) end
    return out
end

function Modules:EvaluateAll()
    for _, M in ipairs(self:Ordered()) do self:Evaluate(M) end
end

function Modules:InitializeAll()
    for _, M in ipairs(self:Ordered()) do
        self:Bind(M)
        ns.SafeCall(M.name, M.OnInitialize, M)
    end
    self.initialized = true
    self:EvaluateAll()
end

function Modules:RefreshAll()
    for _, M in ipairs(self.list) do
        if M.enabled then ns.SafeCall(M.name, M.Refresh, M) end
    end
end
