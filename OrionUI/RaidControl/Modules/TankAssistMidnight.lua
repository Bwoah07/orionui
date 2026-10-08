local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local TankAssist = RC:GetModule("TankAssist", true)

if not TankAssist then
    return
end

-- Current Midnight tank controller.
--
-- Blizzard can mark enemy spellcast payloads secret on restricted maps. This
-- module therefore treats Encounter Timeline events as the authoritative
-- trigger. A timeline event reaching Finished means "mechanic starts now";
-- it is never treated as an automatic taunt by itself.

local MIDNIGHT_KEYS = {
    nymrissa = true,
    nekzali = true,
    sentinels = true,
    explorers = true,
    vashnik = true,
    sszorak = true,
    twinfangs = true,
    coiledaltar = true,
    ulatek = true,
}

local MECHANIC_META = {
    nymrissa = {
        ["Iceblade Flurry"] = {
            bossUnit = "boss1",
            resolveAfter = 7.0,
            playerTitle = "HOLD BOSS — ICEBLADE FLURRY",
            playerDetail = "Keep Nymrissa for the full cast and strike sequence.",
            offTitle = "WAIT — TAUNT AFTER FLURRY",
            offDetail = "Do not taunt early. Take Nymrissa when the full sequence ends.",
        },
        ["Water Jet"] = {
            bossUnit = "boss1",
            resolveAfter = 6.0,
            playerTitle = "AIM WATER JET AT ICE",
            playerDetail = "Keep the boss and aim Water Jet through Lingering Frost. Swap after the channel.",
            offTitle = "WAIT — TAUNT AFTER WATER JET",
            offDetail = "Let the current tank finish the Water Jet channel, then take Nymrissa.",
            preMoveLead = 7,
            preMoveTitle = "AIM BOSS AT FROST — WATER JET SOON",
            preMoveDetail = "Line Nymrissa up with Lingering Frost before Water Jet starts; keep the frontal off the raid.",
            preMoveSpoken = "Aim",
        },
    },
    nekzali = {
        ["Possession Barrage"] = {
            bossUnit = "boss1",
            resolveAfter = 8.0,
            playerTitle = "RUN OUT — POSSESSION BARRAGE",
            playerDetail = "Create maximum distance and keep Nek'zali for the full 6 sec cast + 2 sec channel.",
            offTitle = "WAIT — TAUNT AFTER BARRAGE",
            offDetail = "Do not taunt early. Take Nek'zali only after the full Barrage resolves.",
            preMoveLead = 7,
            preMoveTitle = "GET READY TO RUN OUT — BARRAGE SOON",
            preMoveDetail = "Set the boss so you have a clean lane to create maximum distance when Possession Barrage starts.",
            preMoveSpoken = "Move",
        },
    },
    sentinels = {
        ["Empowering Slam"] = { bossUnit = "boss1" },
        ["Bloodvenom Injection"] = { bossUnit = "boss2" },
        ["Vitriolic Stasis"] = {
            resolveAfter = 30.0,
            everyoneTitle = "STASIS — SOLVE TOXINS",
            everyoneDetail = "Resolve Vitriolic Stasis. Tanks exchange Sentinel assignments when Stasis ends.",
            spoken = "Move",
            preMoveEveryone = true,
            preMoveLead = 8,
            preMoveTitle = "STASIS SOON — PREPARE TANK SWAP",
            preMoveDetail = "Get ready for Stasis. After it ends, trade Sentinels so Bloodvenom stacks can fall off.",
            preMoveSpoken = "Move",
            resolveEveryoneTitle = "SWAP SENTINELS NOW",
            resolveEveryoneDetail = "Stasis is over: exchange Sentinel assignments and return to your side while keeping the bosses separated.",
            resolveEveryoneSpoken = "Swap",
        },
    },
    explorers = {
        ["Shredding Shards"] = {
            bossUnit = "boss4",
            resolveAfter = 3.5,
            crossSwap = true,
            playerTitle = "HOLD IKU — SHREDDING SHARDS",
            playerDetail = "Keep Iku for the entire Shredding Shards sequence.",
            offTitle = "WAIT — CROSS-TAUNT AFTER SHARDS",
            offDetail = "Do not taunt during the sequence. Cross-taunt Iku and Nama when it ends.",
        },
    },
    vashnik = {
        ["Dripping Fangs"] = {
            bossUnit = "boss1",
            resolveAfter = 2.0,
            playerTitle = "HOLD — DRIPPING FANGS",
            playerDetail = "Take the full cast, then hand Vashnik over.",
            offTitle = "WAIT — TAUNT AFTER FANGS",
            offDetail = "Take Vashnik after Dripping Fangs finishes.",
        },
    },
    sszorak = {
        ["Apex Predator"] = {
            startOnly = true,
            everyoneTitle = "APEX PREDATOR — TANK COMBO",
            everyoneDetail = "Each tank takes one Ravage and one Mutilate. Tempest is not a taunt trigger.",
            spoken = "Defensive",
        },
    },
    twinfangs = {
        ["Caustic Deluge"] = {
            bossName = "vexhul",
            resolveAfter = 5.0,
            playerTitle = "HOLD VEXHUL — CAUSTIC DELUGE",
            playerDetail = "Keep Vexhul for the full Deluge, then hand the boss over.",
            offTitle = "WAIT — TAUNT VEXHUL AFTER DELUGE",
            offDetail = "Do not taunt Vexhul during Deluge. Take Vexhul when it finishes.",
        },
        ["Stone Breaker"] = {
            bossName = "ithraz",
            defensive = false,
            startOnly = true,
            playerTitle = "STONE BREAKER — HOLD ALL 3",
            playerDetail = "Keep Ithraz for all three impacts. Exchange bosses only after 3/3.",
            offTitle = "WAIT — TAUNT AFTER 3/3",
            offDetail = "Do not steal Ithraz during Stone Breaker. Exchange bosses after the third impact.",
            preMoveLead = 7,
            preMoveTitle = "MOVE ITHRAZ TO STONE BREAKER #1",
            preMoveDetail = "Get to the first numbered Stone Breaker soak and be ready to take all three impacts in order.",
            preMoveSpoken = "Move",
        },
    },
    coiledaltar = {
        ["Sever"] = {
            bossName = "zul'jan",
            resolveAfter = 3.5,
            playerTitle = "AIM SEVER — HOLD BOSS",
            playerDetail = "Aim the frontal through the assigned venom cleanup, then swap after the channel.",
            offTitle = "WAIT — TAUNT AFTER SEVER",
            offDetail = "Let the current tank finish the Sever channel, then take the boss.",
            preMoveLead = 7,
            preMoveTitle = "FACE BOSS INTO ORB PILE — SEVER SOON",
            preMoveDetail = "Pre-position Zul'jan so Sever clears the assigned venom/orb pile without sweeping the raid.",
            preMoveSpoken = "Aim",
        },
        ["Soul Sever"] = {
            bossName = "malacrass",
            resolveAfter = 3.5,
            playerTitle = "AIM SOUL SEVER — HOLD BOSS",
            playerDetail = "Aim Soul Sever at the assigned spirits. Swap only after the channel.",
            offTitle = "WAIT — TAUNT AFTER SOUL SEVER",
            offDetail = "Let the current tank finish Soul Sever, then take the boss.",
            preMoveLead = 7,
            preMoveTitle = "FACE BOSS INTO SPIRITS — SOUL SEVER SOON",
            preMoveDetail = "Pre-position Malacrass so Soul Sever hits the assigned spirits and not the raid.",
            preMoveSpoken = "Aim",
        },
        ["Blighted Sever"] = {
            bossName = "zul'jan",
            resolveAfter = 3.5,
            playerTitle = "AIM BLIGHTED SEVER — HOLD",
            playerDetail = "Aim the frontal through the assigned cleanup. Swap after the channel.",
            offTitle = "WAIT — TAUNT AFTER BLIGHTED SEVER",
            offDetail = "Do not taunt during the frontal. Take the boss after it resolves.",
            preMoveLead = 7,
            preMoveTitle = "FACE BOSS INTO CLEANUP PILE — SEVER SOON",
            preMoveDetail = "Set the combined boss facing before Blighted Sever so the frontal performs the planned cleanup.",
            preMoveSpoken = "Aim",
        },
    },
    ulatek = {
        ["Caustic Waves"] = {
            defensive = false,
            startOnly = true,
            everyoneTitle = "CAUSTIC WAVES — SAFE TANK TRADE",
            everyoneDetail = "Use the safe movement window for the tank handoff; do not range-taunt through unsafe space.",
            spoken = "Swap",
        },
        ["Mother's Wrath"] = {
            -- The red circle both tanks stand in (Stig, 2026-10-08): defensive for both.
            everyTank = true,
            resolveAfter = 8.0,
            playerTitle = "HOLD — MOTHER'S WRATH",
            playerDetail = "Stay in melee for the full 5 sec cast + 3 sec wrath sequence, then hand Ula'tek over.",
            offTitle = "WAIT — TAUNT AFTER WRATH",
            offDetail = "Do not range-taunt. Take Ula'tek after the full Mother's Wrath sequence ends.",
        },
    },
}

local MOVEMENT_EXACT = {
    nymrissa = {
        [1258668] = { action = "nymrissa-gap", label = "Swirling Whirlpools" },
        [1258669] = { action = "nymrissa-gap", label = "Swirling Whirlpools" },
        [1258676] = { action = "nymrissa-gap", label = "Swirling Whirlpools" },
        [1258677] = { action = "nymrissa-gap", label = "Swirling Whirlpools" },
    },
    nekzali = {
        [1295397] = { action = "nekzali-coffins", label = "Restless Amani" },
    },
    explorers = {
        [1296249] = { action = "explorers-mushrooms", label = "Explosive Surprise" },
    },
    vashnik = {
        [1283164] = { action = "vashnik-fountains", label = "Imbibe" },
    },
    sszorak = {
        [1285732] = { action = "sszorak-center", label = "Howling Maelstrom" },
        [1285828] = { action = "sszorak-center", label = "Howling Maelstrom" },
        [1305959] = { action = "sszorak-clean-slice", label = "Venomous Surge" },
        [1285419] = { action = "sszorak-crosswinds", label = "Raging Crosswinds" },
        [1285425] = { action = "sszorak-crosswinds", label = "Raging Crosswinds" },
        [1285443] = { action = "sszorak-crosswinds", label = "Raging Crosswinds" },
        [1285453] = { action = "sszorak-crosswinds", label = "Raging Crosswinds" },
    },
    ulatek = {
        [1301510] = { action = "ulatek-platform", label = "Circling Prey / Platform Break" },
    },
}

local MOVEMENT_ACTIONS = {
    ["nymrissa-gap"] = {
        bossUnit = "boss1",
        lead = 8,
        preTitle = "MOVE BOSS TO SAFE GAP",
        preDetail = "Start moving Nymrissa into the safe lane before Swirling Whirlpools closes the space.",
        zeroTitle = "HOLD SAFE GAP — WHIRLPOOLS",
        zeroDetail = "Keep Nymrissa in the safe lane while the raid resolves Swirling Whirlpools.",
    },
    ["nekzali-coffins"] = {
        bossUnit = "boss1",
        lead = 8,
        preTitle = "MOVE BOSS TOWARD COFFINS",
        preDetail = "Drag Nek'zali toward the Restless Amani/coffin side now so the raid is positioned before the mechanic.",
        zeroTitle = "HOLD AT COFFINS — RESTLESS AMANI",
        zeroDetail = "Keep the boss stable at the planned coffin side without turning him through the raid.",
    },
    ["explorers-mushrooms"] = {
        everyTank = true,
        lead = 8,
        preTitle = "MOVE TO MUSHROOMS — BOMB SOON",
        preDetail = "Bring your tanked turtle close to a usable mushroom. Keep the mushroom untouched until the Blast Wave reaches it.",
        zeroTitle = "STAY BY MUSHROOM — DON'T JUMP YET",
        zeroDetail = "Explosive Surprise is active. Preserve the mushroom and wait for the Blast Wave to travel toward you.",
        zeroSpoken = "Move",
        activeDuration = 10,
        resolveTitle = "BLAST WAVE — USE MUSHROOM",
        resolveDetail = "Use the mushroom as the Blast Wave reaches your position. Do not burn it early.",
        resolveSpoken = "Jump",
    },
    ["vashnik-fountains"] = {
        bossUnit = "boss1",
        lead = 9,
        preTitle = "MOVE BOSS TO NEXT FOUNTAINS",
        preDetail = "Position Vashnik between the two fountains your raid wants for the next Imbibe.",
        zeroTitle = "HOLD BETWEEN FOUNTAINS — IMBIBE",
        zeroDetail = "Vashnik uses the two closest fountains. Keep the chosen pair closest until Imbibe begins.",
    },
    ["sszorak-center"] = {
        bossUnit = "boss1",
        lead = 9,
        preTitle = "MOVE BOSS TO CENTER",
        preDetail = "Start centering Sszorak before Howling Maelstrom / Dig In so the raid has room for the intermission.",
        zeroTitle = "HOLD CENTER — MAELSTROM",
        zeroDetail = "Keep Sszorak centered through Howling Maelstrom / Dig In.",
    },
    ["sszorak-clean-slice"] = {
        bossUnit = "boss1",
        lead = 7,
        preTitle = "MOVE BOSS TO CLEAN SLICE",
        preDetail = "Shift Sszorak to the next clean slice before Venomous Surge / Caustic Claws fills the current area.",
        zeroTitle = "HOLD CLEAN SLICE — SURGE",
        zeroDetail = "Keep the boss in the fresh section while the raid places Venomous Surge cysts.",
    },
    ["sszorak-crosswinds"] = {
        bossUnit = "boss1",
        lead = 7,
        preTitle = "SET BOSS — CROSSWINDS SOON",
        preDetail = "Finish the reposition now so Sszorak can stay stable while the raid pairs Raging Crosswinds.",
        zeroTitle = "HOLD BOSS STEADY — CROSSWINDS",
        zeroDetail = "Do not drag Sszorak during the paired Crosswinds resolution unless survival requires it.",
    },
    ["ulatek-platform"] = {
        everyTank = true,
        lead = 10,
        preTitle = "MOVE BOSS TO JUMP EDGE",
        preDetail = "Set Ula'tek on the edge toward the next platform now. Circling Prey / Platform Break is coming.",
        zeroTitle = "JUMP TO OTHER SIDE — PLATFORM BREAK",
        zeroDetail = "Circling Prey has started its 8-second break cast. Move Ula'tek and yourself off the current platform.",
        zeroSpoken = "Move",
        activeDuration = 8,
        resolveTitle = "PLATFORM BREAK NOW — BE OFF OLD SIDE",
        resolveDetail = "Be on the next platform and stabilize Ula'tek there. Taunt any Blightscale Shrieker your assignment requires.",
        resolveSpoken = "Jump",
    },
}

local EXPLORER_UNIT_STAGE = {
    boss1 = 2, -- Trader Gebbo
    boss3 = 3, -- First Mate Nama
    boss4 = 4, -- Scrollsage Iku
}

local LegacyOnInitialize = TankAssist.OnInitialize
local LegacyEncounterStart = TankAssist.ENCOUNTER_START
local LegacyEncounterEnd = TankAssist.ENCOUNTER_END
local LegacyClassifyTimelineEvent = TankAssist.ClassifyTimelineEvent
local LegacyHandleTimelineFinished = TankAssist.HandleTimelineFinished

local function ValueIsAccessible(value)
    if value == nil then
        return false
    end
    if issecretvalue then
        local ok, secret = pcall(issecretvalue, value)
        if ok and secret then
            return false
        end
    end
    if canaccessvalue then
        local ok, accessible = pcall(canaccessvalue, value)
        if ok and accessible == false then
            return false
        end
    end
    return true
end

local function SafeNumber(value)
    if not ValueIsAccessible(value) then
        return nil
    end
    local ok, number = pcall(tonumber, value)
    return ok and number or nil
end

local function SafeText(value)
    if not ValueIsAccessible(value) then
        return nil
    end
    local ok, text = pcall(tostring, value)
    return ok and text or nil
end

local function SafeLower(value)
    local text = SafeText(value)
    if not text then
        return ""
    end
    local ok, lower = pcall(string.lower, text)
    return ok and lower or ""
end

local function SafeBoolCall(callback, ...)
    if type(callback) ~= "function" then
        return nil
    end
    local ok, value = pcall(callback, ...)
    if not ok or not ValueIsAccessible(value) or type(value) ~= "boolean" then
        return nil
    end
    return value
end

local function CancelTimer(timer)
    if timer and type(timer.Cancel) == "function" then
        pcall(timer.Cancel, timer)
    end
end

local function GetEventFields(eventInfo)
    if type(eventInfo) ~= "table" or not ValueIsAccessible(eventInfo) then
        return nil, "", nil
    end
    local bossMod = TankAssist.GetBossModTimelineInfo and TankAssist:GetBossModTimelineInfo(eventInfo)
    local okID, rawID = pcall(function() return eventInfo.spellID end)
    local spellID = okID and SafeNumber(rawID) or nil
    if not spellID then
        local legacyOK, legacyID = pcall(function() return eventInfo.spellId end)
        spellID = legacyOK and SafeNumber(legacyID) or nil
    end
    local okName, rawName = pcall(function() return eventInfo.spellName end)
    local name = okName and SafeLower(rawName) or ""
    -- Hidden in encounters; the linked BigWigs bar knows the spell and name.
    if bossMod then
        spellID = spellID or bossMod.spellID
        if name == "" then name = bossMod.name or "" end
    end
    local okDuration, rawDuration = pcall(function() return eventInfo.duration end)
    local duration = okDuration and SafeNumber(rawDuration) or nil
    if duration then
        duration = math.floor(duration + 0.5)
    end
    return spellID, name, duration
end

local function CopyMeta(tracked, meta)
    if not tracked or not meta then
        return tracked
    end
    for key, value in pairs(meta) do
        if tracked[key] == nil then
            tracked[key] = value
        end
    end
    return tracked
end

function TankAssist:IsMidnightLiveRule(rule)
    return rule and MIDNIGHT_KEYS[rule.key] == true
end

function TankAssist:ResetMidnightEncounterState()
    if self.midnightResolutionTimers then
        for _, timer in pairs(self.midnightResolutionTimers) do
            CancelTimer(timer)
        end
    end
    CancelTimer(self.explorerStageTimer)
    CancelTimer(self.explorerStageResetTimer)
    self.explorerStageTimer = nil
    self.explorerStageResetTimer = nil
    self.midnightResolutionTimers = {}
    self.midnightTimelineCounts = {}
    self.midnightMovementCounts = {}
    self.timelineState = self.timelineState or {}
    self.timelineState.explorerStage = 1
end

function TankAssist:OnInitialize(...)
    if LegacyOnInitialize then
        LegacyOnInitialize(self, ...)
    end
    self:ResetMidnightEncounterState()
    -- Lost Explorers empowerment can be derived without reading protected casts:
    -- a turtle briefly becomes friendly about six seconds before its empowered
    -- timeline set is published. Keep this separate from normal unit spell data.
    if self.RegisterEvent then
        pcall(self.RegisterEvent, self, "UNIT_FLAGS", "MIDNIGHT_UNIT_FLAGS")
    end
end

function TankAssist:ENCOUNTER_START(...)
    if LegacyEncounterStart then
        LegacyEncounterStart(self, ...)
    end
    self:ResetMidnightEncounterState()
end

function TankAssist:ENCOUNTER_END(...)
    self:ResetMidnightEncounterState()
    if self.ClearMechanicCountdown then
        self:ClearMechanicCountdown(true)
    end
    if LegacyEncounterEnd then
        return LegacyEncounterEnd(self, ...)
    end
end

function TankAssist:MIDNIGHT_UNIT_FLAGS(event, unit)
    if not self.activeRule or self.activeRule.key ~= "explorers" then
        return
    end
    local stage = EXPLORER_UNIT_STAGE[unit]
    if not stage or SafeBoolCall(UnitIsFriend, "player", unit) ~= true then
        return
    end

    CancelTimer(self.explorerStageTimer)
    CancelTimer(self.explorerStageResetTimer)
    if not C_Timer or type(C_Timer.NewTimer) ~= "function" then
        return
    end

    -- BigWigs observes roughly 6.2s from the friendly flag to the empowerment.
    -- Set the stage just before Blizzard publishes the new timeline batch.
    self.explorerStageTimer = C_Timer.NewTimer(5.7, function()
        self.explorerStageTimer = nil
        if not self.activeRule or self.activeRule.key ~= "explorers" then
            return
        end
        self.timelineState = self.timelineState or {}
        self.timelineState.explorerStage = stage
        self.midnightMovementCounts.explorers32 = 0

        -- Mor'zahi's Command lasts about one minute. If no later friendly event
        -- arrives, return to the normal unempowered timeline after the phase.
        self.explorerStageResetTimer = C_Timer.NewTimer(61, function()
            self.explorerStageResetTimer = nil
            if self.timelineState then
                self.timelineState.explorerStage = 1
            end
            if self.midnightMovementCounts then
                self.midnightMovementCounts.explorers32 = 0
            end
        end)
    end)
end

function TankAssist:FindBossUnitByName(fragment)
    fragment = SafeLower(fragment)
    if fragment == "" then
        return nil
    end
    for index = 1, 5 do
        local unit = "boss" .. index
        if SafeBoolCall(UnitExists, unit) == true then
            local ok, name = pcall(UnitName, unit)
            name = ok and SafeLower(name) or ""
            if name ~= "" and string.find(name, fragment, 1, true) then
                return unit
            end
        end
    end
    return nil
end

function TankAssist:GetTrackedOwner(tracked, rule)
    -- Stable ownership lives in TankAssist.lua: a tank must hold the boss for a
    -- moment before it counts, so cast retargets and fast taunts cannot flip it.
    return self:GetMechanicOwner(tracked, rule)
end

local function BuildTankRecord(label, action, meta)
    local record = {
        kind = "tank",
        action = action or "swap",
        label = label,
    }
    return CopyMeta(record, meta)
end

function TankAssist:ClassifyMidnightTimelineEventByTimer(rule, eventInfo)
    local exact = self:GetTimelineMechanic(rule, eventInfo)
    if exact then
        exact.identifiedBy = self:GetBossModTimelineInfo(eventInfo) and "BigWigs" or "spell"
        local meta = MECHANIC_META[rule.key] and MECHANIC_META[rule.key][exact.label]
        return CopyMeta(exact, meta)
    end

    local spellID, eventName, duration = GetEventFields(eventInfo)
    local movementTable = MOVEMENT_EXACT[rule.key]
    local movement = spellID and movementTable and movementTable[spellID] or nil
    if movement then
        return {
            kind = "movement",
            action = movement.action,
            label = movement.label,
        }
    end

    -- Name fallback is useful when the spell ID itself is withheld but the
    -- timeline name remains accessible.
    if rule.key == "nekzali" and eventName == "restless amani" then
        return { kind = "movement", action = "nekzali-coffins", label = "Restless Amani" }
    elseif rule.key == "explorers" and eventName == "explosive surprise" then
        return { kind = "movement", action = "explorers-mushrooms", label = "Explosive Surprise" }
    elseif rule.key == "vashnik" and eventName == "imbibe" then
        return { kind = "movement", action = "vashnik-fountains", label = "Imbibe" }
    elseif rule.key == "sszorak" and eventName == "howling maelstrom" then
        return { kind = "movement", action = "sszorak-center", label = "Howling Maelstrom" }
    elseif rule.key == "sszorak" and eventName == "venomous surge" then
        return { kind = "movement", action = "sszorak-clean-slice", label = "Venomous Surge" }
    elseif rule.key == "sszorak" and eventName == "raging crosswinds" then
        return { kind = "movement", action = "sszorak-crosswinds", label = "Raging Crosswinds" }
    elseif rule.key == "nymrissa" and eventName == "swirling whirlpools" then
        return { kind = "movement", action = "nymrissa-gap", label = "Swirling Whirlpools" }
    elseif rule.key == "ulatek" and (eventName == "circling prey" or eventName == "platform break") then
        return { kind = "movement", action = "ulatek-platform", label = "Circling Prey / Platform Break" }
    end

    if not duration then
        return nil
    end

    if rule.key == "nymrissa" then
        if duration == 89 or duration == 107 then
            return { kind = "movement", action = "nymrissa-gap", label = "Swirling Whirlpools" }
        elseif duration == 9 or duration == 22 or duration == 27 then
            if self.activeDifficultyID == 16 then
                return BuildTankRecord("Water Jet", "swap", MECHANIC_META.nymrissa["Water Jet"])
            end
            return BuildTankRecord("Iceblade Flurry", "swap", MECHANIC_META.nymrissa["Iceblade Flurry"])
        end
    elseif rule.key == "nekzali" then
        if duration == 28 or duration == 36 then
            return BuildTankRecord("Possession Barrage", "swap", MECHANIC_META.nekzali["Possession Barrage"])
        end
        -- Restless Amani shares a 40s bucket with another event in phase one;
        -- do not guess it. Unique timeline/name data above is required.
    elseif rule.key == "sentinels" then
        if duration == 4 then
            return BuildTankRecord("Empowering Slam", "defensive", MECHANIC_META.sentinels["Empowering Slam"])
        elseif duration == 6 then
            return BuildTankRecord("Bloodvenom Injection", "defensive", MECHANIC_META.sentinels["Bloodvenom Injection"])
        end
        -- The repeating 22s bucket is deliberately ignored because delays can
        -- invert an alternating counter and warn the wrong tank.
    elseif rule.key == "explorers" then
        local stage = self.timelineState and self.timelineState.explorerStage or 1
        if duration == 30 then
            return BuildTankRecord("Shredding Shards", "cross-swap", MECHANIC_META.explorers["Shredding Shards"])
        elseif stage == 2 and duration == 13 then
            return { kind = "movement", action = "explorers-mushrooms", label = "Explosive Surprise" }
        elseif stage == 2 and duration == 32 then
            self.midnightMovementCounts = self.midnightMovementCounts or {}
            self.midnightMovementCounts.explorers32 = (self.midnightMovementCounts.explorers32 or 0) + 1
            if self.midnightMovementCounts.explorers32 == 3 then
                return { kind = "movement", action = "explorers-mushrooms", label = "Explosive Surprise" }
            end
        end
    elseif rule.key == "vashnik" then
        if duration == 20 or duration == 80 then
            return { kind = "movement", action = "vashnik-fountains", label = "Imbibe" }
        end
        local difficulty = self.activeDifficultyID
        local match = (difficulty == 16 and (duration == 8 or duration == 11 or duration == 22))
            or (difficulty == 15 and (duration == 8 or duration == 27 or duration == 28))
            or (difficulty ~= 15 and difficulty ~= 16 and (duration == 2 or duration == 30 or duration == 33))
        if match then
            return BuildTankRecord("Dripping Fangs", "swap", MECHANIC_META.vashnik["Dripping Fangs"])
        end
    elseif rule.key == "sszorak" then
        if duration == 5 or duration == 6 then
            return BuildTankRecord("Apex Predator", "assignment", MECHANIC_META.sszorak["Apex Predator"])
        elseif duration == 100 or duration == 111 or duration == 125 then
            return { kind = "movement", action = "sszorak-center", label = "Howling Maelstrom" }
        elseif duration == 29 or duration == 32 or duration == 36 then
            return { kind = "movement", action = "sszorak-clean-slice", label = "Venomous Surge" }
        elseif duration == 39 or duration == 43 or duration == 49 then
            return { kind = "movement", action = "sszorak-crosswinds", label = "Raging Crosswinds" }
        end
    elseif rule.key == "twinfangs" then
        local mythic = self.activeDifficultyID == 16
        if not mythic and (duration == 9 or duration == 10) then
            return BuildTankRecord("Caustic Deluge", "swap", MECHANIC_META.twinfangs["Caustic Deluge"])
        elseif (mythic and duration == 18) or (not mythic and (duration == 20 or duration == 22 or duration == 23)) then
            return BuildTankRecord("Stone Breaker", "stonebreaker", MECHANIC_META.twinfangs["Stone Breaker"])
        end
        -- Mythic 8s and the long repeating buckets contain multiple mechanics.
        -- Never infer a tank swap from those buckets without an exact identity.
    elseif rule.key == "coiledaltar" then
        if duration == 16 or duration == 21 then
            return BuildTankRecord("Sever", "swap", MECHANIC_META.coiledaltar["Sever"])
        elseif duration == 31 then
            return BuildTankRecord("Soul Sever", "swap", MECHANIC_META.coiledaltar["Soul Sever"])
        elseif duration == 29 or duration == 30 or duration == 32 or duration == 38 then
            return BuildTankRecord("Blighted Sever", "swap", MECHANIC_META.coiledaltar["Blighted Sever"])
        end
    elseif rule.key == "ulatek" then
        local state = self.timelineState or {}
        local stage = state.ulatekStage or 1
        if stage == 1 and duration == 118 then
            return { kind = "phase", stage = 2, label = "Rage of the Shackled" }
        elseif stage == 2 and duration == 10 then
            return { kind = "phase", stage = 2.5, label = "Stage Two transition" }
        elseif stage < 3 and (duration == 230 or duration == 235) then
            return { kind = "phase", stage = 3, label = "Serpent's Bite" }
        end
        if stage == 1 then
            if duration == 42 then
                return BuildTankRecord("Caustic Waves", "swap", MECHANIC_META.ulatek["Caustic Waves"])
            elseif duration == 10 or duration == 22 or duration == 37 or duration == 67 then
                return BuildTankRecord("Mother's Wrath", "defensive", MECHANIC_META.ulatek["Mother's Wrath"])
            end
        elseif stage == 3 then
            local difficulty = self.activeDifficultyID
            local platformBreak = (difficulty == 16 and (duration == 51 or duration == 61))
                or (difficulty == 15 and (duration == 51 or duration == 52 or duration == 61))
                or (difficulty ~= 15 and difficulty ~= 16 and (duration == 56 or duration == 66))
            if platformBreak then
                return { kind = "movement", action = "ulatek-platform", label = "Circling Prey / Platform Break" }
            elseif duration == 75 or duration == 76 then
                return BuildTankRecord("Mother's Wrath", "swap", MECHANIC_META.ulatek["Mother's Wrath"])
            end
        end
    end

    return nil
end

-- The timer-length buckets below date from when RaidControl was written and
-- drift with every hotfix (2026-10-08 against BigWigs: Ula'tek, Coiled Altar
-- and Vashnik buckets no longer match), which made taunt calls fire on the
-- wrong ability. BigWigs keeps its buckets current and counts shared ones, so
-- when its bar names a spell that is not one of our tank mechanics, the event
-- is not a taunt and the timer-length guess is skipped.
function TankAssist:ClassifyMidnightTimelineEvent(rule, eventInfo)
    local result = self:ClassifyMidnightTimelineEventByTimer(rule, eventInfo)
    if result and result.kind == "tank" and not result.identifiedBy then
        local bossMod = self:GetBossModTimelineInfo(eventInfo)
        if bossMod and bossMod.spellID then
            return nil
        end
        result.identifiedBy = "timer length"
    end
    return result
end

function TankAssist:ClassifyTimelineEvent(rule, eventInfo)
    if self:IsMidnightLiveRule(rule) then
        return self:ClassifyMidnightTimelineEvent(rule, eventInfo)
    end
    return LegacyClassifyTimelineEvent and LegacyClassifyTimelineEvent(self, rule, eventInfo) or nil
end

-- Explorers cross-swap: Nama is boss3, Iku is boss4 (see EXPLORER_UNIT_STAGE).
local CROSS_SWAP_PAIR = {
    { unit = "boss3", name = "NAMA" },
    { unit = "boss4", name = "IKU" },
}

-- Which boss the player should taunt when the cross-swap comes, from who has
-- held each boss for a while (the stable holder, not the live target, so a boss
-- turning for a cast doesn't flip the answer). Falls back to the live target,
-- then nil (unknown, keep the generic call). Returns the boss unit and name.
function TankAssist:GetCrossSwapTarget()
    local a, b = CROSS_SWAP_PAIR[1], CROSS_SWAP_PAIR[2]
    local roleA = self:GetHolderRole(self:GetStableBossHolder(a.unit))
    local roleB = self:GetHolderRole(self:GetStableBossHolder(b.unit))
    local mine
    if roleA == "player" and roleB ~= "player" then
        mine = a
    elseif roleB == "player" and roleA ~= "player" then
        mine = b
    elseif roleA == "cotank" and roleB ~= "cotank" then
        mine = b
    elseif roleB == "cotank" and roleA ~= "cotank" then
        mine = a
    elseif self:GetBossTargetState("player", a.unit) == true then
        mine = a
    elseif self:GetBossTargetState("player", b.unit) == true then
        mine = b
    end
    if not mine then
        return nil, nil
    end
    local other = mine == a and b or a
    return other.unit, self:GetBossDisplayName(other.unit, other.name) or other.name
end

function TankAssist:ShowPersonalMechanicStart(tracked, owner, rule)
    local title
    local detail
    local spoken
    if tracked.everyoneTitle then
        title = tracked.everyoneTitle
        detail = tracked.everyoneDetail or tracked.label
        spoken = tracked.spoken
    elseif tracked.crossSwap and tracked.crossTargetName then
        -- Hold your boss through the sequence, then take the other one.
        title = "WAIT — TAUNT " .. tracked.crossTargetName .. " AFTER SHARDS"
        detail = nil
        spoken = owner == "player" and (tracked.playerSpoken or "Defensive") or tracked.offSpoken
    elseif owner == "player" then
        title = tracked.playerTitle or ("HOLD — " .. string.upper(tracked.label or "TANK MECHANIC"))
        detail = tracked.playerDetail or "Keep the boss until the mechanic fully resolves."
        spoken = tracked.playerSpoken or "Defensive"
    elseif owner == "cotank" then
        title = tracked.offTitle or ("WAIT — TAUNT AFTER " .. string.upper(tracked.label or "MECHANIC"))
        detail = tracked.offDetail or "Do not taunt early. Take the boss after the mechanic resolves."
        spoken = tracked.offSpoken
    else
        return false
    end

    local category = self:GetWarningCategory(nil, spoken, title)
    if not self:IsWarningEnabled(category) then
        return false
    end
    local duration = SafeNumber(tracked.resolveAfter)
    if duration and duration > 0 and self.ShowActiveMechanicCountdown then
        self:ShowActiveMechanicCountdown(tracked, duration, title, detail, category)
        if self.PlayAlertSound and spoken then
            self:PlayAlertSound(spoken, category)
        end
        return true
    end

    return self:Alert(
        title,
        detail,
        spoken,
        rule.key .. ":start:" .. tostring(tracked.label),
        spoken ~= nil,
        rule,
        category
    )
end

function TankAssist:ResolveMidnightTankMechanic(tracked, owner, rule)
    if not self:ShouldRun() or not self.activeRule or self.activeRule.key ~= rule.key then
        return
    end

    if tracked.resolveEveryoneTitle then
        self:Alert(
            tracked.resolveEveryoneTitle,
            tracked.resolveEveryoneDetail or tostring(tracked.label or "Tank mechanic") .. " resolved.",
            tracked.resolveEveryoneSpoken or "Swap",
            rule.key .. ":resolve:everyone:" .. tostring(tracked.label),
            true,
            rule,
            "taunt"
        )
        return
    end

    if tracked.crossSwap and tracked.crossTargetName then
        if self:IsPlayerDead() then
            return
        end
        -- Already on it (a fast taunt): stay quiet rather than call it again.
        if tracked.crossTargetUnit and self:GetBossTargetState("player", tracked.crossTargetUnit) == true then
            return
        end
        self:Alert(
            "TAUNT " .. tracked.crossTargetName .. " NOW",
            "Cross-swap after " .. tostring(tracked.label or "Shredding Shards") .. ". Never taunt Gebbo.",
            "Taunt",
            rule.key .. ":resolve:" .. tostring(tracked.label),
            true,
            rule,
            "taunt"
        )
        return
    end

    if tracked.crossSwap then
        self:Alert(
            "CROSS-TAUNT NOW — IKU / NAMA",
            "Iku tank takes Nama; Nama tank takes Iku. Never taunt Gebbo.",
            "Taunt",
            rule.key .. ":resolve:" .. tostring(tracked.label),
            true,
            rule,
            "taunt"
        )
        return
    end

    -- Resolve using the owner snapshotted when the mechanic STARTED. Never
    -- pick the direction from the boss target after the mechanic; a fast
    -- correct taunt would reverse the call and tell the raid to taunt back.
    -- The live target is only used to stay quiet once the swap has happened.
    local label = tostring(tracked.label or "Tank mechanic")
    local bossUnit = self:ResolveMechanicBossUnit(tracked, rule)
    local bossName = self:GetBossDisplayName(bossUnit, tracked.bossName)
    if owner == "cotank" then
        if self:IsPlayerDead() then
            return
        end
        if bossUnit and self:GetBossTargetState("player", bossUnit) == true then
            return
        end
        self:Alert(
            self:GetRuleAlertText(rule, bossName and ("TAUNT " .. bossName .. " NOW") or "TAUNT NOW"),
            label .. " finished. Taunt " .. (bossName and self:TitleCase(bossName) or "the boss") .. " now.",
            "Taunt",
            rule.key .. ":taunt:" .. label,
            true,
            rule,
            "taunt"
        )
    elseif owner == "player" then
        -- Re-pick the co-tank so a living third tank replaces a dead partner.
        self:RefreshCoTank()
        if bossUnit and self:GetBossTargetState(self.coTankUnit, bossUnit) == true then
            return
        end
        if self.coTankUnit and self:IsCoTankDead() then
            self:Alert(
                "HOLD BOSS — CO-TANK DEAD",
                "No living co-tank can take the boss after " .. label .. ". Keep it and use a defensive.",
                "Defensive",
                rule.key .. ":hold:" .. label,
                true,
                rule,
                "defensive"
            )
            return
        end
        local coTank = self.coTankName and (self.coTankName:match("^([^%-]+)") or self.coTankName) or "Your co-tank"
        self:Alert(
            "SWAP OUT — CO-TANK TAUNT",
            label .. " finished. " .. coTank .. " takes "
                .. (bossName and self:TitleCase(bossName) or "the boss") .. " now.",
            "Swap",
            rule.key .. ":swap:" .. label,
            true,
            rule,
            "taunt"
        )
    elseif not self:IsPlayerDead() then
        -- Ownership was never readable (secret targets on the pull). A neutral
        -- call beats silence on the swap itself, unless a third tank is known
        -- to hold this boss and the swap is not ours at all.
        local holder = bossUnit and self:GetStableBossHolder(bossUnit) or nil
        if holder and holder ~= "other" and not self:GetHolderRole(holder) then
            return
        end
        self:Alert(
            bossName and ("TANK SWAP — " .. bossName) or "TANK SWAP",
            label .. " finished. Off-tank taunts now; the tank that took it lets go.",
            "Swap",
            rule.key .. ":check:" .. label,
            true,
            rule,
            "taunt"
        )
    end
end

function TankAssist:ScheduleMidnightResolution(tracked, owner, rule)
    local delay = SafeNumber(tracked.resolveAfter)
    if not delay or delay <= 0 or not C_Timer or type(C_Timer.NewTimer) ~= "function" then
        return false
    end

    self.midnightResolutionTimers = self.midnightResolutionTimers or {}
    local key = tostring(tracked.eventID or tracked.label or (GetTime and GetTime() or 0))
    CancelTimer(self.midnightResolutionTimers[key])
    self.midnightResolutionTimers[key] = C_Timer.NewTimer(delay, function()
        self.midnightResolutionTimers[key] = nil
        if self.ClearMechanicCountdown then
            self:ClearMechanicCountdown(false, tracked.eventID)
        end
        self:ResolveMidnightTankMechanic(tracked, owner, rule)
    end)
    return true
end

function TankAssist:ShouldPlayerHandleMidnightMovement(tracked, spec, rule)
    if not spec then
        return false
    end
    if spec.everyTank then
        if self.IsPlayerTank then
            return self:IsPlayerTank() == true
        end
        return true
    end

    local bossUnit = spec.bossUnit or (tracked and tracked.bossUnit)
    if not bossUnit and tracked and tracked.bossName then
        bossUnit = self:FindBossUnitByName(tracked.bossName)
    end
    if not bossUnit and rule then
        bossUnit = rule.bossUnit
    end
    if not bossUnit then
        return false
    end
    -- Movement calls go to the tank that has held the boss, so a boss turning
    -- to cast at someone else does not hide "where to take the boss".
    local role = self:GetHolderRole(self:GetStableBossHolder(bossUnit))
    if role then
        return role == "player"
    end
    return self:GetBossTargetState("player", bossUnit) == true
end

function TankAssist:ShouldShowUpcomingMovement(tracked)
    if not tracked or tracked.kind ~= "movement" then
        return false
    end
    local spec = MOVEMENT_ACTIONS[tracked.action]
    if not spec then
        return false
    end
    return self:ShouldPlayerHandleMidnightMovement(tracked, spec, self.activeRule)
end

function TankAssist:HandleMidnightProactiveWarning(tracked)
    if not tracked or not self:ShouldRun() or not self.activeRule
        or not self:IsMidnightLiveRule(self.activeRule)
        or RC.db.profile.tankAssistUseCastRules == false
    then
        return false
    end

    local rule = self.activeRule
    local title, detail, spoken
    if tracked.kind == "movement" then
        local spec = MOVEMENT_ACTIONS[tracked.action]
        if not spec or not self:ShouldPlayerHandleMidnightMovement(tracked, spec, rule) then
            return false
        end
        title = spec.preTitle
        detail = spec.preDetail
        spoken = spec.preSpoken or "Move"
    elseif tracked.kind == "tank" and tracked.preMoveTitle then
        if not tracked.preMoveEveryone then
            local owner = self:GetTrackedOwner(tracked, rule)
            if owner ~= "player" then
                return false
            end
        end
        title = tracked.preMoveTitle
        detail = tracked.preMoveDetail
        spoken = tracked.preMoveSpoken or "Move"
    else
        return false
    end

    tracked.previewTitle = title
    tracked.previewDetail = detail
    local shown = self:Alert(
        title,
        detail,
        spoken,
        rule.key .. ":preposition:" .. tostring(tracked.eventID or tracked.label),
        spoken ~= nil,
        rule,
        "movement"
    )
    -- Restore the live timeline countdown after the short alert so the tank can
    -- see exactly how much movement time remains.
    if shown and self.ShowTimelineMechanicCountdown then
        self:ShowTimelineMechanicCountdown(tracked)
    end
    return shown
end

function TankAssist:ScheduleMidnightProactiveWarning(tracked)
    if not tracked or not tracked.eventID or not self:IsMidnightLiveRule(self.activeRule)
        or not C_Timer or type(C_Timer.NewTimer) ~= "function"
    then
        return false
    end

    local defaultLead
    if tracked.kind == "movement" then
        local spec = MOVEMENT_ACTIONS[tracked.action]
        if not spec then
            return false
        end
        defaultLead = SafeNumber(spec.lead) or 8
    elseif tracked.kind == "tank" and tracked.preMoveTitle then
        defaultLead = SafeNumber(tracked.preMoveLead) or 8
    else
        return false
    end

    local profile = RC.db and RC.db.profile or {}
    local configuredLead = SafeNumber(profile.tankAssistMovementLeadSeconds)
    -- Respect the selected warning lead; use the authored lead only if unset.
    local lead = configuredLead or defaultLead
    lead = math.max(4, math.min(15, lead))
    tracked.proactiveLead = lead
    local scheduledAt = GetTime and SafeNumber(GetTime()) or nil

    local function GetRemaining()
        if tracked.eventID and C_EncounterTimeline and type(C_EncounterTimeline.GetEventTimeRemaining) == "function" then
            local ok, value = pcall(C_EncounterTimeline.GetEventTimeRemaining, tracked.eventID)
            local remaining = ok and SafeNumber(value) or nil
            if remaining then
                return remaining
            end
        end
        -- Without a live timeline value, count down from the original duration.
        -- Returning the static duration would re-arm forever and never warn.
        local duration = SafeNumber(tracked.duration)
        local now = scheduledAt and GetTime and SafeNumber(GetTime())
        if duration and now then
            return duration - (now - scheduledAt)
        end
        return duration
    end

    local function Arm()
        if not self.timelineEvents or self.timelineEvents[tracked.eventID] ~= tracked then
            return
        end
        local remaining = GetRemaining()
        if not remaining then
            return
        end
        if remaining <= lead + 0.15 then
            tracked.proactiveTimer = nil
            self:HandleMidnightProactiveWarning(tracked)
            return
        end
        tracked.proactiveTimer = C_Timer.NewTimer(math.max(0.1, remaining - lead), Arm)
    end

    Arm()
    return true
end

function TankAssist:ScheduleMidnightMovementResolution(tracked, spec, rule)
    local delay = SafeNumber(spec and spec.activeDuration)
    if not delay or delay <= 0 or not C_Timer or type(C_Timer.NewTimer) ~= "function" then
        return false
    end
    self.midnightResolutionTimers = self.midnightResolutionTimers or {}
    local key = "movement:" .. tostring(tracked.eventID or tracked.action or (GetTime and GetTime() or 0))
    CancelTimer(self.midnightResolutionTimers[key])
    self.midnightResolutionTimers[key] = C_Timer.NewTimer(delay, function()
        self.midnightResolutionTimers[key] = nil
        if not self:ShouldRun() or not self.activeRule or self.activeRule.key ~= rule.key then
            return
        end
        if self.ClearMechanicCountdown then
            self:ClearMechanicCountdown(false, tracked.eventID)
        end
        if spec.resolveTitle then
            self:Alert(
                spec.resolveTitle,
                spec.resolveDetail,
                spec.resolveSpoken or "Move",
                rule.key .. ":movement:resolve:" .. tostring(tracked.eventID or tracked.action),
                true,
                rule,
                "movement"
            )
        end
    end)
    return true
end

function TankAssist:HandleMidnightMovement(tracked, rule)
    local spec = tracked and MOVEMENT_ACTIONS[tracked.action]
    if not spec or not self:IsWarningEnabled("movement")
        or not self:ShouldPlayerHandleMidnightMovement(tracked, spec, rule)
    then
        return false
    end

    if SafeNumber(spec.activeDuration) and self.ShowActiveMechanicCountdown then
        self:ShowActiveMechanicCountdown(tracked, spec.activeDuration, spec.zeroTitle, spec.zeroDetail, "movement")
        if self.PlayAlertSound and spec.zeroSpoken then
            self:PlayAlertSound(spec.zeroSpoken, "movement")
        end
        self:ScheduleMidnightMovementResolution(tracked, spec, rule)
        return true
    end

    return self:Alert(
        spec.zeroTitle or spec.preTitle or ("MOVE — " .. tostring(tracked.label or "POSITION")),
        spec.zeroDetail or spec.preDetail or "Finish the planned boss reposition now.",
        spec.zeroSpoken,
        rule.key .. ":movement:start:" .. tostring(tracked.eventID or tracked.action),
        spec.zeroSpoken ~= nil,
        rule,
        "movement"
    )
end

function TankAssist:HandleTimelineFinished(tracked)
    if not tracked or not self:IsMidnightLiveRule(self.activeRule) then
        if LegacyHandleTimelineFinished then
            return LegacyHandleTimelineFinished(self, tracked)
        end
        return
    end
    if not self:ShouldRun() or RC.db.profile.tankAssistUseCastRules == false
        or not self:IsRuleEnabled(self.activeRule)
    then
        return
    end

    local rule = self.activeRule
    if tracked.kind == "phase" then
        self.timelineState = self.timelineState or {}
        self.timelineState.ulatekStage = tracked.stage or self.timelineState.ulatekStage
        return
    end
    if tracked.kind == "movement" then
        self:HandleMidnightMovement(tracked, rule)
        return
    end
    if tracked.kind ~= "tank" then
        return
    end

    local meta = MECHANIC_META[rule.key] and MECHANIC_META[rule.key][tracked.label]
    CopyMeta(tracked, meta)

    -- Defensive-only mechanics have already produced a personal warning before
    -- their timeline reaches zero. Do not manufacture a taunt at mechanic start.
    if tracked.action == "defensive" then
        return
    end

    if rule.key == "ulatek" and tracked.label == "Mother's Wrath" then
        local stage = self.timelineState and self.timelineState.ulatekStage or 1
        if stage < 3 then
            return
        end
        tracked.action = "swap"
    end

    -- Fall back to the owner seen at the pre-hit defensive warning when the
    -- boss target cannot be read as the mechanic starts.
    local owner = self:GetTrackedOwner(tracked, rule) or tracked.ownerBeforeHit
    tracked.ownerAtStart = owner
    -- Snapshot the cross-swap direction at the start, like the owner: after
    -- the swap the holders flip and would point back the wrong way.
    if tracked.crossSwap then
        tracked.crossTargetUnit, tracked.crossTargetName = self:GetCrossSwapTarget()
    end

    if tracked.startOnly or tracked.action == "stonebreaker"
        or (tracked.action == "assignment" and not SafeNumber(tracked.resolveAfter))
    then
        self:ShowPersonalMechanicStart(tracked, owner, rule)
        return
    end

    self:ShowPersonalMechanicStart(tracked, owner, rule)
    self:ScheduleMidnightResolution(tracked, owner, rule)
end
