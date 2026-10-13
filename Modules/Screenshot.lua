local _, ns = ...
local RC = ns.RC
local L = RC.L
local ScreenShot = RC:NewModule("Screenshot", "AceEvent-3.0")

local DEFAULT_TARGET_WIDTH = 3840
local DEFAULT_TARGET_HEIGHT = 2160

local MAX_PROFILE = {
    { "graphicsQuality", "10" },
    { "RAIDgraphicsQuality", "10" },
    { "raidGraphicsQuality", "10" },

    { "graphicsTextureResolution", "3" },
    { "graphicsTextureFiltering", "5" },
    { "graphicsAntiAliasingMode", "5" },
    { "graphicsResampleQuality", "3" },
    { "graphicsProjectedTextures", "1" },
    { "graphicsViewDistance", "10" },
    { "graphicsEnvironmentDetail", "10" },
    { "graphicsGroundClutter", "10" },
    { "graphicsShadowQuality", "6" },
    { "graphicsLiquidDetail", "3" },
    { "graphicsSunshafts", "2" },
    { "graphicsParticleDensity", "5" },
    { "graphicsSpellDensity", "5" },
    { "graphicsComputeEffects", "4" },
    { "graphicsSSAO", "5" },
    { "graphicsDepthEffects", "4" },
    { "graphicsLightingQuality", "3" },
    { "graphicsOutlineMode", "3" },
    { "graphicsTextureFilteringMode", "5" },
    { "graphicsParticleQuality", "5" },
    { "graphicsClutterDensity", "10" },

    { "RAIDgraphicsTextureResolution", "3" },
    { "RAIDgraphicsTextureFiltering", "5" },
    { "RAIDgraphicsAntiAliasingMode", "5" },
    { "RAIDgraphicsResampleQuality", "3" },
    { "RAIDgraphicsProjectedTextures", "1" },
    { "RAIDgraphicsViewDistance", "10" },
    { "RAIDgraphicsEnvironmentDetail", "10" },
    { "RAIDgraphicsGroundClutter", "10" },
    { "RAIDgraphicsShadowQuality", "6" },
    { "RAIDgraphicsLiquidDetail", "3" },
    { "RAIDgraphicsSunshafts", "2" },
    { "RAIDgraphicsParticleDensity", "5" },
    { "RAIDgraphicsSpellDensity", "5" },
    { "RAIDgraphicsComputeEffects", "4" },
    { "RAIDgraphicsSSAO", "5" },
    { "RAIDgraphicsDepthEffects", "4" },
    { "RAIDgraphicsLightingQuality", "3" },
    { "RAIDgraphicsOutlineMode", "3" },
    { "RAIDgraphicsTextureFilteringMode", "5" },
    { "RAIDgraphicsParticleQuality", "5" },
    { "RAIDgraphicsClutterDensity", "10" },

    { "raidGraphicsTextureResolution", "3" },
    { "raidGraphicsTextureFiltering", "5" },
    { "raidGraphicsAntiAliasingMode", "5" },
    { "raidGraphicsResampleQuality", "3" },
    { "raidGraphicsProjectedTextures", "1" },
    { "raidGraphicsViewDistance", "10" },
    { "raidGraphicsEnvironmentDetail", "10" },
    { "raidGraphicsGroundClutter", "10" },
    { "raidGraphicsShadowQuality", "6" },
    { "raidGraphicsLiquidDetail", "3" },
    { "raidGraphicsSunshafts", "2" },
    { "raidGraphicsParticleDensity", "5" },
    { "raidGraphicsSpellDensity", "5" },
    { "raidGraphicsComputeEffects", "4" },
    { "raidGraphicsSSAO", "5" },
    { "raidGraphicsDepthEffects", "4" },
    { "raidGraphicsLightingQuality", "3" },
    { "raidGraphicsOutlineMode", "3" },
    { "raidGraphicsTextureFilteringMode", "5" },
    { "raidGraphicsParticleQuality", "5" },
    { "raidGraphicsClutterDensity", "10" },

    { "farclip", "10000" },
    { "horizonStart", "6000" },
    { "horizonClip", "10000" },
    { "environmentDetail", "150" },
    { "groundEffectDensity", "256" },
    { "groundEffectDist", "600" },
    { "particleDensity", "100" },
    { "particleMTDensity", "100" },
    { "projectedTextures", "1" },
    { "shadowMode", "4" },
    { "shadowTextureSize", "4096" },
    { "shadowNumCascades", "4" },
    { "SSAO", "3" },
    { "sunShafts", "2" },
    { "waterDetail", "3" },
    { "rippleDetail", "2" },
    { "reflectionMode", "3" },
    { "textureFilteringMode", "5" },
    { "MSAAQuality", "3" },
    { "MSAAAlphaTest", "1" },
    { "ResampleQuality", "3" },
    { "DepthBasedOpacity", "1" },
    { "ffxGlow", "1" },
    { "ffxAntiAliasingMode", "2" },
    { "ffxRectangle", "1" },
    { "weatherDensity", "3" },
    { "VolumeFog", "1" },
    { "VolumeFogLevel", "3" },
    { "refraction", "2" },
    { "OutlineEngineMode", "2" },
    { "entityLodDist", "10" },
    { "entityShadowFadeScale", "25" },
    { "wmoLodDist", "500" },
    { "lodObjectFadeScale", "120" },
    { "lodObjectMinSize", "0" },
    { "lodObjectCullSize", "0" },
    { "componentTextureLevel", "0" },
    { "worldBaseMip", "0" },
    { "terrainMipLevel", "0" },
    { "TerrainLodDiv", "128" },
    { "terrainTextureLod", "0" },
    { "showfootprints", "1" },
    { "showfootprintparticles", "1" },
    { "SpellClutter", "0" },
    { "spellClutter", "0" },

    { "RAIDfarclip", "10000" },
    { "RAIDhorizonStart", "6000" },
    { "RAIDhorizonClip", "10000" },
    { "RAIDgroundEffectDensity", "256" },
    { "RAIDgroundEffectDist", "600" },
    { "RAIDparticleDensity", "100" },
    { "RAIDparticleMTDensity", "100" },
    { "RAIDprojectedTextures", "1" },
    { "RAIDshadowMode", "4" },
    { "RAIDshadowNumCascades", "4" },
    { "RAIDSSAO", "3" },
    { "RAIDsunShafts", "2" },
    { "RAIDWaterDetail", "3" },
    { "RAIDrippleDetail", "2" },
    { "RAIDreflectionMode", "3" },
    { "RAIDweatherDensity", "3" },
    { "RAIDVolumeFog", "1" },
    { "RAIDVolumeFogLevel", "3" },
    { "RAIDrefraction", "2" },
    { "RAIDOutlineEngineMode", "2" },
    { "RAIDentityLodDist", "10" },
    { "RAIDentityShadowFadeScale", "25" },
    { "RAIDwmoLodDist", "500" },
    { "RAIDlodObjectFadeScale", "120" },
    { "RAIDlodObjectMinSize", "0" },
    { "RAIDlodObjectCullSize", "0" },

}

local function GetCVarSafe(name)
    local ok, value
    if C_CVar and C_CVar.GetCVar then
        ok, value = pcall(C_CVar.GetCVar, name)
    elseif GetCVar then
        ok, value = pcall(GetCVar, name)
    end

    if ok and value ~= nil then
        return tostring(value)
    end
    return nil
end

local function SetCVarSafe(name, value)
    if value == nil then
        return false
    end

    local ok
    if C_CVar and C_CVar.SetCVar then
        ok = pcall(C_CVar.SetCVar, name, tostring(value))
    elseif SetCVar then
        ok = pcall(SetCVar, name, tostring(value))
    end

    return ok and true or false
end

local function ParseResolution(value)
    if type(value) ~= "string" then
        return nil, nil
    end
    local width, height = value:match("^(%d+)x(%d+)")
    return tonumber(width), tonumber(height)
end

function ScreenShot:GetCurrentResolutionString()
    if GetPhysicalScreenSize then
        local ok, width, height = pcall(GetPhysicalScreenSize)
        width, height = tonumber(width), tonumber(height)
        if ok and width and height and width > 0 and height > 0 then
            return string.format("%dx%d", math.floor(width + 0.5), math.floor(height + 0.5))
        end
    end

    local cvarResolution = GetCVarSafe("gxResolution") or GetCVarSafe("gxWindowedResolution")
    local width, height = ParseResolution(cvarResolution)
    if width and height then
        return string.format("%dx%d", width, height)
    end

    if GetCurrentResolution and GetScreenResolutions then
        local okIndex, index = pcall(GetCurrentResolution)
        local okRes, resolutions = pcall(function()
            return { GetScreenResolutions() }
        end)
        if okIndex and okRes and resolutions and resolutions[index] then
            width, height = ParseResolution(resolutions[index])
            if width and height then
                return string.format("%dx%d", width, height)
            end
        end
    end

    return nil
end

function ScreenShot:SetSizePreset(preset)
    local value = preset
    if preset == "current" then
        value = self:GetCurrentResolutionString()
        if not value then
            RC:ShowError(L["Could not detect current resolution."])
            return
        end
    elseif preset == "auto" then
        value = ""
    end
    RC.db.profile.screenshotSizePreset = preset or "3840x2160"
    RC.db.profile.screenshotSizeOverride = value ~= "" and value or "3840x2160"
    if preset == "auto" then
        RC.db.profile.screenshotSizeOverride = self:GetCurrentResolutionString() or "3840x2160"
    end
end

function ScreenShot:OnInitialize()
    self.active = false
    StaticPopupDialogs["RC_CONFIRM_SCREENSHOT"] = StaticPopupDialogs["RC_CONFIRM_SCREENSHOT"] or {
        text = L["RaidControl will raise graphics, render scale, and screenshot resolution for this shot. Very high settings can freeze or lag the game for a moment.\n\nTake screenshot now?"],
        button1 = YES,
        button2 = NO,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function()
            local module = RC:GetModule("Screenshot", true)
            if module and module.Take then
                module:Take(true)
            end
        end,
    }
end

function ScreenShot:OnEnable()
    self:RegisterEvent("SCREENSHOT_SUCCEEDED")
    self:RegisterEvent("SCREENSHOT_FAILED")
end

function ScreenShot:CreateMenuButton()
    if not RC.Menu then return end

    local btn = RC:CreateStandardButton(nil, RC.Menu, 194, 22)
    btn.Text:SetText(L["Screenshot"])
    btn:SetScript("OnClick", function()
        self:Take()
    end)
    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(RC.Config.Accent.r, RC.Config.Accent.g, RC.Config.Accent.b, 1)
        if not self.customBg then
            self:SetBackdropColor(RC.Config.ButtonHover.r, RC.Config.ButtonHover.g, RC.Config.ButtonHover.b, 1)
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Max graphics screenshot"], 1, 1, 1)
        GameTooltip:AddLine(L["Uses your configured screenshot quality, hides UI if enabled, then restores everything."], 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        local br, bg, bb, ba = RC:GetBorderColor()
        self:SetBackdropBorderColor(br, bg, bb, ba)
        if not self.customBg then
            self:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a)
        end
        GameTooltip:Hide()
    end)

    self.button = btn
    self.frame = btn
end

function ScreenShot:SetButtonBusy(busy)
    local button = self.button
    if not button then
        local control = RC:GetModule("Control", true)
        button = control and control.screenshotButton
        self.button = button
    end
    if not button then
        return
    end

    if busy then
        button.Text:SetText(button.rcBusyText or L["Shooting..."])
        button.customBg = true
        button:SetBackdropColor(0.08, 0.20, 0.32, 0.95)
    else
        button.Text:SetText(button.rcDefaultText or L["Screenshot"])
        button.customBg = nil
        button:SetBackdropColor(RC.Config.ButtonBg.r, RC.Config.ButtonBg.g, RC.Config.ButtonBg.b, RC.Config.ButtonBg.a)
    end
end

function ScreenShot:SaveAndSetCVar(name, value)
    local currentValue = GetCVarSafe(name)
    if currentValue == nil then
        return false
    end

    -- CVar names are case-insensitive, and the profile lists some under two
    -- spellings. Only the first sighting holds the player's real value; saving
    -- again would record the max value just applied and restore that instead.
    local key = string.lower(name)
    if self.saved.cvars[key] == nil then
        self.saved.cvars[key] = currentValue
    end
    return SetCVarSafe(name, value)
end

function ScreenShot:FindBestResolution()
    if not GetScreenResolutions then
        return nil, nil
    end

    local ok, resolutions = pcall(function()
        return { GetScreenResolutions() }
    end)
    if not ok or not resolutions then
        return nil, nil
    end

    local bestIndex, bestValue, bestScore
    for index, value in ipairs(resolutions) do
        local width, height = ParseResolution(value)
        if width and height then
            local pixels = width * height
            local targetWidth, targetHeight = ParseResolution(RC.db and RC.db.profile and RC.db.profile.screenshotSizeOverride or "")
            targetWidth = targetWidth or DEFAULT_TARGET_WIDTH
            targetHeight = targetHeight or DEFAULT_TARGET_HEIGHT
            local isAtLeast4K = width >= targetWidth and height >= targetHeight
            local score = pixels + (isAtLeast4K and 1000000000 or 0)
            if not bestScore or score > bestScore then
                bestIndex = index
                bestValue = value
                bestScore = score
            end
        end
    end

    return bestIndex, bestValue
end

function ScreenShot:SaveState()
    self.saved = {
        cvars = {},
        uiParentShown = UIParent and UIParent:IsShown(),
        resolutionIndex = nil,
    }

    if GetCurrentResolution then
        local ok, index = pcall(GetCurrentResolution)
        if ok then
            self.saved.resolutionIndex = index
        end
    end
end

function ScreenShot:ApplyMaxGraphics()
    local profile = RC.db and RC.db.profile or {}
    self:SaveAndSetCVar("screenshotFormat", profile.screenshotFormat or "jpg")
    self:SaveAndSetCVar("screenshotQuality", tostring(profile.screenshotQuality or 10))
    self:SaveAndSetCVar("screenshotSizeOverride", profile.screenshotSizeOverride or "3840x2160")
    self:SaveAndSetCVar("RenderScale", tostring(profile.screenshotRenderScale or 2))
    self:SaveAndSetCVar("renderScale", tostring(profile.screenshotRenderScale or 2))

    if profile.screenshotApplyMaxGraphics ~= false then
        for _, entry in ipairs(MAX_PROFILE) do
            self:SaveAndSetCVar(entry[1], entry[2])
        end
    end

    local targetIndex, targetResolution = self:FindBestResolution()
    if targetResolution then
        self:SaveAndSetCVar("gxResolution", targetResolution)
        self:SaveAndSetCVar("gxNewResolution", targetResolution)
        self:SaveAndSetCVar("gxFullscreenResolution", targetResolution)
        self:SaveAndSetCVar("gxWindowedResolution", targetResolution)
    end

    if targetIndex and SetScreenResolution then
        pcall(SetScreenResolution, targetIndex)
    end
end

function ScreenShot:HideUI()
    if RC.db and RC.db.profile and RC.db.profile.screenshotHideUI == false then
        return
    end
    if UIParent and UIParent.Hide then
        pcall(UIParent.Hide, UIParent)
    end
end

function ScreenShot:RestoreUI()
    if not UIParent then
        return
    end

    if self.saved and self.saved.uiParentShown then
        pcall(UIParent.Show, UIParent)
    elseif UIParent.Hide then
        pcall(UIParent.Hide, UIParent)
    end
end

function ScreenShot:RestoreGraphics()
    if not self.saved then
        return
    end

    if self.saved.resolutionIndex and SetScreenResolution then
        pcall(SetScreenResolution, self.saved.resolutionIndex)
    end

    for name, value in pairs(self.saved.cvars or {}) do
        SetCVarSafe(name, value)
    end
end

function ScreenShot:Restore(message)
    if not self.active then
        return
    end

    self.active = false
    if self.restoreTimer and self.restoreTimer.Cancel then
        self.restoreTimer:Cancel()
    end
    self.restoreTimer = nil

    self:RestoreUI()
    self:RestoreGraphics()
    self:SetButtonBusy(false)

    if message then
        RC:Print(message)
    end
end

function ScreenShot:FireScreenshot()
    if not self.active then
        return
    end

    if _G.Screenshot then
        local ok = pcall(_G.Screenshot)
        if not ok then
            self:Restore(L["Screenshot failed; graphics and UI restored."])
        end
    else
        self:Restore(L["Screenshot API is unavailable; graphics and UI restored."])
    end
end

function ScreenShot:Take(skipConfirm)
    if self.active then
        RC:ShowError(L["Screenshot already in progress."])
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        RC:ShowError(L["Screenshots can't hide the UI in combat. Try again after the fight."])
        return
    end

    if not skipConfirm and RC.db and RC.db.profile and RC.db.profile.screenshotConfirmHighQuality ~= false and StaticPopup_Show then
        StaticPopup_Show("RC_CONFIRM_SCREENSHOT")
        return
    end

    self.active = true
    self:SetButtonBusy(true)
    self:SaveState()
    self:ApplyMaxGraphics()

    if RC.CloseMenu then
        RC:CloseMenu()
    end

    local delay = math.max(0.1, math.min(5, tonumber(RC.db and RC.db.profile and RC.db.profile.screenshotDelay) or 1))
    C_Timer.After(delay, function()
        if not self.active then return end
        self:HideUI()
        C_Timer.After(0.25, function()
            self:FireScreenshot()
        end)
    end)

    self.restoreTimer = C_Timer.NewTimer(delay + 6, function()
        self:Restore(L["Screenshot timed out; graphics and UI restored."])
    end)
end

function ScreenShot:SCREENSHOT_SUCCEEDED()
    if self.active then
        C_Timer.After(0.15, function()
            self:Restore(L["Screenshot saved. Graphics and UI restored."])
        end)
    end
end

function ScreenShot:SCREENSHOT_FAILED()
    self:Restore(L["Screenshot failed; graphics and UI restored."])
end
