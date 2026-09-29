-- BossModBridge (CLAUDE.md §7.4): adapters for BigWigs and DBM feed it; it keeps the
-- active timers, dedupes, resolves mechanics, and emits one neutral event type so
-- nothing downstream knows which boss mod is installed.
--
--   MechanicEvent = { source, kind = "timer"|"message", id, key, text, icon, duration,
--                     expiresAt, approx, encounterID, mechanic (InternalMechanic) }
--
-- Messages: OUI_MECHANIC_TIMER(evt) for new and revised timers, OUI_MECHANIC_MESSAGE(evt),
-- OUI_MECHANIC_CANCEL(evt) for one timer or OUI_MECHANIC_CANCEL(nil) for all.
-- Everything reaching here is scrubbed: adapters drop secret values (CLAUDE.md §4.1).
local _, ns = ...

local L = ns.L
local S = ns.Schema

local Bridge = ns.Modules:New("BossModBridge", {
    category = "reminders", label = L["Boss mods"], order = 10,
    desc = L["Where encounter timers come from. OrionUI reads BigWigs or DBM; nothing downstream depends on which."],
    profileKey = "reminders",
    requires = { "EncounterManager" },
    schema = S.Table{ fields = {
        enabled = S.Bool{ default = true, hidden = true },
        source = S.Enum{ default = "auto", values = { "auto", "BigWigs", "DBM" }, label = L["Boss mod to follow"],
            valueLabels = { auto = L["Automatic (BigWigs first)"], BigWigs = "BigWigs", DBM = "Deadly Boss Mods" }, order = 1 },
        monitor = S.Bool{ default = false, label = L["Show encounter monitor"], order = 2,
            desc = L["A small list of the upcoming boss abilities as OrionUI sees them. Useful to check what reminders will react to."] },
    } },
})
ns.BossModBridge = Bridge

Bridge.adapters = {}  -- name -> { IsLoaded = fn, Register = fn }
Bridge.timers = {}    -- source:id -> MechanicEvent

local DEDUPE_WINDOW = 0.25 -- seconds; BigWigs sends StartBar and Timer for the same bar

function Bridge:RegisterAdapter(name, adapter)
    self.adapters[name] = adapter
end

-- The boss mod whose events we accept.
function Bridge:ActiveSource()
    local want = self.db and self.db.source or "auto"
    if want ~= "auto" then return want end
    for _, name in ipairs({ "BigWigs", "DBM" }) do
        local a = self.adapters[name]
        if a and a.IsLoaded() then return name end
    end
end

function Bridge:Accepts(source)
    -- "Test" is /oui test reminder: always accepted so the pipeline can be checked anywhere.
    return self.enabled and (source == "Test" or source == self:ActiveSource())
end

-- /oui test reminder: fake timers through the real pipeline (CLAUDE.md §6.9).
function Bridge:Test()
    local fake = {
        { id = "test-buster", text = ns.L["Test: tank buster"], duration = 8, icon = 136105,
          tags = { tank = true, buster = true }, testMode = "defensive" },
        { id = "test-raid", text = ns.L["Test: group damage"], duration = 12, icon = 135808,
          tags = { important = true }, testMode = "warn" },
    }
    for _, t in ipairs(fake) do
        -- Test mechanics are ad-hoc; tag them before the timer goes out so every consumer
        -- sees the tags, and say which reminder mode the test expects.
        local cur = ns.EncounterManager.current
        local m = ns.MechanicRegistry:Resolve("Test", t.id, cur and cur.encounterID, t.text)
        m.tags, m.testMode = t.tags, t.testMode
        self:Timer({ source = "Test", id = t.id, key = t.id, text = t.text, duration = t.duration, icon = t.icon })
    end
    ns.Events:Fire("OUI_MECHANIC_TEST")
end

local function EncounterID()
    local cur = ns.EncounterManager.current
    return cur and cur.encounterID
end

-- t: { source, id, key, text, icon, duration, approx, encounterID }
function Bridge:Timer(t)
    if not self:Accepts(t.source) or not t.id or not t.duration then return end
    if t.duration <= 0 then return self:Cancel(t.source, t.id) end -- negative/zero: timer is over
    local now = GetTime()
    local full = t.source .. ":" .. tostring(t.id)
    local expiresAt = now + t.duration
    local existing = self.timers[full]
    if not existing and not (t.key or t.text) then return end -- update for a timer we never saw
    if existing and existing.paused then existing.paused = nil end
    if existing and math.abs(existing.expiresAt - expiresAt) < DEDUPE_WINDOW then
        -- Same bar from a second message shape: keep the richer fields, no new event.
        existing.key = existing.key or t.key
        existing.icon = existing.icon or t.icon
        return
    end
    local encounterID = t.encounterID or EncounterID()
    local evt = existing or {}
    evt.source, evt.kind, evt.id, evt.full = t.source, "timer", t.id, full
    evt.key = t.key or evt.key
    evt.text, evt.icon, evt.approx = t.text or evt.text, t.icon or evt.icon, t.approx
    evt.duration, evt.expiresAt, evt.encounterID = t.duration, expiresAt, encounterID
    evt.mechanic = ns.MechanicRegistry:Resolve(t.source, evt.key, encounterID, evt.text)
    evt.revised = existing ~= nil
    self.timers[full] = evt
    ns.Events:Fire("OUI_MECHANIC_TIMER", evt)
end

function Bridge:Message(m)
    if not self:Accepts(m.source) then return end
    local encounterID = m.encounterID or EncounterID()
    ns.Events:Fire("OUI_MECHANIC_MESSAGE", {
        source = m.source, kind = "message", key = m.key, text = m.text, icon = m.icon,
        encounterID = encounterID, mechanic = ns.MechanicRegistry:Resolve(m.source, m.key, encounterID, m.text),
    })
end

-- A stop cancels the timer AND anything downstream queued for it (Kira left queued
-- announcements alive; CLAUDE.md §14.2).
function Bridge:Cancel(source, id)
    local full = source .. ":" .. tostring(id)
    local evt = self.timers[full]
    if not evt then return end
    self.timers[full] = nil
    ns.Events:Fire("OUI_MECHANIC_CANCEL", evt)
end

function Bridge:Pause(source, id)
    local evt = self.timers[source .. ":" .. tostring(id)]
    if evt and not evt.paused then
        evt.paused = math.max(0, evt.expiresAt - GetTime())
        ns.Events:Fire("OUI_MECHANIC_CANCEL", evt)
    end
end

function Bridge:Resume(source, id)
    local evt = self.timers[source .. ":" .. tostring(id)]
    if evt and evt.paused then
        local remaining = evt.paused
        evt.paused = nil
        evt.expiresAt = GetTime() + remaining
        evt.duration = remaining
        evt.revised = true
        ns.Events:Fire("OUI_MECHANIC_TIMER", evt)
    end
end

-- Clears every timer (from `source` only, if given).
function Bridge:CancelAll(source)
    local any = false
    for full, evt in pairs(self.timers) do
        if not source or evt.source == source then
            self.timers[full] = nil
            any = true
        end
    end
    if any or not source then ns.Events:Fire("OUI_MECHANIC_CANCEL", nil) end
end

-- Sorted list of live timers (for the monitor and tests).
function Bridge:Active()
    local list, now = {}, GetTime()
    for full, evt in pairs(self.timers) do
        if evt.paused or evt.expiresAt > now - 1 then
            list[#list + 1] = evt
        else
            self.timers[full] = nil -- expired a while ago
        end
    end
    table.sort(list, function(a, b) return (a.paused or a.expiresAt) < (b.paused or b.expiresAt) end)
    return list
end

function Bridge:RegisterAll()
    for name, a in pairs(self.adapters) do
        if a.IsLoaded() then ns.SafeCall("Adapter:" .. name, a.Register) end
    end
end

function Bridge:OnEnable()
    self:RegisterAll()
    -- Boss mods (or their cores) may load after us: retry on every ADDON_LOADED.
    ns.Events:On("ADDON_LOADED", self, function() self:RegisterAll() end)
    -- Blizzard's end event is authoritative even if a boss mod misses its own.
    ns.Events:On("OUI_ENCOUNTER_END", self, function() self:CancelAll() end)
    ns.Events:On("OUI_ENCOUNTER_START", self, function(_, _, info)
        ns.MechanicRegistry:LoadEncounter(info.encounterID)
    end)
    self:Refresh() -- creates the monitor frame so edit mode can place it
end

function Bridge:OnDisable()
    self:CancelAll()
end

function Bridge:Refresh()
    if ns.EncounterMonitor then ns.EncounterMonitor:Update() end
end
