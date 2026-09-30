-- Media lookup. Our own media (CLAUDE.md §12.3) is registered with
-- LibSharedMedia when it is loaded (EllesmereUI and most packs load it); we don't
-- embed LSM ourselves. Lookups fall back to Blizzard defaults so nothing breaks
-- without it.
local _, ns = ...

local Media = {}
ns.Media = Media

local FALLBACK = {
    font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
    statusbar = "Interface\\Buttons\\WHITE8X8",
    background = "Interface\\Buttons\\WHITE8X8",
    border = "Interface\\Buttons\\WHITE8X8",
}

-- Our media, registered on login: { type, name, path }.
Media.own = {
    -- Grayscale 256x32 bar textures we made ourselves (2026-09-30); the game tints them.
    { "statusbar", "Orion Flat",   ns.MEDIA_PATH .. "Textures\\Flat.tga" },
    { "statusbar", "Orion Smooth", ns.MEDIA_PATH .. "Textures\\Smooth.tga" },
    { "statusbar", "Orion Stripe", ns.MEDIA_PATH .. "Textures\\Stripe.tga" },
    -- Fonts under SIL OFL 1.1 with no reserved font names (licenses in Media/Fonts/OFL-*.txt).
    -- Main font is EllesmereUI's Expressway (EUI ships it; we use it, never bundle it).
    { "font", "Orion 2",      ns.MEDIA_PATH .. "Fonts\\Orion2.ttf" },      -- Inter SemiBold
    { "font", "Orion 2 Bold", ns.MEDIA_PATH .. "Fonts\\Orion2-Bold.ttf" }, -- Inter Bold
    { "font", "Orion 3",      ns.MEDIA_PATH .. "Fonts\\Orion3.ttf" },      -- Rajdhani SemiBold
    { "font", "Orion 3 Bold", ns.MEDIA_PATH .. "Fonts\\Orion3-Bold.ttf" }, -- Rajdhani Bold
}

local function LSM()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

function Media:Register()
    local lsm = LSM()
    if not lsm then return end
    for _, m in ipairs(self.own) do lsm:Register(m[1], m[2], m[3]) end
end

-- Path for a named media, or the fallback for that type.
function Media:Fetch(mediaType, name)
    local lsm = LSM()
    local path = lsm and name and lsm:Fetch(mediaType, name, true)
    return path or FALLBACK[mediaType]
end

function Media:List(mediaType)
    local lsm = LSM()
    return lsm and lsm:List(mediaType) or {}
end

-- Register as soon as this file loads too: EllesmereUI (an OptionalDep, so loaded first)
-- brings LibSharedMedia, and registering early puts our textures in its pickers right away.
Media:Register()
