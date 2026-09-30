-- /ouidev capture eui: saves Stig's current EllesmereUI profile as an export string into
-- OrionUIDevDB.captures, so after a /reload it can be read from the SavedVariables file and
-- turned into an installer preset (CLAUDE.md §12). No copy-pasting of huge strings.
--
-- EllesmereUI.ExportProfile(name) called bare is EUI's documented "headless full" export for
-- partner installers: layout, CDM spell layouts for every spec, globals and overrides included
-- (EllesmereUI_Profiles.lua, checked 2026-09-30). Read-only: nothing in EUI is changed.
--
-- /ouidev capture eui <module> (e.g. nameplates, actionbars, unitframes) saves only that
-- module, via ExportProfile's includedFolders set, into OrionUIDevDB.captures.euiModules.
-- EUI stamps such strings partialImport, so the installer can apply the pieces one by one.
-- A module capture leaves out fonts/colours, overrides, window skins and (unless it is the
-- CDM itself) CDM spell layouts, so layering it on another profile changes only that module.
local _, ns = ...

-- "nameplates" -> "EllesmereUINameplates" when that addon exists (case-insensitive).
local function ModuleFolder(name)
    for i = 1, C_AddOns.GetNumAddOns() do
        local folder = C_AddOns.GetAddOnInfo(i)
        if folder and folder:lower() == ("EllesmereUI" .. name):lower() then return folder end
    end
end

local function CaptureEUI(module)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.ExportProfile and EUI.GetCurrentProfileKey) then
        ns.Chat("EllesmereUI isn't loaded (or has no export API).")
        return
    end
    if InCombatLockdown() then ns.Chat("Leave combat first.") return end
    local okKey, key = ns.Try(EUI.GetCurrentProfileKey)
    if not okKey or type(key) ~= "string" then ns.Chat("Couldn't read the active EUI profile: " .. tostring(key)) return end
    local folder
    if module then
        folder = ModuleFolder(module)
        if not folder then ns.Chat("No EUI module called '" .. module .. "' (try nameplates, actionbars, unitframes, cooldownmanager).") return end
    end
    local ok, str
    if folder then
        -- ExportProfile(name, includedFolders, includeLayout, includeCDM, cdmSpecs,
        --               includeGlobals, includeOverrides, includeBlizzSkin)
        ok, str = ns.Try(EUI.ExportProfile, key, { [folder] = true }, true,
            folder == "EllesmereUICooldownManager", nil, false, false, false)
    else
        ok, str = ns.Try(EUI.ExportProfile, key)
    end
    if not ok or type(str) ~= "string" or str == "" then
        ns.Chat("EUI export failed: " .. tostring(str))
        return
    end
    local w, h = GetPhysicalScreenSize()
    ns.db.captures = ns.db.captures or {}
    local entry = {
        profile = key,
        string = str,
        euiVersion = C_AddOns.GetAddOnMetadata("EllesmereUI", "Version"),
        screen = ("%dx%d"):format(w, h),
        uiScale = UIParent:GetScale(),
        date = date("%Y-%m-%d %H:%M"),
    }
    if folder then
        ns.db.captures.euiModules = ns.db.captures.euiModules or {}
        ns.db.captures.euiModules[folder] = entry
    else
        ns.db.captures.eui = entry
    end
    ns.Chat(("Saved %s from EUI profile '%s' (%d characters, screen %dx%d). Now /reload so it's written to disk.")
        :format(folder or "the whole profile", key, #str, w, h))
end

function ns.ProbeCapture(args)
    if args[1] == "eui" then CaptureEUI(args[2]) return end
    ns.Chat("/ouidev capture eui [module]")
end

-- /ouidev install eui [set]: imports a locally saved EUI preset set (OrionUI_Dev/Private/Presets.lua,
-- gitignored) through EUI's partner-installer API, the same path OrionUI_Installer will use:
-- EllesmereUI.ImportProfileSilent{ importString, profileName, cleanSlate, applyUIScale }.
-- It never reloads by itself, so we reload right after it succeeds. Nothing is shipped from here.
--
-- A set is a base profile plus module layers (e.g. only the minimap from another profile).
-- EUI merges an import onto the ACTIVE profile, and the base import only becomes active
-- after its reload. So the layers are applied on the next login (pending flag), onto the
-- base profile, with cleanSlate = false and the user's UI scale kept.
local function Sets() return ns.PrivatePresets and ns.PrivatePresets.euiSets or {} end

local function FindSet(key)
    for _, set in ipairs(Sets()) do
        if set.key == key then return set end
    end
end

-- Every saved module capture, by short name: "unitframes" -> { folder, string }.
local function Modules()
    local out = {}
    for _, set in ipairs(Sets()) do
        for _, layer in ipairs(set.layers or {}) do
            out[layer.folder:gsub("^EllesmereUI", ""):lower()] = layer
        end
    end
    return out
end

local function ListSets()
    if #Sets() == 0 then ns.Chat("No local EUI presets (OrionUI_Dev/Private/Presets.lua is missing).") return end
    ns.Chat("Whole profiles, /ouidev install eui <name>:")
    for _, set in ipairs(Sets()) do ns.Chat(("  %s: %s"):format(set.key, set.note or "")) end
    local names = {}
    for name in pairs(Modules()) do names[#names + 1] = name end
    table.sort(names)
    ns.Chat("Single modules onto your current EUI profile: " .. table.concat(names, ", "))
end

-- One module capture onto the active EUI profile; nothing else in the profile changes.
local function InstallModule(layer)
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.ImportProfileSilent and EUI.GetCurrentProfileKey) then
        ns.Chat("EllesmereUI isn't loaded, or this EUI version has no ImportProfileSilent.")
        return
    end
    if InCombatLockdown() then ns.Chat("Leave combat first.") return end
    local profile = EUI.GetCurrentProfileKey()
    local ok, res, err = ns.Try(EUI.ImportProfileSilent, {
        importString = layer.string, profileName = profile, cleanSlate = false, applyUIScale = false,
    })
    if not ok then ns.Chat("EUI import errored: " .. tostring(res)) return end
    if not res then ns.Chat("EUI refused the import: " .. tostring(err)) return end
    ns.Chat(("Added %s to EUI profile '%s'. Reloading..."):format(layer.folder, profile))
    ReloadUI()
end

local function InstallEUI(key)
    local set = key and FindSet(key)
    if not set then
        local layer = key and Modules()[key]
        if layer then InstallModule(layer) else ListSets() end
        return
    end
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.ImportProfileSilent) then
        ns.Chat("EllesmereUI isn't loaded, or this EUI version has no ImportProfileSilent.")
        return
    end
    if InCombatLockdown() then ns.Chat("Leave combat first.") return end
    local ok, res, err = ns.Try(EUI.ImportProfileSilent, {
        importString = set.string,
        profileName = set.name,
        cleanSlate = true,     -- replaces only a profile with this same name
        applyUIScale = true,   -- use the capture's UI scale
    })
    if not ok then ns.Chat("EUI import errored: " .. tostring(res)) return end
    if not res then ns.Chat("EUI refused the import: " .. tostring(err)) return end
    ns.db.pendingEUILayers = (set.layers and #set.layers > 0) and set.key or nil
    ns.Chat(("Imported EUI preset '%s' as profile '%s'. Reloading..."):format(set.key, set.name))
    ReloadUI()
end

local function ApplyPendingLayers()
    local key = ns.db and ns.db.pendingEUILayers
    if not key then return end
    ns.db.pendingEUILayers = nil -- one attempt only, never a reload loop
    local set = FindSet(key)
    if not set then return end
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.ImportProfileSilent and EUI.GetCurrentProfileKey) then ns.Chat("EUI missing, module layers skipped.") return end
    if EUI.GetCurrentProfileKey() ~= set.name then
        ns.Chat(("Active EUI profile isn't '%s', module layers skipped."):format(set.name))
        return
    end
    local applied = 0
    for _, layer in ipairs(set.layers) do
        local ok, res, err = ns.Try(EUI.ImportProfileSilent, {
            importString = layer.string, profileName = set.name, cleanSlate = false, applyUIScale = false,
        })
        if ok and res then
            applied = applied + 1
            ns.Chat("Layered " .. layer.folder .. " onto " .. set.name .. ".")
        else
            ns.Chat("|cffff5555Layer failed|r " .. tostring(layer.folder) .. ": " .. tostring(ok and err or res))
        end
    end
    if applied > 0 then ns.Chat("Type /reload to see the layered modules.") end
end
ns.On("PLAYER_LOGIN", function() ApplyPendingLayers() end)

function ns.ProbeInstall(args)
    if args[1] == "eui" then InstallEUI(args[2] and args[2]:lower()) return end
    ns.Chat("/ouidev install eui [preset]")
end
