-- RaidControl settings: one AceConfig panel, opened with /rc, a right-click on the launcher tab,
-- the Escape menu button, or Options > AddOns > RaidControl. Rows read and write RC.db.profile
-- directly; every change re-applies the launcher, menu and action strip.
local _, ns = ...
local RC = ns.RC
local L = RC.L

local Settings = RC:NewModule("Settings")
local APP = "RaidControl"

local MODIFIERS = { SHIFT = L["Shift"], CTRL = L["Ctrl"], ALT = L["Alt"] }
local MODIFIER_ORDER = { "SHIFT", "CTRL", "ALT" }
local PULL_ADDONS = { auto = L["Automatic"], bigwigs = "BigWigs", dbm = "DBM", ert = "MRT", none = L["Blizzard only"] }
local PULL_ADDON_ORDER = { "auto", "bigwigs", "dbm", "ert", "none" }

local function Profile() return RC.db.profile end
local function Default(key) return RC.db.defaults.profile[key] end

local function Call(obj, fn, ...)
    if obj and type(obj[fn]) == "function" then
        local ok, err = pcall(obj[fn], obj, ...)
        if not ok then geterrorhandler()(err) end
    end
end

-- Re-applies everything the panel can change (scales, visibility, buttons, theme).
local function Changed()
    local p = Profile()
    local legacy = p.launcherScale or p.scale or 1
    Call(RC, "ApplyTheme", p.theme or "Starforge", false)
    Call(RC, "ApplyTopBarScale", p.topBarScale or legacy)
    Call(RC, "ApplyMenuScale", p.menuScale or legacy)
    Call(RC, "ApplyInterfaceVisibility")
    Call(RC, "RefreshLayout")
    Call(RC, "RefreshTheme", false)
    Call(RC, "UpdateCycleKeybinds")
    local control = RC:GetModule("Control", true)
    Call(control, "RefreshButtonVisibility")
    Call(control, "RefreshModifierAttributes")
    Call(RC:GetModule("Markers", true), "RefreshModifierAttributes")
    local strip = RC:GetModule("ActionStrip", true)
    Call(strip, "RefreshButtonVisibility")
    Call(strip, "UpdateVisibility")
    Call(strip, "UpdateScale", p.actionStripScale or 1)
    Call(strip, "RefreshModifierAttributes")
end

local function Value(key)
    local v = Profile()[key]
    if v == nil then v = Default(key) end
    return v
end

-- Row builders. `invert` shows the opposite of a "hide..." setting.
local order = 0
local function Next() order = order + 1 return order end

local function Toggle(key, name, opts)
    opts = opts or {}
    return {
        type = "toggle", name = name, desc = opts.desc, order = Next(), width = "full",
        get = function()
            if opts.invert then return not Value(key) end
            return Value(key) and true or false
        end,
        set = function(_, v)
            if opts.invert then v = not v end
            Profile()[key] = v
            Changed()
        end,
    }
end

local function Range(key, name, min, max, step)
    return {
        type = "range", name = name, order = Next(), min = min, max = max, step = step, width = "double",
        get = function() return tonumber(Value(key)) or min end,
        set = function(_, v) Profile()[key] = v; Changed() end,
    }
end

local function Select(key, name, values, sorting)
    return {
        type = "select", name = name, order = Next(), values = values, sorting = sorting,
        get = function() return Value(key) end,
        set = function(_, v) Profile()[key] = v; Changed() end,
    }
end

local function Header(name) return { type = "header", name = name, order = Next() } end

local function Group(name, args)
    return { type = "group", name = name, order = Next(), args = args }
end

local function ThemeValues()
    local values = {}
    for _, key in ipairs(RC.ThemeOrder or {}) do
        local def = RC.ThemeDefinitions and RC.ThemeDefinitions[key]
        values[key] = def and def.label or key
    end
    return values
end

local function RunSlash(args)
    local handler = SlashCmdList and SlashCmdList["ACECONSOLE_RC"]
    if handler then handler(args) end
end

local function BuildOptions()
    order = 0
    return {
        type = "group", name = "RaidControl", childGroups = "tab",
        args = {
            launcher = Group(L["Launcher"], {
                h1 = Header(L["Launcher"]),
                showTopBar = Toggle("hideTopBar", L["Show the launcher bar"], { invert = true }),
                solo = Toggle("hideLauncherWhenSolo", L["Hide it when I'm not in a group"]),
                blizzard = Toggle("hideBlizzardRaidControl", L["Hide Blizzard's raid manager"]),
                topBarScale = Range("topBarScale", L["Launcher size"], 0.5, 2, 0.05),
                menuScale = Range("menuScale", L["Menu size"], 0.5, 2, 0.05),
                h2 = Header(L["Menu buttons"]),
                ready = Toggle("showReadyButton", L["Ready check"]),
                pull = Toggle("showPullButton", L["Pull timer"]),
                convert = Toggle("showConvertButton", L["Convert party / raid"]),
                difficulty = Toggle("showDifficultyButton", L["Difficulty"]),
                invite = Toggle("showInviteButton", L["Guild invite"]),
                clear = Toggle("showClearButton", L["Clear markers"]),
                disband = Toggle("showDisbandButton", L["Disband group"]),
                screenshot = Toggle("showScreenshotButton", L["Screenshot"]),
                roles = Toggle("hideRoles", L["Show tank / healer / DPS counts"], { invert = true }),
                h3 = Header(L["Pull timer"]),
                pullLength = Range("pullTimerDuration", L["Pull timer length (seconds)"], 3, 30, 1),
                pullAddon = Select("pullTimerAddon", L["Send the pull timer through"], PULL_ADDONS, PULL_ADDON_ORDER),
            }),
            markers = Group(L["Markers"], {
                h1 = Header(L["Markers"]),
                show = Toggle("hideMarkers", L["Show marker buttons"], { invert = true }),
                dropdown = Toggle("showDropdownMarkers", L["Markers in the drop-down menu"]),
                target = Toggle("enableTargetMarkers", L["Click marks your target"]),
                world = Toggle("enableWorldMarkers", L["Modifier-click places a world marker"]),
                worldMod = Select("worldMarkerModifier", L["World marker modifier"], MODIFIERS, MODIFIER_ORDER),
                cycleMod = Select("cycleMarkerModifier", L["Cycle keybind modifier"], MODIFIERS, MODIFIER_ORDER),
            }),
            strip = Group(L["Action strip"], {
                desc = { type = "description", order = Next(), fontSize = "medium",
                    name = L["A slim row of raid buttons you can place anywhere. Move it with /rc layout."] },
                h1 = Header(L["Action strip"]),
                show = Toggle("showActionStrip", L["Show the action strip"]),
                scale = Range("actionStripScale", L["Size"], 0.5, 2, 0.05),
                markers = Toggle("showActionStripMarkers", L["Include marker buttons"]),
                mouseover = Toggle("actionStripMouseover", L["Only show it on mouseover"]),
                h2 = Header(L["Buttons"]),
                ready = Toggle("actionStripShowReady", L["Ready check"]),
                pull = Toggle("actionStripShowPull", L["Pull timer"]),
                convert = Toggle("actionStripShowConvert", L["Convert party / raid"]),
                difficulty = Toggle("actionStripShowDifficulty", L["Difficulty"]),
                invite = Toggle("actionStripShowInvite", L["Guild invite"]),
                clearTarget = Toggle("actionStripShowClearTarget", L["Clear target markers"]),
                clearWorld = Toggle("actionStripShowClearWorld", L["Clear world markers"]),
                disband = Toggle("actionStripShowDisband", L["Disband group"]),
                screenshot = Toggle("actionStripShowScreenshot", L["Screenshot"]),
            }),
            look = Group(L["Look"], {
                h1 = Header(L["Look"]),
                theme = Select("theme", L["Theme"], ThemeValues),
                classColor = Toggle("useClassColor", L["Use my class colour as the accent"]),
                accent = {
                    type = "color", name = L["Accent colour"], order = Next(),
                    disabled = function() return Value("useClassColor") end,
                    get = function()
                        local c = Value("accentColor") or {}
                        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
                    end,
                    set = function(_, r, g, b, a)
                        Profile().accentColor = { r = r, g = g, b = b, a = a or 1 }
                        Changed()
                    end,
                },
                h2 = Header(L["Position"]),
                layout = { type = "execute", name = L["Move frames"], order = Next(),
                    desc = L["Toggle Edit Mode for every RaidControl frame"],
                    func = function() RunSlash("layout") end },
                reset = { type = "execute", name = L["Reset launcher"], order = Next(),
                    desc = L["Move the launcher back to the centre of the screen"],
                    func = function() RunSlash("reset") end },
                reload = { type = "execute", name = L["Reload UI"], order = Next(),
                    desc = L["Most changes show right away; a few need a /reload."], func = ReloadUI },
            }),
        },
    }
end

function Settings:OnInitialize()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(APP, BuildOptions)
    local dialog = LibStub("AceConfigDialog-3.0")
    dialog:SetDefaultSize(APP, 560, 600)
    self.blizzardPanel = dialog:AddToBlizOptions(APP, "RaidControl")
end

function Settings:Open()
    if InCombatLockdown and InCombatLockdown() then
        RC:Print(L["RaidControl settings are unavailable during combat."])
        return false
    end
    LibStub("AceConfigDialog-3.0"):Open(APP)
    return true
end

function Settings:Toggle()
    local dialog = LibStub("AceConfigDialog-3.0")
    if dialog.OpenFrames and dialog.OpenFrames[APP] then
        dialog:Close(APP)
        return false
    end
    return self:Open()
end

-- Called by LayoutMode when edit mode turns on or off, and after profile changes.
function Settings:RefreshLayoutModeControls()
    LibStub("AceConfigRegistry-3.0"):NotifyChange(APP)
end
function Settings:SelectTab() end
function Settings:CreateWindow() end
