-- Wire format for profile strings (CLAUDE.md §10.3):
--   "!OUI:<kind>:<version>!" .. printable(deflate9(LibSerialize(payload)))
-- kind: L = layout profile, R = reminders profile, C = single custom reminder/preset,
--       S = one Raid Split group layout.
-- The version is the WIRE format version; decoders dispatch on it.
local _, ns = ...

local Serialize = { WIRE_VERSION = 1, KINDS = { L = "layout", R = "reminders", C = "custom", S = "raidsplit" } }
ns.Serialize = Serialize

local MAX_INPUT = 2 * 1024 * 1024         -- pasted string
local MAX_DECOMPRESSED = 4 * 1024 * 1024  -- guards against decompression bombs

-- Libraries resolve lazily so tests can inject them.
function Serialize:Libs()
    if not self.libSerialize then
        self.libSerialize = LibStub and LibStub("LibSerialize", true)
        self.libDeflate = LibStub and LibStub("LibDeflate", true)
    end
    return self.libSerialize, self.libDeflate
end

function Serialize:Encode(kind, payload)
    assert(self.KINDS[kind], "unknown kind " .. tostring(kind))
    local LS, LD = self:Libs()
    if not (LS and LD) then return nil, "serialization libraries missing" end
    -- stable: same data gives the same string, so exports diff cleanly.
    local raw = LS:SerializeEx({ stable = true }, payload)
    local packed = LD:CompressDeflate(raw, { level = 9 })
    return ("!OUI:%s:%d!"):format(kind, self.WIRE_VERSION) .. LD:EncodeForPrint(packed)
end

-- -> ok, kind, payload  |  false, errorMessage
function Serialize:Decode(str)
    if type(str) ~= "string" then return false, "not text" end
    str = str:gsub("%s", "")
    if #str > MAX_INPUT then return false, "string is too large" end
    local kind, version, body = str:match("^!OUI:(%a):(%d+)!(.+)$")
    if not kind then return false, "not an " .. ns.NAME .. " string" end
    if not self.KINDS[kind] then return false, "unknown string type " .. kind end
    version = tonumber(version)
    if version ~= 1 then return false, "made by a newer version of " .. ns.NAME .. " (format " .. version .. ")" end

    local LS, LD = self:Libs()
    if not (LS and LD) then return false, "serialization libraries missing" end
    local packed = LD:DecodeForPrint(body)
    if not packed then return false, "string is damaged (decode)" end
    local raw = LD:DecompressDeflate(packed)
    if not raw then return false, "string is damaged (decompress)" end
    if #raw > MAX_DECOMPRESSED then return false, "string contents are too large" end
    local ok, payload = LS:Deserialize(raw)
    if not ok or type(payload) ~= "table" then return false, "string is damaged (data)" end
    return true, kind, payload
end
