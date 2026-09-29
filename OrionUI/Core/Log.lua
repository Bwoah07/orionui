-- Ring-buffer logger with per-module levels (CLAUDE.md §6.8). /oui log shows it in a
-- copyable window. In dev builds ERROR also goes to geterrorhandler() so BugSack sees it.
local _, ns = ...

local format, date, select, tostring = string.format, date, select, tostring

local LEVELS = { ERROR = 1, WARN = 2, INFO = 3, DEBUG = 4, TRACE = 5 }
local NAMES = { "ERROR", "WARN", "INFO", "DEBUG", "TRACE" }
local CAPACITY = 500

local Log = { LEVELS = LEVELS }
ns.Log = Log

local buffer, head, count = {}, 0, 0
local defaultLevel = LEVELS.INFO
local moduleLevels = {} -- tag -> level

function Log:SetLevel(tag, level)
    level = LEVELS[level and level:upper() or ""] or tonumber(level)
    if not level then return false end
    if tag == "all" then
        defaultLevel = level
        wipe(moduleLevels)
    else
        moduleLevels[tag] = level
    end
    return true
end

local function Write(level, tag, fmt, ...)
    if level > (moduleLevels[tag] or defaultLevel) then return end
    local ok, msg = true, fmt
    if select("#", ...) > 0 then ok, msg = pcall(format, fmt, ...) end
    if not ok then msg = tostring(fmt) .. " (bad log format: " .. tostring(msg) .. ")" end
    local line = format("%s %-5s [%s] %s", date("%H:%M:%S"), NAMES[level], tag or "?", msg)
    head = head % CAPACITY + 1
    buffer[head] = line
    if count < CAPACITY then count = count + 1 end
    if level == LEVELS.ERROR and ns.IS_DEV then
        geterrorhandler()(ns.NAME .. " [" .. tostring(tag) .. "] " .. msg)
    end
end

function Log:Error(tag, fmt, ...) Write(LEVELS.ERROR, tag, fmt, ...) end
function Log:Warn(tag, fmt, ...) Write(LEVELS.WARN, tag, fmt, ...) end
function Log:Info(tag, fmt, ...) Write(LEVELS.INFO, tag, fmt, ...) end
function Log:Debug(tag, fmt, ...) Write(LEVELS.DEBUG, tag, fmt, ...) end
function Log:Trace(tag, fmt, ...) Write(LEVELS.TRACE, tag, fmt, ...) end

-- Oldest first.
function Log:Lines()
    local out = {}
    local start = head - count
    for i = 1, count do
        out[i] = buffer[(start + i - 1) % CAPACITY + 1]
    end
    return out
end

function Log:Show()
    ns.CopyBox:Show(ns.NAME .. " log", table.concat(self:Lines(), "\n"))
end

-- User-facing message in chat, prefixed. Not a log entry.
function ns.Print(msg)
    print("|cff9d7bff" .. ns.NAME .. "|r " .. tostring(msg))
end
