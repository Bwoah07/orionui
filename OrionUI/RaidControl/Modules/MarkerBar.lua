local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
local Markers = RC:NewModule("Markers")

function Markers:OnInitialize()
    -- Initialize the Markers module
end

function Markers:OnEnable()
    self:CreateMarkerBar()
    -- Register with menu system
    RC:RegisterMenuModule({
        name = "Markers",
        order = 30,
        frame = self.frame,
        isVisible = function()
            local profile = RC.db and RC.db.profile or {}
            if profile.showDropdownMarkers ~= nil then
                return profile.showDropdownMarkers ~= false
            end
            return not profile.hideMarkers
        end
    })
end

local function NormalizeModifier(modifier)
    modifier = tostring(modifier or "SHIFT"):upper()
    if modifier ~= "CTRL" and modifier ~= "ALT" then
        modifier = "SHIFT"
    end
    return modifier
end

local function ApplyWorldMarkerModifier(btn, markerIndex)
    if not btn then
        return
    end
    local profile = RC.db and RC.db.profile or {}
    local modifier = NormalizeModifier(profile.worldMarkerModifier)
    RC:ConfigureMarkerActionButton(btn, markerIndex, profile.enableTargetMarkers ~= false, profile.enableWorldMarkers ~= false, modifier)
end

-- Blizzard's localized marker names, with English fallbacks.
local MARKER_NAMES = {
    [1] = L["Star"], [2] = L["Circle"], [3] = L["Diamond"], [4] = L["Triangle"],
    [5] = L["Moon"], [6] = L["Square"], [7] = L["Cross"], [8] = L["Skull"],
}

local function GetMarkerName(markerIndex)
    return _G["RAID_TARGET_" .. tostring(markerIndex)] or MARKER_NAMES[markerIndex] or L["Marker"]
end

local function MarkerModifierLabel(modifier)
    modifier = NormalizeModifier(modifier)
    if modifier == "CTRL" then
        return L["Ctrl"]
    elseif modifier == "ALT" then
        return L["Alt"]
    end
    return L["Shift"]
end

local function BuildMarkerHints(btn)
    local profile = RC.db and RC.db.profile or {}
    local hints = {}
    if profile.enableTargetMarkers ~= false then
        table.insert(hints, L["Click: mark your target"])
        table.insert(hints, L["Right-click: clear target marker"])
    end
    if profile.enableWorldMarkers ~= false then
        local modifier = MarkerModifierLabel(btn.worldMarkerModifier)
        table.insert(hints, string.format(L["%s-click: place world marker"], modifier))
        table.insert(hints, string.format(L["%s-right-click: clear world marker"], modifier))
    end
    if #hints == 0 then
        table.insert(hints, L["Marker clicks are turned off in Settings"])
    end
    return hints
end

local function StyleMarkerCell(btn, state)
    local bg = RC.Config.ButtonBg
    if state == "pressed" then
        local pressed = RC.Config.ButtonPressed
        btn:SetBackdropColor(pressed.r, pressed.g, pressed.b, 0.85)
    elseif state == "hover" then
        local hover = RC.Config.ButtonHover
        btn:SetBackdropColor(hover.r, hover.g, hover.b, 0.85)
    else
        btn:SetBackdropColor(bg.r, bg.g, bg.b, 0.30)
    end
    if state == "hover" or state == "pressed" then
        local accent = RC.Config.Accent
        btn:SetBackdropBorderColor(accent.r, accent.g, accent.b, 0.52)
        btn.icon:SetVertexColor(1, 1, 1, 1)
    else
        btn:SetBackdropBorderColor(1, 1, 1, 0)
        btn.icon:SetVertexColor(0.92, 0.92, 0.92, 1)
    end
end

local function RegisterSecureClicks(btn)
    -- Pin the secure action to one phase instead of inheriting a CVar that can
    -- leave a button registered for the opposite phase and therefore inert.
    btn:RegisterForClicks("AnyDown")
    btn:SetAttribute("useOnKeyDown", true)
end

function Markers:CreateMarkerBar()
    if not RC.Menu then return end

    local layout = RC.MenuLayout or { contentWidth = 216, rowHeight = 28 }
    local bar = CreateFrame("Frame", nil, RC.Menu)
    bar:SetSize(layout.contentWidth, layout.rowHeight)
    self.frame = bar

    local icons = {
        [8] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", -- Skull
        [7] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7", -- Cross
        [6] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6", -- Square
        [5] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5", -- Moon
        [4] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4", -- Triangle
        [3] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3", -- Diamond
        [2] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2", -- Circle
        [1] = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1", -- Star
    }

    -- Eight flush cells spanning the full content width, so the strip lines
    -- up edge to edge with the control buttons above it (8 x 27 = 216).
    local totalIcons = 8
    local btnWidth = math.floor(layout.contentWidth / totalIcons)
    local btnHeight = layout.rowHeight
    local btnSpacing = 0
    local iconSize = 20
    local totalRowWidth = (totalIcons * btnWidth) + ((totalIcons - 1) * btnSpacing)
    local startX = math.floor((layout.contentWidth - totalRowWidth) / 2)

    local lastBtn = nil
    for i = 8, 1, -1 do
        -- SecureActionButtonTemplate required for protected actions
        local btn = CreateFrame("Button", "RC_MarkerBtn" .. i, bar, "SecureActionButtonTemplate,BackdropTemplate")
        btn.rcBorderMinAlpha = 0
        btn:SetSize(btnWidth, btnHeight)
        RC:SkinFrame(btn)
        RC:SetFrameThemeRole(btn, "ButtonBg", 0.30)
        btn:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, 0.30)
        btn:SetBackdropBorderColor(1, 1, 1, 0)

        -- Register release-only clicks so marker actions do not double-fire.
        RegisterSecureClicks(btn)

        ---------------------------------------------------------------
        -- Normal click: Target marker via /tm (built-in slash command)
        -- macrotext works in 11.0.2+ with 255-char limit
        ---------------------------------------------------------------
        ---------------------------------------------------------------
        -- Modifier+click: World marker via Blizzard's native secure
        -- "worldmarker" action. The attributes are prepared out of combat.
        ---------------------------------------------------------------
        ApplyWorldMarkerModifier(btn, i)

        -- Icon texture
        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("CENTER")
        tex:SetSize(iconSize, iconSize)
        tex:SetTexture(icons[i])
        btn.icon = tex

        -- Store for tooltip
        btn.markerIndex = i

        -- Hover highlight + tooltip
        StyleMarkerCell(btn, "normal")

        btn:SetScript("OnEnter", function(self)
            StyleMarkerCell(self, "hover")
            RC:ShowMenuTooltip(self, GetMarkerName(self.markerIndex), nil, BuildMarkerHints(self))
        end)
        btn:SetScript("OnLeave", function(self)
            StyleMarkerCell(self, "normal")
            RC:HideMenuTooltip(self)
        end)
        btn:HookScript("OnMouseDown", function(self)
            StyleMarkerCell(self, "pressed")
        end)
        btn:HookScript("OnMouseUp", function(self)
            StyleMarkerCell(self, self:IsMouseOver() and "hover" or "normal")
        end)

        if i == 8 then
            btn:SetPoint("LEFT", bar, "LEFT", startX, 0)
        else
            btn:SetPoint("LEFT", lastBtn, "RIGHT", btnSpacing, 0)
        end

        lastBtn = btn
    end

    -- No explicitly tacked on clear button as per user request
end

function Markers:RefreshTheme()
    if not self.frame then return end
    for _, btn in ipairs({ self.frame:GetChildren() }) do
        if btn and btn.markerIndex then
            StyleMarkerCell(btn, "normal")
        end
    end
end

function Markers:UpdateClearAttributes()
    self:RefreshModifierAttributes()
end

function Markers:RefreshModifierAttributes()
    if InCombatLockdown and InCombatLockdown() then
        -- Secure attributes are locked; RC re-applies every surface after combat.
        RC.MarkerModifierRefreshPending = true
        return
    end
    if not self.frame then
        return
    end
    for _, child in ipairs({ self.frame:GetChildren() }) do
        if child and child.markerIndex then
            ApplyWorldMarkerModifier(child, child.markerIndex)
        end
    end
end
