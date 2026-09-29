-- Declarative settings schema (CLAUDE.md §6.5). One description drives three things:
-- defaults, import validation (wrong types reset, unknown keys dropped, sizes capped)
-- and the auto-built options UI (label/desc/order/hidden on each node).
-- Pure Lua: unit tested.
local _, ns = ...

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring

local Schema = {}
ns.Schema = Schema

local NODE = {} -- marker so options/builders can recognise schema nodes

local function Node(kind, spec)
    spec = spec or {}
    spec.kind = kind
    spec[NODE] = true
    return spec
end

function Schema.IsNode(v) return type(v) == "table" and v[NODE] == true end

function Schema.Bool(spec) return Node("bool", spec) end
function Schema.Number(spec) return Node("number", spec) end
function Schema.String(spec) return Node("string", spec) end
function Schema.Enum(spec)
    assert(spec and spec.values, "Enum needs values")
    return Node("enum", spec)
end
function Schema.Color(spec) return Node("color", spec) end
-- fields: name -> node. allowUnknown keeps keys not in fields.
function Schema.Table(spec)
    assert(spec and spec.fields, "Table needs fields")
    return Node("table", spec)
end
-- Array of `of`. max caps the length (default 500).
function Schema.List(spec)
    assert(spec and spec.of, "List needs of")
    return Node("list", spec)
end
-- String/number keys -> `of`. For user-keyed data such as per-encounter bindings.
function Schema.Map(spec)
    assert(spec and spec.of, "Map needs of")
    return Node("map", spec)
end

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------

function Schema.Default(node)
    local k = node.kind
    if k == "table" then
        local out = {}
        for name, field in pairs(node.fields) do out[name] = Schema.Default(field) end
        return out
    elseif k == "list" or k == "map" then
        return ns.Util.DeepCopy(node.default or {})
    elseif k == "color" then
        return ns.Util.DeepCopy(node.default or { 1, 1, 1, 1 })
    end
    return node.default
end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------

function Schema.NewReport() return { fixed = {}, dropped = {}, errors = {} } end

local function Fix(report, path, why)
    if report then report.fixed[#report.fixed + 1] = path .. ": " .. why end
end

local function IsFiniteNumber(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local validators = {}

function validators.bool(node, v, path, report)
    if type(v) == "boolean" then return v end
    Fix(report, path, "not a true/false value, reset")
    return node.default
end

function validators.number(node, v, path, report)
    if not IsFiniteNumber(v) then
        Fix(report, path, "not a number, reset")
        return node.default
    end
    if node.min and v < node.min then Fix(report, path, "below minimum, clamped") return node.min end
    if node.max and v > node.max then Fix(report, path, "above maximum, clamped") return node.max end
    return v
end

function validators.string(node, v, path, report)
    if type(v) ~= "string" then
        Fix(report, path, "not text, reset")
        return node.default
    end
    local maxLen = node.maxLen or 4000
    if #v > maxLen then
        Fix(report, path, "too long, cut")
        return v:sub(1, maxLen)
    end
    return v
end

function validators.enum(node, v, path, report)
    for _, allowed in ipairs(node.values) do
        if v == allowed then return v end
    end
    Fix(report, path, "unknown choice " .. tostring(v) .. ", reset")
    return node.default
end

function validators.color(node, v, path, report)
    if type(v) == "table" then
        local ok = true
        for i = 1, 3 do
            if not IsFiniteNumber(v[i]) or v[i] < 0 or v[i] > 1 then ok = false end
        end
        local a = v[4]
        if a ~= nil and (not IsFiniteNumber(a) or a < 0 or a > 1) then ok = false end
        if ok then return { v[1], v[2], v[3], a or 1 } end
    end
    Fix(report, path, "not a colour, reset")
    return Schema.Default(node)
end

function validators.table(node, v, path, report)
    if type(v) ~= "table" then
        if v ~= nil then Fix(report, path, "not a table, reset") end
        return Schema.Default(node)
    end
    local out = {}
    for name, field in pairs(node.fields) do
        local fv = v[name]
        if fv == nil then
            out[name] = Schema.Default(field) -- missing is normal (older data), not reported
        else
            out[name] = Schema.Validate(field, fv, path .. "." .. tostring(name), report)
        end
    end
    for key, val in pairs(v) do
        if node.fields[key] == nil then
            if node.allowUnknown then
                out[key] = ns.Util.DeepCopy(val)
            elseif report then
                report.dropped[#report.dropped + 1] = path .. "." .. tostring(key)
            end
        end
    end
    return out
end

function validators.list(node, v, path, report)
    if type(v) ~= "table" then
        if v ~= nil then Fix(report, path, "not a list, reset") end
        return Schema.Default(node)
    end
    local max = node.max or 500
    local out = {}
    for i = 1, #v do
        if i > max then
            Fix(report, path, "more than " .. max .. " entries, extra dropped")
            break
        end
        out[i] = Schema.Validate(node.of, v[i], path .. "[" .. i .. "]", report)
    end
    return out
end

function validators.map(node, v, path, report)
    if type(v) ~= "table" then
        if v ~= nil then Fix(report, path, "not a table, reset") end
        return Schema.Default(node)
    end
    local max, n, out = node.max or 1000, 0, {}
    for key, val in pairs(v) do
        local kt = type(key)
        if kt ~= "string" and kt ~= "number" then
            if report then report.dropped[#report.dropped + 1] = path .. "[?]" end
        elseif n >= max then
            Fix(report, path, "more than " .. max .. " entries, extra dropped")
            break
        else
            n = n + 1
            out[key] = Schema.Validate(node.of, val, path .. "[" .. tostring(key) .. "]", report)
        end
    end
    return out
end

-- Returns a cleaned copy of v; never modifies v. report is optional.
function Schema.Validate(node, v, path, report)
    local fn = validators[node.kind]
    if not fn then error("unknown schema kind " .. tostring(node.kind)) end
    return fn(node, v, path or "", report)
end
