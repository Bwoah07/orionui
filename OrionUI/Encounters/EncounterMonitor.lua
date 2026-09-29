-- Encounter monitor: a compact list of the boss abilities OrionUI currently knows about
-- (from the bridge), with a countdown and Journal tags. A debugging and trust tool:
-- it shows exactly what reminders will react to. Off by default (Boss mods page).
local _, ns = ...

local L = ns.L
local Monitor = { rows = {} }
ns.EncounterMonitor = Monitor

local MAX_ROWS, ROW_H, WIDTH = 8, 20, 260
local TAG_ORDER = { "tank", "deadly", "healer", "dps", "important", "interruptible", "magic", "bleed" }

local frame, ticker, testUntil

local function Create()
    local T = ns.Theme
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(WIDTH, 24 + MAX_ROWS * ROW_H)
    frame:SetFrameStrata("MEDIUM")
    T:Skin(frame, { 0.05, 0.05, 0.07, 0.85 })
    frame.title = T:Text(frame, 11, T.colors.muted)
    frame.title:SetPoint("TOPLEFT", 8, -6)
    frame.title:SetText(L["Encounter monitor"])
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(WIDTH - 12, ROW_H)
        row:SetPoint("TOPLEFT", 6, -20 - (i - 1) * ROW_H)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT")
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.time = T:Text(row, 12)
        row.time:SetPoint("RIGHT")
        row.time:SetJustifyH("RIGHT")
        row.text = T:Text(row, 12)
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.text:SetPoint("RIGHT", row.time, "LEFT", -6, 0)
        row.text:SetWordWrap(false)
        Monitor.rows[i] = row
    end
    frame:Hide()
    ns.Movers:Register("EncounterMonitor", {
        label = L["Encounter monitor"], getFrame = function() return frame end, default = { x = -520, y = 120 },
    })
end

local function Tags(m)
    if not (m and m.tags) then return "" end
    local out = {}
    for _, t in ipairs(TAG_ORDER) do
        if m.tags[t] then out[#out + 1] = t:upper() end
    end
    return #out > 0 and ("  |cff999999" .. table.concat(out, " ") .. "|r") or ""
end

local function ShouldShow()
    local bridge = ns.BossModBridge
    if testUntil and GetTime() < testUntil then return true end
    return bridge.enabled and bridge.db.monitor and #bridge:Active() > 0
end

function Monitor:Update()
    if not frame then Create() end
    if not ShouldShow() then
        frame:Hide()
        if ticker then ticker:Cancel() ticker = nil end
        return
    end
    local list, now = ns.BossModBridge:Active(), GetTime()
    for i, row in ipairs(self.rows) do
        local evt = list[i]
        if evt then
            local left = evt.paused or math.max(0, evt.expiresAt - now)
            row.icon:SetTexture(evt.icon or 134400)
            row.text:SetText((evt.mechanic and evt.mechanic.title or evt.text or "?") .. Tags(evt.mechanic))
            row.time:SetText(evt.paused and "||" or (left < 10 and ("%.1f"):format(left) or ("%d"):format(left)))
            row:Show()
        else
            row:Hide()
        end
    end
    frame:Show()
    -- Tick only while visible; stops itself when there is nothing to show.
    if not ticker then ticker = C_Timer.NewTicker(0.1, function() Monitor:Update() end) end
end

local function OnChange() Monitor:Update() end
ns.Events:On("OUI_MECHANIC_TIMER", Monitor, OnChange)
ns.Events:On("OUI_MECHANIC_CANCEL", Monitor, OnChange)
ns.Events:On("OUI_MECHANIC_TEST", Monitor, function()
    testUntil = GetTime() + 12
    Monitor:Update()
end)
Monitor.name = "EncounterMonitor"

ns.Slash:Register("test", function(args)
    if args[1] ~= "reminder" then
        ns.Print("/oui test reminder")
        return
    end
    if not ns.BossModBridge.enabled then ns.Print(L["Boss mod support is turned off."]) return end
    ns.BossModBridge:Test()
    ns.Print(L["Sent two test mechanics through the encounter pipeline."])
end, "reminder  (fake boss timers through the pipeline)")

ns.Slash:Register("catalog", function()
    local entry, err = ns.JournalCatalog:Current()
    if not entry then ns.Print(L["No Journal data here:"] .. " " .. tostring(err)) return end
    local lines = { ("%s (journal %d, difficulty %s)"):format(entry.name, entry.journalInstanceID, tostring(entry.difficultyID)) }
    for _, boss in ipairs(entry.bosses) do
        lines[#lines + 1] = ("%d %s  encounterID=%s"):format(boss.index, boss.name, tostring(boss.encounterID))
        for _, a in ipairs(boss.abilities) do
            local tags = {}
            for t in pairs(a.tags) do tags[#tags + 1] = t end
            table.sort(tags)
            lines[#lines + 1] = ("    %d %s [%s]"):format(a.spellID, a.title, table.concat(tags, ","))
        end
    end
    ns.CopyBox:Show(L["Encounter Journal catalog"], table.concat(lines, "\n"))
end, "show the boss abilities OrionUI knows for this instance")
