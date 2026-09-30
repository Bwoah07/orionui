-- Scheduler (CLAUDE.md §7.9): MechanicEvents -> Reminders at the right moment.
--
--   Reminder = { id, mechanic, text, icon, expiresAt, defensive, maybe, covered, mode }
--
-- * Fires at expiresAt - leadTime (immediately if that moment already passed).
-- * Timer revisions reschedule the pending reminder instead of stacking a second one.
-- * The retrigger guard is checked when a reminder FIRES, after any revision (Kira applied
--   it first and blocked corrections).
-- * A cancelled timer removes its pending and visible reminder (Kira left them alive).
-- One C_Timer per pending reminder; nothing runs while nothing is pending.
local _, ns = ...

local Scheduler = { pending = {}, visible = {}, lastFired = {} }
ns.Scheduler = Scheduler

local HIDE_AFTER = 1 -- seconds after the hit

local function Hide(full)
    local r = Scheduler.visible[full]
    if not r then return end
    Scheduler.visible[full] = nil
    if r.hideTimer then r.hideTimer:Cancel() end
    ns.Events:Fire("OUI_REMINDER_HIDE", r)
end

local function Unschedule(full)
    local p = Scheduler.pending[full]
    if p then
        p.timer:Cancel()
        Scheduler.pending[full] = nil
    end
end

local function Fire(evt, mode, byTankRule)
    local R, mechanic = ns.Reminders, evt.mechanic
    local now = GetTime()
    local last = Scheduler.lastFired[mechanic.id]
    if last and now - last < R.db.retrigger and evt.source ~= "Test" then
        ns.Log:Debug("Scheduler", "%s: repeat within %ds, skipped", mechanic.id, R.db.retrigger)
        return
    end
    local tankRelated = byTankRule or (mechanic.tags and (mechanic.tags.tank or mechanic.tags.buster))
    if R.db.onlyWhenTanking and tankRelated and evt.source ~= "Test" then
        local react, why = ns.TankOwnership:ShouldReact(mechanic.ownerUnit)
        if not react then
            ns.Log:Debug("Scheduler", "%s ignored: %s", mechanic.id, why)
            return
        end
    end
    Scheduler.lastFired[mechanic.id] = now

    local reminder = {
        id = evt.full, mechanic = mechanic, mode = mode,
        text = mechanic.title or evt.text, icon = evt.icon or mechanic.icon, expiresAt = evt.expiresAt,
    }
    if mode == "defensive" then
        local res = ns.DefensiveResolver:Resolve(mechanic, ns.Reminders:Binding(mechanic.encounterID, mechanic.id))
        reminder.defensive, reminder.maybe, reminder.covered = res.pick, res.maybe, res.covered
        ns.Log:Debug("Resolver", "%s: %s", mechanic.id, table.concat(res.reasons, "; "))
    end
    Hide(evt.full)
    Scheduler.visible[evt.full] = reminder
    reminder.hideTimer = C_Timer.NewTimer(math.max(0.5, evt.expiresAt - now + HIDE_AFTER), function() Hide(evt.full) end)
    ns.Events:Fire("OUI_REMINDER_SHOW", reminder)
end

local function OnTimer(_, _, evt)
    local mode, byTankRule = ns.Reminders:Mode(evt.mechanic)
    Unschedule(evt.full)
    if mode == "off" then return end
    local fireIn = evt.expiresAt - ns.Reminders.db.leadTime - GetTime()
    if evt.expiresAt - GetTime() < 0.5 then return end -- too late to be useful
    if Scheduler.visible[evt.full] then
        -- Already showing: a revision just moves the countdown.
        Scheduler.visible[evt.full].expiresAt = evt.expiresAt
        ns.Events:Fire("OUI_REMINDER_SHOW", Scheduler.visible[evt.full])
        return
    end
    if fireIn <= 0 then
        Fire(evt, mode, byTankRule)
    else
        Scheduler.pending[evt.full] = {
            evt = evt,
            timer = C_Timer.NewTimer(fireIn, function()
                Scheduler.pending[evt.full] = nil
                ns.SafeCall("Scheduler", Fire, evt, mode, byTankRule)
            end),
        }
    end
end

local function OnCancel(_, _, evt)
    if evt then
        Unschedule(evt.full)
        Hide(evt.full)
        return
    end
    for full in pairs(Scheduler.pending) do Unschedule(full) end
    for full in pairs(Scheduler.visible) do Hide(full) end
end

function Scheduler:Start()
    ns.Events:On("OUI_MECHANIC_TIMER", self, OnTimer)
    ns.Events:On("OUI_MECHANIC_CANCEL", self, OnCancel)
    ns.Events:On("OUI_ENCOUNTER_END", self, function() wipe(self.lastFired) end)
end

function Scheduler:Stop()
    ns.Events:OffAll(self)
    OnCancel(nil, nil, nil)
end

-- Shows a ready-made reminder (custom reminders use this) through the same output.
-- r = { id, text, icon, expiresAt, mode = "custom", sound = bool, speech = bool }
function Scheduler:Show(r, hideAfter)
    Hide(r.id)
    self.visible[r.id] = r
    r.hideTimer = C_Timer.NewTimer(hideAfter, function() Hide(r.id) end)
    ns.Events:Fire("OUI_REMINDER_SHOW", r)
end

function Scheduler:HideReminder(id) Hide(id) end

-- Visible reminders, soonest first (for the output).
function Scheduler:Visible()
    local list = {}
    for _, r in pairs(self.visible) do list[#list + 1] = r end
    table.sort(list, function(a, b) return a.expiresAt < b.expiresAt end)
    return list
end

Scheduler.name = "Scheduler"
