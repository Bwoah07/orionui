-- /oui command registry (CLAUDE.md §6.9). Modules add subcommands with
-- ns.Slash:Register("name", fn, "help text"); fn receives the remaining words.
local _, ns = ...

local Slash = { commands = {}, order = {} }
ns.Slash = Slash

function Slash:Register(name, fn, help)
    if not self.commands[name] then self.order[#self.order + 1] = name end
    self.commands[name] = { fn = fn, help = help }
end

function Slash:Help()
    ns.Print(ns.L["Commands:"])
    for _, name in ipairs(self.order) do
        local c = self.commands[name]
        print("  /oui " .. name .. (c.help and ("  " .. c.help) or ""))
    end
end

function Slash:Run(msg)
    local args = ns.Util.Split(msg or "")
    local name = table.remove(args, 1)
    if not name then
        ns.Options:Open()
        return
    end
    local c = self.commands[name:lower()]
    if not c then return self:Help() end
    ns.SafeCall("Slash:" .. name, c.fn, args)
end

SLASH_ORIONUI1 = "/oui"
SlashCmdList.ORIONUI = function(msg) Slash:Run(msg) end

---------------------------------------------------------------------------
-- Core commands
---------------------------------------------------------------------------

Slash:Register("help", function() Slash:Help() end)

Slash:Register("log", function() ns.Log:Show() end, "show the log")

Slash:Register("debug", function(args)
    local tag, level = args[1], args[2]
    if not (tag and level) or not ns.Log:SetLevel(tag, level) then
        ns.Print("/oui debug <module|all> <error|warn|info|debug|trace>")
        return
    end
    ns.Print(("log level for %s set to %s"):format(tag, level))
end, "<module|all> <level>")

Slash:Register("edit", function() ns.EditMode:Toggle() end, "move frames")

Slash:Register("profile", function(args)
    local store, name = args[1], table.concat(args, " ", 2)
    if (store ~= "layout" and store ~= "reminders") or name == "" then
        ns.Print("/oui profile <layout|reminders> <name>")
        return
    end
    local ok, err = OrionUIAPI.SetProfile(store, name)
    ns.Print(ok and ("switched %s profile to %s"):format(store, name) or ("can't switch: " .. tostring(err)))
end, "<layout|reminders> <name>")

Slash:Register("reset", function(args)
    local M = args[1] and ns.Modules:Get(args[1])
    if not M then
        ns.Print("/oui reset <module>. Modules: " .. table.concat(ns.Util.SortedKeys(ns.Modules.byName), ", "))
        return
    end
    if InCombatLockdown() then ns.Print(ns.L.COMBAT_REFUSED) return end
    M:ResetSettings()
    ns.Print(M.label .. " reset (a backup was made)")
end, "<module>")
