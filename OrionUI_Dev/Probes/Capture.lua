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
    local ok, str = ns.Try(EUI.ExportProfile, key, folder and { [folder] = true } or nil)
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

-- /ouidev install eui: imports a locally saved EUI preset (OrionUI_Dev/Private/Presets.lua,
-- gitignored) through EUI's partner-installer API, the same path OrionUI_Installer will use:
-- EllesmereUI.ImportProfileSilent{ importString, profileName, cleanSlate, applyUIScale }.
-- It never reloads by itself, so we reload right after it succeeds. Nothing is shipped from here.
local function InstallEUI()
    local preset = ns.PrivatePresets and ns.PrivatePresets.eui
    if not preset then ns.Chat("No local EUI preset (OrionUI_Dev/Private/Presets.lua is missing).") return end
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.ImportProfileSilent) then
        ns.Chat("EllesmereUI isn't loaded, or this EUI version has no ImportProfileSilent.")
        return
    end
    if InCombatLockdown() then ns.Chat("Leave combat first.") return end
    local ok, res, err = ns.Try(EUI.ImportProfileSilent, {
        importString = preset.string,
        profileName = preset.name,
        cleanSlate = true,     -- replaces only a profile with this same name
        applyUIScale = true,   -- use the capture's UI scale
    })
    if not ok then ns.Chat("EUI import errored: " .. tostring(res)) return end
    if not res then ns.Chat("EUI refused the import: " .. tostring(err)) return end
    ns.Chat(("Imported EUI profile '%s' (%s). Reloading..."):format(preset.name, preset.note or ""))
    ReloadUI()
end

function ns.ProbeInstall(args)
    if args[1] == "eui" then InstallEUI() return end
    ns.Chat("/ouidev install eui")
end
