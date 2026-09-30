local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local L = RC.L
local SynergyAnalyzer = RC:NewModule("SynergyAnalyzer", "AceEvent-3.0")

function SynergyAnalyzer:OnInitialize()
    self.db = RC.db.profile
end

-- Uses the same raid-buff provider rules as the Ready Check tooltip, so both
-- report the same missing buffs for the same roster.
function SynergyAnalyzer:AnalyzeRaid()
    if not self.db.enableSynergyAnalyzer then
        RC:Print(L["Buff Analyzer is disabled in settings."])
        return
    end

    if not IsInGroup() then
        RC:Print(L["Buff Analyzer: you are not in a group."])
        return
    end

    local foundClasses = {}
    for _, unit in ipairs(RC:GetGroupUnits()) do
        if UnitExists(unit) then
            local _, classFile = UnitClass(unit)
            if classFile then
                foundClasses[classFile] = true
            end
        end
    end

    local missing = {}
    for _, rule in ipairs(RC:GetCoreBuffRules()) do
        local covered = false
        for _, classFile in ipairs(rule.classes) do
            if foundClasses[classFile] then
                covered = true
                break
            end
        end
        if not covered then
            table.insert(missing, rule.name)
        end
    end

    if #missing == 0 then
        RC:Print(L["Buff Analyzer: |cff33ff33every raid buff and utility is covered.|r"])
    else
        RC:Print(string.format(L["Buff Analyzer: |cffff5555missing|r %s."], table.concat(missing, ", ")))
    end
end
