-- Custom reminders editor: pick a boss (or "any boss"), add reminders, edit the selected
-- one, test it, share it as a string. The editor sits above the list so the list can grow.
local _, ns = ...

local L = ns.L

local MAX_ROWS = 30
local ROW_H = 34
local TRIGGER_TEXT = { timer = L["Before a boss-mod timer ends"], message = L["When the boss mod announces"], pull = L["After the pull"] }
local ROLE_TEXT = { any = L["Everyone"], TANK = L["Tanks"], HEALER = L["Healers"], DAMAGER = L["Damage dealers"] }

local page = { encounterID = 0, rows = {} }

local function C() return ns.CustomReminders end

-- Every boss we have Journal data for (cached instances), plus "any boss".
local function Bosses()
    local out, seen = { { value = 0, text = L["Any boss"] } }, {}
    local cache = ns.DB.sv.caches.journal
    for _, entry in pairs(cache and cache.instances or {}) do
        for _, b in ipairs(entry.bosses or {}) do
            if b.encounterID and not seen[b.encounterID] then
                seen[b.encounterID] = true
                out[#out + 1] = { value = b.encounterID, text = b.name .. "  |cff888888" .. tostring(entry.name) .. "|r" }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.value == 0 then return true elseif b.value == 0 then return false end
        return a.text < b.text
    end)
    return out
end

local function Abilities()
    local boss = page.encounterID ~= 0 and ns.JournalCatalog:Boss(page.encounterID)
    local out = { { value = "", text = L["Choose..."] } }
    for _, a in ipairs(boss and boss.abilities or {}) do
        out[#out + 1] = { value = tostring(a.spellID), text = a.title }
    end
    return out
end

local function Summary(r)
    local when = r.trigger == "pull" and ("%ss after pull"):format(r.offset)
        or r.trigger == "timer" and ("%ss before %s"):format(r.offset, r.match ~= "" and r.match or "?")
        or ("on %s"):format(r.match ~= "" and r.match or "?")
    return when .. "  ·  " .. ROLE_TEXT[r.role]
end

local function Sel() return page.sel end
local function NoSel() return page.sel == nil end
local function Field(key, fallback)
    return function() local s = Sel() return s and s[key] or fallback end,
        function(v) local s = Sel() if s then s[key] = v ns.Options:Refresh() end end
end

local function EditorSpecs()
    local function F(type_, label, key, extra, fallback)
        local get, set = Field(key, fallback)
        local spec = { type = type_, label = label, get = get, set = set, disabled = NoSel }
        for k, v in pairs(extra or {}) do spec[k] = v end
        return spec
    end
    return {
        { type = "Header", label = L["Edit reminder"] },
        F("Toggle", L["Enabled"], "enabled", nil, false),
        F("Input", L["Name"], "name", nil, ""),
        F("Dropdown", L["When"], "trigger", { values = function()
            local out = {}
            for _, t in ipairs(C().TRIGGERS) do out[#out + 1] = { value = t, text = TRIGGER_TEXT[t] } end
            return out
        end }, "timer"),
        { type = "Dropdown", label = L["Pick an ability"], disabled = NoSel, values = Abilities,
          get = function() return "" end,
          set = function(v) if page.sel and v ~= "" then page.sel.match = v ns.Options:Refresh() end end },
        F("Input", L["Ability ID or text to match"], "match", { desc = L["The boss mod's ability ID (spell ID), or part of the timer/message text."] }, ""),
        F("Slider", L["Seconds (before the timer ends / after the pull)"], "offset", { min = 0, max = 60, step = 0.5 }, 5),
        F("Input", L["Text to show"], "text", nil, ""),
        F("Slider", L["Seconds on screen (announcements and pull)"], "show", { min = 1, max = 30, step = 0.5 }, 4),
        F("Dropdown", L["Who sees it"], "role", { values = function()
            local out = {}
            for _, r in ipairs(C().ROLES) do out[#out + 1] = { value = r, text = ROLE_TEXT[r] } end
            return out
        end }, "any"),
        F("Toggle", L["Play a sound"], "sound", nil, false),
        F("Toggle", L["Speak the text"], "speech", nil, false),
        { type = "ButtonBar", buttons = {
            { label = L["Test"], style = "accent", disabled = NoSel, func = function() C():Test(page.sel) end },
            { label = L["Export"], disabled = NoSel, func = function()
                ns.CopyBox:Show(L["Export reminder"], C():Export(page.sel))
            end },
        } },
    }
end

local function NewRow(container)
    local T = ns.Theme
    local row = CreateFrame("Frame", nil, container)
    row:SetHeight(ROW_H)
    row.name = T:Text(row, 13)
    row.name:SetPoint("TOPLEFT", 0, -3)
    row.name:SetWordWrap(false)
    row.sub = T:Text(row, 11, T.colors.faint)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.del = T:Button(row, L["Delete"], 64, 22)
    row.del:SetPoint("RIGHT")
    row.edit = T:Button(row, L["Edit"], 64, 22)
    row.edit:SetPoint("RIGHT", row.del, "LEFT", -6, 0)
    row.name:SetPoint("RIGHT", row.edit, "LEFT", -10, 0)
    row.sub:SetPoint("RIGHT", row.edit, "LEFT", -10, 0)
    return row
end

local function Refresh(container)
    local list = C():For(page.encounterID)
    local y = page.listTop
    local r1, g1, b1 = ns.Theme:Accent()
    page.empty:SetShown(#list == 0)
    for i = 1, MAX_ROWS do
        local row, e = page.rows[i], list[i]
        if e then
            local r = e.r
            row.name:SetText((r.enabled and "" or "|cff777777") .. (r.name ~= "" and r.name or L["(no name)"]) ..
                (e.key == 0 and page.encounterID ~= 0 and "  |cff888888" .. L["(any boss)"] .. "|r" or ""))
            if r == page.sel then row.name:SetTextColor(r1, g1, b1) else row.name:SetTextColor(1, 1, 1) end
            row.sub:SetText(Summary(r))
            row.edit:SetScript("OnClick", function() page.sel = r ns.Options:Refresh() end)
            row.del:SetScript("OnClick", function()
                ns.Dialog:Confirm(L["Delete this reminder?"], function()
                    if page.sel == r then page.sel = nil end
                    C():Delete(e.key, e.index)
                    ns.Options:Refresh()
                end)
            end)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", container, "TOPLEFT", 16, -y)
            row:SetWidth(page.width - 32)
            row:Show()
            y = y + ROW_H
        else
            row:Hide()
        end
    end
    page.box:SetShown(#list > 0)
    if #list > 0 then page.box:Place(0, page.listTop - 6, page.width, y - page.listTop + 12) end
    container:SetHeight(y + 40)
end

ns.Options:RegisterPage("customreminders", {
    category = "reminders", label = L["Custom reminders"], order = 4,
    build = function(container, addRows, width)
        page.width = width
        local specs = {
            { type = "Title", label = L["Custom reminders"],
              desc = L["Your own warnings for boss abilities: shown, played or spoken when a boss-mod timer is about to end, when the boss mod announces something, or a set time after the pull."] },
            { type = "Header", label = L["Boss"] },
            { type = "Dropdown", label = L["Reminders for"], values = Bosses,
              get = function() return page.encounterID end,
              set = function(v) page.encounterID, page.sel = v, nil ns.Options:Refresh() end },
            { type = "Description", label = L["Bosses appear here once you've opened their dungeon on the Encounters page or entered it."] },
            { type = "ButtonBar", buttons = {
                { label = L["Add reminder"], style = "accent", width = 130, func = function()
                    page.sel = C():New(page.encounterID)
                    ns.Options:Refresh()
                end },
                { label = L["Import"], func = function()
                    ns.CopyBox:Prompt(L["Import reminder"], L["Paste a reminder string. It is added to the boss selected above."], L["Import"], function(text)
                        local ok, r = C():Import(text, page.encounterID)
                        if not ok then return false, r end
                        page.sel = r
                        ns.Options:Refresh()
                        return true, L["Imported."]
                    end)
                end },
            } },
        }
        for _, s in ipairs(EditorSpecs()) do specs[#specs + 1] = s end
        local y = addRows(specs, 0)
        local T = ns.Theme
        local header = T:Text(container, 11, T.colors.muted)
        header:SetPoint("TOPLEFT", 2, -y)
        header:SetText(L["Reminders"]:upper())
        page.empty = T:Text(container, 12, T.colors.muted)
        page.empty:SetPoint("TOPLEFT", 2, -(y + 22))
        page.empty:SetText(L["None yet. Add one above."])
        page.listTop = y + 26
        page.box = T:Box(container)
        for i = 1, MAX_ROWS do page.rows[i] = NewRow(container) end
        return page.listTop + 40
    end,
    refresh = Refresh,
})
