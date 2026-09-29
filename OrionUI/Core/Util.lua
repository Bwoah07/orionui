-- Small table/string helpers. Pure Lua: no WoW API, so it is unit tested.
local _, ns = ...

local type, pairs, next = type, pairs, next

local Util = {}
ns.Util = Util

function Util.DeepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local out = {}
    seen[v] = out
    for k, val in pairs(v) do out[Util.DeepCopy(k, seen)] = Util.DeepCopy(val, seen) end
    return out
end

-- Fills missing keys in `target` from `defaults`, recursively. Existing values win,
-- including false. Kira only filled top-level keys; nested tables drifted (CLAUDE.md §6.2).
function Util.FillDefaults(target, defaults)
    for k, dv in pairs(defaults) do
        local tv = target[k]
        if tv == nil then
            target[k] = Util.DeepCopy(dv)
        elseif type(tv) == "table" and type(dv) == "table" then
            Util.FillDefaults(tv, dv)
        end
    end
    return target
end

-- Removes values equal to their default so saved variables only store changes.
function Util.StripDefaults(target, defaults)
    for k, dv in pairs(defaults) do
        local tv = target[k]
        if type(tv) == "table" and type(dv) == "table" then
            Util.StripDefaults(tv, dv)
            if next(tv) == nil then target[k] = nil end
        elseif tv == dv then
            target[k] = nil
        end
    end
    return target
end

function Util.Wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end

function Util.Count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function Util.SortedKeys(t, cmp)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, cmp or function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

function Util.Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function Util.Split(s)
    local out = {}
    for word in s:gmatch("%S+") do out[#out + 1] = word end
    return out
end

-- "a.b.c" -> t.a.b.c (nil if any step is missing)
function Util.GetPath(t, path)
    for part in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

function Util.SetPath(t, path, value)
    local parts = {}
    for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
    for i = 1, #parts - 1 do
        local p = parts[i]
        if type(t[p]) ~= "table" then t[p] = {} end
        t = t[p]
    end
    t[parts[#parts]] = value
end
