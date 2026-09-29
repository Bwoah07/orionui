-- Profile import/export (CLAUDE.md §10.3-10.4). Import order: decode -> size limits
-- -> per-module migrations -> schema validation (unknown keys dropped) -> backup ->
-- apply -> report. Caches are never part of a profile, so they are never exported.
local _, ns = ...

local ProfileIO = {}
ns.ProfileIO = ProfileIO

local KIND_FOR_STORE = { layout = "L", reminders = "R" }

function ProfileIO:Export(store, name)
    local kind = KIND_FOR_STORE[store]
    if not kind then return nil, "unknown store" end
    name = name or ns.Profiles:ActiveName(store)
    local profile = ns.DB.sv.profiles[store][name]
    if not profile then return nil, "no such profile" end
    local data = ns.Util.DeepCopy(profile)
    local versions = data.__versions or {}
    data.__versions = nil
    return ns.Serialize:Encode(kind, {
        addon = ns.NAME, addonVersion = ns.VERSION, dbVersion = ns.DB.VERSION,
        store = store, name = name, versions = versions, data = data,
    })
end

-- Decodes and validates without touching saved data. -> ok, cleanProfile, report | false, err
function ProfileIO:Prepare(store, str)
    local ok, kind, payload = ns.Serialize:Decode(str)
    if not ok then return false, kind end
    if kind ~= KIND_FOR_STORE[store] then
        return false, ("this is a %s string, not %s"):format(ns.Serialize.KINDS[kind] or kind, store)
    end
    if type(payload.data) ~= "table" then return false, "string has no profile data" end

    local report = ns.Schema.NewReport()
    report.modules, report.sourceName = {}, payload.name
    local versions = type(payload.versions) == "table" and payload.versions or {}
    local clean = { __versions = {} }

    for key, section in pairs(payload.data) do
        local M = type(key) == "string" and ns.Modules:Get(key)
        if not M or M.profileKey ~= store or type(section) ~= "table" then
            report.dropped[#report.dropped + 1] = tostring(key) .. " (not an " .. store .. " module here)"
        else
            local from = tonumber(versions[key]) or 1
            if from > M.schemaVersion then
                report.errors[#report.errors + 1] = key .. ": made by a newer " .. ns.NAME .. "; some settings may be ignored"
                from = M.schemaVersion
            end
            local migrated = ns.Modules:Migrate(M, ns.Util.DeepCopy(section), from)
            if M.schema then
                clean[key] = ns.Schema.Validate(M.schema, migrated, key, report)
            else
                clean[key] = migrated
            end
            clean.__versions[key] = M.schemaVersion
            report.modules[#report.modules + 1] = M.label
        end
    end
    table.sort(report.modules)
    return true, clean, report
end

-- opts: overwrite (replace an existing profile of that name), activate (switch to it).
-- -> ok, report | false, err
function ProfileIO:Import(store, str, name, opts)
    opts = opts or {}
    if InCombatLockdown() then return false, "combat" end
    local ok, clean, report = self:Prepare(store, str)
    if not ok then return false, clean end

    name = name or report.sourceName or "Imported"
    if type(name) ~= "string" or not name:match("%S") then name = "Imported" end
    local exists = ns.Profiles:Exists(store, name)
    if exists and not opts.overwrite then return false, "a profile named " .. name .. " already exists" end

    ns.DB:Backup(store, "before importing " .. name)
    ns.DB.sv.profiles[store][name] = clean
    report.name = name

    if opts.activate then
        ns.Profiles:Switch(store, name)
    elseif ns.Profiles:ActiveName(store) == name then
        ns.Profiles:Rebind(store)
    end
    ns.Log:Info("ProfileIO", "imported %s profile %s: %d fixed, %d dropped", store, name, #report.fixed, #report.dropped)
    return true, report
end

-- One-paragraph text for the import dialog.
function ProfileIO:DescribeReport(report)
    local lines = {}
    if report.name then lines[#lines + 1] = "Imported as \"" .. report.name .. "\"." end
    if #report.modules > 0 then lines[#lines + 1] = "Contains: " .. table.concat(report.modules, ", ") .. "." end
    if #report.fixed > 0 then lines[#lines + 1] = #report.fixed .. " invalid setting(s) reset to default." end
    if #report.dropped > 0 then lines[#lines + 1] = #report.dropped .. " unknown setting(s) ignored." end
    for _, e in ipairs(report.errors) do lines[#lines + 1] = e end
    return table.concat(lines, "\n")
end
