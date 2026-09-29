-- Profile stores (CLAUDE.md §10). Two stores, `layout` and `reminders`, so importing
-- a look never wipes someone's reminders. Module db views point straight into the
-- active profile table: edits are live, nothing is snapshotted on switch.
local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles

local DEFAULT = "Default"

local function ValidStore(store)
    for _, s in ipairs(ns.DB.STORES) do if s == store then return true end end
    return false
end

local function ValidName(name)
    return type(name) == "string" and name:match("%S") ~= nil and #name <= 48
end

function Profiles:List(store)
    return ns.Util.SortedKeys(ns.DB.sv.profiles[store])
end

function Profiles:ActiveName(store)
    local a = ns.DB.sv.active[store]
    local name = a.byChar[ns.DB.charKey] or a.default
    if not ns.DB.sv.profiles[store][name] then name = DEFAULT end
    return name
end

-- The live table of the active profile.
function Profiles:Active(store)
    return ns.DB.sv.profiles[store][self:ActiveName(store)]
end

function Profiles:Exists(store, name)
    return ns.DB.sv.profiles[store][name] ~= nil
end

-- Re-points every module of the store at the active profile and notifies them.
function Profiles:Rebind(store)
    ns.Modules:BindStore(store)
    ns.Events:Fire("OUI_PROFILE_CHANGED", store, self:ActiveName(store))
end

function Profiles:Switch(store, name)
    if not ValidStore(store) then return false, "unknown store" end
    if not self:Exists(store, name) then return false, "no such profile" end
    ns.DB.sv.active[store].byChar[ns.DB.charKey] = name
    self:Rebind(store)
    return true
end

-- New empty profile (modules fill defaults when bound), or a copy of `from`.
function Profiles:New(store, name, from)
    if not ValidName(name) then return false, "invalid name" end
    if self:Exists(store, name) then return false, "name already used" end
    local src = from and ns.DB.sv.profiles[store][from]
    ns.DB.sv.profiles[store][name] = src and ns.Util.DeepCopy(src) or {}
    return true
end

-- Overwrites the ACTIVE profile with a copy of `from` (backed up first).
function Profiles:CopyFrom(store, from)
    local src = ns.DB.sv.profiles[store][from]
    if not src then return false, "no such profile" end
    local name = self:ActiveName(store)
    if name == from then return false, "same profile" end
    ns.DB:Backup(store, "before copying " .. from .. " into " .. name)
    ns.DB.sv.profiles[store][name] = ns.Util.DeepCopy(src)
    self:Rebind(store)
    return true
end

function Profiles:Rename(store, old, new)
    if old == DEFAULT then return false, "Default can't be renamed" end
    if not self:Exists(store, old) then return false, "no such profile" end
    if not ValidName(new) or self:Exists(store, new) then return false, "invalid or used name" end
    local p = ns.DB.sv.profiles[store]
    p[new], p[old] = p[old], nil
    local a = ns.DB.sv.active[store]
    for char, n in pairs(a.byChar) do if n == old then a.byChar[char] = new end end
    if a.default == old then a.default = new end
    return true
end

function Profiles:Delete(store, name)
    if name == DEFAULT then return false, "Default can't be deleted" end
    if name == self:ActiveName(store) then return false, "can't delete the active profile" end
    if not self:Exists(store, name) then return false, "no such profile" end
    ns.DB:Backup(store, "before deleting " .. name)
    ns.DB.sv.profiles[store][name] = nil
    local a = ns.DB.sv.active[store]
    for char, n in pairs(a.byChar) do if n == name then a.byChar[char] = nil end end
    if a.default == name then a.default = DEFAULT end
    return true
end

-- Resets the active profile to defaults (backed up first).
function Profiles:Reset(store)
    local name = self:ActiveName(store)
    ns.DB:Backup(store, "before resetting " .. name)
    ns.DB.sv.profiles[store][name] = {}
    self:Rebind(store)
    return true
end
