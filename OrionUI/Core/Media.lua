-- Media lookup. Our own media (none yet, CLAUDE.md §12.3) is registered with
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
    -- { "statusbar", "Orion Flat", ns.MEDIA_PATH .. "Textures\\Flat.tga" },
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
