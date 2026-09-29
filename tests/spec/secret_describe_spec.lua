-- ns.Describe must never turn a secret into text (CLAUDE.md §4). Loads only the pure
-- helper part of OrionUI_Dev/Core.lua by stubbing the frame API it touches at load.
local mock = WowMock

describe("OrionUI_Dev Describe", function()
    local ns
    setup(function()
        _G.CreateFrame = function()
            return { RegisterEvent = function() end, SetScript = function() end }
        end
        ns = mock.LoadAddonFile("OrionUI_Dev/Core.lua", "OrionUI_Dev", {})
    end)

    it("labels secrets without stringifying them", function()
        assert.are.equal("<secret table>", ns.Describe(mock.SECRET))
    end)

    it("describes plain values", function()
        assert.are.equal("nil", ns.Describe(nil))
        assert.are.equal("5", ns.Describe(5))
        assert.are.equal("true", ns.Describe(true))
        assert.are.equal('"x"', ns.Describe("x"))
    end)

    it("marks secret struct fields and keeps readable ones", function()
        local cd = { startTime = mock.SECRET, duration = mock.SECRET, isActive = true, isEnabled = true }
        local text = ns.DescribeFields(cd, { "startTime", "duration", "isActive", "isEnabled" })
        assert.truthy(text:find("startTime=<secret table>", 1, true))
        assert.truthy(text:find("isActive=true", 1, true))
        assert.are.equal("secret: startTime,duration", ns.SecretSummary(cd, { "startTime", "duration", "isActive", "isEnabled" }))
    end)
end)
