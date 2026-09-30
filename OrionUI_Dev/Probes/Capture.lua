-- /ouidev capture eui: saves Stig's current EllesmereUI profile as an export string into
-- OrionUIDevDB.captures, so after a /reload it can be read from the SavedVariables file and
-- turned into an installer preset (CLAUDE.md §12). No copy-pasting of huge strings.
--
-- EllesmereUI.ExportProfile(name) called bare is EUI's documented "headless full" export for
-- partner installers: layout, CDM spell layouts for every spec, globals and overrides included
-- (EllesmereUI_Profiles.lua, checked 2026-09-30). Read-only: nothing in EUI is changed.
local _, ns = ...

local function CaptureEUI()
    local EUI = _G.EllesmereUI
    if not (EUI and EUI.ExportProfile and EUI.GetCurrentProfileKey) then
        ns.Chat("EllesmereUI isn't loaded (or has no export API).")
        return
    end
    if InCombatLockdown() then ns.Chat("Leave combat first.") return end
    local okKey, key = ns.Try(EUI.GetCurrentProfileKey)
    if not okKey or type(key) ~= "string" then ns.Chat("Couldn't read the active EUI profile: " .. tostring(key)) return end
    local ok, str = ns.Try(EUI.ExportProfile, key)
    if not ok or type(str) ~= "string" or str == "" then
        ns.Chat("EUI export failed: " .. tostring(str))
        return
    end
    local w, h = GetPhysicalScreenSize()
    ns.db.captures = ns.db.captures or {}
    ns.db.captures.eui = {
        profile = key,
        string = str,
        euiVersion = C_AddOns.GetAddOnMetadata("EllesmereUI", "Version"),
        screen = ("%dx%d"):format(w, h),
        uiScale = UIParent:GetScale(),
        date = date("%Y-%m-%d %H:%M"),
    }
    ns.Chat(("Saved EUI profile '%s' (%d characters, screen %dx%d). Now /reload so it's written to disk."):format(key, #str, w, h))
end

function ns.ProbeCapture(args)
    if args[1] == "eui" then CaptureEUI() return end
    ns.Chat("/ouidev capture eui")
end
