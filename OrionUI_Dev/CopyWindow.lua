-- Scrollable, selectable text box so probe output can be copied (Ctrl+A, Ctrl+C)
-- and pasted back into the project thread. Created lazily on first use.
local _, ns = ...

local CopyWindow = {}
ns.CopyWindow = CopyWindow

local frame, editBox

local function Create()
    frame = CreateFrame("Frame", "OrionUIDevCopyFrame", UIParent) -- global name: required for UISpecialFrames (Esc closes)
    frame:SetSize(760, 480)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "OrionUIDevCopyFrame")

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("OrionUI_Dev: Ctrl+A then Ctrl+C to copy, Esc to close")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    editBox = CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(700)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Read-only feel: typing is allowed by the widget, but we restore the text on change.
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self.orionText then self:SetText(self.orionText) end
    end)
    scroll:SetScrollChild(editBox)
end

function CopyWindow:Show(text)
    if not frame then Create() end
    text = (text and text ~= "") and text or "(nothing logged yet)"
    editBox.orionText = text
    editBox:SetText(text)
    editBox:SetCursorPosition(0)
    frame:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end
