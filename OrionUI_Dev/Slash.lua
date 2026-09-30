-- /ouidev command router.
local _, ns = ...

local HELP = {
    "/ouidev secrets [all | spellID ...]  cooldown/charge secrecy for defensives",
    "/ouidev restrictions                 restriction states + C_Secrets predicates",
    "/ouidev cleu                         is the combat log restricted right now",
    "/ouidev auras [list | spellID ...]   own-buff readability (list = all buffs)",
    "/ouidev threat                       threat readability on boss1-5 and target",
    "/ouidev bossmod                      boss-mod listener status (events go to the log)",
    "/ouidev ej [id | mplus]              Encounter Journal dump (out of combat)",
    "/ouidev bone [sound]                 Bone Shield display options + find Boiling Point",
    "/ouidev casts                        90s log of your casts and proc glows (spell readable?)",
    "/ouidev cdm [name]                   what the Cooldown Manager can track for this spec",
    "/ouidev capture eui                  save your EllesmereUI profile for the installer (then /reload)",
    "/ouidev all                          secrets + restrictions + auras + threat in one box",
    "/ouidev watch on|off                 auto snapshots on combat/boss/M+ start (default on)",
    "/ouidev log [N]                      show the saved log (last N lines)",
    "/ouidev clear                        clear the saved log",
}

local COMMANDS = {
    secrets = function(a) ns.ProbeSecrets(a) end,
    restrictions = function(a) ns.ProbeRestrictions(a) end,
    cleu = function(a) ns.ProbeCLEU(a) end,
    auras = function(a) ns.ProbeAuras(a) end,
    threat = function(a) ns.ProbeThreat(a) end,
    bossmod = function(a) ns.ProbeBossMod(a) end,
    ej = function(a) ns.ProbeJournal(a) end,
    bone = function(a) ns.ProbeBone(a) end,
    casts = function(a) ns.ProbeCasts(a) end,
    cdm = function(a) ns.ProbeCDM(a) end,
    capture = function(a) ns.ProbeCapture(a) end,
    all = function()
        local lines, quiet = {}, { show = false }
        for _, probe in ipairs({ ns.ProbeRestrictions, ns.ProbeSecrets, ns.ProbeAuras, ns.ProbeThreat }) do
            for _, l in ipairs(probe(quiet) or {}) do lines[#lines + 1] = l end
        end
        ns.CopyWindow:Show(table.concat(lines, "\n"))
    end,
    watch = function(a)
        if a[1] == "on" then ns.SetWatch(true)
        elseif a[1] == "off" then ns.SetWatch(false)
        else ns.Chat("watch is " .. (ns.db.watch and "on" or "off")) end
    end,
    log = function(a) ns.Report:ShowLog(tonumber(a[1])) end,
    clear = function() ns.Report:ClearLog(); ns.Chat("log cleared") end,
}

SLASH_OUIDEV1 = "/ouidev"
SlashCmdList.OUIDEV = function(msg)
    local args = {}
    for word in (msg or ""):gmatch("%S+") do args[#args + 1] = word end
    local cmd = table.remove(args, 1)
    cmd = cmd and cmd:lower()
    local fn = cmd and COMMANDS[cmd]
    if not fn then
        for _, line in ipairs(HELP) do ns.Chat(line) end
        return
    end
    if not ns.db then ns.Chat("not ready yet") return end
    local ok, err = pcall(fn, args)
    if not ok then
        -- Never silent: report in chat and hand to BugSack.
        ns.Chat("|cffff5555error|r in " .. cmd .. ": " .. tostring(err))
        geterrorhandler()(err)
    end
end
