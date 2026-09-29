-- Profiles page: both stores (switch, new, copy, rename, delete, reset, import, export)
-- and the backup list with one-click restore (CLAUDE.md §6.4, §10).
local _, ns = ...

local L = ns.L

local STORE_TEXT = {
    layout = { title = L["Layout profile"], desc = L["Look, positions and feature toggles."] },
    reminders = { title = L["Reminders profile"], desc = L["Encounter reminders and defensive choices. Kept separate so importing a new look never touches your reminders."] },
}

local function Combat()
    if InCombatLockdown() then ns.Print(L.COMBAT_REFUSED) return true end
    return false
end

local function Refresh() ns.Options:Refresh() end

local function FreeName(store, base)
    local name, n = base, 2
    while ns.Profiles:Exists(store, name) do
        name = base .. " (" .. n .. ")"
        n = n + 1
    end
    return name
end

local function Report(ok, err)
    if not ok then ns.Print(L["Couldn't do that:"] .. " " .. tostring(err)) end
    Refresh()
end

local function StoreSpecs(store)
    local P = ns.Profiles
    local function Others(filter)
        return function()
            local out = {}
            for _, name in ipairs(P:List(store)) do
                if name ~= P:ActiveName(store) and (not filter or filter(name)) then out[#out + 1] = name end
            end
            return out
        end
    end
    return {
        { type = "Header", label = STORE_TEXT[store].title },
        { type = "Description", label = STORE_TEXT[store].desc },
        { type = "Dropdown", label = L["Active profile (this character)"],
          values = function() return P:List(store) end,
          get = function() return P:ActiveName(store) end,
          set = function(name) if not Combat() then Report(P:Switch(store, name)) end end },
        { type = "ButtonBar", buttons = {
            { label = L["New"], func = function()
                ns.Dialog:Ask(L["Name for the new profile:"], FreeName(store, "New"), function(name)
                    local ok, err = P:New(store, name)
                    if ok and not Combat() then ok, err = P:Switch(store, name) end
                    Report(ok, err)
                end)
            end },
            { label = L["Rename"], disabled = function() return P:ActiveName(store) == "Default" end, func = function()
                local old = P:ActiveName(store)
                ns.Dialog:Ask(L["New name:"], old, function(name) Report(P:Rename(store, old, name)) end)
            end },
            { label = L["Reset"], func = function()
                ns.Dialog:Confirm(L["Reset this profile to defaults?"] .. "\n" .. L["A backup is made first."], function()
                    if not Combat() then Report(P:Reset(store)) end
                end)
            end },
            { label = L["Export"], func = function()
                local str, err = ns.ProfileIO:Export(store)
                if str then
                    ns.CopyBox:Show(L["Export"] .. ": " .. P:ActiveName(store), str)
                else
                    Report(false, err)
                end
            end },
            { label = L["Import"], func = function()
                ns.CopyBox:Prompt(L["Import"] .. " " .. STORE_TEXT[store].title, L["Paste a profile string. It is imported as a new profile and switched to; nothing is overwritten."], L["Import"], function(text)
                    local ok, cleanOrErr, report = ns.ProfileIO:Prepare(store, text)
                    if not ok then return false, cleanOrErr end
                    local name = FreeName(store, report.sourceName or "Imported")
                    local done, result = ns.ProfileIO:Import(store, text, name, { activate = true })
                    if not done then return false, result end
                    Refresh()
                    return true, ns.ProfileIO:DescribeReport(result)
                end)
            end },
        } },
        { type = "Dropdown", label = L["Copy settings from another profile into this one"],
          values = Others(), get = function() return L["Choose..."] end,
          set = function(from)
              ns.Dialog:Confirm(L["Replace this profile with a copy of"] .. " " .. from .. "?\n" .. L["A backup is made first."], function()
                  if not Combat() then Report(P:CopyFrom(store, from)) end
              end)
          end },
        { type = "Dropdown", label = L["Delete a profile"],
          values = Others(function(n) return n ~= "Default" end), get = function() return L["Choose..."] end,
          set = function(name)
              ns.Dialog:Confirm(L["Delete profile"] .. " " .. name .. "?\n" .. L["A backup is made first."], function()
                  Report(P:Delete(store, name))
              end)
          end },
    }
end

local function BackupSpecs()
    local specs = {
        { type = "Header", label = L["Backups"] },
        { type = "Description", label = L["Made automatically before imports, resets, copies and deletes. The newest are kept."] },
    }
    for i = 1, ns.MAX_BACKUPS do
        specs[#specs + 1] = {
            type = "ActionRow", buttonLabel = L["Restore"], empty = i == 1 and L["No backups yet."] or "",
            text = function()
                local b = ns.DB:Backups()[i]
                if not b then return nil end
                return ("%s  |cff999999%s|r  %s"):format(date("%Y-%m-%d %H:%M", b.time), b.store, b.reason)
            end,
            func = function()
                ns.Dialog:Confirm(L["Restore this backup? The current state is backed up first."], function()
                    if not Combat() then Report(ns.DB:RestoreBackup(i)) end
                end)
            end,
        }
    end
    return specs
end

ns.Options:RegisterPage("profiles", {
    category = "profiles", label = L["Profiles"], order = 1,
    build = function(_, addRows)
        local y = addRows({ { type = "Title", label = L["Profiles"],
            desc = L["Each character picks its own profiles. Share a setup by exporting a string and importing it elsewhere."] } }, 0)
        y = addRows(StoreSpecs("layout"), y)
        y = addRows(StoreSpecs("reminders"), y)
        return addRows(BackupSpecs(), y)
    end,
})
