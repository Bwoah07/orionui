-- Minimal WoW environment for busted. Pure-logic modules take their WoW dependencies as
-- parameters (CLAUDE.md §16.1); this file only provides what file headers touch.
local mock = {}

-- A sentinel standing in for a 12.x secret value. Any attempt to stringify it errors,
-- so tests catch code that would leak a secret into text.
local SECRET = setmetatable({}, {
    __tostring = function() error("secret value was stringified", 2) end,
    __concat = function() error("secret value was concatenated", 2) end,
    __eq = function() error("secret value was compared", 2) end,
})
mock.SECRET = SECRET

function _G.issecretvalue(v) return rawequal(v, SECRET) end
function _G.canaccesstable(t) return not rawequal(t, SECRET) end
function _G.GetTime() return mock.now or 0 end

_G.C_AddOns = { GetAddOnMetadata = function() return "test" end }

-- Loads an addon file with the (addonName, ns) varargs WoW passes to every file.
function mock.LoadAddonFile(path, addonName, ns)
    local chunk = assert(loadfile(path))
    chunk(addonName, ns)
    return ns
end

_G.WowMock = mock
return mock
