-- CDMMirror: finding a buff's Cooldown Manager frame by spell and copying its stack text
-- without reading it (the in-combat path of the Blood DK Bone Shield counter).
local mock = WowMock

local FILES = {
    "OrionUI/Core/Init.lua", "OrionUI/Locales/enUS.lua", "OrionUI/Core/Util.lua",
    "OrionUI/Core/Log.lua", "OrionUI/Core/SafeCall.lua", "OrionUI/Core/Secret.lua",
    "OrionUI/Core/Events.lua", "OrionUI/Classes/Framework/CDMMirror.lua",
}

local function Child(cooldownID, active, stackText)
    local fs = { text = stackText }
    function fs:GetText() return self.text end
    return {
        cooldownID = cooldownID,
        auraInstanceID = active and mock.SECRET or nil,
        Applications = { Applications = fs },
    }
end

describe("CDMMirror", function()
    local ns
    before_each(function()
        mock.frames = {}
        ns = mock.LoadCore(FILES)
        _G.C_CooldownViewer = {
            GetCooldownViewerCooldownInfo = function(id)
                if id == 9039 then return { spellID = 195181, linkedSpellIDs = {} } end
                if id == 9126 then return { spellID = 48792, linkedSpellIDs = { 999 } } end
                return { linkedSpellIDs = {} }
            end,
        }
        local children = { Child(9126, false, nil), Child(mock.SECRET, true, mock.SECRET), Child(9039, true, mock.SECRET) }
        _G.BuffIconCooldownViewer = { GetChildren = function() return unpack(children) end }
        _G.BuffBarCooldownViewer = nil
    end)

    it("finds the frame by spell, skipping secret cooldown IDs", function()
        local child = ns.CDMMirror:Find({ [195181] = true })
        assert.are.equal(9039, child.cooldownID)
        assert.are.equal(9126, ns.CDMMirror:Find({ [999] = true }).cooldownID) -- linked spell
        assert.is_nil(ns.CDMMirror:Find({ [1] = true }))
    end)

    it("knows whether the buff is up without comparing secrets", function()
        assert.is_true(ns.CDMMirror:IsActive(ns.CDMMirror:Find({ [195181] = true })))
        assert.is_false(ns.CDMMirror:IsActive(ns.CDMMirror:Find({ [48792] = true })))
    end)

    it("passes the secret stack text straight to the target", function()
        local got
        local target = { SetText = function(_, t) got = t end }
        assert.is_true(ns.CDMMirror:CopyStacks(ns.CDMMirror:Find({ [195181] = true }), target))
        assert.is_true(rawequal(got, mock.SECRET))
    end)
end)
