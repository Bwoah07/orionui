-- HUD stack (Stig, 2026-09-30): the rune bar moves up while the Death and Decay bar (EUI's first
-- tracked buff bar) is showing, so the two never overlap, and drops back down when it hides.
--
--   rune bar              <- sits on the D&D bar while it shows, else on the power bar
--   Death and Decay bar   <- EUI anchors it on the power bar
--   power bar
--   cooldown row
--
-- The frames are EllesmereUI's (checked in its source 2026-09-30): ERB_SecondaryFrame (runes /
-- combo points), ERB_PrimaryBar (power), ECME_TBBWrap1 (first tracked buff bar). They are plain,
-- unprotected frames, so moving them is fine in combat. EUI re-anchors them now and then; we
-- hook their SetPoint and put ours back on the next frame. Nothing is saved into EUI.
local _, ns = ...

local L = ns.L
local S = ns.Schema

local M = ns.Modules:New("HudStack", {
    category = "qol", label = L["Resource stack"], order = 4,
    desc = L["Keeps EllesmereUI's rune bar above the Death and Decay bar (or any first tracked buff bar) while it shows, so nothing overlaps."],
    profileKey = "layout",
    -- Off by default: EllesmereUI keeps re-positioning the rune bar and fights the move (Stig saw it
    -- jump around, 2026-09-30). The EUI layout now leaves a fixed slot for the D&D bar instead.
    schema = S.Table{ fields = {
        enabled = S.Bool{ default = false, label = L["Enabled (experimental)"], order = 0 },
        gap = S.Number{ default = 1, min = 0, max = 10, step = 1, label = L["Gap between bars (pixels)"], order = 1 },
    } },
})

local function Runes() return _G.ERB_SecondaryFrame end
local function Power() return _G.ERB_PrimaryBar end
local function Tracked() return _G.ECME_TBBWrap1 end

local placing = false -- true while we move the runes ourselves (so our SetPoint hook ignores it)

local function Place()
    if not M.enabled then return end
    local runes, power, tracked = Runes(), Power(), Tracked()
    if not (runes and power) then return end
    local base = (tracked and tracked:IsShown()) and tracked or power
    local gap = M.db.gap
    placing = true
    runes:ClearAllPoints()
    runes:SetPoint("BOTTOM", base, "TOP", 0, gap)
    placing = false
end

local hooked = {}
local function Hook()
    local runes, tracked = Runes(), Tracked()
    if runes and not hooked.runes then
        hooked.runes = true
        -- EUI re-anchors the runes on its own layout passes; put ours back right after.
        hooksecurefunc(runes, "SetPoint", function()
            if not placing and M.enabled then ns.Events:Coalesce("hudstack", Place) end
        end)
    end
    if tracked and not hooked.tracked then
        hooked.tracked = true
        tracked:HookScript("OnShow", Place)
        tracked:HookScript("OnHide", Place)
    end
    return runes ~= nil
end

-- The Death and Decay bar is created and shown by EUI whenever it likes (often only once D&D is
-- first cast), so rather than relying on hooks alone we check twice a second whether it's showing
-- and move the runes when that changes. Cheap: two lookups and a comparison.
local lastShown
local function Check()
    Hook()
    local tracked, runes = Tracked(), Runes()
    local shown = tracked ~= nil and tracked:IsShown()
    -- Also re-place when EUI has moved the runes back to its own anchor.
    local _, rel = runes and runes:GetPoint(1)
    local want = shown and tracked or Power()
    if shown ~= lastShown or (runes and rel ~= want) then
        lastShown = shown
        Place()
    end
end

function M:OnEnable()
    lastShown = nil
    self:NewTicker(0.5, Check)
    ns.Events:On("PLAYER_ENTERING_WORLD", self, function() lastShown = nil Check() end)
    Check()
end

function M:Refresh() Place() end

-- Hooks can't be removed; they check M.enabled. Put the runes back on the power bar.
function M:OnDisable()
    local runes, power = Runes(), Power()
    if runes and power then
        placing = true
        runes:ClearAllPoints()
        runes:SetPoint("BOTTOM", power, "TOP", 0, 1)
        placing = false
    end
end
