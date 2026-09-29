-- Small modal-ish dialogs in our style: a yes/no confirm and a one-line text prompt.
local _, ns = ...

local Dialog = {}
ns.Dialog = Dialog

local frame

local function Create()
    local T = ns.Theme
    frame = CreateFrame("Frame", "OrionUIDialog", UIParent) -- global name: Esc closes via UISpecialFrames
    frame:SetSize(380, 150)
    frame:SetPoint("CENTER", 0, 120)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    tinsert(UISpecialFrames, "OrionUIDialog")
    T:Skin(frame, T.colors.bg)
    T:Shadow(frame)

    frame.text = T:Text(frame, 13)
    frame.text:SetPoint("TOPLEFT", 16, -16)
    frame.text:SetPoint("TOPRIGHT", -16, -16)
    frame.text:SetJustifyH("CENTER")

    frame.input = CreateFrame("EditBox", nil, frame)
    frame.input:SetSize(300, 22)
    frame.input:SetPoint("TOP", frame.text, "BOTTOM", 0, -12)
    frame.input:SetAutoFocus(false)
    frame.input:SetFont(T:Font(), 12, "")
    frame.input:SetTextInsets(6, 6, 0, 0)
    frame.input:SetMaxLetters(48)
    T:Skin(frame.input, T.colors.control)
    frame.input:SetScript("OnEscapePressed", function() frame:Hide() end)
    frame.input:SetScript("OnEnterPressed", function() frame.yes:Click() end)

    frame.yes = T:Button(frame, OKAY, 110, 26, "accent")
    frame.yes:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -6, 14)
    frame.no = T:Button(frame, CANCEL, 110, 26)
    frame.no:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 6, 14)
    frame.no:SetScript("OnClick", function() frame:Hide() end)
end

local function Open(text, withInput, default, onAccept)
    if not frame then Create() end
    frame.text:SetText(text)
    frame.input:SetShown(withInput)
    frame.input:SetText(default or "")
    frame:SetHeight(withInput and 150 or 120)
    frame.yes:SetScript("OnClick", function()
        local value = frame.input:GetText()
        frame:Hide()
        onAccept(withInput and ns.Util.Trim(value) or true)
    end)
    frame:Show()
    if withInput then
        frame.input:SetFocus()
        frame.input:HighlightText()
    end
end

function Dialog:Confirm(text, onYes) Open(text, false, nil, onYes) end

function Dialog:Ask(text, default, onAccept) Open(text, true, default, onAccept) end
