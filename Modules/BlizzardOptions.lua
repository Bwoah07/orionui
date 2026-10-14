local addonName, ns = ...
local RC = ns.RC
local L = RC.L
local BlizzardOptions = RC:NewModule("BlizzardOptions")

-- =============================================================================
-- BLIZZARD SETTINGS + ADDON COMPARTMENT
-- RaidControl owns its settings window. The Settings > AddOns page is a
-- landing page that hands off to it, and the addon compartment entry (wired
-- through AddonCompartmentFunc in the TOC) opens the same window.
-- =============================================================================

local ICON_TEXTURE = "Interface\\AddOns\\RaidControl\\Media\\RaidControlIcon"
local BRAND_COLOR = "ffffc928"
local CATEGORY_NAME = "RaidControl"

local function GetAddonVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return getMetadata and getMetadata(addonName, "Version") or nil
end

local function CloseBlizzardSettings()
    if SettingsPanel and SettingsPanel:IsShown() then
        HideUIPanel(SettingsPanel)
    end
end

function BlizzardOptions:OpenSettings()
    local settings = RC:GetModule("Settings", true)
    if not settings or not settings.Open then
        return false
    end

    -- Close Blizzard's panel first so the RaidControl window is not left
    -- underneath it; Settings:Open queues itself until combat ends.
    CloseBlizzardSettings()
    return settings:Open()
end

function BlizzardOptions:CreateCanvas()
    local canvas = CreateFrame("Frame")
    canvas:Hide()

    local icon = canvas:CreateTexture(nil, "ARTWORK")
    icon:SetSize(56, 56)
    icon:SetPoint("TOPLEFT", 20, -20)
    icon:SetTexture(ICON_TEXTURE)

    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, -6)
    title:SetText(string.format("|c%sRaidControl|r", BRAND_COLOR))

    local version = canvas:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    local versionText = GetAddonVersion()
    version:SetText(versionText and string.format(L["Version %s"], versionText) or "")

    local description = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -20)
    description:SetPoint("RIGHT", canvas, "RIGHT", -20, 0)
    description:SetJustifyH("LEFT")
    description:SetSpacing(3)
    description:SetText(L["RaidControl keeps its options in its own window, with search, themes and layout tools that do not fit Blizzard's settings panel."])

    local openButton = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    openButton:SetSize(220, 28)
    openButton:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -18)
    openButton:SetText(L["Open RaidControl Settings"])
    openButton:SetScript("OnClick", function()
        BlizzardOptions:OpenSettings()
    end)

    local hint = canvas:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", openButton, "BOTTOMLEFT", 0, -10)
    hint:SetText(L["You can also type /rc or use the RaidControl entry in the addon compartment."])

    return canvas
end

function BlizzardOptions:RegisterCategory()
    if self.category or not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    self.canvas = self:CreateCanvas()
    self.category = Settings.RegisterCanvasLayoutCategory(self.canvas, CATEGORY_NAME)
    Settings.RegisterAddOnCategory(self.category)
end

function BlizzardOptions:OnInitialize()
    self:RegisterCategory()
end

-- =============================================================================
-- ADDON COMPARTMENT (globals named by the TOC's AddonCompartmentFunc* fields)
-- =============================================================================

function RaidControl_OnAddonCompartmentClick()
    BlizzardOptions:OpenSettings()
end

function RaidControl_OnAddonCompartmentEnter(_, menuButtonFrame)
    GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText(string.format("|c%sRaidControl|r", BRAND_COLOR))
    GameTooltip:AddLine(L["Click to open settings."], 1, 1, 1)
    GameTooltip:Show()
end

function RaidControl_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
