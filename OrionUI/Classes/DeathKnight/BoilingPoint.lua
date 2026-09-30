-- Boiling Point indicator for Blood DK (our own design, CLAUDE.md §8.3): a thin bar in
-- the resource-bar style, or a plain icon, shown while Blood Boil is empowered.
--
-- Signal: the game's spell-activation highlight on Blood Boil (SPELL_ACTIVATION_OVERLAY_
-- GLOW_SHOW/HIDE, spell 50842). Its spell ID is readable in combat (verified 2026-09-30).
-- No stack counting: the game hides those numbers in combat, so a segmented bar driven by
-- stacks isn't possible; the highlight is the reliable "use it now" moment.
local _, ns = ...

local L = ns.L

local BLOOD_BOIL = 50842

local BP = { name = "BoilingPoint", active = false }
ns.BoilingPoint = BP

local frame, fill, icon

local function DB() return ns.BloodDK.db.boilingPoint end

local function Create()
    if frame then return end
    frame = CreateFrame("Frame", nil, UIParent)
    ns.Theme:Skin(frame, { 0, 0, 0, 0.5 })
    fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(C_Spell.GetSpellTexture(BLOOD_BOIL))
    frame:Hide()
    ns.Movers:Register("BloodBoilingPoint", {
        label = L["Boiling Point"], getFrame = function() return frame end, default = { x = 0, y = -160 },
    })
end

function BP:Refresh()
    if not frame then return end
    local db = DB()
    if db.style == "icon" then
        local s = math.max(16, db.height * 4)
        frame:SetSize(s, s)
        fill:Hide()
        icon:Show()
    else
        frame:SetSize(db.width, db.height)
        fill:SetColorTexture(ns.Theme:Accent())
        fill:Show()
        icon:Hide()
    end
    frame:SetShown(db.show and self.active)
end

local function OnGlow(_, event, spellID)
    if ns.Secret.Is(spellID) or spellID ~= BLOOD_BOIL then return end
    local on = event == "SPELL_ACTIVATION_OVERLAY_GLOW_SHOW"
    if on and not BP.active and DB().sound then PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959) end
    BP.active = on
    BP:Refresh()
end

function BP:Enable()
    Create()
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", self, OnGlow)
    ns.Events:On("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", self, OnGlow)
    self:Refresh()
end

function BP:Disable()
    ns.Events:OffAll(self)
    self.active = false
    if frame then frame:Hide() end
end
