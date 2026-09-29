-- SavedVariables layout, account-level migrations and backups (CLAUDE.md §6.4).
--
-- OrionUIDB = {
--   schemaVersion, global = {}, profiles = { layout = {[name]={}}, reminders = {...} },
--   active = { layout = { byChar = {}, default = "Default" }, reminders = {...} },
--   backups = { {time, reason, store, snapshot} ... }, caches = {} }
-- OrionUICharDB = operational per-character state only.
local _, ns = ...

local DB = { STORES = { "layout", "reminders" }, VERSION = 1 }
ns.DB = DB

-- Account-level migrations, keyed by the version they migrate TO. Pure functions of
-- the SavedVariables table; run in order on login.
DB.migrations = {
    -- [2] = function(sv) end,
}

local function EnsureStructure(sv)
    sv.global = sv.global or {}
    sv.profiles = sv.profiles or {}
    sv.active = sv.active or {}
    for _, store in ipairs(DB.STORES) do
        sv.profiles[store] = sv.profiles[store] or {}
        sv.active[store] = sv.active[store] or { byChar = {}, default = "Default" }
        sv.active[store].byChar = sv.active[store].byChar or {}
        sv.active[store].default = sv.active[store].default or "Default"
        sv.profiles[store].Default = sv.profiles[store].Default or {}
    end
    sv.backups = sv.backups or {}
    sv.caches = sv.caches or {}
    return sv
end

function DB.Migrate(sv)
    local from = sv.schemaVersion or DB.VERSION
    for v = from + 1, DB.VERSION do
        local fn = DB.migrations[v]
        if fn then fn(sv) end
        sv.schemaVersion = v
    end
    sv.schemaVersion = DB.VERSION
end

-- Called with the SavedVariables tables (tests pass plain tables).
function DB:Initialize(sv, charSV, charKey)
    self.sv = EnsureStructure(sv or {})
    self.char = charSV or {}
    self.charKey = charKey
    DB.Migrate(self.sv)
    return self.sv, self.char
end

---------------------------------------------------------------------------
-- Backups: taken before anything destructive. The whole store is snapshotted so a
-- restore also brings back deleted or renamed profiles.
---------------------------------------------------------------------------

function DB:Backup(store, reason)
    local backups = self.sv.backups
    table.insert(backups, 1, {
        time = time and time() or 0,
        reason = reason,
        store = store,
        snapshot = ns.Util.DeepCopy(self.sv.profiles[store]),
    })
    while #backups > ns.MAX_BACKUPS do table.remove(backups) end
    ns.Log:Info("DB", "backup of %s store: %s", store, reason)
    return backups[1]
end

function DB:Backups() return self.sv.backups end

function DB:RestoreBackup(index)
    local b = self.sv.backups[index]
    if not b then return false, "no such backup" end
    -- Restoring is itself destructive: back up the current state first.
    self:Backup(b.store, "before restoring backup from " .. (date and date("%Y-%m-%d %H:%M", b.time) or b.time))
    self.sv.profiles[b.store] = ns.Util.DeepCopy(b.snapshot)
    self.sv.profiles[b.store].Default = self.sv.profiles[b.store].Default or {}
    ns.Profiles:Rebind(b.store)
    return true
end
