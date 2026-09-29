-- Error-reporting protected call (CLAUDE.md §2.7). Never silent: every failure is
-- logged with its tag and stack; in dev builds Log:Error also forwards to BugSack.
local _, ns = ...

local xpcall, debugstack, select, unpack = xpcall, debugstack, select, unpack

local lastError
local function handler(err)
    lastError = tostring(err) .. "\n" .. (debugstack and debugstack(2) or "")
    return err
end

-- ns.SafeCall(tag, fn, ...) -> ok, results...
-- Arguments go through a closure so this also runs on stock Lua 5.1 (tests).
function ns.SafeCall(tag, fn, ...)
    local n, args = select("#", ...), { ... }
    local results = { xpcall(function() return fn(unpack(args, 1, n)) end, handler) }
    if not results[1] then
        ns.Log:Error(tag, "%s", lastError)
    end
    return unpack(results, 1, table.maxn(results))
end
