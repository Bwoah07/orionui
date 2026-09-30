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
function Settings:Open()
    if ns.Options then ns.Options:Open("RC_Launcher") end
    return false
end
function Settings:Toggle() return self:Open() end
function Settings:SelectTab() end
function Settings:CreateWindow() end
