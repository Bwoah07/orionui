-- OrionUI_Dev: namespace, secret-safe value description, tiny event helper.
--
-- Everything in this addon is READ-ONLY. Probes query APIs and describe what came back.
-- They never change game state, never register COMBAT_LOG_EVENT_UNFILTERED, and never
-- read, compare, or do arithmetic on a value that may be secret (CLAUDE.md §4).
local ADDON_NAME, ns = ...

ns.NAME = "OrionUI_Dev"
ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

local type, tostring, format, pairs = type, tostring, string.format, pairs
local issecretvalue = issecretvalue
local canaccesstable = canaccesstable

---------------------------------------------------------------------------
-- Secret-safe helpers
--
-- Pattern taken from how Blizzard's own Dump.lua treats secrets: type() is always
-- safe, issecretvalue() is safe on any value including nil, and a secret value is
-- never passed to tostring/format/concat (that would give us a secret string we
-- cannot write into our log).
---------------------------------------------------------------------------

function ns.IsSecret(v)
    if not issecretvalue then return false end -- pre-12.x client: nothing is secret
    return issecretvalue(v) == true
end

-- Tables can themselves be secret (opaque). Their fields must not be indexed then.
function ns.CanReadTable(t)
    if ns.IsSecret(t) then return false end
    if canaccesstable then return canaccesstable(t) == true end
    return true
end

-- One-word, always-plain description of any value. Secrets become "<secret type>".
function ns.Describe(v)
    local t = type(v)
    if ns.IsSecret(v) then return "<secret " .. t .. ">" end
    if t == "nil" then return "nil" end
    if t == "string" then
        if #v > 80 then v = v:sub(1, 80) .. "…" end
        return format("%q", v)
    end
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "table" then
        if not ns.CanReadTable(v) then return "<inaccessible table>" end
        -- BigWigs passes its boss module as the first message argument.
        -- Check secrecy before any truthiness test: `a or b` on a secret would error.
        local name = v.moduleName
        if ns.IsSecret(name) then return "<table secret-name>" end
        if type(name) == "string" then return "<table " .. name .. ">" end
        return "<table>"
    end
    return "<" .. t .. ">"
end

-- Enum value -> name, only for readable values.
function ns.EnumName(enumTable, v)
    if ns.IsSecret(v) or v == nil or not enumTable then return ns.Describe(v) end
    for name, value in pairs(enumTable) do
        if value == v then return name end
    end
    return tostring(v)
end

-- "field=value(S)" for a list of known struct fields, (S) marking secret values,
-- followed by any fields we did not expect so API changes show up in the log.
function ns.DescribeFields(tbl, fields)
    if type(tbl) ~= "table" then return ns.Describe(tbl) end
    if not ns.CanReadTable(tbl) then return "<inaccessible table>" end
    local parts, seen = {}, {}
    for _, f in ipairs(fields) do
        seen[f] = true
        local v = tbl[f]
        parts[#parts + 1] = f .. "=" .. ns.Describe(v)
    end
    for k, v in pairs(tbl) do
        if ns.IsSecret(k) then
            parts[#parts + 1] = "<secret key>=" .. ns.Describe(v)
        elseif not seen[k] then
            parts[#parts + 1] = tostring(k) .. "=" .. ns.Describe(v)
        end
    end
    return table.concat(parts, " ")
end

-- Count of secret vs readable values in a struct: quick "can we branch?" summary.
function ns.SecretSummary(tbl, fields)
    if type(tbl) ~= "table" or not ns.CanReadTable(tbl) then return "n/a" end
    local secret, plain = {}, 0
    for _, f in ipairs(fields) do
        if ns.IsSecret(tbl[f]) then secret[#secret + 1] = f else plain = plain + 1 end
    end
    if #secret == 0 then return "all readable" end
    return "secret: " .. table.concat(secret, ",")
end

-- Calls an API that might not exist on this build. Never hides errors: a failed
-- call returns the error text so it lands in the log (CLAUDE.md §2.7).
function ns.Try(fn, ...)
    if type(fn) ~= "function" then return false, "API missing" end
    return pcall(fn, ...)
end

---------------------------------------------------------------------------
-- Event helper (one frame, handlers keyed by event)
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}
ns.eventFrame = frame

function ns.On(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
    frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then
            ns.Chat("|cffff5555handler error|r " .. event .. ": " .. tostring(err))
            geterrorhandler()(err)
        end
    end
end)

function ns.Chat(msg)
    print("|cff9d7bffOrionUI_Dev|r " .. msg)
end

---------------------------------------------------------------------------
-- SavedVariables
---------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    OrionUIDevDB = OrionUIDevDB or {}
    local db = OrionUIDevDB
    db.log = db.log or {}
    if db.watch == nil then db.watch = true end
    ns.db = db
    if ns.OnDBReady then ns.OnDBReady() end
end)
