-- Custom reminders (CLAUDE.md §7.10): user-written warnings per boss, shown through the
-- same on-screen output as defensive reminders.
--
--   list[encounterID or 0] = { { enabled, name, trigger, match, offset, text, sound,
--                                speech, role, show } }
--   trigger "timer"   fires `offset` seconds before a boss-mod timer ends
--           "message" fires when the boss mod announces it
--           "pull"    fires `offset` seconds after the pull
--   match   the boss-mod key (usually the ability's spell ID) or part of the bar/message
--           text; empty matches nothing (except for "pull")
--   role    "any" | "TANK" | "HEALER" | "DAMAGER"
-- Encounter 0 holds reminders for every boss. Lives in the reminders profile, so it is
-- exported/imported with it; single reminders also export as !OUI:C:1! strings.
local _, ns = ...

local L = ns.L
local S = ns.Schema

local TRIGGERS = { "timer", "message", "pull" }
local ROLES = { "any", "TANK", "HEALER", "DAMAGER" }

local ReminderSchema = S.Table{ fields = {
    enabled = S.Bool{ default = true },
    name = S.String{ default = "", maxLen = 60 },
    trigger = S.Enum{ default = "timer", values = TRIGGERS },
    match = S.String{ default = "", maxLen = 80 },
    offset = S.Number{ default = 5, min = 0, max = 600, step = 0.5 },
    text = S.String{ default = "", maxLen = 120 },
    sound = S.Bool{ default = true },
    speech = S.Bool{ default = false },
    show = S.Number{ default = 4, min = 1, max = 30, step = 0.5 }, -- seconds on screen (message/pull)
    role = S.Enum{ default = "any", values = ROLES },
} }

local C = ns.Modules:New("CustomReminders", {
    category = "reminders", label = L["Custom reminders"], order = 4,
    profileKey = "reminders",
    hideInOptions = true, -- edited on the Custom reminders page
    requires = { "Reminders" },
    schema = S.Table{ fields = {
        enabled = S.Bool{ default = true, hidden = true },
        list = S.Map{ hidden = true, of = S.List{ of = ReminderSchema, max = 100 } },
    } },
})
ns.CustomReminders = C
C.TRIGGERS, C.ROLES, C.Schema = TRIGGERS, ROLES, ReminderSchema

local pending = {} -- id -> C_Timer handle

function C:For(encounterID)
    local out = {}
    for _, key in ipairs({ encounterID or 0, 0 }) do
        for i, r in ipairs(self.db.list[key] or {}) do out[#out + 1] = { r = r, key = key, index = i } end
        if key == 0 then break end
    end
    return out
end

function C:New(encounterID)
    local key = encounterID or 0
    self.db.list[key] = self.db.list[key] or {}
    local r = S.Default(ReminderSchema)
    r.name = L["New reminder"]
    table.insert(self.db.list[key], r)
    return r, #self.db.list[key]
end

function C:Delete(encounterID, index)
    local list = self.db.list[encounterID or 0]
    if list then table.remove(list, index) end
end

---------------------------------------------------------------------------
-- Matching and firing
---------------------------------------------------------------------------

local function RoleOK(r)
    return r.role == "any" or r.role == ns.Player.role
end

-- Key match is exact (spell IDs compare as text); text match is "contains", case-insensitive.
local function Matches(r, evt)
    local m = r.match
    if m == "" then return false end
    if evt.key ~= nil and tostring(evt.key) == m then return true end
    local text = evt.text or (evt.mechanic and evt.mechanic.title)
    return type(text) == "string" and text:lower():find(m:lower(), 1, true) ~= nil
end

local function Show(r, id, expiresAt, noTime, icon)
    ns.Scheduler:Show({
        id = id, mode = "custom", text = r.text ~= "" and r.text or r.name, icon = icon,
        expiresAt = expiresAt, noTime = noTime, sound = r.sound, speech = r.speech,
    }, noTime and r.show or math.max(0.5, expiresAt - GetTime() + 1))
end

local function Cancel(id)
    if pending[id] then pending[id]:Cancel() pending[id] = nil end
    ns.Scheduler:HideReminder(id)
end

local function Schedule(id, delay, fn)
    Cancel(id)
    if delay <= 0 then return fn() end
    pending[id] = C_Timer.NewTimer(delay, function()
        pending[id] = nil
        ns.SafeCall("CustomReminders", fn)
    end)
end

local function EachActive(encounterID, trigger, fn)
    for _, e in ipairs(C:For(encounterID)) do
        local r = e.r
        if r.enabled and r.trigger == trigger and RoleOK(r) then fn(r, e) end
    end
end

local function OnTimer(_, _, evt)
    EachActive(evt.encounterID, "timer", function(r, e)
        if not Matches(r, evt) then return end
        local id = ("custom:%d:%d:%s"):format(e.key, e.index, evt.full)
        Schedule(id, evt.expiresAt - r.offset - GetTime(), function()
            Show(r, id, evt.expiresAt, false, evt.icon)
        end)
    end)
end

local function OnMessage(_, _, evt)
    EachActive(evt.encounterID, "message", function(r, e)
        if not Matches(r, evt) then return end
        local id = ("custom:%d:%d:msg"):format(e.key, e.index)
        Show(r, id, GetTime() + r.show, true, evt.icon)
    end)
end

local function OnCancel(_, _, evt)
    local suffix = evt and (":" .. evt.full) or nil
    for id in pairs(pending) do
        if not suffix or id:sub(-#suffix) == suffix then Cancel(id) end
    end
end

local function OnPull(_, _, info)
    EachActive(info.encounterID, "pull", function(r, e)
        local id = ("custom:%d:%d:pull"):format(e.key, e.index)
        Schedule(id, r.offset, function() Show(r, id, GetTime() + r.show, true) end)
    end)
end

local function OnEnd()
    for id in pairs(pending) do Cancel(id) end
end

-- Fires one reminder now, as if its trigger happened (editor "Test" button).
function C:Test(r)
    local id = "custom:test"
    if r.trigger == "timer" then
        Show(r, id, GetTime() + r.offset, false)
    else
        Show(r, id, GetTime() + r.show, true)
    end
end

-- Single reminder as a shareable string (!OUI:C:1!).
function C:Export(r)
    return ns.Serialize:Encode("C", { type = "custom", reminder = ns.Util.DeepCopy(r) })
end

function C:Import(str, encounterID)
    local ok, kind, payload = ns.Serialize:Decode(str)
    if not ok then return false, kind end
    if kind ~= "C" or type(payload.reminder) ~= "table" then return false, L["Not a reminder string."] end
    local report = S.NewReport()
    local r = S.Validate(ReminderSchema, payload.reminder, "reminder", report)
    local key = encounterID or 0
    self.db.list[key] = self.db.list[key] or {}
    table.insert(self.db.list[key], r)
    return true, r
end

function C:OnEnable()
    ns.Events:On("OUI_MECHANIC_TIMER", self, OnTimer)
    ns.Events:On("OUI_MECHANIC_MESSAGE", self, OnMessage)
    ns.Events:On("OUI_MECHANIC_CANCEL", self, OnCancel)
    ns.Events:On("OUI_ENCOUNTER_START", self, OnPull)
    ns.Events:On("OUI_ENCOUNTER_END", self, OnEnd)
end

function C:OnDisable() OnEnd() end
