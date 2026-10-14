local _, ns = ...
local RC = ns.RC or LibStub("AceAddon-3.0"):GetAddon("RaidControl")

RC.SettingsV2 = RC.SettingsV2 or {}
local V2 = RC.SettingsV2

V2.Tooltips = V2.Tooltips or {}
local Tooltips = V2.Tooltips

-- Hover help for settings rows, keyed by the row's English label. Only rows
-- whose label does not already say everything get an entry.
local DESCRIPTIONS = {
    -- Interface > General
    ["Show Top Bar and Dropdown"] = "Shows the RaidControl tab at the top of the screen and the dropdown panel it opens.",
    ["Hide Top Bar and Dropdown While Solo"] = "Hides the top tab and dropdown whenever you are not in a party or raid. They return as soon as you join a group.",
    ["Enable Action Strip"] = "Shows the compact bar of raid actions and markers. Its buttons are configured on the Action Strip tab.",
    ["Show Blizzard Raid Tools"] = "Shows Blizzard's own raid manager on the left edge of the screen. Changes made in combat apply when combat ends.",

    -- Interface > Dropdown and Action Strip
    ["Dropdown Marker Icons"] = "Shows the row of raid target icons in the dropdown panel.",
    ["Show Marker Icons"] = "Shows the raid target icons on the action strip.",
    ["Enable Target Marker Clicks"] = "Clicking a marker icon puts that marker on your current target.",
    ["Enable World Marker Modifier Clicks"] = "Holding the world marker modifier while clicking a marker icon places the matching world marker at your cursor. Requires a group.",
    ["World Marker Modifier"] = "The key to hold while clicking a marker icon to place a world marker instead of a target marker. Also used by the Cycle Marker key binding.",
    ["Show Role Counts in Dropdown"] = "Shows how many tanks, healers and damage dealers are in your group under the dropdown actions.",
    ["Show on Mouseover Only"] = "Fades the action strip out until you move the mouse over it.",
    ["Layout"] = "How the action strip arranges its buttons and markers.",
    ["Marker Position"] = "Whether the marker icons come before or after the action buttons.",

    -- Screenshots
    ["Confirm High Quality Screenshot"] = "Asks before taking a screenshot, because the capture briefly raises graphics settings and hides the interface.",
    ["Apply Max Graphics"] = "Raises graphics settings to their maximum for the capture, then restores your own settings afterwards.",
    ["Hide UI During Screenshot"] = "Hides the whole interface for the capture so only the game world is saved.",
    ["Screenshot Format"] = "JPG files are small. TGA files are uncompressed and much larger.",
    ["Screenshot Quality"] = "JPG compression quality, from 1 (smallest file) to 10 (best image).",
    ["Render Scale"] = "Render scale used for the capture, in percent. Values above 100 supersample the image for sharper edges.",
    ["Screenshot Delay"] = "How long to wait after applying the capture settings before taking the picture, in tenths of a second. 10 is one second.",
    ["Screenshot Size Override"] = "Custom capture size, written as width x height, for example 3840x2160.",

    -- Look & Feel
    ["Use Player Class Color"] = "Uses your character's class color as the accent color instead of the custom accent.",
    ["Custom Accent Color"] = "Accent color for highlights, selected tabs and values. Ignored while Use Player Class Color is on.",
    ["Global Font"] = "Font used across RaidControl. Fonts registered by other addons through SharedMedia are listed too.",
    ["Menu Alpha (%)"] = "Opacity of the top tab and dropdown panel.",
    ["Top Tab Scale (%)"] = "Size of the RaidControl tab at the top of the screen.",
    ["Dropdown Panel Scale (%)"] = "Size of the dropdown panel opened from the top tab.",
    ["Settings Window Scale (%)"] = "Size of this settings window.",

    -- Tank
    ["Enable Tank Assist"] = "Turns on personal taunt, defensive and movement instructions for supported encounters.",
    ["Only Run While Tanking"] = "Only gives instructions while your current specialization is a tank.",
    ["Raid Boss Encounters Only"] = "Only gives instructions while a supported raid boss is engaged.",
    ["Mythic+ Tank-Buster Warnings"] = "Warns about tank busters in Mythic+ dungeons while you are the tank.",
    ["Lock Tank Frames"] = "Locks the warning and timer bar frames in place. Unlock to drag them.",
    ["Co-Tank Name Override"] = "Name of the player to treat as your co-tank. Leave blank to use the other tank in your group.",

    -- Raid Tools
    ["Enable Raid Demo"] = "Plays an animated preview scene for trying out the raid tools. It is visual only and never sends anything to your group.",
    ["Enable Keystone Tracker"] = "Shares and collects Mythic+ keystones with group members who also use RaidControl.",
    ["Enable Buff Analyzer"] = "Enables the Run Roster Scan button, which lists raid buffs and utility (such as Bloodlust and Battle Res) that nobody in your group brings.",
    ["Who Pulled"] = "Reports which player started combat when a boss is pulled.",
    ["Durability Sync"] = "Shares your lowest gear durability with group members who use RaidControl.",
    ["Timer Source"] = "Which addon or system starts the pull countdown.",
    ["Auto-load Encounter Note"] = "Loads the saved Boss Note for the boss you are fighting when the encounter starts.",
    ["Merge Personal NSRT Note"] = "Adds reminders from your personal NSRT note to the shared encounter note.",
    ["Show All Shared Assignments"] = "Shows every assignment in the shared note, not only the ones meant for you.",
    ["Share NSRT on Ready Check"] = "When you lead a raid, sends the active shared note to the raid each time you start a ready check.",
    ["Note-driven Nameplate Cues"] = "Marks enemy nameplates when the note assigns you an interrupt on them.",
    ["Announce Slackers"] = "When a ready check you started ends, posts the players who were not ready to group chat.",
    ["Whisper Slackers"] = "Used by the Scan Consumables button below: whispers each player the food or flask they are missing.",
    ["Report to Chat"] = "Used by the Scan Consumables button below: posts the missing food and flask lists to group chat instead of only your chat window.",
    ["Use Custom Ready Check UI"] = "Replaces Blizzard's ready check window with the RaidControl ready check tracker.",
    ["Issues View by Default"] = "Opens the ready check results with players who have a problem highlighted. Everyone stays on the list.",
    ["Enable Missing-Consumable Whisper Button"] = "Adds a button that whispers each player the consumables they are missing.",
    ["Result Auto-Close"] = "Seconds the ready check results stay open after the check finishes. 0 keeps them open.",
    ["Low Durability Warning (%)"] = "Players at or below this durability are flagged during ready checks.",

    -- Automation
    ["Keyword"] = "Whisper text that triggers an automatic invite.",
    ["Allow"] = "Who may be invited by whispering the keyword.",
    ["Auto-Convert Keyword Invites to Raid"] = "After a keyword invite, converts your party to a raid. You must be the group leader.",
    ["Promote guild members at rank (and above)"] = "Guild members at this rank or higher are given raid assist automatically.",
    ["Also promote by name (comma-separated)"] = "Extra players to give raid assist, separated by commas. A name without a realm matches any realm.",
    ["Enable Combat Log Prompts"] = "Offers to start combat logging when you enter the instance types selected below.",
    ["Ask Before Starting"] = "Asks each time before logging starts. Off starts logging without asking.",
    ["Use Guild Funds"] = "Pays for repairs from the guild bank when you have enough withdrawal allowance. Otherwise your own gold is used.",
    ["Auto-Sell Junk (Greys)"] = "Sells poor quality (grey) items when you open a merchant.",
}

local index

-- Keys and text go through the locale table when one exists, so translated
-- labels still find their help text.
local function Localize(text)
    local L = RC.L
    return L and L[text] or text
end

local function BuildIndex()
    index = {}
    for label, description in pairs(DESCRIPTIONS) do
        index[Localize(label)] = Localize(description)
    end
end

function Tooltips:Get(label)
    if type(label) ~= "string" or label == "" then
        return nil
    end
    if not index then
        BuildIndex()
    end
    return index[label]
end

function Tooltips:Show(owner, title, text)
    if not owner or not GameTooltip or (not title and not text) then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 4)
    if title then
        GameTooltip:SetText(title, 1, 1, 1, 1, true)
    end
    if text then
        if title then
            GameTooltip:AddLine(text, 1, 0.82, 0, true)
        else
            GameTooltip:SetText(text, 1, 0.82, 0, 1, true)
        end
    end
    GameTooltip:Show()
end

function Tooltips:Hide(owner)
    if GameTooltip and GameTooltip:IsOwned(owner) then
        GameTooltip:Hide()
    end
end
