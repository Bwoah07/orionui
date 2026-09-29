-- Text dialog for the log, exports and imports. Read-only mode for copying; editable
-- mode with an action button for pasting (imports).
local _, ns = ...

local CopyBox = {}
ns.CopyBox = CopyBox

local frame

local function Create()
    local T = ns.Theme
    frame = CreateFrame("Frame", "OrionUICopyBox", UIParent) -- global name: Esc closes via UISpecialFrames
    frame:SetSize(640, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "OrionUICopyBox")
    T:Skin(frame, T.colors.bg)
    T:Shadow(frame)

    frame.title = T:Text(frame, 14)
    frame.title:SetPoint("TOPLEFT", 12, -10)

    frame.hint = T:Text(frame, 11, T.colors.muted)
    frame.hint:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
    frame.hint:SetPoint("RIGHT", -40, 0)

    local close = T:TextButton(frame, "x", 16)
    close:SetPoint("TOPRIGHT", -8, -6)
    close:SetScript("OnClick", function() frame:Hide() end)

    local box = CreateFrame("Frame", nil, frame)
    box:SetPoint("TOPLEFT", 12, -52)
    box:SetPoint("BOTTOMRIGHT", -12, 44)
    T:Skin(box, T.colors.sidebar)

    local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFont(T:Font(), 12, "")
    edit:SetTextColor(0.92, 0.92, 0.94)
    edit:SetWidth(580)
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        -- Read-only mode: undo typing but still allow selection/copy.
        if userInput and frame.readOnly then self:SetText(frame.text or "") end
    end)
    scroll:SetScrollChild(edit)
    box:SetScript("OnMouseDown", function() edit:SetFocus() end)
    frame.edit = edit

    frame.action = T:Button(frame, "", 140, 26, "accent")
    frame.action:SetPoint("BOTTOMRIGHT", -12, 12)

    frame.status = T:Text(frame, 11, T.colors.muted)
    frame.status:SetPoint("BOTTOMLEFT", 12, 16)
    frame.status:SetPoint("RIGHT", frame.action, "LEFT", -8, 0)
end

-- Read-only text to copy.
function CopyBox:Show(title, text, hint)
    if not frame then Create() end
    frame.readOnly, frame.text = true, text or ""
    frame.title:SetText(title or ns.NAME)
    frame.hint:SetText(hint or ns.L["Ctrl+A then Ctrl+C to copy."])
    frame.edit:SetText(frame.text)
    frame.edit:SetCursorPosition(0)
    frame.action:Hide()
    frame.status:SetText("")
    frame:Show()
    frame.edit:SetFocus()
    frame.edit:HighlightText()
end

-- Editable box; onAction(text) returns ok, message. The box stays open on failure.
function CopyBox:Prompt(title, hint, actionLabel, onAction)
    if not frame then Create() end
    frame.readOnly, frame.text = false, ""
    frame.title:SetText(title)
    frame.hint:SetText(hint or "")
    frame.edit:SetText("")
    frame.status:SetText("")
    frame.action:SetText(actionLabel)
    frame.action:SetScript("OnClick", function()
        local ok, msg = onAction(frame.edit:GetText())
        frame.status:SetText(msg or "")
        if ok then
            frame.readOnly, frame.text = true, frame.edit:GetText()
            frame.action:Hide()
        end
    end)
    frame.action:Show()
    frame:Show()
    frame.edit:SetFocus()
end
