-- Reminders module: settings for the defensive reminder engine (reminders profile) and
-- the binding lookup the scheduler uses. Bindings are per spec x encounter x mechanic
-- (CLAUDE.md §7.7):
--   db.bindings[specID][encounterID][mechanicId] = { mode = , defensives = { keys } }
--   mode: "auto" (default rule), "off", "warn" (warning only), "defensive" (warning + pick)
-- Default rule for "auto": tank-tagged mechanics get a defensive reminder when you play a
-- tank spec (setting tankAuto); everything else is off until you turn it on.
local _, ns = ...

local L = ns.L
local S = ns.Schema

local MODES = { "auto", "off", "warn", "defensive" }

local R = ns.Modules:New("Reminders", {
    category = "reminders", label = L["Defensive reminders"], order = 1,
    desc = L["Before a dangerous boss ability lands, OrionUI tells you which defensive to press: one that is ready and not already covered."],
    profileKey = "reminders",
    requires = { "BossModBridge" },
    schema = S.Table{ fields = {
        leadTime = S.Number{ default = 5, min = 1, max = 15, step = 0.5, label = L["Warn this many seconds before"], order = 1 },
        tankAuto = S.Bool{ default = true, label = L["Tank specs: remind about tank abilities automatically"], order = 2,
            desc = L["Abilities the Encounter Journal marks for tanks get a defensive reminder without setting each one up."] },
        onlyWhenTanking = S.Bool{ default = true, label = L["Only when I'm tanking that boss"], order = 3,
            desc = L["Uses the boss's threat. If the game hides it, you are warned anyway."] },
        skipCovered = S.Bool{ default = true, label = L["Skip when a defensive is already running"], order = 4 },
        retrigger = S.Number{ default = 6, min = 0, max = 20, step = 1, label = L["Ignore repeats within (seconds)"], order = 5 },
        sound = S.Bool{ default = true, label = L["Play a sound"], order = 10 },
        speech = S.Bool{ default = false, label = L["Speak the defensive's name"], order = 11 },
        iconSize = S.Number{ default = 56, min = 32, max = 96, step = 2, label = L["Icon size"], order = 20 },
        presets = S.Map{ hidden = true, of = S.List{ of = S.String{ default = "" }, max = 20 } },
        bindings = S.Map{ hidden = true, of = S.Map{ of = S.Map{ of = S.Table{ fields = {
            mode = S.Enum{ default = "auto", values = MODES },
            defensives = S.List{ of = S.String{ default = "" }, max = 20 },
        } } } } },
    } },
    options = function()
        return { { type = "Button", label = L["Test reminder"], style = "accent", func = function() ns.BossModBridge:Test() end } }
    end,
})
ns.Reminders = R
R.MODES = MODES

function R:Binding(encounterID, mechanicId, create)
    local specID = ns.Player.specID
    if not (specID and encounterID and mechanicId) then return nil end
    local b = self.db.bindings
    if not create then
        return b[specID] and b[specID][encounterID] and b[specID][encounterID][mechanicId]
    end
    b[specID] = b[specID] or {}
    b[specID][encounterID] = b[specID][encounterID] or {}
    b[specID][encounterID][mechanicId] = b[specID][encounterID][mechanicId] or { mode = "auto", defensives = {} }
    return b[specID][encounterID][mechanicId]
end

function R:SetMode(encounterID, mechanicId, mode)
    local b = self:Binding(encounterID, mechanicId, true)
    b.mode = mode
end

-- Effective mode for a mechanic: "off" | "warn" | "defensive", plus whether the tank
-- rule decided it (then ownership is checked).
function R:Mode(mechanic)
    if not mechanic then return "off" end
    if mechanic.testMode then return mechanic.testMode, false end -- /oui test reminder
    local b = self:Binding(mechanic.encounterID, mechanic.id)
    local mode = b and b.mode or "auto"
    if mode ~= "auto" then return mode, false end
    local tags = mechanic.tags or {}
    if self.db.tankAuto and ns.Player.role == "TANK" and (tags.tank or tags.buster) then
        return "defensive", true
    end
    return "off", false
end

function R:OnEnable()
    ns.ReminderOutput:Create()
    ns.Scheduler:Start()
end
function R:OnDisable() ns.Scheduler:Stop() end
function R:Refresh() if ns.ReminderOutput then ns.ReminderOutput:ApplySettings() end end
