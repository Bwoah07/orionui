local _, ns = ...
local RC = ns.RC
if not RC then
    return
end

local function IsFinitePositive(value)
    return type(value) == "number"
        and value > 0
        and value == value
        and value ~= math.huge
end

-- Scale top-level UI frames around their current visual center. WoW scales
-- anchor offsets with the child frame, so the center offset must be adjusted
-- by the same ratio to prevent the window from walking across the screen.
function RC:SetScalePreserveCenter(frame, rawScale, onPositionChanged)
    if not frame or not frame.SetScale then
        return nil
    end

    local newScale = tonumber(rawScale)
    if not IsFinitePositive(newScale) then
        return nil
    end

    local oldScale = frame.GetScale and tonumber(frame:GetScale()) or 1
    if not IsFinitePositive(oldScale) then
        oldScale = 1
    end

    if math.abs(newScale - oldScale) < 0.0001 then
        return newScale
    end

    local centerX, centerY
    if frame.GetCenter then
        centerX, centerY = frame:GetCenter()
    end
    local canReanchor = type(centerX) == "number"
        and type(centerY) == "number"
        and UIParent
        and frame.ClearAllPoints
        and frame.SetPoint
        and (not frame.GetParent or frame:GetParent() == UIParent)

    frame:SetScale(newScale)

    if canReanchor then
        local ratio = newScale / oldScale
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", centerX / ratio, centerY / ratio)
    end

    if type(onPositionChanged) == "function" then
        onPositionChanged(frame, canReanchor)
    end
    return newScale
end

-- Resize a top-level frame whose rows hang from its top edge without the rows
-- jumping: a CENTER or BOTTOM anchor would move the top by half (or all) of
-- the height change. The frame is re-anchored by its current top-left first.
function RC:SetHeightKeepingTop(frame, height)
    if not frame or not frame.SetHeight then
        return
    end
    local current = frame.GetHeight and frame:GetHeight()
    if type(current) == "number" and math.abs(current - height) < 0.5 then
        return
    end
    local point, relativeTo, relativePoint = nil, nil, nil
    if frame.GetPoint then
        point, relativeTo, relativePoint = frame:GetPoint(1)
    end
    local anchoredByTop = point == "TOPLEFT" and relativePoint == "BOTTOMLEFT"
    local left = frame.GetLeft and frame:GetLeft()
    local top = frame.GetTop and frame:GetTop()
    if not anchoredByTop and not frame.rcMoving and type(left) == "number" and type(top) == "number"
        and UIParent and (relativeTo == nil or relativeTo == UIParent)
        and (not frame.GetParent or frame:GetParent() == UIParent) then
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    frame:SetHeight(height)
end
