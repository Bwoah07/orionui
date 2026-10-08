local _, ns = ...
local RC = ns.RC
if not RC then return end -- standalone RaidControl is enabled
local TankAssist = RC:NewModule("TankAssist", "AceEvent-3.0")

local ALERT_WIDTH = 344
local ALERT_HEIGHT = 76
local STATUS_WIDTH = 344
local STATUS_HEIGHT = 54
local ALERT_DEFAULT_POS = { "CENTER", "UIParent", "CENTER", 0, 150 }
local STATUS_DEFAULT_POS = { "CENTER", "UIParent", "CENTER", 0, 84 }
local SOUND_ROOT = "Interface\\AddOns\\OrionUI\\RaidControl\\Media\\Sounds\\"
local MAX_AURAS = 40
local DEFENSIVE_WARNING_LEAD_SECONDS = 3
-- A tank must be the boss target this long before it counts as the owner.
local OWNER_STABLE_SECONDS = 1.0

local function CancelTimer(timer)
    if timer and type(timer.Cancel) == "function" then
        pcall(timer.Cancel, timer)
    end
end

local function ValueIsAccessible(value)
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

local function SafeText(value)
    if not ValueIsAccessible(value) or value == nil then
        return nil
    end
    local ok, text = pcall(tostring, value)
    if not ok or type(text) ~= "string" then
        return nil
    end
    return text
end

local function SafeBoolean(value)
    if not ValueIsAccessible(value) then
        return nil
    end
    local ok, valueType = pcall(type, value)
    if not ok or valueType ~= "boolean" then
        return nil
    end
    return value
end

local function SafeBooleanCall(api, ...)
    if type(api) ~= "function" then
        return nil
    end
    local ok, value = pcall(api, ...)
    if not ok then
        return nil
    end
    return SafeBoolean(value)
end

local function SafeUnitExists(unit)
    if not unit then
        return nil
    end
    return SafeBooleanCall(UnitExists, unit)
end

local function SafeUnitRole(unit)
    if type(UnitGroupRolesAssigned) ~= "function" then
        return nil
    end
    local ok, role = pcall(UnitGroupRolesAssigned, unit)
    return ok and SafeText(role) or nil
end

local function SafeLower(value)
    local text = SafeText(value)
    if not text then
        return ""
    end
    local ok, lowered = pcall(string.lower, text)
    return ok and lowered or ""
end

local function SafeNumber(value)
    if not ValueIsAccessible(value) then
        return nil
    end
    local ok, number = pcall(tonumber, value)
    return ok and number or nil
end

local function RoundNumber(value)
    value = SafeNumber(value)
    if not value then
        return nil
    end
    return math.floor(value + 0.5)
end

local function NameKey(name)
    name = SafeText(name)
    if not name or name == "" then
        return nil
    end
    if Ambiguate then
        local ok, shortName = pcall(Ambiguate, name, "none")
        shortName = ok and SafeText(shortName) or nil
        if shortName and shortName ~= "" then
            name = shortName
        end
    else
        name = name:match("^([^%-]+)") or name
    end
    return string.lower(name)
end

local function ShortNameKey(name)
    name = SafeText(name)
    if not name or name == "" then
        return nil
    end
    if Ambiguate then
        local ok, shortName = pcall(Ambiguate, name, "short")
        shortName = ok and SafeText(shortName) or nil
        if shortName and shortName ~= "" then
            name = shortName
        end
    end
    name = name:match("^([^%-]+)") or name
    return string.lower(name)
end

local function UnitFullNameSafe(unit)
    if not unit or SafeUnitExists(unit) ~= true then
        return nil
    end
    if UnitFullName then
        local ok, name, realm = pcall(UnitFullName, unit)
        name = ok and SafeText(name) or nil
        realm = ok and SafeText(realm) or nil
        if name and name ~= "" then
            if realm and realm ~= "" then
                return name .. "-" .. realm
            end
            return name
        end
    end
    if type(UnitName) == "function" then
        local ok, name = pcall(UnitName, unit)
        return ok and SafeText(name) or nil
    end
    return nil
end

local SOUND_LABELS = {
    voicepack = "RaidControl Voice Pack",
    custom = "Custom Sound File",
    tts = "Blizzard TTS",
    raid = "Raid Warning",
    ready = "Ready Check",
    bell = "Bell",
    none = "None",
}

local SOUND_ORDER = { "voicepack", "custom", "tts", "raid", "ready", "bell", "none" }

local SOUND_CHANNEL_LABELS = {
    Master = "Master",
    SFX = "Sound Effects",
    Dialog = "Dialog",
    Ambience = "Ambience",
    Music = "Music",
}

local ICON_LABELS = {
    skull = "Skull",
    cross = "Cross",
    square = "Square",
    moon = "Moon",
    triangle = "Triangle",
    diamond = "Diamond",
    circle = "Circle",
    star = "Star",
    shield = "Shield",
    warning = "Warning",
}

local ICON_DATA = {
    skull = { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
    cross = { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
    square = { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
    moon = { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
    triangle = { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
    diamond = { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
    circle = { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
    star = { texture = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
    shield = { texture = "Interface\\Icons\\Ability_Warrior_DefensiveStance", texCoord = { 0.08, 0.92, 0.08, 0.92 } },
    warning = { texture = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew", texCoord = { 0.08, 0.92, 0.08, 0.92 } },
}

-- BigWigs/LittleWigs v12.1.9 uses the purple message channel for these
-- tank mechanics in the official Midnight Season 2 Mythic+ pool. Listening
-- to its exact numeric keys avoids reading protected enemy targets or guessing
-- from localized spell names.
local MYTHIC_PLUS_TANK_BUSTERS = {
    -- Altar of Fangs
    [1307703] = { name = "Fresh Meat", dungeon = "Altar of Fangs" },
    [1298949] = { name = "Tail Scythe", dungeon = "Altar of Fangs" },
    [1301350] = { name = "Chop Down", dungeon = "Altar of Fangs" },
    -- Murder Row
    [473898] = { name = "Legion Strike", dungeon = "Murder Row" },
    [1222795] = { name = "Envenom", dungeon = "Murder Row" },
    -- The Blinding Vale
    [1234753] = { name = "Bedrock Slam", dungeon = "The Blinding Vale" },
    [1247685] = { name = "Thornspike", dungeon = "The Blinding Vale" },
    -- Voidscar Arena
    [1222642] = { name = "Hulking Claw", dungeon = "Voidscar Arena" },
    [1311923] = { name = "Dark Waves", dungeon = "Voidscar Arena" },
    [1297017] = { name = "Void Blast", dungeon = "Voidscar Arena" },
    -- King's Rest
    [265910] = { name = "Tail Thrash", dungeon = "King's Rest" },
    [266237] = { name = "Debilitating Backhand", dungeon = "King's Rest" },
    [268586] = { name = "Blade Combo", dungeon = "King's Rest" },
    [1303488] = { name = "Savage Maul", dungeon = "King's Rest" },
    -- Temple of Sethraliss
    [1311804] = { name = "Overload", dungeon = "Temple of Sethraliss" },
    [1290797] = { name = "Lightning Bite", dungeon = "Temple of Sethraliss" },
    -- Ruby Life Pools
    [372858] = { name = "Searing Blows", dungeon = "Ruby Life Pools" },
    [381512] = { name = "Stormslam", dungeon = "Ruby Life Pools" },
}

-- Spell IDs and timeline duration signatures are validated against the live
-- 12.1 encounter data and BigWigs Venomous Abyss v423. Private auras are labels only; addon logic never reads
-- or branches on values that Blizzard marks secret.
local BOSS_RULES = {
    {
        key = "imperator",
        encounterID = 3176,
        raid = "The Voidspire",
        name = "Imperator Averzian",
        aliases = { "imperator averzian", "averzian" },
        stackAuras = {
            { spellID = 1265540, name = "Blackening Wounds", private = true },
        },
        statusText = "Blackening Wounds is a private aura.",
        note = "Blackening Wounds is private in Midnight. RaidControl shows tank ownership but will not invent a stack count or an automatic taunt call.",
    },
    {
        key = "vorasius",
        encounterID = 3177,
        raid = "The Voidspire",
        name = "Vorasius",
        aliases = { "vorasius" },
        mechanic = "Shadowclaw Slam",
        timeline = "vorasius",
        action = "sequence",
        swapEvery = 2,
        stackAuras = {
            { spellID = 1241844, name = "Smashed", private = true },
        },
        tauntText = "TAUNT NOW",
        statusText = "Second Shadowclaw Slam triggers the swap check.",
        note = "The swap check fires after the second Shadowclaw Slam in each Primordial Roar cycle, using the live boss target to choose TAUNT NOW or SWAP OUT.",
    },
    {
        key = "vaelgor",
        encounterID = 3178,
        raid = "The Voidspire",
        name = "Vaelgor and Ezzorak",
        aliases = { "vaelgor", "ezzorak", "vaelgor and ezzorak", "vaelgor & ezzorak" },
        statusText = "Dual-boss target ownership only.",
        note = "This is an assignment-driven dual-boss encounter. RaidControl shows who is tanking but does not issue an unsafe generic taunt call.",
    },
    {
        key = "salhadaar",
        encounterID = 3179,
        raid = "The Voidspire",
        name = "Fallen-King Salhadaar",
        aliases = { "fallen-king salhadaar", "fallen king salhadaar", "salhadaar" },
        mechanic = "Shattering Twilight",
        timeline = "salhadaar",
        action = "assignment",
        stackAuras = {
            { spellID = 1253024, name = "Shattering Twilight", private = true },
            { spellID = 1268992, name = "Shattering Twilight", private = true },
            { spellID = 1271577, name = "Destabilizing Strikes", private = true },
        },
        tauntText = "TANK MECHANIC",
        statusText = "Shattering Twilight is timeline tracked.",
        note = "Shattering Twilight is tracked, but its tank debuffs are private. The warning is assignment-neutral instead of claiming a stack threshold.",
    },
    {
        key = "vanguard",
        encounterID = 3180,
        raid = "The Voidspire",
        name = "Lightblinded Vanguard",
        aliases = { "lightblinded vanguard", "vanguard", "bellamy", "venel", "senn" },
        statusText = "Three-boss assignment tracking.",
        note = "Judgement assignments depend on which Vanguard boss and color each tank owns. RaidControl shows target ownership without a misleading raid-wide taunt call.",
    },
    {
        key = "crown",
        encounterID = 3181,
        raid = "The Voidspire",
        name = "Crown of the Cosmos",
        aliases = { "crown of the cosmos", "alleria", "alleria windrunner" },
        stackAuras = {
            { spellID = 1246462, name = "Rift Slash", private = true },
        },
        statusText = "Phase-specific tank ownership tracking.",
        note = "Dark Hand, Rift Slash, and Simulacrum positioning vary by phase and assignment. RaidControl keeps the co-tank display active but avoids guessing the strategy.",
    },
    {
        key = "beloren",
        encounterID = 3182,
        raid = "March on Quel'Danas",
        name = "Belo'ren, Child of Al'ar",
        aliases = { "belo'ren", "beloren", "child of al'ar", "child of alar" },
        mechanic = "Guardian's Edict",
        timeline = "beloren",
        action = "assignment",
        tauntText = "TANK COMBO",
        statusText = "Guardian's Edict is timeline tracked.",
        note = "Guardian's Edict is color-assignment driven. RaidControl warns both tanks at the combo without pretending it can inspect private color auras.",
    },
    {
        key = "midnightfalls",
        encounterID = 3183,
        raid = "March on Quel'Danas",
        name = "Midnight Falls",
        aliases = { "midnight falls", "l'ura", "lura" },
        mechanic = "Heaven's Lance",
        timeline = "midnightfalls",
        action = "swap",
        tauntText = "TAUNT NOW",
        stackAuras = {
            { spellID = 1265842, name = "Impaled", private = true },
        },
        statusText = "Heaven's Lance swaps are timeline tracked.",
        note = "Heaven's Lance is tracked by phase and difficulty. The resolved call uses L'ura's current tank target.",
    },
    {
        key = "chimaerus",
        encounterID = 3306,
        raid = "The Dreamrift",
        name = "Chimaerus the Undreamt God",
        aliases = { "chimaerus", "undreamt god" },
        stackAuras = {
            { spellID = 1250953, name = "Rift Sickness", private = true },
        },
        statusText = "Group assignment encounter; no fixed taunt swap.",
        note = "Chimaerus uses split tank groups rather than a universal taunt swap. RaidControl shows co-tank state and leaves group timing to the raid plan.",
    },
    {
        key = "nymrissa",
        current = true,
        encounterID = 3379,
        raid = "The Tidebound Grotto",
        name = "Nymrissa Wavecaller",
        aliases = { "nymrissa wavecaller", "nymrissa" },
        mechanic = "Iceblade Flurry / Water Jet",
        timeline = "nymrissa",
        action = "swap",
        timelineMechanics = {
            { spellID = 1282937, name = "Iceblade Flurry", action = "swap", bossUnit = "boss1", resolveAfter = 7.0 },
            { spellID = 1268562, name = "Water Jet", action = "swap", difficulties = { 16 }, bossUnit = "boss1", resolveAfter = 6.0 },
        },
        tauntText = "TAUNT NOW",
        statusText = "World/Normal/Heroic: swap after Iceblade Flurry. Mythic: swap after Water Jet.",
        note = "Use a defensive for the active tank hit, then swap after it resolves. On Mythic, aim Water Jet through Lingering Frost before the trade.",
    },
    {
        key = "nekzali",
        current = true,
        encounterID = 3470,
        raid = "The Venomous Abyss",
        name = "Nek'zali the Soulcoiler",
        aliases = { "nek'zali", "nekzali", "soulcoiler" },
        mechanic = "Possession Barrage",
        timeline = "nekzali",
        action = "swap",
        timelineMechanics = {
            { spellID = 1292036, name = "Possession Barrage", action = "swap", bossUnit = "boss1", resolveAfter = 8.0 },
        },
        stackAuras = {
            { spellID = 1284109, name = "Hollowing Strikes", private = true },
        },
        statusText = "Swap after every Possession Barrage; 6-8 Hollowing stacks is advisory only.",
        note = "Use a defensive for Possession Barrage, then swap after it resolves. Hollowing Strikes reduces healing received by 5% per stack; 6-8 stacks reflects the guide range, but the stack is private and never drives the automatic call.",
    },
    {
        key = "sentinels",
        current = true,
        encounterID = 3445,
        raid = "The Venomous Abyss",
        name = "Entombed Sentinels",
        aliases = { "entombed sentinels", "sentinels" },
        mechanic = "Sentinel tank buster",
        timeline = "sentinels",
        action = "defensive",
        timelineMechanics = {
            { spellID = 1284458, name = "Empowering Slam", action = "defensive", bossUnit = "boss1" },
            { spellID = 1284487, name = "Bloodvenom Injection", action = "defensive", bossUnit = "boss2" },
            { spellID = 1284588, name = "Vitriolic Stasis", action = "assignment", label = "Vitriolic Stasis", defensive = false },
        },
        stackAuras = {
            { spellID = 1284491, name = "Bloodvenom Injection", private = true },
        },
        tauntText = "SWAP SENTINELS",
        statusText = "Defensive warnings track both busters; trade Sentinels after Stasis.",
        note = "Empowering Slam and Bloodvenom Injection are defensive checks, not automatic cross-room taunts. Trade Sentinels after each Vitriolic Stasis so Bloodvenom stacks can expire.",
    },
    {
        key = "explorers",
        current = true,
        encounterID = 3497,
        raid = "The Venomous Abyss",
        name = "The Lost Explorers",
        aliases = { "the lost explorers", "lost explorers", "explorers" },
        mechanic = "Shredding Shards",
        timeline = "explorers",
        action = "swap",
        timelineMechanics = {
            { spellID = 1295854, name = "Shredding Shards", action = "cross-swap", bossUnit = "boss4", resolveAfter = 3.5 },
        },
        stackAuras = {
            { spellID = 1295858, name = "Shredding Shards", private = true },
        },
        tauntText = "SWAP AFTER SHREDDING SHARDS",
        statusText = "Finish the full Shredding Shards sequence, then cross-taunt Iku/Nama. Never taunt Gebbo.",
        note = "The same assignments hold for the complete Shredding Shards sequence. When it finishes, Iku's tank takes Nama and Nama's tank takes Iku; Gebbo is never the taunt target.",
    },
    {
        key = "vashnik",
        current = true,
        encounterID = 3455,
        raid = "The Venomous Abyss",
        name = "Vashnik the Malignant",
        aliases = { "vashnik the malignant", "vashnik" },
        mechanic = "Dripping Fangs",
        timeline = "vashnik",
        action = "swap",
        timelineMechanics = {
            { spellID = 1280935, name = "Dripping Fangs", action = "swap", bossUnit = "boss1", resolveAfter = 2.0 },
        },
        stackAuras = {
            { spellID = 1280934, name = "Dripping Fangs", private = true },
        },
        tauntText = "TAUNT NOW",
        statusText = "Dripping Fangs swaps are timeline tracked.",
        note = "Use a defensive for Dripping Fangs, then hard-swap after every cast. RaidControl snapshots the tank owner when the mechanic begins so a fast correct taunt cannot reverse the call.",
    },
    {
        key = "sszorak",
        current = true,
        encounterID = 3420,
        raid = "The Venomous Abyss",
        name = "Sszorak",
        aliases = { "sszorak" },
        mechanic = "Apex Predator",
        timeline = "sszorak",
        action = "assignment",
        timelineMechanics = {
            { spellID = 1277025, name = "Apex Predator", action = "assignment" },
        },
        stackAuras = {
            { spellID = 1277105, name = "Ravage", private = true },
        },
        tauntText = "APEX ASSIGNMENT",
        statusText = "Apex Predator: each tank takes one Ravage and one Mutilate; Tempest never triggers a taunt.",
        note = "Apex Predator is treated as a tank assignment, not a blind taunt trigger: each tank takes one Ravage and one Mutilate, while Tempest never causes a swap call. Private Corroding Venom values are never guessed.",
    },
    {
        key = "twinfangs",
        current = true,
        encounterID = 3421,
        raid = "The Venomous Abyss",
        name = "The Twin Fangs",
        aliases = { "the twin fangs", "twin fangs" },
        mechanic = "Twin Fangs tank mechanic",
        timeline = "twinfangs",
        action = "swap",
        timelineMechanics = {
            { spellID = 1289192, name = "Caustic Deluge", action = "swap", resolveAfter = 5.0 },
            { spellID = 1288538, name = "Stone Breaker", action = "stonebreaker", defensive = false },
        },
        stackAuras = {
            { spellID = 1289092, name = "Stone Breaker", private = true },
        },
        tauntText = "TAUNT NOW",
        statusText = "Vexhul swaps after Caustic Deluge; Ithraz is held through all three Stone Breaker impacts before the exchange.",
        note = "RaidControl binds each mechanic to the correct boss: hold Vexhul for the full Caustic Deluge, then swap; hold Ithraz through all three Stone Breaker impacts and exchange only after 3/3. Ambiguous repeating timeline buckets are ignored rather than guessed.",
    },
    {
        key = "coiledaltar",
        current = true,
        encounterID = 3429,
        raid = "The Venomous Abyss",
        name = "The Coiled Altar",
        aliases = { "the coiled altar", "coiled altar" },
        mechanic = "Sever",
        timeline = "coiledaltar",
        action = "swap",
        timelineMechanics = {
            { spellID = 1299680, name = "Sever", action = "swap", bossName = "zul\'jan", resolveAfter = 3.5 },
            { spellID = 1286573, name = "Soul Sever", action = "swap", bossName = "malacrass", resolveAfter = 3.5 },
            { spellID = 1307279, name = "Blighted Sever", action = "swap", bossName = "zul\'jan", resolveAfter = 3.5 },
        },
        stackAuras = {
            { spellID = 1283345, name = "Twinfang Toxin", private = true },
            { spellID = 1298795, name = "Corrupted Toxin", private = true },
        },
        tauntText = "TAUNT NOW",
        statusText = "Swap after every Sever, Soul Sever, and Blighted Sever.",
        note = "Use a defensive for each phase-specific tank hit, then swap after it resolves: Sever in phase 1, Soul Sever in phase 2, and Blighted Sever in phase 3.",
    },
    {
        key = "ulatek",
        current = true,
        encounterID = 3492,
        raid = "The Venomous Abyss",
        name = "Ula'tek",
        aliases = { "ula'tek", "ulatek" },
        mechanic = "Caustic Waves / Mother's Wrath",
        timeline = "ulatek",
        action = "swap",
        phaseStateKey = "ulatekStage",
        timelineMechanics = {
            { spellID = 1292188, name = "Caustic Waves", action = "swap", defensive = false, phases = { 1 } },
            { spellID = 1292403, name = "Caustic Waves", action = "swap", defensive = false, phases = { 1 } },
            { spellID = 1298367, name = "Mother's Wrath", action = "defensive", phases = { 1, 2, 2.5 } },
            { spellID = 1298367, name = "Mother's Wrath", action = "swap", phases = { 3 } },
        },
        stackAuras = {
            { spellID = 1298417, name = "Stone Venom", private = true },
        },
        tauntText = "TAUNT NOW",
        statusText = "Phase 1: trade during Caustic Waves. Phase 3: trade after Mother's Wrath.",
        note = "Phase 1 Mother's Wrath is a defensive-only warning; trade as Caustic Waves begins. In phase 3, use a defensive for Mother's Wrath and swap after it resolves. Private Stone Venom values are never read or guessed.",
    },
}

local RULES_BY_ENCOUNTER = {}
for _, rule in ipairs(BOSS_RULES) do
    RULES_BY_ENCOUNTER[rule.encounterID] = rule
end

local function IsBossUnit(unit)
    return type(unit) == "string" and unit:match("^boss%d+$") ~= nil
end

local function SafeNow()
    return type(GetTime) == "function" and SafeNumber(GetTime()) or 0
end

local function UnitIsDeadSafe(unit)
    if not unit then
        return nil
    end
    return SafeBooleanCall(UnitIsDeadOrGhost, unit)
end

local function RuleMatches(rule, encounterName)
    local lower = SafeLower(encounterName)
    if lower == "" then
        return false
    end
    for _, alias in ipairs(rule.aliases or {}) do
        if string.find(lower, alias, 1, true) then
            return true
        end
    end
    return false
end

function TankAssist:OnInitialize()
    self.activeRule = nil
    self.activeEncounter = nil
    self.activeEncounterID = nil
    self.activeDifficultyID = nil
    self.coTankUnit = nil
    self.coTankName = nil
    self.lastAlerts = {}
    self.timelineEvents = {}
    self.timelineState = {}
    self.mythicPlusBusterTimers = {}
    self._bigWigsCallbackRegistered = false
end

function TankAssist:OnEnable()
    -- Register all AceEvent subscriptions exactly once during module enable.
    -- Midnight can reject protected Frame:RegisterEvent calls made later from a
    -- tainted ADDON_LOADED/settings execution path, so ApplyEnabledState must
    -- never register or unregister events dynamically.
    self:RegisterEvent("ADDON_LOADED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_ROLES_ASSIGNED")
    self:RegisterEvent("ENCOUNTER_START")
    self:RegisterEvent("ENCOUNTER_END")
    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("UNIT_TARGET")
    self:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
    self:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED")
    self:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED")
    self:RegisterEvent("ENCOUNTER_TIMELINE_EVENT_REMOVED")
    self:ApplyEnabledState()
end

function TankAssist:OnDisable()
    self:UnregisterBigWigsCallbacks()
    self:CancelMythicPlusBusterTimers()
    self:HideFrames()
end

function TankAssist:GetRules()
    return BOSS_RULES
end

function TankAssist:GetMythicPlusTankBusters()
    return MYTHIC_PLUS_TANK_BUSTERS
end

function TankAssist:GetJournalBossRules()
    if SafeBooleanCall(InCombatLockdown) == true and self._journalBossRules then
        return self._journalBossRules
    end
    local bossNotes = RC.GetModule and RC:GetModule("BossNotes", true)
    if not bossNotes or type(bossNotes.GetBossNotesRaidData) ~= "function" then
        return self._journalBossRules or {}
    end
    local ok, raidData = pcall(bossNotes.GetBossNotesRaidData, bossNotes)
    if not ok or type(raidData) ~= "table" then
        return self._journalBossRules or {}
    end

    local rules = {}
    for _, raid in ipairs(raidData) do
        if raid.key ~= "custom" then
            for _, boss in ipairs(raid.bosses or {}) do
                local encounterID = SafeNumber(boss.encounterID)
                local name = SafeText(boss.name)
                if name and name ~= "" and not (encounterID and RULES_BY_ENCOUNTER[encounterID]) then
                    local slug = SafeLower(name):gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
                    rules[#rules + 1] = {
                        key = encounterID and ("journal:" .. tostring(encounterID)) or ("journal:" .. slug),
                        encounterID = encounterID,
                        raid = SafeText(raid.name) or "Midnight",
                        name = name,
                        aliases = { SafeLower(name) },
                        statusText = "Tank target ownership tracking.",
                        note = "This Midnight boss is available from the Encounter Journal. Co-tank ownership is tracked, but automatic swap calls wait for a verified boss rule.",
                        journalOnly = true,
                    }
                end
            end
        end
    end
    self._journalBossRules = rules
    return rules
end

function TankAssist:GetSoundList()
    if RC.GetSharedMediaSoundOptions then
        return RC:GetSharedMediaSoundOptions(SOUND_LABELS, SOUND_ORDER)
    end
    return SOUND_LABELS, SOUND_ORDER
end

function TankAssist:GetSoundOrder()
    local _, order = self:GetSoundList()
    return order
end

function TankAssist:GetSoundChannelList()
    return SOUND_CHANNEL_LABELS
end

function TankAssist:GetIconList()
    return ICON_LABELS
end

function TankAssist:GetRuleIconData(rule)
    return ICON_DATA[self:GetRuleIconKey(rule)] or ICON_DATA.skull
end

function TankAssist:GetBossList()
    local bosses = {}
    for _, rule in ipairs(BOSS_RULES) do
        if rule.current then
            bosses[rule.key] = rule.raid .. ": " .. rule.name
        end
    end
    for _, rule in ipairs(self:GetJournalBossRules()) do
        bosses[rule.key] = rule.raid .. ": " .. rule.name .. " (status only)"
    end
    return bosses
end

function TankAssist:GetRuleByKey(key)
    for _, rule in ipairs(BOSS_RULES) do
        if rule.key == key then
            return rule
        end
    end
    for _, rule in ipairs(self:GetJournalBossRules()) do
        if rule.key == key then
            return rule
        end
    end
    return BOSS_RULES[1]
end

function TankAssist:FindRule(encounterID, encounterName)
    encounterID = SafeNumber(encounterID)
    if encounterID then
        if RULES_BY_ENCOUNTER[encounterID] then
            return RULES_BY_ENCOUNTER[encounterID]
        end
        for _, rule in ipairs(self:GetJournalBossRules()) do
            if rule.encounterID == encounterID then
                return rule
            end
        end
        return nil
    end
    for _, rule in ipairs(BOSS_RULES) do
        if RuleMatches(rule, encounterName) then
            return rule
        end
    end
    for _, rule in ipairs(self:GetJournalBossRules()) do
        if RuleMatches(rule, encounterName) then
            return rule
        end
    end
    return nil
end

function TankAssist:GetRuleConfig(ruleOrKey)
    local profile = RC.db and RC.db.profile or {}
    profile.tankAssistBossOverrides = profile.tankAssistBossOverrides or {}
    local key = type(ruleOrKey) == "table" and ruleOrKey.key or ruleOrKey
    key = key or BOSS_RULES[1].key
    profile.tankAssistBossOverrides[key] = profile.tankAssistBossOverrides[key] or {}
    local config = profile.tankAssistBossOverrides[key]
    if config.enabled == nil then
        config.enabled = true
    end
    return config
end

function TankAssist:IsRuleEnabled(rule)
    return rule and self:GetRuleConfig(rule).enabled ~= false or false
end

function TankAssist:GetSwapEvery(rule)
    local configured = SafeNumber(self:GetRuleConfig(rule).swapEvery)
    return math.max(1, math.floor(configured or rule.swapEvery or 1))
end

function TankAssist:GetRuleAlertText(rule, fallback)
    local text = rule and SafeText(self:GetRuleConfig(rule).tauntText)
    return text and text ~= "" and text or fallback
end

function TankAssist:GetDefaultAlertText(rule)
    if not rule then
        return "TANK CHECK"
    end
    if rule.tauntText then
        return rule.tauntText
    end
    if rule.action == "assignment" then
        return "TANK MECHANIC"
    end
    if rule.action == "swap" or rule.action == "sequence" then
        return "TAUNT NOW"
    end
    return "TANK STATUS"
end

function TankAssist:GetRuleIconKey(rule)
    local profile = RC.db and RC.db.profile or {}
    local config = rule and self:GetRuleConfig(rule) or nil
    local key = config and SafeText(config.icon) or nil
    key = key and key ~= "" and key or profile.tankAssistAlertIcon
    return ICON_DATA[key] and key or "skull"
end

function TankAssist:IsEnabled()
    return RC.db and RC.db.profile and RC.db.profile.enableTankAssist == true
end

function TankAssist:IsRaidInstance()
    if type(GetInstanceInfo) ~= "function" then
        return false
    end
    local ok, _, instanceType = pcall(GetInstanceInfo)
    return ok and ValueIsAccessible(instanceType) and instanceType == "raid"
end

function TankAssist:IsPartyInstance()
    if type(GetInstanceInfo) ~= "function" then
        return false
    end
    local ok, _, instanceType = pcall(GetInstanceInfo)
    return ok and ValueIsAccessible(instanceType) and instanceType == "party"
end

function TankAssist:IsMythicPlusActive()
    if not C_ChallengeMode or type(C_ChallengeMode.IsChallengeModeActive) ~= "function" then
        return false
    end
    return SafeBooleanCall(C_ChallengeMode.IsChallengeModeActive) == true
end

function TankAssist:IsPlayerTank()
    if SafeUnitRole("player") == "TANK" then
        return true
    end
    local spec
    if type(GetSpecialization) == "function" then
        local ok, value = pcall(GetSpecialization)
        spec = ok and SafeNumber(value) or nil
    end
    if spec and type(GetSpecializationInfo) == "function" then
        local ok, _, _, _, _, role = pcall(GetSpecializationInfo, spec)
        if ok and SafeText(role) == "TANK" then
            return true
        end
    end
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecializationInfo then
        local ok, value = pcall(C_SpecializationInfo.GetSpecialization)
        spec = ok and SafeNumber(value) or nil
        if spec then
            local infoOK, _, _, _, _, role = pcall(C_SpecializationInfo.GetSpecializationInfo, spec)
            return infoOK and SafeText(role) == "TANK"
        end
    end
    return false
end

function TankAssist:ShouldRun()
    local profile = RC.db and RC.db.profile or {}
    if not self:IsEnabled() then
        return false
    end
    if profile.tankAssistTanksOnly ~= false and not self:IsPlayerTank() then
        return false
    end
    if not self:IsRaidInstance() then
        return false
    end
    if SafeBooleanCall(IsInRaid) ~= true then
        return false
    end
    if profile.tankAssistEncounterOnly ~= false and not self.activeEncounter then
        return false
    end
    if not self.activeRule or not self:IsRuleEnabled(self.activeRule) then
        return false
    end
    return true
end

function TankAssist:ShouldRunMythicPlusBusters()
    local profile = RC.db and RC.db.profile or {}
    return self:IsEnabled()
        and profile.tankAssistEnableDungeonBusters ~= false
        and self:IsPlayerTank()
        and self:IsPartyInstance()
        and self:IsMythicPlusActive()
end

local ACTIVE_EVENTS = {
    "UNIT_AURA",
    "UNIT_TARGET",
    "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "ENCOUNTER_TIMELINE_EVENT_ADDED",
    "ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED",
    "ENCOUNTER_TIMELINE_EVENT_REMOVED",
}

function TankAssist:ApplyEnabledState()
    -- Event subscriptions are intentionally static (registered in OnEnable).
    -- Only behavior/UI changes here; this keeps settings and ADDON_LOADED paths
    -- from touching protected AceEvent30Frame:RegisterEvent in Midnight.
    if self:IsEnabled() then
        self:RegisterBigWigsCallbacks()
        self:GetJournalBossRules()
        self:CreateAlertFrame()
        self:CreateStatusFrame()
        self:ApplyFrameSettings()
        self:RefreshCoTank()
        self:RefreshStatus()
    else
        self:UnregisterBigWigsCallbacks()
        self:CancelMythicPlusBusterTimers()
        self:HideFrames()
    end
end

function TankAssist:RegisterBigWigsCallbacks()
    if self._bigWigsCallbackRegistered then
        return true
    end
    if type(BigWigsLoader) ~= "table" or type(BigWigsLoader.RegisterMessage) ~= "function" then
        return false
    end

    local owner = self._bigWigsCallbackOwner or {}
    self._bigWigsCallbackOwner = owner
    local callbacks = {
        BigWigs_Timer = function(_, module, key, duration, maxDuration, text)
            self:OnBigWigsTimer(module, key, duration, maxDuration, text)
        end,
        BigWigs_Message = function(_, module, key, text, color)
            self:OnBigWigsMessage(module, key, text, color)
        end,
        BigWigs_StopBar = function(_, module, text)
            self:CancelMythicPlusBusterTimer(module, text)
        end,
        BigWigs_StopBars = function(_, module)
            self:CancelMythicPlusBusterTimers(module)
        end,
    }

    for message, callback in pairs(callbacks) do
        local ok = pcall(BigWigsLoader.RegisterMessage, owner, message, callback)
        if not ok then
            if type(BigWigsLoader.UnregisterMessage) == "function" then
                for registeredMessage in pairs(callbacks) do
                    pcall(BigWigsLoader.UnregisterMessage, owner, registeredMessage)
                end
            end
            return false
        end
    end
    self._bigWigsCallbackRegistered = true
    return true
end

function TankAssist:UnregisterBigWigsCallbacks()
    local owner = self._bigWigsCallbackOwner
    if owner and type(BigWigsLoader) == "table" and type(BigWigsLoader.UnregisterMessage) == "function" then
        for _, message in ipairs({ "BigWigs_Timer", "BigWigs_Message", "BigWigs_StopBar", "BigWigs_StopBars" }) do
            pcall(BigWigsLoader.UnregisterMessage, owner, message)
        end
    end
    self._bigWigsCallbackRegistered = false
end

function TankAssist:GetMythicPlusBusterTimerKey(spellID, text)
    local safeText = SafeText(text)
    return safeText and safeText ~= "" and safeText or ("spell:" .. tostring(spellID))
end

function TankAssist:CancelMythicPlusBusterTimer(module, text)
    local bucket = self.mythicPlusBusterTimers and self.mythicPlusBusterTimers[module or self]
    local safeText = SafeText(text)
    if not bucket or not safeText then
        return false
    end
    local timer = bucket[safeText]
    if not timer then
        return false
    end
    CancelTimer(timer)
    bucket[safeText] = nil
    return true
end

function TankAssist:CancelMythicPlusBusterTimers(module)
    local timers = self.mythicPlusBusterTimers or {}
    if module then
        local bucket = timers[module]
        for _, timer in pairs(bucket or {}) do
            CancelTimer(timer)
        end
        timers[module] = nil
        return
    end
    for _, bucket in pairs(timers) do
        for _, timer in pairs(bucket or {}) do
            CancelTimer(timer)
        end
    end
    self.mythicPlusBusterTimers = {}
end

function TankAssist:FireMythicPlusBuster(spellID, lead)
    local buster = MYTHIC_PLUS_TANK_BUSTERS[SafeNumber(spellID)]
    if not buster or not self:ShouldRunMythicPlusBusters() then
        return false
    end
    local detail = "Use active mitigation or a defensive for " .. buster.name
    if lead and lead > 0 then
        detail = detail .. " in about " .. tostring(lead) .. " seconds."
    else
        detail = detail .. "."
    end
    return self:Alert(
        "DEFENSIVE NOW",
        detail,
        "Defensive",
        "mplus:defensive:" .. tostring(spellID),
        true,
        nil,
        "defensive"
    )
end

function TankAssist:OnBigWigsTimer(module, key, duration, maxDuration, text)
    local spellID = SafeNumber(key)
    local buster = spellID and MYTHIC_PLUS_TANK_BUSTERS[spellID]
    if not buster or not self:ShouldRunMythicPlusBusters()
        or not C_Timer or type(C_Timer.NewTimer) ~= "function"
    then
        return false
    end
    duration = SafeNumber(duration)
    if not duration or duration < 0 or duration > 180 then
        return false
    end

    local profile = RC.db and RC.db.profile or {}
    local lead = math.max(1, math.min(8, SafeNumber(profile.tankAssistDefensiveLeadSeconds)
        or DEFENSIVE_WARNING_LEAD_SECONDS))
    local moduleKey = module or self
    local timerKey = self:GetMythicPlusBusterTimerKey(spellID, text)
    self.mythicPlusBusterTimers = self.mythicPlusBusterTimers or {}
    self.mythicPlusBusterTimers[moduleKey] = self.mythicPlusBusterTimers[moduleKey] or {}
    local bucket = self.mythicPlusBusterTimers[moduleKey]
    CancelTimer(bucket[timerKey])

    local timer
    timer = C_Timer.NewTimer(math.max(0, duration - lead), function()
        if bucket[timerKey] == timer then
            bucket[timerKey] = nil
            self:FireMythicPlusBuster(spellID, lead)
        end
    end)
    bucket[timerKey] = timer
    return true
end

function TankAssist:OnBigWigsMessage(module, key, text, color)
    local spellID = SafeNumber(key)
    if SafeLower(color) ~= "purple" or not spellID or not MYTHIC_PLUS_TANK_BUSTERS[spellID] then
        return false
    end
    self:CancelMythicPlusBusterTimer(module, text)
    return self:FireMythicPlusBuster(spellID)
end

function TankAssist:RefreshRuntimeSettings()
    if RC.db and RC.db.profile and RC.db.profile.tankAssistUseCastRules == false then
        self.timelineEvents = {}
    end
    if RC.db and RC.db.profile and RC.db.profile.tankAssistEnableDungeonBusters == false then
        self:CancelMythicPlusBusterTimers()
    end
    self:ApplyFrameSettings()
    if self.UpdateUpcomingTimerBars then
        self:UpdateUpcomingTimerBars(true)
    end
    self:RefreshStatus()
end

function TankAssist:SaveFramePosition(frame)
    if not frame or not frame._positionKey or not RC.db or not RC.db.profile then
        return
    end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    RC.db.profile[frame._positionKey] = { point, "UIParent", relativePoint, x, y }
end

function TankAssist:ConfigureMovableFrame(frame, positionKey, defaultPosition)
    frame._positionKey = positionKey
    frame._defaultPosition = defaultPosition
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(target)
        local profile = RC.db and RC.db.profile or {}
        local unlocked = profile.tankAssistFramesLocked == false
            or (RC.IsUILayoutUnlocked and RC:IsUILayoutUnlocked())
        if unlocked then
            target.rcMoving = true
            target:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(target)
        if not target.rcMoving then return end
        target.rcMoving = nil
        target:StopMovingOrSizing()
        self:SaveFramePosition(target)
    end)
end

function TankAssist:ApplySingleFrameSettings(frame)
    if not frame then
        return
    end
    local profile = RC.db and RC.db.profile or {}
    local scale = math.max(0.5, math.min(2, SafeNumber(profile.tankAssistFrameScale) or 1))
    local alpha = math.max(0.2, math.min(1, SafeNumber(profile.tankAssistFrameAlpha) or 1))
    local position = profile[frame._positionKey] or frame._defaultPosition
    frame:SetAlpha(alpha)
    local unlocked = profile.tankAssistFramesLocked == false
        or (RC.IsUILayoutUnlocked and RC:IsUILayoutUnlocked())
    frame:EnableMouse(unlocked and true or false)
    if not frame._rcPositionReady then
        frame:SetScale(scale)
        frame:ClearAllPoints()
        frame:SetPoint(
            position and position[1] or "CENTER",
            UIParent,
            position and position[3] or "CENTER",
            position and position[4] or 0,
            position and position[5] or 0
        )
        frame._rcPositionReady = true
    else
        if RC.SetScalePreserveCenter then
            RC:SetScalePreserveCenter(frame, scale, function(target)
                self:SaveFramePosition(target)
            end)
        else
            frame:SetScale(scale)
        end
    end
end

function TankAssist:ApplyFrameScale(rawScale)
    local profile = RC.db and RC.db.profile or {}
    local scale = math.max(0.5, math.min(2, SafeNumber(rawScale) or 1))
    profile.tankAssistFrameScale = scale
    for _, frame in pairs({ self.frame, self.statusFrame, self.timerFrame }) do
        if frame then
            if not frame._rcPositionReady then
                self:ApplySingleFrameSettings(frame)
            else
                if RC.SetScalePreserveCenter then
                    RC:SetScalePreserveCenter(frame, scale, function(target)
                        self:SaveFramePosition(target)
                    end)
                else
                    frame:SetScale(scale)
                end
            end
        end
    end
    return scale
end

function TankAssist:ApplyFrameSettings()
    self:ApplySingleFrameSettings(self.frame)
    self:ApplySingleFrameSettings(self.statusFrame)
    self:ApplySingleFrameSettings(self.timerFrame)
    if self.ApplyTankAssistVisualSettings then
        self:ApplyTankAssistVisualSettings()
    end
    if self.UpdateUpcomingTimerBars then
        self:UpdateUpcomingTimerBars(true)
    end
end

function TankAssist:ResetFramePositions()
    if not RC.db or not RC.db.profile then
        return
    end
    RC.db.profile.tankAssistAlertPos = { "CENTER", "UIParent", "CENTER", 0, 150 }
    RC.db.profile.tankAssistStatusPos = { "CENTER", "UIParent", "CENTER", 0, 84 }
    RC.db.profile.tankAssistTimerPos = { "CENTER", "UIParent", "CENTER", 0, 55 }
    if self.frame then self.frame._rcPositionReady = nil end
    if self.statusFrame then self.statusFrame._rcPositionReady = nil end
    if self.timerFrame then self.timerFrame._rcPositionReady = nil end
    self:ApplyFrameSettings()
end

function TankAssist:CreateAlertFrame()
    if self.frame or not CreateFrame then
        return
    end

    local frame = CreateFrame("Frame", "RaidControlTankAssistAlert", UIParent, "BackdropTemplate")
    frame:SetSize(ALERT_WIDTH, ALERT_HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(600)
    frame:Hide()
    RC:SkinFrame(frame)
    RC:ApplyThemedWindow(frame, "window")

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(42, 42)
    icon:SetPoint("LEFT", frame, "LEFT", 16, 0)
    frame.icon = icon

    local title = frame:CreateFontString(nil, "OVERLAY")
    RC:SetFont(title, 20, "OUTLINE")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 4)
    title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -10)
    title:SetJustifyH("LEFT")
    title:SetText("TAUNT NOW")
    frame.title = title

    local detail = frame:CreateFontString(nil, "OVERLAY")
    RC:SetFont(detail, 11, "OUTLINE")
    detail:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -22)
    detail:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -42)
    detail:SetJustifyH("LEFT")
    detail:SetText("")
    frame.detail = detail

    self.frame = frame
    self:ConfigureMovableFrame(frame, "tankAssistAlertPos", ALERT_DEFAULT_POS)
    self:ApplySingleFrameSettings(frame)
    self:ApplyAlertIcon()
    self:RefreshTheme()
end

function TankAssist:CreateStatusFrame()
    if self.statusFrame or not CreateFrame then
        return
    end

    local frame = CreateFrame("Frame", "RaidControlTankAssistStatus", UIParent, "BackdropTemplate")
    frame:SetSize(STATUS_WIDTH, STATUS_HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(200)
    frame:Hide()
    RC:SkinFrame(frame)
    RC:ApplyThemedWindow(frame, "window")

    local name = frame:CreateFontString(nil, "OVERLAY")
    RC:SetFont(name, 12, "OUTLINE")
    name:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -9)
    name:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -112, -9)
    name:SetJustifyH("LEFT")
    name:SetHeight(14)
    if name.SetWordWrap then
        name:SetWordWrap(false)
    end
    frame.name = name

    local target = frame:CreateFontString(nil, "OVERLAY")
    RC:SetFont(target, 11, "OUTLINE")
    target:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
    target:SetWidth(96)
    target:SetHeight(14)
    target:SetJustifyH("RIGHT")
    if target.SetWordWrap then
        target:SetWordWrap(false)
    end
    frame.target = target

    local detail = frame:CreateFontString(nil, "OVERLAY")
    RC:SetFont(detail, 11, "OUTLINE")
    detail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 9)
    detail:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 9)
    detail:SetJustifyH("LEFT")
    detail:SetHeight(14)
    if detail.SetWordWrap then
        detail:SetWordWrap(false)
    end
    frame.detail = detail

    self.statusFrame = frame
    self:ConfigureMovableFrame(frame, "tankAssistStatusPos", STATUS_DEFAULT_POS)
    self:ApplySingleFrameSettings(frame)
    self:RefreshTheme()
end

function TankAssist:ApplyAlertIcon(rule)
    if not self.frame or not self.frame.icon then
        return
    end
    local icon = ICON_DATA[self:GetRuleIconKey(rule)] or ICON_DATA.skull
    self.frame.icon:SetTexture(icon.texture)
    if icon.texCoord then
        self.frame.icon:SetTexCoord(icon.texCoord[1], icon.texCoord[2], icon.texCoord[3], icon.texCoord[4])
    else
        self.frame.icon:SetTexCoord(0, 1, 0, 1)
    end
end

function TankAssist:RefreshTheme()
    local warning = RC.Config.WarningColor
    local textColor = RC.Config.Text or RC.Config.WhiteText
    for _, frame in ipairs({ self.frame, self.statusFrame }) do
        if frame then
            RC:ApplyThemedWindow(frame, "window")
            frame:SetBackdropBorderColor(
                RC.Config.NavSelectedBorder.r,
                RC.Config.NavSelectedBorder.g,
                RC.Config.NavSelectedBorder.b,
                RC.Config.NavSelectedBorder.a or 1
            )
        end
    end
    if self.frame then
        self.frame.title:SetTextColor(warning.r, warning.g, warning.b, warning.a or 1)
        self.frame.detail:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a or 1)
    end
    if self.statusFrame then
        self.statusFrame.name:SetTextColor(textColor.r, textColor.g, textColor.b, textColor.a or 1)
        self.statusFrame.detail:SetTextColor(textColor.r, textColor.g, textColor.b, 0.85)
    end
end

function TankAssist:HideFrames()
    self._tankTimerPreviewActive = nil
    self._tankTimerPreviewExpires = nil
    self.activeHUDMechanics = {}
    if self.StopAlertHUDTimer then self:StopAlertHUDTimer() end
    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end
    if self.layoutPreviewTimer then
        self.layoutPreviewTimer:Cancel()
        self.layoutPreviewTimer = nil
    end
    if self.frame then
        self.frame:Hide()
    end
    if self.statusFrame then
        self.statusFrame:Hide()
    end
    if self.timerFrame then
        self.timerFrame:Hide()
    end
end

function TankAssist:ADDON_LOADED()
    if self:IsEnabled() and not self._bigWigsCallbackRegistered then
        self:RegisterBigWigsCallbacks()
    end
end

function TankAssist:PLAYER_ENTERING_WORLD()
    self:CancelMythicPlusBusterTimers()
    if not self:IsRaidInstance() then
        self.activeRule = nil
        self.activeEncounter = nil
        self.activeEncounterID = nil
        self.activeDifficultyID = nil
        self.coTankUnit = nil
        self.coTankName = nil
        self:ResetEncounterState()
        self:HideFrames()
    end
    self:ApplyEnabledState()
end

function TankAssist:GROUP_ROSTER_UPDATE()
    self:RefreshCoTank()
    self:RefreshStatus()
end

function TankAssist:PLAYER_ROLES_ASSIGNED()
    self:RefreshCoTank()
    self:RefreshStatus()
end

function TankAssist:INSTANCE_ENCOUNTER_ENGAGE_UNIT()
    self:ForgetMissingBossHolders()
    self:RefreshStatus()
end

function TankAssist:ResetEncounterState()
    self.activeHUDMechanics = {}
    if self.StopAlertHUDTimer then self:StopAlertHUDTimer() end
    for _, tracked in pairs(self.timelineEvents or {}) do
        CancelTimer(tracked and tracked.defensiveTimer)
    end
    self.timelineEvents = {}
    self.bossHolders = {}
    self.timelineState = {
        vorasiusSlamCount = 0,
        salhadaarFortyFiveCount = 0,
        midnightStage = 1,
        ulatekStage = 1,
        durationCounts = {},
    }
    self.lastAlerts = {}
end

function TankAssist:ENCOUNTER_START(event, encounterID, encounterName, difficultyID)
    local rule = self:IsRaidInstance() and self:FindRule(encounterID, encounterName) or nil
    self.activeRule = self:IsRuleEnabled(rule) and rule or nil
    self.activeEncounterID = self.activeRule and SafeNumber(encounterID) or nil
    self.activeEncounter = self.activeRule and SafeText(encounterName) or nil
    self.activeDifficultyID = self.activeRule and SafeNumber(difficultyID) or nil
    self:ResetEncounterState()
    self:RefreshCoTank()
    self:RefreshStatus()

    if not self.activeRule then
        self:HideFrames()
    end

    if self:IsEnabled() and RC.db.profile.tankAssistAnnounceRule and self.activeRule then
        RC:Print("Tank Assist: " .. self.activeRule.name .. " - " .. self.activeRule.note)
    end
end

function TankAssist:ENCOUNTER_END()
    self.activeRule = nil
    self.activeEncounter = nil
    self.activeEncounterID = nil
    self.activeDifficultyID = nil
    self:ResetEncounterState()
    self:HideFrames()
end

function TankAssist:RefreshCoTank()
    local profile = RC.db and RC.db.profile or {}
    local manualName = SafeText(profile.tankAssistCoTankName)
    local manualKey = NameKey(manualName)
    local manualShortKey = ShortNameKey(manualName)
    local manualHasRealm = manualName and manualName:find("-", 1, true) ~= nil
    local playerKey = NameKey(UnitFullNameSafe("player"))
    local foundUnit
    local foundName

    if not self:IsRaidInstance() or SafeBooleanCall(IsInRaid) ~= true then
        self.coTankUnit = nil
        self.coTankName = nil
        return nil, nil
    end

    local function consider(unit)
        if foundUnit or not unit or SafeUnitExists(unit) ~= true then
            return
        end
        local name = UnitFullNameSafe(unit)
        local key = NameKey(name)
        if not key or key == playerKey then
            return
        end
        if manualKey and manualKey ~= "" then
            local shortKey = ShortNameKey(name)
            if key == manualKey or (not manualHasRealm and shortKey == manualShortKey) then
                foundUnit = unit
                foundName = name
            end
        elseif SafeUnitRole(unit) == "TANK" then
            foundUnit = unit
            foundName = name
        end
    end

    local count = math.max(SafeNumber(GetNumGroupMembers and GetNumGroupMembers()) or 0, 0)
    if manualKey and manualKey ~= "" then
        for index = 1, count do
            consider("raid" .. index)
        end
    else
        -- With three tank-role players, the first one in the roster is often
        -- not the partner. Prefer the living tank who holds or is targeted by
        -- a boss, then any living tank, then the first tank found.
        local best, bestName, bestScore = nil, nil, -1
        for index = 1, count do
            local unit = "raid" .. index
            local name = SafeUnitExists(unit) == true and UnitFullNameSafe(unit) or nil
            local key = NameKey(name)
            if key and key ~= playerKey and SafeUnitRole(unit) == "TANK" then
                local score = 0
                if UnitIsDeadSafe(unit) ~= true then
                    score = 1
                    for _, record in pairs(self.bossHolders or {}) do
                        if record.holder == key then
                            score = score + 4
                            break
                        end
                    end
                    for bossIndex = 1, 5 do
                        if SafeBooleanCall(UnitIsUnit, "boss" .. bossIndex .. "target", unit) == true then
                            score = score + 2
                            break
                        end
                    end
                end
                if score > bestScore then
                    best, bestName, bestScore = unit, name, score
                end
            end
        end
        foundUnit, foundName = best, bestName
    end

    self.coTankUnit = foundUnit
    self.coTankName = foundName
    return foundUnit, foundName
end

function TankAssist:GetBossTargetState(unit, bossUnit)
    if not unit or type(UnitExists) ~= "function" or type(UnitIsUnit) ~= "function" then
        return false, nil, nil
    end
    local first = bossUnit and bossUnit:match("^boss%d+$") and bossUnit or nil
    local firstIndex = first and SafeNumber(first:match("(%d+)$")) or 1
    local lastIndex = first and firstIndex or 5
    local unknown = false
    for index = firstIndex, lastIndex do
        local target = "boss" .. index .. "target"
        local exists = SafeUnitExists(target)
        if exists == true then
            local matches = SafeBooleanCall(UnitIsUnit, target, unit)
            if matches == true then
                local owner = "boss" .. index
                return true, owner, UnitFullNameSafe(owner)
            elseif matches == nil then
                unknown = true
            end
        elseif exists == nil then
            unknown = true
        end
    end
    if unknown then
        return nil, nil, nil
    end
    return false, nil, nil
end

function TankAssist:IsUnitBossTarget(unit, bossUnit)
    local matches = self:GetBossTargetState(unit, bossUnit)
    return matches
end

function TankAssist:PlayerIsBossTarget(bossUnit)
    return self:IsUnitBossTarget("player", bossUnit)
end

function TankAssist:CoTankIsBossTarget(bossUnit)
    return self:IsUnitBossTarget(self.coTankUnit, bossUnit)
end

-- Stable tank ownership.
--
-- A boss's live target is a poor answer to "who is tanking": bosses retarget
-- during casts and frontals, and a fast taunt flips the target instantly. Each
-- boss therefore keeps a holder that only changes once a tank has been the
-- boss target for OWNER_STABLE_SECONDS. Non-tank targets and unknown (secret)
-- targets never replace the holder.

-- Returns the name key of the tank the boss is targeting, "other" when the
-- boss targets nothing or a non-tank, or nil when the target cannot be read.
function TankAssist:GetLiveBossHolder(bossUnit)
    if not IsBossUnit(bossUnit) or type(UnitIsUnit) ~= "function" then
        return nil
    end
    local target = bossUnit .. "target"
    local exists = SafeUnitExists(target)
    if exists == nil then
        return nil
    elseif exists == false then
        return "other"
    end

    local unknown = false
    local function matches(unit)
        local result = SafeBooleanCall(UnitIsUnit, target, unit)
        if result == nil then
            unknown = true
        end
        return result == true
    end

    if matches("player") then
        return NameKey(UnitFullNameSafe("player"))
    end
    if self.coTankUnit and matches(self.coTankUnit) then
        return NameKey(UnitFullNameSafe(self.coTankUnit))
    end
    local count = math.max(SafeNumber(GetNumGroupMembers and GetNumGroupMembers()) or 0, 0)
    for index = 1, count do
        local unit = "raid" .. index
        if unit ~= self.coTankUnit and SafeUnitRole(unit) == "TANK" and matches(unit) then
            return NameKey(UnitFullNameSafe(unit))
        end
    end
    if unknown then
        return nil
    end
    return "other"
end

function TankAssist:UpdateBossHolder(bossUnit)
    if not IsBossUnit(bossUnit) then
        return nil
    end
    self.bossHolders = self.bossHolders or {}
    local record = self.bossHolders[bossUnit] or {}
    self.bossHolders[bossUnit] = record
    local now = SafeNow()

    -- Commit the previous candidate if it held the boss long enough, even if
    -- the boss has since turned to cast at someone else.
    if record.candidate and record.candidate ~= "other"
        and now - (record.candidateSince or now) >= OWNER_STABLE_SECONDS
    then
        record.holder = record.candidate
    end

    local live = self:GetLiveBossHolder(bossUnit)
    if live and live ~= record.candidate then
        record.candidate = live
        record.candidateSince = now
    end
    return record.holder
end

function TankAssist:GetStableBossHolder(bossUnit)
    return self:UpdateBossHolder(bossUnit)
end

-- Maps a holder name key to "player", "cotank", or nil (a third tank).
function TankAssist:GetHolderRole(holder)
    if not holder or holder == "other" then
        return nil
    end
    if holder == NameKey(UnitFullNameSafe("player")) then
        return "player"
    end
    if self.coTankUnit and holder == NameKey(UnitFullNameSafe(self.coTankUnit)) then
        return "cotank"
    end
    return nil
end

function TankAssist:ForgetMissingBossHolders()
    for bossUnit in pairs(self.bossHolders or {}) do
        if SafeUnitExists(bossUnit) == false then
            self.bossHolders[bossUnit] = nil
        end
    end
end

function TankAssist:ResolveMechanicBossUnit(tracked, rule)
    local bossUnit = tracked and tracked.bossUnit or nil
    if not bossUnit and tracked and tracked.bossName and self.FindBossUnitByName then
        bossUnit = self:FindBossUnitByName(tracked.bossName)
    end
    return bossUnit or (rule and rule.bossUnit) or nil
end

-- Who owns the boss this mechanic comes from: "player", "cotank", or nil when
-- it is unknown or ambiguous. The second return is the boss unit, if known.
-- Stable ownership wins; the live boss target is only used when no tank has
-- held the boss long enough to be recorded yet (for example on the pull).
function TankAssist:GetMechanicOwner(tracked, rule)
    -- The timer stack asks this ten times a second; the roster scan only
    -- needs to run a couple of times a second.
    local now = SafeNow()
    if not self.coTankRefreshedAt or now - self.coTankRefreshedAt >= 0.5 or now < self.coTankRefreshedAt then
        self.coTankRefreshedAt = now
        self:RefreshCoTank()
    end
    local bossUnit = self:ResolveMechanicBossUnit(tracked, rule)

    if bossUnit then
        local stable = self:GetHolderRole(self:GetStableBossHolder(bossUnit))
        if stable then
            return stable, bossUnit
        end
    else
        -- No single boss: trust stable ownership only if exactly one of the
        -- two tanks holds a boss. Multi-boss fights are otherwise ambiguous.
        local playerBoss, coTankBoss
        for index = 1, 5 do
            local unit = "boss" .. index
            local role = self:GetHolderRole(self:GetStableBossHolder(unit))
            if role == "player" then
                playerBoss = playerBoss or unit
            elseif role == "cotank" then
                coTankBoss = coTankBoss or unit
            end
        end
        if playerBoss and not coTankBoss then
            return "player", playerBoss
        elseif coTankBoss and not playerBoss then
            return "cotank", coTankBoss
        elseif playerBoss and coTankBoss then
            return nil, nil
        end
    end

    local playerHasBoss, playerBossUnit = self:GetBossTargetState("player", bossUnit)
    local coTankHasBoss, coTankBossUnit = self:GetBossTargetState(self.coTankUnit, bossUnit)
    if playerHasBoss == true and coTankHasBoss ~= true then
        return "player", bossUnit or playerBossUnit
    end
    if coTankHasBoss == true and playerHasBoss ~= true then
        return "cotank", bossUnit or coTankBossUnit
    end
    return nil, bossUnit
end

-- Upper-case boss name for warning titles, e.g. "VEXHUL". Nil when unknown.
function TankAssist:GetBossDisplayName(bossUnit, fallback)
    local name = bossUnit and UnitFullNameSafe(bossUnit) or nil
    if not name or name == "" then
        name = SafeText(fallback)
    end
    if not name or name == "" then
        return nil
    end
    local ok, upper = pcall(string.upper, name)
    return ok and upper or nil
end

-- "VEXHUL" -> "Vexhul", "ZUL'JAN" -> "Zul'jan" for detail lines.
function TankAssist:TitleCase(text)
    text = SafeText(text)
    if not text or text == "" then
        return text
    end
    local lower = string.lower(text)
    return (lower:gsub("^%l", string.upper):gsub("([%s%-])(%l)", function(sep, letter)
        return sep .. string.upper(letter)
    end))
end

function TankAssist:IsCoTankDead()
    return UnitIsDeadSafe(self.coTankUnit) == true
end

function TankAssist:IsPlayerDead()
    return UnitIsDeadSafe("player") == true
end

function TankAssist:GetTrackedAura(unit, auraRules)
    if not unit or SafeUnitExists(unit) ~= true then
        return nil
    end
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
        return nil
    end

    local function privateResult()
        local firstRule = auraRules and auraRules[1]
        return {
            name = firstRule and firstRule.name or "Tank debuff",
            accessible = false,
        }
    end

    local hasInspectableRule = false
    for _, wanted in ipairs(auraRules or {}) do
        if not wanted.private then
            hasInspectableRule = true
            break
        end
    end
    if not hasInspectableRule then
        return privateResult()
    end

    for index = 1, MAX_AURAS do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HARMFUL")
        if not ok or not ValueIsAccessible(aura) then
            return privateResult()
        end
        if not aura then
            break
        end
        local okFields, auraSpellID, auraNameValue, applications = pcall(function()
            return aura.spellId, aura.name, aura.applications
        end)
        if not okFields then
            return privateResult()
        end
        auraSpellID = SafeNumber(auraSpellID)
        local auraName = SafeLower(auraNameValue)
        for _, wanted in ipairs(auraRules or {}) do
            local matchesID = not wanted.private and auraSpellID and auraSpellID == wanted.spellID
            local matchesName = not wanted.private and auraName ~= "" and auraName == SafeLower(wanted.name)
            if matchesID or matchesName then
                applications = SafeNumber(applications)
                if applications then
                    return {
                        name = SafeText(auraNameValue) or wanted.name,
                        count = math.max(1, math.floor(applications)),
                        accessible = true,
                    }
                end
                return { name = wanted.name, accessible = false }
            end
        end
    end
    return nil
end

function TankAssist:GetAuraStatusText(rule)
    local auraRules = rule and rule.stackAuras
    if not auraRules or #auraRules == 0 then
        return rule and rule.statusText or "Co-tank tracking active."
    end
    local aura = self:GetTrackedAura(self.coTankUnit, auraRules)
    if aura and aura.accessible and aura.count then
        return string.format("%s: %d", aura.name, aura.count)
    end
    if aura and not aura.accessible then
        return aura.name .. ": private"
    end
    for _, wanted in ipairs(auraRules) do
        if wanted.private then
            return wanted.name .. ": private"
        end
    end
    return auraRules[1].name .. ": 0"
end

function TankAssist:RefreshStatus()
    local profile = RC.db and RC.db.profile or {}
    local frame = self.statusFrame
    if not frame then
        return
    end
    if profile.tankAssistShowStatus == false
        or not self:ShouldRun()
        or not self.activeRule
        or not self:IsRuleEnabled(self.activeRule)
    then
        frame:Hide()
        return
    end

    frame.name:SetText("Co-tank: " .. (self.coTankName or "not found"))
    local coTankHasBoss, _, coTankBossName = self:GetBossTargetState(self.coTankUnit)
    local playerHasBoss, _, playerBossName = self:GetBossTargetState("player")
    if self.coTankUnit and coTankHasBoss == true then
        frame.target:SetText(coTankBossName and ("TANKING: " .. coTankBossName) or "TANKING")
        frame.target:SetTextColor(1, 0.72, 0.2, 1)
    elseif playerHasBoss == true then
        frame.target:SetText(playerBossName and ("YOU TANK: " .. playerBossName) or "YOU TANK")
        frame.target:SetTextColor(0.35, 0.85, 0.5, 1)
    else
        frame.target:SetText("TARGET UNKNOWN")
        frame.target:SetTextColor(0.7, 0.7, 0.7, 1)
    end
    if profile.tankAssistUseAuraRules == false then
        frame.detail:SetText(self.activeRule.statusText or "Co-tank tracking active.")
    else
        frame.detail:SetText(self:GetAuraStatusText(self.activeRule))
    end
    frame:Show()
end

function TankAssist:UNIT_TARGET(event, unit)
    unit = SafeText(unit)
    if self:ShouldRun() and unit and string.find(unit, "^boss") then
        self:UpdateBossHolder(unit)
        self:RefreshStatus()
    end
end

function TankAssist:UNIT_AURA(event, unit)
    if not self:ShouldRun() or RC.db.profile.tankAssistUseAuraRules == false then
        return
    end
    unit = SafeText(unit)
    if unit == "player" or unit == self.coTankUnit then
        self:RefreshStatus()
    end
end

function TankAssist:GetBossModTimelineInfo(eventInfo)
    local map = ns.BossModTimeline
    if not map or type(eventInfo) ~= "table" then
        return nil
    end
    local ok, rawID = pcall(function() return eventInfo.id end)
    local eventID = ok and SafeNumber(rawID) or nil
    return eventID and map[eventID] or nil
end

function TankAssist:GetTimelineMechanic(rule, eventInfo)
    local mechanics = rule and rule.timelineMechanics
    if type(mechanics) ~= "table" or type(eventInfo) ~= "table" or not ValueIsAccessible(eventInfo) then
        return nil
    end

    local okName, rawName = pcall(function() return eventInfo.spellName end)
    local eventName = okName and SafeLower(rawName) or ""
    local okID, rawID = pcall(function() return eventInfo.spellID end)
    local eventSpellID = okID and SafeNumber(rawID) or nil
    if not eventSpellID then
        local legacyOK, legacyID = pcall(function() return eventInfo.spellId end)
        eventSpellID = legacyOK and SafeNumber(legacyID) or nil
    end

    -- Encounters hide the timeline's spell; take it from the BigWigs bar linked
    -- to this timeline event when there is one.
    if not eventSpellID or eventName == "" then
        local bossMod = self:GetBossModTimelineInfo(eventInfo)
        if bossMod then
            eventSpellID = eventSpellID or bossMod.spellID
            if eventName == "" then eventName = bossMod.name or "" end
        end
    end

    for _, mechanic in ipairs(mechanics) do
        local wantedID = SafeNumber(mechanic.spellID)
        local wantedName = SafeLower(mechanic.name)
        local idMatches = eventSpellID and wantedID and eventSpellID == wantedID
        local nameMatches = eventName ~= "" and wantedName ~= "" and eventName == wantedName
        local difficultyMatches = true
        if type(mechanic.difficulties) == "table" then
            difficultyMatches = false
            for _, difficultyID in ipairs(mechanic.difficulties) do
                if self.activeDifficultyID == difficultyID then
                    difficultyMatches = true
                    break
                end
            end
        end
        local phaseMatches = true
        if type(mechanic.phases) == "table" then
            phaseMatches = false
            local state = self.timelineState or {}
            local currentPhase = state[rule.phaseStateKey] or 1
            for _, phase in ipairs(mechanic.phases) do
                if currentPhase == phase then
                    phaseMatches = true
                    break
                end
            end
        end
        if (idMatches or nameMatches) and difficultyMatches and phaseMatches then
            return {
                kind = "tank",
                action = mechanic.action or rule.action or "assignment",
                label = mechanic.label or mechanic.name or rule.mechanic or "Tank mechanic",
                defensive = mechanic.defensive,
                bossUnit = mechanic.bossUnit,
                bossName = mechanic.bossName,
                resolveAfter = SafeNumber(mechanic.resolveAfter),
            }
        end
    end
    return nil
end

function TankAssist:ClassifyTimelineEvent(rule, eventInfo)
    if not rule or not rule.timeline or type(eventInfo) ~= "table" or not ValueIsAccessible(eventInfo) then
        return nil
    end
    local exactMechanic = self:GetTimelineMechanic(rule, eventInfo)
    if exactMechanic then
        return exactMechanic
    end

    local okDuration, durationValue = pcall(function()
        return eventInfo.duration
    end)
    local duration = okDuration and RoundNumber(durationValue) or nil
    if not duration then
        return nil
    end
    local state = self.timelineState or {}
    self.timelineState = state
    state.durationCounts = state.durationCounts or {}
    local function durationCount(value)
        state.durationCounts[value] = (state.durationCounts[value] or 0) + 1
        return state.durationCounts[value]
    end

    if rule.timeline == "vorasius" then
        if duration == 6 or duration == 120 then
            return { kind = "reset", reset = "vorasius", label = "Primordial Roar" }
        end
        if duration == 16 or duration == 136 or duration == 240 then
            return { kind = "tank", action = "sequence", label = rule.mechanic }
        end
    elseif rule.timeline == "salhadaar" then
        if duration == 100 then
            state.salhadaarFortyFiveCount = 0
            return nil
        end
        if duration == 42 or duration == 44 then
            return { kind = "tank", action = "assignment", label = rule.mechanic }
        end
        if duration == 45 then
            state.salhadaarFortyFiveCount = (state.salhadaarFortyFiveCount or 0) + 1
            if state.salhadaarFortyFiveCount % 3 == 0 then
                return { kind = "tank", action = "assignment", label = rule.mechanic }
            end
        end
    elseif rule.timeline == "beloren" then
        local mythic = self.activeDifficultyID == 16
        if duration == 20 or (mythic and duration == 16) or (not mythic and duration == 18) then
            return { kind = "tank", action = "assignment", label = rule.mechanic }
        end
    elseif rule.timeline == "midnightfalls" then
        local stage = state.midnightStage or 1
        if duration == 45 and stage == 1 then
            return { kind = "phase", stage = 2, label = "The Darkwell" }
        end
        if duration == 97 and stage <= 2 then
            return { kind = "phase", stage = 3, label = "Dark Meltdown" }
        end
        local mythic = self.activeDifficultyID == 16
        local isLance = (stage <= 2 and duration == 20)
            or (stage == 3 and mythic and (duration == 30 or duration == 40))
            or (stage == 3 and not mythic and (duration == 20 or duration == 23))
        if isLance then
            return { kind = "tank", action = "swap", label = rule.mechanic }
        end
    elseif rule.timeline == "nekzali" then
        if duration == 28 or duration == 36 then
            return { kind = "tank", action = "swap", label = "Possession Barrage", bossUnit = "boss1", resolveAfter = 8.0 }
        end
    elseif rule.timeline == "sentinels" then
        if duration == 4 then
            return { kind = "tank", action = "defensive", label = "Empowering Slam" }
        end
        if duration == 6 then
            return { kind = "tank", action = "defensive", label = "Bloodvenom Injection" }
        end
        -- Do not guess the repeating 22-second bucket. Empowering Slam can be
        -- delayed independently, which permanently flips an alternating counter.
        -- A missed warning is safer than telling the wrong tank to use a defensive.
    elseif rule.timeline == "explorers" then
        if duration == 30 then
            return { kind = "tank", action = "swap", label = rule.mechanic }
        end
    elseif rule.timeline == "vashnik" then
        local difficulty = self.activeDifficultyID
        if difficulty == 16 then
            if duration == 8 or duration == 11 or duration == 22
                or (duration == 30 and durationCount(duration) % 2 == 1)
            then
                return { kind = "tank", action = "swap", label = rule.mechanic }
            end
        elseif difficulty == 15 then
            if duration == 8 or duration == 27 or duration == 28
                or (duration == 13 and durationCount(duration) > 1)
            then
                return { kind = "tank", action = "swap", label = rule.mechanic }
            end
        elseif duration == 2 or duration == 30 or duration == 33
            or (duration == 8 and durationCount(duration) == 1)
        then
            return { kind = "tank", action = "swap", label = rule.mechanic }
        end
    elseif rule.timeline == "sszorak" then
        if duration == 5 or duration == 6 then
            return { kind = "tank", action = "assignment", label = rule.mechanic }
        end
        if (duration == 47 or duration == 52 or duration == 59) and durationCount(duration) % 3 == 1 then
            return { kind = "tank", action = "assignment", label = rule.mechanic }
        end
    elseif rule.timeline == "twinfangs" then
        local mythic = self.activeDifficultyID == 16
        if (mythic and duration == 18)
            or (not mythic and (duration == 20 or duration == 22 or duration == 23))
        then
            return { kind = "tank", action = "stonebreaker", label = "Stone Breaker", defensive = false }
        end
        if mythic and duration == 61 then
            local count = durationCount(duration) % 8
            if count == 3 then
                return { kind = "tank", action = "stonebreaker", label = "Stone Breaker", defensive = false }
            end
        end
        if not mythic and (duration == 68 or duration == 76) then
            local count = durationCount(duration) % 6
            if count == 2 then
                return { kind = "tank", action = "stonebreaker", label = "Stone Breaker", defensive = false }
            end
        end
    elseif rule.timeline == "coiledaltar" then
        if duration == 16 or duration == 21 then
            return { kind = "tank", action = "swap", label = "Sever", resolveAfter = 3.5 }
        elseif duration == 31 then
            return { kind = "tank", action = "swap", label = "Soul Sever", resolveAfter = 3.5 }
        elseif duration == 29 or duration == 30 or duration == 32 or duration == 38 then
            return { kind = "tank", action = "swap", label = "Blighted Sever", resolveAfter = 3.5 }
        end
    elseif rule.timeline == "nymrissa" then
        if self.activeDifficultyID ~= 16 and (duration == 9 or duration == 22 or duration == 27) then
            return { kind = "tank", action = "swap", label = "Iceblade Flurry", bossUnit = "boss1", resolveAfter = 7.0 }
        end
    elseif rule.timeline == "ulatek" then
        local stage = state.ulatekStage or 1
        if stage == 1 and duration == 118 then
            state.ulatekStage = 2
            state.durationCounts = {}
            return nil
        elseif stage == 2 and duration == 10 then
            state.ulatekStage = 2.5
            state.durationCounts = {}
            return nil
        elseif stage < 3 and (duration == 230 or duration == 235) then
            state.ulatekStage = 3
            state.durationCounts = {}
            return nil
        end

        if stage == 1 then
            if duration == 42 or (duration == 52 and durationCount(duration) == 2) then
                return { kind = "tank", action = "swap", label = "Caustic Waves", defensive = false }
            end
            if duration == 10 or duration == 37 or duration == 67 then
                return { kind = "tank", action = "defensive", label = "Mother's Wrath" }
            end
        elseif stage == 3 then
            local count = durationCount(duration)
            if duration == 10 and count == 1 then
                return nil
            end
            if duration == 10 or duration == 75 or duration == 76 then
                return { kind = "tank", action = "swap", label = "Mother's Wrath" }
            end
        end
    end
    return nil
end

function TankAssist:ENCOUNTER_TIMELINE_EVENT_ADDED(event, eventInfo, deferred)
    if not self:ShouldRun()
        or RC.db.profile.tankAssistUseCastRules == false
        or not self.activeRule
        or not self:IsRuleEnabled(self.activeRule)
    then
        return
    end
    if type(eventInfo) ~= "table" or not ValueIsAccessible(eventInfo) then
        return
    end
    local okFields, source, rawEventID = pcall(function()
        return eventInfo.source, eventInfo.id
    end)
    if not okFields or SafeNumber(source) ~= 0 then
        return
    end
    local eventID = SafeNumber(rawEventID)
    if not eventID then
        return
    end
    -- BigWigs may start its bar for this event after we see it. When the spell
    -- is hidden, wait a moment for that bar so the mechanic is identified by
    -- spell instead of guessed from the timer length.
    if not deferred and BigWigsLoader and C_Timer and C_Timer.After
        and not self:GetBossModTimelineInfo(eventInfo)
    then
        local okSpell, rawSpell = pcall(function() return eventInfo.spellID end)
        if not (okSpell and SafeNumber(rawSpell)) then
            C_Timer.After(0.1, function()
                self:ENCOUNTER_TIMELINE_EVENT_ADDED(event, eventInfo, true)
            end)
            return
        end
    end
    local classified = self:ClassifyTimelineEvent(self.activeRule, eventInfo)
    if classified and ns.Log then
        local bossMod = self:GetBossModTimelineInfo(eventInfo)
        ns.Log:Info("TankAssist", "timeline %d (%ss) -> %s %s [%s]", eventID,
            tostring(SafeNumber(select(2, pcall(function() return eventInfo.duration end))) or "?"),
            tostring(classified.kind), tostring(classified.label or classified.action),
            classified.identifiedBy or (bossMod and "BigWigs" or "timer length"))
    end
    if classified then
        local okDuration, rawDuration = pcall(function() return eventInfo.duration end)
        classified.duration = okDuration and SafeNumber(rawDuration) or nil
        classified.eventID = eventID
        self.timelineEvents[eventID] = classified
        self:ScheduleDefensiveWarning(classified)
        if self.ScheduleMidnightProactiveWarning then
            self:ScheduleMidnightProactiveWarning(classified)
        end
    end
end

function TankAssist:ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED(event, eventID)
    eventID = SafeNumber(eventID)
    local tracked = eventID and self.timelineEvents[eventID]
    if not tracked or not C_EncounterTimeline or not C_EncounterTimeline.GetEventState then
        return
    end
    local ok, state = pcall(C_EncounterTimeline.GetEventState, eventID)
    state = ok and SafeNumber(state) or nil
    if state == 2 then
        self.timelineEvents[eventID] = nil
        CancelTimer(tracked.defensiveTimer)
        CancelTimer(tracked.proactiveTimer)
        self:HandleTimelineFinished(tracked)
    elseif state == 3 then
        self.timelineEvents[eventID] = nil
        CancelTimer(tracked.defensiveTimer)
        CancelTimer(tracked.proactiveTimer)
    end
end

function TankAssist:ENCOUNTER_TIMELINE_EVENT_REMOVED(event, eventID)
    eventID = SafeNumber(eventID)
    if eventID then
        CancelTimer(self.timelineEvents[eventID] and self.timelineEvents[eventID].defensiveTimer)
        CancelTimer(self.timelineEvents[eventID] and self.timelineEvents[eventID].proactiveTimer)
        self.timelineEvents[eventID] = nil
    end
end

function TankAssist:ScheduleDefensiveWarning(tracked)
    if not tracked or tracked.kind ~= "tank" or tracked.defensive == false
        or not C_Timer or type(C_Timer.NewTimer) ~= "function"
    then
        return false
    end

    local profile = RC.db and RC.db.profile or {}
    local lead = math.max(1, math.min(8, SafeNumber(profile.tankAssistDefensiveLeadSeconds)
        or DEFENSIVE_WARNING_LEAD_SECONDS))
    tracked.defensiveLead = lead
    local scheduledAt = type(GetTime) == "function" and SafeNumber(GetTime()) or nil

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
        local now = scheduledAt and SafeNumber(GetTime())
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
            tracked.defensiveTimer = nil
            self:HandleDefensiveWarning(tracked)
            return
        end
        tracked.defensiveTimer = C_Timer.NewTimer(math.max(0.1, remaining - lead), Arm)
    end

    Arm()
    return true
end

function TankAssist:HandleDefensiveWarning(tracked)
    if not tracked
        or not self:ShouldRun()
        or RC.db.profile.tankAssistUseCastRules == false
        or not self.activeRule
        or not self:IsRuleEnabled(self.activeRule)
    then
        return false
    end

    local rule = self.activeRule
    -- TankAssist is intentionally player-actionable. Never tell this player to
    -- use a defensive for a hit that belongs to the co-tank. Ownership comes
    -- from the tank that has held the boss steadily; when the mechanic is not
    -- bound to one boss and both tanks hold a boss, it is ambiguous, so stay
    -- silent. The owner is remembered so the swap call after the hit still
    -- knows who took it if the boss target is unreadable by then.
    local owner, bossUnit = self:GetMechanicOwner(tracked, rule)
    tracked.ownerBeforeHit = owner or tracked.ownerBeforeHit
    if owner ~= "player" then
        return false
    end
    local playerBossName = bossUnit and UnitFullNameSafe(bossUnit) or nil

    local detail = "Use active mitigation or a defensive for " .. tracked.label
        .. (playerBossName and (" from " .. playerBossName) or "") .. "."
    return self:Alert(
        "DEFENSIVE NOW",
        detail,
        "Defensive",
        rule.key .. ":defensive:" .. tracked.label,
        true,
        rule,
        "defensive"
    )
end

function TankAssist:HandleTimelineFinished(tracked)
    if not tracked
        or not self:ShouldRun()
        or RC.db.profile.tankAssistUseCastRules == false
        or not self.activeRule
        or not self:IsRuleEnabled(self.activeRule)
    then
        return
    end
    if tracked.kind == "phase" then
        self.timelineState.midnightStage = tracked.stage
        return
    end
    if tracked.kind == "reset" then
        if tracked.reset == "vorasius" then
            self.timelineState.vorasiusSlamCount = 0
        end
        return
    end
    if tracked.kind ~= "tank" then
        return
    end

    if tracked.action == "defensive" then
        self:RefreshStatus()
        return
    end

    local rule = self.activeRule
    if tracked.action == "sequence" then
        self.timelineState.vorasiusSlamCount = (self.timelineState.vorasiusSlamCount or 0) + 1
        if self.timelineState.vorasiusSlamCount ~= self:GetSwapEvery(rule) then
            return
        end
    end

    self:RefreshCoTank()
    if tracked.action == "assignment" then
        local playerHasBoss, _, playerBossName = self:GetBossTargetState("player", rule.bossUnit)
        local coTankHasBoss, _, coTankBossName = self:GetBossTargetState(self.coTankUnit, rule.bossUnit)
        local activeBoss = playerHasBoss == true and playerBossName
            or (coTankHasBoss == true and coTankBossName or nil)
        local detail = tracked.label .. ": follow your tank assignment."
        if activeBoss then
            detail = detail .. " Active tank target: " .. activeBoss .. "."
        end
        self:Alert(
            self:GetRuleAlertText(rule, rule.tauntText or "TANK MECHANIC"),
            detail,
            "Swap",
            rule.key .. ":assignment:" .. tracked.label,
            true,
            rule,
            "taunt"
        )
    else
        -- Use the tank that has held the boss steadily, not the live target:
        -- bosses retarget while casting, and a quick taunt flips the target.
        local owner, ownerBossUnit = self:GetMechanicOwner(tracked, rule)
        owner = owner or tracked.ownerBeforeHit
        local bossName = ownerBossUnit and UnitFullNameSafe(ownerBossUnit) or nil
        local coTankHasBoss = owner == "cotank"
        local playerHasBoss = owner == "player"
        local coTankBossName, playerBossName = bossName, bossName
        if coTankHasBoss and self:IsPlayerDead() then
            self:RefreshStatus()
            return
        end
        if playerHasBoss and self.coTankUnit and self:IsCoTankDead() then
            self:Alert(
                "HOLD BOSS — CO-TANK DEAD",
                "No living co-tank can take " .. tracked.label .. ". Keep the boss and use a defensive.",
                "Defensive",
                rule.key .. ":hold:" .. tracked.label,
                true,
                rule,
                "defensive"
            )
            self:RefreshStatus()
            return
        end
        if coTankHasBoss == true then
            local upperBoss = self:GetBossDisplayName(ownerBossUnit)
            local title = self:GetRuleAlertText(rule,
                upperBoss and ("TAUNT " .. upperBoss .. " NOW") or rule.tauntText or "TAUNT NOW")
            local coTank = self.coTankName and (self.coTankName:match("^([^%-]+)") or self.coTankName)
            self:Alert(
                title,
                (coTank or "Your co-tank") .. " took " .. tracked.label
                    .. (coTankBossName and (" from " .. coTankBossName) or "") .. ".",
                "Taunt",
                rule.key .. ":taunt:" .. tracked.label,
                true,
                rule,
                "taunt"
            )
        elseif playerHasBoss == true then
            local upperBoss = self:GetBossDisplayName(ownerBossUnit)
            local title = upperBoss and ("SWAP OUT — " .. upperBoss) or "SWAP OUT"
            self:Alert(
                title,
                "You took " .. tracked.label
                    .. (playerBossName and (" from " .. playerBossName) or "") .. ".",
                "Swap",
                rule.key .. ":swap:" .. tracked.label,
                true,
                rule,
                "taunt"
            )
        else
            local bossLabel = self:GetBossDisplayName(ownerBossUnit, rule.name) or "ACTIVE BOSS"
            self:Alert(
                "TANK SWAP — " .. bossLabel,
                tracked.label .. ". Off-tank taunts; the tank that took it lets go.",
                "Swap",
                rule.key .. ":check:" .. tracked.label,
                true,
                rule,
                "taunt"
            )
        end
    end
    self:RefreshStatus()
end

local WARNING_PREFIXES = {
    taunt = "tankAssistTaunt",
    defensive = "tankAssistDefensive",
    movement = "tankAssistMovement",
}

-- Internal callers pass a category explicitly. Keep a spoken-word fallback for
-- extensions that still call the original Alert API, even with a custom title.
function TankAssist:GetWarningCategory(category, spokenText, title)
    if WARNING_PREFIXES[category] then
        return category
    end
    local text = SafeLower(spokenText)
    if text == "" then
        text = SafeLower(title)
    end
    if string.find(text, "defensive", 1, true) or string.find(text, "mitigation", 1, true) then
        return "defensive"
    end
    for _, word in ipairs({ "move", "jump", "run", "position", "aim", "soak" }) do
        if string.find(text, word, 1, true) then
            return "movement"
        end
    end
    return "taunt"
end

function TankAssist:IsWarningEnabled(category)
    local profile = RC.db and RC.db.profile or {}
    local prefix = WARNING_PREFIXES[self:GetWarningCategory(category)]
    return profile[prefix .. "Enabled"] ~= false
end

function TankAssist:GetWarningSoundSettings(category)
    local profile = RC.db and RC.db.profile or {}
    category = self:GetWarningCategory(category)
    local prefix = WARNING_PREFIXES[category]
    local sound = profile[prefix .. "Sound"]
    local inheritsSound = not sound or sound == "inherit"
    if inheritsSound then
        sound = profile.tankAssistSound or "voicepack"
    end
    local channel = profile[prefix .. "SoundChannel"]
    if not channel or channel == "inherit" then
        channel = profile.tankAssistSoundChannel or "Master"
    end
    if not SOUND_CHANNEL_LABELS[channel] then
        channel = "Master"
    end
    local customFile = profile[prefix .. "CustomSoundFile"]
    if inheritsSound or customFile == nil then
        customFile = profile.tankAssistCustomSoundFile
    end
    if profile.tankAssistSoundEnabled == false or not self:IsWarningEnabled(category) then
        sound = "none"
    end
    return sound, channel, SafeText(customFile)
end

function TankAssist:GetCountdownSettings(category)
    local profile = RC.db and RC.db.profile or {}
    category = self:GetWarningCategory(category)
    local prefix = WARNING_PREFIXES[category]
    local sound = self:GetWarningSoundSettings(category)
    local seconds = math.floor(math.max(1, math.min(10, SafeNumber(profile[prefix .. "CountdownSeconds"]) or 3)))
    return profile[prefix .. "CountdownEnabled"] ~= false and sound ~= "none", seconds
end

function TankAssist:Alert(title, detail, spokenText, key, playSound, rule, category)
    local profile = RC.db and RC.db.profile or {}
    category = self:GetWarningCategory(category, spokenText, title)
    if not self:IsWarningEnabled(category) then
        return false
    end
    local now = GetTime and GetTime() or 0
    local cooldown = SafeNumber(profile.tankAssistAlertCooldown) or 6
    key = key or ((title or "") .. ":" .. (detail or ""))
    if self.lastAlerts[key] and now - self.lastAlerts[key] < cooldown then
        return false
    end
    self.lastAlerts[key] = now
    self.alertHUDCategory = category

    if profile.tankAssistShowVisual ~= false then
        if self.layoutPreviewTimer then
            self.layoutPreviewTimer:Cancel()
            self.layoutPreviewTimer = nil
        end
        self:CreateAlertFrame()
        if self.frame then
            self:ApplySingleFrameSettings(self.frame)
            self:ApplyAlertIcon(rule)
            self.frame.title:SetText(title or "TAUNT NOW")
            self.frame.detail:SetText(detail or "")
            self.frame:Show()
            if self.hideTimer then
                self.hideTimer:Cancel()
            end
            if C_Timer and C_Timer.NewTimer then
                local duration = math.max(1, math.min(15, SafeNumber(profile.tankAssistVisualDuration) or 2.5))
                self.hideTimer = C_Timer.NewTimer(duration, function()
                    if self.frame then
                        self.frame:Hide()
                    end
                end)
            end
        end
    end

    if playSound and spokenText and spokenText ~= "" then
        self:PlayAlertSound(spokenText, category)
    end
    return true
end

local function TrySoundCall(callback, ...)
    local ok, result = pcall(callback, ...)
    return ok and result ~= false
end

function TankAssist:PlayAlertSound(spokenText, category)
    local profile = RC.db and RC.db.profile or {}
    category = self:GetWarningCategory(category, spokenText)
    local sound, channel, customFile = self:GetWarningSoundSettings(category)
    local played = false
    local sharedPath = RC.ResolveSharedMediaSound and RC:ResolveSharedMediaSound(sound)

    if sound == "none" then
        return
    elseif sharedPath and PlaySoundFile then
        played = TrySoundCall(PlaySoundFile, sharedPath, channel)
    elseif sound == "voicepack" and PlaySoundFile then
        local voiceFile = self:GetVoicePackFile(spokenText, category)
        if voiceFile then
            played = TrySoundCall(PlaySoundFile, voiceFile, channel)
        end
    elseif sound == "custom" and PlaySoundFile then
        if customFile and customFile ~= "" then
            played = TrySoundCall(PlaySoundFile, customFile, channel)
        end
    elseif sound == "tts" and C_VoiceChat and C_VoiceChat.SpeakText then
        local voiceID = self:GetTtsVoiceID()
        local volume = math.max(0, math.min(100, SafeNumber(profile.tankAssistTtsVolume) or 100))
        if Enum and Enum.VoiceTtsDestination and Enum.VoiceTtsDestination.LocalPlayback then
            played = TrySoundCall(
                C_VoiceChat.SpeakText,
                voiceID,
                spokenText or "Taunt",
                Enum.VoiceTtsDestination.LocalPlayback,
                0,
                volume
            )
        else
            played = TrySoundCall(C_VoiceChat.SpeakText, voiceID, spokenText or "Taunt", 0, volume, true)
        end
    end

    if not played and PlaySound and SOUNDKIT then
        local soundKit
        if sound == "ready" then
            soundKit = SOUNDKIT.READY_CHECK
        elseif sound == "bell" then
            soundKit = SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
        else
            soundKit = SOUNDKIT.RAID_WARNING
        end
        if soundKit then
            played = TrySoundCall(PlaySound, soundKit, channel)
        end
    end

    if not played and PlaySoundFile then
        pcall(PlaySoundFile, "Sound\\Interface\\RaidWarning.ogg", channel)
    end
end

function TankAssist:GetVoicePackFile(spokenText, category)
    local text = SafeLower(spokenText)
    -- The bundled voice pack only contains tank-action words. Positioning cues
    -- must never accidentally fall through to the taunt sample.
    if category == "defensive"
        or (category == "movement" and not string.find(text, "soak", 1, true))
        or string.find(text, "defensive", 1, true)
        or string.find(text, "move", 1, true)
        or string.find(text, "jump", 1, true)
        or string.find(text, "run", 1, true)
        or string.find(text, "position", 1, true)
        or string.find(text, "aim", 1, true)
    then
        return nil
    end
    if string.find(text, "soak", 1, true) then
        return SOUND_ROOT .. "soak.mp3"
    end
    if string.find(text, "swap", 1, true) then
        return SOUND_ROOT .. "swap.mp3"
    end
    return SOUND_ROOT .. "taunt.mp3"
end

function TankAssist:PreviewWarningSound(category)
    category = self:GetWarningCategory(category)
    local spoken = category == "defensive" and "Defensive"
        or (category == "movement" and "Move" or "Taunt")
    self:PlayAlertSound(spoken, category)
end

function TankAssist:GetTtsVoiceID()
    local profile = RC.db and RC.db.profile or {}
    local configured = SafeNumber(profile.tankAssistTtsVoiceID)
    if configured then
        return configured
    end
    if C_TTSSettings and C_TTSSettings.GetVoiceOptionID then
        local ok, voiceID = pcall(C_TTSSettings.GetVoiceOptionID)
        if ok and SafeNumber(voiceID) then
            return SafeNumber(voiceID)
        end
    end
    return 0
end

local TEST_PREVIEW_DURATION = 6

function TankAssist:ShowTestAlert(title, detail, spokenText, category, rule)
    local function ShowNow()
        self:CreateAlertFrame()
        if not self.frame then
            return false
        end

        if self.hideTimer then
            self.hideTimer:Cancel()
            self.hideTimer = nil
        end

        local now = GetTime and GetTime() or 0
        local token = tostring(now) .. ":" .. tostring(math.random and math.random(100000, 999999) or 0)
        self._tankTestPreviewToken = token
        self._tankTestPreviewUntil = now + TEST_PREVIEW_DURATION

        local shown = self:Alert(
            title,
            detail,
            spokenText,
            "manual:preview:" .. token,
            spokenText ~= nil and spokenText ~= "",
            rule,
            category
        )
        if not shown then
            return false
        end

        -- Test buttons live inside the settings UI. That UI can perform a same-frame
        -- refresh/cleanup after the click, so test previews deliberately own their
        -- lifetime instead of sharing the short live-combat alert timer.
        if self.hideTimer then
            self.hideTimer:Cancel()
            self.hideTimer = nil
        end
        self.alertHUDTimerMode = "visual"
        self.alertHUDTimerCategory = category
        self.alertHUDCategory = category
        self.alertHUDTimerStart = now
        self.alertHUDTimerEnd = now + TEST_PREVIEW_DURATION
        self.alertHUDTimerDuration = TEST_PREVIEW_DURATION
        self.alertHUDTimelineEventID = nil
        if self.EnsureTankAssistHUDDriver then
            self:EnsureTankAssistHUDDriver()
        end
        if self.UpdateAlertHUDTimer then
            self:UpdateAlertHUDTimer()
        end

        if C_Timer and C_Timer.NewTimer then
            self.hideTimer = C_Timer.NewTimer(TEST_PREVIEW_DURATION, function()
                if self._tankTestPreviewToken ~= token then
                    return
                end
                self._tankTestPreviewToken = nil
                self._tankTestPreviewUntil = nil
                if self.alertHUDTimerMode == "visual" and self.StopAlertHUDTimer then
                    self:StopAlertHUDTimer()
                end
                if self.frame then
                    self.frame:Hide()
                end
            end)
        end
        return true
    end

    -- Defer one frame so the settings button/layout code finishes any cleanup
    -- before the preview is shown. This prevents the old one-frame flicker.
    if C_Timer and C_Timer.After then
        C_Timer.After(0, ShowNow)
        return true
    end
    return ShowNow()
end

function TankAssist:TestAlert(ruleKey)
    self:RefreshCoTank()
    local selected = ruleKey or (RC.db and RC.db.profile and RC.db.profile.tankAssistSelectedBoss)
    local rule = self:GetRuleByKey(selected)
    local title = self:GetDefaultAlertText(rule)
    local spokenText = title == "TAUNT NOW" and "Taunt" or (title == "SWAP OUT" and "Swap" or "Taunt")
    return self:ShowTestAlert(
        self:GetRuleAlertText(rule, title),
        "Test alert. Co-tank: " .. (self.coTankName or "auto not found"),
        spokenText,
        "taunt",
        rule
    )
end

function TankAssist:TestDefensiveAlert()
    return self:ShowTestAlert(
        "DEFENSIVE NOW",
        "Test tank-buster warning. Use active mitigation or a defensive.",
        "Defensive",
        "defensive",
        nil
    )
end

function TankAssist:TestMovementAlert()
    return self:ShowTestAlert(
        "MOVE BOSS TO SAFE POSITION",
        "Preview movement warning. Position the boss for the next mechanic.",
        "Move",
        "movement",
        nil
    )
end

function TankAssist:PreviewLayout(persistent)
    self:CreateAlertFrame()
    self:CreateStatusFrame()
    self:ApplyFrameSettings()
    if self.hideTimer then
        self.hideTimer:Cancel()
        self.hideTimer = nil
    end
    if self.frame then
        self:ApplyAlertIcon(self:GetRuleByKey(RC.db and RC.db.profile and RC.db.profile.tankAssistSelectedBoss))
        self.frame.title:SetText("TAUNT NOW")
        self.frame.detail:SetText("Layout preview: drag while tank frames are unlocked.")
        self.frame:Show()
    end
    if self.statusFrame then
        self.statusFrame.name:SetText("Co-tank: Preview")
        self.statusFrame.target:SetText("TANKING")
        self.statusFrame.target:SetTextColor(1, 0.72, 0.2, 1)
        self.statusFrame.detail:SetText("Boss stacks: 2")
        self.statusFrame:Show()
    end
    if self.layoutPreviewTimer then
        self.layoutPreviewTimer:Cancel()
    end
    if not persistent and C_Timer and C_Timer.NewTimer then
        self.layoutPreviewTimer = C_Timer.NewTimer(15, function()
            self.layoutPreviewTimer = nil
            if self.frame then
                self.frame:Hide()
            end
            if self.activeEncounter then
                self:RefreshStatus()
            elseif self.statusFrame then
                self.statusFrame:Hide()
            end
        end)
    end
end

function TankAssist:BeginLayoutMode()
    self._layoutModePreviewActive = self.activeEncounter == nil
    if self._layoutModePreviewActive then
        self:PreviewLayout(true)
    else
        self:ApplyFrameSettings()
        self:RefreshStatus()
    end
end

function TankAssist:EndLayoutMode()
    if self.layoutPreviewTimer then
        self.layoutPreviewTimer:Cancel()
        self.layoutPreviewTimer = nil
    end
    if self._layoutModePreviewActive then
        if self.frame then
            self.frame:Hide()
        end
        if self.activeEncounter then
            self:RefreshStatus()
        elseif self.statusFrame then
            self.statusFrame:Hide()
        end
    else
        self:ApplyFrameSettings()
        self:RefreshStatus()
    end
    self._layoutModePreviewActive = nil
end

function TankAssist:PrintActiveRule()
    self:RefreshCoTank()
    local rule = self.activeRule
    if rule then
        RC:Print("Tank Assist: " .. rule.raid .. " / " .. rule.name .. " - " .. rule.note)
    else
        RC:Print("Tank Assist: no supported boss rule active. Co-tank: " .. (self.coTankName or "not found"))
    end
end
