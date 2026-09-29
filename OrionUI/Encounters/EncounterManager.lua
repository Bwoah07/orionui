-- Encounter and instance state (CLAUDE.md §7.1). ENCOUNTER_START's encounterID is the
-- canonical boss identity; it matches the Journal's dungeonEncounterID (verified
-- 2026-09-29). Fires OUI_ENCOUNTER_START / OUI_ENCOUNTER_END and OUI_INSTANCE_CHANGED.
--
--   EncounterInfo = { encounterID, name, difficultyID, groupSize, startTime,
--                     instanceMapID, journalInstanceID, mplus, keystoneLevel }
local _, ns = ...

local EM = ns.Modules:New("EncounterManager", { category = "core" })
ns.EncounterManager = EM

EM.current = nil  -- EncounterInfo while a boss is engaged
EM.instance = {}  -- { name, instanceType, difficultyID, instanceMapID, journalInstanceID }

local function Plain(v) return ns.Secret.Plain(v, nil) end

local function RefreshInstance()
    local name, instanceType, difficultyID, _, _, _, _, instanceMapID = GetInstanceInfo()
    local old = EM.instance
    local journalInstanceID
    if instanceType ~= "none" and instanceMapID then
        journalInstanceID = C_EncounterJournal.GetInstanceForGameMap(instanceMapID)
    end
    EM.instance = {
        name = name, instanceType = instanceType, difficultyID = difficultyID,
        instanceMapID = instanceMapID, journalInstanceID = Plain(journalInstanceID),
    }
    if old.instanceMapID ~= instanceMapID or old.difficultyID ~= difficultyID then
        ns.Log:Debug("Encounters", "instance %s (%s) diff %s journal %s", tostring(name), tostring(instanceMapID),
            tostring(difficultyID), tostring(EM.instance.journalInstanceID))
        ns.Events:Fire("OUI_INSTANCE_CHANGED", EM.instance)
    end
end

function EM:IsInEncounter() return self.current ~= nil end

function EM:OnEnable()
    ns.Events:On("PLAYER_ENTERING_WORLD", self, RefreshInstance)
    ns.Events:On("ZONE_CHANGED_NEW_AREA", self, RefreshInstance)
    ns.Events:On("ENCOUNTER_START", self, function(_, _, encounterID, name, difficultyID, groupSize)
        -- Payload is documented plain; scrub anyway since everything keys on it.
        encounterID = Plain(encounterID)
        if not encounterID then return end
        local cm = C_ChallengeMode.IsChallengeModeActive()
        local level = cm and C_ChallengeMode.GetActiveKeystoneInfo() or nil
        self.current = {
            encounterID = encounterID, name = Plain(name), difficultyID = Plain(difficultyID),
            groupSize = Plain(groupSize), startTime = GetTime(),
            instanceMapID = self.instance.instanceMapID, journalInstanceID = self.instance.journalInstanceID,
            mplus = cm, keystoneLevel = level,
        }
        ns.Log:Info("Encounters", "start %d %s", encounterID, tostring(self.current.name))
        ns.Events:Fire("OUI_ENCOUNTER_START", self.current)
    end)
    ns.Events:On("ENCOUNTER_END", self, function(_, _, encounterID, _, _, _, success)
        local info = self.current
        self.current = nil
        success = Plain(success) == 1
        ns.Log:Info("Encounters", "end %s success=%s", tostring(Plain(encounterID)), tostring(success))
        ns.Events:Fire("OUI_ENCOUNTER_END", info or { encounterID = Plain(encounterID) }, success)
    end)
    RefreshInstance()
end

function EM:OnDisable()
    self.current = nil
end
