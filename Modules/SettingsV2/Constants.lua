local _, ns = ...
local RC = ns.RC
local L = RC.L

RC.SettingsV2 = RC.SettingsV2 or {}
local V2 = RC.SettingsV2

V2.Constants = V2.Constants or {}

V2.Constants.Pages = {
    { key = "interface", label = L["Interface"], glyph = "UI", description = L["Visibility, dropdown controls, and the action strip"] },
    { key = "tank", label = L["Tank"], glyph = "TK", description = L["Personal warnings, upcoming timers, separate sounds, and boss rules"] },
    { key = "screenshot", label = L["Screenshot"], glyph = "SS", description = L["Capture quality, format, render scale, and resolution"] },
    { key = "appearance", label = L["Look & Feel"], glyph = "AP", description = L["Theme, surfaces, fonts, scaling, and profiles"] },
}

function V2.Constants:GetPages(settings)
    return (settings and settings.navTabs) or self.Pages
end

function V2.Constants:GetPageInfo(settings, key)
    for _, page in ipairs(self:GetPages(settings)) do
        if page.key == key then
            return page
        end
    end
    return { key = key or "interface", label = L["Settings"], description = L[""] }
end

function V2.Constants:IsValidPage(settings, key)
    for _, page in ipairs(self:GetPages(settings)) do
        if page.key == key then
            return true
        end
    end
    return false
end
