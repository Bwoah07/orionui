-- Public API: the global OrionUIAPI (CLAUDE.md §10.5). Stable and versioned; used by our
-- installer and anyone else. Documented in docs/api.md. Mutating calls refuse in
-- combat and return false, "combat".
local _, ns = ...

local API = { version = 1 }

local function ValidStore(store) return store == "layout" or store == "reminders" end

function API.OpenConfig(page)
    ns.Options:Open(page)
end

-- -> ok, report | false, reason
function API.ImportProfile(store, str, name, opts)
    if not ValidStore(store) then return false, "unknown store" end
    return ns.ProfileIO:Import(store, str, name, opts)
end

-- -> string | nil, reason
function API.ExportProfile(store, name)
    if not ValidStore(store) then return nil, "unknown store" end
    return ns.ProfileIO:Export(store, name)
end

-- -> array of names, active name
function API.GetProfiles(store)
    if not ValidStore(store) then return nil end
    return ns.Profiles:List(store), ns.Profiles:ActiveName(store)
end

function API.SetProfile(store, name)
    if InCombatLockdown() then return false, "combat" end
    if not ValidStore(store) then return false, "unknown store" end
    return ns.Profiles:Switch(store, name)
end

OrionUIAPI = API

-- Addon compartment (minimap addon menu) entry; the TOC names this global.
function OrionUI_OnAddonCompartmentClick()
    ns.Options:Toggle()
end
