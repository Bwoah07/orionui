-- Combat queue and restriction-state cache (CLAUDE.md §6.7).
local _, ns = ...

local Combat = { restrictions = {} }
ns.Combat = Combat

local queue, order = {}, {}

function Combat:InLockdown()
    return InCombatLockdown()
end

-- Runs fn now if out of combat, else once after combat ends. Repeated requests with
-- the same key collapse to the latest fn (e.g. many layout changes -> one apply).
function Combat:Defer(key, fn)
    if not InCombatLockdown() then
        return ns.SafeCall("Defer:" .. key, fn)
    end
    if not queue[key] then order[#order + 1] = key end
    queue[key] = fn
    return false, "deferred"
end

function Combat:IsRestricted(typeName)
    local value = Enum.AddOnRestrictionType and Enum.AddOnRestrictionType[typeName]
    if value == nil then return nil end
    return self.restrictions[value] == Enum.AddOnRestrictionState.Active
        or self.restrictions[value] == Enum.AddOnRestrictionState.Activating
end

local function RefreshRestrictions()
    if not (C_RestrictedActions and Enum.AddOnRestrictionType) then return end
    for _, value in pairs(Enum.AddOnRestrictionType) do
        Combat.restrictions[value] = C_RestrictedActions.GetAddOnRestrictionState(value)
    end
end

function Combat:OnInitialize()
    RefreshRestrictions()
    ns.Events:On("PLAYER_REGEN_DISABLED", self, function()
        ns.Events:Fire("OUI_COMBAT_START")
    end)
    ns.Events:On("PLAYER_REGEN_ENABLED", self, function()
        local keys, fns = order, queue
        order, queue = {}, {}
        for _, key in ipairs(keys) do ns.SafeCall("Defer:" .. key, fns[key]) end
        ns.Events:Fire("OUI_COMBAT_END")
    end)
    ns.Events:On("ADDON_RESTRICTION_STATE_CHANGED", self, function(_, _, rtype, state)
        -- Payload is documented plain; guard anyway since we branch on it.
        if ns.Secret.Is(rtype) or ns.Secret.Is(state) then return end
        Combat.restrictions[rtype] = state
        ns.Events:Fire("OUI_RESTRICTION_CHANGED", rtype, state)
    end)
end
Combat.name = "Combat"
