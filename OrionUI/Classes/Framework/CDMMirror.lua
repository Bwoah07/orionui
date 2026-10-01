-- CDMMirror: show a player buff's stack count in combat by mirroring Blizzard's
-- Cooldown Manager (CDM) buff frames.
--
-- Why (verified in game 2026-09-30, docs/verification-log.md): in combat our own aura
-- queries are refused (GetUnitAuraInstanceIDs throws, aura data is secret), but the CDM's
-- tracked-buff frames keep a plain `cooldownID`, a secret-but-displayable stack string in
-- `Applications`, and `auraInstanceID` set only while the buff is up. FontString:SetText
-- accepts secret text (AllowedWhenTainted), so we can DISPLAY the count without reading it.
-- Limits: we never learn the number, so thresholds ("below 5") can't be computed in combat,
-- and the buff must be one of the player's CDM tracked buffs.
local _, ns = ...

local Mirror = {}
ns.CDMMirror = Mirror

local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
local infoCache = {} -- cooldownID -> set of spell IDs it stands for

local function SpellsFor(cooldownID)
    local set = infoCache[cooldownID]
    if set then return set end
    set = {}
    local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
    if ns.Secret.CanRead(info) then
        for _, k in ipairs({ "spellID", "overrideSpellID", "overrideTooltipSpellID" }) do
            local v = ns.Secret.Plain(info[k])
            if v then set[v] = true end
        end
        if ns.Secret.CanRead(info.linkedSpellIDs) then
            for _, v in ipairs(info.linkedSpellIDs) do
                v = ns.Secret.Plain(v)
                if v then set[v] = true end
            end
        end
    end
    -- Cache only real answers: the info can be withheld in combat, and an empty set cached
    -- then would hide the buff for the rest of the session.
    if next(set) then infoCache[cooldownID] = set end
    return set
end

-- The CDM frame tracking any of `spellIDs` ({ [id] = true }), or nil.
-- The last match is remembered per spell set: in combat the lookup can fail (secret
-- cooldownID or withheld info) while the frame found out of combat still shows the buff.
local lastFound = setmetatable({}, { __mode = "k" })
local function Search(spellIDs)
    for _, name in ipairs(VIEWERS) do
        local viewer = _G[name]
        if viewer then
            for _, child in ipairs({ viewer:GetChildren() }) do
                local id = child.cooldownID
                if not ns.Secret.Is(id) and id ~= nil then -- check secrecy before comparing
                    for spell in pairs(SpellsFor(id)) do
                        if spellIDs[spell] then return child end
                    end
                end
            end
        end
    end
end

function Mirror:Find(spellIDs)
    local child = Search(spellIDs)
    if child then lastFound[spellIDs] = child return child end
    local old = lastFound[spellIDs]
    if not old then return nil end
    -- Reuse it only while we can't tell what it tracks now (a pooled frame may have moved on).
    local id = old.cooldownID
    if ns.Secret.Is(id) or (id ~= nil and next(SpellsFor(id)) == nil) then return old end
end

-- Is the buff up? type() is safe on secrets; the CDM clears auraInstanceID when it drops.
function Mirror:IsActive(child)
    return child ~= nil and type(child.auraInstanceID) ~= "nil"
end

-- The CDM's stack FontString (Applications frame holds an Applications FontString).
local function StackString(child)
    local apps = child and child.Applications
    local fs = apps and (apps.Applications or apps)
    if fs and fs.GetText then return fs end
end

-- Copies the CDM's (possibly secret) stack text into our FontString. -> true if copied.
function Mirror:CopyStacks(child, target)
    local fs = StackString(child)
    if not fs then return false end
    target:SetText(fs:GetText())
    return true
end

-- Copies the CDM icon's (possibly secret) countdown text, i.e. the buff's time left as
-- Blizzard's own Cooldown widget shows it, into our FontString. -> true if there was text.
-- FontString:GetText is secret for the Text aspect; SetText accepts it (display only).
function Mirror:CopyCountdown(child, target)
    local cd = child and child.Cooldown
    local fs = cd and cd.GetCountdownFontString and cd:GetCountdownFontString()
    if not (fs and fs.GetText) then return false end
    local text = fs:GetText()
    if type(text) == "nil" then return false end
    target:SetText(text)
    return true
end

function Mirror:Forget() wipe(infoCache) end

ns.Events:On("COOLDOWN_VIEWER_DATA_LOADED", Mirror, function() Mirror:Forget() end)
Mirror.name = "CDMMirror"
