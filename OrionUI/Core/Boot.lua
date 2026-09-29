-- Startup: SavedVariables -> combat/restriction cache -> player info -> modules.
-- Loaded after every Core file and before modules register (see TOC).
local ADDON_NAME, ns = ...

-- Cached player facts used by module loadWhen conditions.
ns.Player = {}

local function UpdatePlayer()
    local p = ns.Player
    local _, class = UnitClass("player")
    p.class = class
    local index = C_SpecializationInfo.GetSpecialization()
    local specID, role
    if index then
        local id, _, _, _, r = C_SpecializationInfo.GetSpecializationInfo(index)
        specID, role = id, r
    end
    local _, instanceType = GetInstanceInfo()
    p.instanceType = instanceType
    if specID ~= p.specID or role ~= p.role then
        p.specID, p.role = specID, role
        return true
    end
    return false
end

local Boot = { name = "Boot" }

local function OnLogin()
    local name, realm = UnitFullName("player")
    realm = realm or GetNormalizedRealmName() or "?"
    ns.DB:Initialize(OrionUIDB, OrionUICharDB, name .. "-" .. realm)
    OrionUIDB, OrionUICharDB = ns.DB.sv, ns.DB.char

    ns.Combat:OnInitialize()
    UpdatePlayer()
    ns.Media:Register()
    ns.Modules:InitializeAll()
    ns.Log:Info("Boot", "%s %s loaded, %d modules", ns.NAME, ns.VERSION, #ns.Modules.list)

    ns.Events:On("PLAYER_ENTERING_WORLD", Boot, function()
        if UpdatePlayer() then ns.Events:Fire("OUI_SPEC_CHANGED", ns.Player.specID, ns.Player.role) end
        ns.Modules:EvaluateAll()
    end)
    ns.Events:On("PLAYER_SPECIALIZATION_CHANGED", Boot, function(_, _, unit)
        if unit ~= "player" then return end
        if UpdatePlayer() then
            ns.Events:Fire("OUI_SPEC_CHANGED", ns.Player.specID, ns.Player.role)
            ns.Modules:EvaluateAll()
        end
    end)
    -- loadWhen = { addon = "X" } modules wake up when X loads.
    ns.Events:On("ADDON_LOADED", Boot, function(_, _, addon)
        if addon ~= ADDON_NAME then ns.Modules:EvaluateAll() end
    end)
end

ns.Events:On("PLAYER_LOGIN", Boot, function() OnLogin() end)
