-- OrionUI <-> RaidControl bridge. Loaded right after RaidControl's Core and Media.
--
-- RaidControl's own settings windows are not part of OrionUI (Stig, 2026-09-30). This stands in
-- for its "Settings" module, so every Settings button, right-click and /rc in RaidControl opens
-- OrionUI's options on the Raid tools pages instead.
local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled

local Settings = RC:NewModule("Settings")

-- Returns false so RaidControl's workspace doesn't show an empty settings page.
-- The workspace window sits above OrionUI's options (DIALOG vs HIGH strata), so it closes
-- first; from Raid Split the Raid split settings page opens.
function Settings:Open()
    local workspace = RC:GetModule("Workspace", true)
    local fromSplit = workspace and workspace.activeKey == "split"
    if workspace and workspace.host and workspace.host:IsShown() then workspace.host:Hide() end
    if ns.Options then ns.Options:Open(fromSplit and "RC_RaidSplit" or "RC_Launcher") end
    return false
end
function Settings:Toggle() return self:Open() end
function Settings:SelectTab() end
function Settings:CreateWindow() end

-- /oui edit also unlocks RaidControl's frames (launcher, action strip, battle res, healer mana,
-- tank assist, role marker button) through RaidControl's own layout mode, which saves their
-- positions in its own settings. Leaving edit mode locks and saves them again.
local EditLink = { name = "RaidControlEditLink" }
ns.Events:On("OUI_EDIT_MODE", EditLink, function(_, _, show)
    local layout = RC:GetModule("LayoutMode", true)
    if layout and layout.SetActive then layout:SetActive(show and true or false) end
end)
