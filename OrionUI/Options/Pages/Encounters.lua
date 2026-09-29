-- Encounter ability browser (CLAUDE.md §9.1, our own design): pick a dungeon and boss,
-- see every ability the Journal lists with its tags, choose per ability what OrionUI
-- does (automatic / off / warning / defensive), and test it through the real pipeline.
-- Settings are per spec (bindings live under the current specialization).
local _, ns = ...

local L = ns.L
local W = ns.Widgets

local MAX_ROWS = 40
local ROW_H = 34
local MODE_TEXT = { off = L["Off"], warn = L["Warning only"], defensive = L["Warning + defensive"] }

local page = { instanceKey = nil, bossIndex = 1, rows = {} }

-- Instances offered: where you are now + this season's Mythic+ dungeons.
local function Instances()
    local list, seen = {}, {}
    local inst = ns.EncounterManager.instance
    if inst.journalInstanceID then
        list[#list + 1] = { value = inst.journalInstanceID .. ":" .. tostring(inst.difficultyID or 0),
            text = L["Here"] .. ": " .. tostring(inst.name), jid = inst.journalInstanceID, diff = inst.difficultyID }
        seen[inst.journalInstanceID] = true
    end
    for _, cmID in ipairs(C_ChallengeMode.GetMapTable() or {}) do
        local name, _, _, _, _, mapID = C_ChallengeMode.GetMapUIInfo(cmID)
        local jid = mapID and C_EncounterJournal.GetInstanceForGameMap(mapID)
        if jid and not seen[jid] then
            seen[jid] = true
            list[#list + 1] = { value = jid .. ":8", text = name, jid = jid, diff = 8 }
        end
    end
    return list
end

local function Selected()
    for _, i in ipairs(Instances()) do
        if i.value == page.instanceKey then return i end
    end
    local first = Instances()[1]
    page.instanceKey = first and first.value
    return first
end

local function Catalog()
    local sel = Selected()
    if not sel then return nil, L["No dungeons to show. Enter a dungeon, or wait for the Mythic+ season list to load."] end
    local entry, err = ns.JournalCatalog:Get(sel.jid, sel.diff)
    if not entry then
        return nil, err == "combat" and L["Leave combat to load the Journal."] or (L["Journal data unavailable:"] .. " " .. tostring(err))
    end
    return entry
end

local function TagText(tags)
    local out = {}
    for _, t in ipairs({ "tank", "healer", "dps", "deadly", "important", "interruptible", "magic", "bleed", "buster", "physical" }) do
        if tags[t] then out[#out + 1] = t end
    end
    return table.concat(out, " · ")
end

local function AutoText(tags)
    local R = ns.Reminders
    if R.db.tankAuto and ns.Player.role == "TANK" and (tags.tank or tags.buster) then
        return L["Automatic (defensive)"]
    end
    return L["Automatic (off)"]
end

local function TestAbility(boss, a)
    ns.MechanicRegistry:LoadEncounter(boss.encounterID)
    ns.BossModBridge:Timer({
        source = "Test", id = "test-" .. a.spellID, key = a.spellID, text = a.title, icon = a.icon,
        duration = ns.Reminders.db.leadTime + 3, encounterID = boss.encounterID,
    })
end

local function AbilityRow(parent)
    local T = ns.Theme
    local row = { }
    local spec = {
        label = "",
        values = function()
            local a = row.ability
            return {
                { value = "auto", text = a and AutoText(a.tags) or L["Automatic"] },
                { value = "off", text = MODE_TEXT.off },
                { value = "warn", text = MODE_TEXT.warn },
                { value = "defensive", text = MODE_TEXT.defensive },
            }
        end,
        get = function()
            local b = row.boss and ns.Reminders:Binding(row.boss.encounterID, row.boss.encounterID .. ":" .. row.ability.spellID)
            return b and b.mode or "auto"
        end,
        set = function(mode)
            ns.Reminders:SetMode(row.boss.encounterID, row.boss.encounterID .. ":" .. row.ability.spellID, mode)
        end,
    }
    local frame = W.Dropdown(parent, spec)
    frame:SetHeight(ROW_H)
    row.frame = frame
    row.icon = frame:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.test = T:Button(frame, L["Test"], 54, 24)
    row.test:SetPoint("RIGHT", frame, "RIGHT", -(W.CONTROL_W + 8), 0)
    row.test:SetScript("OnClick", function() TestAbility(row.boss, row.ability) end)
    row.title = T:Text(frame, 13)
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 2)
    row.title:SetPoint("RIGHT", row.test, "LEFT", -8, 0)
    row.title:SetWordWrap(false)
    row.tags = T:Text(frame, 11, T.colors.faint)
    row.tags:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.tags:SetPoint("RIGHT", row.test, "LEFT", -8, 0)
    row.tags:SetWordWrap(false)
    return row
end

local function Refresh(container)
    local entry, err = Catalog()
    page.message:SetText(err or "")
    local boss = entry and (entry.bosses[page.bossIndex] or entry.bosses[1])
    local abilities = boss and boss.abilities or {}
    local y = page.listTop
    for i = 1, MAX_ROWS do
        local row, a = page.rows[i], abilities[i]
        if a then
            row.boss, row.ability = boss, a
            row.icon:SetTexture(a.icon or 134400)
            row.title:SetText(a.title)
            row.tags:SetText(TagText(a.tags))
            row.frame:ClearAllPoints()
            row.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 16, -y)
            row.frame:SetWidth(page.width - 32)
            row.frame:Refresh()
            row.frame:Show()
            y = y + ROW_H
        else
            row.frame:Hide()
        end
    end
    page.box:SetShown(#abilities > 0)
    if #abilities > 0 then page.box:Place(0, page.listTop - 6, page.width, y - page.listTop + 12) end
    container:SetHeight(y + 30)
end

ns.Options:RegisterPage("encounters", {
    category = "reminders", label = L["Encounters"], order = 5,
    build = function(container, addRows, width)
        page.width = width
        local y = addRows({
            { type = "Title", label = L["Encounters"],
              desc = L["Choose what happens for each boss ability. Settings are saved for your current specialization."] },
            { type = "Header", label = L["Dungeon"] },
            { type = "Dropdown", label = L["Dungeon"], values = function()
                local out = {}
                for _, i in ipairs(Instances()) do out[#out + 1] = { value = i.value, text = i.text } end
                return out
              end,
              get = function() Selected() return page.instanceKey end,
              set = function(v) page.instanceKey, page.bossIndex = v, 1 ns.Options:Refresh() end },
            { type = "Dropdown", label = L["Boss"], values = function()
                local entry = Catalog()
                local out = {}
                for i, b in ipairs(entry and entry.bosses or {}) do out[#out + 1] = { value = i, text = b.name } end
                return out
              end,
              get = function() return page.bossIndex end,
              set = function(v) page.bossIndex = v ns.Options:Refresh() end },
        }, 0)
        local T = ns.Theme
        local header = T:Text(container, 11, T.colors.muted)
        header:SetPoint("TOPLEFT", 2, -y)
        header:SetText(L["Abilities"]:upper())
        page.message = T:Text(container, 12, T.colors.muted)
        page.message:SetPoint("TOPLEFT", 2, -(y + 22))
        page.message:SetWidth(width)
        page.listTop = y + 26
        page.box = T:Box(container)
        for i = 1, MAX_ROWS do page.rows[i] = AbilityRow(container) end
        return page.listTop + 40
    end,
    refresh = Refresh,
})
