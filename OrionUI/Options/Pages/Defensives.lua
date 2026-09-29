-- Defensive priority editor for the current specialization (CLAUDE.md §7.7 spec preset).
-- The first defensive in the list that is known, ready and not covered gets suggested.
local _, ns = ...

local L = ns.L
local ROW_H = 36
local MAX_ROWS = 12

local page = { rows = {} }

local function Order()
    local specID = ns.Player.specID
    local keys = ns.DefensiveResolver:Chain(specID, nil)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k end
    return out, specID
end

local function Save(order, specID)
    ns.Reminders.db.presets[specID] = order
    ns.Options:Refresh()
end

local function Move(index, delta)
    local order, specID = Order()
    local j = index + delta
    if j < 1 or j > #order then return end
    order[index], order[j] = order[j], order[index]
    Save(order, specID)
end

local function NewRow(container)
    local T = ns.Theme
    local row = CreateFrame("Frame", nil, container)
    row:SetHeight(ROW_H)
    row.num = T:Text(row, 12, T.colors.faint)
    row.num:SetPoint("LEFT", 0, 0)
    row.num:SetWidth(18)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(22, 22)
    row.icon:SetPoint("LEFT", 22, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = T:Text(row, 13)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 10, 0)
    row.note = T:Text(row, 11, T.colors.faint)
    row.note:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.down = T:Button(row, L["Down"], 56, 22)
    row.down:SetPoint("RIGHT")
    row.up = T:Button(row, L["Up"], 56, 22)
    row.up:SetPoint("RIGHT", row.down, "LEFT", -6, 0)
    return row
end

local DMG_TEXT = { all = L["all damage"], physical = L["physical"], magic = L["magic"] }

local function Refresh(container)
    local order, specID = Order()
    local y = page.listTop
    page.message:SetText(#order == 0 and L["No defensives for this specialization yet."] or "")
    for i = 1, MAX_ROWS do
        local row, key = page.rows[i], order[i]
        local def = key and ns.Data.DefensiveByKey(specID, key)
        if def then
            local known = C_SpellBook.IsSpellKnown(def.spell)
            row.num:SetText(i)
            row.icon:SetTexture(C_Spell.GetSpellTexture(def.spell) or 134400)
            row.icon:SetDesaturated(not known)
            row.name:SetText(C_Spell.GetSpellName(def.spell) or key)
            row.name:SetTextColor(unpack(known and ns.Theme.colors.text or ns.Theme.colors.faint))
            row.note:SetText(DMG_TEXT[def.dmg] .. (known and "" or ("  ·  " .. L["not talented"])))
            row.up:SetScript("OnClick", function() Move(i, -1) end)
            row.down:SetScript("OnClick", function() Move(i, 1) end)
            row.up:SetAlpha(i == 1 and 0.35 or 1)
            row.down:SetAlpha(i == #order and 0.35 or 1)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 16, -y)
            row:SetWidth(page.width - 32)
            row:Show()
            y = y + ROW_H
        else
            row:Hide()
        end
    end
    page.box:SetShown(#order > 0)
    if #order > 0 then page.box:Place(0, page.listTop - 6, page.width, y - page.listTop + 12) end
    page.reset:ClearAllPoints()
    page.reset:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -(y + 16))
    container:SetHeight(y + 50)
end

ns.Options:RegisterPage("defensives", {
    category = "reminders", label = L["Defensive priority"], order = 3,
    build = function(container, addRows, width)
        page.width = width
        local y = addRows({ { type = "Title", label = L["Defensive priority"],
            desc = L["Order for your current specialization. OrionUI suggests the first one that is known, ready, fits the damage type and isn't covered by one already running. Individual abilities can override this on the Encounters page later."] } }, 0)
        local T = ns.Theme
        page.message = T:Text(container, 12, T.colors.muted)
        page.message:SetPoint("TOPLEFT", 2, -y)
        page.listTop = y + 8
        page.box = T:Box(container)
        for i = 1, MAX_ROWS do page.rows[i] = NewRow(container) end
        page.reset = T:TextButton(container, L["Reset to default order"], 12)
        page.reset:SetScript("OnClick", function()
            ns.Reminders.db.presets[ns.Player.specID] = nil
            ns.Options:Refresh()
        end)
        return page.listTop + 40
    end,
    refresh = Refresh,
})
