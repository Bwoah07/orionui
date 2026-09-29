-- The only place that deals with 12.x secret values (CLAUDE.md §4, §6.6). Everything
-- else calls these. Rules proven in game on 2026-09-29 (docs/verification-log.md):
-- type() and issecretvalue() are safe on anything; comparing, doing maths on, testing
-- truthiness of, or stringifying a secret is not.
local _, ns = ...

local issecretvalue, canaccesstable = issecretvalue, canaccesstable

local Secret = {}
ns.Secret = Secret

function Secret.Is(v)
    if not issecretvalue then return false end
    return issecretvalue(v) == true
end

-- v when readable, otherwise fallback.
function Secret.Plain(v, fallback)
    if Secret.Is(v) then return fallback end
    return v
end

-- A table whose fields we may index (not itself secret/opaque).
function Secret.CanRead(t)
    if Secret.Is(t) then return false end
    if type(t) ~= "table" then return false end
    if canaccesstable then return canaccesstable(t) == true end
    return true
end

-- Shallow copy with secret values dropped. nil for unreadable tables.
function Secret.Scrub(t)
    if not Secret.CanRead(t) then return nil end
    local out = {}
    for k, v in pairs(t) do
        if not Secret.Is(k) and not Secret.Is(v) then out[k] = v end
    end
    return out
end

-- Tri-state boolean: true / false / nil (unknown). Unknown never collapses to false:
-- Kira's ready check reported unreadable flasks as "missing" (CLAUDE.md §6.6).
function Secret.Bool(v)
    if Secret.Is(v) then return nil end
    if v == true then return true end
    if v == false then return false end
    return nil
end
