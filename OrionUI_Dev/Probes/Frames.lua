-- Layout probes (2026-09-30): find which frame is which on screen, so OrionUI can attach
-- to the right EllesmereUI frames.
--   /ouidev frames   the EUI frames OrionUI attaches to: shown?, size, screen edges
--   /ouidev under    hover something, then run it: every frame under the mouse with its parents
local _, ns = ...

local NAMES = {
    "ECME_CDMBar_cooldowns", "ECME_CDMBar_utility", "ECME_CDMBar_buffs",
    "EssentialCooldownViewer", "UtilityCooldownViewer", "BuffIconCooldownViewer", "BuffBarCooldownViewer",
    "EllesmereUIResourceBarsFrame", "ERB_PrimaryBar", "ERB_SecondaryFrame", "ERB_CastBarFrame",
    "ECME_TBBWrap1", "ECME_TBB1", "ECME_TBBWrap2",
}

local function Rect(f)
    local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
    if not l then return "no position" end
    return ("L%.0f R%.0f T%.0f B%.0f  (%.0fx%.0f)"):format(l, r, t, b, r - l, t - b)
end

local function Frames()
    local lines = {}
    for _, name in ipairs(NAMES) do
        local f = _G[name]
        if f and f.GetLeft then
            local p1, rel, p2, x, y = f:GetPoint(1)
            local relName = rel and rel.GetName and rel:GetName() or tostring(rel)
            lines[#lines + 1] = ("%-30s %s  %s  anchor %s->%s:%s %.0f,%.0f"):format(name, f:IsShown() and "SHOWN" or "hidden",
                Rect(f), tostring(p1), tostring(relName), tostring(p2), x or 0, y or 0)
        else
            lines[#lines + 1] = ("%-30s missing"):format(name)
        end
    end
    ns.CopyWindow:Show(table.concat(lines, "\n"))
end

local function Under()
    local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
    local lines = {}
    for _, f in ipairs(foci or {}) do
        local chain, cur, depth = {}, f, 0
        while cur and depth < 8 do
            chain[#chain + 1] = (cur.GetName and cur:GetName() or "?") .. " [" .. Rect(cur) .. "]"
            cur = cur.GetParent and cur:GetParent()
            depth = depth + 1
        end
        lines[#lines + 1] = table.concat(chain, "\n   in ")
    end
    if #lines == 0 then lines[1] = "Nothing under the mouse (some frames ignore the mouse; use /ouidev frames)." end
    ns.CopyWindow:Show(table.concat(lines, "\n\n"))
end

function ns.ProbeFrames() Frames() end
function ns.ProbeUnder() Under() end
