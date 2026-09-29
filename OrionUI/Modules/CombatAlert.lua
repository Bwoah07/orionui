-- Combat alert: a short "+Combat" / "-Combat" flash when combat starts and ends.
-- Small on purpose: it is the reference module for the framework (CLAUDE.md §18.7)
-- and exercises settings schema, auto-built options, events, timers, a pooled-free
-- single frame, profile changes and a mover.
local _, ns = ...

local L = ns.L
local S = ns.Schema

local M = ns.Modules:New("CombatAlert", {
    category = "qol", label = L["Combat alert"],
    profileKey = "layout",
    schema = S.Table{ fields = {
        showEnter = S.Bool{ default = true, label = L["Show when entering combat"], order = 1 },
        showLeave = S.Bool{ default = true, label = L["Show when leaving combat"], order = 2 },
        duration = S.Number{ default = 1.5, min = 0.5, max = 5, step = 0.5, label = L["Duration (seconds)"], order = 3 },
        fontSize = S.Number{ default = 22, min = 10, max = 48, step = 1, label = L["Text size"], order = 4 },
        enterColor = S.Color{ default = { 1, 0.3, 0.3, 1 }, label = L["Entering colour"], order = 5 },
        leaveColor = S.Color{ default = { 0.3, 1, 0.5, 1 }, label = L["Leaving colour"], order = 6 },
    } },
})

local frame, text, hideTimer

local function EnsureFrame()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(200, 40)
    frame:SetFrameStrata("HIGH")
    text = frame:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER")
    frame:Hide()
    ns.Movers:Register("CombatAlert", {
        label = L["Combat alert"], getFrame = function() return frame end, default = { x = 0, y = 220 },
    })
end

function M:Refresh()
    if not frame then return end
    text:SetFont(ns.Theme:Font(), self.db.fontSize, "OUTLINE")
end

local function Flash(msg, color)
    text:SetText(msg)
    text:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    frame:Show()
    if hideTimer then hideTimer:Cancel() end
    hideTimer = M:After(M.db.duration, function() frame:Hide() end)
end

function M:OnEnable()
    EnsureFrame()
    self:Refresh()
    ns.Events:On("OUI_COMBAT_START", self, function()
        if self.db.showEnter then Flash(L["+Combat"], self.db.enterColor) end
    end)
    ns.Events:On("OUI_COMBAT_END", self, function()
        if self.db.showLeave then Flash(L["-Combat"], self.db.leaveColor) end
    end)
end

-- Events and timers are removed by the registry; only our own frame needs hiding.
function M:OnDisable()
    if frame then frame:Hide() end
end
