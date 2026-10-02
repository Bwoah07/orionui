-- Hearthstone toys the top bar can pick at random (CLAUDE.md §7.12: authored by us; item IDs
-- are game facts). Only toys the player owns ever show up, so a wrong or missing ID just
-- doesn't appear. Names come from the game. IDs from memory (2026-09-30), not yet checked in
-- game: /oui check hearthstones lists which ones the game knows.
local _, ns = ...

ns.Data.HEARTHSTONE_ITEM = 6948 -- the plain Hearthstone (an item, not a toy)

ns.Data.HearthstoneToys = {
    54452,  -- Ethereal Portal
    64488,  -- The Innkeeper's Daughter
    93672,  -- Dark Portal
    142542, -- Tome of Town Portal
    162973, -- Greatfather Winter's Hearthstone
    163045, -- Headless Horseman's Hearthstone
    165669, -- Lunar Elder's Hearthstone
    165670, -- Peddlefeet's Lovely Hearthstone
    165802, -- Noble Gardener's Hearthstone
    166746, -- Fire Eater's Hearthstone
    166747, -- Brewfest Reveler's Hearthstone
    168907, -- Holographic Digitalization Hearthstone
    172179, -- Eternal Traveler's Hearthstone
    180290, -- Night Fae Hearthstone
    182773, -- Necrolord Hearthstone
    183716, -- Venthyr Sinstone
    184353, -- Kyrian Hearthstone
    188952, -- Dominated Hearthstone
    190196, -- Enlightened Hearthstone
    190237, -- Broker Translocation Matrix
    193588, -- Timewalker's Hearthstone
    200630, -- Ohn'ir Windsage's Hearthstone
    206195, -- Path of the Naaru
    208704, -- Deepdweller's Earthen Hearthstone
    209035, -- Hearthstone of the Flame
    210455, -- Draenic Hologem
    212337, -- Stone of the Hearth
    228940, -- Notorious Thread's Hearthstone
    235016, -- Redeployment Module
    236687, -- Explosive Hearthstone
}

-- Other teleports with their own cooldown, offered as optional fixed buttons.
ns.Data.TeleportToys = {
    { key = "dalaran",  item = 140192 }, -- Dalaran Hearthstone
    { key = "garrison", item = 110560 }, -- Garrison Hearthstone
    { key = "arcantina", item = 253629 }, -- Personal Key to the Arcantina (toy)
}
