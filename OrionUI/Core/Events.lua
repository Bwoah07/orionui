-- Central event bus (CLAUDE.md §6.3). One hidden frame owns every Blizzard event
-- registration; a real event is registered only while something subscribes to it.
-- Internal messages start with "OUI_" and never touch the frame.
--
-- Handlers are called as handler(owner, event, ...) through SafeCall. `handler` may
-- be a function or the name of a method on `owner`.
local _, ns = ...

local Events = {}
ns.Events = Events

local frame = CreateFrame("Frame")
local subs = {}      -- event -> array of { owner = , fn = }
local unitFrames = {} -- owner -> event -> frame (RegisterUnitEvent needs its own frame)

local function IsInternal(event) return event:sub(1, 4) == "OUI_" end

local function Tag(owner)
    return type(owner) == "table" and (owner.name or owner.NAME) or tostring(owner)
end

local function Call(owner, fn, event, ...)
    if type(fn) == "string" then fn = owner[fn] end
    if type(fn) ~= "function" then
        ns.Log:Error(Tag(owner), "no handler for %s", event)
        return
    end
    ns.SafeCall(Tag(owner), fn, owner, event, ...)
end

local function Dispatch(event, ...)
    local list = subs[event]
    if not list then return end
    -- Snapshot: handlers may subscribe/unsubscribe while we iterate.
    local snapshot = {}
    for i = 1, #list do snapshot[i] = list[i] end
    for i = 1, #snapshot do
        local s = snapshot[i]
        if not s.removed then Call(s.owner, s.fn, event, ...) end
    end
end

frame:SetScript("OnEvent", function(_, event, ...) Dispatch(event, ...) end)

function Events:On(event, owner, fn)
    assert(type(event) == "string" and owner ~= nil, "Events:On(event, owner, handler)")
    fn = fn or event
    local list = subs[event]
    if not list then
        list = {}
        subs[event] = list
    end
    for i = 1, #list do
        if list[i].owner == owner then list[i].fn = fn return end
    end
    list[#list + 1] = { owner = owner, fn = fn }
    if #list == 1 and not IsInternal(event) then frame:RegisterEvent(event) end
end

function Events:Off(event, owner)
    local list = subs[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].owner == owner then
            list[i].removed = true
            table.remove(list, i)
        end
    end
    if #list == 0 then
        subs[event] = nil
        if not IsInternal(event) then frame:UnregisterEvent(event) end
    end
    local uf = unitFrames[owner] and unitFrames[owner][event]
    if uf then
        uf:UnregisterAllEvents()
        unitFrames[owner][event] = nil
    end
end

function Events:OffAll(owner)
    local events = {}
    for event, list in pairs(subs) do
        for i = 1, #list do
            if list[i].owner == owner then events[#events + 1] = event break end
        end
    end
    for _, event in ipairs(events) do self:Off(event, owner) end
    if unitFrames[owner] then
        for event in pairs(unitFrames[owner]) do self:Off(event, owner) end
    end
end

-- Unit events filtered by the engine (RegisterUnitEvent), e.g. UNIT_AURA for player only.
function Events:OnUnit(event, units, owner, fn)
    fn = fn or event
    unitFrames[owner] = unitFrames[owner] or {}
    local uf = unitFrames[owner][event]
    if not uf then
        uf = CreateFrame("Frame")
        unitFrames[owner][event] = uf
        uf:SetScript("OnEvent", function(_, ev, ...) Call(owner, fn, ev, ...) end)
    end
    uf:UnregisterAllEvents()
    uf:RegisterUnitEvent(event, unpack(units))
end

-- Internal message. Payload values must already be plain (not secret).
function Events:Fire(message, ...)
    assert(IsInternal(message), "internal messages start with OUI_")
    Dispatch(message, ...)
end

-- Runs fn once on the next frame no matter how often it is requested this frame.
-- For bursty events (UNIT_AURA, nameplates).
local pending = {}
function Events:Coalesce(key, fn)
    if pending[key] then return end
    pending[key] = true
    C_Timer.After(0, function()
        pending[key] = nil
        ns.SafeCall("Coalesce:" .. tostring(key), fn)
    end)
end
