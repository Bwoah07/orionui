-- DBM adapter -> BossModBridge. Callback payloads verified against DBM-Core source
-- (modules/objects/Timer.lua, Announce.lua, CombatDetection.lua; cloned 2026-09-29):
--   DBM_TimerBegin(id, msg, timer, icon, simpType, spellId, colorId, modId, keep, fade,
--                  name, guid, timerCount, isPriority, type, hasVariance, maxTimer, ...)
--   DBM_TimerUpdate(id, elapsed, total)   DBM_TimerStop(id[, guid])
--   DBM_TimerPause(id) / DBM_TimerResume(id)
--   DBM_Announce(message, icon, type, spellId, modId, isSpecial, count)
--   DBM_Pull(mod, delay, synced, startHp)  DBM_Kill(mod)  DBM_Wipe(mod)
-- Not yet tested in game (Stig uses BigWigs); DBM is best effort for now (CLAUDE.md §19.7).
local _, ns = ...

local SOURCE = "DBM"
local Plain = ns.Secret.Plain
local registered = false

local function Bridge() return ns.BossModBridge end

-- DBM's own utility timers (pull, break, LFG, respawn, pizza) are not mechanics.
local IGNORE_TYPES = { extratimer = true, pizzatimer = true, breaktimer = true, pulltimer = true }

local function Key(v)
    v = Plain(v)
    local t = type(v)
    if t == "number" or t == "string" then return v end
end

local handlers = {
    DBM_TimerBegin = function(_, id, msg, timer, icon, simpType, spellId, _, modId)
        id, msg, timer = Plain(id), Plain(msg), Plain(timer)
        if type(id) ~= "string" or type(timer) ~= "number" then return end
        if IGNORE_TYPES[Plain(simpType)] or not Key(modId) then return end
        Bridge():Timer({
            source = SOURCE, id = id, key = Key(spellId), text = type(msg) == "string" and msg or nil,
            icon = Plain(icon), duration = timer,
        })
    end,
    DBM_TimerUpdate = function(_, id, elapsed, total)
        id, elapsed, total = Plain(id), Plain(elapsed), Plain(total)
        if type(id) ~= "string" or type(elapsed) ~= "number" or type(total) ~= "number" then return end
        Bridge():Timer({ source = SOURCE, id = id, duration = total - elapsed })
    end,
    DBM_TimerStop = function(_, id)
        id = Plain(id)
        if type(id) == "string" then Bridge():Cancel(SOURCE, id) end
    end,
    DBM_TimerPause = function(_, id)
        id = Plain(id)
        if type(id) == "string" then Bridge():Pause(SOURCE, id) end
    end,
    DBM_TimerResume = function(_, id)
        id = Plain(id)
        if type(id) == "string" then Bridge():Resume(SOURCE, id) end
    end,
    DBM_Announce = function(_, message, icon, _, spellId, modId)
        message = Plain(message)
        if type(message) ~= "string" or not Key(modId) then return end
        Bridge():Message({ source = SOURCE, key = Key(spellId), text = message, icon = Plain(icon) })
    end,
    DBM_Kill = function() Bridge():CancelAll(SOURCE) end,
    DBM_Wipe = function() Bridge():CancelAll(SOURCE) end,
}

ns.BossModBridge:RegisterAdapter(SOURCE, {
    IsLoaded = function() return DBM ~= nil and DBM.RegisterCallback ~= nil end,
    Register = function()
        if registered then return end
        for event, fn in pairs(handlers) do
            DBM:RegisterCallback(event, function(...)
                ns.SafeCall("DBM:" .. event, fn, ...)
            end)
        end
        registered = true
        ns.Log:Info("DBM", "listening to DBM")
    end,
})
